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

# --- 9. late sessions go back to their old places, not to the end in id order
# (2026-11-05: the mux server crashed after a reboot, 22 Claudes outlived it,
# and snapshot appended them sorted by session id)
setup late-order
mkdir -p "$H/.local/bin" "$T/bin"
# old server: claude c3, shell xpeng, claude a1, shell life, claude b2
{
  echo "mux $OLD"
  printf '0\t0\tclaude\t%s\tc3\t\n' "$H/projects/life"
  printf '0\t1\tshell\t%s\t\t\n' "$H/projects/xpeng"
  printf '0\t2\tclaude\t%s\ta1\t\n' "$H/projects/life"
  printf '0\t3\tshell\t%s\t\t\n' "$H/projects/life"
  printf '0\t4\tclaude\t%s\tb2\t\n' "$H/projects/life"
} > "$S/panes.used"
for e in "c3 0" "a1 2" "b2 4"; do
  set -- $e; entry "$1" "$H/projects/life" "$2" "$OLD"
  f=$(ls "$S/sessions/$1"@*.json); jq --arg m "$OLD" '.late = $m' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
# the new server already has the two shell tabs plan reopened
jq -n --arg x "$H/projects/xpeng" --arg l "$H/projects/life" \
  '[{window_id:0,tab_id:0,pane_id:0,cwd:("file://"+$x),tty_name:"/dev/pts/fake0"},
    {window_id:0,tab_id:1,pane_id:1,cwd:("file://"+$l),tty_name:"/dev/pts/fake1"}]' > "$T/mux.json"
cat > "$H/.local/bin/frankenterm-gui" <<EOF
#!/usr/bin/env python3
import json, sys
st = "$T/mux.json"
tabs = json.load(open(st))
a = sys.argv[2:]
def opt(n): return a[a.index(n) + 1]
if a[0] == "list":
    print(json.dumps(tabs))
elif a[0] == "spawn":
    n = max([t["pane_id"] for t in tabs] + [-1]) + 1
    tabs.append({"window_id": int(opt("--window-id")), "tab_id": n, "pane_id": n,
                 "cwd": "file://" + opt("--cwd"), "tty_name": "/dev/pts/fake%d" % n,
                 "cmd": a[-1]})
    print(n)
elif a[0] == "move-tab":
    t = next(t for t in tabs if t["tab_id"] == int(opt("--tab-id")))
    w = [x for x in tabs if x["window_id"] == t["window_id"] and x is not t]
    w.insert(int(opt("--index")), t)
    rest = iter(w)
    tabs = [next(rest) if x["window_id"] == t["window_id"] else x for x in tabs]
json.dump(tabs, open(st, "w"))
EOF
chmod +x "$H/.local/bin/frankenterm-gui"
# the server is up and the machine is not stopping, whatever this machine says
printf '#!/bin/sh\ncase "$*" in *is-system-running*) echo running ;; *is-active*) echo active ;; esac\n' > "$T/bin/systemctl"
chmod +x "$T/bin/systemctl"
PATH=$T/bin:$PATH HOME=$H XDG_STATE_HOME=$T/state CLAUDE_PERSIST_MUX_ID=$NEW \
  CLAUDE_PERSIST_BIN=/usr/bin/claude CLAUDE_TAB_RUN_BIN=/nonexistent \
  bash "$T/hooks/claude-persist.sh" snapshot
order=$(jq -r '.[] | if .cmd then (.cmd | capture("--resume\\\\? (?<s>[a-z0-9]+)").s) else (.cwd | sub(".*/"; "")) end' "$T/mux.json" | paste -sd' ')
check "three late sessions spawned" '[ "$(jq "[.[] | select(.cmd)] | length" "$T/mux.json")" = 3 ]'
check "tabs are in the old order" '[ "$order" = "c3 xpeng a1 life b2" ]'
check "placement is logged" 'grep -q "late a1@.*resumed in pane .* at tab 2 (old place 2)" "$S/events.log"'

