#!/usr/bin/env python3
"""
ReCoreUI SmaliPatcher
=====================

Applies ReCoreUI .smalipatch files to an apktool/baksmali work directory.

Format:
    AUTHOR <name>

    FILE <relative/path/to/file.smali>

    REPLACE <exact .method declaration>
        <complete replacement body>
    END

    FIND_REPLACE "old" "new"

    PATCH [optional exact method declaration]
        <context line>
      - <line to remove>
      + <line to add>
        <context line>
    END

Comments beginning with # or // are ignored.

PATCH matching is ordered and exact after conservative whitespace normalization;
the replacement preserves the patch's context/addition lines and removes only
the exact old sequence represented by the hunk. This is intentionally stricter
than the old positional deletion logic so a failed hunk cannot silently corrupt
a smali file.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import List, Tuple, Optional, Dict, Any


class Colors:
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    RESET = "\033[0m"

    @staticmethod
    def init() -> None:
        if os.name == "nt":
            try:
                import colorama  # type: ignore
                colorama.init()
            except ImportError:
                pass


def log(msg: str, color: str = "", quiet: bool = False) -> None:
    if not quiet:
        print(f"{color}{msg}{Colors.RESET if color else ''}")


def log_error(msg: str) -> None:
    print(f"{Colors.RED}{msg}{Colors.RESET}", file=sys.stderr)


def normalize_line(line: str) -> str:
    """
    Normalize only formatting noise that should not affect smali matching.

    We deliberately do not normalize punctuation, labels, register names, or
    opcodes. Tabs/spaces at the edges and runs of internal whitespace are the
    only ignored differences.
    """
    return re.sub(r"[ \t]+", " ", line.strip())


def parse_quoted_args(text: str) -> List[str]:
    """Parse double-quoted arguments; support \\" and \\\\ without mangling other backslashes."""
    args: List[str] = []
    current: List[str] = []
    in_quote = False
    escape = False

    for c in text:
        if not in_quote:
            if c == '"':
                in_quote = True
            continue
        if escape:
            if c in ('"', '\\'):
                current.append(c)
            else:
                # Preserve unknown escapes literally.
                current.append('\\')
                current.append(c)
            escape = False
            continue
        if c == '\\':
            escape = True
            continue
        if c == '"':
            args.append("".join(current))
            current = []
            in_quote = False
            continue
        current.append(c)

    if in_quote:
        raise ValueError("unterminated quoted argument")
    return args


def read_content_block(lines: List[str], start: int) -> Tuple[List[str], int]:
    """
    Read until END or the start of another action/FILE.

    A content line that begins with '+ ' / '- ' is still content and is never
    treated as an action.
    """
    content: List[str] = []
    i = start
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped == "END":
            return content, i + 1
        if stripped.startswith("FILE "):
            return content, i
        if stripped.startswith("REPLACE ") or stripped.startswith("PATCH") or stripped.startswith("FIND_REPLACE "):
            return content, i
        content.append(lines[i].rstrip("\r\n"))
        i += 1
    return content, i


