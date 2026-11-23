#!/bin/sh
# Build krdp-blank into $1 (default: ~/.cache/krdp-blank/krdp-blank). Takes about a second.
# Needs gcc, wayland, wayland-protocols and plasma-wayland-protocols.
set -eu
src=$(cd "$(dirname "$0")" && pwd)
out=${1:-${XDG_CACHE_HOME:-$HOME/.cache}/krdp-blank/krdp-blank}
gen=$(mktemp -d /var/tmp/krdp-blank.XXXXXX)
trap 'rm -rf "$gen"' EXIT
wp=/usr/share/wayland-protocols
for xml in "$src/wlr-layer-shell-unstable-v1.xml" \
           "$wp/stable/viewporter/viewporter.xml" \
           "$wp/stable/xdg-shell/xdg-shell.xml" \
           "$wp/staging/single-pixel-buffer/single-pixel-buffer-v1.xml" \
           /usr/share/plasma-wayland-protocols/kde-lockscreen-overlay-v1.xml; do
  base=$(basename "$xml" .xml)
  wayland-scanner client-header "$xml" "$gen/$base-client-protocol.h"
  wayland-scanner private-code "$xml" "$gen/$base-protocol.c"
done
mkdir -p "$(dirname "$out")"
cc -O2 -Wall -Wextra -Wno-unused-parameter -I"$gen" -o "$out.tmp" "$src/krdp-blank.c" "$gen"/*-protocol.c -lwayland-client
mv "$out.tmp" "$out"
echo "$out"
