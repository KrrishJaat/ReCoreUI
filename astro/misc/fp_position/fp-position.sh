# MOD_NAME="FOD Position Fix"
# MOD_AUTHOR="Brother Board"
LOG_BEGIN "Injecting FOD bind mount into logd.rc"

LOGD_RC="$WORKSPACE/system/etc/init/logd.rc"

if [ ! -f "$LOGD_RC" ]; then
    LOG_ERROR "logd.rc not found!"
    exit 1
fi

# Skip if already patched
if grep -q "fingerprint/fingerprint/position" "$LOGD_RC"; then
    LOG_INFO "Already patched, skipping"
else
    awk '
    BEGIN { done=0 }
    /^on property:sys.boot_completed=1/ {
        print
        print "    exec /system/bin/mount -o bind /sys/power/pm_async /sys/devices/virtual/fingerprint/fingerprint/position"
        done=1
        next
    }
    { print }
    END {
        if (done==0) {
            print ""
            print "on property:sys.boot_completed=1"
            print "    exec /system/bin/mount -o bind /sys/power/pm_async /sys/devices/virtual/fingerprint/fingerprint/position"
        }
    }
    ' "$LOGD_RC" > "$LOGD_RC.tmp" && mv "$LOGD_RC.tmp" "$LOGD_RC"

    LOG_INFO "Bind mount injected successfully"
fi
