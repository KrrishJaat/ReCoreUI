if ! GET_FEATURE DEVICE_USE_STOCK_BASE; then
    SOURCE_ESIM=false
    DEVICE_ESIM=false
    GET_FEATURE SOURCE_HAVE_ESIM_SUPPORT && SOURCE_ESIM=true
    GET_FEATURE DEVICE_HAVE_ESIM_SUPPORT && DEVICE_ESIM=true

    if [[ "$SOURCE_ESIM" == true && "$DEVICE_ESIM" == false ]]; then
        LOG_BEGIN "Device does NOT support eSIM, removing blobs"

        # \( \) grouping is required, otherwise -exec only binds to the last -iname
        find "$WORKSPACE/system/system" \
            \( -iname "*esim*" -o -iname "*euicc*" \) \
            -prune -exec rm -rf {} +

        LEFTOVERS=$(find "$WORKSPACE/system/system" \
            \( -iname "*esim*" -o -iname "*euicc*" \) 2>/dev/null)
        if [[ -n "$LEFTOVERS" ]]; then
            LOG_INFO "Some eSIM files could not be removed:"
            LOG_INFO "$LEFTOVERS"
        fi

        FF "COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH" ""
        LOG_END "eSIM blobs removed"

    elif [[ "$SOURCE_ESIM" == false && "$DEVICE_ESIM" == true ]]; then
        LOG_BEGIN "Device supports eSIM, adding blobs"

        ADD_FROM_FW "extra" "system" "priv-app/EsimKeyString"
        ADD_FROM_FW "extra" "system" "priv-app/EuiccService"

        ADD_FROM_FW "extra" "system" "etc/permissions/privapp-permissions-com.samsung.android.app.esimkeystring.xml"
        ADD_FROM_FW "extra" "system" "etc/permissions/privapp-permissions-com.samsung.euicc.xml"
        ADD_FROM_FW "extra" "system" "etc/sysconfig/preinstalled-packages-com.samsung.android.app.esimkeystring.xml"
        ADD_FROM_FW "extra" "system" "etc/sysconfig/preinstalled-packages-com.samsung.euicc.xml"

        FF_IF_DIFF "stock" "COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH"

        LOG_END "eSIM blobs added"

    else
        LOG_INFO "No eSIM changes required"
    fi
fi