#!/usr/bin/env bash
# ReCoreUI compatibility layer for stock UN1CA Magisk-style modules.
# Loaded automatically by root build.sh because it lives under scripts/.

_UN1CA_SELF_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_UN1CA_PREBUILTS="${PREBUILTS:-${RECOREUI:-$(cd "$_UN1CA_SELF_DIR/.." && pwd)}/prebuilts}"
_UN1CA_PATCHER="$_UN1CA_PREBUILTS/smalipatch/un1ca_patch.py"
_UN1CA_SMALI_COMPAT="$_UN1CA_SELF_DIR/un1ca_smali_compat.py"

# Capture native ReCoreUI GET_PROP exactly once, before the UN1CA wrapper
# below is installed under the same name. This is what avoids the recursive
# self-wrapping bug: the capture never repeats inside a per-module code path,
# it always renames the ORIGINAL native definition, once, at source time.
if declare -f GET_PROP >/dev/null 2>&1 && ! declare -f _RECORE_NATIVE_GET_PROP >/dev/null 2>&1; then
    eval "$(declare -f GET_PROP | sed '1s/^GET_PROP /_RECORE_NATIVE_GET_PROP /')"
fi

# Exactly the 8 partitions UN1CA's own common_utils.sh:IS_VALID_PARTITION_NAME
# accepts (itself sourced from AOSP's property_service.cpp). Do not add more:
# an accepted-but-wrong partition name silently resolves to a bogus path
# instead of failing loudly, which is worse than rejecting it.
_UN1CA_VALID_PARTITION() {
    case "$1" in
        system|system_ext|product|vendor|odm|vendor_dlkm|odm_dlkm|system_dlkm) return 0;;
        *) return 1;;
    esac
}

# Same order UN1CA's own bare/single-arg GET_PROP searches in (AOSP
# property_service.cpp load order): system, system_ext, system_dlkm, vendor,
# vendor_dlkm, odm_dlkm, odm, product.
_UN1CA_PROP_SEARCH_ORDER=(system system_ext system_dlkm vendor vendor_dlkm odm_dlkm odm product)

_UN1CA_LOG() {
    if declare -f LOG >/dev/null 2>&1; then LOG "$*"; else printf '%s\n' "$*"; fi
}

_UN1CA_PARTITION_PATH() {
    local p="$1"
    if declare -f GET_PARTITION_PATH >/dev/null 2>&1; then GET_PARTITION_PATH "$p"; return $?; fi
    case "$p" in system) printf '%s/system/system\n' "$WORKSPACE";; *) printf '%s/%s\n' "$WORKSPACE" "$p";; esac
}

