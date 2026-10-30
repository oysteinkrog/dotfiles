#!/usr/bin/env bash
# Tests for claude-persist.sh plan (and the opencode session lookup). Each test
# gets its own HOME, state dir and copy of the script, and a fake mux id, so no
# live entry, mux server or tab is touched and nothing is spawned.
# Run: bash ~/.dotfiles/.claude/hooks/claude-persist.test.sh
# CLAUDE_PERSIST_SH=<path> tests another copy of the script.
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT=${CLAUDE_PERSIST_SH:-$HERE/claude-persist.sh}
mkdir -p /var/tmp/claude; ROOT=$(mktemp -d /var/tmp/claude/claude-persist-test.XXXXXX)
BG=()
trap 'for p in "${BG[@]}"; do kill "$p" 2>/dev/null; done; [ -n "${KEEP:-}" ] || rm -rf -- "$ROOT"' EXIT
pass=0 fail=0
OLD=bootA:100   # the server that went away
NEW=bootB:200   # the server running plan

ok()   { pass=$((pass + 1)); echo "ok   $T_NAME: $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL $T_NAME: $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# setup NAME: a fresh HOME with ~/projects/life, ~/work/life and a script copy
# whose resume prompt helper renames an entry when $T/rename holds "FROM TO".
setup() {
  T_NAME=$1; T=$ROOT/$1
  H=$T/home; S=$T/state/claude-persist
  mkdir -p "$H/projects/life" "$H/work/life" "$H/projects/xpeng" "$H/.claude/sessions" \
           "$S/sessions" "$T/hooks"
  cp "$SCRIPT" "$T/hooks/claude-persist.sh"
  cat > "$T/hooks/claude-persist-resume.py" <<EOF
import json, os
r = "$T/rename"
if os.path.exists(r):
    # what retire-work-symlinks does: write the entry under the new folder's
    # name with the new cwd, then remove the old one
    a, b, cwd = open(r).read().split()
    e = json.load(open(a))
    e["cwd"] = cwd
    json.dump(e, open(b, "w"))
    os.remove(a)
    os.remove(r)
EOF
}

run_plan() {
  HOME=$H XDG_STATE_HOME=$T/state CLAUDE_PERSIST_MUX_ID=$NEW \
    CLAUDE_PERSIST_BIN=/usr/bin/claude CLAUDE_TAB_RUN_BIN=/nonexistent \
    OPENCODE_DB=$T/opencode.db bash "$T/hooks/claude-persist.sh" plan
}

# entry SID CWD PANE STAMP [AGE_SECONDS]: write a session entry and its transcript
entry() {
  local sid=$1 cwd=$2 pane=$3 stamp=$4 age=${5:-100} slug f tr
  slug=$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')
  tr=$H/.claude/projects/$slug/$sid.jsonl
  mkdir -p "$(dirname "$tr")"
  echo '{"type":"user","entrypoint":"cli"}' > "$tr"
  f=$S/sessions/$sid@$slug.json
  jq -n --arg sid "$sid" --arg cwd "$cwd" --arg tr "$tr" --argjson pane "$pane" --arg m "$stamp" \
    '{session_id:$sid, cwd:$cwd, name:"", transcript:$tr, pid:999999, pane:$pane,
      launcher:[], flags:[], started:"2026-10-25T20:48:01+01:00"}
     + (if $m == "" then {} else {mux:$m} end)' > "$f"
  touch -d "@$(( $(date +%s) - age ))" "$f"
}

tab_order() { { echo "mux $1"; shift; for p in "$@"; do printf '0\t%s\n' "$p"; done; } > "$S/tab-order"; }

# --- 1. the 2026-10-30 race: an entry renamed while plan runs is still resumed
setup rename-race
tab_order "$OLD" 0 1 42
entry a1 "$H/projects/life" 0 "$OLD" 300
entry b2 "$H/projects/life" 1 "$OLD" 200
entry cfd2 "$H/work/life" 42 "$OLD" 100
# the first resume renames cfd2's entry the way retire-work-symlinks did
echo "$S/sessions/cfd2@$(printf '%s' "$H/work/life" | sed 's/[^A-Za-z0-9]/-/g').json $S/sessions/cfd2@$(printf '%s' "$H/projects/life" | sed 's/[^A-Za-z0-9]/-/g').json $H/projects/life" > "$T/rename"
out=$(run_plan)
check "three tabs printed" '[ "$(printf "%s\n" "$out" | grep -c .)" = 3 ]'
check "renamed entry is resumed" 'grep -q "^resume cfd2 ($H/projects/life)" "$S/restore.log"'
check "vanished name is logged" 'grep -q "^skip cfd2@.*work-life: the entry vanished during plan" "$S/restore.log"'
check "second pass is logged" 'grep -q "^found cfd2@.*projects-life after the first pass" "$S/restore.log"'
check "no entry left in sessions/" '[ -z "$(ls "$S/sessions")" ]'
check "no nameless drop line" '! grep -q "^drop : " "$S/restore.log"'

