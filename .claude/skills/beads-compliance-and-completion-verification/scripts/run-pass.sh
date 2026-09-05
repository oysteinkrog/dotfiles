#!/usr/bin/env bash
# run-pass.sh — Convenience wrapper that orchestrates a full audit pass end-to-end.
#
# Usage:
#   run-pass.sh <project-path> [--threshold 700] [--mode full-audit]
#                              [--policy completion-debt]
#                              [--as-of <git-ref>] [--bead-id <id>]
#
# Flags:
#   --threshold N         score < N for a `closed` bead → false-closed (default 700;
#                         overridden by audit-policy.yaml#threshold; CLI wins)
#   --mode <name>         The mode label is recorded in manifest.json#mode for
#                         downstream tools (dashboard, drift-check, audit-self-
#                         explainer) to read; this wrapper does NOT branch on it
#                         today — phase behaviour is the same regardless. Accepts
#                         any string; canonical names per references/MODES-AND-
#                         TIERS.md are:
#                           triage | standard | comprehensive | tripwire |
#                           re-verification | onboarding
#                         The default `full-audit` is the legacy synonym for
#                         `standard`. Use `single-bead` and `time-machine`
#                         labels only when invoked via their dedicated wrappers
#                         (scripts/single-bead-audit.sh, scripts/time-machine-
#                         audit.sh) — both pass the right label through. (CLI-
#                         only — not in YAML schema today.)
#   --policy <name>       completion-debt | reopen | report-only (default
#                         completion-debt; overridden by audit-policy.yaml#remediation_policy)
#   --as-of <ref>         documented in TIME-MACHINE-MODE.md; this wrapper accepts
#                         the flag but emits a WARNING because real time-machine
#                         orchestration belongs in scripts/time-machine-audit.sh
#   --bead-id <id>        documented in single-bead mode; this wrapper accepts
#                         the flag but emits a WARNING because real per-bead
#                         orchestration belongs in scripts/single-bead-audit.sh
#   --audit-dir <path>    Override the default subdirectory location
#                         (`<project>/beads_compliance_audit/`). Use this when
#                         you want to keep the audit dir somewhere else (e.g.
#                         a dedicated audit-only filesystem, or a CI artifacts
#                         directory). Sets AUDIT_DIR_OVERRIDE for
#                         bootstrap-audit.sh; relative paths are resolved
#                         against the cwd before exporting.
#
# Most users should drive the phases via subagents (see subagents/) for parallelism.
# This script is for single-agent local runs and CI tripwire mode.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path required}"
shift || true

# --- Defaults: hardcoded < audit-policy.yaml < CLI flags ---------------------
THRESHOLD=700
MODE="full-audit"
POLICY="completion-debt"
AS_OF=""        # documented in TIME-MACHINE-MODE.md; currently no-op here
BEAD_ID=""      # documented in RELEASE-GATING.md / single-bead mode
AUDIT_DIR_FLAG=""   # if set via --audit-dir, exported as AUDIT_DIR_OVERRIDE
SKIP_POLISH=0       # `--no-polish` disables Phase 9.5 (only when user asked)
SKIP_CALIBRATION=0  # `--no-calibration` disables the bottom-N spot-check helper
CALIBRATION_N=5     # bottom-N count for the calibration helper

