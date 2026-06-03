set PATH ~/.local/bin ~/.cargo/bin ~/bin ~/bin/gcmw /home/linuxbrew/.linuxbrew/bin ~/go/bin $PATH

# disable default vi mode prompt prefix
function fish_mode_prompt
end

starship init fish | source


set -U FZF_COMPLETE 2
set -U FZF_FIND_FILE_COMMAND "ag -l --hidden --ignore .git"
set -U FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border"

# opam configuration
#source /c/users/oystein/.opam/opam-init/init.fish > /dev/null 2> /dev/null; or true

# Node v22 via nvm — prepend directly to avoid the ~8s `nvm use` cost on every shell.
# If you switch node versions, update this path (or run `nvm use` manually).
if test -d ~/.nvm/versions/node/v22.14.0/bin
    fish_add_path -p ~/.nvm/versions/node/v22.14.0/bin
end

# Re-prepend ~/.local/bin so locally-installed Linux-native tools (e.g. the
# ELF `claude` at ~/.local/bin/claude) win over Windows .exe symlinks that
# nvm puts on PATH. Without this, subprocesses that resolve `claude` via
# PATH (e.g. tools/localization/smart-translation translator) get the
# Windows binary and fail with "Exec format error" under WSL1.
fish_add_path -p ~/.local/bin

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH

# dotnet alias
alias dotnet="dotnet.exe"

# ripgrep config
set -x RIPGREP_CONFIG_PATH "$HOME/.ripgreprc"

# WSL: use Windows browser for links (gh auth, xdg-open, etc.)
set -x BROWSER explorer.exe

# opencode
fish_add_path /c/users/oystein/.opencode/bin