# Single source of truth for "where does <partition> <file> really live in
# the workspace". UN1CA's own DECODE_APK/SMALI_PATCH strip a literal leading
# "system/" from FILE only when partition is "system" (every other
# partition's FILE is already partition-root-relative) - replicated exactly -
# then all partition placement, including system's "system/system" doubling,
# is delegated to _UN1CA_PARTITION_PATH (-> native GET_PARTITION_PATH) rather
# than hardcoded here a second time. Two independent hardcoded copies of this
# is what let DECODE_APK and the virtual-target resolver drift apart for any
# partition other than system.
_UN1CA_REAL_PATH() {
    local part="$1" file="$2" rel base
    while [[ "$file" == /* ]]; do file="${file#/}"; done
    rel="$file"
    [[ "$part" == system ]] && rel="${file#system/}"
    base="$(_UN1CA_PARTITION_PATH "$part")" || return 1
    printf '%s/%s\n' "$base" "$rel"
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
        target=""
        case "$name" in
            file_context-*) target="${name/file_context-/}_file_contexts";;
            fs_config-*) target="${name/fs_config-/}_fs_config";;
        esac
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
    local mod="$1" p src dst links
    for p in system system_ext product vendor odm vendor_dlkm odm_dlkm system_dlkm; do
        src="$mod/$p"; [[ -d "$src" ]] || continue
        dst="$(_UN1CA_PARTITION_PATH "$p")" || return 1
        [[ -d "$dst" ]] || mkdir -p "$dst"
        links="$(find "$src" -type l 2>/dev/null)"
        [[ -z "$links" ]] || _UN1CA_LOG "UN1CA: warning: module ships symlink(s) under $p/, skipping (not copied): $links"
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
    local part="$1" file="$2" root="$WORKSPACE/.un1ca_apktool" real link
    real="$(_UN1CA_REAL_PATH "$part" "$file")" || return 1
    real="$(dirname "$real")/$(basename "$real")_decompiled"
    while [[ "$file" == /* ]]; do file="${file#/}"; done
    [[ "$part" == system ]] && file="${file#system/}"
    link="$root/$part/$file"
    [[ -d "$real" ]] || return 1
    mkdir -p "$(dirname "$link")"
    rm -rf "$link"
    ln -s "$real" "$link"
    printf '%s\n' "$link"
}

DECODE_APK() {
    local part="$1" file="$2" target_file worktree
    _UN1CA_VALID_PARTITION "$part" || return 1
    target_file=""
    if declare -f FIND_TARGET >/dev/null 2>&1; then
        target_file="$(FIND_TARGET "$(basename "$file")" 2>/dev/null || true)"
    fi
    if [[ -z "$target_file" || ! -f "$target_file" ]]; then
        target_file="$(_UN1CA_REAL_PATH "$part" "$file")" || return 1
    fi
    [[ -f "$target_file" ]] || { printf 'UN1CA: target not found: %s\n' "$target_file" >&2; return 1; }
    worktree="$(dirname "$target_file")/$(basename "$target_file")_decompiled"
    if [[ ! -d "$worktree" ]]; then
        DECOMPILE "${target_file#$WORKSPACE/}" || return 1
    fi
    mkdir -p "$WORKSPACE/.un1ca_apktool"
    _UN1CA_VIRTUAL_TARGET "$part" "$file" >/dev/null || return 1
    APKTOOL_DIR="$WORKSPACE/.un1ca_apktool"; export APKTOOL_DIR
}

GET_PROP() {
    if [[ $# -eq 1 ]]; then
        declare -f _RECORE_NATIVE_GET_PROP >/dev/null 2>&1 || return 1
        local part val
        for part in "${_UN1CA_PROP_SEARCH_ORDER[@]}"; do
            val="$(_RECORE_NATIVE_GET_PROP "$part" "$1" 2>/dev/null)"
            [[ -n "$val" ]] && { printf '%s\n' "$val"; return 0; }
        done
        return 1
    fi
    _RECORE_NATIVE_GET_PROP "$@"
}

SET_PROP() {
    local part="$1" key="$2" val="${3:-}"
    if [[ "$val" == "--delete" || "$val" == "-d" ]]; then val=""; fi
    if declare -f BPROP >/dev/null 2>&1; then BPROP "$part" "$key" "$val"; return $?; fi
    return 1
}

# Prefers ReCoreUI's own native, xmlstarlet-backed FF/GET_FF_VAL when a
# WORKSPACE-relative call is made (the common case from customize.sh) - more
# robust than text-scanning for anything beyond a single-line <tag>value</tag>.
# The explicit-file form (2 args) still uses the plain-text approach, since
# that form exists specifically to point at a file outside the live tree.
GET_FLOATING_FEATURE_CONFIG() {
    local file="" config=""
    if [[ $# -eq 1 ]]; then config="$1"; else file="$1"; config="$2"; fi
    if [[ -z "$file" ]] && declare -f GET_FF_VAL >/dev/null 2>&1; then
        GET_FF_VAL "$config"; return $?
    fi
    file="${file:-$WORKSPACE/system/system/etc/floating_feature.xml}"
    [[ -f "$file" ]] || return 1
    grep -o -P "(?<=<${config}>)[^<]+" "$file" 2>/dev/null || true
}

SET_FLOATING_FEATURE_CONFIG() {
    local config="$1" value="$2" file="${3:-}"
    if [[ -z "$file" ]] && declare -f FF >/dev/null 2>&1; then
        if [[ "$value" == "--delete" || "$value" == "-d" ]]; then FF "$config"; else FF "$config" "$value"; fi
        return $?
    fi
    file="${file:-$WORKSPACE/system/system/etc/floating_feature.xml}"
    [[ -f "$file" ]] || return 1
    if grep -q "<${config}>" "$file"; then
        if [[ "$value" == "--delete" || "$value" == "-d" ]]; then sed -i "/<${config}>/d" "$file"; else sed -i "s|<${config}>[^<]*</${config}>|<${config}>${value}</${config}>|" "$file"; fi
    elif [[ "$value" != "--delete" && "$value" != "-d" ]]; then
        sed -i '/<\/SecFloatingFeatureSet>/d' "$file"
        grep -q 'Added by scripts' "$file" || printf '%s\n' '    <!-- Added by scripts/utils/module_utils.sh -->' >> "$file"
        printf '    <%s>%s</%s>\n</SecFloatingFeatureSet>\n' "$config" "$value" "$config" >> "$file"
    fi
}

EVAL() {
    local out rc
    out="$(eval -- "$*" 2>&1)"; rc=$?
    [[ $rc -eq 0 ]] || printf 'UN1CA: command failed: %s\n%s\n' "$*" "$out" >&2
    return $rc
}

LOG_STEP_IN() { if declare -f LOG_BEGIN >/dev/null 2>&1; then LOG_BEGIN "$*"; else _UN1CA_LOG "$*"; fi; }
LOG_STEP_OUT() { if declare -f LOG_END >/dev/null 2>&1; then LOG_END "$*"; fi; }

# Refuses to touch a smali element (whole file, or one method) that's still
# referenced anywhere ELSE in the decompiled tree. Checked against the WHOLE
# tree root, not just the smali file's own folder - a class/method is almost
# always referenced from a *different* package, so a same-folder-only check
# (as originally written here) would essentially never catch a real usage.
_UN1CA_UNUSED_ELSEWHERE() {
    local tree_root="$1" fp="$2" needle="$3" hits
    hits="$(grep -rl -F -- "$needle" "$tree_root" 2>/dev/null | grep -v -F -x -- "$fp")"
    [[ -z "$hits" ]]
}

SMALI_PATCH() {
    local part="$1" file="$2" smali="$3" op="${4:-}"
    [[ -n "$part" && -n "$file" && -n "$smali" && -n "$op" ]] || return 1
    _UN1CA_VALID_PARTITION "$part" || return 1
    DECODE_APK "$part" "$file" || return 1
    local relfile="$file"
    while [[ "$relfile" == /* ]]; do relfile="${relfile#/}"; done
    [[ "$part" == system ]] && relfile="${relfile#system/}"
    local tree_root="$APKTOOL_DIR/$part/$relfile"
    local fp="$tree_root/$smali"
    [[ -f "$fp" ]] || { printf 'UN1CA: smali not found: %s\n' "$fp" >&2; return 1; }
    local cls="${smali%.smali}"; cls="${cls##*/}"
    case "$op" in
        remove)
            _UN1CA_UNUSED_ELSEWHERE "$tree_root" "$fp" "${cls};" || { printf 'UN1CA: refusing to remove used smali %s\n' "$smali" >&2; return 1; }
            rm -f -- "$fp";;
        strip)
            local m5="${5:-}"
            [[ -n "$m5" ]] || { printf 'UN1CA: strip requires a method\n' >&2; return 1; }
            local mname="${m5%%(*}"
            local hits owners
            hits="$(grep -rl -F -- "${cls};" "$tree_root" 2>/dev/null | grep -v -F -x -- "$fp")"
            if [[ -n "$hits" ]]; then
                owners="$(printf '%s\n' "$hits" | xargs -r grep -l -F -- "$mname" 2>/dev/null)"
                [[ -z "$owners" ]] || { printf 'UN1CA: refusing to strip used method %s\n' "$m5" >&2; return 1; }
            fi
            python3 "$_UN1CA_SMALI_COMPAT" strip "$fp" "$m5";;
        replaceall) python3 "$_UN1CA_SMALI_COMPAT" replaceall "$fp" __ALL__ "${5:-}" "${6:-}";;
        replace) python3 "$_UN1CA_SMALI_COMPAT" replace "$fp" "${5:-}" "${6:-}" "${7:-}";;
        return|null) python3 "$_UN1CA_SMALI_COMPAT" "$op" "$fp" "${5:-}" "${6:-}";;
        *) printf 'UN1CA: invalid SMALI_PATCH operation: %s\n' "$op" >&2; return 1;;
    esac
}

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
        if [[ -z "$tf" || ! -f "$tf" ]]; then
            tf="$(_UN1CA_REAL_PATH "$part" "$target_rel")" || return 1
        fi
        [[ -f "$tf" ]] || continue
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
    # A module may be discovered more than once (or the build re-run for an
    # idempotency check). Skip an exact repeat in this workspace, while still
    # allowing genuinely changed module contents to run again.
    local module_fingerprint marker_dir marker
    module_fingerprint="$( { printf '%s\n' "$mod"; find "$mod" -type f -print0 | sort -z | xargs -0 -r sha256sum; } | sha256sum | cut -d' ' -f1 )"
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
