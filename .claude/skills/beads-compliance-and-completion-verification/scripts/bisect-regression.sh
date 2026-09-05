#!/usr/bin/env bash
# bisect-regression.sh — git-bisect a bead-score regression to a single commit.
#
# Setup: a bead's score regressed pass-over-pass (e.g. 880 → 540 across the
# last two audits). The author insists "I didn't touch that code." We don't
# care — we want the commit that broke it. This script automates git-bisect
# using single-bead-audit.sh as the test predicate.
#
# How:
#   1. Find the most recent passing pass (score >= threshold) — the "good".
#   2. The latest failing pass is the "bad".
#   3. git bisect start; mark good and bad SHAs from manifest.json.
#   4. For each bisect step: create a fresh worktree at that SHA, run
#      single-bead-audit on the target bead, score >= threshold → good,
#      else → bad. Standard bisection.
#   5. Print the offending commit (and its body, with author/date), retaining
#      the bisect worktree for diagnosis.
#
# Usage:
#   bisect-regression.sh <project-path> <bead-id>
#     [--audit-dir <path>]           default: <project>/beads_compliance_audit/
#     [--threshold 700]              passing-score threshold
#     [--good <sha>] [--bad <sha>]   override auto-detection
#
# Output:
#   - bisect_log.txt in the audit dir's bisect/<bead-id>/ subdir
#   - prints the offending commit SHA + summary on success
#
# Safety:
#   - Always uses worktrees; never disturbs the project's main working tree.
#   - The bisect worktree is retained; cleanup is a human decision.
#   - If the user's HEAD has uncommitted changes, we DO NOT touch them — the
#     worktree is independent.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path required}"
BEAD_ID="${2:?bead-id required}"
shift 2

[ -d "$PROJECT/.git" ] || { echo "ERROR: $PROJECT is not a git repo" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$SKILL_DIR/scripts"

# Defaults: hardcoded < audit-policy.yaml < CLI flags.
AUDIT_DIR=""
THRESHOLD=700
GOOD_SHA=""
BAD_SHA=""

require_value() { if [ "$2" -lt 2 ]; then echo "ERROR: $1 requires a value" >&2; exit 3; fi; }

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

# Policy resolution must see the requested audit dir; otherwise bisect runs can
# silently use the default threshold while reading pass history from another
# audit tree.
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

. "$SCRIPTS/_load-policy.sh"
load_policy "$PROJECT" "$AUDIT_DIR"
[ -n "${POLICY_THRESHOLD:-}" ] && THRESHOLD="$POLICY_THRESHOLD"

while [ $# -gt 0 ]; do
  case "$1" in
    --audit-dir) require_value "$1" "$#"; AUDIT_DIR="$(resolve_audit_dir_arg "$2")"; shift 2 ;;
    --threshold) require_value "$1" "$#"; THRESHOLD="$2"; shift 2 ;;
    --good)      require_value "$1" "$#"; GOOD_SHA="$2"; shift 2 ;;
    --bad)       require_value "$1" "$#"; BAD_SHA="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 3 ;;
  esac
done

if [ -z "$AUDIT_DIR" ]; then
  AUDIT_DIR="$(cd "$PROJECT" && pwd)/beads_compliance_audit"
fi
[ -d "$AUDIT_DIR/passes" ] || { echo "ERROR: no audit history at $AUDIT_DIR/passes" >&2; exit 4; }

