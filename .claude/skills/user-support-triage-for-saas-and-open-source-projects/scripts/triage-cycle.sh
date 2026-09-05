#!/usr/bin/env bash
# triage-cycle.sh — start one support-triage cycle without sending anything.
#
# Usage:
#   triage-cycle.sh /path/to/project
#
# Creates a session workspace under the target project's support-triage folder,
# captures open-item ground truth, and writes an owner-review draft bundle
# skeleton. Customer-facing sends remain manual and owner-approved.
#
# Optional fire drill:
#   SUPPORT_TRIAGE_FIXTURE=/path/to/open-items.json triage-cycle.sh /path/to/project

set -euo pipefail

PROJECT="${1:-}"
if [[ -z "$PROJECT" || ! -d "$PROJECT" ]]; then
  echo "usage: triage-cycle.sh <project-path>" >&2
  exit 2
fi
PROJECT="$(cd "$PROJECT" && pwd)"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPPORT_DIR="$PROJECT/.claude/support-triage"
DET="$SUPPORT_DIR/_detection.json"

if [[ ! -f "$DET" ]]; then
  echo "missing $DET — run onboarding first" >&2
  exit 2
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SESSION="$SUPPORT_DIR/.workspace/triage-session-$STAMP"
if [[ -e "$SESSION" ]]; then
  SESSION="$SUPPORT_DIR/.workspace/triage-session-$STAMP-$$"
fi
mkdir -p "$SESSION"

if [[ -n "${SUPPORT_TRIAGE_FIXTURE:-}" ]]; then
  if [[ ! -f "$SUPPORT_TRIAGE_FIXTURE" ]]; then
    echo "SUPPORT_TRIAGE_FIXTURE not found: $SUPPORT_TRIAGE_FIXTURE" >&2
    exit 2
  fi
  python3 "$SKILL_DIR/scripts/validate-adapter-output.py" "$SUPPORT_TRIAGE_FIXTURE" >&2
  cp "$SUPPORT_TRIAGE_FIXTURE" "$SESSION/open-items.json"
  OPEN_SOURCE="$SUPPORT_TRIAGE_FIXTURE (fire-drill fixture)"
else
  "$SKILL_DIR/scripts/list-open-items.sh" "$PROJECT" > "$SESSION/open-items.json"
  OPEN_SOURCE="$SESSION/open-items.json"
fi

cat > "$SESSION/draft-bundle.md" <<EOF
# Triage draft bundle — $STAMP

Owner approval is required before any customer-facing send.

## Ground Truth

- Source: \`$OPEN_SOURCE\`
- Session copy: \`$SESSION/open-items.json\`
- Surfaces: \`$(jq -r '.surfaces | join(", ")' "$DET" 2>/dev/null || echo unknown)\`
- Mode: \`$([[ -n "${SUPPORT_TRIAGE_FIXTURE:-}" ]] && echo "fire-drill/no-send" || echo "live-read/no-send")\`

## Items

For each open item:

1. Orient: id, user, tier, channel, age, SLA.
2. Reproduce or verify independently.
3. Correlate against siblings and recent deploys.
4. Draft with specific evidence.
5. Run voice/de-slop pass.
6. Hold for owner confirmation.
7. Name the pipeline/runbook used and any TBD-OWNER gaps.
8. Select an accretive value loop for meaningful evidence, or write
   not-accretive-this-session.

## Approved Sends

Paste only owner-approved replies here before executing them.

## Follow-Up Beads

List confirmed bugs or policy gaps that need engineering/product follow-up.

## Outcome Record

Before ending, write a Phase 6 outcome record under:

\`$SUPPORT_DIR/outcomes/$STAMP-<slug>.md\`
EOF
cat <<EOF
Triage session workspace:
  $SESSION

Ground truth:
  $SESSION/open-items.json

Draft bundle skeleton:
  $SESSION/draft-bundle.md

Next:
  1. Read open-items.json and apply ORIENT/REPRO/CORRELATE.
  2. Fill draft-bundle.md.
  3. Show the whole bundle to the owner.
  4. Send only owner-approved customer-facing replies.
EOF
