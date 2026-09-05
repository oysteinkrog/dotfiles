#!/usr/bin/env bash
# diff-passes.sh — Compare two audit passes and print a human-readable diff.
#
# Useful for:
#   - "What got better/worse since last week?"
#   - Pre-commit summary in CI tripwire mode (only alert on regression).
#   - Post-mortem: did our remediation actually move the needle?
#
# Usage:
#   diff-passes.sh <audit-dir> [--from <pass-id>] [--to <pass-id>]
#                              [--threshold 700]
#
# Defaults:
#   --from = the second-newest pass
#   --to   = the newest pass
#
# Output (markdown to stdout):
#   - Headline KPIs delta (false-closed count, score median, total beads)
#   - Top regressors (largest score drops)
#   - Top improvers (largest score rises)
#   - Newly false-closed beads (closed status, score newly < threshold)
#   - Newly recovered beads (closed status, score newly >= threshold)
#   - Beads that left the universe (deleted/tombstoned)
#   - Beads that entered the universe (newly created since prior pass)
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

AUDIT_DIR="${1:?audit dir required}"
shift || true

FROM_ID=""
TO_ID=""
# Defaults: hardcoded < audit-policy.yaml < CLI flags. The diff threshold
# determines which beads count as "false-closed" for the regression KPI.
THRESHOLD=700

# shellcheck source=.claude/skills/beads-compliance-and-completion-verification/scripts/_load-policy.sh
# shellcheck disable=SC1091
. "$(dirname "$0")/_load-policy.sh"
# diff-passes takes an audit-dir directly; pass it as the audit_dir arg.
load_policy "" "$AUDIT_DIR"
[ -n "${POLICY_THRESHOLD:-}" ] && THRESHOLD="$POLICY_THRESHOLD"

require_value() { if [ "$2" -lt 2 ]; then echo "ERROR: $1 requires a value" >&2; exit 3; fi; }
while [ $# -gt 0 ]; do
  case "$1" in
    --from)      require_value "$1" "$#"; FROM_ID="$2"; shift 2 ;;
    --to)        require_value "$1" "$#"; TO_ID="$2"; shift 2 ;;
    --threshold) require_value "$1" "$#"; THRESHOLD="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 3 ;;
  esac
done

[ -d "$AUDIT_DIR/passes" ] || { echo "ERROR: $AUDIT_DIR has no passes/ subdirectory" >&2; exit 2; }

mapfile -t ALL_PASSES < <(find "$AUDIT_DIR/passes" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort)
if [ "${#ALL_PASSES[@]}" -lt 2 ] && [ -z "$FROM_ID" ]; then
  echo "ERROR: need at least 2 passes to diff (found ${#ALL_PASSES[@]})" >&2
  exit 4
fi

