set PATH ~/.cargo/bin ~/bin ~/bin/gcmw /home/linuxbrew/.linuxbrew/bin ~/go/bin $PATH

# disable default vi mode prompt prefix
function fish_mode_prompt
end

starship init fish | source

# opam configuration
#source /c/users/oystein/.opam/opam-init/init.fish > /dev/null 2> /dev/null; or true
