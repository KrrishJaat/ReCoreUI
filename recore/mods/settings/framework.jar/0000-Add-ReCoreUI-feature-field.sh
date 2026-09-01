#!/usr/bin/env bash
# MOD_NAME="ReCoreUI framework feature field"
set -eo pipefail
F="$PWD/smali/android/app/ApplicationPackageManager.smali"
[[ -f "$F" ]] || { echo "Missing $F" >&2; exit 1; }
if ! grep -Fq '.field private static final blacklist FEATURES_NEXUS:[Ljava/lang/String;' "$F"; then
python3 - "$F" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
needle='.field private static final blacklist HAS_SYSTEM_FEATURE_API:Ljava/lang/String; = "has_system_feature"'
if s.count(needle)!=1: raise SystemExit('feature field anchor not found exactly once')
insert='.field private static final blacklist FEATURES_NEXUS:[Ljava/lang/String;\n\n'+needle
p.write_text(s.replace(needle, insert, 1))
PY
fi
exit 0
