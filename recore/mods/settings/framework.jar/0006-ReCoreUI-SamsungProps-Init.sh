#!/usr/bin/env bash
set -euo pipefail
for f in smali/android/app/Instrumentation.smali; do
  [[ -f "$f" ]] || { echo "[ReCoreUI] skip: $f absent"; exit 0; }
  python3 - "$f" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); s=p.read_text()
methods=['newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;', 'newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;']
for sig in methods:
    lines=s.splitlines(True)
    hit=None
    for i,line in enumerate(lines):
        if sig in line:
            hit=i; break
    if hit is None:
        print('[ReCoreUI] skip missing Instrumentation method',sig); continue
    j=hit
    while j < len(lines) and lines[j].strip() != '.end method': j += 1
    if j >= len(lines): raise SystemExit(f'No .end method for {sig}')
    body=''.join(lines[hit:j+1])
    if 'SamsungPropsHooks;->init' in body: continue
    is_loader='ClassLoader' in sig
    marker='invoke-virtual {p0, p3}, Landroid/app/Application;->attach(Landroid/content/Context;)V' if is_loader else 'invoke-virtual {p0, p1}, Landroid/app/Application;->attach(Landroid/content/Context;)V'
    if marker not in body: raise SystemExit(f'Required attach call not found in {sig}')
    ins='\n    invoke-static {p3}, Lio/mesalabs/unica/SamsungPropsHooks;->init(Landroid/content/Context;)V' if is_loader else '\n    invoke-static {p1}, Lio/mesalabs/unica/SamsungPropsHooks;->init(Landroid/content/Context;)V'
    body=body.replace(marker,marker+ins,1)
    lines[hit:j+1]=[body]
    s=''.join(lines)
p.write_text(s)
PY
done
