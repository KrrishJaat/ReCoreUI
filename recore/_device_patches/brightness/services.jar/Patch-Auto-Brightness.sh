#!/system/bin/sh

echo "▪ Executing Patch-Auto-Brightness.sh"

if ! GET_FEATURE DEVICE_USE_STOCK_BASE; then

    [[ -z "$SOURCE_AUTO_BRIGHTNESS_LEVEL" || -z "$DEVICE_AUTO_BRIGHTNESS_LEVEL" ]] && \
    ERROR_EXIT "Missing auto brightness var"

    TARGET_FILES=$(find "$(pwd)" -type f \( \
        -name "DisplayPowerController.smali" -o \
        -name "AutomaticBrightnessStrategy.smali" -o \
        -name "AutomaticBrightnessStrategy2.smali" -o \
        -name "PowerManagerUtil.smali" \
    \))

    [ -z "$TARGET_FILES" ] && \
    ERROR_EXIT "No brightness smali files found"

    for FILE in $TARGET_FILES; do

        echo "Patching: $FILE"

        sed -i -E \
        "s/\"${SOURCE_AUTO_BRIGHTNESS_LEVEL}\"/\"${DEVICE_AUTO_BRIGHTNESS_LEVEL}\"/g" \
        "$FILE"

    done

    echo "✓ Auto brightness patch completed"

fi