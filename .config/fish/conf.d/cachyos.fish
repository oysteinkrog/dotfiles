# Picks from the CachyOS default fish config (/usr/share/cachyos-fish-config).
# Only loads on CachyOS, so WSL and other machines are unaffected. The fastfetch
# greeting is left out on purpose: functions/fish_greeting.fish is ours.
test -d /usr/share/cachyos-fish-config; or return
status is-interactive; or return

# Desktop notification when a command that ran >10s finishes in an unfocused window
source /usr/share/cachyos-fish-config/conf.d/done.fish
set -g __done_min_cmd_duration 10000
set -g __done_notification_urgency_level low

# Colored man pages via bat
set -x MANROFFOPT "-c"
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

# !! expands to the previous command, !$ to its last argument
function __history_previous_command
    switch (commandline -t)
        case "!"
            commandline -t $history[1]; commandline -f repaint
        case "*"
            commandline -i !
    end
end

function __history_previous_command_arguments
    switch (commandline -t)
        case "!"
            commandline -t ""
            commandline -f history-token-search-backward
        case "*"
            commandline -i '$'
    end
end

if [ "$fish_key_bindings" = fish_vi_key_bindings ]
    bind -Minsert ! __history_previous_command
    bind -Minsert '$' __history_previous_command_arguments
else
    bind ! __history_previous_command
    bind '$' __history_previous_command_arguments
end

# ls via eza
alias ls='eza -al --color=always --group-directories-first --icons=always'
alias la='eza -a --color=always --group-directories-first --icons=always'
alias ll='eza -l --color=always --group-directories-first --icons=always'
alias lt='eza -aT --color=always --group-directories-first --icons=always'
alias l.="eza -a | grep -e '^\.'"

# Arch maintenance
alias update='sudo cachyos-rate-mirrors && sudo pacman -Syu'
alias mirror='sudo cachyos-rate-mirrors'
alias cleanup='sudo pacman -Rns (pacman -Qtdq)'
alias fixpacman='sudo rm /var/lib/pacman/db.lck'
alias jctl='journalctl -p 3 -xb'
alias rip="expac --timefmt='%Y-%m-%d %T' '%l\t%n %v' | sort | tail -200 | nl"
alias big="expac -H M '%m\t%n' | sort -h | nl"
alias hw='hwinfo --short'
