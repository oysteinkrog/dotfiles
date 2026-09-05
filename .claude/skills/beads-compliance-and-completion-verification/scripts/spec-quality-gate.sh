#!/usr/bin/env bash
# spec-quality-gate.sh — Pre-claim hook: score a NEW (open/draft) bead's spec
# auditability and gate work-claim on the verdict.
#
# Pairs with subagents/spec-quality-reviewer.md. The script handles the
# deterministic baseline (heuristics that don't need an LLM); for full review,
# the orchestrator should follow up by invoking the subagent.
#
# Usage:
#   spec-quality-gate.sh <project-path> <bead-id> [--threshold 700] [--write]
#                                                  [--policy block|advise]
#
# Exit codes:
#   0  — spec ≥ threshold (claim allowed)
#   1  — spec < threshold (claim blocked under --policy=block, advisory under
#         --policy=advise [exit still 0 in advise mode])
#   2  — usage error
#   3  — bead not found
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path required}"
BEAD_ID="${2:?bead-id required}"
shift 2

# Defaults: hardcoded < audit-policy.yaml < CLI flags. POLICY default is
# `advise` (don't break velocity); use `--policy block` (or set it in YAML)
# to make the gate hard. Note: spec-quality-gate's THRESHOLD applies to the
# spec-quality score (separate from the audit threshold), but we let the
# top-level YAML threshold serve as a sane default — projects that want
# stricter spec-quality should override via CLI or YAML override section.
THRESHOLD=700
POLICY="advise"
WRITE_OUT=false

# shellcheck source=.claude/skills/beads-compliance-and-completion-verification/scripts/_load-policy.sh
. "$(dirname "$0")/_load-policy.sh"
load_policy "$PROJECT"
[ -n "${POLICY_THRESHOLD:-}" ] && THRESHOLD="$POLICY_THRESHOLD"

require_value() { if [ "$2" -lt 2 ]; then echo "ERROR: $1 requires a value" >&2; exit 2; fi; }
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) require_value "$1" "$#"; THRESHOLD="$2"; shift 2 ;;
    --policy)    require_value "$1" "$#"; POLICY="$2"; shift 2 ;;
    --write)     WRITE_OUT=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -d "$PROJECT/.beads" ] || { echo "ERROR: $PROJECT has no .beads/ directory" >&2; exit 3; }
DB="$(find "$PROJECT/.beads" -maxdepth 1 -type f -name '*.db' -print | head -1)"
[ -n "$DB" ] || { echo "ERROR: no .beads/*.db found in $PROJECT" >&2; exit 3; }

SHOW="$(br --db "$DB" show "$BEAD_ID" --json 2>/dev/null)" || {
  echo "ERROR: bead '$BEAD_ID' not found in $DB" >&2
  exit 3
}

# Heuristic spec-quality scoring. The subagent does the deeper review; this
# script provides the baseline so the gate works without an LLM in the loop.
#
# We use a temp file for the python source (heredoc) AND pass SHOW via stdin
# so python can read both. Mixing heredoc-on-stdin with extra-input-on-stdin
# is what mangled an earlier version.
#
# `mktemp` (no flags) is portable across GNU/BSD; `--suffix` is GNU-only and
# breaks on macOS. Python doesn't care about the .py extension. Keep the
# generated source file: repo policy forbids file deletion, and retaining it
# helps diagnose python parse/runtime failures.
PY_TMP="$(mktemp)"
cat > "$PY_TMP" <<'PY'
import json
import re
import sys
from pathlib import Path

bead_id = sys.argv[1]
threshold = int(sys.argv[2])
policy = sys.argv[3]
write_out = sys.argv[4] == "true"
project = Path(sys.argv[5])

raw = sys.stdin.read()
show = json.loads(raw)

desc = show.get("description") or ""
design = show.get("design") or ""
acs = show.get("acceptance_criteria") or ""
notes = show.get("notes") or ""
issue_type = show.get("issue_type") or "task"
labels = show.get("labels") or []
title = show.get("title") or "(untitled)"
body = "\n".join([desc, design, acs, notes])

if not body.strip():
    print(f"ERROR: bead {bead_id} has no body — cannot score spec quality", file=sys.stderr)
    sys.exit(3)

scores = {}
notes_per_dim: dict[str, list[str]] = {}

