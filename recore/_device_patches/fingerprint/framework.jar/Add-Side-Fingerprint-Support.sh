find . -name "*.smali" -exec \
    sed -i -E "s|google_touch_display_optical,settings=3,aod_transition_animation|google_touch_side,settings=3,navi=1|g" {} +

find . -name "InputRune.smali" -exec \
    sed -i -E "s|sput-boolean v1, Lcom/samsung/android/rune/InputRune;->PWM_SKIP_TOO_FAST_DOUBLE_PRESS:Z|sput-boolean v4, Lcom/samsung/android/rune/InputRune;->PWM_SKIP_TOO_FAST_DOUBLE_PRESS:Z|g" {} +

find . -name "FingerprintManager.smali" -exec \
    sed -i '/^\.method public static blacklist semGetSensorPosition()/,/^\.end method/ {
        s/^\(\s*\)const\/4 v0, 0x2/\1const\/4 v0, 0x4/
    }' {} +

find . -name "SemFingerprintManager\$Characteristics.smali" -exec \
    sed -i '/^\.method public whitelist getSensorType()/,/^\.end method/ {
        s/^\(\s*\)const\/4 p0, 0x2/\1const\/4 p0, 0x1/
    }' {} +  