#/bin/sh

# This script creates symlinks from the home directory to any desired dotfiles in ~/dotfiles
############################

########## Variables

# fix zsh iteration over space-separated words
setopt shwordsplit      # this can be unset by saying: unsetopt shwordsplit

dir=~/.dotfiles
olddir=~/.dotfiles_old
files=".gitconfig .vimrc .vimrc.remaps .vimrc.bundles .vsvimrc .ideavimrc .zprezto .vimperator .vimperatorrc .dir_colors .tmux.conf .minttyrc .githelpers .lesskey .ackrc .git_template .vim"


##########
export MSYS=winsymlinks:nativestrict

# create .dotfiles_old in homedir
echo "Creating $olddir for backup of any existing dotfiles in ~"
mkdir -p $olddir
echo "...done"

# change to the .dotfiles directory
echo "Changing to the $dir directory"
cd $dir
echo "...done"

# move any existing .dotfiles in homedir to dotfiles_old directory, then create symlinks 
echo "Moving any existing dotfiles from ~ to $olddir"
for file in $files; do
    mv ~/$file $olddir/
    echo "$dir/$file => ~/$file"
    ln -sf $dir/$file ~/$file
done

zsh install-prezto.sh