# --- the Agent Hub channel flag on a bare resume
setup channel
entry ch1 "$H/projects/life" 0 "$OLD"
f=$(ls "$S/sessions/"ch1@*.json)
resume() {
  HOME=$H XDG_STATE_HOME=$T/state CLAUDE_PERSIST_BIN=/usr/bin/claude \
    CLAUDE_CHANNEL_ARGS_BIN=$HERE/../../bin/claude-channel-args \
    bash "$T/hooks/claude-persist.sh" resume-cmd "$f"
}
out=$(resume)
check "bare resume gets the channel flag before --resume" \
  'printf "%s\n" "$out" | grep -qF "/usr/bin/claude --channels plugin:agent-hub@agent-hub-plugins --resume ch1"'
out=$(AGENT_HUB_CHANNEL=0 resume)
check "AGENT_HUB_CHANNEL=0 leaves it out" \
  'printf "%s\n" "$out" | grep -qF "/usr/bin/claude --resume ch1" && ! printf "%s\n" "$out" | grep -q -- --channels'
out=$(HOME=$H XDG_STATE_HOME=$T/state CLAUDE_PERSIST_BIN=/usr/bin/claude \
  CLAUDE_CHANNEL_ARGS_BIN=/nonexistent bash "$T/hooks/claude-persist.sh" resume-cmd "$f")
check "no helper installed: resume as before" 'printf "%s\n" "$out" | grep -qF "/usr/bin/claude --resume ch1"'

# --- sessions that ran in the old herdr server: plan leaves them out
setup herdr-skip
tab_order "$OLD" 1 2
entry ft1 "$H/projects/life" 1 "$OLD"
entry hd1 "$H/projects/xpeng" 2 "$OLD"
f=$(ls "$S/sessions/"hd1@*.json)
jq '.herdr = {pane:"w1:p1", workspace:"w1"} | .pane = null' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
printf 'mux %s\nft1\nhd1\n' "$OLD" > "$S/live"
out=$(run_plan)
check "the mux session is resumed" 'printf "%s\n" "$out" | grep -q -- "--resume ft1"'
check "the herdr session is not resumed into the mux" '! printf "%s\n" "$out" | grep -q hd1'
check "the herdr entry stays on the list" '[ -f "$f" ]'

name=$( (source "$T/hooks/claude-persist.sh"; herdr_name "Manager: CTO review 2026") )
check "titles become valid terminal names" '[ "$name" = manager-cto-review-2026 ]'

# --- sessions that ran in a herdr-core (hc) terminal
setup hc-skip
tab_order "$OLD" 1
entry hc1 "$H/projects/life" null "$OLD"
f=$(ls "$S/sessions/"hc1@*.json)
jq '.hc = {terminal:"t3", name:"cto"}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
printf 'mux %s\nhc1\n' "$OLD" > "$S/live"
out=$(run_plan)
check "plan leaves an hc session out" '! printf "%s\n" "$out" | grep -q hc1'

setup hc-restore
mkdir -p "$T/bin"
cat > "$T/bin/hc" <<EOF
#!/bin/bash
echo "\$*" >> "$T/hc.log"
case "\$1 \$2" in
  "server status") echo '{"pid":1}' ;;
esac
EOF
chmod +x "$T/bin/hc"
entry hc2 "$H/projects/life" null "$OLD"
entry hc3 "$H/projects/xpeng" null "$OLD"
f=$(ls "$S/sessions/"hc2@*.json); jq '.hc = {terminal:"t3", name:"cto"}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
f=$(ls "$S/sessions/"hc3@*.json); jq '.hc = {terminal:"t4", name:null}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
printf 'mux %s\nhc2\n' "$OLD" > "$S/live"
HOME=$H XDG_STATE_HOME=$T/state CLAUDE_PERSIST_MUX_ID=$NEW CLAUDE_PERSIST_BIN=/usr/bin/claude \
  CLAUDE_TAB_RUN_BIN=/nonexistent CLAUDE_CHANNEL_ARGS_BIN=/nonexistent \
  CLAUDE_PERSIST_HC_BIN=$T/bin/hc bash "$T/hooks/claude-persist.sh" restore-hc
