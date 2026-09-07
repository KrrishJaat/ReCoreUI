#!/usr/bin/env python3
"""Small compatibility executor for UN1CA SMALI_PATCH operations."""
from __future__ import annotations
import argparse, re, sys
from pathlib import Path


def method_ranges(text: str, method: str):
    lines = text.splitlines()
    hits=[]
    for i,l in enumerate(lines):
        if l.lstrip().startswith('.method') and method in l:
            end=None
            for j in range(i+1,len(lines)):
                if lines[j].strip()=='.end method': end=j; break
            if end is None: raise ValueError(f"unterminated method: {method}")
            hits.append((i,end))
    if len(hits)!=1: raise ValueError(f"expected exactly one method match for {method}, found {len(hits)}")
    return lines,hits[0]


def write(path, lines):
    path.write_text('\n'.join(lines)+'\n', encoding='utf-8')


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('operation', choices=['remove','replace','replaceall','return','null','strip'])
    ap.add_argument('file')
    ap.add_argument('method', nargs='?')
    ap.add_argument('value', nargs='?')
    ap.add_argument('replacement', nargs='?')
    a=ap.parse_args()
    p=Path(a.file)
    if not p.is_file(): raise SystemExit(f"smali not found: {p}")
    text=p.read_text(encoding='utf-8')
    op=a.operation
    if op=='remove':
        p.unlink(); return 0
    if op=='replaceall':
        if a.value is None or a.replacement is None: raise SystemExit('replaceall requires value and replacement')
        if a.value not in text: return 0
        p.write_text(text.replace(a.value,a.replacement), encoding='utf-8')
        return 0
    if not a.method: raise SystemExit('method required')
    lines,(s,e)=method_ranges(text,a.method)
    body=lines[s+1:e]
    if op=='replace':
        if a.value is None or a.replacement is None: raise SystemExit('replace requires value and replacement')
        old=a.value
        new=a.replacement.replace('\\n','\n')
        joined='\n'.join(body)
        if new in joined and old not in joined:
            return 0
        changed=False
        out=[]
        for line in body:
            stripped=line.strip()
            if stripped==old:
                indent=line[:len(line)-len(line.lstrip())]
                out.extend([(indent+x if x else '') for x in new.splitlines()]); changed=True
            elif old and re.match(r'^\s*const-string(?:/jumbo)?\s', line) and f'"{old}"' in line:
                out.append(line.replace(f'"{old}"', f'"{new}"', 1)); changed=True
            else: out.append(line)
        if not changed: raise SystemExit(f'replace pattern not found: {old}')
        lines[s+1:e]=out
    elif op=='null':
        lines[s+1:e]=['    .locals 0','    ','    return-void']
    elif op=='return':
        if a.value is None: raise SystemExit('return requires value')
        sig=a.method
        ret=sig.split(')',1)[1] if ')' in sig else ''
        static=bool(' static ' in lines[s])
        reg='v0' if static and '()' in sig else 'p0'
        if ret=='V': raise SystemExit('cannot return a value from void method')
        val=a.value
        if ret=='Ljava/lang/String;':
            val=f'"{val}"'; ins=f'const-string {reg}, {val}'; retins=f'return-object {reg}'; loc='.locals 0'
        elif ret=='Z':
            if val not in ('true','false','0x0','0x1','0','1'): raise SystemExit('invalid boolean return')
            val={'true':'0x1','false':'0x0','0':'0x0','1':'0x1'}.get(val,val)
            ins=f'const/4 {reg}, {val}'; retins=f'return {reg}'; loc='.locals 1' if reg=='v0' else '.locals 0'
        elif re.fullmatch(r'\[*[BCSI]', ret):
            try: n=int(val,0)
            except: raise SystemExit('invalid integer return')
            ins=f'const/4 {reg}, 0x{n:x}' if -8<n<8 else f'const/16 {reg}, 0x{n:x}'
            retins=f'return {reg}'; loc='.locals 1' if reg=='v0' else '.locals 0'
        elif ret=='J':
            ins=f'const-wide/16 {reg}, {val}'; retins=f'return-wide {reg}'; loc='.locals 1' if reg=='v0' else '.locals 0'
        else:
            if val not in ('null','0x0','0'): raise SystemExit('invalid object return')
            ins=f'const/4 {reg}, 0x0'; retins=f'return-object {reg}'; loc='.locals 1' if reg=='v0' else '.locals 0'
        lines[s+1:e]=[f'    {loc}','    ',f'    {ins}','    ',f'    {retins}']
    elif op=='strip':
        del lines[s:e+1]
    write(p,lines)
    return 0

if __name__=='__main__':
    try: raise SystemExit(main())
    except Exception as e:
        print(f'un1ca_smali_compat.py: ERROR: {e}', file=sys.stderr); raise SystemExit(1)
