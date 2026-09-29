# Shared helpers for setup/bootstrap.sh and setup/steps/*.sh. Source, do not run.

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
SETUP="$DOTFILES/setup"

# Machine profile: <DOTFILES_HOSTS>/<hostname>/host.sh. The profiles live in a private
# repo, cloned to ~/work/Life, because they name disks, networks and devices.
# DOTFILES_HOST=<name> picks another profile, DOTFILES_HOSTS=<dir> another folder.
HOSTS_ROOT="${DOTFILES_HOSTS:-$HOME/work/Life/setup/machines}"
HOST_NAME="${DOTFILES_HOST:-$(hostnamectl hostname 2>/dev/null || cat /etc/hostname)}"
HOST_DIR="$HOSTS_ROOT/$HOST_NAME"

# Defaults a host.sh can override.
HOST_PACKAGES=()          # extra pacman packages for this machine
HOST_AUR_PACKAGES=()      # extra AUR packages for this machine
HOST_PIPEWIRE_CONFS=()    # files in <profile>/pipewire/ to link into filter-chain.conf.d
HOST_UFW_LAN=""           # LAN subnet allowed to reach Sunshine and RDP, e.g. 192.168.1.0/24
HOST_KDE_SCALE=""         # kwinrc [Xwayland] Scale, e.g. 1.1
HOST_KRDP_MONITOR=""      # monitor index KRDP streams, for multi-monitor hosts, e.g. 1
host_system() { :; }      # extra root steps for this machine (runs inside the system step)

if [ -f "$HOST_DIR/host.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOST_DIR/host.sh"
  HOST_KNOWN=1
else
  HOST_KNOWN=0
fi

if [ -t 1 ]; then
  _b=$'\e[1m'; _g=$'\e[32m'; _y=$'\e[33m'; _r=$'\e[31m'; _n=$'\e[0m'
else
  _b=""; _g=""; _y=""; _r=""; _n=""
fi
step() { printf '\n%s=== %s ===%s\n' "$_b" "$*" "$_n"; }
ok()   { printf '  %sok%s    %s\n' "$_g" "$_n" "$*"; }
warn() { printf '  %swarn%s  %s\n' "$_y" "$_n" "$*"; }
fail() { printf '  %sFAIL%s  %s\n' "$_r" "$_n" "$*"; }
info() { printf '        %s\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Read a package list: one name per line. Blank lines, # comments and the
# "plainlang: skip" marker line (for the prose checker) are ignored.
read_list() { sed -e '/^plainlang:/d' -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | awk 'NF'; }

has_nvidia() { lspci 2>/dev/null | awk 'tolower($0) ~ /(vga|3d).*nvidia/ {f=1} END {exit !f}'; }
