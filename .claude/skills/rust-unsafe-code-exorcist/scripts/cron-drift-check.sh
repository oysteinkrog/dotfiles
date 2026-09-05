#!/usr/bin/env bash
# cron-drift-check.sh — nightly drift detection in continuous mode.
# Usage: ./cron-drift-check.sh <audit-dir> <project>
#
# Per CONTINUOUS-MODE.md. Compares current project state to audit baseline;
# files drift beads for detected new-site, modified-site, geiger-increase, and harness-failure drift.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: cron-drift-check.sh <audit-dir> <project>}"
PROJECT="${2:?usage: cron-drift-check.sh <audit-dir> <project>}"
PROJECT=$(audit_realpath "$PROJECT")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT")

DATE=$(date -u +%Y-%m-%d)
DRIFT_DIR="$AUDIT_DIR/drift/$DATE"
mkdir -p "$DRIFT_DIR"

CONFIG="$AUDIT_DIR/continuous-mode.toml"
BASELINE="$AUDIT_DIR/baseline"

if [ ! -d "$BASELINE" ]; then
  echo "error: baseline not found at $BASELINE. Run a baseline audit first." >&2
  exit 2
fi

if [ -f "$CONFIG" ] && grep -qE '^\s*enabled\s*=\s*false' "$CONFIG"; then
  echo "Continuous mode is disabled in $CONFIG; exiting."
  exit 0
fi

cd "$PROJECT"

echo "==> [1/6] Re-enumerating unsafe sites"
"$SCRIPT_DIR/enumerate-unsafe.sh" "$PROJECT" "$DRIFT_DIR" >/dev/null

echo "==> [2/6] Generating current inventory"
node "$SCRIPT_DIR/generate-inventory.mjs" "$DRIFT_DIR" >/dev/null

echo "==> [3/6] Computing diff vs baseline"
DIFF_FILE="$DRIFT_DIR/diff.json"
# IMPORTANT: each JSONL file has ONE object per line; `jq -s` over two files
# would slurp objects from BOTH files into a single array (loses file boundary).
# Use `--slurpfile` so each file becomes its own array under $base / $cur.
jq -n \
  --slurpfile base "$BASELINE/unsafe-inventory.jsonl" \
  --slurpfile cur  "$DRIFT_DIR/unsafe-inventory.jsonl" \
  '
    def site_key: "\(.crate)__\(.file)__\(.line_start)__\(.kind)";
    ($base | map({key: (. | site_key), value: .}) | from_entries) as $B |
    ($cur  | map({key: (. | site_key), value: .}) | from_entries) as $C |
    {
      added:   [$C | to_entries[] | select(.key as $k | $B | has($k) | not) | .value],
      removed: [$B | to_entries[] | select(.key as $k | $C | has($k) | not) | .value],
      modified:[$C | to_entries[] | select(.key as $k | ($B | has($k))
                                            and (.value.source_excerpt != $B[$k].source_excerpt))
                                  | .value]
    }
  ' > "$DIFF_FILE"

ADDED=$(jq '.added | length' "$DIFF_FILE")
REMOVED=$(jq '.removed | length' "$DIFF_FILE")
MODIFIED=$(jq '.modified | length' "$DIFF_FILE")

echo "    added: $ADDED, removed: $REMOVED, modified: $MODIFIED"

echo "==> [4/6] Re-running verify.sh"
HARNESS_OK=true
if ! bash "$AUDIT_DIR/verify.sh" "$PROJECT" > "$DRIFT_DIR/verify.log" 2>&1; then
  HARNESS_OK=false
fi
echo "    harness: $($HARNESS_OK && echo GREEN || echo FAIL)"

