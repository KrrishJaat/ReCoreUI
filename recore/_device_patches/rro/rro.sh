#!/usr/bin/env bash

_GET_BUILD_PROP_FROM_DIR()
{
    local ROOT="$1"
    local KEY="$2"
    local BUILD_PROP VALUE

    [[ -d "$ROOT" ]] || return 1

    while IFS= read -r -d '' BUILD_PROP; do
        VALUE="$(sed -n -E \
            "s/^[[:space:]]*${KEY//./\\.}[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$/\1/p" \
            "$BUILD_PROP" | tail -n1)"

        if [[ -n "$VALUE" ]]; then
            printf '%s\n' "$VALUE"
            return 0
        fi
    done < <(find "$ROOT" -type f -name 'build.prop' -print0 2>/dev/null)

    return 1
}

_GET_EXTRA_PROP()
{
    local PART="$1"
    local KEY="$2"
    local EXTRA_ROOT
    local PART_DIR

    EXTRA_ROOT="$(GET_FW_DIR "extra" 2>/dev/null)" || return 1
    PART_DIR="$EXTRA_ROOT/$PART"
    _GET_BUILD_PROP_FROM_DIR "$PART_DIR" "$KEY"
}

_GET_CURRENT_PROP()
{
    local PART="$1"
    local KEY="$2"
    local PART_DIR

    PART_DIR="$(GET_PARTITION_PATH "$PART" 2>/dev/null)" || return 1
    _GET_BUILD_PROP_FROM_DIR "$PART_DIR" "$KEY"
}

SOURCE_PRODUCT_NAME="$(_GET_EXTRA_PROP "system" "ro.product.system.name")"
TARGET_PRODUCT_NAME="$(_GET_CURRENT_PROP "vendor" "ro.product.vendor.name")"


[[ -n "$SOURCE_PRODUCT_NAME" ]] || ERROR_EXIT "EXTRA build.prop: ro.product.system.name not found"
[[ -n "$TARGET_PRODUCT_NAME" ]] || ERROR_EXIT "Target build.prop: ro.product.vendor.name not found"

if [[ "$SOURCE_PRODUCT_NAME" == "$TARGET_PRODUCT_NAME" ]]; then
    LOG_INFO "Nothing to do: $SOURCE_PRODUCT_NAME == $TARGET_PRODUCT_NAME"
    unset SOURCE_PRODUCT_NAME TARGET_PRODUCT_NAME
    return 0
fi

LOG_INFO "Customizing RROs: $SOURCE_PRODUCT_NAME -> $TARGET_PRODUCT_NAME"

PRODUCT_DIR="$(GET_PARTITION_PATH "product")" || ERROR_EXIT "product partition not found"
OVERLAY_DIR="$PRODUCT_DIR/overlay"

[[ -d "$OVERLAY_DIR" ]] || {
    LOG_INFO "No product overlay directory found"
    unset SOURCE_PRODUCT_NAME TARGET_PRODUCT_NAME PRODUCT_DIR OVERLAY_DIR
    return 0
}

# Use the module's overlay first, then the selected objective/platform overlay.
TARGET_OVERLAY=""
for DIR in \
    "$SCRPATH/overlay" \
    "$OBJECTIVE/overlay" \
    "$RECOREUI/platform/$RECORE_CODENAME/overlay" \
    "$RECOREUI/platform/$CODENAME/overlay"; do
    if [[ -d "$DIR" ]]; then
        TARGET_OVERLAY="$DIR"
        break
    fi
done

while IFS= read -r -d '' FILE; do
    NAME="$(basename "$FILE")"
    NEW_NAME="${NAME//$SOURCE_PRODUCT_NAME/$TARGET_PRODUCT_NAME}"

    OLD_WORK_DIR="$(dirname "$FILE")/${NAME}_decompiled"
    NEW_WORK_DIR="$(dirname "$FILE")/${NEW_NAME}_decompiled"
    NEW_FILE="$(dirname "$FILE")/$NEW_NAME"

    LOG_BEGIN "Customizing $NAME"

    RELATIVE="${FILE#$WORKSPACE/}"
    DECOMPILE "$RELATIVE" || {
        LOG_WARN "Failed to decompile $NAME"
        continue
    }

    [[ -d "$OLD_WORK_DIR" ]] || {
        LOG_WARN "Decompiled directory not found for $NAME"
        continue
    }

    if [[ -f "$OLD_WORK_DIR/apktool.yml" ]]; then
        sed -i "s/${SOURCE_PRODUCT_NAME}/${TARGET_PRODUCT_NAME}/g" \
            "$OLD_WORK_DIR/apktool.yml"
    fi

    [[ "$FILE" == "$NEW_FILE" ]] || rm -f "$NEW_FILE"
    mv -f "$FILE" "$NEW_FILE" || {
        LOG_WARN "Failed to rename $NAME -> $NEW_NAME"
        rm -rf "$OLD_WORK_DIR"
        continue
    }

    mv -f "$OLD_WORK_DIR" "$NEW_WORK_DIR" || {
        LOG_WARN "Failed to rename decompiled directory for $NEW_NAME"
        continue
    }

    if [[ "$NAME" == framework-res* ]]; then
        if [[ -n "$TARGET_OVERLAY" ]]; then
            LOG "Applying target framework-res overlay"
            rm -rf "$NEW_WORK_DIR/res"
            cp -a "$TARGET_OVERLAY" "$NEW_WORK_DIR/res" || {
                LOG_WARN "Failed to apply framework-res overlay"
                continue
            }
        else
            LOG_WARN "No target overlay directory found"
        fi

    elif [[ "$NAME" == SystemUI* ]]; then
        LOG "Removing SystemUI public.xml"
        rm -f "$NEW_WORK_DIR/res/values/public.xml"

        BOOLS="$NEW_WORK_DIR/res/values/bools.xml"
        if [[ "${TARGET_CAMERA_SUPPORT_CUTOUT_PROTECTION:-false}" == "true" ]]; then
            if ! grep -q "config_enableDisplayCutoutProtection" "$BOOLS" 2>/dev/null; then
                sed -i '/<resources>/a\    <bool name="config_enableDisplayCutoutProtection">true</bool>' "$BOOLS"
            fi
        elif grep -q "config_enableDisplayCutoutProtection" "$BOOLS" 2>/dev/null; then
            sed -i '/config_enableDisplayCutoutProtection/d' "$BOOLS"
        fi
    fi

    BUILD "${NEW_FILE#$WORKSPACE/}" || {
        LOG_WARN "Failed to rebuild $NEW_NAME"
        continue
    }

    LOG_END "Customized $NEW_NAME"
done < <(find "$OVERLAY_DIR" -maxdepth 1 -type f -name "*${SOURCE_PRODUCT_NAME}*.apk" -print0)

unset SOURCE_PRODUCT_NAME TARGET_PRODUCT_NAME PRODUCT_DIR OVERLAY_DIR TARGET_OVERLAY
unset -f _GET_EXTRA_BUILD_PROP

return 0
