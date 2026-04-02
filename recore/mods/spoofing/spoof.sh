########################################
# Spoof To S25 Ultra
########################################

LOG_INFO "Applying custom spoof props..."

# System props
BPROP "system" "ro.product.system.model" "SM-S938B"
BPROP "system" "ro.product.system.name" "pa3qxxx"

LOG_INFO "Custom spoof props applied!"