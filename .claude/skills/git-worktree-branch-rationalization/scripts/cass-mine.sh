#!/usr/bin/env bash
# cass-mine.sh — Phase 0.5: mine prior agent sessions for context.
#
# Searches `cass` for prior runs of this skill on this project, prior
# branch/worktree rationalization incidents, and convention discoveries.
# Writes findings to <workspace>/cass_findings.md so Phase 5 triage and
# Phase 7 harmonization can reuse the institutional memory.
#
# Skips silently if cass isn't installed or unhealthy — it's a context aid,
# never a gate (per AGENTS.md "always use --robot or --json", never bare).
#
# Exit codes:
#   0  findings file written (even when cass is absent — a stub is emitted)
#   2  not a git work tree

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: cass-mine.sh <project-path>

Phase 0.5. Mines prior agent sessions via \`cass\` for context relevant to
the rationalization run. Writes <workspace>/cass_findings.md. Skips silently
if cass isn't installed or healthy.

Queries used:
  - cass search "<basename>" --robot --limit 50 --days 90
  - cass search "branch rationalization" --robot --limit 20
  - cass search "git worktree" --robot --limit 20
  - cass search "git branch -D" --robot --limit 20
  - cass search "harmonize branches" --robot --limit 10

Env:
  WORKSPACE              Workspace dir override.
  CASS_MINE_DAYS=N       Override the --days window for the basename query (default 90).

Exit codes:
  0  findings written
  2  not a git work tree
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
BASENAME="$(basename "$PROJECT_ABS")"
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
mkdir -p "$WORKSPACE_DIR"
OUT="$WORKSPACE_DIR/cass_findings.md"
DAYS="${CASS_MINE_DAYS:-90}"
if [[ ! "$DAYS" =~ ^[0-9]+$ ]]; then
  log "invalid CASS_MINE_DAYS=$DAYS; using 90"
  DAYS=90
fi

write_stub() {
  local reason="$1"
  {
    printf '# CASS findings — Phase 0.5\n\n'
    printf 'Project: %s\n' "$PROJECT_ABS"
    printf 'Mined: %s\n\n' "$(date -u +%FT%TZ)"
    printf 'Skipped: %s\n' "$reason"
    printf '\n_Inline fallback: this skill operates without prior-session context;\n'
    printf 'Phase 5 triage runs on the present-state inventory alone._\n'
  } > "$OUT"
}

if ! command -v cass >/dev/null 2>&1; then
  write_stub "cass is not installed"
  echo "cass not installed; wrote stub to $OUT"
  exit 0
fi

# `cass health --json` exits non-zero if the index is unbuilt or unreachable.
if ! cass health --json >/dev/null 2>&1; then
  write_stub "cass installed but health check failed"
  echo "cass not healthy; wrote stub to $OUT"
  exit 0
fi

# Resume-aware: if cass_findings.md exists with the same basename + day-window
# header, skip re-mining.
if [[ -f "$OUT" ]]; then
  prior_basename=$(grep -E '^Project:' "$OUT" 2>/dev/null | head -1 || true)
  prior_days=$(grep -E '^Mined-window:' "$OUT" 2>/dev/null | head -1 || true)
  if [[ "$prior_basename" == "Project: $PROJECT_ABS" \
     && "$prior_days"     == "Mined-window: $DAYS days" ]]; then
    log "cass_findings.md is current for $PROJECT_ABS / $DAYS days; skipping re-mine."
    echo "cass_findings.md current; wrote $OUT"
    exit 0
  fi
fi

mined_at=$(date -u +%FT%TZ)

# Five canonical queries — basename catches prior runs on THIS project; the
# other four catch general patterns the agent may have learned on other
# projects.
declare -a QUERY_TEXTS=(
  "$BASENAME"
  "branch rationalization"
  "git worktree"
  "git branch -D"
  "harmonize branches"
)
declare -a QUERY_DAYS=(
  "$DAYS"
  365
  365
  365
  365
)
declare -a QUERY_LIMITS=(
  50
  20
  20
  20
  10
)

{
  printf '# CASS findings — Phase 0.5\n\n'
  printf 'Project: %s\n' "$PROJECT_ABS"
  printf 'Mined: %s\n' "$mined_at"
  printf 'Mined-window: %s days\n' "$DAYS"
  printf '\n'
} > "$OUT"

findings_count=0
for idx in "${!QUERY_TEXTS[@]}"; do
  query="${QUERY_TEXTS[$idx]}"
  query_days="${QUERY_DAYS[$idx]}"
  query_limit="${QUERY_LIMITS[$idx]}"

  # Query, capture, slice — never trust unbounded output. Prefer --fields
  # minimal for compactness; the parent agent can re-run with full fields if
  # a finding looks promising.
  if results=$(cass search "$query" --robot --days "$query_days" --limit "$query_limit" --fields minimal 2>/dev/null); then
    if [[ -n "$results" ]] && [[ "$results" != "{}" ]] && [[ "$results" != "[]" ]]; then
      findings_count=$((findings_count + 1))
      # Single-quoted format strings are intentional (markdown literal backticks).
      # shellcheck disable=SC2016
      {
        printf '## Query: `%s`\n\n' "$query"
        printf -- '- flags: `--days %s --limit %s`\n\n' "$query_days" "$query_limit"
        printf '```json\n'
        # Cap at ~80 lines per query; the rest is browsable via cass directly.
        printf '%s\n' "$results" | sed -n '1,80p'
        printf '\n```\n\n'
      } >> "$OUT"
    fi
  fi
done

{
  printf '## Summary\n\n'
  if [[ "$findings_count" -eq 0 ]]; then
    printf 'No relevant prior sessions found across %s queries.\n' "${#QUERY_TEXTS[@]}"
    printf 'Skill-state: clean (no priors to factor in).\n'
  else
    printf '%s of %s queries returned matches. Review above for relevance and feed:\n' \
      "$findings_count" "${#QUERY_TEXTS[@]}"
    printf -- '- Phase 4 protection-list confirmation (any branches you protected before?)\n'
    printf -- '- Phase 5 triage rubric (verdict priors from past runs)\n'
    printf -- '- Phase 7 harmonization plan (variant-intent patterns the project has seen before)\n'
  fi
} >> "$OUT"

echo "wrote $OUT"
echo "Mined ${#QUERY_TEXTS[@]} queries; findings_count=$findings_count"
exit 0