check "the live hc session comes back under its old name" \
  'grep -q "^run --bg --name cto --cwd $H/projects/life -- bash .*/hc-run/hc2.sh" "$T/hc.log"'
check "its script resumes it and drops the child-session marker" \
  'grep -q -- "--resume hc2" "$S/hc-run/hc2.sh" && grep -q CLAUDE_CODE_CHILD_SESSION "$S/hc-run/hc2.sh"'
check "a session not running at the last snapshot is dropped" '! grep -q hc3 "$T/hc.log"'

# hc kept the old terminal across the reboot as an idle shell under the old
# name: the session goes back into its old space and tab under that name.
setup hc-standin
mkdir -p "$T/bin"
sleep 60 & idle=$!; BG+=("$idle")
cat > "$T/bin/hc" <<EOF
#!/bin/bash
echo "\$*" >> "$T/hc.log"
case "\$1 \$2" in
  "server status") echo '{"pid":1}' ;;
  "get t9"|"get cto-hc4")
    if [ -f "$T/sent" ]; then
      echo '{"address":"t9","name":"cto","state":"live","labels":{"herdr.space":"spA"},"foreground":{"name":"bash","pid":2}}'
    else
      echo '{"address":"t9","name":"cto","state":"live","labels":{"herdr.space":"spA"},"foreground":{"name":"fish","pid":$idle}}'
    fi ;;
  "send t9") touch "$T/sent" "\${3##* }.started" ;;
esac
exit 0
EOF
chmod +x "$T/bin/hc"
entry hc4 "$H/projects/life" null "$OLD"
f=$(ls "$S/sessions/"hc4@*.json); jq '.hc = {terminal:"t9", name:"cto", space:"spA", tab:"tbB"}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
printf 'mux %s\nhc4\n' "$OLD" > "$S/live"
HOME=$H XDG_STATE_HOME=$T/state CLAUDE_PERSIST_MUX_ID=$NEW CLAUDE_PERSIST_BIN=/usr/bin/claude \
  CLAUDE_TAB_RUN_BIN=/nonexistent CLAUDE_CHANNEL_ARGS_BIN=/nonexistent \
  CLAUDE_PERSIST_HC_BIN=$T/bin/hc bash "$T/hooks/claude-persist.sh" restore-hc
kill $idle 2>/dev/null
check "the session resumes inside the idle stand-in shell" \
  'grep -q "^keys t9 ctrl+c" "$T/hc.log" && grep -q "^send t9 .*exec bash .*/hc-run/hc4.sh" "$T/hc.log"'
check "the stand-in keeps its terminal, so the window layout does not change" \
  '! grep -qE "^(run --bg|kill t9|rm t9)" "$T/hc.log" && grep -q "resume hc4 .* in stand-in t9 (cto)" "$S/restore.log"'

# A stand-in that is busy at the last check before typing (here: its fish pid
# changed) gets nothing typed into it: the session starts in a new terminal
# under the stand-in's name. Regression, office reboot 2026-11-26: with a name
# that is already 32 characters (herdr_name's limit) the placeholder got the
# same name, hc refused both runs, and six sessions were not restored.
setup hc-long-name
mkdir -p "$T/bin"
sleep 60 & idle=$!; BG+=("$idle")
long=swing-catalyst-sheepdog-voice-ag
cat > "$T/bin/hc" <<EOF
#!/bin/bash
echo "\$*" >> "$T/hc.log"
bump() { local c=\$(cat "$T/\$1" 2>/dev/null || echo 0); echo \$((c + 1)) > "$T/\$1"; echo \$((c + 1)); }
case "\$1 \$2" in
  "server status") echo '{"pid":1}' ;;
  "get t6f") [ -f "$T/gone" ] && exit 1
    if [ "\$(bump get)" -lt 2 ]; then p=$idle; else p=1; fi
    echo '{"address":"t6f","name":"$long","state":"live","labels":{"herdr.space":"spA"},"foreground":{"name":"fish","pid":'"\$p"'}}' ;;
  "rm t6f") touch "$T/gone" ;;
  "run --bg") [ -e "$T/taken-\$4" ] && exit 1; touch "$T/taken-\$4" ;;
  "kill "*) rm -f "$T/taken-\$2" ;;