# Dim 1 (300): ACs are concrete.
# ACs may live in the dedicated `acceptance_criteria` field OR be embedded in
# the description under an "## Acceptance criteria" / "## ACs" / "Done when"
# heading. Pull from both so we don't penalize the common-but-valid pattern.
ac_section_re = re.compile(
    r"^#+\s*(?:Acceptance\s*Criteria|ACs?|Done\s*when)\b.*?(?=^#+\s|\Z)",
    re.I | re.M | re.S,
)
ac_text = acs
for section in ac_section_re.findall(body):
    ac_text += "\n" + section
ac_lines = [ln for ln in ac_text.splitlines() if re.match(r"^\s*[-*+]\s+|^\s*\[ \]|^\s*\d+\.", ln)]
n_acs = len(ac_lines)
vague_words = re.findall(r"\b(robust|performant|secure|reliable|fast|scalable|smooth|nice|great|works well|properly)\b", ac_text, re.I)
score_d1 = 0
if n_acs == 0:
    notes_per_dim.setdefault("ACs concrete", []).append("no acceptance criteria parsed (need bullets / checkboxes in `acceptance_criteria` field OR under '## Acceptance criteria' / '## ACs' / 'Done when' heading)")
else:
    score_d1 = min(300, n_acs * 60) - len(vague_words) * 30
    score_d1 = max(0, score_d1)
    if vague_words:
        notes_per_dim.setdefault("ACs concrete", []).append(f"{len(vague_words)} vague word(s) detected: {set(vague_words)}")
scores["ACs concrete"] = (score_d1, 300)

# Dim 2 (200): test types named.
test_kinds = ["unit", "integration", "e2e", "end-to-end", "fuzz", "property", "metamorphic", "golden", "snapshot", "conformance", "smoke", "regression", "load", "soak", "chaos"]
named = [k for k in test_kinds if re.search(rf"\b{re.escape(k)}\b", body, re.I)]
score_d2 = min(200, len(named) * 50)
if not named:
    notes_per_dim.setdefault("Test types named", []).append("no test type words detected; specify which test types are required")
else:
    notes_per_dim.setdefault("Test types named", []).append(f"named: {', '.join(named)}")
scores["Test types named"] = (score_d2, 200)

# Dim 3 (100): numeric budgets where the bead is perf-flavored.
perf_signal = re.search(r"\b(p50|p95|p99|latency|throughput|qps|rps|memory|allocations?|cold[- ]start)\b", body, re.I)
budget_match = re.findall(r"[<≤>≥]\s*\d+(?:\.\d+)?\s*(?:ms|us|ns|s|MB|KB|GB|req/s|qps|rps|%)", body, re.I)
if perf_signal:
    score_d3 = 100 if budget_match else 0
    if not budget_match:
        notes_per_dim.setdefault("Numeric budgets", []).append("perf-flavored bead but no numeric budget found")
    else:
        notes_per_dim.setdefault("Numeric budgets", []).append(f"budgets present: {budget_match[:3]}")
else:
    score_d3 = 100  # not perf-flavored, full credit
    notes_per_dim.setdefault("Numeric budgets", []).append("not perf-flavored; rule N/A")
scores["Numeric budgets"] = (score_d3, 100)

# Dim 4 (100): rollback plan.
needs_rollback = any(k in (issue_type or "").lower() for k in ("migration", "infra")) or any(
    re.search(rf"\b{w}\b", body, re.I) for w in ("migration", "schema", "ddl", "backfill", "deploy", "rollout")
)
rb_match = re.search(r"(rollback|revert|undo|fallback|recovery|disaster|kill[- ]switch|feature[- ]flag.*off)", body, re.I)
if needs_rollback:
    score_d4 = 100 if rb_match else 0
    if not rb_match:
        notes_per_dim.setdefault("Rollback plan", []).append("migration/deploy bead with no rollback / recovery plan stated")
else:
    score_d4 = 100
    notes_per_dim.setdefault("Rollback plan", []).append("rollback rule N/A for this bead-type")
scores["Rollback plan"] = (score_d4, 100)

# Dim 5 (100): dependencies explicit.
implicit_dep_pattern = re.compile(r"\b(uses|depends on|requires|builds on)\s+(?:the\s+)?(?:new\s+)?(?:bead\s+)?[`\"]?[a-z][\w.-]+", re.I)
implicit = implicit_dep_pattern.findall(body)
score_d5 = 80 if not implicit else max(0, 80 - len(implicit) * 20)
if implicit:
    notes_per_dim.setdefault("Dependencies explicit", []).append(f"{len(implicit)} implicit dep phrase(s); ensure `br dep add` records them")
