# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="robbyrussell"

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
#plugins=(git)

source $ZSH/oh-my-zsh.sh

# Customize to your needs...
# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=2000
SAVEHIST=2000

setopt autocd extendedglob

bindkey -e #emacs keybindings
#bindkey -v  #vi keybindings

# End of lines configured by zsh-newuser-install
#autocorrection
autoload -Uz compinit
compinit
zstyle ':completion:*:descriptions' format '%U%B%d%b%u'
zstyle ':completion:*:warnings' format '%BSorry, no matches for: %d%b'
setopt correctall

#cache
zstyle ':completion::complete:*' use-cache 1

# prompt
autoload -U promptinit
promptinit


#if [[ "$TERM" != "dumb" ]]; then
    #if [[ -x `which dircolors` ]]; then
        #eval `dircolors -b`
        #alias 'ls=ls -lsah --color=auto'
    #fi
#fi

# auto screen session on login
#if [ -n "$SSH_CONNECTION" ] && [ -z "$SCREEN_EXIST" ]; then
#    export SCREEN_EXIST=1
#    exec screen -xR
#    screen -ARR
#fi

alias 'rsync-mv=rsync -a --progress --remove-source-files'
alias 'rsync-cp=rsync -a --progress'
alias ls='ls -lsa --color'

PROMPT=$'%{\e[0;32m%}%B[%b%{\e[0m%}%n%{\e[0;32m%}@%{\e[0m%}%(4c,./%1~,%~)%{\e[0;32m%}%B]%b% %(?,%{\e[0;32m%}:%)%{\e[0m%},%{\e[0;31m%}:(%{\e[0m%}) %# '

# To define styles for nested brackets up to level 4
ZSH_HIGHLIGHT_STYLES[bracket-level-1]='fg=pink,bold'
ZSH_HIGHLIGHT_STYLES[bracket-level-2]='fg=red,bold'
ZSH_HIGHLIGHT_STYLES[bracket-level-3]='fg=yellow,bold'
ZSH_HIGHLIGHT_STYLES[bracket-level-4]='fg=magenta,bold'

# load zsh-syntax-highlighting
. $HOME/.zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

