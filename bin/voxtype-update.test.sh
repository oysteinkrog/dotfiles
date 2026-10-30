#!/usr/bin/env bash
# Tests for voxtype-update. Each test gets its own git repos, machine profile, state dir
# and stub commands (pacman, localbuild, systemctl, job, notify-send, voxtype), so
# nothing real is installed or restarted.
# Run: bash ~/.dotfiles/bin/voxtype-update.test.sh
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT=$HERE/voxtype-update
mkdir -p /var/tmp/claude; ROOT=$(mktemp -d /var/tmp/claude/voxtype-update-test.XXXXXX)
trap '[ -n "${KEEP:-}" ] || rm -rf -- "$ROOT"' EXIT
pass=0 fail=0
NOW=1800000000

g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

setup() {
  T=$ROOT/$1; mkdir -p "$T/bin" "$T/state" "$T/hosts/t" "$T/cfg/config.d"
  for r in lb dot; do
    g init -q --bare "$T/$r.git"
    g clone -q "$T/$r.git" "$T/$r" 2>/dev/null
  done
  mkdir -p "$T/lb/recipes/voxtype"
  echo "PIN=aaaaaaaaaa1111111111" > "$T/lb/recipes/voxtype/recipe.sh"
  g -C "$T/lb" add -A && g -C "$T/lb" commit -qm pin && g -C "$T/lb" push -q origin HEAD 2>/dev/null
  g -C "$T/dot" commit -q --allow-empty -m base && g -C "$T/dot" push -q origin HEAD 2>/dev/null
  printf 'HOST_VOXTYPE_VARIANT=cuda\nHOST_VOXTYPE_PEERS=(peer1)\n' > "$T/hosts/t/host.sh"
  echo 'engine = "cohere"' > "$T/cfg/config.toml"
  echo "1.1.1.gaaaaaaaaaa-1" > "$T/pkgver"
  echo idle > "$T/status"
  presence away 10
  cat > "$T/bin/pacman" <<EOF
#!/bin/sh
echo "voxtype-cuda-local \$(cat $T/pkgver)"
EOF
  cat > "$T/bin/localbuild" <<EOF
#!/bin/sh
echo "localbuild \$*" >> $T/calls
case "\$1" in
  fetch) [ -f $T/peer-has ] ;;
  install) cp $T/peer-has $T/pkgver ;;
esac
EOF
  cat > "$T/bin/voxtype" <<EOF
#!/bin/sh
cat $T/status
EOF
  for c in systemctl job notify-send; do
    printf '#!/bin/sh\necho "%s $*" >> %s/calls\n' "$c" "$T" > "$T/bin/$c"
  done
  chmod +x "$T"/bin/*
  export PATH="$T/bin:$PATH" DOTFILES_HOSTS=$T/hosts DOTFILES_HOST=t \
    VXS_LOCALBUILDS=$T/lb VXS_DOTFILES=$T/dot VXS_VOXTYPE=$T/bin/voxtype VXS_STATE=$T/state \
    VXS_PRESENCE=$T/presence VXS_CONFIG_DIR=$T/cfg VXS_NOW=$NOW VXS_HOUR=14 \
    XDG_CONFIG_HOME=$T/xdg
}
presence() { printf '{"state": "%s", "updated": %s}\n' "$1" "$((NOW - $2))" > "$T/presence"; }
# A new PIN upstream that peer1 has built.
new_pin() {
  g clone -q "$T/lb.git" "$T/lb-other" 2>/dev/null
  echo "PIN=bbbbbbbbbb2222222222" > "$T/lb-other/recipes/voxtype/recipe.sh"
  g -C "$T/lb-other" commit -qam bump && g -C "$T/lb-other" push -q origin HEAD 2>/dev/null
  echo "1.1.1.gbbbbbbbbbb-1" > "$T/peer-has"
}
run() { bash "$SCRIPT" --live > "$T/out" 2>&1; }
calls() { cat "$T/calls" 2>/dev/null; }
has() { calls | grep -q -- "$1"; }

t() {
  local name=$1; shift
  if ( setup "$name"; "$@" ); then pass=$((pass + 1)); echo "ok   $name"
  else fail=$((fail + 1)); echo "FAIL $name"; cat "$ROOT/$name/out" 2>/dev/null | sed 's/^/     /'; fi
}

same_pin_does_nothing() {
  run && ! has localbuild && ! has systemctl && grep -q 'up to date' "$T/out"
}
new_pin_while_recording_installs_nothing() {
  new_pin; echo recording > "$T/status"
  run && has 'localbuild fetch voxtype@cuda --from peer1' && ! has 'localbuild install' && ! has systemctl
}
new_pin_idle_and_away_installs_and_restarts() {
  new_pin
  run && has 'localbuild install voxtype@cuda' && has 'systemctl --user restart voxtype.service' &&
    git -C "$T/lb" log -1 --format=%s | grep -q bump && [ ! -e "$T/state/pending-since" ]
}
idle_but_here_waits_then_gives_in_after_a_day() {
  new_pin; presence here 5
  run && ! has systemctl || return 1
  echo $((NOW - 90000)) > "$T/state/pending-since"
  run && has 'systemctl --user restart voxtype.service'
}
stale_presence_is_not_away() {
  new_pin; presence away 600
  run && ! has systemctl
}
diverged_repo_is_left_alone() {
  new_pin
  g -C "$T/lb" commit -q --allow-empty -m local
  run && grep -q 'not pulling it' "$T/out" && git -C "$T/lb" log -1 --format=%s | grep -q local &&
    ! has localbuild
}
config_change_restarts_without_install() {
  run || return 1
  echo '[osd]' > "$T/cfg/config.d/50-host.toml"
  run && has 'systemctl --user restart voxtype.service' && ! has 'localbuild install'
}
dry_run_changes_nothing() {
  new_pin
  bash "$SCRIPT" --dry-run > "$T/out" 2>&1 && ! has localbuild && ! has systemctl &&
    grep -q 'would install and restart' "$T/out" && git -C "$T/lb" log -1 --format=%s | grep -q pin
}
no_peer_builds_at_night_only() {
  new_pin; rm "$T/peer-has"
  run && ! has 'job submit' && grep -q 'between 01:00 and 06:00' "$T/out" || return 1
  VXS_HOUR=3 run && has 'job submit --detach -- localbuild build voxtype@cuda' && ! has systemctl
}

t same_pin_does_nothing same_pin_does_nothing
t new_pin_while_recording_installs_nothing new_pin_while_recording_installs_nothing
t new_pin_idle_and_away_installs_and_restarts new_pin_idle_and_away_installs_and_restarts
t idle_but_here_waits_then_gives_in_after_a_day idle_but_here_waits_then_gives_in_after_a_day
t stale_presence_is_not_away stale_presence_is_not_away
t diverged_repo_is_left_alone diverged_repo_is_left_alone
t config_change_restarts_without_install config_change_restarts_without_install
t dry_run_changes_nothing dry_run_changes_nothing
t no_peer_builds_at_night_only no_peer_builds_at_night_only
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
