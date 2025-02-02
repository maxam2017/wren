#!/bin/bash

SCRIPT_NAME="wren"
# Follow symlink to get the real script path
PROJECT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
INSTALL_DIR="/usr/local/lib/$SCRIPT_NAME"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"

MAX_BRANCHES=100

source "$PROJECT_ROOT/bootstrap.sh"
bootstrap "$SCRIPT_NAME" "DEBUG=true"

import "utils.sh"

install_script() {
    local force="${1:-false}"
    if [[ ! -f "$INSTALL_PATH" ]] || [[ "$force" == "true" ]]; then
        # ask for sudo password first
        sudo -v
        start_spinner "🪜 Setting up Wren..."
        
        # Create directories
        sudo mkdir -p "$(dirname "$INSTALL_PATH")"
        sudo mkdir -p "$INSTALL_DIR"
        
        # Copy the entire project directory
        if sudo cp -r "$PROJECT_ROOT/"* "$INSTALL_DIR/" && \
           sudo ln -sf "$INSTALL_DIR/$(basename "${BASH_SOURCE[0]}")" "$INSTALL_PATH"; then
            stop_spinner "Wren is installed at $INSTALL_PATH"
            echo "✨ Try running 'wren' to see if it works!"
        else
            stop_spinner "Error: Failed to install Wren"
            exit 1
        fi
    else
        info "🐦 Wren is already installed at $INSTALL_PATH"
    fi
}

uninstall_script() {
    sudo -v
    if [[ -f "$INSTALL_PATH" ]]; then
        start_spinner "🗑️  Uninstalling Wren..."
        if sudo rm "$INSTALL_PATH" && sudo rm -rf "$INSTALL_DIR"; then
            stop_spinner "👋 Thanks for using Wren! Successfully uninstalled"
        else
            stop_spinner "Error: Failed to uninstall Wren"
            exit 1
        fi
    else
        warn "Wren is not installed"
    fi
}

upgrade_script() {
    # run ./install.sh
    "$PROJECT_ROOT/install.sh"
}

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME COMMAND [OPTIONS]

Commands:
    install     Install the script and its dependencies
    uninstall   Remove the script and its dependencies

Options:
    -h, --help     Show this help message
    -f, --force    Force installation even if already installed

Examples:
    $SCRIPT_NAME install          # Install normally
    $SCRIPT_NAME install -f      # Force install/update
    $SCRIPT_NAME uninstall       # Remove installation
EOF
}

# Check if git is available and current directory is a git repository
check_git() {
    if ! command -v git >/dev/null 2>&1; then
        error "Error: Git is not installed"
        exit 1
    fi
    
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        error "Error: Not a git repository"
        exit 1
    fi

    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
        error "Error: No commits yet"
        exit 1
    fi
}

# Add this function after check_git()
check_uncommitted_changes() {
    # Check for staged/unstaged changes
    if ! git diff-index --quiet HEAD --; then
        return 0  # Has changes
    fi
    # Check for untracked files
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        return 0  # Has untracked files
    fi
    return 1  # No changes
}

