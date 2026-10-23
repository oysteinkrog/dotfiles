#!/usr/bin/env bash
# Install tasklens on this machine by repacking the build installed on another desktop,
# instead of compiling it again (a release build takes a long time).
#   setup/tasklens-from-host.sh <ssh host>
# The other desktop has the pacman package tasklens, built there with
# ~/work/tasklens/packaging/PKGBUILD (makepkg -si). makepkg does not keep the .pkg.tar.zst,
# so this copies the installed files and wraps them in a package with the same name,
# version and dependencies. The build is generic x86_64, so it runs on Intel and AMD.
# To build from source instead: cd ~/work/tasklens/packaging && makepkg -si
set -euo pipefail

host="${1:?usage: tasklens-from-host.sh <ssh host>}"
ver="$(ssh "$host" pacman -Q tasklens | awk '{print $2}')"
pkgver="${ver%-*}" pkgrel="${ver##*-}"
work="/var/tmp/claude/tasklens-repack-$pkgver"
mkdir -p "$work/files"

ssh "$host" 'pacman -Qlq tasklens | tar --no-recursion -cf - -T - 2>/dev/null' | tar -xf - -C "$work/files"
want="$(ssh "$host" sha256sum /usr/bin/tasklens | awk '{print $1}')"
got="$(sha256sum "$work/files/usr/bin/tasklens" | awk '{print $1}')"
[ "$want" = "$got" ] || { echo "tasklens: copied binary does not match $host" >&2; exit 1; }

cat >"$work/PKGBUILD" <<EOF
# Repack of tasklens $ver as installed on $host. Nothing is compiled here.
pkgname=tasklens
pkgver=$pkgver
pkgrel=$pkgrel
pkgdesc='Task manager for Linux'
arch=('x86_64')
license=('MIT')
depends=('wayland' 'libxkbcommon' 'libxkbcommon-x11' 'libxcb' 'fontconfig' 'vulkan-icd-loader' 'polkit')
optdepends=('nvidia-utils: NVIDIA GPU monitoring')
options=('!strip' '!lto' '!debug')
package() {
  cp -a "\$startdir/files/." "\$pkgdir/"
}
EOF
(cd "$work" && makepkg -f --nodeps >/dev/null)
sudo pacman -U --noconfirm "$work/tasklens-$ver-x86_64.pkg.tar.zst"
