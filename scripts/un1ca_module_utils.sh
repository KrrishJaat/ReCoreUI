#!/usr/bin/env bash
# ReCoreUI compatibility layer for stock UN1CA Magisk-style modules.
# Loaded automatically by root build.sh because it lives under scripts/.

_UN1CA_SELF_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_UN1CA_PREBUILTS="${PREBUILTS:-${RECOREUI:-$(cd "$_UN1CA_SELF_DIR/.." && pwd)}/prebuilts}"
_UN1CA_PATCHER="$_UN1CA_PREBUILTS/smalipatch/un1ca_patch.py"
_UN1CA_SMALI_COMPAT="$_UN1CA_SELF_DIR/un1ca_smali_compat.py"

# Capture native ReCoreUI GET_PROP once, before the UN1CA one-argument wrapper
# is installed. This avoids recursive self-wrapping on repeated module calls.
if declare -f GET_PROP >/dev/null 2>&1 && ! declare -f _RECORE_NATIVE_GET_PROP >/dev/null 2>&1; then
    eval "$(declare -f GET_PROP | sed '1s/^GET_PROP /_RECORE_NATIVE_GET_PROP /')"
fi

_UN1CA_VALID_PARTITION() {
    case "$1" in system|system_ext|product|vendor|odm|vendor_dlkm|odm_dlkm|system_dlkm|optics|prism) return 0;; *) return 1;; esac
}

_UN1CA_LOG() {
    if declare -f LOG >/dev/null 2>&1; then LOG "$*"; else printf '%s\n' "$*"; fi
}

_UN1CA_PARTITION_PATH() {
    local p="$1"
    if declare -f GET_PARTITION_PATH >/dev/null 2>&1; then GET_PARTITION_PATH "$p"; return $?; fi
    case "$p" in system) printf '%s/system/system\n' "$WORKSPACE";; *) printf '%s/%s\n' "$WORKSPACE" "$p";; esac
}

_READ_MODULE_PROP() {
    local f="$1"; MOD_ID=""; MOD_NAME=""; MOD_AUTHOR=""; MOD_DESC=""
    [[ -f "$f" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        case "$line" in
            id=*) MOD_ID="${line#id=}";; name=*) MOD_NAME="${line#name=}";;
            author=*) MOD_AUTHOR="${line#author=}";; description=*) MOD_DESC="${line#description=}";;
        esac
    done < "$f"
}

_UN1CA_MERGE_CONFIG() {
    local mod="$1" cfgdir="${CONFIG_DIR:-$WORKSPACE/config}" src name target line key
    mkdir -p "$cfgdir"
    for src in "$mod"/file_context-* "$mod"/fs_config-*; do
        [[ -f "$src" ]] || continue
        name=$(basename "$src")
        case "$name" in file_context-*) target="${name/file_context-/}_file_contexts";; fs_config-*) target="${name/fs_config-/}_fs_config";; esac
        [[ -n "$target" ]] || continue
        if [[ ! -f "$cfgdir/$target" ]]; then cp -a "$src" "$cfgdir/$target"; continue; fi
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"; [[ -z "$line" || "$line" == \#* ]] && continue
            key="${line%%[[:space:]]*}"; [[ -z "$key" ]] && continue
            sed -i "\\|^${key}[[:space:]]|d" "$cfgdir/$target"
            printf '%s\n' "$line" >> "$cfgdir/$target"
        done < "$src"
    done
}

_APPLY_MODULE_PAYLOAD() {
    local mod="$1" p src dst
    for p in system system_ext product vendor odm vendor_dlkm odm_dlkm system_dlkm; do
        src="$mod/$p"; [[ -d "$src" ]] || continue
        dst="$(_UN1CA_PARTITION_PATH "$p")" || return 1
        [[ -d "$dst" ]] || mkdir -p "$dst"
        rsync -a --no-links "$src/" "$dst/" || return 1
    done
}

