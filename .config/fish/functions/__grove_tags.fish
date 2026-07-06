function __grove_tags --description "Grove project tags (for tab completion)"
    # --no-status skips per-worktree git status (slow on DrvFs); ~0.2s total.
    command grove list --json --no-status 2>/dev/null | jq -r '.repos[].projects[].tag' 2>/dev/null
end
