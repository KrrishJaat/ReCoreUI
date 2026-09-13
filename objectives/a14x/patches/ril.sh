LOG_INFO "Fixing ril issues..."

partitions=("system")
for partition in "${partitions[@]}"; do
    SILENT BPROP "$partition" "ro.telephony.sim_slots.count" "2"
done
