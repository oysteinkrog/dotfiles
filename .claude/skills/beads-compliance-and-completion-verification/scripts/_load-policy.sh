#!/usr/bin/env bash
# _load-policy.sh — Source from other scripts to load audit-policy.yaml values.
#
# Resolves the policy file by checking, in order:
#   1. <audit-dir>/audit-policy.yaml          (preferred — per-pass canonical)
#   2. <project>/audit-policy.yaml            (project-local, before first audit)
#   3. <project>/.beads/audit-policy.yaml     (alongside the bead store)
#
# Sets the following shell variables ONLY if the YAML file exists AND the
# corresponding key is present (otherwise leaves them empty, so caller's
# hard-coded defaults survive):
#
#   POLICY_FILE                  — absolute path to the resolved YAML (or empty)
#   POLICY_THRESHOLD             — `threshold:` integer (e.g. 700)
#   POLICY_REMEDIATION_POLICY    — `remediation_policy:` string
#
# Other YAML sections (parallelism, weights_by_type, project_theater_patterns,
# release_gate, subagents, phase_4_environment, attribution) are read directly
# by the orchestrating subagent that owns them — see the audit-policy.yaml
# header for the per-section ownership table. Add new fields here only when
# a *shell* script needs them.
#
# Resolution precedence in callers:
#   hardcoded defaults  <  YAML  <  CLI flags
#
# So: source this BEFORE the arg-parsing while-loop, and only let CLI assign
# THRESHOLD/POLICY/MODE if the case-statement fires (CLI wins by virtue of
# running last).
#
# Usage from another script:
#   . "$(dirname "$0")/_load-policy.sh"
#   load_policy "$PROJECT" "${AUDIT_DIR:-}"
#   [ -n "${POLICY_THRESHOLD:-}" ] && THRESHOLD="$POLICY_THRESHOLD"
#   [ -n "${POLICY_REMEDIATION_POLICY:-}" ] && POLICY="$POLICY_REMEDIATION_POLICY"
#
# Safe to source under `set -euo pipefail`; emits no output, never errors.

# Use python3 for YAML parsing — it's already a dependency throughout the skill
# and avoids adding `yq` as a new requirement.
_load_policy_field() {
  # _load_policy_field <yaml-path> <python-expression-on-d>
  #
  # Only SCALAR values are emitted (int, float, bool, non-empty str). Lists,
  # dicts, None, and empty strings produce no output, so the caller's
  # `[ -n "${POLICY_X:-}" ]` test correctly falls back to the hardcoded default.
  # This protects downstream consumers like `[ "$POLICY_THRESHOLD" -gt 700 ]`
  # from receiving an un-comparable Python repr (e.g. `[800, 900]`) when the
  # YAML field has the wrong shape.
  python3 - "$1" "$2" <<'PY' 2>/dev/null || true
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1]).read()) or {}
except Exception:
    sys.exit(0)
expr = sys.argv[2]
# Eval the expression with `d` in scope. We block most builtins for
# defense-in-depth but keep `isinstance`, `dict`, `list`, `str`, `int`, `len`
# so caller expressions can do shape checks like
# `(d.get('foo') or {}).get('bar') if isinstance(d.get('foo'), dict) else ''`.
SAFE = {"isinstance": isinstance, "dict": dict, "list": list,
        "str": str, "int": int, "len": len, "bool": bool, "float": float}
try:
    val = eval(expr, {"__builtins__": SAFE}, {"d": d})
except Exception:
    sys.exit(0)
# Only emit scalars. Anything else → silent empty so caller defaults survive.
if val is None or isinstance(val, (list, dict, tuple, set)):
    sys.exit(0)
if isinstance(val, str) and val == "":
    sys.exit(0)
print(val)
PY
}

load_policy() {
  # load_policy <project-path> [audit-dir-path]
  local project="${1:-}"
  local audit_dir="${2:-}"
  POLICY_FILE=""
  POLICY_THRESHOLD=""
  POLICY_REMEDIATION_POLICY=""

  # Compute likely default audit-dir if caller didn't pass one.
  if [ -z "$audit_dir" ] && [ -n "$project" ]; then
    local project_abs
    project_abs="$(cd "$project" 2>/dev/null && pwd || echo "")"
    [ -n "$project_abs" ] && audit_dir="$project_abs/beads_compliance_audit"
  fi

  # Search in priority order.
  for cand in \
    "${audit_dir:+$audit_dir/audit-policy.yaml}" \
    "${project:+$project/audit-policy.yaml}" \
    "${project:+$project/.beads/audit-policy.yaml}"
  do
    [ -z "$cand" ] && continue
    if [ -f "$cand" ]; then
      POLICY_FILE="$cand"
      break
    fi
  done
  [ -z "$POLICY_FILE" ] && return 0

  # shellcheck disable=SC2034 # Consumed by sourcing callers (see header).
  POLICY_THRESHOLD="$(_load_policy_field "$POLICY_FILE" "d.get('threshold', '')")"
  # shellcheck disable=SC2034 # Consumed by sourcing callers (see header).
  POLICY_REMEDIATION_POLICY="$(_load_policy_field "$POLICY_FILE" "d.get('remediation_policy', '')")"
  return 0
}