# Auto-detect good/bad SHAs from pass history if not supplied.
# A pass's manifest.json may or may not record the project's HEAD SHA at audit
# time (depends on the version of bootstrap-audit.sh). We probe defensively.
if [ -z "$GOOD_SHA" ] || [ -z "$BAD_SHA" ]; then
  echo "Auto-detecting good/bad SHAs from audit pass history..." >&2
  for PASS_DIR in $(ls -1d "$AUDIT_DIR/passes"/*/ 2>/dev/null | sort -r); do
    SC="$PASS_DIR/beads/$BEAD_ID/scorecard.md"
    [ -f "$SC" ] || continue
    # Portable: grep -P is GNU-only; sed -nE works on both GNU + BSD/macOS.
    SCORE="$(sed -nE 's/.*Score:[[:space:]]+([0-9]+).*/\1/p' "$SC" 2>/dev/null | head -1)"
    [ -n "$SCORE" ] || SCORE=0
    SHA="$(jq -r '.project_git_sha_at_pass_start // .project_sha // .as_of_sha // empty' "$PASS_DIR/manifest.json" 2>/dev/null)"
    [ -n "$SHA" ] || continue
    if [ "$SCORE" -ge "$THRESHOLD" ] && [ -z "$GOOD_SHA" ]; then GOOD_SHA="$SHA"; fi
    if [ "$SCORE" -lt "$THRESHOLD" ] && [ -z "$BAD_SHA" ]; then BAD_SHA="$SHA"; fi
    [ -n "$GOOD_SHA" ] && [ -n "$BAD_SHA" ] && break
  done
fi

if [ -z "$GOOD_SHA" ] || [ -z "$BAD_SHA" ]; then
  echo "ERROR: could not auto-detect good/bad SHAs. Pass --good <sha> --bad <sha> explicitly." >&2
  echo "       (audit pass manifests may lack project_sha; bisect needs both endpoints.)" >&2
  exit 5
fi

echo "Bisecting bead $BEAD_ID:" >&2
echo "  good (score ≥ $THRESHOLD): $GOOD_SHA" >&2
echo "  bad  (score <  $THRESHOLD): $BAD_SHA" >&2

OUT_DIR="$AUDIT_DIR/bisect/$BEAD_ID"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/bisect_log.txt"
: > "$LOG"

# Use a dedicated bisect worktree so the project repo is untouched.
TS="$(date -u +%s)"
WORKTREE="/tmp/$(basename "$PROJECT")__bisect_${BEAD_ID}__${TS}"

cleanup() {
  if [ -d "$WORKTREE" ]; then
    echo "Retained bisect worktree for diagnosis: $WORKTREE" >&2
  fi
}
trap cleanup EXIT

git -C "$PROJECT" worktree add --detach "$WORKTREE" "$BAD_SHA" >/dev/null
echo "Bisect worktree: $WORKTREE" | tee -a "$LOG" >&2

git -C "$WORKTREE" bisect start "$BAD_SHA" "$GOOD_SHA" 2>&1 | tee -a "$LOG" >&2

PREDICATE_OUT="$OUT_DIR/predicate.log"
: > "$PREDICATE_OUT"

# Inner bisect loop. Each iteration: HEAD is the candidate; run a quick
# single-bead audit; report good/bad; let git pick the next candidate.
#
# Safety: cap iterations at MAX_BISECT_STEPS. git-bisect always converges in
# O(log N) steps so 100 covers any realistic project history; if we hit it,
# something pathological is happening (predicate output git-bisect doesn't
# recognize, infinite skip loop, etc.) and we abort with a clear error
# instead of looping forever.
MAX_BISECT_STEPS=100
STEP=0
BISECT_CONCLUSIVE=0
while true; do
  STEP=$((STEP + 1))
  if [ "$STEP" -gt "$MAX_BISECT_STEPS" ]; then
    echo "ERROR: bisect exceeded $MAX_BISECT_STEPS steps without converging — aborting." >&2
    echo "       See $PREDICATE_OUT and $LOG for diagnostics." >&2
    git -C "$WORKTREE" bisect reset >/dev/null 2>&1 || true
    exit 7
  fi
  HEAD_SHA="$(git -C "$WORKTREE" rev-parse HEAD)"
  echo "--- step $STEP testing $HEAD_SHA ---" >> "$PREDICATE_OUT"
  set +e
  "$SCRIPTS/single-bead-audit.sh" "$WORKTREE" "$BEAD_ID" \
    --threshold "$THRESHOLD" --policy report-only --audit-dir "$OUT_DIR/run_${HEAD_SHA:0:10}" \
    >> "$PREDICATE_OUT" 2>&1
  PRED_RC=$?
  set -e
  # single-bead-audit.sh exits 0 on PASS (score >= threshold) and 2 on FAIL.
  if [ "$PRED_RC" -eq 0 ]; then
    git -C "$WORKTREE" bisect good 2>&1 | tee -a "$LOG" >&2
  elif [ "$PRED_RC" -eq 2 ]; then
    git -C "$WORKTREE" bisect bad 2>&1 | tee -a "$LOG" >&2
  else
    # Predicate errored (build broken etc.) → mark as 'skip'.
    git -C "$WORKTREE" bisect skip 2>&1 | tee -a "$LOG" >&2
  fi
  LAST="$(tail -3 "$LOG")"
  if echo "$LAST" | grep -q 'is the first bad commit'; then
    BISECT_CONCLUSIVE=1
    break
  fi
  if echo "$LAST" | grep -qE 'There are only .* untested commits left|We cannot bisect more'; then break; fi
done

OFFENDER_SHA=""
if [ "$BISECT_CONCLUSIVE" -eq 1 ]; then
  # Do not parse `# bad: [...]` from `git bisect log`: the first such entry is
  # the initial failing endpoint. The conclusive output line names the actual
  # first bad commit. Keep refs/bisect/bad as a fallback before reset.
  OFFENDER_SHA="$(sed -nE 's/^([a-f0-9]{7,40}) is the first bad commit$/\1/p' "$LOG" | tail -1)"
  if [ -z "$OFFENDER_SHA" ]; then
    OFFENDER_SHA="$(git -C "$WORKTREE" rev-parse --verify refs/bisect/bad 2>/dev/null || true)"
  fi
fi
git -C "$WORKTREE" bisect reset >/dev/null 2>&1 || true

if [ -n "$OFFENDER_SHA" ]; then
  echo "" | tee -a "$LOG"
  echo "=== Offending commit ===" | tee -a "$LOG"
  git -C "$PROJECT" log -1 --pretty=fuller "$OFFENDER_SHA" | tee -a "$LOG"
  echo "" | tee -a "$LOG"
  echo "=== Files changed ===" | tee -a "$LOG"
  git -C "$PROJECT" show --stat --pretty="" "$OFFENDER_SHA" | tee -a "$LOG"
  echo ""
  echo "Bisect complete. Offending commit: $OFFENDER_SHA"
  echo "Full log: $LOG"
  exit 0
else
  echo "Bisect produced no clear offender. See $LOG."
  exit 6
fi
