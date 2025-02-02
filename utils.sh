#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Spinner characters
SPINNER_CHARS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
_SPINNER_PID=""

# List UI configuration
LIST_CURSOR="→"
LIST_SELECTED_PREFIX="✓"
LIST_UNSELECTED_PREFIX=" "
LIST_SELECTED_COLOR="GREEN"
LIST_CURSOR_COLOR="CYAN"
LIST_ITEM_COLOR="GRAY"

# Print colored text to stdout
# Args:
#   $1 - color name (RED, GREEN, BLUE, etc.)
#   $2 - message to print
print() {
    local color=$1
    local message=$2
    echo -e "${!color}${message}${NC}"
}

# Print a success message with green checkmark
# Args:
#   $1 - message to print
success() {
    print "GREEN" "✓ $1"
}

# Print an error message with red X
# Args:
#   $1 - message to print
error() {
    print "RED" "✗ $1"
}

# Print an info message with blue info symbol
# Args:
#   $1 - message to print
info() {
    print "BLUE" "ℹ $1"
}

# Print a warning message with yellow warning symbol
# Args:
#   $1 - message to print
warn() {
    print "YELLOW" "⚠ $1"
}

# Display an animated spinner with a message
# The spinner will continue until stop_spinner is called
# Args:
#   $1 - message to display next to spinner
start_spinner() {
    local message=$1
    
    # Don't start a new spinner if one is already running
    if [ ! -z "$_SPINNER_PID" ]; then
        return
    fi

    # Get terminal width
    local term_width=0
    if command -v tput >/dev/null 2>&1; then
        term_width=$(tput cols)
    else
        # Fallback if tput is not available
        term_width=80
    fi

    local max_length=$((term_width - 10))

    _spin() {
        while true; do
            for char in "${SPINNER_CHARS[@]}"; do
                if [ ${#message} -gt $max_length ]; then
                    echo -ne "\r${BLUE}${char}${NC} ${message:0:$max_length}..."
                else
                    echo -ne "\r${BLUE}${char}${NC} ${message}"
                fi
                sleep 0.1
            done
        done
    }

    # Start spinner in background
    _spin &
    _SPINNER_PID=$!
}

# Stop the currently running spinner
# Args:
#   $1 - (optional) final message to display
stop_spinner() {
    local message=$1
    
    # Kill the spinner process if it exists
    if [ ! -z "$_SPINNER_PID" ]; then
        kill $_SPINNER_PID
        _SPINNER_PID=""
        
        # Clear the spinner line
        echo -ne "\r\033[K"
        
        # Print message if provided
        if [ ! -z "$message" ]; then
            echo "$message"
        fi
    fi
}

# Create an interactive list UI with keyboard navigation and scrolling
# Returns: Selected index (0-based) or 255 if quit
# Usage: show_list "Title" "item1" "item2" "item3"
show_list() {
    local title=$1
    shift || true
    local items=("$@")
    local selected=0
    local total=${#items[@]}
    local scroll_offset=0
    
    # Calculate available rows for rendering
    local term_height=0
    if command -v tput >/dev/null 2>&1; then
        term_height=$(tput lines)
    else
        term_height=24  # fallback height
    fi
    
    # Reserve rows for title and potential status messages
    local reserved_rows=4
    local max_visible=$((term_height - reserved_rows))
    local ROWS=$((max_visible > 10 ? 10 : max_visible))
    
    # Hide cursor during list display
    tput civis
    
    while true; do
        # Clear screen from cursor position
        echo -ne "\033[2J\033[H"

        # Print title
        print "BLUE" "$title"
        
        # Calculate visible range
        local start_idx=$scroll_offset
        local end_idx=$((scroll_offset + ROWS))
        [ $end_idx -gt $total ] && end_idx=$total
        
        # Print scroll indicator if needed
        if [ $scroll_offset -gt 0 ]; then
            echo -e "${GRAY}↑ More items above${NC}"
        fi
        
        # Print visible items
        for ((i=start_idx; i<end_idx; i++)); do
            local prefix="$LIST_UNSELECTED_PREFIX"
            local color="$LIST_ITEM_COLOR"
            local cursor=" "
            
            if [ $i -eq $selected ]; then
                cursor="$LIST_CURSOR"
                color="$LIST_CURSOR_COLOR"
            fi
            
            printf "${!LIST_CURSOR_COLOR}%s${NC} ${!color}%s${NC}\n" "$cursor" "${items[$i]}"
        done
        
        # Print scroll indicator if needed
        if [ $end_idx -lt $total ]; then
            echo -e "${GRAY}↓ More items below${NC}"
        fi
        
        # Read single character
        read -rsn1 key
        
        case "$key" in
            $'\x1B')  # Handle escape sequences
                read -rsn2 key
                case "$key" in
                    "[A") # Up arrow
                        if [ $selected -gt 0 ]; then
                            ((selected--))
                            # Scroll up if selected item would be out of view
                            if [ $selected -lt $scroll_offset ]; then
                                ((scroll_offset--))
                            fi
                        fi
                        ;;
                    "[B") # Down arrow
                        if [ $selected -lt $((total - 1)) ]; then
                            ((selected++))
                            # Scroll down if selected item would be out of view
                            if [ $selected -ge $((scroll_offset + ROWS)) ]; then
                                ((scroll_offset++))
                            fi
                        fi
                        ;;
                esac
                ;;
            "") # Enter key
                # Show cursor again
                tput cnorm
                return $selected
                ;;
            q|Q) # Quit
                # Show cursor again
                tput cnorm
                echo
                return 255
                ;;
        esac
    done

    # Show cursor again
    tput cnorm
}

