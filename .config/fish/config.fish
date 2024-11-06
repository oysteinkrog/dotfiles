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
