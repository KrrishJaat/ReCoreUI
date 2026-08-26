# ==============================================================================
#
# MOD_NAME="ReCoreUI Settings - Manifest Activities"
# MOD_AUTHOR="salvogiangri (ported from UN1CA)"
# MOD_DESC="Registers the 6 new ReCoreUI Settings activities
#           (Settings$Unica*Activity, declared as new inner classes under
#           smali_classes4/com/android/settings/) in AndroidManifest.xml."
#
# ==============================================================================
#
# AndroidManifest.xml is always decoded to text by apktool regardless of
# whether resource decoding (-r) is enabled for this apk, so this merge works
# independently of the res-fragment merges in 01/02.
#
# The block of <activity> declarations lives in
# res-fragments/_manifest_activities.xml and gets inserted right before the
# closing </application> tag.

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAGMENT="$_SELF_DIR/res-fragments/_manifest_activities.xml"
TARGET="AndroidManifest.xml"

if [[ ! -f "$TARGET" ]]; then
    LOG_WARN "Cannot add ReCoreUI Settings activities: $TARGET not found"
elif grep -qF "Settings\$UnicaSettingsActivity" "$TARGET"; then
    LOG_INFO "ReCoreUI Settings activities already present in $TARGET, skipping"
else
    LOG_INFO "Adding ReCoreUI Settings activities to $TARGET"
    { grep -n "</application>" "$TARGET" | head -n1 | cut -d: -f1; } | {
        read -r LINE_NO
        head -n "$((LINE_NO - 1))" "$TARGET" > "$TARGET.recoreui_tmp"
        cat "$FRAGMENT" >> "$TARGET.recoreui_tmp"
        tail -n "+$LINE_NO" "$TARGET" >> "$TARGET.recoreui_tmp"
        mv "$TARGET.recoreui_tmp" "$TARGET"
    }
fi
