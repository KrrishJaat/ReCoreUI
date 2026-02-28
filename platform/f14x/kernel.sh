[ -f "$SCRPATH/img/vendor_boot.img" ] || ERROR_EXIT "vendor_boot.img not found"
[ -f "$SCRPATH/img/vbmeta.img" ] || ERROR_EXIT "vbmeta.img not found"
[ -f "$SCRPATH/img/boot.img" ] || ERROR_EXIT "boot.img not found"
[ -f "$SCRPATH/img/dtbo.img" ] || ERROR_EXIT "dtbo.img not found"

mkdir -p "$DIROUT" && cp -f "$SCRPATH/img/vendor_boot.img" "$SCRPATH/img/boot.img" "$SCRPATH/img/vbmeta.img" "$SCRPATH/img/dtbo.img" "$DIROUT/"
