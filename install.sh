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
  aiolos-rc
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

# Native Linux (not WSL): skip Windows-only configs and link the Linux git overrides
native_linux=""
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  native_linux=1
  config_dirs=("${config_dirs[@]/ConEmu}")
  linux_links=(".gitconfig.local:.gitconfig.linux")
fi

# Files inside .claude to symlink individually when ~/.claude is a real dir
claude_items=(
  CLAUDE.md
  settings.json
  agents
  mcp-servers.json
  hooks
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
  ln -sfn "$dir/$file" "$HOME/$file"
  echo "  $file -> $dir/$file"
done

for pair in "${linux_links[@]}"; do
  ln -sfn "$dir/${pair#*:}" "$HOME/${pair%%:*}"
  echo "  ${pair%%:*} -> $dir/${pair#*:}"
done

echo ""
echo "=== Linking bin ==="
if [ -e "$HOME/bin" ] && [ ! -L "$HOME/bin" ]; then
  mv "$HOME/bin" "$olddir/bin-backup"
  echo "  backed up ~/bin"
fi
ln -sfn "$dir/bin" "$HOME/bin"
echo "  bin -> $dir/bin"

echo ""
echo "=== Linking .config subdirectories ==="
mkdir -p "$HOME/.config"
for sub in "${config_dirs[@]}"; do
  [ -n "$sub" ] || continue
  if [ -e "$HOME/.config/$sub" ] && [ ! -L "$HOME/.config/$sub" ]; then
    mv "$HOME/.config/$sub" "$olddir/config-$sub"
    echo "  backed up .config/$sub"
  fi
  ln -sfn "$dir/.config/$sub" "$HOME/.config/$sub"
  echo "  .config/$sub -> $dir/.config/$sub"
done

echo ""
echo "=== Linking .claude config ==="
# Two layouts are supported:
#  - ~/.claude is a link to $dir/.claude (whole dir, so Claude's runtime state also
#    lands in the repo dir). Used when ~/.claude does not exist yet.
#  - ~/.claude is a real dir and only the items above are linked into it.
#    Set CLAUDE_LINK_ITEMS=1 to force this layout on a fresh machine.
if [ ! -e "$HOME/.claude" ] && [ ! -L "$HOME/.claude" ] && [ "${CLAUDE_LINK_ITEMS:-0}" != 1 ]; then
  ln -sfn "$dir/.claude" "$HOME/.claude"
  echo "  .claude -> $dir/.claude"
fi
# When ~/.claude is itself a link to $dir/.claude, the items are already in place.
if [ "$(realpath "$HOME/.claude" 2>/dev/null)" = "$(realpath "$dir/.claude")" ]; then
  echo "  ~/.claude -> $dir/.claude, nothing to link"
  claude_items=()
fi
mkdir -p "$HOME/.claude"
for item in "${claude_items[@]}"; do
  if [ -e "$HOME/.claude/$item" ] && [ ! -L "$HOME/.claude/$item" ]; then
    mv "$HOME/.claude/$item" "$olddir/claude-$item"
    echo "  backed up .claude/$item"
  fi
  ln -sfn "$dir/.claude/$item" "$HOME/.claude/$item"
  echo "  .claude/$item -> $dir/.claude/$item"
done

if [ -n "$native_linux" ]; then
  echo ""
  echo "=== Linking systemd user units (native Linux) ==="
  mkdir -p "$HOME/.config/systemd/user"
  units=()
  for unit_path in "$dir"/.config/systemd/user/*.service; do
    [ -e "$unit_path" ] || continue
    unit="$(basename "$unit_path")"
    target="$HOME/.config/systemd/user/$unit"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      mv "$target" "$olddir/systemd-$unit"
      echo "  backed up .config/systemd/user/$unit"
    fi
    ln -sfn "$unit_path" "$target"
    echo "  .config/systemd/user/$unit -> $unit_path"
    units+=("$unit")
  done
  if [ ${#units[@]} -gt 0 ]; then
    echo "  to start them: systemctl --user daemon-reload && systemctl --user enable --now ${units[*]}"
  fi

  echo ""
  echo "=== Linking tools into ~/.local/bin (native Linux) ==="
  # Claude Code hooks call dcg by bare name, and Claude may start without ~/bin on PATH.
  mkdir -p "$HOME/.local/bin"
  if [ -e "$dir/bin/dcg" ]; then
    if [ -e "$HOME/.local/bin/dcg" ] && [ ! -L "$HOME/.local/bin/dcg" ]; then
      mv "$HOME/.local/bin/dcg" "$olddir/local-bin-dcg"
      echo "  backed up .local/bin/dcg"
    fi
    ln -sfn "$dir/bin/dcg" "$HOME/.local/bin/dcg"
    echo "  .local/bin/dcg -> $dir/bin/dcg"
  else
    echo "  bin/dcg not found (it is not in git), skipping. Install dcg into bin/ and run again."
  fi
fi

echo ""
echo "=== Activating dotfiles repo hooks ==="
if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
  git -C "$dir" config core.hooksPath .git_template/hooks
  echo "  core.hooksPath -> .git_template/hooks (secret-guard active)"
fi

echo ""
echo "=== Done ==="
