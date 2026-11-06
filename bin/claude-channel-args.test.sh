#!/usr/bin/env bash
# Tests for the Agent Hub channel flag: the claude-channel-args helper, the fish
# `claude` function and aiolos-rc. A stub script stands in for the Claude binary
# and prints the arguments it got, so no real session starts.
# Run: bash ~/.dotfiles/bin/claude-channel-args.test.sh
set -uo pipefail
HERE=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
DOT=$(dirname "$HERE")
HELPER=$HERE/claude-channel-args
mkdir -p /var/tmp/claude; T=$(mktemp -d /var/tmp/claude/channel-test.XXXXXX)
LISTENER=""
trap '[ -n "$LISTENER" ] && kill "$LISTENER" 2>/dev/null; rm -rf -- "$T"' EXIT
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass + 1)); echo "ok   $1"; else fail=$((fail + 1)); echo "FAIL $1"; echo "     got: $out"; fi; }

FLAG="--channels plugin:agent-hub@agent-hub-plugins"
args() { "$HELPER" "$@" | paste -sd' '; }

# --- the helper
out=$(args); check "helper: plain session gets the flag" '[ "$out" = "$FLAG" ]'
out=$(args --resume abc); check "helper: resume gets the flag" '[ "$out" = "$FLAG" ]'
out=$(args -p hi); check "helper: -p gets nothing" '[ -z "$out" ]'
out=$(args --model x --print hi); check "helper: --print gets nothing" '[ -z "$out" ]'
out=$(args --channels server:x); check "helper: --channels given gets nothing" '[ -z "$out" ]'
out=$(args --channels=server:x); check "helper: --channels= given gets nothing" '[ -z "$out" ]'
out=$(args -- -p); check "helper: -p after -- is a prompt, flag kept" '[ "$out" = "$FLAG" ]'
for sub in rc remote-control mcp plugin doctor; do
  out=$(args "$sub"); check "helper: subcommand $sub gets nothing" '[ -z "$out" ]'
done
out=$(AGENT_HUB_CHANNEL=0 args); check "helper: AGENT_HUB_CHANNEL=0 turns it off" '[ -z "$out" ]'
out=$(AGENT_HUB_CHANNEL=off args); check "helper: AGENT_HUB_CHANNEL=off turns it off" '[ -z "$out" ]'
out=$(AGENT_HUB_CHANNEL_SPEC=server:y args); check "helper: AGENT_HUB_CHANNEL_SPEC replaces the name" '[ "$out" = "--channels server:y" ]'

# --- the stub binary: a script, so the fish function runs it directly
STUB=$T/claude-stub
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s|" "$a"; done; echo\n' > "$STUB"
chmod +x "$STUB"

# --- the fish function (HOME stays real, so it finds ~/bin/claude-channel-args)
fishrun() {
  CLAUDE_VERSION=$STUB fish --no-config -c "source $DOT/.config/fish/functions/claude.fish; claude $*"
}
out=$(fishrun)
check "fish: plain session" '[ "$out" = "--channels|plugin:agent-hub@agent-hub-plugins|--dangerously-skip-permissions|" ]'
out=$(fishrun "'fix the bug'")
check "fish: a prompt comes after skip-permissions, not after --channels" \
  '[ "$out" = "--channels|plugin:agent-hub@agent-hub-plugins|--dangerously-skip-permissions|fix the bug|" ]'
out=$(fishrun -p hi)
check "fish: -p gets no channel" '[ "$out" = "--dangerously-skip-permissions|-p|hi|" ]'
out=$(fishrun --channels server:x)
check "fish: --channels is not added twice" '[ "$out" = "--dangerously-skip-permissions|--channels|server:x|" ]'
out=$(fishrun rc)
check "fish: rc gets no channel" '[ "$out" = "rc|--permission-mode|bypassPermissions|" ]'
out=$(fishrun mcp list)
check "fish: mcp list is untouched" '[ "$out" = "mcp|list|" ]'
out=$(AGENT_HUB_CHANNEL=0 fishrun)
check "fish: AGENT_HUB_CHANNEL=0 turns it off" '[ "$out" = "--dangerously-skip-permissions|" ]'

# --- aiolos-rc. A listener of our own stands in for the shared shim, so it
# starts no shim. A private XDG_RUNTIME_DIR has no systemd socket, so it makes
# no scope, and its --settings file goes there.
mkdir -p "$T/secrets/certs" "$T/run"
touch "$T/secrets/certs/ca.pem" "$T/secrets/certs/leaf-chain.pem" "$T/secrets/certs/leaf.key"
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -c "import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('127.0.0.1', $PORT)); s.listen(8); time.sleep(120)" &
LISTENER=$!
for _ in $(seq 1 50); do (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && break; sleep 0.1; done
rcrun() {
  env -u AIOLOS_RC_SCOPED CLAUDE_BIN=$STUB AIOLOS_RC_SECRETS=$T/secrets AIOLOS_RC_SHARED_PORT=$PORT \
    XDG_RUNTIME_DIR=$T/run ANTHROPIC_BASE_URL=http://aiolos.invalid \
    "$DOT/.config/aiolos-rc/aiolos-rc" "$@" 2>/dev/null | tail -1
}
S="--settings|$T/run/aiolos-rc/override.settings.json"
out=$(rcrun --no-pin)
check "aiolos-rc: session gets the flag before --settings" \
  '[ "$out" = "--channels|plugin:agent-hub@agent-hub-plugins|$S|--dangerously-skip-permissions|" ]'
out=$(rcrun --no-pin -r abc)
check "aiolos-rc: resume gets the flag" \
  '[ "$out" = "--channels|plugin:agent-hub@agent-hub-plugins|$S|--dangerously-skip-permissions|-r|abc|" ]'
out=$(rcrun --no-pin -p hi)
check "aiolos-rc: -p gets no channel" '[ "$out" = "$S|--dangerously-skip-permissions|-p|hi|" ]'
out=$(AGENT_HUB_CHANNEL=0 rcrun --no-pin)
check "aiolos-rc: AGENT_HUB_CHANNEL=0 turns it off" '[ "$out" = "$S|--dangerously-skip-permissions|" ]'
out=$(rcrun --no-pin rc)
check "aiolos-rc: rc gets no channel" '[ "$out" = "rc|--permission-mode|bypassPermissions|" ]'

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
