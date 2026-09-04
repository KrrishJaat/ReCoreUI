# MOD_NAME="ReCoreUI Settings — feature flags"
# MOD_AUTHOR="ported from supplied Settings app mod"

LOG_BEGIN "Configuring ReCoreUI Settings feature flags"

# The source mod removes this legacy flag and enables the EU battery regulatory page.
FF "BATTERY_SUPPORT_BSOH_SETTINGS" ""
FF "SETTINGS_ENABLE_EU_BATTERY_REGULATORY" "TRUE"

LOG_END "ReCoreUI Settings feature flags configured"
