#!/bin/bash
# Launch Windows Terminal tabs for desktop_master worktrees with intelligent names

MAIN_REPO="/c/work/desktop_master"
CACHE_FILE="$HOME/.cache/worktree-names.cache"
FILTER_PATTERN="desktop_master"  # Default: only master variants
DRY_RUN=false
REFRESH=false
INCLUDE_ALL=false
TERMINAL="wezterm"  # Default terminal: wezterm or wt
FIRST_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --all)
            INCLUDE_ALL=true
            shift
            ;;
        --refresh)
            REFRESH=true
            shift
            ;;
        --wt)
            TERMINAL="wt"
            shift
            ;;
        --wezterm)
            TERMINAL="wezterm"
            shift
            ;;
        --first)
            FIRST_ONLY=true
            shift
            ;;
        *)
            echo "Usage: $0 [--dry-run] [--all] [--refresh] [--wt|--wezterm] [--first]"
            echo "  --dry-run   Print commands without executing"
            echo "  --all       Include all worktrees (not just desktop_master*)"
            echo "  --refresh   Regenerate all cached names"
            echo "  --wt        Use Windows Terminal (wt.exe)"
            echo "  --wezterm   Use WezTerm (default)"
            echo "  --first     Only launch the first worktree (for testing)"
            exit 1
            ;;
    esac
done

# Ensure cache directory exists
mkdir -p "$(dirname "$CACHE_FILE")"

# Clear cache if refresh requested
if [[ "$REFRESH" == true ]] && [[ -f "$CACHE_FILE" ]]; then
    rm "$CACHE_FILE"
fi

# Extract master number from path
# /c/WORK/desktop_master   → 1
# /c/WORK/desktop_master2  → 2
# /c/WORK/desktop_master17 → 17
get_master_number() {
    local path="$1"
    local basename=$(basename "$path" | tr '[:upper:]' '[:lower:]')
    if [[ "$basename" =~ ^desktop_master([0-9]+)?$ ]]; then
        echo "${BASH_REMATCH[1]:-1}"
    else
        echo ""
    fi
}

