#!/usr/bin/env bash
# MOD_NAME="ReCoreUI Settings integration"
# MOD_AUTHOR="ported from UN1CA Settings app mod"
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${PWD}"
PAYLOAD="$SCRIPT_DIR/_payload"

log() { LOG_INFO "$*" 2>/dev/null || printf '[ReCoreUI Settings] %s\n' "$*"; }
fatal() { ERROR_EXIT "$*" 2>/dev/null || { printf '[ReCoreUI Settings] ERROR: %s\n' "$*" >&2; exit 1; }; }

[[ -d "$PAYLOAD" ]] || fatal "Payload directory missing: $PAYLOAD"

# Copy a file only when the destination is absent or differs. This keeps rebuilds idempotent.
copy_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then return 0; fi
    cp -f "$src" "$dst"
}

# Merge values XML without deleting stock resources. Resource names are de-duplicated.
merge_values_xml() {
    local src="$1" dst="$2"
    [[ -f "$dst" ]] || { copy_file "$src" "$dst"; return; }
    python3 - "$src" "$dst" <<'PY'
import re, sys
from pathlib import Path
src, dst = map(Path, sys.argv[1:])
s = src.read_text(encoding='utf-8')
d = dst.read_text(encoding='utf-8')
body = re.search(r'<resources(?:\s[^>]*)?>(.*?)</resources>', s, re.S)
if not body:
    raise SystemExit(f'Invalid values XML: {src}')
items = re.findall(r'(?ms)^\s*(<(?:string|color|id|bool|integer|dimen|fraction|item|style|declare-styleable|attr|plurals|array)\b.*?</(?:string|color|bool|integer|dimen|fraction|item|style|plurals|array)>|<id\b[^>]*/>)', body.group(1))
if not items:
    # Fall back to line-oriented single element extraction for simple one-line resources.
    items = [x.strip() for x in body.group(1).splitlines() if x.strip().startswith('<')]
existing_names = set(re.findall(r'<(?:string|color|id|bool|integer|dimen|fraction|item|style|declare-styleable|attr|plurals|array)\b[^>]*\bname="([^"]+)"', d))
add=[]
for item in items:
    m=re.search(r'\bname="([^"]+)"', item)
    if m and m.group(1) in existing_names:
        continue
    add.append(item.rstrip())
if add:
    pos=d.rfind('</resources>')
    if pos < 0: raise SystemExit(f'Missing </resources> in {dst}')
    d=d[:pos]+'\n'+'\n'.join(add)+'\n'+d[pos:]
    dst.write_text(d, encoding='utf-8')
PY
}