else:
    notes_per_dim.setdefault("Dependencies explicit", []).append("no implicit-dep phrases detected (heuristic; verify with `br dep list`)")
scores["Dependencies explicit"] = (score_d5, 100)

# Dim 6 (200): "done" recognizable.
recognizable = sum([
    1 if re.search(r"\bDone when\b|\bComplete when\b", body, re.I) else 0,
    1 if re.search(r"file:line|`[^`]+\.\w+:\d+`", body) else 0,
    1 if re.search(r"\bcommit\b|\bSHA\b|\bbranch\b", body, re.I) else 0,
    1 if n_acs >= 3 else 0,
])
score_d6 = recognizable * 50
notes_per_dim.setdefault("Done recognizable", []).append(f"{recognizable}/4 'done'-clarity heuristics matched")
scores["Done recognizable"] = (score_d6, 200)

total = sum(s for s, _ in scores.values())

verdict = (
    "EXCELLENT" if total >= 900 else
    "GOOD ENOUGH" if total >= 700 else
    "REWRITE BEFORE CLAIM" if total >= 500 else
    "REJECTED"
)

# Output report.
lines = [
    f"# Spec Quality Report — `{bead_id}` ({issue_type})",
    "",
    f"**Title:** {title}",
    f"**Score:** {total} / 1000",
    f"**Threshold:** {threshold}",
    f"**Verdict:** {verdict}",
    f"**Labels:** {', '.join(labels) if labels else '(none)'}",
    "",
    "| Dimension | Score | Max | Notes |",
    "|-----------|------:|----:|-------|",
]
for dim, (s, m) in scores.items():
    note = "; ".join(notes_per_dim.get(dim, []))[:200]
    lines.append(f"| {dim} | {s} | {m} | {note} |")
lines.append("")

if total < threshold:
    lines.append("## Strongest revisions to demand (heuristic — full review by `subagents/spec-quality-reviewer.md`)")
    lines.append("")
    if "no acceptance criteria parsed" in str(notes_per_dim.get("ACs concrete", [])):
        lines.append("- Add bulleted / checkboxed acceptance criteria; each AC should be independently testable.")
    if any("vague word" in s for s in notes_per_dim.get("ACs concrete", [])):
        lines.append("- Replace vague qualifiers (robust / performant / secure) with measurable assertions.")
    if not named:
        lines.append("- Name the required test types explicitly (unit / e2e / property / fuzz / golden / metamorphic / conformance).")
    if perf_signal and not budget_match:
        lines.append("- Add a numeric budget (e.g. `p95 < 100ms`, `< 5 MB allocation`). Perf beads without budgets are non-auditable.")
    if needs_rollback and not rb_match:
        lines.append("- Add a rollback / recovery plan section. Migration / deploy beads without one are not closeable.")
    if implicit:
        lines.append("- Promote implicit deps to explicit `br dep add` entries.")

report = "\n".join(lines)
print(report)

if write_out:
    # The audit dir is a SUBDIRECTORY of the project (`<project>/beads_compliance_audit/`).
    # bootstrap-audit.sh adds it to the project's .gitignore so spec-gate
    # reports don't accidentally get committed by `git add -A`.
    project_abs = project.resolve()
    audit_dir = project_abs / "beads_compliance_audit"
    out_dir = audit_dir / "spec_gate"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{bead_id}.md").write_text(report + "\n")
    print(f"\nWrote {out_dir / (bead_id + '.md')}", file=sys.stderr)

# Exit policy.
if total < threshold and policy == "block":
    print(f"\nGATE: BLOCKED ({total} < {threshold}; --policy=block)", file=sys.stderr)
    sys.exit(1)
if total < threshold:
    print(f"\nGATE: ADVISE ({total} < {threshold}; --policy=advise; not blocking)", file=sys.stderr)
    sys.exit(0)
print(f"\nGATE: PASSED ({total} ≥ {threshold})", file=sys.stderr)
sys.exit(0)
PY
python3 "$PY_TMP" "$BEAD_ID" "$THRESHOLD" "$POLICY" "$WRITE_OUT" "$PROJECT" <<<"$SHOW"
