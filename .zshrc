# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="ys"

# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Set to this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Comment this out to disable bi-weekly auto-update checks
# DISABLE_AUTO_UPDATE="true"

# Uncomment to change how often before auto-updates occur? (in days)
# export UPDATE_ZSH_DAYS=13

# Uncomment following line if you want to disable colors in ls
# DISABLE_LS_COLORS="true"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment following line if you want to disable command autocorrection
# DISABLE_CORRECTION="true"

# Uncomment following line if you want red dots to be displayed while waiting for completion
# COMPLETION_WAITING_DOTS="true"

# Uncomment following line if you want to disable marking untracked files under
# VCS as dirty. This makes repository status check for large repositories much,
# much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(vim-mode git cp colorize extract)

source $ZSH/oh-my-zsh.sh

# Customize to your needs...
# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=2000
SAVEHIST=2000

setopt autocd extendedglob

#bindkey -e #emacs keybindings

# End of lines configured by zsh-newuser-install
#autocorrection
#
autoload -Uz compinit
compinit -u
zstyle ':completion:*:descriptions' format '%U%B%d%b%u'
zstyle ':completion:*:warnings' format '%BSorry, no matches for: %d%b'
setopt correctall

#cache
zstyle ':completion::complete:*' use-cache 1

# prompt
autoload -U promptinit
promptinit


command_exists ()
{
    command "$1" >/dev/null 2>&1;
}

alias 'rsync-mv=rsync -a --progress --remove-source-files'
alias 'rsync-cp=rsync -a --progress'

export CLICOLOR=1
export LSCOLOR=ExFxBxDxCxegedabagacad

if [ "$TERM" != "dumb" ]; then
    [ -e "$HOME/.dir_colors" ] && DIR_COLORS="$HOME/.dir_colors"
    [ -e "$DIR_COLORS" ] || DIR_COLORS=""
    eval "`dircolors -b $DIR_COLORS`"
    alias ls='ls --color=auto'
fi

if [[ uname == "Darwin" ]]; then
    alias ls='ls -lsG'
    alias la='ls -aG'
else
    alias ls='ls -ls --color'
    alias la='ls -a --color'
fi

if [[ `uname` =~ .*CYGWIN.* ]]; then
    # start ssh-pageant (if needed, the -r reuses the socket if already open)
    eval $(/usr/bin/ssh-pageant -ra /tmp/.ssh-pageant)

    if [[ ( -z `/cygdrive/c/Windows/system32/whoami /priv |grep SeCreateSymbolicLinkPrivilege`) ]]; then
        echo "Warning, you do not have the SeCreateSymbolicLinkPrivilege!, cygwin will not be able to use native symlinking" 
    else
        export CYGWIN="winsymlinks:native"
    fi
fi