# Merge the supplied normal resources safely.
while IFS= read -r -d '' src; do
    rel="${src#"$PAYLOAD/"}"
    dst="$TARGET/$rel"
    if [[ "$rel" == res/values*/\*.xml ]]; then :; fi
    if [[ "$rel" == res/values*/*.xml ]]; then
        merge_values_xml "$src" "$dst"
    elif [[ "$rel" == res/xml/sec_top_level_settings.xml ]]; then
        # First line in the source archive is a sed insertion directive. Apply it without replacing stock XML.
        python3 - "$src" "$dst" <<'PY'
from pathlib import Path
import sys
src,dst=map(Path,sys.argv[1:])
lines=src.read_text().splitlines()
if not lines: raise SystemExit('Empty sec_top_level_settings.xml payload')
needle=lines[0].strip()
insert='\n'.join(lines[1:]).strip()
text=dst.read_text() if dst.exists() else ''
if not insert: raise SystemExit('No top-level preference payload')
key='android:key="top_level_unica"'
if key in text: raise SystemExit(0)
marker=needle.strip('/a').strip() if needle.startswith('/') else needle
idx=text.find('</PreferenceScreen>')
if marker and marker in text:
    line_end=text.find('\n', text.find(marker))
    if line_end<0: line_end=len(text)
    text=text[:line_end+1]+insert+'\n'+text[line_end+1:]
elif idx>=0:
    text=text[:idx]+insert+'\n'+text[idx:]
else:
    raise SystemExit(f'No suitable insertion point in {dst}')
dst.write_text(text)
PY
    elif [[ "$rel" == res/xml/*.xml || "$rel" == res/layout/*.xml || "$rel" == res/drawable/*.xml || "$rel" == res/drawable-nodpi/* ]]; then
        # Unique payload resources are safe to add/replace with the same supplied source.
        copy_file "$src" "$dst"
    fi
done < <(find "$PAYLOAD/res" -type f -print0)

# Android manifest: add each new Activity once, just before </application>.
python3 - "$PAYLOAD/manifest_activities.xml" "$TARGET/AndroidManifest.xml" <<'PY'
from pathlib import Path
import re,sys
src,dst=map(Path,sys.argv[1:])
text=dst.read_text(encoding='utf-8')
fragment=src.read_text(encoding='utf-8').strip()
for m in re.finditer(r'<activity\b[^>]*android:name="([^"]+)"[^>]*>.*?</activity>', fragment, re.S):
    block=m.group(0)
    name=m.group(1)
    if f'android:name="{name}"' in text: continue
    pos=text.find('</application>')
    if pos < 0: raise SystemExit('Missing </application> in AndroidManifest.xml')
    text=text[:pos]+block+'\n    '+text[pos:]
dst.write_text(text, encoding='utf-8')
PY

# Required SecSettings smali integrations. Each edit is idempotent and validates its result.
patch_replace_once() {
    local file="$1" old="$2" new="$3"
    [[ -f "$file" ]] || fatal "Required smali file missing: $file"
    if grep -Fq "$new" "$file"; then return 0; fi
    grep -Fq "$old" "$file" || fatal "Required pattern not found in $(basename "$file"): $old"
    python3 - "$file" "$old" "$new" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); old,new=sys.argv[2:]
s=p.read_text()
count=s.count(old)
if count!=1: raise SystemExit(f'Expected exactly one match, found {count}: {old}')
p.write_text(s.replace(old,new,1))
PY
}

# One UI minor version: force the method to return true.
ONEUI="$TARGET/smali_classes4/com/samsung/android/settings/deviceinfo/softwareinfo/OneUIVersionPreferenceController.smali"
[[ -f "$ONEUI" ]] || fatal "Missing OneUIVersionPreferenceController.smali"
python3 - "$ONEUI" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); s=p.read_text()
pat=r'(\.method[^\n]*\bisDeviceWithMicroVersion\(\)Z\n)(.*?)(?=^\.end method\s*$)'
m=re.search(pat,s,re.M|re.S)
if not m: raise SystemExit('isDeviceWithMicroVersion()Z not found')
body=m.group(0)
if 'const/4 p0, 0x1\n\n    return p0' in body: raise SystemExit(0)
# preserve signature and return a deterministic true value.
new=m.group(1)+'    .locals 1\n\n    const/4 p0, 0x1\n\n    return p0\n.end method'
s=s[:m.start()]+new+s[m.end():]
p.write_text(s)
PY

MODEL="$TARGET/smali_classes4/com/samsung/android/settings/deviceinfo/aboutphone/ModelNameGetter.smali"
patch_replace_once "$MODEL" 'const-string p0, "ro.product.model"' 'const-string p0, "ro.boot.em.model"'

SEARCHM="$TARGET/smali/com/android/settingslib/search/SearchIndexableResourcesMobile.smali"
patch_replace_once "$SEARCHM" '.class public final Lcom/android/settingslib/search/SearchIndexableResourcesMobile;' '.class public Lcom/android/settingslib/search/SearchIndexableResourcesMobile;'

LAMBDA="$TARGET/smali/com/android/settings/search/SearchFeatureProviderImpl\$\$ExternalSyntheticLambda0.smali"
patch_replace_once "$LAMBDA" 'new-instance p0, Lcom/android/settingslib/search/SearchIndexableResourcesMobile;' 'new-instance p0, Lio/mesalabs/unica/search/UnicaSearchIndexableResources;'
patch_replace_once "$LAMBDA" 'invoke-direct {p0}, Lcom/android/settingslib/search/SearchIndexableResourcesBase;-><init>()V' 'invoke-direct {p0}, Lio/mesalabs/unica/search/UnicaSearchIndexableResources;-><init>()V'

log "ReCoreUI Settings payload merged and SecSettings hooks applied"
