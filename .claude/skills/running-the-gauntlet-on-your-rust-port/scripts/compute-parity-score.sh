#!/usr/bin/env bash
# compute-parity-score.sh — Read scorecards; apply category weights from
# parity_score_contract.toml; run Beta-posterior + conformal-band math;
# emit lower-bound + `truncate_score`'d output (6 decimal places).
#
# Pure-determinism: same inputs → byte-identical output across platforms.
#
# USAGE:
#   compute-parity-score.sh <workspace>
#                           [--contract <path>]
#                           [--scorecards <glob>]
#                           [--confidence 0.95]
#                           [--category <name>] [--emit-intermediates <path>]
#
# OUTPUT FILES:
#   <workspace>/reports/parity_score.json
#
# EXIT CODES:
#   0 — score computed
#   1 — inputs missing
#   3 — usage error
#
# IDEMPOTENT.

set -euo pipefail

usage() { sed -n '2,16p' "$0"; exit "${1:-3}"; }

WORKSPACE=""
CONTRACT=""
SCORECARDS=""
CONFIDENCE="0.95"
CATEGORY=""
EMIT_INTERMEDIATES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --contract)   CONTRACT="$2"; shift 2;;
    --scorecards) SCORECARDS="$2"; shift 2;;
    --confidence) CONFIDENCE="$2"; shift 2;;
    --category)   CATEGORY="$2"; shift 2;;
    --emit-intermediates) EMIT_INTERMEDIATES="$2"; shift 2;;
    -h|--help)    usage 0;;
    *)
      if [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$WORKSPACE" ] || usage

if [ -z "$CONTRACT" ]; then
  CONTRACT="$(find "$WORKSPACE" -maxdepth 4 -name parity_score_contract.toml 2>/dev/null | head -1 || true)"
fi
[ -f "$CONTRACT" ] || { echo "ERROR: parity_score_contract.toml not found" >&2; exit 1; }

OUT_DIR="$WORKSPACE/reports"
mkdir -p "$OUT_DIR"
OUT_JSON="$OUT_DIR/parity_score.json"

python3 - "$CONTRACT" "$WORKSPACE" "$OUT_JSON" "$CONFIDENCE" "${SCORECARDS:-}" "${CATEGORY:-}" "${EMIT_INTERMEDIATES:-}" <<'PYTHON'
import json, sys, math, os, glob, time

contract_path, workspace, out_json, confidence_str, scorecards_glob, requested_category, emit_intermediates = sys.argv[1:8]
confidence = float(confidence_str)

try:
    import tomllib
    with open(contract_path, "rb") as f: contract = tomllib.load(f)
except Exception:
    import tomli
    with open(contract_path, "rb") as f: contract = tomli.load(f)

categories = contract.get("categories", {})
weight_sum = sum(c.get("weight", 0.0) for c in categories.values())
if abs(weight_sum - 1.0) > 1e-6:
    print(f"ERROR: category weights sum to {weight_sum}, expected 1.0", file=sys.stderr)
    sys.exit(1)

# Collect scorecards
if not scorecards_glob:
    scorecards_glob = os.path.join(workspace, "artifacts", "**", "scorecard.json")
files = sorted(glob.glob(scorecards_glob, recursive=True))

# Per-category accumulators: successes (alpha contribution) + failures (beta).
ALPHA_PRIOR = 1.0
BETA_PRIOR  = 1.0

per_cat = {name: {"alpha": ALPHA_PRIOR, "beta": BETA_PRIOR,
                  "weight": cfg.get("weight", 0.0),
                  "observations": 0.0}
           for name, cfg in categories.items()}
source_files = []
source_category_scores = {}

def record_source_score(source, category, passes, failures):
    total = passes + failures
    if total <= 0:
        return
    source_category_scores.setdefault(source, {})[category] = passes / total

for fp in files:
    try:
        with open(fp) as fh: sc = json.load(fh)
    except Exception:
        continue
    used = False
    for cat_name, stats in sc.get("per_category", {}).items():
        bucket = per_cat.get(cat_name)
        if bucket is None: continue
        passes = float(stats.get("passes", 0.0))
        failures = float(stats.get("failures", 0.0))
        bucket["alpha"] += passes
        bucket["beta"]  += failures
        bucket["observations"] += passes + failures
        record_source_score(fp, cat_name, passes, failures)
        used = True
    if used:
        source_files.append(fp)

# Feature coverage dashboard is a first-class score source. Its status weights
# already encode excluded-as-debt and partial-as-visible-not-full.
feature_coverage_fp = os.path.join(workspace, "reports", "feature_coverage.json")
if os.path.exists(feature_coverage_fp):
    try:
        with open(feature_coverage_fp) as fh:
            coverage = json.load(fh)
        used = False
        for row in coverage.get("families", []):
            cat_name = row.get("family")
            bucket = per_cat.get(cat_name)
            if bucket is None:
                continue
            supported = float(row.get("supported_weight", 0.0))
            partial = float(row.get("partial_weight", 0.0))
            missing = float(row.get("missing_weight", 0.0))
            excluded = float(row.get("excluded_weight", 0.0))
            passes = supported + 0.5 * partial
            failures = missing + excluded + 0.5 * partial
            bucket["alpha"] += passes
            bucket["beta"] += failures
            bucket["observations"] += passes + failures
            record_source_score(feature_coverage_fp, cat_name, passes, failures)
            used = True
        if used:
            source_files.append(feature_coverage_fp)
    except Exception as exc:
        print(f"WARN: could not read feature coverage {feature_coverage_fp}: {exc}", file=sys.stderr)

total_observations = sum(b["observations"] for b in per_cat.values())
if total_observations <= 0:
    print("ERROR: no score observations found in scorecards or feature_coverage.json", file=sys.stderr)
    sys.exit(1)

# --- Beta posterior helpers (regularized incomplete beta via bisection) ----
def beta_pdf_log(x, a, b):
    if x <= 0 or x >= 1: return float("-inf")
    return (a-1)*math.log(x) + (b-1)*math.log(1-x) \
         - (math.lgamma(a)+math.lgamma(b)-math.lgamma(a+b))

def beta_cdf(x, a, b, steps=4096):
    # trapezoidal rule on log-pdf-exp; deterministic across platforms
    if x <= 0: return 0.0
    if x >= 1: return 1.0
    h = x / steps
    s = 0.0
    prev = math.exp(beta_pdf_log(1e-12, a, b))
    for i in range(1, steps+1):
        xi = i*h
        cur = math.exp(beta_pdf_log(xi if xi < 1.0 else 1.0-1e-12, a, b))
        s += (prev + cur) * h * 0.5
        prev = cur
    return min(max(s, 0.0), 1.0)

def beta_quantile(p, a, b, tol=1e-8):
    lo, hi = 0.0, 1.0
    for _ in range(64):
        mid = (lo+hi)/2
        if beta_cdf(mid, a, b) < p: lo = mid
        else: hi = mid
        if hi - lo < tol: break
    return (lo+hi)/2

def truncate_score(x, decimals=6):
    factor = 10**decimals
    return math.floor(x*factor) / factor

# --- Compute per-category mean + lower bound, then global ----------------
tail = (1.0 - confidence) / 2.0
out = {
    "schema_version": "gauntlet.parity_score.v1",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "contract": contract_path,
    "confidence": confidence,
    "observation_count": truncate_score(total_observations),
    "source_files": source_files,
    "categories": {},
}

global_mean = 0.0
global_lower = 0.0
category_means = {}
for name, b in per_cat.items():
    a, beta = b["alpha"], b["beta"]
    mean = a / (a + beta)
    lower = beta_quantile(tail, a, beta)
    upper = beta_quantile(1.0 - tail, a, beta)
    weight = b["weight"]
    out["categories"][name] = {
        "alpha": truncate_score(a),
        "beta":  truncate_score(beta),
        "observations": truncate_score(b["observations"]),
        "weight": weight,
        "mean":  truncate_score(mean),
        "lower": truncate_score(lower),
        "upper": truncate_score(upper),
    }
    category_means[name] = mean
    global_mean  += weight * mean
    global_lower += weight * lower

out["global_mean"]  = truncate_score(global_mean)
bayesian_global_lower = global_lower

def conformal_quantile(values, confidence_level):
    if not values:
        return None
    ordered = sorted(values)
    rank = math.ceil((len(ordered) + 1) * confidence_level)
    idx = min(max(rank - 1, 0), len(ordered) - 1)
    return ordered[idx]

calibration_rows = []
for source, scores in sorted(source_category_scores.items()):
    denom = sum(per_cat[name]["weight"] for name in scores if per_cat.get(name, {}).get("weight", 0.0) > 0)
    if denom <= 0:
        continue
    observed = sum(per_cat[name]["weight"] * score for name, score in scores.items()) / denom
    predicted = sum(per_cat[name]["weight"] * category_means[name] for name in scores) / denom
    calibration_rows.append({
        "source": source,
        "category_count": len(scores),
        "observed": truncate_score(observed),
        "predicted": truncate_score(predicted),
        "residual": abs(observed - predicted),
    })

if len(calibration_rows) >= 2:
    q = conformal_quantile([row["residual"] for row in calibration_rows], confidence)
    conformal_lower_raw = max(0.0, global_mean - q)
    conformal_status = "calibrated"
else:
    q = None
    conformal_lower_raw = bayesian_global_lower
    conformal_status = "insufficient_calibration"

out["bayesian_global_lower"] = truncate_score(bayesian_global_lower)
out["global_lower"] = truncate_score(min(bayesian_global_lower, conformal_lower_raw))
out["conformal_band"] = {
    "status": conformal_status,
    "method": "finite-sample residual quantile over scorecard/category observations",
    "confidence": confidence,
    "calibration_count": len(calibration_rows),
    "residual_quantile": truncate_score(q) if q is not None else None,
    "lower": truncate_score(conformal_lower_raw),
    "rows": [
        {
            "source": row["source"],
            "category_count": row["category_count"],
            "observed": row["observed"],
            "predicted": row["predicted"],
            "residual": truncate_score(row["residual"]),
        }
        for row in calibration_rows
    ],
}

with open(out_json, "w") as f:
    json.dump(out, f, indent=2, sort_keys=True)

if emit_intermediates:
    intermediate_dir = os.path.dirname(emit_intermediates)
    if intermediate_dir:
        os.makedirs(intermediate_dir, exist_ok=True)
    payload = {
        "schema_version": "gauntlet.parity_score_intermediates.v1",
        "generated_at": out["generated_at"],
        "requested_category": requested_category or None,
        "category": out["categories"].get(requested_category) if requested_category else None,
        "categories": out["categories"],
        "global_mean": out["global_mean"],
        "global_lower": out["global_lower"],
        "bayesian_global_lower": out["bayesian_global_lower"],
        "conformal_band": out["conformal_band"],
        "source_files": source_files,
    }
    with open(emit_intermediates, "w") as f:
        json.dump(payload, f, indent=2, sort_keys=True)

print(f"Wrote {out_json}")
if emit_intermediates:
    print(f"Wrote {emit_intermediates}")
print(f"global_mean={out['global_mean']} global_lower={out['global_lower']}")
PYTHON