# --- 2. a live Claude at the last snapshot wins over an old stamp
setup live-wins
tab_order "$OLD" 0 1
entry fresh "$H/projects/life" 0 "$OLD"
entry stale "$H/projects/life" 1 "bootZ:7"
entry gone "$H/projects/life" 2 "bootZ:7"
entry nostamp "$H/projects/life" 3 ""
printf 'mux %s\nstale\nnostamp\n' "$OLD" > "$S/live"
out=$(run_plan)
check "stale but live is resumed" 'grep -q "^resume stale " "$S/restore.log"'
check "stale but live says why" 'grep -q "^keep stale .*running at the last snapshot" "$S/restore.log"'
check "unstamped but live is resumed" 'grep -q "^resume nostamp " "$S/restore.log"'
check "stale and not live is dropped with its stamp" 'grep -q "^drop gone .*(stamp bootZ:7)" "$S/restore.log"'
check "a live list of another server is ignored" '
  setup live-other; tab_order "$OLD" 0; entry s2 "$H/projects/life" 0 "bootZ:7"
  printf "mux bootQ:1\ns2\n" > "$S/live"; run_plan >/dev/null
  grep -q "^drop s2 " "$S/restore.log"'

# --- 3. every entry gets a log line, including unreadable ones
setup every-entry-logged
tab_order "$OLD" 0 1
entry r1 "$H/projects/life" 0 "$OLD"
entry r2 "$H/projects/life" 0 "$OLD" 500          # older one in the same pane
entry r3 "/nonexistent/folder" 1 "$OLD"
: > "$S/sessions/broken@x.json"
run_plan >/dev/null
check "older entry in the same pane is dropped" 'grep -q "^drop r2 .*same pane 0" "$S/restore.log"'
check "gone folder is dropped" 'grep -q "^drop r3: folder /nonexistent/folder is gone" "$S/restore.log"'
check "unreadable entry is dropped with its name" 'grep -q "^drop broken@x: unreadable entry" "$S/restore.log"'
check "plan line names the last mux" 'grep -q "^=== plan .*(last mux $OLD)" "$S/restore.log"'

# --- 4. a Claude still running is skipped, marked late, and named in the log
setup still-running
tab_order "$OLD" 0
entry run1 "$H/projects/life" 0 "$OLD"
sleep 60 & BG+=($!); pid=$!
echo "{\"sessionId\":\"run1\",\"kind\":\"interactive\"}" > "$H/.claude/sessions/$pid.json"
f=$(ls "$S/sessions/"run1@*.json)
jq --argjson p "$pid" '.pid = $p' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
run_plan >/dev/null
check "running session is skipped with a reason" 'grep -q "^skip run1: still running as pid $pid, resumed when it exits" "$S/restore.log"'
check "running session is marked late" '[ "$(jq -r .late "$f")" = "$OLD" ]'

# --- 5. shell and opencode tabs come back in tab order
setup panes
tab_order "$OLD" 5 0 6 7 8 9 10
entry c0 "$H/projects/life" 0 "$OLD"
{
  echo "mux $OLD"
  printf '0\t5\tshell\t%s\t\n' "$H/projects/life"
  printf '0\t0\tclaude\t%s\tc0\n' "$H/projects/life"
  printf '0\t6\topencode\t%s\tses_abc\n' "$H/projects/xpeng"
  printf '0\t7\topencode\t%s\t\n' "$H/projects/xpeng"
  printf '0\t8\tshell\t%s\t\n' "$H/work/xpeng"          # moved to ~/projects/xpeng
  printf '0\t9\tshell\t%s\t\n' "$H/nowhere"
  printf '0\t10\tother\t%s\tnvim\n' "$H/projects/life"
} > "$S/panes"
out=$(run_plan)
check "seven tabs printed" '[ "$(printf "%s\n" "$out" | grep -c .)" = 7 ]'
check "shell tab first, in its folder" '[ "$(printf "%s\n" "$out" | head -1 | cut -f3)" = "cd $H/projects/life" ]'
check "claude tab second" 'printf "%s\n" "$out" | sed -n 2p | grep -q -- "--resume c0"'
check "claude pane is not opened twice" 'grep -q "^skip pane 0 (claude): Claude session c0 is in it" "$S/restore.log"'
check "opencode resumes its session" 'printf "%s\n" "$out" | grep -qF "cd $H/projects/xpeng && opencode -s ses_abc"'
check "opencode without a session starts fresh, logged" 'grep -q "^reopen pane 7 .*opencode, started fresh: no session id was found" "$S/restore.log"'
check "moved folder is followed" 'grep -q "^pane 8: folder $H/work/xpeng is gone, using $H/projects/xpeng (moved)" "$S/restore.log"'
check "missing folder falls back to HOME, logged" 'grep -q "^pane 9: folder $H/nowhere is gone, opening in $H instead" "$S/restore.log"'
check "other program comes back as a shell, logged" 'grep -q "^reopen pane 10 .*it ran nvim, which is not restarted" "$S/restore.log"'
check "panes file is used once" '[ ! -e "$S/panes" ] && [ -e "$S/panes.used" ]'
out2=$(run_plan)
check "a second plan opens no tabs" '[ -z "$out2" ]'

