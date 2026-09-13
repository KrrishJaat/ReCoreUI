#!/bin/bash

# ==========================================================
# Remove AVB flags from selected fstab partitions
# ==========================================================

LOG_BEGIN "Removing AVB flags from fstab"

while IFS= read -r -d '' FSTAB; do
    LOG_INFO "Patching $(basename "$FSTAB")"
    sed -i -E \
        '/^[[:space:]]*(system|vendor|system_dlkm|vendor_dlkm|product|odm)[[:space:]]/ s/,avb//g' \
        "$FSTAB"

done < <(
    find "$WORKSPACE/vendor/etc" \
        -type f \
        -name "fstab*" \
        -print0
)
