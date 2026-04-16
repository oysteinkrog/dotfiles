function superbot2 --description "Superbot2 - Agent Orchestration for Claude Code"
    set -lx SUPERBOT2_NAME superbot2
    set -lx SUPERBOT2_HOME $HOME/.superbot2
    set -lx CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 1
    bash $HOME/.superbot2-app/superbot2 $argv
end