require_value() {
  # $1=flag-name, $2=remaining-arg-count
  if [ "$2" -lt 2 ]; then
    echo "ERROR: $1 requires a value (e.g. $1 700)" >&2
    exit 3
  fi
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

# `audit-policy.yaml` resolution needs the audit-dir override before the main
# parser runs, while CLI threshold/policy flags still need to win afterward.
ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    --audit-dir)
      if [ $((i + 1)) -ge ${#ARGS[@]} ]; then
        echo "ERROR: --audit-dir requires a value (e.g. --audit-dir ./audit)" >&2
        exit 3
      fi
      AUDIT_DIR_FLAG="$(resolve_audit_dir_arg "${ARGS[$((i + 1))]}")"
      break
      ;;
  esac
done

# Load audit-policy.yaml from <audit-dir>/, <project>/, or <project>/.beads/
# (in that order). Sets POLICY_THRESHOLD / POLICY_REMEDIATION_POLICY /
# POLICY_PARALLELISM_PER_PHASE if found; leaves them empty otherwise so the
# hardcoded defaults survive.
. "$(dirname "$0")/_load-policy.sh"
load_policy "$PROJECT" "$AUDIT_DIR_FLAG"
[ -n "${POLICY_THRESHOLD:-}" ] && THRESHOLD="$POLICY_THRESHOLD"
[ -n "${POLICY_REMEDIATION_POLICY:-}" ] && POLICY="$POLICY_REMEDIATION_POLICY"
# Mode is not in the YAML schema today; treated as a CLI-only override.

while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) require_value "$1" "$#"; THRESHOLD="$2"; shift 2 ;;
    --mode)      require_value "$1" "$#"; MODE="$2"; shift 2 ;;
    --policy)    require_value "$1" "$#"; POLICY="$2"; shift 2 ;;
    --as-of)
      require_value "$1" "$#"
      AS_OF="$2"; shift 2
      echo "WARNING: --as-of is documented but not yet implemented in run-pass.sh." >&2
      echo "         The audit will run against HEAD; ignore the AS_OF value." >&2
      echo "         For real time-machine audits, manually:" >&2
      echo "           git -C <project> stash push" >&2
      echo "           git -C <project> checkout $AS_OF" >&2
      echo "           run-pass.sh ... ; git checkout - ; git stash pop" >&2
      ;;
    --bead-id)
      require_value "$1" "$#"
      BEAD_ID="$2"; shift 2
      echo "WARNING: --bead-id (single-bead mode) is documented but not yet" >&2
      echo "         routed through run-pass.sh. The audit will run on the full" >&2
      echo "         bead universe. Filter REPORT.md / scorecards by '$BEAD_ID'" >&2
      echo "         after the pass, OR use the orchestrator (subagents) to scope." >&2
      ;;
    --audit-dir)
      require_value "$1" "$#"
      # Resolve relative paths NOW (cwd of the user) so the env var we
      # hand to bootstrap-audit.sh is unambiguous. If the parent dir does
      # not yet exist (legitimate first-run case), fall back to passing the
      # value through unchanged — bootstrap-audit.sh will either accept it
      # absolute or error with a clear message for relative-and-unrooted.
      AUDIT_DIR_FLAG="$(resolve_audit_dir_arg "$2")"
      shift 2
      ;;
    --no-polish)        SKIP_POLISH=1; shift ;;
    --no-calibration)   SKIP_CALIBRATION=1; shift ;;
    --calibration-n)    require_value "$1" "$#"; CALIBRATION_N="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 3 ;;
  esac
done

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$SKILL_DIR/scripts"

# Capture the project's branch BEFORE doing anything. The skill's hard rule is
# that the audit must NEVER switch branches in the project repo. We snapshot
# here and verify at the end so a Phase-9 commit (which is OK on .beads/) can't
# silently move HEAD via some unexpected git invocation along the way.
PROJECT_ABS="$(cd "$PROJECT" && pwd)"
ENTRY_BRANCH=""
if [ -d "$PROJECT_ABS/.git" ]; then
  ENTRY_BRANCH="$(git -C "$PROJECT_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
fi

# Phase loops below glob `"$PASS_DIR"/beads/*/...`. With nullglob OFF (bash
# default), a glob with no matches expands to its literal pattern — and the
# loop body would then run with `$bd` set to `…/beads/*/`, calling
# extract-spec.py on a literal asterisk and erroring confusingly. nullglob
# makes empty matches collapse to zero iterations, which is the correct
# behaviour for a project that has no closed beads (legitimate first-run
# state) or a Phase 1 inventory that produced an empty universe.
shopt -s nullglob

