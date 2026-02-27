# Galaxy M35 5G config
CODENAME="m35x"
PLATFORM="ex_1380"

# Stock firmware details for download
STOCK_MODEL="SM-M356B"
STOCK_CSC="INS"
STOCK_IMEI="350967550447763"

# Source firmware details for download
MODEL="SM-S711B"
CSC="INS"
IMEI="350411870309841"

# Extra firmware (Optional) details for download
EXTRA_MODEL=""
EXTRA_CSC=""
EXTRA_IMEI=""

# Output
FILESYSTEM="erofs"


#
# The following values are auto genarated by auto_gen.sh.
# Manually uncomment and set values here to override default stock values.
#

###
DEVICE_MODEL_NAME="Galaxy M35 5G"                          # Brand name from settings config
DEVICE_SIOP_POLICY_FILENAME="siop_m35x_s5e8835"                # Thermal/SIOP policy filename
DEVICE_USE_STOCK_BASE="false"
RECORE_CODENAME="monster35"

### Display
DEVICE_DISPLAY_HFR_MODE="2"                   # High Frame Rate Mode (0=60Hz)
DEVICE_HAVE_HIGH_REFRESH_RATE="true"              # Device have high refresh rate or not
DEVICE_DISPLAY_REFRESH_RATE_VALUES_HZ="60,120"      # Supported rates by display (e.g., 60,120)
DEVICE_DEFAULT_REFRESH_RATE="120"                # Initial boot refresh rate
DEVICE_HAVE_QHD_PANEL="false"                      # True if QHD display device
DEVICE_HAVE_AMOLED_DISPLAY="true"                 # True if amoled display device
DEVICE_AUTO_BRIGHTNESS_LEVEL="2"               # Light sensor behavior
DEVICE_MDNIE_MODE="0"                          # Samsung mDnie color profile

###
SOURCE_HAVE_ESIM_SUPPORT="true"
DEVICE_HAVE_ESIM_SUPPORT="false"

### Audio
DEVICE_HAVE_DUAL_SPEAKER="true"                   # true for Stereo, false for Mono

### Extra features
DEVICE_HAVE_SPEN_SUPPORT="false"                   # Device have SPen support
DEVICE_HAVE_ESIM_SUPPORT="false"                   # Device have esim support
DEVICE_HAVE_NPU="false"                            # Device have NPU

### Build Properties
DEVICE_FIRST_API_VERSION="13"                   # ro.vendor.build.version.release
DEVICE_FIRST_SDK_VERSION="33"                   # ro.vendor.build.version.sdk
DEVICE_VNDK_VERSION="33"                      # VNDK version
DEVICE_SINGLE_SYSTEM_IMAGE="essi"                 # ro.product.system.device

### External
DEVICE_FINGERPRINT_SENSOR_TYPE="capacitive_powerkey_phone"             # Biometric sensor type
# DEVICE_HAVE_LEGACY_FACE_HAL=""                # Have legacy Samsung 2.0 biometric face libraries


