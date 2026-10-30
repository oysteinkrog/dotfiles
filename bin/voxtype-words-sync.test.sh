#!/usr/bin/env bash
# Tests for voxtype-words-sync: two clones of one bare repo stand in for two machines.
# Run: bash ~/.dotfiles/bin/voxtype-words-sync.test.sh
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT=$HERE/voxtype-words-sync
mkdir -p /var/tmp/claude; ROOT=$(mktemp -d /var/tmp/claude/voxtype-words-sync-test.XXXXXX)
trap 'rm -rf -- "$ROOT"' EXIT
pass=0 fail=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false

setup() {
  T=$ROOT/$1; mkdir -p "$T/bin"
  printf '#!/bin/sh\necho "notify $*" >> %s/notices\n' "$T" > "$T/bin/notify-send"
  chmod +x "$T/bin/notify-send"
  export PATH="$T/bin:$PATH" XDG_CONFIG_HOME=$T/xdg
  git init -q --bare "$T/life.git"
  git clone -q "$T/life.git" "$T/a" 2>/dev/null
  mkdir -p "$T/a/setup/voxtype"
  printf 'setup/voxtype/corrections.jsonl merge=union\nsetup/voxtype/words-learned.toml merge=union\n' \
    > "$T/a/.gitattributes"
  printf '{"wrong":"one"}\n' > "$T/a/setup/voxtype/corrections.jsonl"
  printf '# Words voxtype learned\n"glim bot" = "GlimBot"\n' > "$T/a/setup/voxtype/words-learned.toml"
  echo notes > "$T/a/notes.md"
  git -C "$T/a" add -A && git -C "$T/a" commit -qm base && git -C "$T/a" push -q origin HEAD 2>/dev/null
  git clone -q "$T/life.git" "$T/b" 2>/dev/null
}
sync() { VXS_LIFE=$T/$1 VXS_STATE=$T/state-$1 bash "$SCRIPT" "${2:---live}" >> "$T/out" 2>&1; }
t() {
  local name=$1; shift
  if ( setup "$name"; "$@" ); then pass=$((pass + 1)); echo "ok   $name"
  else fail=$((fail + 1)); echo "FAIL $name"; sed 's/^/     /' "$ROOT/$name/out" 2>/dev/null; fi
}

both_machines_append_and_both_end_with_every_line() {
  echo '{"wrong":"two-a"}' >> "$T/a/setup/voxtype/corrections.jsonl"
  echo '{"wrong":"two-b"}' >> "$T/b/setup/voxtype/corrections.jsonl"
  echo 'pdq = "PDQ"' >> "$T/a/setup/voxtype/words-learned.toml"
  echo 'zed = "Zed9"' >> "$T/b/setup/voxtype/words-learned.toml"
  sync a && sync b && sync a || return 1
  for m in a b; do
    f=$T/$m/setup/voxtype
    [ "$(wc -l < "$f/corrections.jsonl")" = 3 ] || return 1
    grep -q PDQ "$f/words-learned.toml" && grep -q Zed9 "$f/words-learned.toml" || return 1
    ! grep -q '<<<<<<<' "$f/corrections.jsonl" "$f/words-learned.toml" || return 1
  done
  [ -z "$(git -C "$T/a" status --porcelain)" ] && [ -z "$(git -C "$T/b" status --porcelain)" ]
}
the_same_word_learned_twice_keeps_both_lines() {
  echo '"blue barrel" = "blueberry"' >> "$T/a/setup/voxtype/words-learned.toml"
  echo '"blue barrel" = "Blueberry"' >> "$T/b/setup/voxtype/words-learned.toml"
  sync a && sync b || return 1
  [ "$(grep -c 'blue barrel' "$T/b/setup/voxtype/words-learned.toml")" = 2 ] &&
    ! grep -q '<<<<<<<' "$T/b/setup/voxtype/words-learned.toml"
}
other_work_is_not_committed() {
  echo draft >> "$T/b/notes.md"
  echo '{"wrong":"x"}' >> "$T/b/setup/voxtype/corrections.jsonl"
  sync b || return 1
  git -C "$T/b" status --porcelain | grep -q 'notes.md' &&
    ! git -C "$T/b" show --stat HEAD | grep -q notes.md
}
a_blocked_merge_is_aborted_with_a_notice() {
  echo upstream >> "$T/a/notes.md"
  git -C "$T/a" commit -qam notes && git -C "$T/a" push -q 2>/dev/null
  echo local-edit >> "$T/b/notes.md"
  sync b || return 1
  grep -q 'merging' "$T/notices" && [ ! -e "$T/b/.git/MERGE_HEAD" ] && grep -q local-edit "$T/b/notes.md"
}
dry_run_changes_nothing() {
  echo '{"wrong":"y"}' >> "$T/b/setup/voxtype/corrections.jsonl"
  head=$(git -C "$T/b" rev-parse HEAD)
  sync b --dry-run || return 1
  [ "$(git -C "$T/b" rev-parse HEAD)" = "$head" ] && grep -q 'would commit' "$T/out"
}

t both_machines_append_and_both_end_with_every_line both_machines_append_and_both_end_with_every_line
t the_same_word_learned_twice_keeps_both_lines the_same_word_learned_twice_keeps_both_lines
t other_work_is_not_committed other_work_is_not_committed
t a_blocked_merge_is_aborted_with_a_notice a_blocked_merge_is_aborted_with_a_notice
t dry_run_changes_nothing dry_run_changes_nothing
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