def parse_smalipatch(lines: List[str], quiet: bool = False) -> List[Dict[str, Any]]:
    patches: List[Dict[str, Any]] = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()

        if not line or line.startswith("#") or line.startswith("//"):
            i += 1
            continue

        if line.startswith("AUTHOR "):
            log(f"  Author: {line[7:].strip()}", Colors.BLUE, quiet)
            i += 1
            continue

        if line.startswith("FILE "):
            file_path = line[5:].strip()
            if not file_path or os.path.isabs(file_path) or ".." in file_path.split("/"):
                raise ValueError(f"Invalid FILE path: {file_path!r}")

            patch: Dict[str, Any] = {
                "type": "FILE",
                "file_path": file_path,
                "actions": [],
            }
            i += 1

            while i < len(lines):
                line = lines[i].strip()

                if not line or line.startswith("#") or line.startswith("//"):
                    i += 1
                    continue

                if line == "END":
                    i += 1
                    break

                if line.startswith("FILE "):
                    # Missing END is a syntax error rather than silently
                    # changing target file.
                    raise ValueError(
                        f"FILE {file_path}: missing END before next FILE"
                    )

                if line.startswith("REPLACE "):
                    method_sig = line[8:].strip()
                    if not method_sig:
                        raise ValueError(f"FILE {file_path}: REPLACE requires a method signature")
                    content, i = read_content_block(lines, i + 1)
                    patch["actions"].append({
                        "type": "REPLACE",
                        "method_sig": method_sig,
                        "content": content,
                    })
                    continue

                if line.startswith("FIND_REPLACE "):
                    parts = parse_quoted_args(line[13:])
                    if len(parts) != 2:
                        raise ValueError(
                            f"FILE {file_path}: FIND_REPLACE requires exactly 2 quoted arguments"
                        )
                    patch["actions"].append({
                        "type": "FIND_REPLACE",
                        "old": parts[0],
                        "new": parts[1],
                    })
                    i += 1
                    continue

                if line == "PATCH" or line.startswith("PATCH "):
                    method_sig = line[5:].strip() or None
                    content, i = read_content_block(lines, i + 1)
                    if not content:
                        raise ValueError(f"FILE {file_path}: empty PATCH block")
                    patch["actions"].append({
                        "type": "PATCH",
                        "method_sig": method_sig,
                        "content": content,
                    })
                    continue

                raise ValueError(f"FILE {file_path}: unknown directive: {line}")

            if not patch["actions"]:
                raise ValueError(f"FILE {file_path}: no actions")
            patches.append(patch)
            continue

        raise ValueError(f"Unexpected directive: {line}")

    return patches


def method_header_pattern(method_sig: str) -> re.Pattern[str]:
    return re.compile(r"^\s*" + re.escape(method_sig) + r"\s*$")


def find_method_range(lines: List[str], method_sig: str) -> Tuple[int, int]:
    """
    Return inclusive [start, end] for one method.

    The signature is matched against the complete .method declaration when the
    smalipatch uses a .method line. If a bare method descriptor/name is supplied,
    we also accept it when it occurs in a .method declaration.
    """
    method_sig = method_sig.strip()

    candidates: List[int] = []
    exact = method_header_pattern(method_sig)
    for i, line in enumerate(lines):
        stripped = line.strip()
        if exact.match(stripped):
            candidates.append(i)
        elif not method_sig.startswith(".method ") and stripped.startswith(".method "):
            if method_sig in stripped:
                candidates.append(i)

    if not candidates:
        return -1, -1
    if len(candidates) > 1:
        # A patch should be deterministic. Multiple matches indicate the
        # descriptor is not specific enough.
        raise ValueError(f"Method signature is ambiguous: {method_sig}")

    start = candidates[0]
    depth = 0
    for j in range(start, len(lines)):
        stripped = lines[j].strip()
        if stripped.startswith(".method "):
            depth += 1
        elif stripped == ".end method":
            depth -= 1
            if depth == 0:
                return start, j

    # Malformed smali: don't guess through the class boundary.
    raise ValueError(f"No .end method found for {method_sig}")


def find_sequence(
    lines: List[str],
    wanted: List[str],
    start: int = 0,
    end: Optional[int] = None,
) -> Tuple[int, int]:
    """
    Find one ordered sequence.

    Non-empty wanted lines must occur in order. Unchanged blank lines are
    treated as formatting noise and may appear between matched lines. Explicit
    added/removed blank lines (which are still represented in the replacement
    sequence) are handled by the caller.
    """
    wanted_norm = [normalize_line(x) for x in wanted if normalize_line(x) != ""]
    if not wanted_norm:
        return start, start

    end = len(lines) if end is None else end
    matches: List[Tuple[int, int]] = []

    for i in range(start, end):
        if normalize_line(lines[i]) != wanted_norm[0]:
            continue

        pos = i
        ok = True
        for wanted_line in wanted_norm[1:]:
            pos += 1
            while pos < end and normalize_line(lines[pos]) == "":
                pos += 1
            if pos >= end or normalize_line(lines[pos]) != wanted_line:
                ok = False
                break

        if ok:
            matches.append((i, pos + 1))

    if len(matches) == 1:
        return matches[0]
    if not matches:
        return -1, -1
    raise ValueError(f"Patch context is ambiguous ({len(matches)} matches)")