# Generate short name using Claude Haiku with caching
generate_short_name() {
    local branch="$1"
    local commit_msg="$2"

    # Check cache first (keyed by branch name)
    if [[ -f "$CACHE_FILE" ]]; then
        cached=$(grep "^${branch}|" "$CACHE_FILE" | head -1 | cut -d'|' -f2)
        if [[ -n "$cached" ]]; then
            echo "$cached"
            return
        fi
    fi

    # Call Claude Haiku for intelligent name
    local name
    name=$(claude --print --model haiku \
        "Branch: $branch, Commit: $commit_msg. Output ONE lowercase word (max 8 chars) that captures this work. Just the word, nothing else." 2>/dev/null)

    # Fallback if claude fails
    if [[ -z "$name" || ${#name} -gt 12 ]]; then
        # Use last component of branch name, truncated
        name=$(echo "$branch" | sed 's/.*\///' | cut -c1-8 | tr '[:upper:]' '[:lower:]')
    fi

    # Clean up the name (remove quotes, whitespace, etc.)
    name=$(echo "$name" | tr -d '"\n\r ' | tr '[:upper:]' '[:lower:]')

    # Cache the result
    echo "${branch}|${name}" >> "$CACHE_FILE"
    echo "$name"
}

# Parse git worktree list --porcelain
# Returns array entries: "path|branch|commit_msg"
discover_worktrees() {
    local worktrees=()
    local current_path=""
    local current_branch=""
    local current_head=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
            # Save previous worktree if we have one
            if [[ -n "$current_path" && -n "$current_branch" ]]; then
                # Get commit message for this worktree
                local commit_msg=""
                if [[ -n "$current_head" ]]; then
                    commit_msg=$(git -C "$current_path" log -1 --format="%s" 2>/dev/null | head -c 80)
                fi
                worktrees+=("${current_path}|${current_branch}|${commit_msg}")
            fi
            current_path="${BASH_REMATCH[1]}"
            current_branch=""
            current_head=""
        elif [[ "$line" =~ ^HEAD\ (.+)$ ]]; then
            current_head="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]]; then
            current_branch="${BASH_REMATCH[1]}"
        elif [[ "$line" == "detached" ]]; then
            current_branch=""  # Skip detached worktrees
        fi
    done < <(git -C "$MAIN_REPO" worktree list --porcelain 2>/dev/null)

    # Don't forget the last worktree
    if [[ -n "$current_path" && -n "$current_branch" ]]; then
        local commit_msg=""
        if [[ -n "$current_head" ]]; then
            commit_msg=$(git -C "$current_path" log -1 --format="%s" 2>/dev/null | head -c 80)
        fi
        worktrees+=("${current_path}|${current_branch}|${commit_msg}")
    fi

    # Output worktrees
    printf '%s\n' "${worktrees[@]}"
}

# Main logic
declare -a worktree_data=()

while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue

    path=$(echo "$entry" | cut -d'|' -f1)
    branch=$(echo "$entry" | cut -d'|' -f2)
    commit_msg=$(echo "$entry" | cut -d'|' -f3)

    # Filter worktrees
    if [[ "$INCLUDE_ALL" != true ]]; then
        # Only include desktop_master variants (case-insensitive)
        path_lower=$(echo "$path" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$path_lower" =~ $FILTER_PATTERN ]]; then
            continue
        fi
    fi

    # Get master number (empty if not a desktop_master path)
    master_num=$(get_master_number "$path")

    # Skip if not a desktop_master variant (unless --all)
    if [[ -z "$master_num" && "$INCLUDE_ALL" != true ]]; then
        continue
    fi

    worktree_data+=("${path}|${branch}|${commit_msg}|${master_num}")
done < <(discover_worktrees)

# Sort by master number
IFS=$'\n' sorted_worktrees=($(printf '%s\n' "${worktree_data[@]}" | sort -t'|' -k4 -n))
unset IFS

# Limit to first worktree if --first
if [[ "$FIRST_ONLY" == true && ${#sorted_worktrees[@]} -gt 0 ]]; then
    sorted_worktrees=("${sorted_worktrees[0]}")
fi

# Build tab title from master number and short name
build_title() {
    local master_num="$1"
    local short_name="$2"
    if [[ -n "$master_num" ]]; then
        echo "${master_num} ${short_name}"
    else
        echo "$short_name"
    fi
}

# Print dry-run worktree summary
print_worktree_summary() {
    echo ""
    echo "Worktrees found:"
    for entry in "${sorted_worktrees[@]}"; do
        local path=$(echo "$entry" | cut -d'|' -f1)
        local branch=$(echo "$entry" | cut -d'|' -f2)
        local master_num=$(echo "$entry" | cut -d'|' -f4)
        local short_name=$(generate_short_name "$branch" "")
        echo "  $master_num: $path ($branch) -> '$(build_title "$master_num" "$short_name")'"
    done
}

launch_wt() {
    local cmd="wt.exe -w 0"

    for entry in "${sorted_worktrees[@]}"; do
        [[ -z "$entry" ]] && continue

        local path=$(echo "$entry" | cut -d'|' -f1)
        local branch=$(echo "$entry" | cut -d'|' -f2)
        local commit_msg=$(echo "$entry" | cut -d'|' -f3)
        local master_num=$(echo "$entry" | cut -d'|' -f4)

        local short_name=$(generate_short_name "$branch" "$commit_msg")
        local title=$(build_title "$master_num" "$short_name")

        # Convert WSL path to Windows path for wt.exe
        local win_path=$(echo "$path" | sed -E 's|^/([cC])/|\U\1:\\|' | sed 's|/|\\|g')

        cmd="$cmd nt -p Ubuntu -d '$win_path' --title '$title' wsl.exe -e fish -c 'claude --dangerously-skip-permissions --continue && exec fish' \\;"
    done

    # Remove trailing \;
    cmd="${cmd% \\;}"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[Windows Terminal mode]"
        echo "Would execute:"
        echo "$cmd"
        print_worktree_summary
    else
        eval "$cmd"
    fi
}

launch_wezterm() {
    # Find wezterm CLI binary
    local wez
    if command -v wezterm &>/dev/null; then
        wez="wezterm"
    elif command -v wezterm.exe &>/dev/null; then
        wez="wezterm.exe"
    elif [[ -x "/c/Program Files/WezTerm/wezterm.exe" ]]; then
        wez="/c/Program Files/WezTerm/wezterm.exe"
    else
        echo "Error: wezterm not found" >&2
        exit 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[WezTerm mode] ($wez)"
        echo "Would execute:"
    fi

    for entry in "${sorted_worktrees[@]}"; do
        [[ -z "$entry" ]] && continue

        local path=$(echo "$entry" | cut -d'|' -f1)
        local branch=$(echo "$entry" | cut -d'|' -f2)
        local commit_msg=$(echo "$entry" | cut -d'|' -f3)
        local master_num=$(echo "$entry" | cut -d'|' -f4)

        local short_name=$(generate_short_name "$branch" "$commit_msg")
        local title=$(build_title "$master_num" "$short_name")

        # Convert WSL path to Windows path for wezterm.exe --cwd
        local win_path=$(echo "$path" | sed -E 's|^/([cC])/|\U\1:\\|' | sed 's|/|\\|g')

        if [[ "$DRY_RUN" == true ]]; then
            echo "  $wez cli spawn --cwd '$win_path' -- wsl.exe -e fish -l -c 'claude --dangerously-skip-permissions --continue; exec fish'"
            echo "  $wez cli set-tab-title '$title'"
        else
            local pane_id
            pane_id=$("$wez" cli spawn --cwd "$win_path" -- wsl.exe -e fish -l -c 'claude --dangerously-skip-permissions --continue; exec fish')
            if [[ -n "$pane_id" ]]; then
                "$wez" cli set-tab-title --pane-id "$pane_id" "$title"
            fi
        fi
    done

    if [[ "$DRY_RUN" == true ]]; then
        print_worktree_summary
    fi
}

# Launch tabs in the selected terminal
case "$TERMINAL" in
    wt)      launch_wt ;;
    wezterm) launch_wezterm ;;
esac
