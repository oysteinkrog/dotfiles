set PATH ~/.local/bin ~/.cargo/bin ~/bin ~/bin/gcmw /home/linuxbrew/.linuxbrew/bin ~/go/bin $PATH

triton jethrokuan/fzf

# disable default vi mode prompt prefix
function fish_mode_prompt
end

starship init fish | source


set -U FZF_COMPLETE 2
set -U FZF_FIND_FILE_COMMAND "ag -l --hidden --ignore .git"
set -U FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border"

# opam configuration
#source /c/users/oystein/.opam/opam-init/init.fish > /dev/null 2> /dev/null; or true

# Set NVM default Node version
if test -d ~/.nvm
    nvm use 22 >/dev/null 2>&1
end

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH

# dotnet alias
alias dotnet="dotnet.exe"

# ripgrep config
set -x RIPGREP_CONFIG_PATH "$HOME/.ripgreprc"

# Auto-start shared MCP services via PM2
if type -q pm2
    if not pm2 pid pal-mcp >/dev/null 2>&1; or test (pm2 pid pal-mcp 2>/dev/null) = "0"
        pm2 start ~/.config/pm2/ecosystem.config.js 2>/dev/null
    end
end
