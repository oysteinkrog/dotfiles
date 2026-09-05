#!/usr/bin/env bash
# single-bead-audit.sh — Run an audit pass scoped to a single bead.
#
# Use cases:
#   - Pre-merge gate: a PR closes bead X; verify before merging.
#   - Single-bead deep-dive: investigate one suspicious bead in detail.
#   - Closer-defense round-trip: re-score after an evidence response.
#
# What it does:
#   - Phase 1 inventory still runs FULL (cheap; gives us the universe so
#     synthesis can see neighbors + dep graph).
#   - Phases 2-6 run ONLY on the target bead.
#   - Phase 7 synthesis runs FULL (so we catch cases where the target broke
#     a sibling — that's the whole point of a pre-merge gate).
#   - Phase 8 scores ONLY the target.
#   - Phase 9 remediation operates only on the target IF it's false-closed.
#   - Phase 10 convergence is N/A for single-bead.
#
# Usage:
#   single-bead-audit.sh <project-path> <bead-id> [--threshold 700]
#                                                 [--policy report-only|completion-debt|reopen]
#                                                 [--audit-dir <path>]
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path required}"
BEAD_ID="${2:?bead-id required}"
shift 2

# Defaults: hardcoded < audit-policy.yaml < CLI flags. POLICY default differs
# from run-pass.sh because single-bead is usually invoked in a pre-merge gate
# context — `report-only` is the conservative choice. The YAML still wins if
# it explicitly sets remediation_policy.
THRESHOLD=700
POLICY="report-only"
AUDIT_DIR=""

require_value() {
  if [ "$2" -lt 2 ]; then echo "ERROR: $1 requires a value" >&2; exit 3; fi
}

resolve_audit_dir_arg() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)
      local parent_abs
      if parent_abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd)"; then
        :
      else
        parent_abs=""
      fi
      if [ -n "$parent_abs" ]; then
        printf '%s/%s\n' "$parent_abs" "$(basename "$1")"
      else
        printf '%s\n' "$1"
      fi
      ;;
  esac
}

# Load policy from the requested audit dir if the caller supplied one. The full
# parser below still runs afterward, so explicit CLI threshold/policy flags win
# over YAML as documented.
ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    --audit-dir)
      if [ $((i + 1)) -ge ${#ARGS[@]} ]; then
        echo "ERROR: --audit-dir requires a value" >&2
        exit 3
      fi
      AUDIT_DIR="$(resolve_audit_dir_arg "${ARGS[$((i + 1))]}")"
      break
      ;;
  esac
done

. "$(dirname "$0")/_load-policy.sh"
load_policy "$PROJECT" "$AUDIT_DIR"
[ -n "${POLICY_THRESHOLD:-}" ] && THRESHOLD="$POLICY_THRESHOLD"
[ -n "${POLICY_REMEDIATION_POLICY:-}" ] && POLICY="$POLICY_REMEDIATION_POLICY"

while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) require_value "$1" "$#"; THRESHOLD="$2"; shift 2 ;;
    --policy)    require_value "$1" "$#"; POLICY="$2"; shift 2 ;;
    --audit-dir) require_value "$1" "$#"; AUDIT_DIR="$(resolve_audit_dir_arg "$2")"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 3 ;;
  esac
done

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$SKILL_DIR/scripts"

# Default audit dir = subdirectory of project at beads_compliance_audit/.
if [ -z "$AUDIT_DIR" ]; then
  AUDIT_DIR="$(cd "$PROJECT" && pwd)/beads_compliance_audit"
fi

# Bootstrap or attach. bootstrap-audit.sh is idempotent on the audit-dir level
# (creates if missing) but always opens a new pass dir for this run.
PASS_DIR="$(AUDIT_DIR_OVERRIDE="$AUDIT_DIR" "$SCRIPTS/bootstrap-audit.sh" "$PROJECT" "$THRESHOLD" "single-bead" "$POLICY")"
AUDIT_DIR="$(cd "$PASS_DIR/../.." && pwd)"
echo "Pass dir: $PASS_DIR  (single-bead mode, target=$BEAD_ID)" >&2

# Phase 1 — full inventory (cheap; needed for graph context).
"$SCRIPTS/inventory-beads.sh" "$PROJECT" "$PASS_DIR" >/dev/null

