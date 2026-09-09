#!/usr/bin/env python3
"""Compatibility executor for UN1CA SMALI_PATCH operations.

Ports the exact semantics of UN1CA's own scripts/utils/smali_utils.sh
(remove/replace/replaceall/return/null/strip) so a stock UN1CA module's
inline SMALI_PATCH calls behave the same way against a ReCoreUI-decoded
smali tree as they do in UN1CA's own build.
"""
from __future__ import annotations
import argparse, re, sys
from pathlib import Path

_CONST_STRING_RE = re.compile(r'^\s*const-string(?:/jumbo)?\s')


def method_ranges(text: str, method: str):
    lines = text.splitlines()
    hits = []
    for i, l in enumerate(lines):
        if l.lstrip().startswith('.method') and method in l:
            end = None
            for j in range(i + 1, len(lines)):
                if lines[j].strip() == '.end method':
                    end = j
                    break
            if end is None:
                raise ValueError(f"unterminated method: {method}")
            hits.append((i, end))
    if len(hits) != 1:
        raise ValueError(f"expected exactly one method match for {method}, found {len(hits)}")
    return lines, hits[0]


def write(path: Path, lines):
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def do_replace(lines, s, e, body, value, replacement):
    old = value
    new = replacement.replace('\\n', '\n')
    is_multiline = '\n' in new
    joined = '\n'.join(body)

    # Idempotency: recognise the target already being in the desired state
    # and succeed without touching the file, instead of either silently
    # re-inserting the block again (multiline case) or hard-failing on a
    # second run (single-line case) - both were possible before this fix.
    if is_multiline:
        if new in joined:
            return None  # no change needed
    else:
        for line in body:
            stripped = line.strip()
            if stripped == new:
                return None
            if new and _CONST_STRING_RE.match(line) and f'"{new}"' in line:
                return None

    changed = False
    out = []
    for line in body:
        stripped = line.strip()
        if is_multiline and old and (not changed) and old in line:
            # A multiline replacement is caller-supplied, already-formatted
            # text (UN1CA modules embed their own leading whitespace, as
            # AOSP's own customize.sh scripts do) - inserted verbatim, same
            # as UN1CA's own awk-based engine does. Auto-prepending the
            # matched line's indent on top of that (as originally written
            # here) double-indents every inserted line, which then breaks
            # the idempotency check above on a second run since the freshly
            # computed `new` no longer byte-matches what's on disk.
            out.extend(new.splitlines())
            changed = True
        elif (not is_multiline) and stripped == old:
            indent = line[:len(line) - len(line.lstrip())]
            out.append(indent + new if new else indent)
            changed = True
        elif (not is_multiline) and old and _CONST_STRING_RE.match(line) and f'"{old}"' in line:
            out.append(line.replace(f'"{old}"', f'"{new}"', 1))
            changed = True
        else:
            out.append(line)
    if not changed:
        raise SystemExit(f'replace pattern not found: {old}')
    lines[s + 1:e] = out
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('operation', choices=['remove', 'replace', 'replaceall', 'return', 'null', 'strip'])
    ap.add_argument('file')
    ap.add_argument('method', nargs='?')
    ap.add_argument('value', nargs='?')
    ap.add_argument('replacement', nargs='?')
    a = ap.parse_args()
    p = Path(a.file)
    if not p.is_file():
        raise SystemExit(f"smali not found: {p}")
    text = p.read_text(encoding='utf-8')
    op = a.operation

    if op == 'remove':
        p.unlink()
        return 0

    if op == 'replaceall':
        if a.value is None or a.replacement is None:
            raise SystemExit('replaceall requires value and replacement')
        if a.value not in text:
            # Idempotency: if the search text is gone because the
            # replacement was already applied, succeed silently. If neither
            # is present, this is a real mismatch and must be reported, not
            # swallowed - a silent no-op here would hide the exact class of
            # baseline-mismatch bug this engine exists to catch.
            if a.replacement and a.replacement in text:
                return 0
            raise SystemExit(f'replaceall pattern not found: {a.value}')
        p.write_text(text.replace(a.value, a.replacement), encoding='utf-8')
        return 0

    if not a.method:
        raise SystemExit('method required')
    lines, (s, e) = method_ranges(text, a.method)
    body = lines[s + 1:e]

    if op == 'replace':
        if a.value is None or a.replacement is None:
            raise SystemExit('replace requires value and replacement')
        result = do_replace(lines, s, e, body, a.value, a.replacement)
        if result is None:
            return 0  # already applied, nothing to write
        lines = result
    elif op == 'null':
        ret = a.method.split(')', 1)[1] if ')' in a.method else ''
        if ret != 'V':
            raise SystemExit('null is only valid on a void method')
        lines[s + 1:e] = ['    .locals 0', '    ', '    return-void']
    elif op == 'return':
        if a.value is None:
            raise SystemExit('return requires value')
        sig = a.method
        ret = sig.split(')', 1)[1] if ')' in sig else ''
        static = ' static ' in lines[s]
        reg = 'v0' if static and '()' in sig else 'p0'
        if ret == 'V':
            raise SystemExit('cannot return a value from void method')
        val = a.value
        if ret == 'Ljava/lang/String;':
            val = f'"{val}"'
            ins = f'const-string {reg}, {val}'
            retins = f'return-object {reg}'
            loc = '.locals 0'
        elif ret == 'Z':
            if val not in ('true', 'false', '0x0', '0x1', '0', '1'):
                raise SystemExit('invalid boolean return')
            val = {'true': '0x1', 'false': '0x0', '0': '0x0', '1': '0x1'}.get(val, val)
            ins = f'const/4 {reg}, {val}'
            retins = f'return {reg}'
            loc = '.locals 1' if reg == 'v0' else '.locals 0'
        elif re.fullmatch(r'\[*[BCSIF]', ret):
            # Non-wide primitives (byte/char/short/int/float, incl. arrays of
            # them per UN1CA's own [ZBCSIJFD] class). Float support is
            # limited exactly the way UN1CA's own bash implementation is:
            # the value is loaded as a raw 32-bit pattern via const/4 or
            # const/16, so a genuine float must be supplied pre-encoded as
            # its hex bit pattern (or a small whole number).
            try:
                n = int(val, 0)
            except ValueError:
                raise SystemExit('invalid integer return')
            ins = f'const/4 {reg}, 0x{n:x}' if -8 < n < 8 else f'const/16 {reg}, 0x{n:x}'
            retins = f'return {reg}'
            loc = '.locals 1' if reg == 'v0' else '.locals 0'
        elif ret in ('J', 'D'):
            # Wide primitives (long/double). Same bit-pattern caveat as
            # above applies to double.
            ins = f'const-wide/16 {reg}, {val}'
            retins = f'return-wide {reg}'
            loc = '.locals 1' if reg == 'v0' else '.locals 0'
        else:
            if val not in ('null', '0x0', '0'):
                raise SystemExit('invalid object return')
            ins = f'const/4 {reg}, 0x0'
            retins = f'return-object {reg}'
            loc = '.locals 1' if reg == 'v0' else '.locals 0'
        lines[s + 1:e] = [f'    {loc}', '    ', f'    {ins}', '    ', f'    {retins}']
    elif op == 'strip':
        del lines[s:e + 1]

    write(p, lines)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as e:
        print(f'un1ca_smali_compat.py: ERROR: {e}', file=sys.stderr)
        raise SystemExit(1)
