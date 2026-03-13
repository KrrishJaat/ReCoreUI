#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Correct path
PARAM_DIR="$SCRIPT_DIR/blobs/param"

DEST_DIR="$OUT"

# fallback if OUT not defined
if [ -z "$DEST_DIR" ]; then
    DEST_DIR="$SCRIPT_DIR/out"
fi

mkdir -p "$DEST_DIR"

if [ "$DEVICE_SINGLE_SYSTEM_IMAGE" = "essi" ]; then
    SRC_FILE="$PARAM_DIR/up_param_1080p.bin"
elif [ "$DEVICE_SINGLE_SYSTEM_IMAGE" = "essi64" ]; then
    SRC_FILE="$PARAM_DIR/up_param_1440p.bin"
else
    SRC_FILE="$PARAM_DIR/up_param_1080p.bin"
fi

echo "Looking for: $SRC_FILE"

if [ -f "$SRC_FILE" ]; then
    echo "Copying $(basename "$SRC_FILE") to $DEST_DIR"
    cp -f "$SRC_FILE" "$DEST_DIR/"
else
    echo "Error: $SRC_FILE not found!"
    exit 1
fi