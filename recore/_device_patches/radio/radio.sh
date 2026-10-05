# ==============================================================================
#
# MOD_NAME="FM Radio"
# MOD_DESC="Adds FM Radio support (HybridRadio app + libs)."
#
# ==============================================================================

# GET_GALAXY_STORE_DOWNLOAD_URL "<package name/id>"
# Returns a URL to download the desired app from Samsung servers.
# Defined here only if the framework doesn't already provide it.
if ! declare -F GET_GALAXY_STORE_DOWNLOAD_URL >/dev/null; then
GET_GALAXY_STORE_DOWNLOAD_URL()
{
    if [[ -z "$1" ]]; then
        LOG_INFO "GET_GALAXY_STORE_DOWNLOAD_URL: PACKAGE parameter is empty"
        return 1
    fi

    local PACKAGE="$1"
    local DEVICES
    local OS
    local ONEUI
    local SYSTEMID
    local PROTOCOL

    # Galaxy S25 Ultra EUR_OPENX
    # Galaxy S22 Ultra GBL_OPENX
    # Galaxy S25 Ultra KOR_SINGLEX
    DEVICES=("SM-S938B" "SM-S901E" "SM-S938N")

    OS="$(GET_PROP "system" "ro.build.version.sdk")"
    ONEUI="$(GET_PROP "system" "ro.build.version.oneui")"
    SYSTEMID="$(date "+%s")"

    if [ ! "$OS" ]; then
        # Fallback to Android 16
        OS="36"
    fi
    if [ ! "$ONEUI" ]; then
        # Fallback to One UI 8.5
        ONEUI="80500"
    fi

    PROTOCOL+="<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>"
    PROTOCOL+="<SamsungProtocol networkType=\"0\" openApiVersion=\"$OS\" deviceModel=\"DEVICE\""
    PROTOCOL+=" mcc=\"262\" mnc=\"01\" csc=\"EUX\" version=\"7.7\" systemId=\"$SYSTEMID\""
    PROTOCOL+=" deviceFeature=\"locale=en_GB||abi32=armeabi-v7a:armeabi||abi64=arm64-v8a||oneUiVersion=$ONEUI\">"
    PROTOCOL+="<request id=\"2303\" numParam=\"2\">"
    PROTOCOL+="<param name=\"stduk\">0</param>"
    PROTOCOL+="<param name=\"productID\">PRODUCTID</param>"
    PROTOCOL+="</request>"
    PROTOCOL+="</SamsungProtocol>"

    local OUT
    local REQUEST
    for i in "${DEVICES[@]}"; do
        if [[ "$PACKAGE" =~ ^[+-]?[0-9]+$ ]]; then
            OUT="$PACKAGE"
        else
            OUT="$(curl -L -s "https://vas.samsungapps.com/stub/stubUpdateCheck.as?appId=$PACKAGE&versionCode=0&deviceId=$i&mcc=262&mnc=01&csc=EUX&sdkVer=$OS&oneUiVersion=$ONEUI&systemId=$SYSTEMID")"
            OUT="$(grep -o -P "(?<=<productId>)[^<]+" <<< "$OUT")"
            if [ ! "$OUT" ]; then
                continue
            fi
        fi

        REQUEST="$PROTOCOL"
        REQUEST="${REQUEST//DEVICE/$i}"
        REQUEST="${REQUEST//PRODUCTID/$OUT}"

        OUT="$(curl -L -s "https://uk-odc.samsungapps.com/ods.as" -H "Content-Type: text/plain" -d "$REQUEST")"
        OUT="$(grep -o -P "(?<=<value name=\"downLoadURI\">)[^<]+" <<< "$OUT")"
        if [ "$OUT" ]; then
            echo "${OUT//amp;/}"
            return 0
        fi
    done

    LOG_INFO "No download URI found for app \"$PACKAGE\""
    return 1
}
fi

# ------------------------------------------------------------------------------

# Skip if the device has no FM radio chip
if [[ "$(GET_FF_VAL "stock" "SEC_FLOATING_FEATURE_FMRADIO_CONFIG_CHIP_VENDOR")" == "0" ]]; then
    LOG_INFO "FM Radio: nothing to do"
    return 0
fi

# Without an external radio chipset the device needs libfmradio_jni.so
if [[ -z "$(GET_FF_VAL "stock" "SEC_FLOATING_FEATURE_FMRADIO_SUPPORT_EXTERNAL_RADIO_CHIPSET")" ]]; then
    if [[ ! -f "$WORKSPACE/system/system/lib64/libfmradio_jni.so" ]]; then
        LOG_INFO "SEC_FLOATING_FEATURE_FMRADIO_SUPPORT_EXTERNAL_RADIO_CHIPSET is not set but libfmradio_jni.so is missing in system/lib64 - skipping FM Radio"
        return 0
    fi
fi

LOG_BEGIN "Adding FM Radio"

# Resolve the app URL first so nothing is added if the lookup fails
FM_URL="$(GET_GALAXY_STORE_DOWNLOAD_URL "com.sec.android.app.fm")"
if [[ -z "$FM_URL" ]]; then
    LOG_INFO "Could not get FM Radio download URL - skipping FM Radio"
    return 0
fi

FM_DIR="$WORKSPACE/system/system/priv-app/HybridRadio"
mkdir -p "$FM_DIR"

LOG_INFO "Downloading latest FM Radio app"
if ! curl -L -s -f -o "$FM_DIR/HybridRadio.apk" "$FM_URL" || [[ ! -s "$FM_DIR/HybridRadio.apk" ]]; then
    LOG_INFO "FM Radio download failed - skipping FM Radio"
    rm -rf "$FM_DIR"
    return 0
fi

ADD_FROM_FW "a17" "system" "etc/permissions/com.samsung.wrappers.libFmRadioImpl.FmRadio.xml"
ADD_FROM_FW "a17" "system" "etc/permissions/privapp-permissions-com.sec.android.app.fm.xml"
ADD_FROM_FW "a17" "system" "etc/permissions/signature-permissions-com.sec.android.app.fm.xml"
ADD_FROM_FW "a17" "system" "etc/sysconfig/preinstalled-packages-com.sec.android.app.fm.xml"
ADD_FROM_FW "a17" "system" "framework/samsungfmradiolib.jar"

SET_METADATA "system" "system/priv-app/HybridRadio" 0 0 755 "u:object_r:system_file:s0"
SET_METADATA "system" "system/priv-app/HybridRadio/HybridRadio.apk" 0 0 644 "u:object_r:system_file:s0"

LOG_END "FM Radio added"