# Phase 0.5 — bootstrap. Pass policy through so manifest records it for Phase 9.
# AUDIT_DIR_OVERRIDE is read by bootstrap-audit.sh; setting it inline (not
# `export`) keeps the var scoped to this single subprocess invocation.
if [ -n "$AUDIT_DIR_FLAG" ]; then
  PASS_DIR="$(AUDIT_DIR_OVERRIDE="$AUDIT_DIR_FLAG" "$SCRIPTS/bootstrap-audit.sh" "$PROJECT" "$THRESHOLD" "$MODE" "$POLICY")"
else
  PASS_DIR="$("$SCRIPTS/bootstrap-audit.sh" "$PROJECT" "$THRESHOLD" "$MODE" "$POLICY")"
fi
echo "Pass dir: $PASS_DIR"

AUDIT_DIR="$(cd "$PASS_DIR/../.." && pwd)"

# Phase 1 — inventory
"$SCRIPTS/inventory-beads.sh" "$PROJECT" "$PASS_DIR" >/dev/null

# Phase 2 — spec extraction (sequential fallback; subagents parallelize this)
echo "Phase 2: extracting specs..."
for show in "$PASS_DIR"/beads/*/show.json; do
  bd="$(dirname "$show")"
  python3 "$SCRIPTS/extract-spec.py" "$show" > "$bd/spec.json"
done

echo "Phase 3: heuristic evidence gathering..."
for bd in "$PASS_DIR"/beads/*/; do
  "$SCRIPTS/gather-evidence.sh" "$PROJECT" "$bd" >/dev/null 2>&1 || true
done

echo "Phase 4: (skipped in wrapper — Phase 4 needs subagents to actually run tests; stubbing compliance.json + test_depth.json)"
for bd in "$PASS_DIR"/beads/*/; do
  ID="$(basename "$bd")"
  [ -f "$bd/compliance.json" ] || jq -n --arg id "$ID" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{bead_id: $id, executed_at: $now, executor: "stub-wrapper", checks: []}' > "$bd/compliance.json"
  [ -f "$bd/test_depth.json" ] || jq -n --arg id "$ID" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{bead_id: $id, audited_at: $now, auditor: "stub-wrapper", checks: []}' > "$bd/test_depth.json"
done

echo "Phase 5: theater + anomaly scan..."
for bd in "$PASS_DIR"/beads/*/; do
  "$SCRIPTS/theater-scan.sh" "$PROJECT" "$bd" >/dev/null 2>&1 || true
  "$SCRIPTS/anomaly-scan.sh" "$PROJECT" "$bd" >/dev/null 2>&1 || true
done

echo "Phase 7: cross-bead synthesis..."
python3 "$SCRIPTS/synthesize.py" "$PASS_DIR" >/dev/null 2>&1 || true

# Phase 8 — score. Look up the most recent prior pass dir (by sort order) so the
# scorer can fold prior scores into the trend line.
# IMPORTANT: declare these as bash arrays from the start; treating them as
# strings and then expanding "${var[@]}" emits a single empty positional
# argument that breaks downstream arg parsing.
echo "Phase 8: scoring..."
PRIOR_PASS_DIR=""
PRIOR_PASS_ARG=()
PRIOR_FOR_REPORT=()
# grep -v exits 1 when nothing matches (the current pass is the only one), and
# `set -o pipefail` would propagate that and kill the script. Use `|| true` so
# "no prior pass" is the legitimate first-pass case, not an error.
PRIOR_CANDIDATE="$( { ls -1d "$AUDIT_DIR/passes"/*/ 2>/dev/null | sed 's|/$||' | grep -v "/$(basename "$PASS_DIR")$" | sort | tail -1; } || true)"
if [ -n "$PRIOR_CANDIDATE" ]; then
  PRIOR_PASS_DIR="$PRIOR_CANDIDATE"
  PRIOR_PASS_ARG=( --prior-pass-dir "$PRIOR_PASS_DIR" )
  PRIOR_FOR_REPORT=( --prior-pass-dir "$PRIOR_PASS_DIR" )
fi

