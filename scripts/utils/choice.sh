
_CHOICE() {
    local TITLE="$1"
    shift
    local OPTIONS=("$@")

    echo "" >&2
    echo "$TITLE:" >&2

    local i=1
    for opt in "${OPTIONS[@]}"; do
        echo "  $i) $opt" >&2
        ((i++))
    done

    echo "" >&2
    read -p "Select option [1-${#OPTIONS[@]}]: " CH >&2

    if [[ "$CH" =~ ^[0-9]+$ ]] && (( CH >= 1 && CH <= ${#OPTIONS[@]} )); then
        echo "$CH"
    else
        echo "Invalid choice" >&2
        exit 1
    fi
}
