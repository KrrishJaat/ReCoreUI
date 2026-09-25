#This Device Has LCD Panel
LOG_BEGIN "- Adding ClockPack_v80 and removing AODService_v80"
ADD_FROM_FW "a17" "system" "priv-app/ClockPack_v80"
SILENT REMOVE "system" "priv-app/AODService_v80"
LOG_END