# Use explicit length-indexing instead of negative indices ($ARRAY[-1]).
# Negative indices need bash 4.3+; macOS still ships bash 3.2 by default.
LAST_IDX=$((${#ALL_PASSES[@]} - 1))
PREV_IDX=$((${#ALL_PASSES[@]} - 2))
[ -z "$TO_ID"   ] && TO_ID="$(basename "${ALL_PASSES[$LAST_IDX]}")"
[ -z "$FROM_ID" ] && FROM_ID="$(basename "${ALL_PASSES[$PREV_IDX]}")"

FROM_DIR="$AUDIT_DIR/passes/$FROM_ID"
TO_DIR="$AUDIT_DIR/passes/$TO_ID"
[ -d "$FROM_DIR" ] || { echo "ERROR: $FROM_DIR not found" >&2; exit 5; }
[ -d "$TO_DIR"   ] || { echo "ERROR: $TO_DIR not found" >&2; exit 5; }

# Diffing a pass against itself is almost certainly a usage error: it'd
# produce an all-zeros report that looks fine but answers no question. Most
# common cause: only one pass exists and the user passed --from but not --to
# (so --to defaulted to the only-and-same pass). Refuse and explain.
if [ "$FROM_ID" = "$TO_ID" ]; then
  echo "ERROR: --from and --to resolve to the same pass ($FROM_ID)." >&2
  echo "       A diff against itself is always all zeros and tells you nothing." >&2
  if [ "${#ALL_PASSES[@]}" -lt 2 ]; then
    echo "       Only ${#ALL_PASSES[@]} pass exists in $AUDIT_DIR/passes/ — run another audit pass first." >&2
  else
    echo "       Pass --from <other-pass-id> and --to <pass-id> explicitly." >&2
  fi
  exit 6
fi

# Use a Python helper for the actual diff math — keeps the shell wrapper simple.
python3 - "$FROM_DIR" "$TO_DIR" "$THRESHOLD" <<'PY'
import json
import re
import sys
from pathlib import Path
from statistics import median

SCORE_RE = re.compile(r"\*\*Score:\s+(\d+)\s*/\s*1000\*\*", re.M)
STATUS_RE = re.compile(r"\*\*Status \(claimed\):\*\*\s+(\S+)", re.M)
TITLE_RE = re.compile(r"\*\*Title:\*\*\s+(.+)$", re.M)


def collect(pass_dir: Path) -> dict[str, dict]:
    out = {}
    for sc in (pass_dir / "beads").glob("*/scorecard.md"):
        txt = sc.read_text()
        sm, st, ti = SCORE_RE.search(txt), STATUS_RE.search(txt), TITLE_RE.search(txt)
        if not sm:
            continue
        out[sc.parent.name] = {
            "score": int(sm.group(1)),
            "status": st.group(1) if st else "unknown",
            "title": (ti.group(1).strip() if ti else "")[:80],
        }
    return out


from_dir = Path(sys.argv[1])
to_dir = Path(sys.argv[2])
threshold = int(sys.argv[3])
A = collect(from_dir)
B = collect(to_dir)

a_ids, b_ids = set(A), set(B)
common = a_ids & b_ids
gone = sorted(a_ids - b_ids)
new = sorted(b_ids - a_ids)

deltas = sorted(
    [(bid, B[bid]["score"] - A[bid]["score"], A[bid], B[bid]) for bid in common],
    key=lambda x: x[1],
)
regressors = [d for d in deltas if d[1] < 0][:15]
improvers = [d for d in deltas[::-1] if d[1] > 0][:15]

a_fc = {bid for bid in a_ids if A[bid]["status"] == "closed" and A[bid]["score"] < threshold}
b_fc = {bid for bid in b_ids if B[bid]["status"] == "closed" and B[bid]["score"] < threshold}
newly_fc = sorted(b_fc - a_fc)
# Python's `&` binds tighter than `-`, so the unparenthesized form
# `a_fc - b_fc & a_ids & b_ids` evaluates as `a_fc - (b_fc & a_ids & b_ids)`,
# which collapses to `a_fc - b_fc` (because b_fc ⊆ b_ids) and would include
# deleted beads — line ~199 then KeyErrors on B[bid] for a bead that's gone.
# We want: beads that were false-closed in A AND are NOT false-closed in B
# AND still exist in B.
newly_recovered = sorted((a_fc - b_fc) & b_ids)

a_scores = [A[bid]["score"] for bid in a_ids]
b_scores = [B[bid]["score"] for bid in b_ids]


def median_score(xs):
    return median(xs) if xs else 0


def fmt_number(value):
    return f"{value:g}"


def fmt_delta(value):
    return f"+{fmt_number(value)}" if value >= 0 else fmt_number(value)


def md_table(rows: list, headers: list, fmt: str = "%s") -> str:
    if not rows:
        return "| _(none)_ |\n"
    out = "| " + " | ".join(headers) + " |\n"
    out += "|" + "|".join(["---"] * len(headers)) + "|\n"
    for r in rows:
        out += "| " + " | ".join(str(c) for c in r) + " |\n"
    return out


print(f"# Audit Pass Diff — `{from_dir.name}` → `{to_dir.name}`")
print()
print(f"_threshold = {threshold}, generated by `diff-passes.sh`._\n")
print("## Headline KPIs")
print()
print("| Metric | From | To | Δ |")
print("|---|---:|---:|---:|")
print(f"| Total beads | {len(A)} | {len(B)} | {len(B)-len(A):+d} |")
a_median = median_score(a_scores)
b_median = median_score(b_scores)
print(f"| Score median | {fmt_number(a_median)} | {fmt_number(b_median)} | {fmt_delta(b_median-a_median)} |")
print(f"| False-closed count | {len(a_fc)} | {len(b_fc)} | {len(b_fc)-len(a_fc):+d} |")
print(f"| Closed beads | {sum(1 for v in A.values() if v['status']=='closed')} | "
      f"{sum(1 for v in B.values() if v['status']=='closed')} | "
      f"{sum(1 for v in B.values() if v['status']=='closed') - sum(1 for v in A.values() if v['status']=='closed'):+d} |")
print()
print("## Top Regressors (score drops)")
print()
print(md_table([[f"`{bid}`", a["score"], b["score"], f"{delta:+d}", a["status"], b["status"], a["title"]] for bid, delta, a, b in regressors],
               ["Bead", "Was", "Now", "Δ", "Was status", "Now status", "Title"]))
print()
print("## Top Improvers (score rises)")
print()
print(md_table([[f"`{bid}`", a["score"], b["score"], f"{delta:+d}", a["status"], b["status"], a["title"]] for bid, delta, a, b in improvers],
               ["Bead", "Was", "Now", "Δ", "Was status", "Now status", "Title"]))
print()
print("## Newly False-Closed (REGRESSION — closed status, dropped below threshold)")
print()
print(md_table([[f"`{bid}`", A.get(bid, {}).get("score", "—"), B[bid]["score"], B[bid]["title"]] for bid in newly_fc],
               ["Bead", "Was", "Now", "Title"]))
print()
print("## Newly Recovered (PROGRESS — closed status, climbed above threshold)")
print()
print(md_table([[f"`{bid}`", A[bid]["score"], B[bid]["score"], B[bid]["title"]] for bid in newly_recovered],
               ["Bead", "Was", "Now", "Title"]))
print()
print("## Universe changes")
print()
print(f"- Beads added since prior pass: **{len(new)}**")
if new[:10]:
    print("  - " + ", ".join(f"`{b}`" for b in new[:10]) + (" …" if len(new) > 10 else ""))
print(f"- Beads removed since prior pass: **{len(gone)}**")
if gone[:10]:
    print("  - " + ", ".join(f"`{b}`" for b in gone[:10]) + (" …" if len(gone) > 10 else ""))
print()
PY