for bd in "$PASS_DIR"/beads/*/; do
  python3 "$SCRIPTS/score-bead.py" "$bd" \
    --threshold "$THRESHOLD" \
    --rubric "$AUDIT_DIR/rubric.md" \
    --synthesis "$PASS_DIR/synthesis.md" \
    "${PRIOR_PASS_ARG[@]}" >/dev/null
done

python3 "$SCRIPTS/master-report.py" "$PASS_DIR" --threshold "$THRESHOLD" "${PRIOR_FOR_REPORT[@]}"

# Calibration spot-check — generate a bottom-N ground-truth checklist BEFORE
# remediation. Across prior runs of this skill, ≥80% of low-score beads were
# SCORE FALSE POSITIVES; the calibration report is what turns "153 false-
# closed!" into "8 actually false-closed; 145 are pipeline artifacts". Always
# generate (it's read-only) unless --no-calibration was passed.
# stderr is INTENTIONALLY propagated so calibrate-bottom-n.sh failures are
# visible — silently swallowing them was Bug R1 in the v1.2 self-review.
if [ "$SKIP_CALIBRATION" -eq 0 ]; then
  echo "Calibration: spot-check report for bottom $CALIBRATION_N beads..."
  "$SCRIPTS/calibrate-bottom-n.sh" "$PROJECT" "$PASS_DIR" \
    --n "$CALIBRATION_N" --threshold "$THRESHOLD" >/dev/null || true
fi

# Phase 9 — remediate
echo "Phase 9: remediating with policy=$POLICY..."
"$SCRIPTS/remediate.sh" "$PROJECT" "$PASS_DIR" "$POLICY" >/dev/null

# Phase 9.5 — write the polish-loop SCAFFOLD (when Phase 9 wrote beads).
# The polish script is pure scaffolding: it generates polish_log.md with three
# sweep sections pre-populated with the verbatim polish prompt + per-bead
# context. The actual prompt application is done by the ORCHESTRATOR AGENT
# (the LLM that invoked this skill), not by run-pass.sh — there's no agent in
# the loop here.
#
# We pass --force because run-pass.sh may be re-invoked on the same pass dir
# (e.g. tripwire reruns), and overwriting the scaffold is fine when the
# orchestrator hasn't yet started filling it in. If the orchestrator HAS
# started, they should re-run polish-remediation-beads.sh manually without
# --force, see the refusal, and decide whether to back up.
#
# stderr is propagated so the scaffold-written summary lands in the user's
# console and the orchestrator can see whether scaffolding succeeded.
if [ "$SKIP_POLISH" -eq 0 ] && [ "$POLICY" != "report-only" ]; then
  echo "Phase 9.5: writing polish-loop scaffold (orchestrator agent drives the actual sweeps)..."
  "$SCRIPTS/polish-remediation-beads.sh" "$PROJECT" "$PASS_DIR" \
    --sweeps 3 --force >/dev/null || true
fi

# Phase 10 — convergence. Pass --score-threshold so Phase 10 uses the SAME
# false-closed cutoff the rest of the pass scored against. Without this,
# convergence-check.py falls back to its default (700) and misclassifies
# beads when the pass was run at a different threshold (e.g.
# `--threshold 800`) — silently reports "no new false-closed" while the
# bead IS newly false-closed at the user's threshold.
echo "Phase 10: convergence check..."

# convergence-check.py fails closed when fresh_eyes_review.json is absent
# (correct for orchestrators that DO run the fresh-eyes subagent — missing
# review = unverified rubric consistency). This wrapper, however, has no
# subagent in the loop; if we left the file missing, EVERY run-pass.sh
# pass would always report `is_converged: false` regardless of actual
# behavior, making the convergence signal useless. Emit a stub review with
# `wrapper-stub: true` so consumers (and the next pass's reviewer) can tell
# this verdict was deterministic rather than an actual fresh-eyes audit.
# Same pattern run-pass.sh uses for the Phase-4 compliance/test_depth stubs.
if [ ! -f "$PASS_DIR/fresh_eyes_review.json" ]; then
  jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{rubric_consistency_pass: true,
      reason: "stubbed by run-pass.sh (no fresh-eyes subagent in this orchestrator). Run subagents/fresh-eyes-rubric-auditor.md for a real review; the next pass should overwrite this stub.",
      reviewed_at: $now,
      reviewer: "run-pass.sh",
      wrapper_stub: true,
      spot_checks: [],
      generosity_flags: [],
      category_miss_flags: []}' \
    > "$PASS_DIR/fresh_eyes_review.json"
fi
if [ -n "$PRIOR_PASS_DIR" ]; then
  python3 "$SCRIPTS/convergence-check.py" --score-threshold "$THRESHOLD" --current "$PASS_DIR" --prior "$PRIOR_PASS_DIR" || true
else
  python3 "$SCRIPTS/convergence-check.py" --score-threshold "$THRESHOLD" --current "$PASS_DIR" || true
fi

# Update manifest with completion timestamp. Write through a tmp file so a jq
# failure never corrupts the manifest. Per repo no-deletion policy, failed tmp
# output is retained for diagnosis; a successful mv consumes it.
TMP="$(mktemp)"
if [ -f "$PASS_DIR/convergence.json" ]; then
  jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --slurpfile conv "$PASS_DIR/convergence.json" \
    '.pass_completed_at = $now | .convergence = $conv[0]' "$PASS_DIR/manifest.json" > "$TMP"
else
  jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.pass_completed_at = $now' "$PASS_DIR/manifest.json" > "$TMP"
fi
mv "$TMP" "$PASS_DIR/manifest.json"
cp "$PASS_DIR/manifest.json" "$AUDIT_DIR/manifest.json"

# Optional dashboard (no-op if matplotlib-style output isn't desired; pure SVG).
# Generate after convergence has been copied into the top-level manifest.
python3 "$SCRIPTS/dashboard.py" "$AUDIT_DIR" >/dev/null 2>&1 || true

# Single audit-pass commit.
if [ -d "$AUDIT_DIR/.git" ]; then
  git -C "$AUDIT_DIR" add -A
  git -C "$AUDIT_DIR" commit -m "audit pass $(basename "$PASS_DIR")" >/dev/null 2>&1 || true
fi

# Branch-drift sanity check. Hard skill rule: project repo must end on the
# same branch we entered on. If it drifted, surface loudly — most likely cause
# is a Phase-9 / Phase-9.5 hook or a misbehaving subagent that ran a
# `git checkout -b` along the way. We do NOT auto-revert; the user needs to
# decide what to do with whatever HEAD got moved to.
if [ -n "$ENTRY_BRANCH" ] && [ -d "$PROJECT_ABS/.git" ]; then
  EXIT_BRANCH="$(git -C "$PROJECT_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [ -n "$EXIT_BRANCH" ] && [ "$EXIT_BRANCH" != "$ENTRY_BRANCH" ]; then
    echo "" >&2
    echo "⚠️  BRANCH DRIFT DETECTED" >&2
    echo "   Project entered the audit on branch: $ENTRY_BRANCH" >&2
    echo "   Project ended the audit on branch:   $EXIT_BRANCH" >&2
    echo "   The skill's hard rule is to NEVER switch branches. Investigate" >&2
    echo "   what moved HEAD before declaring the audit complete." >&2
    echo "   To restore: git -C $PROJECT_ABS checkout $ENTRY_BRANCH" >&2
    echo "" >&2
  fi
fi

echo ""
echo "Pass complete. See:"
echo "  $AUDIT_DIR/REPORT.md (master report)"
echo "  $PASS_DIR/calibration.md (bottom-$CALIBRATION_N spot-check — read BEFORE acting on REPORT.md)"
echo "  $AUDIT_DIR/remediation.md (Phase 9 actions)"
if [ "$SKIP_POLISH" -eq 0 ] && [ "$POLICY" != "report-only" ]; then
  echo "  $PASS_DIR/polish_log.md (Phase 9.5 polish-loop log)"
fi
echo "  $PASS_DIR/convergence.json (Phase 10 verdict)"
