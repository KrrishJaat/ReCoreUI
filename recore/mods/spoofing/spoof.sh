########################################
# Spoof From Extra Firmware
########################################

LOG_INFO "Applying custom spoof props..."

BPROP "system" "ro.product.system.model" "$(GET_BPROP_VAL "extra" "ro.product.system.model")"
BPROP "system" "ro.product.system.name" "$(GET_BPROP_VAL "extra" "ro.product.system.name")"

LOG_INFO "Custom spoof props applied!"