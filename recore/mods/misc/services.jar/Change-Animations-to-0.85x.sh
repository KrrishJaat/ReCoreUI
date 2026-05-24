if grep -q "const/high16 v4, 0x3f800000" "$WMS_SMALI"; then
    REPLACE_LINE \
        "const/high16 v4, 0x3f800000" \
        "const v4, 0x3f59999a    # 0.85f" \
        "$WMS_SMALI"
else
    echo "⚠ Animation scale line not found, skipping patch"
fi