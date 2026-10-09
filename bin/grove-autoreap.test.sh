#!/usr/bin/env bash
# Tests for grove-autoreap with fake lanes made by the real grove binary.
# Everything lives under /var/tmp/claude/grove-autoreap-test.<pid>, with HOME
# and the XDG dirs pointed there, so the real registry and state are never read.
# Run: bin/grove-autoreap.test.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
reap=$here/grove-autoreap
real_grove=$(command -v grove) || { echo "grove not on PATH" >&2; exit 1; }

T=/var/tmp/claude/grove-autoreap-test.$$
mkdir -p "$T"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
  rm -rf "$T"
}
trap cleanup EXIT

export HOME=$T/home XDG_CONFIG_HOME=$T/home/.config XDG_STATE_HOME=$T/home/.local/state \
  XDG_DATA_HOME=$T/home/.local/share XDG_CACHE_HOME=$T/home/.cache XDG_RUNTIME_DIR=$T/run
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$XDG_CONFIG_HOME/grove" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR/heavy-build.jobs" "$XDG_RUNTIME_DIR/heavy-build.queue"
git config --global init.defaultBranch master

W=$T/work
git init -q --bare "$T/origin.git"
git init -q "$W/master"
git -C "$W/master" commit -q --allow-empty -m init
git -C "$W/master" remote add if "$T/origin.git"
git -C "$W/master" remote add my "$T/origin.git"
git -C "$W/master" push -q if master
git -C "$W/master" fetch -q if
mkdir -p "$W/.grove"
echo '{"schema_version":1,"projects":{}}' >"$W/.grove/registry.json"
cat >"$XDG_CONFIG_HOME/grove/repos.json" <<EOF
{"schema_version":1,"default_repo":"t","repos":{"t":{"main_repo":"$W/master","work_dir":"$W","dir_prefix":"","upstream_remote":"if","fork_remote":"my","default_base":"master","issue_prefix":"T"}}}
EOF

# A grove wrapper that reports owners from $T/alive as alive.
cat >"$T/grove" <<EOF
#!/usr/bin/env bash
if [[ \${1:-} == who ]] && grep -qx "\${2:-}" "$T/alive" 2>/dev/null; then
  printf 'tag:          %s\nstatus:       alive\nsession:      owner-s\nagent:        OwnerAgent\n' "\$2"
  exit 0
fi
exec "$real_grove" "\$@"
EOF
chmod +x "$T/grove"
touch "$T/alive"

lane() { # tag ttl
  (cd "$W/master" && "$real_grove" new "$1" --ephemeral --ttl "$2" --no-fetch >/dev/null 2>&1) \
    || { echo "could not make lane $1" >&2; exit 1; }
}
lp() { echo "$W/.scratch/$1"; }

lane clean 1s
lane clean-2 1s          # name shares a prefix with "clean"
lane dirty 1s
lane unpushed 1s
lane inuse 1s
lane hb 1s
lane owned 1s
lane frozen 1s
lane fresh 14d
lane pushed 1s

echo scratch >"$(lp dirty)/notes.txt"
git -C "$(lp unpushed)" commit -q --allow-empty -m local-only
git -C "$(lp pushed)" commit -q --allow-empty -m pushed
git -C "$(lp pushed)" push -q my HEAD:refs/heads/pushed-branch
git -C "$W/master" fetch -q my
(cd "$(lp inuse)" && exec sleep 600) & pids+=($!)
(cd "$(lp clean-2)" && exec sleep 600) & pids+=($!)
printf 'heavy-build-x 1 1 1 1 1 1 1 1 0 normal tree:%s\n' "$(lp hb)" >"$XDG_RUNTIME_DIR/heavy-build.jobs/heavy-build-x"
printf 'q\nnormal 8 8 600 tree:%s-other\n' "$(lp clean)" >"$XDG_RUNTIME_DIR/heavy-build.queue/1-q"
echo owned >"$T/alive"
(cd "$W/master" && "$real_grove" freeze frozen >/dev/null 2>&1)
sleep 2

