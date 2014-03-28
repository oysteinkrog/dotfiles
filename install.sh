# This script creates symlinks from the home directory to any desired dotfiles in ~/dotfiles
############################

########## Variables

dir=~/.dotfiles
olddir=~/.dotfiles_old
files=".gitconfig .zshrc .vimrc.bundles.local .vimrc.local .vsvimrc .zshrc .oh-my-zsh .spf13-vim-3 .vimperator .vimperatorrc .dir_colors .tmux.conf .minttyrc .githelpers"


##########

# create .dotfiles_old in homedir
echo "Creating $olddir for backup of any existing dotfiles in ~"
mkdir -p $olddir
echo "...done"

# change to the .dotfiles directory
echo "Changing to the $dir directory"
cd $dir
echo "...done"

# move any existing .dotfiles in homedir to dotfiles_old directory, then create symlinks 
for file in $files; do
    echo "Moving any existing dotfiles from ~ to $olddir"
    mv ~/$file $olddir/
    echo "Creating symlink to $file in home directory."
    ln -s $dir/$file ~/$file
done

