# ==============================================================================
#
# MOD_NAME="ReCoreUI Settings - Merge Resources"
# MOD_AUTHOR="salvogiangri (ported from UN1CA)"
# MOD_DESC="Splices the ReCoreUI Settings strings/colors/ids into SecSettings's
#           existing values*/*.xml files, and drops in any missing locale
#           strings.xml as a brand new file."
#
# ==============================================================================
#
# WHY THIS SCRIPT EXISTS:
# ReCoreUI's apktool.sh merges a mod's res/, smali*, assets/, lib/ folders into
# the decompiled apk with a plain `rsync`. That's perfect for brand new files
# (the unica_*.xml preference screens, drawables, layout, smali classes - see
# the sibling `res/` and `smali_classes4/` folders next to this script), but it
# would be destructive for values/strings.xml, values/colors.xml, values/ids.xml
# and every values-XX/strings.xml: those files already exist in the stock apk
# and a plain rsync would replace the whole file with just our few new entries,
# deleting every original Samsung string in the process.
#
# So instead of shipping those under res/, they're staged under res-fragments/
# (same relative layout, e.g. res-fragments/values/strings.xml,
# res-fragments/values-fr/strings.xml, ...) which apktool.sh's rsync step never
# touches. This script runs afterwards (once resources have already been
# merged/decompiled) and splices each fragment's <string>/<color>/<id> entries
# in just before the closing </resources> tag of the real file - or, if a given
# values-XX locale doesn't exist yet in the stock apk, adds the fragment as a
# brand new file (it's already a complete, valid resources XML document).

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAGMENTS_DIR="$_SELF_DIR/res-fragments"

MERGE_RESOURCE_FRAGMENT()
{
    local FRAGMENT="$1"
    local TARGET="$2"

    if [[ ! -f "$TARGET" ]]; then
        LOG_INFO "Adding new resource file: ${TARGET#res/}"
        mkdir -p "$(dirname "$TARGET")"
        cp -a "$FRAGMENT" "$TARGET"
        return 0
    fi

    local LAST_LINE
    LAST_LINE="$(tail -n 1 "$TARGET" | tr -d '[:space:]')"

    if [[ "$LAST_LINE" != "</resources>" ]]; then
        LOG_WARN "Skipping merge for ${TARGET#res/}: file doesn't end with </resources> as expected"
        return 1
    fi

    # Strip the xml declaration and the <resources>/</resources> wrapper tags,
    # keeping only the <string>/<color>/<id> entries themselves.
    local STRIPPED
    STRIPPED="$(sed -e '/<?xml/d' -e '/<resources[ >]/d' -e '/<resources>/d' -e '/<\/resources>/d' "$FRAGMENT")"

    LOG_INFO "Merging entries into: ${TARGET#res/}"

    { head -n -1 "$TARGET"; printf '%s\n' "$STRIPPED"; tail -n 1 "$TARGET"; } \
        > "$TARGET.recoreui_tmp" && mv "$TARGET.recoreui_tmp" "$TARGET"
}

while IFS= read -r -d '' FRAGMENT; do
    REL="${FRAGMENT#"$FRAGMENTS_DIR"/}"
    [[ "$REL" == _* ]] && continue   # skip non-values fragments (handled by other scripts)
    MERGE_RESOURCE_FRAGMENT "$FRAGMENT" "res/$REL"
done < <(find "$FRAGMENTS_DIR" -mindepth 2 -type f -name "*.xml" -print0)
