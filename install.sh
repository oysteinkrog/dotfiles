#!/bin/bash

# Symlink dotfiles from ~/.dotfiles into $HOME
# Backs up existing files to ~/.dotfiles_old

set -e

HOME="${HOME:-/mnt/c/Users/Oystein}"
dir="$HOME/.dotfiles"
olddir="$HOME/.dotfiles_old"

# Files/dirs to symlink directly into $HOME
files=(
  .ackrc
  .cvimrc
  .dir_colors
  .git_template
  .gitconfig
  .githelpers
  .ideavimrc
  .inputrc
  .lesskey
  .minttyrc
  .ripgreprc
  .tmux.conf
  .vim
  .vimperator
  .vimperatorrc
  .vimrc
  .vimrc.bundles
  .vimrc.remaps
  .vsvimrc
  .wezterm.lua
  .zprezto
  .aider.conf.yml
)

# Subdirectories inside .config to symlink individually
config_dirs=(
  ConEmu
  fish
  fisher
  nvim
  omf
  pm2
  rclone
  tridactyl
  wezterm
)

# Files inside .claude to symlink individually (not the whole dir — it has runtime state)
claude_items=(
  CLAUDE.md
  settings.json
  agents
  mcp-servers.json
  output
  skills
)

mkdir -p "$olddir"

echo "=== Linking dotfiles ==="
for file in "${files[@]}"; do
  if [ -e "$HOME/$file" ] && [ ! -L "$HOME/$file" ]; then
    mv "$HOME/$file" "$olddir/"
    echo "  backed up $file"
  fi
  ln -sf "$dir/$file" "$HOME/$file"
  echo "  $file -> $dir/$file"
done

echo ""
echo "=== Linking bin ==="
if [ -e "$HOME/bin" ] && [ ! -L "$HOME/bin" ]; then
  mv "$HOME/bin" "$olddir/bin-backup"
  echo "  backed up ~/bin"
fi
ln -sf "$dir/bin" "$HOME/bin"
echo "  bin -> $dir/bin"

echo ""
echo "=== Linking .config subdirectories ==="
mkdir -p "$HOME/.config"
for sub in "${config_dirs[@]}"; do
  if [ -e "$HOME/.config/$sub" ] && [ ! -L "$HOME/.config/$sub" ]; then
    mv "$HOME/.config/$sub" "$olddir/config-$sub"
    echo "  backed up .config/$sub"
  fi
  ln -sf "$dir/.config/$sub" "$HOME/.config/$sub"
  echo "  .config/$sub -> $dir/.config/$sub"
done

echo ""
echo "=== Linking .claude config ==="
mkdir -p "$HOME/.claude"
for item in "${claude_items[@]}"; do
  if [ -e "$HOME/.claude/$item" ] && [ ! -L "$HOME/.claude/$item" ]; then
    mv "$HOME/.claude/$item" "$olddir/claude-$item"
    echo "  backed up .claude/$item"
  fi
  ln -sf "$dir/.claude/$item" "$HOME/.claude/$item"
  echo "  .claude/$item -> $dir/.claude/$item"
done

echo ""
echo "=== Done ==="
