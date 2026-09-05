#!/usr/bin/env bash
# preflight.sh — Knock-out checks before running the audit.
#
# Usage:
#   preflight.sh <project-path>
#
# Runs cheap sanity checks that, if they fail, would cause the audit to waste
# time or produce garbage. Each check is one of:
#   ABORT — the audit cannot proceed (exit 2; bootstrap-audit.sh should bail)
#   WARN  — the audit can proceed but the user should know
#
# Exit codes:
#   0  all clear
#   2  one or more aborts (audit should not start)
#
# Full check catalog + rationale: references/PRE-AUDIT-CHECKS.md.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -uo pipefail   # NOT -e: each check should run even if a previous one warned

PROJECT="${1:?project path}"
WARNINGS=()
ABORT_REASONS=()

abort() { ABORT_REASONS+=("$1"); }
warn() { WARNINGS+=("$1"); }

# Check 1: project has a .beads/ directory
[ -d "$PROJECT/.beads" ] || abort "No .beads/ directory in $PROJECT"

# Check 2: br CLI installed
command -v br >/dev/null || abort "br CLI not installed (install beads_rust)"

# Check 3: there's a SQLite db in .beads/
DB="$(ls "$PROJECT/.beads"/*.db 2>/dev/null | head -1)"
[ -n "$DB" ] || abort "No .db file under $PROJECT/.beads/"

# Check 4: at least 5 closed beads (otherwise audit is pointless)
if [ -n "$DB" ]; then
  N_CLOSED=$(br --db "$DB" list --status=closed --limit 0 --json 2>/dev/null \
    | jq '.issues | length' 2>/dev/null || echo 0)
  [ "${N_CLOSED:-0}" -lt 5 ] && warn "Only $N_CLOSED closed beads (audit needs ≥ 5 to be meaningful)"
fi

# Check 5: br doctor exits clean
if [ -n "$DB" ]; then
  br --db "$DB" doctor --json >/dev/null 2>&1 || abort "br doctor failed — hand off to /fixing-beads-problems"
fi

# Check 6: no dependency cycles in the bead graph
if [ -n "$DB" ]; then
  CYCLES=$(br --db "$DB" dep cycles --json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
  [ "${CYCLES:-0}" -gt 0 ] && abort "$CYCLES dep cycle(s) — resolve first"
fi

# Check 7: project is a git repo (not shallow)
git -C "$PROJECT" rev-parse HEAD >/dev/null 2>&1 || abort "Not a git repo"
[ "$(git -C "$PROJECT" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ] && warn "Shallow git repo (Phase 3 git-blame may miss history)"

# Check 8: language-specific test runners present for primary stack
if [ -f "$PROJECT/Cargo.toml" ]; then
  command -v cargo >/dev/null || warn "cargo not installed (Rust project)"
fi
if [ -f "$PROJECT/package.json" ]; then
  command -v npm >/dev/null 2>&1 || command -v bun >/dev/null 2>&1 || command -v pnpm >/dev/null 2>&1 \
    || warn "no JS package manager (npm/pnpm/bun) found for package.json project"
fi
if [ -f "$PROJECT/pyproject.toml" ] || [ -f "$PROJECT/requirements.txt" ]; then
  command -v python3 >/dev/null || warn "python3 not installed (Python project)"
fi
if [ -f "$PROJECT/go.mod" ]; then
  command -v go >/dev/null || warn "go not installed (Go project)"
fi

# Check 9: working tree clean (uncommitted changes will be exercised by Phase 4)
DIRTY=$(git -C "$PROJECT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
[ "${DIRTY:-0}" -gt 0 ] && warn "Working tree has $DIRTY uncommitted change(s); Phase 4 will run against current state"

# Check 10: jq + ripgrep present (skill dependencies)
command -v jq >/dev/null || abort "jq not installed (skill dependency)"
command -v rg >/dev/null || warn "rg (ripgrep) not installed; theater-scan will be slow"

# Check 11: enough free disk for the audit dir (≥ 512 MB at parent)
AUDIT_DIR_PARENT="$(dirname "$(realpath "$PROJECT" 2>/dev/null || readlink -f "$PROJECT" 2>/dev/null || echo "$PROJECT")")"
AVAIL_KB=$(df -k "$AUDIT_DIR_PARENT" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
[ "${AVAIL_KB:-0}" -lt 524288 ] && warn "Less than 512MB free in $AUDIT_DIR_PARENT"

# Print results
{
  echo "Pre-flight check for: $PROJECT"
  echo
  if [ "${#ABORT_REASONS[@]}" -gt 0 ]; then
    echo "ABORT REASONS:"
    printf '  ✗ %s\n' "${ABORT_REASONS[@]}"
  fi
  if [ "${#WARNINGS[@]}" -gt 0 ]; then
    echo "WARNINGS:"
    printf '  ⚠ %s\n' "${WARNINGS[@]}"
  fi
  if [ "${#ABORT_REASONS[@]}" -eq 0 ] && [ "${#WARNINGS[@]}" -eq 0 ]; then
    echo "✓ All pre-flight checks passed"
  fi
}

[ "${#ABORT_REASONS[@]}" -gt 0 ] && exit 2
exit 0
