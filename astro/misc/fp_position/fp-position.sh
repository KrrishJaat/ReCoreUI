# MOD_NAME="FOD Position Fix"
# MOD_AUTHOR="Brother Board"

LOG_BEGIN "Injecting FOD bind mount into logd.rc"

while IFS= read -r -d '' RCFILE; do
    LOG_INFO "Patching ${RCFILE#$WORKSPACE/}"

    if grep -q "fingerprint/fingerprint/position" "$RCFILE"; then
        LOG_INFO "Already patched, skipping"
        continue
    fi

    sed -i '/on property:sys.boot_completed=1/ a\    exec /system/bin/mount -o bind /sys/power/pm_async /sys/devices/virtual/fingerprint/fingerprint/position' "$RCFILE"

done < <(
    find "$WORKSPACE/system/system/etc/init" \
        -type f \
        -name "logd.rc" \
        -print0
)