_READ_AND_APPLY_MODULE_PROPS() {
    local mod="$1" f part line key value
    while IFS= read -r -d '' f; do
        [[ "$(basename "$f")" == "module.prop" ]] && continue
        part="$(basename "$f" .prop)"
        _UN1CA_VALID_PARTITION "$part" || continue
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            [[ -z "$line" || "$line" == \#* ]] && continue
            [[ "$line" == *=* ]] || { printf 'UN1CA: malformed property in %s: %s\n' "$f" "$line" >&2; return 1; }
            key="${line%%=*}"; value="${line#*=}"
            if [[ -z "$value" ]]; then SET_PROP "$part" "$key" --delete; else SET_PROP "$part" "$key" "$value"; fi
        done < "$f"
    done < <(find "$mod" -maxdepth 1 -type f -name '*.prop' -print0)
}

_UN1CA_VIRTUAL_TARGET() {
    local part="$1" file="$2" root="$WORKSPACE/.un1ca_apktool" real link rel
    while [[ "$file" == /* ]]; do file="${file#/}"; done
    [[ "$part" == system ]] && file="${file#system/}"
    real="${WORKSPACE}/${part}/${file}"
    # Virtual UN1CA target points at ReCoreUI's decoded worktree, not the APK/JAR file.
    if [[ "$part" == system ]]; then real="${WORKSPACE}/system/system/${file}"; fi
    real="$(dirname "$real")/$(basename "$real")_decompiled"
    link="$root/$part/$file"
    [[ -d "$real" ]] || return 1
    mkdir -p "$(dirname "$link")"
    rm -rf "$link"
    ln -s "$real" "$link"
    printf '%s\n' "$link"
}

DECODE_APK() {
    local part="$1" file="$2" target rel worktree
    while [[ "$file" == /* ]]; do file="${file#/}"; done
    target="$file"; [[ "$part" == system ]] && target="${file#system/}"
    if [[ "$part" == system ]]; then rel="system/system/$target"; else rel="$part/$target"; fi
    # FIND_TARGET accepts the same relative workspace path used by apktool.sh.
    local target_file=""
    if declare -f FIND_TARGET >/dev/null 2>&1; then target_file="$(FIND_TARGET "$(basename "$target")" 2>/dev/null || true)"; fi
    if [[ -z "$target_file" ]]; then target_file="$WORKSPACE/$rel"; fi
    worktree="$(dirname "$target_file")/$(basename "$target")_decompiled"
    if [[ ! -d "$worktree" ]]; then
        DECOMPILE "${target_file#$WORKSPACE/}" || return 1
    fi
    mkdir -p "$WORKSPACE/.un1ca_apktool"
    _UN1CA_VIRTUAL_TARGET "$part" "$file" >/dev/null || return 1
    APKTOOL_DIR="$WORKSPACE/.un1ca_apktool"; export APKTOOL_DIR
}

GET_PROP() {
    if [[ $# -eq 1 ]]; then
        if declare -f _RECORE_NATIVE_GET_PROP >/dev/null 2>&1; then _RECORE_NATIVE_GET_PROP system "$1"; else return 1; fi
    else
        _RECORE_NATIVE_GET_PROP "$@"
    fi
}

SET_PROP() {
    local part="$1" key="$2" val="${3:-}"
    if [[ "$val" == "--delete" || "$val" == "-d" ]]; then val=""; fi
    if declare -f BPROP >/dev/null 2>&1; then BPROP "$part" "$key" "$val"; return $?; fi
    return 1
}

GET_FLOATING_FEATURE_CONFIG() {
    local file config
    if [[ $# -eq 1 ]]; then file="$WORKSPACE/system/system/etc/floating_feature.xml"; config="$1"; else file="$1"; config="$2"; fi
    [[ -f "$file" ]] || return 1
    grep -o -P "(?<=<${config}>)[^<]+" "$file" 2>/dev/null || true
}

SMALI_PATCH() {
    local part="$1" file="$2" smali="$3" op="$4"
    [[ -n "$part" && -n "$file" && -n "$smali" && -n "$op" ]] || return 1
    _UN1CA_VALID_PARTITION "$part" || return 1
    DECODE_APK "$part" "$file" || return 1
    local relfile="$file"
    [[ "$part" == system ]] && relfile="${file#system/}"
    local fp="$APKTOOL_DIR/$part/$relfile/$smali"
    [[ -f "$fp" ]] || { printf 'UN1CA: smali not found: %s\n' "$fp" >&2; return 1; }
    case "$op" in
        remove)
            local cls="${smali%.smali}" used
            used=$(find "$(dirname "$fp")" -type f ! -path "$fp" -exec grep -l -- "${cls##*/};" {} + 2>/dev/null || true)
            [[ -z "$used" ]] || { printf 'UN1CA: refusing to remove used smali %s\n' "$smali" >&2; return 1; }
            rm -f -- "$fp";;
        replaceall) python3 "$_UN1CA_SMALI_COMPAT" replaceall "$fp" __ALL__ "$5" "$6";;
        replace) python3 "$_UN1CA_SMALI_COMPAT" replace "$fp" "$5" "$6" "$7";;
        return|null|strip) python3 "$_UN1CA_SMALI_COMPAT" "$op" "$fp" "$5" "${6:-}";;
        *) printf 'UN1CA: invalid SMALI_PATCH operation: %s\n' "$op" >&2; return 1;;
    esac
}

SET_FLOATING_FEATURE_CONFIG() {
    local config="$1" value="$2" file="${3:-$WORKSPACE/system/system/etc/floating_feature.xml}"
    [[ -f "$file" ]] || return 1
    if grep -q "<${config}>" "$file"; then
        if [[ "$value" == "--delete" || "$value" == "-d" ]]; then sed -i "/<${config}>/d" "$file"; else sed -i "s|<${config}>[^<]*</${config}>|<${config}>${value}</${config}>|" "$file"; fi
    elif [[ "$value" != "--delete" && "$value" != "-d" ]]; then
        sed -i '/<\/SecFloatingFeatureSet>/d' "$file"
        grep -q 'Added by scripts' "$file" || printf '%s\n' '    <!-- Added by scripts/utils/module_utils.sh -->' >> "$file"
        printf '    <%s>%s</%s>\n</SecFloatingFeatureSet>\n' "$config" "$value" "$config" >> "$file"
    fi
}