# Confirm the target bead exists in the inventory. If not, fail loudly — the
# user probably typo'd the ID. We compare against inventory.jsonl rather than
# `br show` so we don't require live DB access.
#
# inventory-beads.sh writes inventory.jsonl as true JSONL (`jq -c '.[]'` →
# one compact JSON object per line). Use `jq -e` for an exact-string match on
# `.id` rather than a regex so IDs containing meta-chars (`.`, `[`, `+`, …)
# — e.g. domain-prefixed `auth.bd-42` or scoped `[infra]bd-7` — are matched
# literally and don't accidentally hit a wrong bead via regex semantics.
if ! jq -e --arg bid "$BEAD_ID" 'select(.id == $bid)' "$PASS_DIR/inventory.jsonl" >/dev/null 2>&1; then
  echo "ERROR: bead '$BEAD_ID' not found in inventory." >&2
  # Print best-guess FIRST (so `head -10` truncation can never hide it),
  # then up to 9 candidates from the inventory.
  # Add `|| true` so a malformed inventory.jsonl (jq exit 5) doesn't crash the
  # script via set -e — we want to print our helpful "bead not found" error
  # even if the inventory itself is unparseable.
  CANDIDATES="$(jq -r '.id // empty' "$PASS_DIR/inventory.jsonl" 2>/dev/null || true)"
  if [ -n "$CANDIDATES" ]; then
    BEST="$(printf '%s\n' "$CANDIDATES" | awk -v t="$BEAD_ID" '
      BEGIN { best = 99999 }
      {
        n = length($0); m = length(t); d = (n > m) ? n - m : m - n;
        if (d < best) { best = d; b = $0 }
      }
      END { if (b != "") print b }')"
    [ -n "$BEST" ] && echo "       Best guess: $BEST" >&2
    echo "       Candidates (first 9):" >&2
    printf '%s\n' "$CANDIDATES" | head -9 | sed 's/^/         /' >&2
  fi
  exit 4
fi

TARGET_DIR="$PASS_DIR/beads/$BEAD_ID"
[ -d "$TARGET_DIR" ] || { echo "ERROR: $TARGET_DIR missing — Phase 1 didn't write it" >&2; exit 5; }

# Phase 2 — spec extract (target only).
echo "Phase 2: extracting spec for $BEAD_ID..." >&2
python3 "$SCRIPTS/extract-spec.py" "$TARGET_DIR/show.json" > "$TARGET_DIR/spec.json"

# Phase 3 — gather evidence (target only).
echo "Phase 3: gathering evidence..." >&2
"$SCRIPTS/gather-evidence.sh" "$PROJECT" "$TARGET_DIR" >/dev/null 2>&1 || true

# Phase 4 stub — single-bead mode emits the stub compliance.json so the scorer
# has a deterministic input. For real Phase 4, the orchestrator should run the
# compliance-verifier subagent (subagents/compliance-verifier.md) here.
[ -f "$TARGET_DIR/compliance.json" ] || jq -n --arg id "$BEAD_ID" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{bead_id: $id, executed_at: $now, executor: "single-bead-stub", checks: []}' > "$TARGET_DIR/compliance.json"
[ -f "$TARGET_DIR/test_depth.json" ] || jq -n --arg id "$BEAD_ID" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{bead_id: $id, audited_at: $now, auditor: "single-bead-stub", checks: []}' > "$TARGET_DIR/test_depth.json"

# Phase 5 — theater + anomaly scan (target only).
echo "Phase 5: theater + anomaly scan..." >&2
"$SCRIPTS/theater-scan.sh" "$PROJECT" "$TARGET_DIR" >/dev/null 2>&1 || true
"$SCRIPTS/anomaly-scan.sh" "$PROJECT" "$TARGET_DIR" >/dev/null 2>&1 || true

# Phase 7 — full synthesis. We still want to see the target bead's effect on
# its siblings (e.g., did it orphan an AC by breaking a contract). We do NOT
# want to skip this — that's the whole reason synthesis exists.
echo "Phase 7: cross-bead synthesis (full universe)..." >&2
python3 "$SCRIPTS/synthesize.py" "$PASS_DIR" >/dev/null 2>&1 || true

# Phase 8 — score the target bead only.
echo "Phase 8: scoring $BEAD_ID..." >&2
PRIOR_PASS_DIR=""
PRIOR_PASS_ARG=()
PRIOR_CANDIDATE="$( { ls -1d "$AUDIT_DIR/passes"/*/ 2>/dev/null | sed 's|/$||' | grep -v "/$(basename "$PASS_DIR")$" | sort | tail -1; } || true)"
if [ -n "$PRIOR_CANDIDATE" ]; then
  PRIOR_PASS_DIR="$PRIOR_CANDIDATE"
  PRIOR_PASS_ARG=( --prior-pass-dir "$PRIOR_PASS_DIR" )
fi
python3 "$SCRIPTS/score-bead.py" "$TARGET_DIR" \
  --threshold "$THRESHOLD" \
  --rubric "$AUDIT_DIR/rubric.md" \
  --synthesis "$PASS_DIR/synthesis.md" \
  "${PRIOR_PASS_ARG[@]}" >/dev/null

