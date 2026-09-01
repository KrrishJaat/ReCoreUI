#!/usr/bin/env bash
set -eo pipefail
f='smali_classes2/com/samsung/android/settings/intelligence/search/categorizing/TopLevelKeysCollector.smali'
[[ -f "$f" ]] || { echo '[ReCoreUI] TopLevelKeysCollector absent; skipping optional search registration'; exit 0; }
python3 - "$f" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
if 'const-string v36, "top_level_unica"' in s: raise SystemExit(0)
old='.locals 36'
new='.locals 37'
if old not in s: raise SystemExit('Expected .locals 36 not found in TopLevelKeysCollector')
s=s.replace(old,new,1)
old2='filled-new-array/range {v1 .. v35}, [Ljava/lang/String;'
new2='const-string v36, "top_level_unica"\n\n    filled-new-array/range {v1 .. v36}, [Ljava/lang/String;'
if old2 not in s: raise SystemExit('Expected top-level key array not found')
s=s.replace(old2,new2,1)
p.write_text(s)
PY
