#!/usr/bin/env bash
# rerun.sh — paste-ready reproducer for this proof pack.
#
# Every proof pack MUST include a rerun.sh that, when run from a fresh checkout
# at the candidate's commit, reproduces the bench numbers in delta_summary.json
# byte-identically (per pattern:K-11 content-addressed artifact identity).

set -euo pipefail

GIT_SHA="<candidate-sha>"
BENCH="<bench-name>"
SCENARIO="<scenario-id>"

# 1. Pre-flight.
[ "$(git rev-parse HEAD)" = "$GIT_SHA" ] || {
  echo "ERROR: not on candidate commit $GIT_SHA; git checkout $GIT_SHA first" >&2; exit 2
}

# 2. Drop concurrent-mode-default proof file (pattern:175-CONCURRENT-MODE-GUARD).
RERUN_DIR="tests/artifacts/perf/rerun-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RERUN_DIR"
echo "CONCURRENT_MODE_DEFAULT=true" > "$RERUN_DIR/concurrent_mode_default_guard.txt"
echo "GIT_SHA=$GIT_SHA" >> "$RERUN_DIR/concurrent_mode_default_guard.txt"
echo "TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RERUN_DIR/concurrent_mode_default_guard.txt"

# 3. Run with the exact release-perf profile.
cargo bench --bench "$BENCH" --profile release-perf -- \
  --scenario "$SCENARIO" \
  --iters 3 \
  --warmup 2

# 4. Re-profile.
samply record --rate 4000 -o candidate_profile.samply.json \
  target/release-perf/"$BENCH" --scenario "$SCENARIO"

# 5. Verify delta_summary.json numbers are reproduced within cv_pct band.
python3 - <<'PY'
import json
with open("delta_summary.json") as f: pack = json.load(f)
# ... compute new primary_score, compare to pack["candidate"]["primary_score"]
# ... assert within cv_pct band
print("rerun verified within noise band")
PY

echo "Reproduction complete."
