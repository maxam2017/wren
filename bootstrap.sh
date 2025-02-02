#!/bin/sh

# Guard against multiple imports
[ -n "${_BOOTSTRAP_LOADED:-}" ] && return 0
_BOOTSTRAP_LOADED=1

# Core bootstrap function
bootstrap() {
    script_name="${1:-$(basename "${0:-unknown}")}"
    shift || true
    options="${*:-}"

    # Essential environment setup
    set -e
    set -u
    
    # Basic configuration using variable variables
    config_set "SCRIPT_NAME" "$script_name"
    config_set "SCRIPT_DIR" "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    config_set "DEBUG" "false"
    config_set "QUIET" "false"
    
    # Parse options
    if [ -n "$options" ]; then
        for opt in $options; do
            key="${opt%%=*}"
            value="${opt#*=}"
            config_set "$key" "$value"
        done
    fi

    # Setup error handling
    trap '_error_handler ${LINENO:-0} $?' ERR
    trap '_cleanup' EXIT
}

# Config helpers using variable variables
config_set() {
    key="$1"
    value="$2"
    eval "CONFIG_${key}=\"${value}\""
    export "CONFIG_${key}"
}

config_get() {
    key="$1"
    eval "echo \"\${CONFIG_${key}:-}\""
}

# Basic error handler
_error_handler() {
    local line=$1
    local exit_code=$2
    echo "Error on line $line (exit code: $exit_code)" >&2
}

# Basic cleanup
_cleanup() {
    # Always ensure cursor is visible
    tput cnorm
}

# Import helper (will be used by other modules)
import() {
    local target_path="$1"
    local calling_file="${BASH_SOURCE[1]}"
    # Follow symlink if it exists and get the real path
    local calling_file_real="$(readlink -f "$calling_file")"
    local base_dir="$(cd "$(dirname "$calling_file_real")" && pwd)"
    local resolved_path="$base_dir/$target_path"
    
    if [ ! -f "$resolved_path" ]; then
        echo "Error: Could not import '$target_path'" >&2
        return 1
    fi
    
    source "$resolved_path"
}

export -f bootstrap import