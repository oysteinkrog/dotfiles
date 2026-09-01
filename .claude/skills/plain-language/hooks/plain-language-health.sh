#!/usr/bin/env bash
# SessionStart hook. Proves the plain-language gate can actually run, once per
# session, and says so loudly when it cannot.
#
# This exists because of the one failure mode that matters. The gate fails open
# on any error, which is correct — a broken guard must not stop your work. But a
# guard that fails open silently is indistinguishable from a guard that is
# working, so it can be dead for weeks while everyone assumes their prose is
# being checked. This hook is the difference between the two.
#
# It never blocks a session. Worst case it prints a line saying the gate is off
# and why.
set -uo pipefail

if [ "${PLAINLANG_OFF:-}" = "1" ]; then
  exit 0
fi

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
guard="$here/plain-language-guard.sh"

[ -f "$guard" ] || exit 0

# A payload that must be refused, and one that must pass. Checking both catches
# a gate that is stuck open and a gate that is stuck shut.
bad=$(cat <<'EOF'
{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/plainlang-health.md","content":"In todays fast-paced world, our journey to remote capture is not just a feature, it is a testament to the evolving landscape of mobile motion analysis. It is worth noting that experts agree this marks a pivotal moment for the whole team and for the product overall."}}
EOF
)
good=$(cat <<'EOF'
{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/plainlang-health.md","content":"The phone now owns its settings. The desktop shows them and sends changes back over the existing protocol. Version 26.2 adds white balance control. The 26.1 protocol ignores unknown field types, so no backport is needed. Tested on four handsets over two days."}}
EOF
)

err=$(printf '%s' "$bad" | bash "$guard" 2>&1 >/dev/null); bad_rc=$?
printf '%s' "$good" | bash "$guard" >/dev/null 2>&1; good_rc=$?

# Third check: is it fully loaded, or running degraded? A missing word-norm table
# leaves the pattern rules working, so the two checks above would both pass while
# the reading-cost half of the gate is dead.
degraded=$(PLAINLANG_SELFCHECK=1 bash "$guard" < /dev/null 2>&1 >/dev/null) || true

if [ "$bad_rc" = 2 ] && [ "$good_rc" = 0 ] && [ -z "$degraded" ]; then
  exit 0
fi

if [ "$bad_rc" = 2 ] && [ "$good_rc" = 0 ] && [ -n "$degraded" ]; then
  cat <<DEGRADED
plain-language gate is running DEGRADED in this session: $degraded

The pattern rules still fire, so writing is partly checked, but the reading-cost
half is not measuring what it should. Check the data files under
$(cd -- "$here/.." && pwd)/data.
DEGRADED
  exit 0
fi

# Something is wrong. Say what, in terms a developer can act on.
reason="unknown"
if [ "$bad_rc" != 2 ] && [ "$good_rc" = 0 ]; then
  reason="it let inflated text through, so it is not actually checking anything"
elif [ "$good_rc" != 0 ]; then
  reason="it refused text that should pass, so it would block ordinary work"
fi

detail=""
[ -n "$err" ] && detail=" Reported: $(printf '%s' "$err" | head -2 | tr '\n' ' ')"

cat <<MSG
plain-language gate is NOT working in this session: $reason.$detail

Nothing is being checked, so prose reaches people unchecked until this is fixed.
Diagnose with:
  bash $here/plain-language-guard.sh < /dev/null; echo \$?
  python3 -c 'import sys; print(sys.version)'
The gate needs python3 3.12 or newer and the skill's data files under
$(cd -- "$here/.." && pwd)/data. It needs no virtualenv and no install step.
Set PLAINLANG_OFF=1 to silence this deliberately.
MSG
exit 0