def apply_replace(lines: List[str], action: Dict[str, Any], quiet: bool) -> Optional[List[str]]:
    method_sig = action["method_sig"]
    try:
        start_idx, end_idx = find_method_range(lines, method_sig)
    except ValueError as exc:
        log_error(f"  ✗ {exc}")
        return None

    if start_idx == -1:
        log_error(f"  ✗ Method not found: {method_sig}")
        return None

    content = list(action["content"])

    # A REPLACE block describes the method body. Keep the original declaration
    # unless the block explicitly contains its own .method declaration.
    if not any(x.lstrip().startswith(".method ") for x in content):
        content.insert(0, lines[start_idx])

    # The replacement must end with exactly one method terminator.
    content = [x for x in content if x.strip() != ".end method"]
    content.append(".end method")

    new_lines = lines[:start_idx] + content + lines[end_idx + 1:]

    log(f"    ✓ Replaced method at line {start_idx + 1}", Colors.GREEN, quiet)
    return new_lines


def apply_find_replace(lines: List[str], action: Dict[str, Any], quiet: bool) -> Optional[List[str]]:
    old_val = action["old"]
    new_val = action["new"]

    count = sum(line.count(old_val) for line in lines)
    if count == 0:
        # Idempotent behavior: if the requested replacement is already present,
        # treat the action as successfully applied.
        if any(new_val in line for line in lines):
            log("    ✓ Pattern already replaced", Colors.GREEN, quiet)
            return list(lines)
        log_error(f"  ✗ Pattern not found: {old_val}")
        return None

    if count != 1:
        log_error(f"  ✗ Pattern is ambiguous: found {count} occurrences of {old_val}")
        return None

    return_lines = [line.replace(old_val, new_val, 1) for line in lines]
    log(f"    ✓ Replaced 1 occurrence", Colors.GREEN, quiet)
    return return_lines


def parse_patch_hunk(content: List[str]) -> Tuple[List[str], List[str], List[str]]:
    """
    Interpret a PATCH block as an ordered diff.

    Returns:
      old_match      - lines that must be found, ignoring unchanged blanks
      new_match      - non-empty lines used for idempotency detection
      replacement    - the exact new context/addition lines to write
    """
    old_match: List[str] = []
    new_match: List[str] = []
    replacement: List[str] = []

    for raw in content:
        if raw.startswith("+ "):
            line = raw[2:]
            new_match.append(line)
            replacement.append(line)
        elif raw.startswith("- "):
            old_match.append(raw[2:])
        elif raw.startswith("+"):
            line = raw[1:]
            new_match.append(line)
            replacement.append(line)
        elif raw.startswith("-"):
            old_match.append(raw[1:])
        else:
            # Context is required for matching unless it is a harmless blank.
            # Keep blanks in replacement but omit them from the matching key.
            replacement.append(raw)
            if raw.strip() != "":
                old_match.append(raw)
                new_match.append(raw)

    if not old_match and not new_match:
        raise ValueError("PATCH hunk has no meaningful lines")
    return old_match, new_match, replacement


def apply_patch(lines: List[str], action: Dict[str, Any], quiet: bool) -> Optional[List[str]]:
    old_seq, new_seq, replacement = parse_patch_hunk(action["content"])

    search_start = 0
    search_end = len(lines)

    method_sig = action.get("method_sig")
    if method_sig:
        try:
            start_idx, end_idx = find_method_range(lines, method_sig)
        except ValueError as exc:
            log_error(f"  ✗ {exc}")
            return None
        if start_idx == -1:
            log_error(f"  ✗ Method not found: {method_sig}")
            return None
        search_start = start_idx
        search_end = end_idx + 1

    try:
        match_idx, match_end = find_sequence(lines, old_seq, search_start, search_end)
    except ValueError as exc:
        log_error(f"  ✗ {exc}")
        return None

    if match_idx == -1:
        # Idempotent behavior: a PATCH may already have been applied.
        try:
            applied_idx, applied_end = find_sequence(lines, new_seq, search_start, search_end)
        except ValueError as exc:
            log_error(f"  ✗ {exc}")
            return None
        if applied_idx != -1:
            log("    ✓ PATCH already applied", Colors.GREEN, quiet)
            return list(lines)

        log_error("  ✗ Ordered PATCH context not found")
        log_error(f"     First context: {old_seq[0].strip()[:120]}")
        return None

    result = lines[:match_idx] + replacement + lines[match_end:]
    log(f"    ✓ Applied PATCH at line {match_idx + 1}", Colors.GREEN, quiet)
    return result


