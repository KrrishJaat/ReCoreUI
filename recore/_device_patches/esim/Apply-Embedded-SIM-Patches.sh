if ! GET_FEATURE DEVICE_USE_STOCK_BASE; then
    SOURCE_ESIM=false
    DEVICE_ESIM=false
    GET_FEATURE SOURCE_HAVE_ESIM_SUPPORT && SOURCE_ESIM=true
    GET_FEATURE DEVICE_HAVE_ESIM_SUPPORT && DEVICE_ESIM=true

    # Paths relative to system/system
    ESIM_PATHS=(
        "etc/permissions/privapp-permissions-com.samsung.android.app.esimkeystring.xml"
        "etc/permissions/privapp-permissions-com.samsung.euicc.xml"
        "etc/sysconfig/preinstalled-packages-com.samsung.android.app.esimkeystring.xml"
        "etc/sysconfig/preinstalled-packages-com.samsung.euicc.xml"
        "priv-app/EsimKeyString"
        "priv-app/EuiccService"
    )

    if [[ "$SOURCE_ESIM" == true && "$DEVICE_ESIM" == false ]]; then
        # Source has eSIM, device doesn't -> remove blobs
        LOG_BEGIN "Device does NOT support eSIM, removing blobs"

        for P in "${ESIM_PATHS[@]}"; do
            rm -rf "$WORKSPACE/system/system/$P"
        done

        # Verify nothing was left behind
        for P in "${ESIM_PATHS[@]}"; do
            [[ -e "$WORKSPACE/system/system/$P" ]] && LOG_INFO "Could not remove: $P"
        done

        FF "COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH" ""
        LOG_END "eSIM blobs removed"

    elif [[ "$SOURCE_ESIM" == false && "$DEVICE_ESIM" == true ]]; then
        # Source lacks eSIM, device has it -> add blobs
        LOG_BEGIN "Device supports eSIM, adding blobs"

        for P in "${ESIM_PATHS[@]}"; do
            ADD_FROM_FW "extra" "system" "$P"
        done

        FF_IF_DIFF "stock" "COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH"
        LOG_END "eSIM blobs added"

    else
        # Both have it, or neither has it
        LOG_INFO "No eSIM changes required"
    fi
fi