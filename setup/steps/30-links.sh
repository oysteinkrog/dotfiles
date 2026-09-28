# Symlink the dotfiles into $HOME. install.sh does the work; it backs up real
# files to ~/.dotfiles_old before replacing them.

step "links"
bash "$DOTFILES/install.sh" | sed 's/^/  /'

# Wine creates these when a Windows app registers file types. They clutter the menu.
rm -f "$HOME"/.local/share/applications/wine-extension-*.desktop
have kbuildsycoca6 && kbuildsycoca6 >/dev/null 2>&1 || true
