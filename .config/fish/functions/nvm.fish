function nvm
    # The Arch nvm package installs nvm.sh under /usr/share/nvm; a git install uses ~/.nvm.
    set -l nvm_sh ~/.nvm/nvm.sh
    test -f $nvm_sh; or set nvm_sh /usr/share/nvm/nvm.sh
    set -q NVM_DIR; or set -gx NVM_DIR ~/.nvm
    bass source $nvm_sh --no-use ';' nvm $argv
end
