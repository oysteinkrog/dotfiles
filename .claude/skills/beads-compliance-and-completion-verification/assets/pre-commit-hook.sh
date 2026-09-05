#!/usr/bin/env bash
# pre-commit-hook.sh — Local pre-commit hook for beads compliance.
#
# Install:
#   ln -s "$(realpath assets/pre-commit-hook.sh)" .git/hooks/pre-commit
# Or copy and edit.
#
# What it does:
#   1. If the staged diff includes `.beads/*.jsonl`, detect any bead whose
#      status flipped to `closed` in this diff.
#   2. For each newly-closed bead, run scripts/spec-quality-gate.sh + a quick
#      single-bead-audit (Phase 2-3-5 only — no test re-runs in a hook).
#   3. Block the commit if any closed bead would be flagged false-closed by
#      the quick audit. Pass --no-verify to override (stays non-destructive).
#
# Why local + remote: remote tripwire catches drift; local hook catches the
# specific commit that introduces it, in the exact session that wrote it.
#
# Bypass: BEADS_HOOK_SKIP=1 git commit … (logs the bypass to .beads_hook.log
# so it's discoverable later — bypasses are not "free").
set -euo pipefail

if [ "${BEADS_HOOK_SKIP:-0}" = "1" ]; then
  printf '%s SKIPPED beads hook\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .beads_hook.log
  exit 0
fi

# Locate the skill (vendored under .claude/skills/ in the project, or installed
# globally under ~/.claude/skills/).
SKILL=""
for cand in \
  ".claude/skills/beads-compliance-and-completion-verification" \
  "$HOME/.claude/skills/beads-compliance-and-completion-verification" \
  "$HOME/.codex/skills/beads-compliance-and-completion-verification"; do
  if [ -d "$cand" ]; then SKILL="$cand"; break; fi
done
if [ -z "$SKILL" ]; then
  echo "[beads-hook] skill not found locally; skipping. Install via 'jsm install beads-compliance-and-completion-verification' or vendor it under .claude/skills/." >&2
  exit 0
fi

# Find beads whose status TRANSITIONED to closed in this commit's staged
# JSONL diff. The naive `grep '^\+.*status.*closed'` approach falsely
# triggers on already-closed beads that are being edited for other reasons
# (the new line still contains `status: "closed"` even though the bead
# wasn't just closed) — that produces wasted audit runs and noisy hook
# blocks. Compare old (`-` lines) vs new (`+` lines) per bead-id and emit
# only true open→closed (or absent→closed) transitions.
#
# Limitation: br can serialize custom statuses as `{"Custom":"name"}`
# objects rather than the string `"closed"` we match here. Standard closed
# beads use the string form, so the common case is covered; custom-status
# transitions skip the hook (acceptable — a downstream tripwire still
# catches them).
NEWLY_CLOSED="$(git diff --cached --unified=0 -- '.beads/*.jsonl' 2>/dev/null \
  | python3 -c '
import re, sys
ID_RE = re.compile(r"\"id\"\s*:\s*\"([a-z][a-z0-9_.-]*)\"")
ST_RE = re.compile(r"\"status\"\s*:\s*\"([a-z_]+)\"")
old, new = {}, {}
for line in sys.stdin:
    if line.startswith(("+++", "---")) or not (line.startswith("+") or line.startswith("-")):
        continue
    m_id = ID_RE.search(line); m_st = ST_RE.search(line)
    if not m_id or not m_st: continue
    bid, st = m_id.group(1), m_st.group(1)
    (new if line.startswith("+") else old)[bid] = st
for bid, st in new.items():
    if st == "closed" and old.get(bid) != "closed":
        print(bid)
' | sort -u || true)"

if [ -z "$NEWLY_CLOSED" ]; then
  exit 0
fi

PROJECT="$(git rev-parse --show-toplevel)"
THRESHOLD="${BEADS_HOOK_THRESHOLD:-700}"

echo "[beads-hook] Verifying $(echo "$NEWLY_CLOSED" | wc -l | tr -d ' ') newly-closed bead(s) at threshold=$THRESHOLD..."
FAIL=0

while IFS= read -r BID; do
  [ -z "$BID" ] && continue
  echo "[beads-hook] -> $BID"
  set +e
  "$SKILL/scripts/single-bead-audit.sh" "$PROJECT" "$BID" --threshold "$THRESHOLD" --policy report-only
  RC=$?
  set -e
  if [ $RC -ne 0 ]; then
    FAIL=1
  fi
done <<< "$NEWLY_CLOSED"

if [ $FAIL -ne 0 ]; then
  echo ""
  echo "[beads-hook] BLOCKED: one or more newly-closed beads failed quick audit (score < $THRESHOLD)." >&2
  echo "             Re-run: $SKILL/scripts/single-bead-audit.sh \"$PROJECT\" <bead-id>" >&2
  echo "             Bypass (logged to .beads_hook.log): BEADS_HOOK_SKIP=1 git commit ..." >&2
  exit 1
fi

echo "[beads-hook] All newly-closed beads passed quick audit."
exit 0
