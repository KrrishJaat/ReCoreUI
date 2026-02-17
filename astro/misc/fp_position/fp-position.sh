LOG_BEGIN "Applying Fingerprint Patch"

while IFS= read -r -d '' RCFILE; do
    LOG_INFO "Patching $(basename "$RCFILE")"

    # Skip if already patched
    if grep -q "fingerprint/fingerprint/position" "$RCFILE"; then
        LOG_INFO "Already patched, skipping"
        continue
    fi

    # Insert mount line before start logd-auditctl
    sed -i '/on property:sys.boot_completed=1/,/start logd-auditctl/{
        /start logd-auditctl/i\    exec /system/bin/mount -o bind /sys/power/pm_async /sys/devices/virtual/fingerprint/fingerprint/position
    }' "$RCFILE"

    LOG_INFO "Bind mount injected successfully"

done < <(
    find "$WORKSPACE/system/etc/init" "$WORKSPACE/vendor/etc/init" \
        -type f \
        -name "logd.rc" \
        -print0 2>/dev/null
)
