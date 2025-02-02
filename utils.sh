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
        term_width=80
    fi

    local max_length=$((term_width - 10))

    _spin() {
        # Setup signal handler
        trap "exit 0" SIGTERM SIGINT
        
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
        kill $_SPINNER_PID 2>/dev/null
        _SPINNER_PID=""
        
        # Clear the spinner line
        echo -ne "\r\033[K"
        
        # Print message if provided
        if [ ! -z "$message" ]; then
            echo "$message"
        fi
    fi
}

# Create an interactive list UI with keyboard navigation, scrolling and search
# Returns: Selected index (0-based) or 255 if quit
# Usage: show_list "Title" "item1" "item2" "item3"
show_list() {
    local title=$1
    shift || true
    local items=("$@")
    local selected=0
    local total=${#items[@]}
    local scroll_offset=0
    local search_query=""
    local filtered_items=()
    local search_mode=false
    local temp_search=""
    
    # Calculate available rows for rendering
    local term_height=0
    if command -v tput >/dev/null 2>&1; then
        term_height=$(tput lines)
    else
        term_height=24  # fallback height
    fi
    
    # Reserve rows for title, search bar and potential status messages
    local reserved_rows=5
    local max_visible=$((term_height - reserved_rows))
    local ROWS=$((max_visible > 10 ? 10 : max_visible))

    # Get terminal width
    local term_width=0
    if command -v tput >/dev/null 2>&1; then
        term_width=$(tput cols)
    else
        # Fallback if tput is not available
        term_width=80
    fi

    local max_length=$((term_width - 10))
    
    # Filter items based on search query
    filter_items() {
        filtered_items=()
        local query=$(echo "$search_query" | tr '[:upper:]' '[:lower:]')
        local idx=0
        for item in "${items[@]}"; do
            if [[ -z "$query" ]] || [[ "$(echo "$item" | tr '[:upper:]' '[:lower:]')" == *"$query"* ]]; then
                filtered_items+=("$item")
            fi
        done
        total=${#filtered_items[@]}
        
        # Reset selection and scroll if needed
        if [ $selected -ge $total ]; then
            selected=$((total - 1))
            [ $selected -lt 0 ] && selected=0
        fi
        if [ $scroll_offset -gt $((total - ROWS)) ]; then
            scroll_offset=$((total - ROWS))
            [ $scroll_offset -lt 0 ] && scroll_offset=0
        fi
    }
    
    # Initialize with all items
    filtered_items=("${items[@]}")
    total=${#filtered_items[@]}
    selected=0
    scroll_offset=0
    
    # Hide cursor during list display
    tput civis
    
    while true; do
        # Clear screen from cursor position
        echo -ne "\033[2J\033[H"
        
        # Print title and filter status with hints
        print "BLUE" "$title"
        if [ -n "$search_query" ]; then
            if [ $total -eq 0 ]; then
                echo -e "${RED}No matches found for: $search_query${NC}"
                echo -e "${GRAY}(ESC to clear, / to search)${NC}"
                echo
                echo -e "${GRAY}🐦 No branches in sight!${NC}"
                echo -e "${GRAY}This wren couldn't spot any matching branches.${NC}"
                echo -e "${GRAY}Try another search or press ESC to see all branches.${NC}"
            else
                echo -e "${GRAY}Filter: $search_query (ESC to clear, / to search)${NC}"
                
                # Calculate visible range
                local start_idx=$scroll_offset
                local end_idx=$((scroll_offset + ROWS))
                [ $end_idx -gt $total ] && end_idx=$total
                
                # Print scroll indicator if needed
                if [ $scroll_offset -gt 0 ]; then
                    echo -e "${GRAY}↑ More branches above${NC}"
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
                    
                    item="${filtered_items[$i]}"
                    if [ ${#item} -gt $max_length ]; then
                        item="${item:0:$max_length}..."
                    fi
                    printf "${!LIST_CURSOR_COLOR}%s${NC} ${!color}%s${NC}\n" "$cursor" "$item"
                done
                
                # Print scroll indicator if needed
                if [ $end_idx -lt $total ]; then
                    echo -e "${GRAY}↓ More branches below${NC}"
                fi
            fi
        else
            # Normal unfiltered view
            # Calculate visible range
            local start_idx=$scroll_offset
            local end_idx=$((scroll_offset + ROWS))
            [ $end_idx -gt $total ] && end_idx=$total
            
            # Print scroll indicator if needed
            if [ $scroll_offset -gt 0 ]; then
                echo -e "${GRAY}↑ More branches above${NC}"
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
                
                item="${filtered_items[$i]}"
                if [ ${#item} -gt $max_length ]; then
                    item="${item:0:$max_length}..."
                fi
                printf "${!LIST_CURSOR_COLOR}%s${NC} ${!color}%s${NC}\n" "$cursor" "$item"
            done
            
            # Print scroll indicator if needed
            if [ $end_idx -lt $total ]; then
                echo -e "${GRAY}↓ More branches below${NC}"
            fi
        fi
        
        # Print search bar at the bottom if in search mode
        if [ "$search_mode" = true ]; then
            echo # Empty line before search
            echo -ne "${BLUE}Search:${NC} $temp_search"
            tput cnorm  # Show cursor in search mode
        else
            tput civis  # Hide cursor when not in search mode
        fi
        
        if [ "$search_mode" = true ]; then
            read -rsn1 search_char
            case "$search_char" in
                $'\x1B')  # ESC in search mode
                    search_mode=false
                    temp_search=""
                    continue
                    ;;
                $'\x7F')  # Backspace
                    if [ -n "$temp_search" ]; then
                        temp_search="${temp_search%?}"
                    fi
                    continue
                    ;;
                "")  # Enter
                    search_mode=false
                    if [ -n "$temp_search" ]; then
                        search_query="$temp_search"
                        filter_items
                    else
                        search_query=""
                        filtered_items=("${items[@]}")
                        total=${#filtered_items[@]}
                        selected=0
                        scroll_offset=0
                    fi
                    temp_search=""
                    continue
                    ;;
                *)  # Any other character
                    if [[ "$search_char" =~ [[:print:]] ]]; then
                        temp_search="$temp_search$search_char"
                    fi
                    continue
                    ;;
            esac
        else
            read -rsn1 input
            # Handle ESC key
            if [[ "$input" == $'\x1B' ]]; then
                # Read arrow keys and handle them
                read -rsn2 arrow 2>/dev/null || arrow=""
                case "$arrow" in
                    "[A")  # Up arrow
                        if [ $selected -gt 0 ]; then
                            ((selected--))
                            if [ $selected -lt $scroll_offset ]; then
                                ((scroll_offset--))
                            fi
                        fi
                        ;;
                    "[B")  # Down arrow
                        if [ $selected -lt $((total - 1)) ]; then
                            ((selected++))
                            if [ $selected -ge $((scroll_offset + ROWS)) ]; then
                                ((scroll_offset++))
                            fi
                        fi
                        ;;
                    *)  # Plain ESC or other sequence
                        if [ -n "$search_query" ]; then
                            search_query=""
                            filtered_items=("${items[@]}")
                            total=${#filtered_items[@]}
                            selected=0
                            scroll_offset=0
                        fi
                        ;;
                esac
            elif [[ "$input" == "/" ]]; then
                search_mode=true
                temp_search="$search_query"
                continue
            elif [[ "$input" == "" ]]; then  # Enter
                tput cnorm
                if [ $total -gt 0 ]; then
                    local selected_item="${filtered_items[$selected]}"
                    for ((i=0; i<${#items[@]}; i++)); do
                        if [ "${items[$i]}" = "$selected_item" ]; then
                            return $i
                        fi
                    done
                fi
                return 255
            elif [[ "$input" == "q" ]] || [[ "$input" == "Q" ]]; then
                tput cnorm
                echo
                return 255
            fi
        fi
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
