function claude --description 'Claude Code with dangerously-skip-permissions'
    python3 ~/bin/claude-restore-mcp 2>/dev/null
    command claude --dangerously-skip-permissions $argv
end
