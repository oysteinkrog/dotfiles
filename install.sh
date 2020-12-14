#/bin/sh

# This script creates symlinks from the home directory to any desired dotfiles in ~/dotfiles
############################

########## Variables

# fix zsh iteration over space-separated words
setopt shwordsplit      # this can be unset by saying: unsetopt shwordsplit

HOME="/c/users/oystein"
dir=$HOME/.dotfiles
olddir=$HOME/.dotfiles_old
files=".gitconfig .vimrc .vimrc.remaps .vimrc.bundles .vsvimrc .ideavimrc .zprezto .vimperator .vimperatorrc .cvimrc .dir_colors .tmux.conf .minttyrc .githelpers .lesskey .ackrc .git_template .vim .config"


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
    mv $HOME/$file $olddir/
    echo "$dir/$file => $HOME/$file"
    ln -sf $dir/$file $HOME/$file
done

# setup prezto
setopt EXTENDED_GLOB
for file in $dir/.zprezto/runcoms/^README.md(.N); do
    echo "$dir/$file => $HOME/$file"
  ln -sf "$file" "$HOME/.${file:t}"
done
