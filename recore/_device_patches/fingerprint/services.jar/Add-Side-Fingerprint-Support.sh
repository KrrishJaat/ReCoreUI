find . -type f -name "*.smali" -exec \
    sed -i -E "s|FP_FEATURE_SENSOR_IS_OPTICAL|FP_FEATURE_SENSOR_IS_SIDE|g" {} +