esac
exit 0
EOF
chmod +x "$T/bin/hc"
touch "$T/taken-$long"   # the busy stand-in still holds the name
entry hc6 "$H/projects/life" null "$OLD"
f=$(ls "$S/sessions/"hc6@*.json); jq '.hc = {terminal:"t6f", name:null, space:"spA", tab:"tbB"}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
printf 'mux %s\nhc6\n' "$OLD" > "$S/live"
HOME=$H XDG_STATE_HOME=$T/state CLAUDE_PERSIST_MUX_ID=$NEW CLAUDE_PERSIST_BIN=/usr/bin/claude \
  CLAUDE_TAB_RUN_BIN=/nonexistent CLAUDE_CHANNEL_ARGS_BIN=/nonexistent \
  CLAUDE_PERSIST_HC_BIN=$T/bin/hc bash "$T/hooks/claude-persist.sh" restore-hc
kill $idle 2>/dev/null
check "a busy stand-in gets nothing typed into it and keeps running" \
  '! grep -qE "^(send|kill|rm) t6f" "$T/hc.log" && grep -q "stand-in t6f ($long) was not idle" "$S/restore.log"'
check "a 32-character name held by the stand-in still gets a new terminal in its space and tab" \
  'grep -q "^run --bg --name ${long:0:27}-hc6 --label herdr.space=spA --label herdr.tab=tbB --cwd .* -- bash .*/hc-run/hc6.sh" "$T/hc.log" && grep -q "resume hc6 .* in hc terminal ${long:0:27}-hc6 " "$S/restore.log"'

# Regression, home reboot 2026-11-22: the last snapshot ran while hc went down
# and saved the terminal with no name, space or tab; restore-hc then ran before
# hc gave the kept terminals their shells. The session must still go back
# into its old terminal, found by its saved address.
setup hc-reboot-race
mkdir -p "$T/bin"
sleep 60 & idle=$!; BG+=("$idle")
cat > "$T/bin/hc" <<EOF
#!/bin/bash
echo "\$*" >> "$T/hc.log"
bump() { local c=\$(cat "$T/\$1" 2>/dev/null || echo 0); echo \$((c + 1)) > "$T/\$1"; echo \$((c + 1)); }
case "\$1 \$2" in
  "server status") echo "{\"pid\":1,\"uptime_ms\":\$(( \$(bump status) * 2000 ))}" ;;
  "get t1v")
    if [ "\$(bump get)" -lt 2 ]; then
      echo '{"address":"t1v","name":"voice-transcriber","state":"finished","keep":true,"labels":{"herdr.space":"spY"},"foreground":null}'
    elif [ -f "$T/sent" ]; then
      echo '{"address":"t1v","name":"voice-transcriber","state":"live","keep":true,"labels":{"herdr.space":"spY"},"foreground":{"name":"bash","pid":2}}'
    else
      echo '{"address":"t1v","name":"voice-transcriber","state":"live","keep":true,"labels":{"herdr.space":"spY"},"foreground":{"name":"fish","pid":$idle}}'
    fi ;;
  "get "*) echo '{"error":{"kind":"not_found"}}'; exit 3 ;;
  "send t1v") touch "$T/sent" "\${3##* }.started" ;;
