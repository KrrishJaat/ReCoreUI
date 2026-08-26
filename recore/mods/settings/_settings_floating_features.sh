# ==============================================================================
#
# MOD_NAME="ReCoreUI Settings - Floating Features"
# MOD_AUTHOR="salvogiangri (ported from UN1CA)"
# MOD_DESC="Shows battery regulatory info in Settings. Requires
#           SEM_BATTERY_PROPERTY_IC_AUTHENTICATION_RESULT support."
#
# ==============================================================================
#
# Ported from UN1CA's customize.sh:
#   if [ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS")" ]; then
#       SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_BATTERY_SUPPORT_BSOH_SETTINGS" --delete
#   fi
#   SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_SETTINGS_ENABLE_EU_BATTERY_REGULATORY" "TRUE"
#
# ReCoreUI's FF() already no-ops when the tag isn't present, so the explicit
# existence check UN1CA needed isn't necessary here - calling FF with no value
# deletes the tag only if it's currently set.
#
# NOTE: this is standalone from mods/bsoh, which sets
# BATTERY_SUPPORT_BSOH_SETTINGS=TRUE for the Galaxy A23 bug it works around.
# If bsoh is enabled for a given device, that mod will re-add this tag after
# this script deletes it - which is the same order UN1CA itself relied on
# (bsoh's own patch runs its FF call after this deletion), so no changes were
# needed here to accommodate that.

FF "BATTERY_SUPPORT_BSOH_SETTINGS"
FF "SETTINGS_ENABLE_EU_BATTERY_REGULATORY" "TRUE"
