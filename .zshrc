# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="ys"

# Uncomment following line if you want red dots to be displayed while waiting for completion
COMPLETION_WAITING_DOTS="true"

# Uncomment following line if you want to disable marking untracked files under
# VCS as dirty. This makes repository status check for large repositories much,
# much faster.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(vim-mode git cp colorize extract common-aliases)

source $ZSH/oh-my-zsh.sh

HISTFILE=~/.histfile
HISTSIZE=2000
SAVEHIST=2000

# completion
autoload -Uz compinit
compinit -u

zstyle ':completion:*:descriptions' format '%U%B%d%b%u'
zstyle ':completion:*:warnings' format '%BSorry, no matches for: %d%b'

#cache
zstyle ':completion::complete:*' use-cache 1

# prompt
autoload -U promptinit

# correction
setopt correctall

# no need for cd
setopt autocd

### fancy globbing, e.g. "cp ^*.(tar|bz2|gz) ."
setopt extendedglob

# make cd push the old directory onto the directory stack
setopt auto_pushd

# red
export GREP_COLOR="0;31"

export CLICOLOR=1
export LSCOLOR=ExFxBxDxCxegedabagacad

if [ "$TERM" != "dumb" ]; then
    [ -e "$HOME/.dir_colors" ] && DIR_COLORS="$HOME/.dir_colors"
    [ -e "$DIR_COLORS" ] || DIR_COLORS=""
    eval "`dircolors -b $DIR_COLORS`"
    alias ls='ls --color=auto'
fi

if [[ uname == "Darwin" ]]; then
#    alias ls='ls -lsG'
#    alias la='ls -aG'
else
#    alias ls='ls -ls --color'
#    alias la='ls -a --color'
fi

if [[ `uname` =~ .*CYGWIN.* ]]; then
    # start ssh-pageant (if needed, the -r reuses the socket if already open)
    eval $(/usr/bin/ssh-pageant -ra /tmp/.ssh-pageant)

    if [[ ( -z `/cygdrive/c/Windows/system32/whoami /priv |grep SeCreateSymbolicLinkPrivilege`) ]]; then
        echo "Warning, you do not have the SeCreateSymbolicLinkPrivilege!, cygwin will not be able to use native symlinking" 
    else
        export CYGWIN="winsymlinks:native"
    fi
    alias cyg='apt-cyg -m http://mirrors.kernel.org/sources.redhat.com/cygwin/'
    alias cyp='apt-cyg -m http://mirrors.kernel.org/sources.redhat.com/cygwinports/'
fi

# misc
alias zshconfig="vim ~/.zshrc"
alias rsync-mv="rsync -a --progress --remove-source-files"
alias rsync-cp="rsync -a --progress"
alias cl='clear'

# git
alias ga='git add -A'
alias gp='git push'
alias gl='git log'
alias gs='git status'
alias gd='git diff'
alias gm='git commit -m'
alias gma='git commit -am'
alias gb='git branch'
alias gc='git checkout'
alias gra='git remote add'
alias grr='git remote rm'
alias gpu='git pull'
alias gpur='git pull --rebase'
alias gcl='git clone'
alias gta='git tag -a -m'
alias gf='git reflog'

alias glg="'C:/Program Files/TortoiseGit/bin/TortoiseGitProc.exe' /command:log /path:."

