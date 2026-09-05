#!/usr/bin/env bash
# run-bench-matrix.sh — Run comprehensive-bench against subject + reference.
# Emits JSON v3 report + scorecard + updates .bench-history/*.latest.json.
#
# USAGE:
#   run-bench-matrix.sh <target> <workspace>
#                       [--bench <name>]   (default: comprehensive_bench)
#                       [--bin <name>]     (alias for --bench)
#                       [--profile <prof>] (default: release-perf)
#                       [--rch]            (offload via rch exec --)
#                       [--allow-stub]     (smoke/debug only; never ratchets)
#                       [--gate <name>]    (metadata tag for CI/proof-pack gate)
#
# EXIT CODES:
#   0 — success
#   1 — bench failure
#   2 — required guard file missing
#   3 — usage error
#
# IDEMPOTENT: re-runs overwrite the JSON; .bench-history is git-tracked.

set -euo pipefail

usage() { sed -n '2,15p' "$0"; exit "${1:-3}"; }

TARGET=""
WORKSPACE=""
BENCH="comprehensive_bench"
PROFILE="release-perf"
USE_RCH=0
ALLOW_STUB=0
GATE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --bench|--bin) BENCH="$2"; shift 2;;
    --profile) PROFILE="$2"; shift 2;;
    --rch)     USE_RCH=1; shift;;
    --allow-stub) ALLOW_STUB=1; shift;;
    --gate)    GATE="$2"; shift 2;;
    -h|--help) usage 0;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"
      elif [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$TARGET" ] && [ -n "$WORKSPACE" ] || usage
[ -d "$TARGET" ] || { echo "ERROR: target $TARGET missing" >&2; exit 3; }
mkdir -p "$WORKSPACE"

ARTIFACT_LANE="$WORKSPACE/artifacts/bench/$BENCH"
mkdir -p "$ARTIFACT_LANE"
mkdir -p "$WORKSPACE/.bench-history"

# ---- preflight: concurrent_mode_default_guard.txt -----------------------
GUARD="$ARTIFACT_LANE/concurrent_mode_default_guard.txt"
GIT_SHA="$(cd "$TARGET" && git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
{
  printf 'CONCURRENT_MODE_DEFAULT=true\n'
  printf 'GIT_SHA=%s\n' "$GIT_SHA"
  printf 'TIMESTAMP=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'PROFILE=%s\n' "$PROFILE"
  printf 'BENCH=%s\n' "$BENCH"
  [ -n "$GATE" ] && printf 'GATE=%s\n' "$GATE"
} > "$GUARD"
[ -f "$GUARD" ] || { echo "ERROR: guard file not written" >&2; exit 2; }

# ---- run bench ----------------------------------------------------------
RUN_CMD=(cargo run --profile "$PROFILE" --bin "$BENCH" --)
echo "Running: ${RUN_CMD[*]} (in $TARGET)" >&2

OUT_JSON="$ARTIFACT_LANE/${BENCH}_report.json"
HIST_JSON="$WORKSPACE/.bench-history/${BENCH}.latest.json"

LOG_FILE="$ARTIFACT_LANE/run.log"

run_local() {
  ( cd "$TARGET" && "${RUN_CMD[@]}" 2>&1 ) > "$LOG_FILE" && return 0 || return 1
}

run_rch() {
  if ! command -v rch >/dev/null 2>&1; then
    echo "WARN: rch not on PATH; falling back to local run." >&2
    run_local
    return $?
  fi
  ( cd "$TARGET" && rch exec -- "${RUN_CMD[@]}" 2>&1 ) > "$LOG_FILE" && return 0 || return 1
}

if [ "$USE_RCH" -eq 1 ]; then
  run_rch || { echo "bench failed (see $LOG_FILE)"; exit 1; }
else
  run_local || { echo "bench failed (see $LOG_FILE)"; exit 1; }
fi

# Conventionally, comprehensive_bench writes its JSON v3 report to stdout or to
# a known path. We accept either: copy file if discoverable, else assume the
# log contains the JSON payload.
CANDIDATE="$(find "$TARGET/target" -maxdepth 5 -name "${BENCH}*report*.json" 2>/dev/null | head -1 || true)"
if [ -n "$CANDIDATE" ] && [ -f "$CANDIDATE" ]; then
  cp "$CANDIDATE" "$OUT_JSON"
else
  # try to slurp the last JSON object in the log
  awk '/^{/,/^}$/' "$LOG_FILE" > "$OUT_JSON" 2>/dev/null || true
fi

if [ ! -s "$OUT_JSON" ]; then
  if [ "$ALLOW_STUB" -ne 1 ]; then
    echo "ERROR: could not locate JSON v3 report; refusing to update bench history from a stub." >&2
    echo "       rerun with --allow-stub only for smoke/debug runs that must not ratchet." >&2
    exit 1
  fi
  echo "WARN: could not locate JSON v3 report; wrote non-ratcheting stub." >&2
  {
    printf '{\n'
    printf '  "schema_version": "fsqlite-e2e.comprehensive-bench-report.v3",\n'
    printf '  "stub": true,\n'
    printf '  "log_file": "%s",\n' "$LOG_FILE"
    printf '  "git_sha": "%s"\n' "$GIT_SHA"
    printf '}\n'
  } > "$OUT_JSON"
fi

# ---- validate report and emit scorecard sidecar -------------------------
SCORECARD="$ARTIFACT_LANE/scorecard.json"
python3 - "$OUT_JSON" "$SCORECARD" "$BENCH" "$PROFILE" "$GIT_SHA" "$HIST_JSON" "$GUARD" <<'PYTHON'
import json, sys, time

report_fp, scorecard_fp, bench, profile, git_sha, hist_fp, guard_fp = sys.argv[1:8]
with open(report_fp) as f:
    report = json.load(f)

if not isinstance(report, dict):
    raise SystemExit(f"ERROR: {report_fp} is not a JSON object")

is_stub = bool(report.get("stub"))
if not is_stub:
    schema = str(report.get("schema_version", ""))
    if not schema.endswith("comprehensive-bench-report.v3"):
        raise SystemExit(
            f"ERROR: {report_fp} schema_version={schema!r}; expected a *comprehensive-bench-report.v3 artifact"
        )
    if not isinstance(report.get("detected_environment"), dict):
        raise SystemExit(f"ERROR: {report_fp} missing top-level detected_environment")
    if not isinstance(report.get("ci_regression_gate"), dict):
        raise SystemExit(f"ERROR: {report_fp} missing top-level ci_regression_gate")

def norm_stats(value):
    if isinstance(value, dict):
        if "passes" in value or "failures" in value:
            return {
                "passes": float(value.get("passes", 0.0)),
                "failures": float(value.get("failures", 0.0)),
            }
        for key in ("score", "pass_rate", "ratio", "relative_score", "weighted_score"):
            if key in value:
                score = max(0.0, min(1.0, float(value[key])))
                total = float(value.get("total", value.get("observations", 1.0)))
                return {"passes": score * total, "failures": (1.0 - score) * total}
    if isinstance(value, (int, float)):
        score = max(0.0, min(1.0, float(value)))
        return {"passes": score, "failures": 1.0 - score}
    return None

per_category = {}
for container_key in ("per_category", "categories", "category_scores"):
    container = report.get(container_key)
    if isinstance(container, dict):
        for name, value in container.items():
            stats = norm_stats(value)
            if stats:
                per_category[name] = stats
    elif isinstance(container, list):
        for item in container:
            if not isinstance(item, dict):
                continue
            name = item.get("name") or item.get("category") or item.get("family")
            if not name:
                continue
            stats = norm_stats(item)
            if stats:
                per_category[name] = stats

if not is_stub and not per_category:
    raise SystemExit(f"ERROR: {report_fp} has no per-category score data")

scorecard = {
    "schema_version": "gauntlet.bench_scorecard.v1",
    "bench": bench,
    "profile": profile,
    "git_sha": git_sha,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "report": report_fp,
    "history": hist_fp if not report.get("stub") else None,
    "guard": guard_fp,
    "stub": bool(report.get("stub")),
    "per_category": per_category,
    "observation_count": sum(v["passes"] + v["failures"] for v in per_category.values()),
}
with open(scorecard_fp, "w") as f:
    json.dump(scorecard, f, indent=2, sort_keys=True)
PYTHON

# ---- update .bench-history/<bench>.latest.json (used by ratchet) --------
if grep -q '"stub": true' "$OUT_JSON"; then
  echo "WARN: stub report not copied to $HIST_JSON" >&2
else
  cp "$OUT_JSON" "$HIST_JSON"
fi

echo "OK"
echo "  report:    $OUT_JSON"
echo "  history:   $HIST_JSON"
echo "  scorecard: $SCORECARD"
echo "  guard:     $GUARD"
