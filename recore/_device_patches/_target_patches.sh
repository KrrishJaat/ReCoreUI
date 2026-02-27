# ==============================================================================
#
# MOD_NAME="Target devices patches"
# MOD_AUTHOR="Salvo Giangreco , ExtremeXT , ShaDisNX255"
# MOD_DESC="Apply device related features on source firmware."
#
# ==============================================================================

# Set target model name
FF_IF_DIFF "stock" "SETTINGS_CONFIG_BRAND_NAME"
FF_IF_DIFF "stock" "SYSTEM_CONFIG_SIOP_POLICY_FILENAME"

BPROP "system" "ro.product.system.model" "SM-S911B"
BPROP "system" "ro.product.product.model" "r12sxxx"

if [[ -n "$RECORE_CODENAME" ]]; then
    BPROP "system" "ro.recore.codename" "$RECORE_CODENAME"
else
    BPROP "system" "ro.recore.codename" "$CODENAME"
fi

# Display
FF_IF_DIFF "stock" "COMMON_CONFIG_MDNIE_MODE"
FF_IF_DIFF "stock" "LCD_SUPPORT_AMOLED_DISPLAY"

# Netflix props
BPROP_IF_DIFF "stock" "system" "ro.netflix.bsp_rev"