EVAL() { eval -- "$*"; }
LOG_STEP_IN() { if declare -f LOG_BEGIN >/dev/null 2>&1; then LOG_BEGIN "$*"; else _UN1CA_LOG "$*"; fi; }
LOG_STEP_OUT() { if declare -f LOG_END >/dev/null 2>&1; then LOG_END "$*"; fi; }

_APPLY_MODULE_SMALI_PATCHES() {
    local mod="$1" f rel part target_rel target_name tf wd
    [[ -d "$mod/smali" ]] || return 0
    while IFS= read -r -d '' f; do
        rel="${f#$mod/smali/}"
        part="${rel%%/*}"
        _UN1CA_VALID_PARTITION "$part" || { printf 'UN1CA: invalid partition %s\n' "$part" >&2; return 1; }
        target_rel="${rel#*/}"
        target_rel="${target_rel%/*}"
        target_name="$(basename "$target_rel")"
        [[ "$target_name" == *.apk || "$target_name" == *.jar ]] || continue
        tf=""
        declare -f FIND_TARGET >/dev/null 2>&1 && tf="$(FIND_TARGET "$target_name" 2>/dev/null || true)"
        [[ -n "$tf" ]] || continue
        wd="$(dirname "$tf")/${target_name}_decompiled"
        [[ -d "$wd" ]] || { DECOMPILE "${tf#$WORKSPACE/}" || return 1; }
        if [[ "$f" == *.patch ]]; then
            [[ -f "$_UN1CA_PATCHER" ]] || return 1
            python3 "$_UN1CA_PATCHER" "$wd" "$f" || return 1
        else
            [[ -f "$_UN1CA_PREBUILTS/smalipatch/smali_patch.py" ]] || return 1
            python3 "$_UN1CA_PREBUILTS/smalipatch/smali_patch.py" "$wd" "$f" || return 1
        fi
    done < <(find "$mod/smali" -type f \( -name '*.patch' -o -name '*.smalipatch' \) -print0 | sort -z)
}

_IS_IN_RECOREUI_MODULE() {
    local file="$1" layer="$2" d
    d="$(dirname "$file")"
    while [[ "$d" != "$layer" && "$d" != / ]]; do
        [[ -f "$d/module.prop" ]] && return 0
        d="$(dirname "$d")"
    done
    return 1
}

_APPLY_RECOREUI_MODULE() {
    local mod="$1"
    [[ -d "$mod" && -f "$mod/module.prop" ]] || return 1
    [[ -f "$mod/disable" ]] && return 0
    # A module may be discovered more than once (or customize.sh may be
    # sourced repeatedly during testing). Skip an exact repeat in this
    # workspace, while allowing changed module contents to run again.
    local module_fingerprint marker_dir marker
    module_fingerprint="$( { printf '%s\n' "$mod"; find "$mod" -type f -not -path '*/.un1ca_apktool/*' -print0 | sort -z | xargs -0 -r sha256sum; } | sha256sum | cut -d' ' -f1 )"
    marker_dir="$WORKSPACE/.un1ca_modules"
    marker="$marker_dir/$module_fingerprint"
    [[ -f "$marker" ]] && return 0
    _READ_MODULE_PROP "$mod/module.prop"
    _UN1CA_LOG "[UN1CA] Processing ${MOD_NAME:-$(basename "$mod")}${MOD_AUTHOR:+ by $MOD_AUTHOR}"
    export MODPATH="$mod" MODULE_PATH="$mod" ZIPFILE="$mod" TMPDIR="${TMPDIR:-$WORKSPACE/.tmp}" WORK_DIR="$WORKSPACE"
    mkdir -p "$TMPDIR" "$WORKSPACE/.un1ca_apktool"
    if ! grep -Eq '^SKIPUNZIP=1\r?$' "$mod/customize.sh" 2>/dev/null; then _APPLY_MODULE_PAYLOAD "$mod" || return 1; fi
    _UN1CA_MERGE_CONFIG "$mod"
    _READ_AND_APPLY_MODULE_PROPS "$mod" || return 1
    if [[ -f "$mod/customize.sh" ]]; then
        _UN1CA_COMPAT_INIT
        source "$mod/customize.sh" || return 1
    fi
    _APPLY_MODULE_SMALI_PATCHES "$mod" || return 1
    mkdir -p "$marker_dir"
    : > "$marker"
    return 0
}

_UN1CA_COMPAT_INIT() {
    mkdir -p "$WORKSPACE/.un1ca_apktool"
    APKTOOL_DIR="$WORKSPACE/.un1ca_apktool"; export APKTOOL_DIR
}

PROCESS_RECOREUI_MODULES() {
    local layer="$1" mod
    [[ -d "$layer" ]] || return 0
    while IFS= read -r -d '' mod; do _APPLY_RECOREUI_MODULE "$mod" || return 1; done < <(find "$layer" -mindepth 1 -maxdepth 1 -type d -exec test -f '{}/module.prop' \; -print0 | LC_ALL=C sort -z)
}