esac
exit 0
EOF
cat > "$T/bin/herdr-app" <<'EOF'
#!/bin/bash
echo '{"spaces":[{"id":"spY","tabs":[{"id":"tbY","terminals":[{"terminal":"t1v"}]}]}]}'
EOF
chmod +x "$T/bin/hc" "$T/bin/herdr-app"
entry hc5 "$H/projects/life" null "$OLD"
f=$(ls "$S/sessions/"hc5@*.json); jq '.hc = {terminal:"t1v", name:null, space:null, tab:null}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
printf 'mux %s\nhc5\n' "$OLD" > "$S/live"
HOME=$H XDG_STATE_HOME=$T/state CLAUDE_PERSIST_MUX_ID=$NEW CLAUDE_PERSIST_BIN=/usr/bin/claude \
  CLAUDE_TAB_RUN_BIN=/nonexistent CLAUDE_CHANNEL_ARGS_BIN=/nonexistent \
  CLAUDE_PERSIST_HERDR_APP_BIN=$T/bin/herdr-app \
  CLAUDE_PERSIST_HC_BIN=$T/bin/hc bash "$T/hooks/claude-persist.sh" restore-hc
kill $idle 2>/dev/null
first_get=$(grep -n '^get ' "$T/hc.log" | head -1 | cut -d: -f1)
last_status=$(grep -n '^server status' "$T/hc.log" | tail -1 | cut -d: -f1)
check "it waits for the core to settle before it looks for stand-ins" \
  '[ -n "$first_get" ] && [ "$last_status" -lt "$first_get" ] && [ "$(cat "$T/status")" -ge 3 ]'
check "it finds the stand-in by its saved address and resumes in it" \
  'grep -q "^send t1v .*exec bash .*/hc-run/hc5.sh" "$T/hc.log" && grep -q "resume hc5 .* in stand-in t1v (voice-transcriber)" "$S/restore.log"'
check "it leaves the stand-in terminal in place" '! grep -qE "^(run --bg|rm t1v)" "$T/hc.log"'

# hc_info: a failed lookup (hc prints its error as JSON on stdout) returns 1,
# so the snapshot keeps the saved terminal instead of overwriting it with nulls.
setup hc-info-fail
mkdir -p "$T/bin"
printf '#!/bin/bash\necho %s; exit 5\n' "'{\"error\":{\"kind\":\"unavailable\"}}'" > "$T/bin/hc-down"
printf '#!/bin/bash\necho %s\n' "'{\"address\":\"t7\",\"name\":\"cto\",\"labels\":{\"herdr.space\":\"spA\",\"herdr.tab\":\"tbA\"}}'" > "$T/bin/hc-up"
chmod +x "$T/bin/hc-down" "$T/bin/hc-up"
env HC_TERMINAL_ID=t7 sleep 30 & tp=$!; BG+=("$tp")
sleep 0.2
down=$( (CLAUDE_PERSIST_HC_BIN=$T/bin/hc-down; source "$T/hooks/claude-persist.sh"; hc_info "$tp"; echo "rc=$?") )
up=$( (CLAUDE_PERSIST_HC_BIN=$T/bin/hc-up; source "$T/hooks/claude-persist.sh"; hc_info "$tp"; echo "rc=$?") )
kill $tp 2>/dev/null
check "hc_info fails when hc does not answer" 'printf "%s\n" "$down" | grep -q "rc=1"'
check "hc_info reads name, space and tab when hc answers" \
  'printf "%s\n" "$up" | grep -q "\"name\":\"cto\",\"space\":\"spA\",\"tab\":\"tbA\"" && printf "%s\n" "$up" | grep -q "rc=0"'
check "the snapshot skips a failed lookup" 'grep -qF "hinfo=\$(hc_info \"\$epid\") || continue" "$T/hooks/claude-persist.sh"'

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