def apply_patch_to_file(work_dir: str, patch: Dict[str, Any], quiet: bool) -> bool:
    file_path = patch["file_path"]
    full_path = os.path.normpath(os.path.join(work_dir, file_path))

    # Prevent directory traversal even after normalization.
    work_abs = os.path.abspath(work_dir)
    full_abs = os.path.abspath(full_path)
    if os.path.commonpath([work_abs, full_abs]) != work_abs:
        log_error(f"   Invalid patch path: {file_path}")
        return False

    if not os.path.isfile(full_abs):
        log_error(f"   File not found: {file_path}")
        return False

    log(f"  Patching: {file_path}", Colors.YELLOW, quiet)

    try:
        with open(full_abs, "r", encoding="utf-8", newline="") as f:
            # Keep line contents; normalize only line endings.
            lines = [line.rstrip("\r\n") for line in f.readlines()]
    except Exception as exc:
        log_error(f"   Failed to read file: {exc}")
        return False

    for idx, action in enumerate(patch["actions"], start=1):
        action_type = action["type"]
        if action_type == "REPLACE":
            result = apply_replace(lines, action, quiet)
        elif action_type == "FIND_REPLACE":
            result = apply_find_replace(lines, action, quiet)
        elif action_type == "PATCH":
            result = apply_patch(lines, action, quiet)
        else:
            log_error(f"   Unknown action type: {action_type}")
            return False

        if result is None:
            log_error(f"   ✗ Action {idx} failed")
            return False
        lines = result

    # Write only after every action has succeeded: a failed multi-action FILE
    # leaves the original file untouched.
    try:
        with open(full_abs, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
    except Exception as exc:
        log_error(f"   Failed to write file: {exc}")
        return False

    log("   ✓ File patched successfully", Colors.GREEN, quiet)
    return True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="ReCoreUI SmaliPatcher: apply .smalipatch files to decoded smali",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument("work_dir", help="Root directory containing decoded smali")
    parser.add_argument("patch_file", help="Path to .smalipatch file")
    parser.add_argument("-q", "--quiet", action="store_true",
                        help="Quiet mode (only errors)")
    args = parser.parse_args()

    Colors.init()

    if not os.path.isdir(args.work_dir):
        log_error(f"ERROR: Directory not found: {args.work_dir}")
        sys.exit(1)

    if not os.path.isfile(args.patch_file):
        log_error(f"ERROR: Patch file not found: {args.patch_file}")
        sys.exit(1)

    try:
        with open(args.patch_file, "r", encoding="utf-8") as f:
            raw_lines = f.read().splitlines()
        patches = parse_smalipatch(raw_lines, quiet=args.quiet)
    except Exception as exc:
        log_error(f"ERROR: Invalid .smalipatch: {exc}")
        sys.exit(1)

    if not patches:
        log_error("ERROR: No valid FILE blocks found")
        sys.exit(1)

    log(f"Found {len(patches)} file(s) to patch", Colors.BLUE, args.quiet)
    log("=" * 50, quiet=args.quiet)

    success_count = 0
    for patch in patches:
        if apply_patch_to_file(args.work_dir, patch, args.quiet):
            success_count += 1
        else:
            # Fail-fast: partial application of a multi-file patch package is
            # dangerous. Caller can discard the entire work directory.
            log_error("Stopping after first failed FILE block")
            sys.exit(1)

    log("=" * 50, quiet=args.quiet)
    log(f"✓ Success: {success_count}/{len(patches)} files patched",
        Colors.GREEN, args.quiet)
    sys.exit(0)


if __name__ == "__main__":
    main()
