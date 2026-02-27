if ! GET_FEATURE DEVICE_USE_STOCK_BASE; then

    SYSROOT="$WORKSPACE/system/system"
    SRCROOT="$BLOBS/pa3q/system/system"

    ############################################
    # CASE 1: Both Source and Device HAVE eSIM
    ############################################
    if GET_FEATURE SOURCE_HAVE_ESIM_SUPPORT && \
       GET_FEATURE DEVICE_HAVE_ESIM_SUPPORT; then

        LOG_END "Both source and device support eSIM — skipping"

    ############################################
    # CASE 2: Both Source and Device DO NOT HAVE eSIM
    ############################################
    elif ! GET_FEATURE SOURCE_HAVE_ESIM_SUPPORT && \
         ! GET_FEATURE DEVICE_HAVE_ESIM_SUPPORT; then

        LOG_END "Neither source nor device supports eSIM — skipping"

    ############################################
    # CASE 3: Source HAS eSIM but Device DOES NOT
    ############################################
    elif GET_FEATURE SOURCE_HAVE_ESIM_SUPPORT && \
         ! GET_FEATURE DEVICE_HAVE_ESIM_SUPPORT; then

        LOG_BEGIN "Source has eSIM but device does NOT — removing all eSIM blobs"

        # Remove apps
        rm -rf "$SYSROOT/priv-app/EsimClient"
        rm -rf "$SYSROOT/priv-app/EsimKeyString"
        rm -rf "$SYSROOT/priv-app/EuiccService"

        # Remove permission XMLs
        rm -f "$SYSROOT/etc/permissions/privapp-permissions-com.samsung.android.app.esimkeystring.xml"
        rm -f "$SYSROOT/etc/permissions/privapp-permissions-com.samsung.euicc.xml"
        rm -f "$SYSROOT/etc/permissions/privapp-permissions-com.samsung.euicc.mep.xml"
        rm -f "$SYSROOT/etc/permissions/privapp-permissions-com.samsung.android.app.telephonyui.esimclient.xml"

        # Remove sysconfig XMLs
        rm -f "$SYSROOT/etc/sysconfig/preinstalled-packages-com.samsung.android.app.esimkeystring.xml"
        rm -f "$SYSROOT/etc/sysconfig/preinstalled-packages-com.samsung.euicc.xml"

        # Disable embedded SIM feature
        FF "COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH" ""

        LOG_END "All eSIM blobs removed"

    ############################################
    # CASE 4: Source DOES NOT HAVE eSIM but Device HAS
    ############################################
    elif ! GET_FEATURE SOURCE_HAVE_ESIM_SUPPORT && \
         GET_FEATURE DEVICE_HAVE_ESIM_SUPPORT; then

        LOG_BEGIN "Device supports eSIM but source does NOT — adding blobs from pa3q"

        # Add apps
        cp -a "$SRCROOT/priv-app/EsimClient" "$SYSROOT/"
        cp -a "$SRCROOT/priv-app/EsimKeyString" "$SYSROOT/"
        cp -a "$SRCROOT/priv-app/EuiccService" "$SYSROOT/"

        # Add permission XMLs
        cp -a "$SRCROOT/etc/permissions/privapp-permissions-com.samsung.android.app.esimkeystring.xml" \
              "$SYSROOT/etc/permissions/"

        cp -a "$SRCROOT/etc/permissions/privapp-permissions-com.samsung.euicc.xml" \
              "$SYSROOT/etc/permissions/"

        cp -a "$SRCROOT/etc/permissions/privapp-permissions-com.samsung.euicc.mep.xml" \
              "$SYSROOT/etc/permissions/"

        cp -a "$SRCROOT/etc/permissions/privapp-permissions-com.samsung.android.app.telephonyui.esimclient.xml" \
              "$SYSROOT/etc/permissions/"

        # Add sysconfig XMLs
        cp -a "$SRCROOT/etc/sysconfig/preinstalled-packages-com.samsung.android.app.esimkeystring.xml" \
              "$SYSROOT/etc/sysconfig/"

        cp -a "$SRCROOT/etc/sysconfig/preinstalled-packages-com.samsung.euicc.xml" \
              "$SYSROOT/etc/sysconfig/"

        FF_IF_DIFF "stock" "COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH"

        LOG_END "eSIM blobs added from pa3q"

    fi

fi