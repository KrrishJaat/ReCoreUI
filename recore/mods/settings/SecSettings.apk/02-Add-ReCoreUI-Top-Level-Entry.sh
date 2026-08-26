# ==============================================================================
#
# MOD_NAME="ReCoreUI Settings - Top Level Entry"
# MOD_AUTHOR="salvogiangri (ported from UN1CA)"
# MOD_DESC="Adds the 'ReCoreUI Settings' row to the main Settings homepage list
#           (res/xml/sec_top_level_settings.xml), right after the stock
#           'Advanced features' entry."
#
# ==============================================================================
#
# sec_top_level_settings.xml already exists in the stock apk, so - same as the
# 01-Merge script - we can't just drop a replacement file in res/. The entry to
# insert lives in res-fragments/_sec_top_level_settings_entry.xml (a single
# <com.android.settings.widget.HomepagePreference .../> line); this script
# inserts it right after the existing "TopLevelAdvancedFeatures" preference.

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRY_FILE="$_SELF_DIR/res-fragments/_sec_top_level_settings_entry.xml"
TARGET="res/xml/sec_top_level_settings.xml"
ANCHOR="TopLevelAdvancedFeatures"

if [[ ! -f "$TARGET" ]]; then
    LOG_WARN "Cannot add ReCoreUI top level entry: $TARGET not found (was resource decoding enabled for SecSettings.apk?)"
elif grep -qF "top_level_unica" "$TARGET"; then
    LOG_INFO "ReCoreUI top level entry already present, skipping"
elif ! grep -q "$ANCHOR" "$TARGET"; then
    LOG_WARN "Anchor \"$ANCHOR\" not found in $TARGET, skipping ReCoreUI top level entry"
else
    LOG_INFO "Adding ReCoreUI Settings entry to $TARGET"
    ENTRY_LINE="$(cat "$ENTRY_FILE")"
    awk -v entry="$ENTRY_LINE" '
        { print }
        $0 ~ /TopLevelAdvancedFeatures/ { print entry }
    ' "$TARGET" > "$TARGET.recoreui_tmp" && mv "$TARGET.recoreui_tmp" "$TARGET"
fi
