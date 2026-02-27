#!/bin/bash
# List all worktrees for desktop_master with branch and latest commit info

MAIN_REPO="/c/work/desktop_master"
CHECK_REMOTE=${1:-""}  # Pass --check-remote to check if remote branches exist

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}🌳 Desktop Worktrees${NC}"
echo -e "${GRAY}════════════════════${NC}"
echo ""

# Fetch remote refs if checking remote
if [[ "$CHECK_REMOTE" == "--check-remote" ]]; then
    echo -e "${GRAY}Fetching remote refs...${NC}"
    git -C "$MAIN_REPO" fetch --prune origin 2>/dev/null
    echo ""
fi

# Collect worktree data first, then sort naturally
declare -a worktrees=()
current_worktree=""
current_head=""
current_branch=""
current_detached=""

while read line; do
    case "$line" in
        "worktree "*)
            current_worktree="${line#worktree }"
            current_detached=""
            current_branch=""
            ;;
        "HEAD "*)
            current_head="${line#HEAD }"
            ;;
        "branch "*)
            current_branch="${line#branch refs/heads/}"
            worktrees+=("$current_worktree|branch|$current_branch")
            ;;
        "detached")
            worktrees+=("$current_worktree|detached|")
            ;;
    esac
done < <(git -C "$MAIN_REPO" worktree list --porcelain)

# Sort naturally (human sort: desktop_master < desktop_master9 < desktop_master17)
printf '%s\n' "${worktrees[@]}" | sort -Vf | while IFS='|' read worktree_path wtype branch; do
    commit_info=$(git -C "$worktree_path" log -1 --format="%h %s" 2>/dev/null)
    short_commit=$(echo "$commit_info" | cut -c1-80)

    if [[ "$wtype" == "branch" ]]; then
        # Check remote status if requested
        remote_status=""
        if [[ "$CHECK_REMOTE" == "--check-remote" ]]; then
            if git -C "$MAIN_REPO" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
                remote_status="${GREEN}✓${NC}"
            else
                remote_status="${RED}🗑️  remote deleted${NC}"
            fi
        fi

        echo -e "🌿 ${GREEN}$branch${NC}"
        echo -e "   ${GRAY}$worktree_path${NC}"
        echo -e "   ${BLUE}$short_commit${NC} $remote_status"
        echo ""
    else
        echo -e "⚠️  ${YELLOW}(detached)${NC}"
        echo -e "   ${GRAY}$worktree_path${NC}"
        echo -e "   ${BLUE}$short_commit${NC}"
        echo ""
    fi
done

echo -e "${GRAY}────────────────────${NC}"
echo -e "🌿 = on branch  ⚠️  = detached HEAD"
if [[ "$CHECK_REMOTE" == "--check-remote" ]]; then
    echo -e "${GREEN}✓${NC} = remote exists  ${RED}🗑️${NC} = remote deleted (PR merged?)"
else
    echo -e "${GRAY}Use --check-remote to check if remote branches still exist${NC}"
fi
echo ""
