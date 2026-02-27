# ==============================================================================
#
# MOD_NAME="Overlay From Stock"
# MOD_AUTHOR="KrrishJaat"
#
# ==============================================================================

SYSTEM_NAME="$(GET_PROP "system" "ro.product.system.name" "stock")"
FW_DIR="$(GET_FW_DIR "stock")"

SRC="$FW_DIR/product/overlay/framework-res__${SYSTEM_NAME}__auto_generated_rro_product.apk"
DST="$WORKSPACE/product/overlay"

if [ -f "$SRC" ]; then
    mkdir -p "$DST"
    cp -f "$SRC" "$DST/"
    chmod 0644 "$DST/$(basename "$SRC")"
fi