# Build a one-bead REPORT.md so the user has a single artifact to read.
REPORT="$PASS_DIR/REPORT.md"
# Portable score extraction: see remediate.sh for the rationale (grep -P is
# GNU-only and absent from BSD grep / macOS by default). sed -nE matches the
# canonical `**Score: N / 1000**` line on both GNU and BSD sed.
SCORE="$(sed -nE 's/.*Score:[[:space:]]+([0-9]+).*/\1/p' "$TARGET_DIR/scorecard.md" 2>/dev/null | head -1)"
[ -n "$SCORE" ] || SCORE=0
STATUS="$(jq -r '.status // "unknown"' "$TARGET_DIR/show.json")"
TITLE="$(jq -r '.title // "untitled"' "$TARGET_DIR/show.json")"
{
  echo "# Single-Bead Audit Report — \`$BEAD_ID\`"
  echo ""
  echo "- **Title:** $TITLE"
  echo "- **Status (claimed):** $STATUS"
  echo "- **Score:** $SCORE / 1000  (threshold: $THRESHOLD)"
  echo "- **Audit pass:** \`$(basename "$PASS_DIR")\`"
  echo "- **Mode:** single-bead"
  echo ""
  echo "## Verdict"
  echo ""
  if [ "$STATUS" = "closed" ] && [ "$SCORE" -lt "$THRESHOLD" ]; then
    echo "🚨 **FALSE-CLOSED** — closed status with score \`$SCORE\` below threshold \`$THRESHOLD\`."
    echo "  Remediation policy in this run: \`$POLICY\`."
  elif [ "$SCORE" -lt "$THRESHOLD" ]; then
    echo "🟠 **BELOW THRESHOLD** — score \`$SCORE\` < \`$THRESHOLD\`. Status is not 'closed', so this is acceptable for in-progress work."
  else
    echo "🟢 **PASSING** — score \`$SCORE\` ≥ threshold \`$THRESHOLD\`."
  fi
  echo ""
  echo "## Full scorecard"
  echo ""
  cat "$TARGET_DIR/scorecard.md"
  echo ""
  echo "## Cross-bead synthesis (filtered to references mentioning \`$BEAD_ID\`)"
  echo ""
  if [ -f "$PASS_DIR/synthesis.md" ]; then
    grep -F "\`$BEAD_ID\`" "$PASS_DIR/synthesis.md" || echo "(no synthesis findings cite this bead)"
  fi
} > "$REPORT"

cp "$REPORT" "$AUDIT_DIR/REPORT.md"

# Phase 9 — remediate the target only (if false-closed and policy != report-only).
if [ "$STATUS" = "closed" ] && [ "$SCORE" -lt "$THRESHOLD" ] && [ "$POLICY" != "report-only" ]; then
  echo "Phase 9: remediating $BEAD_ID (policy=$POLICY)..." >&2
  # remediate.sh reads false-closed beads from REPORT.md's "False-closed list" section.
  # For single-bead mode, synthesize that section so the reuse path works.
  REM_REPORT="$PASS_DIR/REPORT.md"
  {
    echo ""
    echo "## False-closed list"
    echo ""
    echo "| Bead | Score | Status | Title |"
    echo "|------|------:|--------|-------|"
    echo "| \`$BEAD_ID\` | $SCORE | $STATUS | $TITLE |"
  } >> "$REM_REPORT"
  "$SCRIPTS/remediate.sh" "$PROJECT" "$PASS_DIR" "$POLICY" >/dev/null
fi

# Single-pass single-bead commit. Write through a tmp file so failed jq output
# never corrupts the manifest. Per repo no-deletion policy, failed tmp output is
# retained for diagnosis; a successful mv consumes it.
TMP="$(mktemp)"
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg bid "$BEAD_ID" \
  '.pass_completed_at = $now | .single_bead_target = $bid' \
  "$PASS_DIR/manifest.json" > "$TMP"
mv "$TMP" "$PASS_DIR/manifest.json"
cp "$PASS_DIR/manifest.json" "$AUDIT_DIR/manifest.json"

if [ -d "$AUDIT_DIR/.git" ]; then
  git -C "$AUDIT_DIR" add -A
  git -C "$AUDIT_DIR" commit -m "single-bead audit: $BEAD_ID (pass $(basename "$PASS_DIR"))" >/dev/null 2>&1 || true
fi

echo ""
echo "Single-bead audit complete." >&2
echo "  Bead:    $BEAD_ID  ($STATUS)" >&2
echo "  Score:   $SCORE / 1000   (threshold: $THRESHOLD)" >&2
echo "  Report:  $REPORT" >&2
echo "  Pass:    $PASS_DIR" >&2
# Exit non-zero if false-closed so CI/pre-merge hooks can gate on it.
if [ "$STATUS" = "closed" ] && [ "$SCORE" -lt "$THRESHOLD" ]; then
  exit 2
fi
exit 0