S=$T/state
run() { GROVE_AUTOREAP_GROVE=$T/grove GROVE_AUTOREAP_STATE=$S "$@" "$reap"; }
# "verdict/reason" for a tag in the newest report. The owner of a test lane is
# gone or unknown depending on the environment, so owner-* reasons become owner.
verdict() {
  awk -F'\t' -v t="$1" '$1 == t {sub(/^owner-(gone|unknown|dormant)$/, "owner", $3); print $2 "/" $3}' \
    "$(ls -t "$S"/report-*.tsv | head -1)"
}

fail=0
check() { # description expected actual
  if [[ $2 == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; fail=1; fi
}

registry_before=$(md5sum <"$W/.grove/registry.json")
out=$(run env GROVE_AUTOREAP_MODE=report)
echo "  $out"
check "report: clean lane would be removed" "reap/owner" "$(verdict clean)"
check "report: process in clean-2 keeps it" "keep/in-use" "$(verdict clean-2)"
check "report: untracked file keeps lane" "keep/dirty" "$(verdict dirty)"
check "report: local-only commit keeps lane" "keep/unpushed" "$(verdict unpushed)"
check "report: process cwd keeps lane" "keep/in-use" "$(verdict inuse)"
check "report: heavy-build lock key keeps lane" "keep/heavy-build" "$(verdict hb)"
check "report: alive owner needs a notice" "notice/owner-alive" "$(verdict owned)"
check "report: frozen lane is kept" "keep/frozen" "$(verdict frozen)"
check "report: unexpired lane is not a candidate" "" "$(verdict fresh)"
check "report: commit pushed to the fork counts as pushed" "reap/owner" "$(verdict pushed)"
check "report: registry unchanged" "$registry_before" "$(md5sum <"$W/.grove/registry.json")"
check "report: no lane removed" "9" "$(ls "$W/.scratch" | grep -vc fresh)"
check "report: no notice written" "0" "$(wc -l <"$S/notices.tsv")"
check "report: summary counts" "1" "$(grep -c 'would remove 2 ' <<<"$out")"

now=$(date +%s)
out=$(run env GROVE_AUTOREAP_MODE=live GROVE_AUTOREAP_NOW="$now")
echo "  $out"
check "live: clean lane removed" "no" "$([[ -d $(lp clean) ]] && echo yes || echo no)"
check "live: pushed lane removed" "no" "$([[ -d $(lp pushed) ]] && echo yes || echo no)"
check "live: clean lane deregistered" "null" "$(jq -c '.projects.clean' "$W/.grove/registry.json")"
check "live: fork branch kept (--keep-remote)" "1" "$(git -C "$T/origin.git" branch --list pushed-branch | wc -l)"
for t in clean-2 dirty unpushed inuse hb owned frozen fresh; do
  check "live: $t still on disk" "yes" "$([[ -d $(lp "$t") ]] && echo yes || echo no)"
done
check "live: notice logged for owned" "1" "$(grep -c 'grove lane owned ' "$S/notices.log")"

out=$(run env GROVE_AUTOREAP_MODE=live GROVE_AUTOREAP_NOW=$(( now + 3600 )))
check "live: owned waits inside the grace period" "wait/owner-alive-notified" "$(verdict owned)"
check "live: owned still on disk after 1 h" "yes" "$([[ -d $(lp owned) ]] && echo yes || echo no)"
check "live: no second notice" "1" "$(grep -c 'grove lane owned ' "$S/notices.log")"

out=$(run env GROVE_AUTOREAP_MODE=live GROVE_AUTOREAP_NOW=$(( now + 21 * 3600 )))
echo "  $out"
check "live: owned removed after the grace period" "no" "$([[ -d $(lp owned) ]] && echo yes || echo no)"
check "live: notice entry cleared" "0" "$(grep -c '^owned' "$S/notices.tsv")"
check "live: grove done logged" "1" "$(grep -c 'removed owned' "$S/reaped.log")"

check "bad mode is refused" "2" "$(GROVE_AUTOREAP_MODE=yes "$reap" >/dev/null 2>&1; echo $?)"

exit "$fail"
