if [ "$DEVICE_FINGERPRINT_SENSOR_TYPE" == "capacitive_powerkey_phone" ]; then

LOG_BEGIN "Adding side fingerprint support"
    FF "BIOAUTH_CONFIG_FINGERPRINT_FEATURES" "capacitive_powerkey_phone"

    ADD_FROM_FW "a17" "system" "priv-app/BiometricSetting"
    
    ADD_PATCH "framework.jar" \
        "$SCRPATH/framework.jar/Add-Side-Fingerprint-Support.sh"
    ADD_PATCH "services.jar" \
        "$SCRPATH/services.jar/Add-Side-Fingerprint-Support.sh"
LOG_END

fi