save_session() {
    local branch="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local stash_message="wren_autosave_${branch}_${timestamp}"
    
    # Add untracked files to the stash
    if git stash push --include-untracked -m "$stash_message" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

restore_session() {
    local branch="$1"
    local stash_list
    stash_list=$(git stash list | grep "wren_autosave_${branch}_" | head -n 1)
    
    if [ -n "$stash_list" ]; then
        local stash_index=$(echo "$stash_list" | cut -d: -f1)
        # Use --index to restore both staged and unstaged changes
        if git stash apply --index "$stash_index" >/dev/null 2>&1; then
            git stash drop "$stash_index" >/dev/null 2>&1
            return 0
        fi
    fi
    return 1
}

# Switch to the selected branch
switch_branch() {
    local branch="$1"
    local current_branch=$(git branch --show-current)
    
    # Remove "(deleted)" suffix if present
    branch="${branch% (deleted)}"
    
    # Check if branch exists locally
    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        error "Error: Branch '$branch' no longer exists locally"
        return 1
    fi

    echo
    start_spinner "🔍 Checking branch status..."
    
    # Check for uncommitted changes
    if check_uncommitted_changes; then
        stop_spinner "👀 Found uncommitted changes or untracked files"

        # Save session
        start_spinner "💾  Saving your work..."
        if save_session "$current_branch"; then
            stop_spinner "💾 Work saved successfully"
        else
            stop_spinner "❌ Failed to save work"
            return 1
        fi
    else
        stop_spinner "👀 Branch is clean"
    fi
    
    start_spinner "🪜 Hopping over to '$branch'..."
    
    if git checkout "$branch" >/dev/null 2>&1; then
        stop_spinner "✨ Successfully landed on '$branch'"
        
        # Check for saved session
        start_spinner "🔍 Checking for saved work..."
        if restore_session "$branch"; then
            stop_spinner "📝 Restored your previous work on this branch"
        else
            stop_spinner "👀 No saved work found"
        fi
        
        return 0
    else
        stop_spinner "Error: Failed to switch to '$branch'"
        return 1
    fi
}

# Add this helper function
confirm() {
    local message="$1"
    local options=("Yes" "No")
    
    show_list "$message" "${options[@]}"
    local choice=$?
    
    [ "$choice" -eq 0 ]
}

show_commands() {
    check_git
    
    # Get branches and create display array with current branch marked
    local display_branches
    array_create display_branches
    
    local current_branch=$(git branch --show-current)
    array_create all_branches "$current_branch"
    # Append all local branches to all_branches (limit to 100)
    local branch_count=0
    while IFS= read -r branch && [ $branch_count -lt $MAX_BRANCHES ]; do
        branch="${branch##* }"  # Remove leading spaces and asterisk
        if ! array_contains all_branches "$branch"; then
            array_append all_branches "$branch"
            ((branch_count++))
        fi
    done < <(git branch --sort=-committerdate)

    local branches # order: last to first
    array_create branches

    while IFS= read -r branch; do
        if ! array_contains branches "$branch"; then
            array_append branches "$branch"
        fi
    done < <(git reflog --no-abbrev |
            grep -i 'checkout: moving from .* to' |
            sed 's/.*moving from .* to \(.*\)/\1/')

    # append rest local branches into branches (maintaining 100 limit)
    for branch in "${all_branches[@]}"; do
        if ! array_contains branches "$branch" && [ $(array_length branches) -lt $MAX_BRANCHES ]; then
            array_append branches "$branch"
        fi
    done

    for branch in "${branches[@]}"; do
        if [[ -n "$branch" ]]; then
            if [[ "$branch" == "$current_branch" ]]; then
                array_append display_branches "$branch (current)"
            else
                array_append display_branches "$branch"
            fi
        fi
    done

    # Show branch selection menu
    set +e
    show_list "🐦 Git Wren - Hop to which branch?" "${display_branches[@]}"
    local choice=$?
    set -e
    
    # Handle selection
    if [[ $choice == 255 ]]; then
        info "🐦 Staying on current branch!"
        exit 0
    elif [[ $choice -ge 0 ]] && [[ $choice -lt $(array_length display_branches) ]]; then
        local selected_branch="${display_branches[$choice]}"
        selected_branch="${selected_branch% (current)}"  # Remove "(current)" suffix if present
        
        if [[ "$selected_branch" != "$current_branch" ]]; then
            switch_branch "$selected_branch"
        else
            info "Already on '$current_branch'"
        fi
    fi
}

main() {
    local action="${1:-}"
    local force=false
    shift || true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                force=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # If no command provided, show interactive menu
    if [ -z "$action" ]; then
        show_commands
        exit 0
    fi

    case "$action" in
        -h|--help)
            show_help
            exit 0
            ;;
        install)
            install_script "$force"
            exit 0
            ;;
        uninstall)
            uninstall_script
            exit 0
            ;;
        upgrade)
            upgrade_script
            exit 0
            ;;
        "")
            show_help
            exit 1
            ;;
        *)
            error "Unknown command: $action"
            show_help
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 