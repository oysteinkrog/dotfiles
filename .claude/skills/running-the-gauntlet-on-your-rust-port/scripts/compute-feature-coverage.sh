#!/usr/bin/env bash
# compute-feature-coverage.sh — Read parity_taxonomy.rs output +
# supported_surface_matrix.toml; emit per-family dashboard verdict
# (none|partial|full per category) + Markdown table.
#
# USAGE:
#   compute-feature-coverage.sh <workspace>
#                               [--matrix <path>]   (default: workspace search)
#                               [--taxonomy <path>] (optional JSON)
#
# OUTPUT FILES:
#   <workspace>/reports/feature_coverage.json
#   <workspace>/reports/feature_coverage.md
#   <workspace>/reports/parity_taxonomy.json
#
# EXIT CODES:
#   0 — coverage computed (regardless of verdict)
#   1 — matrix not found
#   3 — usage error
#
# IDEMPOTENT.

set -euo pipefail

usage() { sed -n '2,14p' "$0"; exit "${1:-3}"; }

WORKSPACE=""
MATRIX=""
TAXONOMY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --matrix)   MATRIX="$2"; shift 2;;
    --taxonomy) TAXONOMY="$2"; shift 2;;
    -h|--help)  usage 0;;
    *)
      if [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$WORKSPACE" ] || usage

if [ -z "$MATRIX" ]; then
  MATRIX="$(find "$WORKSPACE" -maxdepth 4 -name supported_surface_matrix.toml 2>/dev/null | head -1 || true)"
fi
if [ -z "$MATRIX" ] || [ ! -f "$MATRIX" ]; then
  echo "ERROR: supported_surface_matrix.toml not found" >&2; exit 1
fi

OUT_DIR="$WORKSPACE/reports"
mkdir -p "$OUT_DIR"
OUT_JSON="$OUT_DIR/feature_coverage.json"
OUT_MD="$OUT_DIR/feature_coverage.md"
OUT_TAXONOMY="$OUT_DIR/parity_taxonomy.json"

python3 - <<'PYTHON' "$MATRIX" "$OUT_JSON" "$OUT_MD" "$OUT_TAXONOMY" "${TAXONOMY:-/dev/null}"
import json, os, sys, time
matrix_path, out_json, out_md, out_taxonomy, taxonomy_path = sys.argv[1:6]

# Minimal TOML reader: depend on tomllib (py>=3.11) or fallback to tomli.
try:
    import tomllib
    loader = tomllib.load
    mode = "rb"
except Exception:
    import tomli as tomllib
    loader = tomllib.load
    mode = "rb"

with open(matrix_path, mode) as f:
    data = loader(f)

def status_key(raw):
    value = str(raw or "missing").strip().lower().replace("-", "_").replace(" ", "_")
    if value in ("present", "supported", "passing", "pass", "full"):
        return "present"
    if value in ("partial", "partially_supported"):
        return "partial"
    if value in ("missing", "absent"):
        return "missing"
    if value in ("excluded", "exclude"):
        return "excluded"
    if value in ("n/a", "na", "n_a", "not_applicable"):
        return "n_a"
    return value

STATUS_DISPLAY = {
    "present": "Present",
    "partial": "Partial",
    "missing": "Missing",
    "excluded": "Excluded",
    "n_a": "N/A",
}

def normalize_feature(feat, source):
    feature = dict(feat)
    category = feature.get("category") or feature.get("family") or "uncategorized"
    return {
        "id": str(feature.get("id", "")).strip(),
        "title": str(feature.get("title", "")).strip(),
        "category": str(category),
        "family": str(feature.get("family") or category),
        "weight": float(feature.get("weight", 1.0)),
        "status": status_key(feature.get("status")),
        "source": source,
    }

def read_taxonomy(path):
    if not path or path == "/dev/null" or not os.path.isfile(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        raw = json.load(f)
    if isinstance(raw, dict):
        raw_features = raw.get("features", [])
    elif isinstance(raw, list):
        raw_features = raw
    else:
        raise SystemExit(f"taxonomy JSON must be an object or list: {path}")
    return [normalize_feature(feat, "taxonomy") for feat in raw_features]

# Matrix schema: [[features]] entries with id, family/category, status, weight.
matrix_features = data.get("features", [])
if not matrix_features and "feature" in data:
    matrix_features = data["feature"]

taxonomy_features = read_taxonomy(taxonomy_path)
taxonomy_by_id = {feat["id"]: feat for feat in taxonomy_features if feat["id"]}
matrix_ids = set()
matrix_missing_from_taxonomy = []
features = []

for raw in matrix_features:
    feat = normalize_feature(raw, "matrix")
    fid = feat["id"]
    if fid:
        matrix_ids.add(fid)
        taxonomy_feat = taxonomy_by_id.get(fid)
        if taxonomy_feat:
            for key in ("title", "category", "family"):
                if not feat[key] and taxonomy_feat[key]:
                    feat[key] = taxonomy_feat[key]
        elif taxonomy_features:
            matrix_missing_from_taxonomy.append(fid)
    features.append(feat)

taxonomy_missing_from_matrix = []
for fid in sorted(set(taxonomy_by_id) - matrix_ids):
    feat = dict(taxonomy_by_id[fid])
    feat["status"] = "missing"
    feat["source"] = "taxonomy_missing_from_matrix"
    taxonomy_missing_from_matrix.append(fid)
    features.append(feat)

families = {}
for feat in features:
    fam = feat["family"] or feat["category"] or "uncategorized"
    status = feat["status"]
    weight = feat["weight"]
    entry = families.setdefault(fam, {"supported": 0.0, "partial": 0.0,
                                      "missing": 0.0, "excluded": 0.0,
                                      "n_a": 0.0, "items": 0, "total_weight": 0.0})
    if status == "present":
        entry["supported"] += weight
    elif status == "partial":
        entry["partial"] += weight
    elif status == "missing":
        entry["missing"] += weight
    elif status == "excluded":
        entry["excluded"] += weight
    elif status == "n_a":
        entry["n_a"] += weight
    entry["total_weight"] += weight
    entry["items"] += 1

def verdict(e):
    s = e["supported"]; tot = e["total_weight"]
    scorable = tot - e["n_a"]
    if scorable <= 0:
        return "n/a"
    if e["missing"] == 0 and e["partial"] == 0 and e["excluded"] == 0 and s > 0:
        return "full"
    if s > 0 or e["partial"] > 0:
        return "partial"
    return "none"

report = {
    "schema_version": "gauntlet.feature_coverage.v1",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "matrix_path": matrix_path,
    "taxonomy_path": taxonomy_path if taxonomy_features else None,
    "matrix_feature_count": len(matrix_features),
    "taxonomy_feature_count": len(taxonomy_features),
    "matrix_missing_from_taxonomy": sorted(matrix_missing_from_taxonomy),
    "taxonomy_missing_from_matrix": taxonomy_missing_from_matrix,
    "families": [],
}
for fam, e in sorted(families.items()):
    scorable_weight = max(e["total_weight"] - e["n_a"], 0.0)
    coverage_debt_weight = e["missing"] + e["excluded"]
    report["families"].append({
        "family": fam,
        "supported_weight": round(e["supported"], 6),
        "partial_weight":   round(e["partial"], 6),
        "missing_weight":   round(e["missing"], 6),
        "excluded_weight":  round(e["excluded"], 6),
        "n_a_weight":       round(e["n_a"], 6),
        "total_weight":     round(e["total_weight"], 6),
        "scorable_weight":  round(scorable_weight, 6),
        "coverage_debt_weight": round(coverage_debt_weight, 6),
        "coverage_debt_fraction": round(coverage_debt_weight / scorable_weight, 6) if scorable_weight > 0 else 0.0,
        "items":            e["items"],
        "verdict":          verdict(e),
    })

with open(out_json, "w") as f:
    json.dump(report, f, indent=2)

taxonomy_snapshot = {
    "schema_version": "gauntlet.parity_taxonomy_snapshot.v1",
    "generated_at": report["generated_at"],
    "matrix_path": matrix_path,
    "taxonomy_path": report["taxonomy_path"],
    "features": [
        {
            "id": feat["id"],
            "title": feat["title"],
            "category": feat["category"],
            "family": feat["family"],
            "weight": round(feat["weight"], 6),
            "status": STATUS_DISPLAY.get(feat["status"], feat["status"]),
            "source": feat["source"],
        }
        for feat in sorted(features, key=lambda item: item["id"])
    ],
}
with open(out_taxonomy, "w") as f:
    json.dump(taxonomy_snapshot, f, indent=2)

md_lines = ["# Feature Coverage Dashboard", "",
            f"_generated_at_: `{report['generated_at']}`",
            f"_matrix_: `{matrix_path}`", "",
            "| Family | Verdict | Supported | Partial | Missing | Excluded | N/A | Scorable | Debt | Total |",
            "|--------|---------|-----------|---------|---------|----------|-----|----------|------|-------|"]
for row in report["families"]:
    md_lines.append(
        f"| {row['family']} | {row['verdict']} | {row['supported_weight']} | "
        f"{row['partial_weight']} | {row['missing_weight']} | "
        f"{row['excluded_weight']} | {row['n_a_weight']} | {row['scorable_weight']} | "
        f"{row['coverage_debt_weight']} | {row['total_weight']} |"
    )
with open(out_md, "w") as f:
    f.write("\n".join(md_lines) + "\n")

print(f"Wrote {out_json}")
print(f"Wrote {out_md}")
print(f"Wrote {out_taxonomy}")
PYTHON
