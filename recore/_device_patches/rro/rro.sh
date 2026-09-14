#!/usr/bin/env bash
# rro patch rom UN1CA

[[ -n "${RECOREUI:-}" ]] || ERROR_EXIT "RECOREUI environment is not loaded"
[[ -n "${WORKSPACE:-}" ]] || ERROR_EXIT "WORKSPACE environment is not loaded"
[[ -n "${PREBUILTS:-}" ]] || ERROR_EXIT "PREBUILTS environment is not loaded"

_GET_PROP_VALUE()
{
    local PART="$1"
    local KEY="$2"
    local VALUE=""

    if declare -F BPROP >/dev/null 2>&1; then
        VALUE="$(BPROP "$PART" "$KEY" 2>/dev/null | sed -n 's/^[^=]*=//p' | head -n1)"
    fi

    printf '%s\n' "$VALUE"
}

_GET_FLOATING_FEATURE_CONFIG()
{
    local KEY="$1"

    if declare -F GET_FLOATING_FEATURE_CONFIG >/dev/null 2>&1; then
        GET_FLOATING_FEATURE_CONFIG "$KEY"
        return $?
    fi

    return 0
}

_LOG_ERROR_OR_WARN()
{
    local MSG="$1"

    if [[ "${DEBUG_BUILD:-false}" == "true" ]]; then
        if declare -F LOG_WARN >/dev/null 2>&1; then
            LOG_WARN "$MSG"
        else
            printf 'WARNING: %s\n' "$MSG" >&2
        fi
        return 0
    fi

    if declare -F ERROR_EXIT >/dev/null 2>&1; then
        ERROR_EXIT "$MSG"
    else
        printf 'ERROR: %s\n' "$MSG" >&2
        return 1
    fi
}

_FIND_PRODUCT_OVERLAYS()
{
    local PRODUCT_NAME="$1"
    local PART_DIR=""

    if declare -F GET_PARTITION_PATH >/dev/null 2>&1; then
        PART_DIR="$(GET_PARTITION_PATH product 2>/dev/null || true)"
    fi

    [[ -z "$PART_DIR" ]] && return 0
    [[ ! -d "$PART_DIR/overlay" ]] && return 0

    find "$PART_DIR/overlay" -maxdepth 1 -type f \
        -name "*${PRODUCT_NAME}*.apk" -print0 2>/dev/null
}

_RESOLVE_TARGET_OVERLAY()
{
    local CANDIDATE

    if [[ -n "${OBJECTIVE:-}" ]]; then
        CANDIDATE="$OBJECTIVE/overlay"
        if [[ -d "$CANDIDATE" ]]; then
            printf '%s\n' "$CANDIDATE"
            return 0
        fi
    fi

    if [[ -n "${RECORE_CODENAME:-}" ]]; then
        CANDIDATE="$RECOREUI/platform/$RECORE_CODENAME/overlay"
        if [[ -d "$CANDIDATE" ]]; then
            printf '%s\n' "$CANDIDATE"
            return 0
        fi
    fi

    if [[ -n "${CODENAME:-}" ]]; then
        CANDIDATE="$RECOREUI/platform/$CODENAME/overlay"
        if [[ -d "$CANDIDATE" ]]; then
            printf '%s\n' "$CANDIDATE"
            return 0
        fi
    fi

    return 1
}


SOURCE_PRODUCT_NAME="$(_GET_PROP_VALUE system ro.product.system.name)"
TARGET_PRODUCT_NAME="$(_GET_PROP_VALUE vendor ro.product.vendor.name)"

if [[ -z "$SOURCE_PRODUCT_NAME" || -z "$TARGET_PRODUCT_NAME" ]]; then
    _LOG_ERROR_OR_WARN \
        "Unable to resolve source/target product names (system ro.product.system.name='$SOURCE_PRODUCT_NAME', vendor ro.product.vendor.name='$TARGET_PRODUCT_NAME')"
    unset SOURCE_PRODUCT_NAME TARGET_PRODUCT_NAME
    return 0
fi

if [[ "$SOURCE_PRODUCT_NAME" == "$TARGET_PRODUCT_NAME" ]]; then
    LOG_INFO "Nothing to do: source and target product names are identical ($SOURCE_PRODUCT_NAME)"
    unset SOURCE_PRODUCT_NAME TARGET_PRODUCT_NAME
    return 0
fi

TARGET_OVERLAY_DIR="$(_RESOLVE_TARGET_OVERLAY || true)"
if [[ -z "$TARGET_OVERLAY_DIR" ]]; then
    _LOG_ERROR_OR_WARN "Target overlay folder not found for selected device/objective"
    unset SOURCE_PRODUCT_NAME TARGET_PRODUCT_NAME TARGET_OVERLAY_DIR
    return 0
fi

LOG_INFO "RRO customization: $SOURCE_PRODUCT_NAME -> $TARGET_PRODUCT_NAME"
LOG_INFO "Target overlay: ${TARGET_OVERLAY_DIR#$RECOREUI/}"


