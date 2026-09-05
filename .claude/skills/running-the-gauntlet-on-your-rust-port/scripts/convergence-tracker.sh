#!/usr/bin/env bash
# convergence-tracker.sh — Compute round-over-round new-finding counts across
# the three ledgers + every per-bucket findings file. Exits non-zero until:
#   (rounds >= 10) AND
#   (last 2 rounds each <3 new genuine findings) AND
#   (every open hypothesis in *_HYPOTHESIS_LEDGER.md resolved)
#
# USAGE:
#   convergence-tracker.sh <workspace>
#                          [--round-glob 'round_*'] [--check]
#
# OUTPUT FILE: <workspace>/reports/convergence_tracker.json
#
# EXIT CODES:
#   0 — converged
#   1 — not yet converged
#   3 — usage error
#
# IDEMPOTENT. Designed as a CI gate.

set -euo pipefail

usage() { sed -n '2,14p' "$0"; exit "${1:-3}"; }

WORKSPACE=""
ROUND_GLOB="round_*"
MIN_ROUNDS=10
CLEAN_THRESHOLD=3
REQUIRED_CLEAN=2

while [ $# -gt 0 ]; do
  case "$1" in
    --round-glob) ROUND_GLOB="$2"; shift 2;;
    --check)       shift;;
    -h|--help)    usage 0;;
    *)
      if [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$WORKSPACE" ] || usage
mkdir -p "$WORKSPACE/reports"
OUT="$WORKSPACE/reports/convergence_tracker.json"

python3 - "$WORKSPACE" "$ROUND_GLOB" "$MIN_ROUNDS" "$CLEAN_THRESHOLD" "$REQUIRED_CLEAN" "$OUT" <<'PYTHON'
import glob, json, os, re, sys, time

workspace, round_glob, min_rounds, clean_threshold, required_clean, out_fp = sys.argv[1:7]
min_rounds = int(min_rounds); clean_threshold = int(clean_threshold); required_clean = int(required_clean)

rounds = sorted(glob.glob(os.path.join(workspace, round_glob)))
round_findings = []

def count_new_findings(round_dir):
    # Heuristic: every file matching findings_*.md or new_finding_*.md is one item.
    n = 0
    for ext in ("findings_*.md", "new_finding_*.md", "*_NEW_FINDINGS.md"):
        n += len(glob.glob(os.path.join(round_dir, ext)))
    # Also scan ledger diffs if present.
    for ledger in ("PERF_NEGATIVE_RESULTS.md", "CONFORMANCE_NEGATIVE_RESULTS.md",
                   "SURFACE_DEFERRALS.md"):
        p = os.path.join(round_dir, ledger)
        if os.path.exists(p):
            with open(p) as f:
                n += sum(1 for line in f if re.match(r'^\s*##\s+', line))
    return n

for r in rounds:
    round_findings.append({"round": os.path.basename(r), "new_findings": count_new_findings(r)})

# Open hypothesis check
open_hypothesis = 0
hyp_pattern = re.compile(r'(CONFIRMED_GAP|NO_EVIDENCE|NEEDS_REFINEMENT|NEW_HYPOTHESIS_SPAWNED|UNRESOLVED|OPEN)', re.I)
for hyp_file in glob.glob(os.path.join(workspace, "*_HYPOTHESIS_LEDGER.md")) \
              + glob.glob(os.path.join(workspace, "GAUNTLET_EXPERIMENT_DESIGNS.md")):
    with open(hyp_file) as f:
        for line in f:
            m = hyp_pattern.search(line)
            if m and m.group(1).upper() in ("NEEDS_REFINEMENT", "NEW_HYPOTHESIS_SPAWNED", "UNRESOLVED", "OPEN"):
                open_hypothesis += 1

n_rounds = len(rounds)
last_two = [r["new_findings"] for r in round_findings[-required_clean:]]
clean_last_two = (len(last_two) == required_clean
                  and all(x < clean_threshold for x in last_two))

converged = (n_rounds >= min_rounds) and clean_last_two and (open_hypothesis == 0)

report = {
    "schema_version": "gauntlet.convergence_tracker.v1",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "workspace": workspace,
    "round_count": n_rounds,
    "min_rounds_required": min_rounds,
    "clean_threshold": clean_threshold,
    "required_consecutive_clean": required_clean,
    "open_hypothesis_count": open_hypothesis,
    "round_findings": round_findings,
    "last_two_findings": last_two,
    "clean_last_two": clean_last_two,
    "converged": converged,
}
with open(out_fp, "w") as f:
    json.dump(report, f, indent=2, sort_keys=True)

print(f"rounds={n_rounds} last_two={last_two} open_hypothesis={open_hypothesis} converged={converged}")
sys.exit(0 if converged else 1)
PYTHON
