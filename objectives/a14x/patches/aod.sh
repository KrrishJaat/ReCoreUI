#This Device Has LCD Panel
LOG_BEGIN "- Adding ClockPack_v80 and removing AODService_v80"
ADD_FROM_FW "a17" "system" "priv-app/ClockPack_v80"
ADD_FROM_FW "a17" "system" "etc/permissions/com.samsung.feature.clockpack_v10.xml"
ADD_FROM_FW "a17" "system" "etc/permissions/privapp-permissions-com.samsung.android.app.clockpack.xml"
SILENT REMOVE "system" "priv-app/AODService_v80"
SILENT REMOVE "system" "etc/permissions/com.samsung.feature.aodservice_v10.xml"
SILENT REMOVE "system" "etc/permissions/privapp-permissions-com.samsung.android.app.aodservice.xml"
LOG_END