while IFS= read -r -d '' TARGET_FILE; do
    FILE_NAME="$(basename "$TARGET_FILE")"
    DIR="$(dirname "$TARGET_FILE")"

    NEW_FILE_NAME="${FILE_NAME//$SOURCE_PRODUCT_NAME/$TARGET_PRODUCT_NAME}"
    NEW_TARGET_FILE="$DIR/$NEW_FILE_NAME"

    OLD_WORK_DIR="$DIR/${FILE_NAME}_decompiled"
    NEW_WORK_DIR="$DIR/${NEW_FILE_NAME}_decompiled"

    [[ "$FILE_NAME" == *"$SOURCE_PRODUCT_NAME"*.apk ]] || continue

    LOG_BEGIN "Customizing $FILE_NAME"

    rm -rf "$OLD_WORK_DIR" "$NEW_WORK_DIR"

    RELATIVE_TARGET="${TARGET_FILE#$WORKSPACE/}"
    if ! DECOMPILE "$RELATIVE_TARGET"; then
        _LOG_ERROR_OR_WARN "Failed to decompile $RELATIVE_TARGET"
        continue
    fi

    [[ -d "$OLD_WORK_DIR" ]] || {
        _LOG_ERROR_OR_WARN "Expected decompiled directory not found: $OLD_WORK_DIR"
        continue
    }

    if [[ -f "$OLD_WORK_DIR/apktool.yml" ]]; then
        sed -i "s/${SOURCE_PRODUCT_NAME}/${TARGET_PRODUCT_NAME}/g" \
            "$OLD_WORK_DIR/apktool.yml"
    fi

    if [[ "$TARGET_FILE" != "$NEW_TARGET_FILE" ]]; then
        if [[ -e "$NEW_TARGET_FILE" ]]; then
            rm -rf "$NEW_TARGET_FILE"
        fi

        if ! mv -f "$TARGET_FILE" "$NEW_TARGET_FILE"; then
            _LOG_ERROR_OR_WARN "Failed to rename $FILE_NAME to $NEW_FILE_NAME"
            rm -rf "$OLD_WORK_DIR"
            continue
        fi
    fi

    if ! mv -f "$OLD_WORK_DIR" "$NEW_WORK_DIR"; then
        _LOG_ERROR_OR_WARN "Failed to rename decompiled directory for $NEW_FILE_NAME"
        continue
    fi

    if [[ "$FILE_NAME" == framework-res* ]]; then
        LOG_INFO "Applying target framework-res overlay"

        rm -rf "$NEW_WORK_DIR/res"
        if ! cp -a "$TARGET_OVERLAY_DIR" "$NEW_WORK_DIR/res"; then
            _LOG_ERROR_OR_WARN "Failed to copy target overlay into framework-res"
            continue
        fi

        EXTRA_BRIGHTNESS="$(_GET_FLOATING_FEATURE_CONFIG SEC_FLOATING_FEATURE_LCD_SUPPORT_EXTRA_BRIGHTNESS)"
        if [[ -n "$EXTRA_BRIGHTNESS" ]] && \
           ! grep -q -w \
             "config_Extra_Brightness_Display_Solution_Brightness_Value" \
             "$TARGET_OVERLAY_DIR/values/arrays.xml" 2>/dev/null; then
            _LOG_ERROR_OR_WARN \
                "SEC_FLOATING_FEATURE_LCD_SUPPORT_EXTRA_BRIGHTNESS is set but \"config_Extra_Brightness_Display_Solution_Brightness_Value\" is missing in arrays.xml"
        fi

        AOD_CONFIG="$(_GET_FLOATING_FEATURE_CONFIG SEC_FLOATING_FEATURE_FRAMEWORK_CONFIG_AOD_ITEM)"
        if [[ "$AOD_CONFIG" =~ activeclock|clocktransition ]] && \
           ! grep -q -w \
             "physical_power_button_center_screen_location_y" \
             "$TARGET_OVERLAY_DIR/values/dimens.xml" 2>/dev/null; then
            _LOG_ERROR_OR_WARN \
                "AOD Clock Transition is enabled but \"physical_power_button_center_screen_location_y\" is missing in dimens.xml"
        fi

    elif [[ "$FILE_NAME" == SystemUI* ]]; then
        LOG_INFO "Applying SystemUI RRO adjustments"

        rm -f "$NEW_WORK_DIR/res/values/public.xml"

        BOOLS="$NEW_WORK_DIR/res/values/bools.xml"
        CUTOUT="${TARGET_CAMERA_SUPPORT_CUTOUT_PROTECTION:-false}"

        if [[ "$CUTOUT" == "true" ]]; then
            if ! grep -q "config_enableDisplayCutoutProtection" "$BOOLS" 2>/dev/null; then
                if [[ -f "$BOOLS" ]]; then
                    sed -i '/<resources>/a\    <bool name="config_enableDisplayCutoutProtection">true</bool>' \
                        "$BOOLS"
                else
                    mkdir -p "$(dirname "$BOOLS")"
                    cat > "$BOOLS" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <bool name="config_enableDisplayCutoutProtection">true</bool>
</resources>
XML
                fi
            fi
        elif grep -q "config_enableDisplayCutoutProtection" "$BOOLS" 2>/dev/null; then
            sed -i '/config_enableDisplayCutoutProtection/d' "$BOOLS"
        fi
    fi

    RELATIVE_NEW_TARGET="${NEW_TARGET_FILE#$WORKSPACE/}"
    if ! BUILD "$RELATIVE_NEW_TARGET"; then
        _LOG_ERROR_OR_WARN "Failed to rebuild $NEW_FILE_NAME"
        continue
    fi

    LOG_END "Customized $NEW_FILE_NAME"

done < <(_FIND_PRODUCT_OVERLAYS "$SOURCE_PRODUCT_NAME")

unset SOURCE_PRODUCT_NAME TARGET_PRODUCT_NAME TARGET_OVERLAY_DIR
unset -f _GET_PROP_VALUE _GET_FLOATING_FEATURE_CONFIG _LOG_ERROR_OR_WARN \
    _FIND_PRODUCT_OVERLAYS _RESOLVE_TARGET_OVERLAY

return 0