# --- 6. run by hand against the live server: no stamp check, no shell tabs
setup by-hand
tab_order "$NEW" 0
entry h1 "$H/projects/life" 0 "bootZ:7"
printf 'mux %s\n0\t3\tshell\t%s\t\n' "$NEW" "$H/projects/life" > "$S/panes"
out=$(run_plan)
check "stamp is not checked by hand" 'grep -q "^resume h1 " "$S/restore.log"'
check "no shell tab by hand" '[ "$(printf "%s\n" "$out" | grep -c .)" = 1 ] && [ -e "$S/panes" ]'

# --- 7. opencode session lookup: the -s argument, else the database
setup opencode-lookup
mkdir -p "$H/real"; ln -s "$H/real" "$H/link"
sqlite3 "$T/opencode.db" "create table session (id text, directory text, parent_id text,
  time_archived integer, time_updated integer);
  insert into session values ('ses_old', '$H/real', null, null, 1000);
  insert into session values ('ses_child', '$H/real', 'ses_new', null, 9999999999999);
  insert into session values ('ses_new', '$H/link', null, null, $(( $(date +%s) * 1000 + 60000 )));"
(cd "$H/real" && exec sleep 60) & BG+=($!); spid=$!
bash -c 'sleep 60; :' opencode -s ses_arg & BG+=($!); apid=$!
sleep 0.2
lookup() { ( HOME=$H OPENCODE_DB=$T/opencode.db; source "$T/hooks/claude-persist.sh"; opencode_session "$@" ); }
check "session id from -s" '[ "$(lookup "$apid" "$H/real")" = ses_arg ]'
check "newest top-level session in the folder, through a symlink" '[ "$(lookup "$spid" "$H/real")" = ses_new ]'
check "nothing for a folder without sessions" '[ -z "$(lookup "$spid" "$H/projects/life")" ]'

# --- 8. a Claude with no ~/.claude/sessions/<pid>.json (seen with 2.1.312
# after `respawn`) is still found in its pane, recorded, stamped and listed live
setup no-sessions-file
mkdir -p "$H/.local/bin"
entry nosf "$H/projects/life" 42 "bootOLD:1"
# a fake Claude on its own pty: argv0 claude, --resume nosf, pane 3
script -qfc "cd $H/projects/life && WEZTERM_PANE=3 exec -a claude bash -c 'sleep 60; :' --resume nosf" /dev/null \
  </dev/null >/dev/null 2>&1 & BG+=($!)
cpid=""; for _ in $(seq 50); do
  cpid=$(pgrep -f -x "claude -c sleep 60; : --resume nosf" | head -1); [ -n "$cpid" ] && break; sleep 0.1
done
ctty=$(readlink "/proc/$cpid/fd/0" 2>/dev/null)
cat > "$H/.local/bin/frankenterm-gui" <<EOF
#!/bin/sh
echo '[{"window_id":0,"pane_id":3,"tty_name":"$ctty","cwd":"file:///nowhere/"}]'
EOF
chmod +x "$H/.local/bin/frankenterm-gui"
HOME=$H XDG_STATE_HOME=$T/state CLAUDE_PERSIST_MUX_ID=$NEW bash "$T/hooks/claude-persist.sh" snapshot
f=$S/sessions/nosf@$(printf '%s' "$H/projects/life" | sed 's/[^A-Za-z0-9]/-/g').json
check "fake Claude runs on a pty" '[ -n "$cpid" ] && [ "${ctty#/dev/pts/}" != "$ctty" ]'
check "pane is recorded as claude with its session id" 'grep -qP "^0\t3\tclaude\t$H/projects/life\tnosf\t$cpid$" "$S/panes"'
check "entry now names the running pid" '[ "$(jq -r .pid "$f")" = "$cpid" ]'
check "entry is stamped by this server" '[ "$(jq -r .mux "$f")" = "$NEW" ]'
check "session is in the live list" 'grep -qx nosf "$S/live"'
check "the recording is logged" 'grep -q "recorded nosf .*Claude pid $cpid in pane 3 had no entry with its pid" "$S/events.log"'

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
