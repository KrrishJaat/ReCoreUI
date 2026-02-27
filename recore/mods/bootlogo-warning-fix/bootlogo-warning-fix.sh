#!/bin/bash

if [ -z "$SCRPATH" ]; then
    SCRPATH="$(cd "$(dirname "$0")" && pwd)"
fi

PROJECT_ROOT="$(cd "$SCRPATH/../../../" && pwd)"

SRC_FILE="$SCRPATH/param/up_param.bin"
OUT_DIR="$PROJECT_ROOT/out"

if [ ! -f "$SRC_FILE" ]; then
    echo "up_param.bin not found in $SCRPATH/param"
    exit 0
fi

mkdir -p "$OUT_DIR"
cp -f "$SRC_FILE" "$OUT_DIR/up_param.bin"
chmod 0644 "$OUT_DIR/up_param.bin"