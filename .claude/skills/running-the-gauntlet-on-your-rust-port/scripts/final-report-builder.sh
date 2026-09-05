#!/usr/bin/env bash
# final-report-builder.sh — Collate phase16_* markdown into
# FINAL_GAUNTLET_REPORT.md. Build the certification-bundle directory:
# confidence gate JSON + verification contract JSON + release certificate JSON
# + CI artifact manifest + benchmark summary + scorecards.json + critical-path
# report + ratchet state.
#
# USAGE:
#   final-report-builder.sh <workspace>
#                           [--template <path>]
#                           [--bundle-dir <path>]
#                           [--incremental]
#
# OUTPUT FILES:
#   <workspace>/FINAL_GAUNTLET_REPORT.md
#   <workspace>/REBASE_REPORT.md (with --incremental)
#   <workspace>/certification_bundle/*
#
# EXIT CODES:
#   0 — report built
#   1 — required inputs missing
#   3 — usage error
#
# IDEMPOTENT.

set -euo pipefail
shopt -s globstar nullglob

usage() { sed -n '2,14p' "$0"; exit "${1:-3}"; }

WORKSPACE=""
TEMPLATE=""
BUNDLE_DIR=""
INCREMENTAL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --template)   TEMPLATE="$2"; shift 2;;
    --bundle-dir) BUNDLE_DIR="$2"; shift 2;;
    --incremental) INCREMENTAL=1; shift;;
    -h|--help)    usage 0;;
    *)
      if [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$WORKSPACE" ] || usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE="${TEMPLATE:-$SKILL_DIR/assets/final-gauntlet-report-template.md}"
if [ "$INCREMENTAL" -eq 1 ]; then
  BUNDLE_DIR="${BUNDLE_DIR:-$WORKSPACE/certification_bundle_incremental}"
  FINAL_REPORT="$WORKSPACE/REBASE_REPORT.md"
else
  BUNDLE_DIR="${BUNDLE_DIR:-$WORKSPACE/certification_bundle}"
  FINAL_REPORT="$WORKSPACE/FINAL_GAUNTLET_REPORT.md"
fi

mkdir -p "$BUNDLE_DIR"

# ---- assemble FINAL_GAUNTLET_REPORT.md from template + phase16_*.md -----
if [ ! -f "$TEMPLATE" ]; then
  echo "WARN: template missing at $TEMPLATE; writing minimal skeleton" >&2
  cat > "$FINAL_REPORT" <<EOF
# FINAL_GAUNTLET_REPORT.md

(no template; emitting collated phase16 sections only)
EOF
else
  cp "$TEMPLATE" "$FINAL_REPORT"
fi

{
  printf '\n\n---\n\n# Collated phase16_*.md\n\n'
  for f in "$WORKSPACE"/phase16_*.md; do
    [ -f "$f" ] || continue
    printf '\n## %s\n\n' "$(basename "$f")"
    cat "$f"
  done
} >> "$FINAL_REPORT"

# ---- certification bundle -----------------------------------------------
copy_if_exists() {
  local src="$1" dst="$2"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    echo "  + $(basename "$dst")"
  fi
}

echo "Building certification bundle at $BUNDLE_DIR"
copy_if_exists "$WORKSPACE/reports/parity_score.json"           "$BUNDLE_DIR/confidence_gate.json"
copy_if_exists "$WORKSPACE/reports/ratchet_state.json"          "$BUNDLE_DIR/ratchet_state.json"
copy_if_exists "$WORKSPACE/reports/ratchet_decision.json"       "$BUNDLE_DIR/ratchet_decision.json"
copy_if_exists "$WORKSPACE/reports/feature_coverage.json"       "$BUNDLE_DIR/verification_contract.json"
copy_if_exists "$WORKSPACE/reports/convergence_tracker.json"    "$BUNDLE_DIR/convergence_tracker.json"
copy_if_exists "$WORKSPACE/reports/bead_graph_validation.json"  "$BUNDLE_DIR/bead_graph_validation.json"

# bench summary: pick the most recent comprehensive_bench scorecard
LATEST_BENCH="$(ls -1t "$WORKSPACE"/artifacts/bench/*/scorecard.json 2>/dev/null | head -1 || true)"
[ -n "$LATEST_BENCH" ] && cp "$LATEST_BENCH" "$BUNDLE_DIR/benchmark_summary.json" && echo "  + benchmark_summary.json"

# scorecards aggregate
{
  printf '{\n  "scorecards": [\n'
  first=1
  for f in "$WORKSPACE"/artifacts/**/scorecard.json; do
    [ -f "$f" ] || continue
    if [ "$first" -eq 0 ]; then printf ',\n'; fi
    printf '    "%s"' "$f"
    first=0
  done
  printf '\n  ]\n}\n'
} > "$BUNDLE_DIR/scorecards.json"
echo "  + scorecards.json"

# CI artifact manifest
{
  printf '{\n'
  printf '  "schema_version": "gauntlet.ci_artifact_manifest.v1",\n'
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "files": [\n'
  first=1
  while IFS= read -r f; do
    rel="${f#$BUNDLE_DIR/}"
    if [ "$first" -eq 0 ]; then printf ',\n'; fi
    printf '    "%s"' "$rel"
    first=0
  done < <(find "$BUNDLE_DIR" -type f -not -name 'ci_artifact_manifest.json' | sort)
  printf '\n  ]\n'
  printf '}\n'
} > "$BUNDLE_DIR/ci_artifact_manifest.json"
echo "  + ci_artifact_manifest.json"

# Release certificate. `certifying` is deliberately computed, not implied: a
# missing field here makes downstream CI think the bundle shape is valid when
# the actual release gate was never evaluated.
python3 - "$WORKSPACE" "$BUNDLE_DIR" "$INCREMENTAL" > "$BUNDLE_DIR/release_certificate.json" <<'PYTHON'
import json, os, sys, time

workspace, bundle_dir, incremental = sys.argv[1:4]
now = time.time()
max_age_hours = 24.0
failures = []

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as exc:
        failures.append({"path": path, "reason": f"not readable JSON: {exc}"})
        return None

def age_hours(path):
    try:
        return (now - os.path.getmtime(path)) / 3600.0
    except OSError:
        return None

required = {
    "confidence_gate": os.path.join(bundle_dir, "confidence_gate.json"),
    "verification_contract": os.path.join(bundle_dir, "verification_contract.json"),
    "ratchet_decision": os.path.join(bundle_dir, "ratchet_decision.json"),
    "convergence_tracker": os.path.join(bundle_dir, "convergence_tracker.json"),
    "benchmark_summary": os.path.join(bundle_dir, "benchmark_summary.json"),
    "scorecards": os.path.join(bundle_dir, "scorecards.json"),
}

evidence_age = {}
loaded = {}
for name, path in required.items():
    if not os.path.exists(path):
        failures.append({"evidence_class": name, "path": path, "reason": "missing"})
        continue
    age = age_hours(path)
    evidence_age[name] = round(age, 6) if age is not None else None
    if age is None or age > max_age_hours:
        failures.append({"evidence_class": name, "path": path, "reason": "stale_or_unstatable"})
    loaded[name] = load_json(path)

ratchet = loaded.get("ratchet_decision") or {}
if ratchet.get("decision") not in ("Allow", "Waiver"):
    failures.append({"evidence_class": "ratchet_decision", "reason": "decision_not_allow_or_waiver", "actual": ratchet.get("decision")})

convergence = loaded.get("convergence_tracker") or {}
if convergence.get("converged") is not True:
    failures.append({"evidence_class": "convergence_tracker", "reason": "not_converged"})

coverage = loaded.get("verification_contract") or {}
if not coverage.get("families"):
    failures.append({"evidence_class": "verification_contract", "reason": "no_feature_families"})
for row in coverage.get("families", []):
    if row.get("verdict") in ("none", "partial"):
        failures.append({"evidence_class": "verification_contract", "reason": "non_full_feature_family", "family": row.get("family"), "verdict": row.get("verdict")})

scorecards = loaded.get("scorecards") or {}
if not scorecards.get("scorecards"):
    failures.append({"evidence_class": "scorecards", "reason": "no_scorecards"})

blocked = os.path.join(workspace, "RELEASE_BLOCKED.md")
if os.path.exists(blocked):
    failures.append({"path": blocked, "reason": "release_blocked_file_present"})

certificate = {
    "schema_version": "strict-conformant-release.v1",
    "gauntlet_mode": "incremental-rebase" if incremental == "1" else "gauntlet-full",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
    "certifying": len(failures) == 0,
    "certification_failures": failures,
    "evidence_age_hours": evidence_age,
    "CERTIFICATION_MIN_VERIFICATION_PCT": 100.0,
    "CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT": 100.0,
    "CERTIFICATION_MAX_HIGH_SEVERITY_COUNTEREXAMPLES": 0,
    "CERTIFICATION_MAX_EVIDENCE_AGE_HOURS": int(max_age_hours),
    "bundle_dir": bundle_dir,
}
json.dump(certificate, sys.stdout, indent=2, sort_keys=True)
print()
PYTHON
echo "  + release_certificate.json"

# Critical-path summary: re-emit highest-severity findings from the markdown.
{
  printf '# Critical-Path Report\n\n'
  printf 'Generated %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for f in "$WORKSPACE"/phase16_*.md "$WORKSPACE"/CONFORMANCE_NEGATIVE_RESULTS.md \
           "$WORKSPACE"/PERF_NEGATIVE_RESULTS.md; do
    [ -f "$f" ] || continue
    grep -nE '(HIGH|CRITICAL|BLOCKER|SEVERITY.*High|SEVERITY.*Critical)' "$f" 2>/dev/null \
      | sed "s|^|- ${f#$WORKSPACE/}: |"
  done
} > "$BUNDLE_DIR/critical_path_report.md"
echo "  + critical_path_report.md"

echo "Done."
echo "  report:                   $FINAL_REPORT"
echo "  certification bundle:     $BUNDLE_DIR"
