#!/usr/bin/env bash
# github-pr-awareness.sh — Phase 1 / 4 / 5: GitHub-side state for triage priors.
#
# When `gh` is installed AND the repo has a GitHub remote, query open PRs and
# branch-protection rules and write a single JSON document so downstream phases
# can:
#   - mark branches with open PRs as `pr-active` (a strong protected-preserve
#     signal — never auto-classify as garbage; surface for explicit review)
#   - mark branches with branch-protection-rule coverage accordingly
#
# Output: <workspace>/github_state.json
#
# This is purely informational: missing `gh` or an unauthenticated session
# never blocks the run — the skill always falls back to local-only triage.
#
# Per AGENTS.md Axiom 15 / Anti-pattern, this script never:
#   - runs `git push --delete`
#   - runs `git push --force`
#   - mutates remote refs in any way
# It is read-only against GitHub's API.
#
# Exit codes:
#   0  state file written (or stub written when gh is unavailable)
#   2  not a git work tree

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: github-pr-awareness.sh <project-path>

Phase 1 / 4 / 5. Read-only GitHub API queries via \`gh\`:
  - open PRs (number, headRefName, baseRefName, author, updatedAt)
  - per-branch protection rules (best-effort; many repos return 404)

Cross-references with branches.tsv to mark pr-active / protected-by-rule.
Writes <workspace>/github_state.json.

Skips silently if:
  - gh is not installed
  - gh is unauthenticated (\`gh auth status\` fails)
  - the repo has no GitHub remote

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  state file written (gh available + queries ran, OR stub on skip)
  2  not a git work tree
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
mkdir -p "$WORKSPACE_DIR"
OUT="$WORKSPACE_DIR/github_state.json"

write_stub() {
  local reason="$1"
  {
    printf '{\n'
    printf '  "checked_at": '; json_string "$(date -u +%FT%TZ)"; printf ',\n'
    printf '  "project": '; json_string "$PROJECT_ABS"; printf ',\n'
    printf '  "available": false,\n'
    printf '  "reason": '; json_string "$reason"; printf ',\n'
    printf '  "open_prs": [],\n'
    printf '  "pr_active_branches": [],\n'
    printf '  "protected_by_rule_branches": []\n'
    printf '}\n'
  } > "$OUT"
}

if ! command -v gh >/dev/null 2>&1; then
  write_stub "gh not installed"
  echo "gh not installed; wrote stub to $OUT"
  exit 0
fi

# Detect the GitHub remote. gh's repo discovery uses `git config --get remote.<name>.url`.
# We don't enforce a specific remote name — `gh repo view` resolves whatever is
# configured.
if ! gh auth status >/dev/null 2>&1; then
  write_stub "gh installed but not authenticated"
  echo "gh not authenticated; wrote stub to $OUT"
  exit 0
fi

# Verify the repo has a GitHub-hosted remote. `gh repo view --json` errors if
# there's no recognized remote.
if ! REPO_INFO=$(cd "$PROJECT_ABS" && gh repo view --json owner,name,nameWithOwner 2>/dev/null); then
  REPO_INFO=""
fi
if [[ -z "$REPO_INFO" ]] || [[ "$REPO_INFO" == "null" ]]; then
  write_stub "no GitHub remote (gh repo view returned nothing)"
  echo "no GitHub remote detected; wrote stub to $OUT"
  exit 0
fi

OWNER=$(printf '%s' "$REPO_INFO" | { jq -r '.owner.login // ""' 2>/dev/null || sed -n 's/.*"login":"\([^"]*\)".*/\1/p'; } | head -1)
NAME=$(printf '%s' "$REPO_INFO"  | { jq -r '.name // ""'        2>/dev/null || sed -n 's/.*"name":"\([^"]*\)".*/\1/p';   } | head -1)
NWO=$(printf '%s' "$REPO_INFO"   | { jq -r '.nameWithOwner // ""' 2>/dev/null || true; } | head -1)
[[ -z "$NWO" && -n "$OWNER" && -n "$NAME" ]] && NWO="$OWNER/$NAME"

if [[ -z "$NWO" ]]; then
  write_stub "could not resolve owner/name for repo"
  echo "could not resolve owner/name; wrote stub to $OUT"
  exit 0
fi

log "GitHub repo detected: $NWO"

# Resume-aware: same branches.tsv hash + same date-hour → reuse. We don't
# want to skip on staleness alone, since open-PR state changes — but within
# a single run hour, re-querying is wasteful.
BR_HASH=""
if [[ -f "$BRANCHES_TSV" ]]; then
  BR_HASH=$(sha256sum "$BRANCHES_TSV" | awk '{print $1}')
fi
HOUR_TAG=$(date -u +%Y-%m-%dT%H)
if [[ -f "$OUT" ]] && command -v jq >/dev/null 2>&1; then
  prior_hour=$(jq -r '.hour_tag // ""' "$OUT" 2>/dev/null || echo "")
  prior_hash=$(jq -r '.branches_tsv_sha256 // ""' "$OUT" 2>/dev/null || echo "")
  if [[ "$prior_hour" == "$HOUR_TAG" ]] && [[ "$prior_hash" == "$BR_HASH" ]]; then
    log "github_state.json is current ($HOUR_TAG, branches.tsv hash matches); skipping re-query."
    echo "wrote $OUT (resumed)"
    exit 0
  fi
fi

# Query open PRs. We pull number, headRefName, baseRefName, author.login,
# updatedAt; gh emits a JSON array.
PR_JSON=$(cd "$PROJECT_ABS" && gh pr list --state open --limit 500 --json number,headRefName,baseRefName,author,updatedAt 2>/dev/null || echo '[]')

# Extract head-branch names. We avoid sed/awk-ing the JSON; jq is required when
# we have multi-PR output (otherwise we degrade to head-grepping for the simplest
# case).
PR_HEADS_FILE="$WORKSPACE_DIR/.github_pr_heads.tmp"
: > "$PR_HEADS_FILE"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$PR_JSON" | jq -r '.[].headRefName' 2>/dev/null > "$PR_HEADS_FILE" || :
else
  # No jq: best-effort by scanning the raw JSON. Fragile but better than nothing.
  printf '%s' "$PR_JSON" | tr ',' '\n' | sed -n 's/.*"headRefName":"\([^"]*\)".*/\1/p' > "$PR_HEADS_FILE" || :
fi

PR_COUNT=$(wc -l < "$PR_HEADS_FILE" 2>/dev/null || echo 0)
PR_COUNT="${PR_COUNT// /}"
log "open PRs: $PR_COUNT"

# Cross-reference with branches.tsv to mark pr-active.
declare -a PR_ACTIVE=()
if [[ -f "$BRANCHES_TSV" ]] && [[ -s "$PR_HEADS_FILE" ]]; then
  while IFS= read -r row; do
    name=""
    tsv_read "$row" name _rest
    [[ "$name" == "name" || -z "$name" ]] && continue
    if grep -Fxq -- "$name" "$PR_HEADS_FILE"; then
      PR_ACTIVE+=("$name")
    fi
  done < "$BRANCHES_TSV"
fi

# Per-branch protection rules. The API returns 404 for branches without
# explicit rules; we treat that as "no rule" rather than as an error.
declare -a PROTECTED_BY_RULE=()
PROT_LIMIT="${GITHUB_PROT_QUERY_LIMIT:-50}"
if [[ ! "$PROT_LIMIT" =~ ^[0-9]+$ ]]; then
  log "invalid GITHUB_PROT_QUERY_LIMIT=$PROT_LIMIT; using 50"
  PROT_LIMIT=50
fi
prot_queried=0
if [[ -f "$BRANCHES_TSV" ]]; then
  # Sort branches with non-empty upstream first so we hit the most likely-
  # protected ones within the query budget; otherwise iterate in order.
  while IFS= read -r row; do
    [[ "$prot_queried" -ge "$PROT_LIMIT" ]] && break
    name=""
    tsv_read "$row" name _rest
    [[ "$name" == "name" || -z "$name" ]] && continue
    prot_queried=$((prot_queried + 1))
    encoded_name=$(url_path_segment "$name")
    if ! branch_protect_json=$(cd "$PROJECT_ABS" && gh api "repos/$NWO/branches/$encoded_name/protection" 2>/dev/null); then
      branch_protect_json=""
    fi
    if [[ -n "$branch_protect_json" ]] && [[ "$branch_protect_json" != "null" ]] \
       && ! printf '%s' "$branch_protect_json" | grep -q '"message":"Branch not protected"'; then
      # Successful body that isn't a "not protected" message → rule present.
      PROTECTED_BY_RULE+=("$name")
    fi
  done < "$BRANCHES_TSV"
fi

log "branches with open PRs: ${#PR_ACTIVE[@]}"
log "branches with protection rules: ${#PROTECTED_BY_RULE[@]} (queried $prot_queried; limit $PROT_LIMIT)"

# Compose the JSON. We include the raw open-PR payload alongside the
# cross-referenced lists; downstream agents can use whichever shape is
# easier to consume.
{
  printf '{\n'
  printf '  "checked_at": '; json_string "$(date -u +%FT%TZ)"; printf ',\n'
  printf '  "hour_tag": '; json_string "$HOUR_TAG"; printf ',\n'
  printf '  "project": '; json_string "$PROJECT_ABS"; printf ',\n'
  printf '  "available": true,\n'
  printf '  "github_repo": '; json_string "$NWO"; printf ',\n'
  printf '  "branches_tsv_sha256": '; json_string "${BR_HASH:-}"; printf ',\n'
  printf '  "open_pr_count": %s,\n' "$PR_COUNT"
  printf '  "protection_query_limit": %s,\n' "$PROT_LIMIT"
  printf '  "protection_query_count": %s,\n' "$prot_queried"

  # pr_active_branches
  printf '  "pr_active_branches": ['
  if [[ "${#PR_ACTIVE[@]}" -gt 0 ]]; then
    printf '\n'
    for i in "${!PR_ACTIVE[@]}"; do
      printf '    '
      json_string "${PR_ACTIVE[$i]}"
      if (( i < ${#PR_ACTIVE[@]} - 1 )); then printf ','; fi
      printf '\n'
    done
    printf '  '
  fi
  printf '],\n'

  # protected_by_rule_branches
  printf '  "protected_by_rule_branches": ['
  if [[ "${#PROTECTED_BY_RULE[@]}" -gt 0 ]]; then
    printf '\n'
    for i in "${!PROTECTED_BY_RULE[@]}"; do
      printf '    '
      json_string "${PROTECTED_BY_RULE[$i]}"
      if (( i < ${#PROTECTED_BY_RULE[@]} - 1 )); then printf ','; fi
      printf '\n'
    done
    printf '  '
  fi
  printf '],\n'

  # raw open_prs payload — embed as a JSON array. The gh output is already
  # JSON; only include if non-empty and valid-looking.
  if [[ -n "$PR_JSON" ]] && [[ "$PR_JSON" != "[]" ]]; then
    printf '  "open_prs": %s\n' "$PR_JSON"
  else
    printf '  "open_prs": []\n'
  fi
  printf '}\n'
} > "$OUT"

# Move-not-delete the temp helper file (Rule 1). Pick a fresh archive path so
# reruns do not overwrite earlier audit breadcrumbs.
if [[ -f "$PR_HEADS_FILE" ]]; then
  archived_heads="$WORKSPACE_DIR/.github_pr_heads.tmp.archived"
  suffix=0
  while [[ -e "$archived_heads" ]]; do
    suffix=$((suffix + 1))
    archived_heads="$WORKSPACE_DIR/.github_pr_heads.tmp.archived-$suffix"
  done
  mv "$PR_HEADS_FILE" "$archived_heads" 2>/dev/null || true
fi

echo "wrote $OUT"
echo "  github_repo: $NWO"
echo "  open PRs: $PR_COUNT"
echo "  pr-active branches: ${#PR_ACTIVE[@]}"
echo "  protected-by-rule branches: ${#PROTECTED_BY_RULE[@]} (queried $prot_queried/$PROT_LIMIT)"
exit 0