# Array utilities using Bash native arrays
# ------------------------------------------

# Create a new array
# Usage: array_create "item1" "item2" "item3"
# Returns: Array declaration command
array_create() {
    local arr_name=$1
    shift
    eval "$arr_name=()"
    for item in "$@"; do
        eval "$arr_name[\${#$arr_name[@]}]=\"\$item\""
    done
}

# Get array length
# Args:
#   $1 - array name
# Returns: Number of elements in array
array_length() {
    local arr_name=$1
    eval "echo \${#$arr_name[@]:-0}"  # Return 0 if array is unbound
}

# Get array element at index
# Args:
#   $1 - array name
#   $2 - index (0-based)
# Returns: Element at index
array_get() {
    local arr_name=$1
    local index=$2
    if ! eval "[ \${#$arr_name[@]:-0} -gt $index ]"; then
        return 1
    fi
    eval "echo \${$arr_name[$index]}"
}

# Join array elements with delimiter
# Args:
#   $1 - array name
#   $2 - delimiter
# Returns: String with elements joined by delimiter
array_join() {
    local arr_name=$1
    local delim=$2
    
    # Check if array exists and has elements
    if [ "$(eval "echo \${#$arr_name[@]:-0}")" -eq 0 ]; then
        echo ""
        return 0
    fi
    
    local first=1
    local result=""
    
    eval "
        for item in \"\${$arr_name[@]}\"; do
            if [ \$first -eq 1 ]; then
                result=\"\$item\"
                first=0
            else
                result=\"\$result$delim\$item\"
            fi
        done
        echo \"\$result\"
    "
}

# Check if array contains element
# Args:
#   $1 - array name
#   $2 - element to search for
# Returns: 0 if element found, 1 if not found
array_contains() {
    local arr_name=$1
    local search=$2
    local found=1
    
    # Check if array exists and has elements
    if [ "$(eval "echo \${#$arr_name[@]:-0}")" -eq 0 ]; then
        return 1
    fi
    
    eval "
        for item in \"\${$arr_name[@]}\"; do
            if [ \"\$item\" = \"$search\" ]; then
                found=0
                break
            fi
        done
    "
    return $found
}

# Append element(s) to array
# Args:
#   $1 - array name
#   $@ - elements to append
# Returns: Updated array string
array_append() {
    local arr_name=$1
    shift
    for item in "$@"; do
        eval "$arr_name[\${#$arr_name[@]}]=\"\$item\""
    done
}