# Geiger delta. enumerate-unsafe.sh writes per-crate `<crate>__geiger.json`
# files under <DRIFT_DIR>/phase1/. The baseline may have either a single
# `cargo-geiger.json` (older audits) or per-crate files (newer audits); handle
# both shapes via aggregation.
aggregate_geiger() {
  local dir="$1"
  local single="$dir/cargo-geiger.json"
  if [ -f "$single" ]; then
    jq '[.packages[]?.package.metrics.counters | objects | .[] | numbers] | add // 0' \
       "$single" 2>/dev/null || echo 0
    return
  fi
  if [ -d "$dir/phase1" ]; then
    local sum=0 part
    for f in "$dir/phase1"/*__geiger.json; do
      [ -f "$f" ] || continue
      part=$(jq '[.packages[]?.package.metrics.counters | objects | .[] | numbers] | add // 0' \
             "$f" 2>/dev/null || echo 0)
      case "$part" in ''|null) part=0 ;; esac
      sum=$((sum + part))
    done
    echo "$sum"
    return
  fi
  echo 0
}

BASELINE_GEIGER=$(aggregate_geiger "$BASELINE")
CURRENT_GEIGER=$(aggregate_geiger "$DRIFT_DIR")
case "$BASELINE_GEIGER" in ''|null) BASELINE_GEIGER=0 ;; esac
case "$CURRENT_GEIGER"  in ''|null) CURRENT_GEIGER=0  ;; esac
GEIGER_DELTA=$((CURRENT_GEIGER - BASELINE_GEIGER))

echo "==> [5/6] File drift beads (where detected conditions require action)"
DRIFT_EVENTS=0
BEADS_FILED=0
# Single timestamp + per-bead SUFFIX so multiple drift beads filed in the same
# second don't collide on title.
N=$(date +%s)
SUFFIX=1

file_drift_bead() {
  command -v br >/dev/null 2>&1 || return 1
  (
    cd "$AUDIT_DIR"
    br create "$@"
  ) >/dev/null 2>&1
}

if [ "$ADDED" -gt 0 ]; then
  if file_drift_bead --title "drift-${N}-${SUFFIX}: $ADDED new unsafe site(s) since baseline [DRIFT]" \
                      --type bug --priority 1 \
                      --description "Detected $DATE.

$ADDED new unsafe site(s) since baseline.

Affected sites (first 10):
$(jq -r '.added[] | "- \(.crate):\(.file):\(.line_start) — kind=\(.kind)"' "$DIFF_FILE" 2>/dev/null | head -10)

Recommendation: spawn a scoped audit:
  /rust-unsafe-code-exorcist --mode harden-incident --scope drift-${N}-${SUFFIX}

See: $DIFF_FILE"
  then
    BEADS_FILED=$((BEADS_FILED+1))
  fi
  DRIFT_EVENTS=$((DRIFT_EVENTS+1))
  SUFFIX=$((SUFFIX+1))
fi
if [ "$MODIFIED" -gt 0 ]; then
  if file_drift_bead --title "drift-${N}-${SUFFIX}: $MODIFIED modified unsafe site(s) since baseline [DRIFT]" \
                      --type bug --priority 1 \
                      --description "Detected $DATE.

$MODIFIED existing unsafe site(s) changed source text since baseline.

Affected sites (first 10):
$(jq -r '.modified[] | "- \(.crate):\(.file):\(.line_start) — kind=\(.kind)"' "$DIFF_FILE" 2>/dev/null | head -10)

Recommendation: verify each modified site's SAFETY comment and proof obligations still match the current code.

See: $DIFF_FILE"
  then
    BEADS_FILED=$((BEADS_FILED+1))
  fi
  DRIFT_EVENTS=$((DRIFT_EVENTS+1))
  SUFFIX=$((SUFFIX+1))
fi
if [ "$GEIGER_DELTA" -gt 0 ]; then
  if file_drift_bead --title "drift-${N}-${SUFFIX}: cargo-geiger count +$GEIGER_DELTA since baseline [DRIFT]" \
                      --type bug --priority 1 \
                      --description "Geiger: baseline=$BASELINE_GEIGER, current=$CURRENT_GEIGER, delta=+$GEIGER_DELTA. See $DRIFT_DIR."
  then
    BEADS_FILED=$((BEADS_FILED+1))
  fi
  DRIFT_EVENTS=$((DRIFT_EVENTS+1))
  SUFFIX=$((SUFFIX+1))
fi
if ! $HARNESS_OK; then
  if file_drift_bead --title "drift-${N}-${SUFFIX}: verify.sh regression (was green) [DRIFT][HARNESS]" \
                      --type bug --priority 0 \
                      --description "verify.sh failed on $DATE. See $DRIFT_DIR/verify.log."
  then
    BEADS_FILED=$((BEADS_FILED+1))
  fi
  DRIFT_EVENTS=$((DRIFT_EVENTS+1))
  SUFFIX=$((SUFFIX+1))
fi

echo "    drift events: $DRIFT_EVENTS, beads filed: $BEADS_FILED"

if [ "$BEADS_FILED" -gt 0 ]; then
  BEAD_HINT="Run \`br ready | grep -F '[DRIFT]'\` from $AUDIT_DIR to see them."
else
  BEAD_HINT="No bead was created automatically. If drift events is nonzero, use this summary to file the drift bead manually from $AUDIT_DIR."
fi

echo "==> [6/6] Writing daily summary"
cat > "$DRIFT_DIR/summary.md" <<EOF
# Drift detection — $DATE

## Diff vs baseline

- Added sites:    $ADDED
- Removed sites:  $REMOVED
- Modified sites: $MODIFIED
- Geiger delta:   $BASELINE_GEIGER → $CURRENT_GEIGER ($GEIGER_DELTA)
- verify.sh:      $($HARNESS_OK && echo GREEN || echo FAIL)
- Drift events:   $DRIFT_EVENTS

## Beads filed
$BEADS_FILED drift bead(s). $BEAD_HINT
(Note: use \`grep -F\` so the brackets are treated as literal characters, not a regex character class.)

## Files
- Diff: $DIFF_FILE
- Verify log: $DRIFT_DIR/verify.log
- New inventory: $DRIFT_DIR/unsafe-inventory.jsonl
EOF

if [ "$DRIFT_EVENTS" -eq 0 ]; then
  echo "$DATE" >> "$AUDIT_DIR/drift/clean-streak.log"
fi

echo
echo "Continuous-mode drift check complete: $DRIFT_DIR/summary.md"
exit 0
