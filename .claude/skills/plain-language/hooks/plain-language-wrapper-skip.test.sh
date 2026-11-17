#!/usr/bin/env bash
# Tests that the user-level wrappers skip when the project has its own copy of the hook.
#   bash plain-language-wrapper-skip.test.sh
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
W="$HERE/../../../hooks/plain-language-guard.sh"
H="$HERE/../../../hooks/plain-language-health.sh"
T=$(mktemp -d -p /var/tmp/claude); trap 'rm -rf "$T"' EXIT
fail=0
BAD='In todays fast-paced world, our journey to remote capture is not just a feature, it is a testament to the evolving landscape of mobile motion analysis. It is worth noting that experts agree this marks a pivotal moment for the whole team and for the product overall.'
payload() { python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":"Write","tool_input":{"file_path":"/var/tmp/claude/x.md","content":sys.argv[2]}}))' "$1" "$BAD"; }
check() { # name expected_exit dir
  local rc; payload "$3" | PLAINLANG_CACHE_OFF=1 bash "$W" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$2" ]; then echo "  ok    $1"; else echo "  FAIL  $1 (exit $rc, want $2)"; fail=1; fi
}
mk() { mkdir -p "$1/.claude"; git -C "$1" init -q; }
own="$T/own"; mk "$own"
echo '{"hooks":{"PreToolUse":[{"matcher":"","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/plain-language-guard.sh"}]}]}}' > "$own/.claude/settings.json"
mkdir -p "$own/sub/dir"
none="$T/none"; mk "$none"; echo '{"hooks":{}}' > "$none/.claude/settings.json"
user="$T/user"; mk "$user"
echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/plain-language-guard.sh"}]}]}}' > "$user/.claude/settings.json"
broken="$T/broken"; mk "$broken"; echo '{not json' > "$broken/.claude/settings.json"
plain="$T/plain"; mkdir -p "$plain"
check "repo with own copy: skips"            0 "$own"
check "own copy, cwd in subdir: skips"       0 "$own/sub/dir"
check "repo without hook: runs (blocks)"     2 "$none"
check "repo with only user-level path: runs" 2 "$user"
check "non-git dir: runs"                    2 "$plain"
check "broken settings.json: runs"           2 "$broken"
check "missing cwd dir: runs"                2 "$T/missing"
# health wrapper skips too
out=$(printf '%s' "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$own\"}" | bash "$H" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then echo "  ok    health wrapper skips silently"; else echo "  FAIL  health wrapper ($rc: $out)"; fail=1; fi
exit $fail
