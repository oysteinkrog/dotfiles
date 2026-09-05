#!/usr/bin/env bash
# ci-workflow-aware-update.sh — Phase 4: detect references to soon-to-be-
# deleted branches in CI / docs / config, and suggest updates.
#
# Files scanned (read-only):
#   - .github/workflows/*.yml + *.yaml
#   - .gitlab-ci.yml
#   - .circleci/config.yml + .circleci/config.yaml
#   - Jenkinsfile
#   - .github/dependabot.yml + dependabot.yaml
#   - .github/mergify.yml + mergify.yaml
#   - package.json (repository / scripts referencing branch names)
#   - README.md / README.MD (install URLs / badge URLs)
#   - CHANGELOG.md (heading references)
#   - Dockerfile / Containerfile (FROM ... :branch)
#   - any .md / .yml / .yaml at the project root
#
# For every match against a branch name in triage.tsv whose verdict is in
# {garbage, superseded, already-merged, novel-but-stale, divergent-refactor},
# emits a finding row with file:line, the matched text, and a suggested
# replacement (typically the canonical branch).
#
# Per AGENTS.md "No Script-Based Changes": this script DOES NOT auto-apply
# updates. The user reviews <workspace>/ci_workflow_updates.md and applies
# changes via the Edit tool manually.
#
# Read-only. Resume-aware: skips re-scanning when triage.tsv hasn't moved.
#
# Exit codes:
#   0  scan complete (findings file written, possibly with 0 findings)
#   2  preflight failed (triage.tsv missing)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: ci-workflow-aware-update.sh <project-path>

Phase 4. Scans CI workflow YAML, README install URLs, dependabot/mergify
config, Dockerfile, package.json, and CHANGELOG.md for references to
branches scheduled for deletion in <workspace>/triage.tsv. Emits findings
to <workspace>/ci_workflow_updates.md.

NEVER auto-applies updates (per AGENTS.md "No Script-Based Changes"). The
user reviews and edits manually.

Env:
  WORKSPACE   Workspace dir override.
  CI_SCAN_FORCE=1   Force re-scan even when triage.tsv unchanged.

Exit codes:
  0  scan complete
  2  preflight failed
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
TRIAGE="$WORKSPACE_DIR/triage.tsv"
PROFILE="$WORKSPACE_DIR/project_profile.json"
PROTECTED="$WORKSPACE_DIR/protected.tsv"
OUT="$WORKSPACE_DIR/ci_workflow_updates.md"

[[ -f "$TRIAGE" ]] || { echo "ERROR: $TRIAGE missing" >&2; exit 2; }

# Resume signature.
SIG=$(sha256sum "$TRIAGE" | awk '{print $1}')
if [[ -z "${CI_SCAN_FORCE:-}" && -f "$OUT" ]]; then
  if grep -qE "^<!-- signature: $SIG -->$" "$OUT" 2>/dev/null; then
    log "ci_workflow_updates.md unchanged for triage signature $SIG; reusing"
    echo "current: $OUT"
    exit 0
  fi
fi

# Resolve canonical for suggested replacements.
CANONICAL=""
if [[ -f "$PROFILE" ]] && command -v jq >/dev/null 2>&1; then
  CANONICAL=$(jq -r '.canonical_branch // ""' "$PROFILE" 2>/dev/null || echo "")
fi
[[ -z "$CANONICAL" ]] && CANONICAL="main"

# Build set of doomed branches.
declare -A DOOMED
declare -A IS_PROTECTED
if [[ -f "$PROTECTED" ]]; then
  while IFS= read -r row; do
    kind=; name=
    tsv_read "$row" kind name _rest
    [[ "$kind" == "kind" ]] && continue
    [[ -z "$name" ]] && continue
    [[ "$kind" == "branch" ]] && IS_PROTECTED["$name"]=1
  done < "$PROTECTED"
fi

while IFS= read -r row; do
  kind=; name=; verdict=
  tsv_read "$row" kind name verdict _rest
  [[ "$kind" == "kind" ]] && continue
  [[ "$kind" != "branch" ]] && continue
  [[ -z "$name" ]] && continue
  [[ -n "${IS_PROTECTED[$name]:-}" ]] && continue
  case "$verdict" in
    garbage|superseded|already-merged|novel-but-stale|divergent-refactor) DOOMED["$name"]=1 ;;
  esac
done < "$TRIAGE"

if [[ ${#DOOMED[@]} -eq 0 ]]; then
  {
    printf '<!-- signature: %s -->\n' "$SIG"
    printf '# CI / workflow / docs review — no doomed branches in triage\n\n'
    printf 'The triage table has zero branches scheduled for deletion in the\n'
    printf 'doomed-verdict set. No CI scan needed.\n'
  } > "$OUT"
  echo "$OUT (no doomed branches)"
  exit 0
fi

# File globs (relative to project root).
declare -a FILES_TO_SCAN=()
add_if_present() {
  for f in "$@"; do
    [[ -f "$PROJECT_ABS/$f" || -d "$PROJECT_ABS/$f" ]] && FILES_TO_SCAN+=("$f")
  done
  return 0
}

# Workflow / config files.
if [[ -d "$PROJECT_ABS/.github/workflows" ]]; then
  while IFS= read -r f; do
    rel="${f#"$PROJECT_ABS"/}"
    FILES_TO_SCAN+=("$rel")
  done < <(find "$PROJECT_ABS/.github/workflows" -maxdepth 2 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
fi
if [[ -d "$PROJECT_ABS/.circleci" ]]; then
  while IFS= read -r f; do
    rel="${f#"$PROJECT_ABS"/}"
    FILES_TO_SCAN+=("$rel")
  done < <(find "$PROJECT_ABS/.circleci" -maxdepth 2 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
fi
add_if_present \
  ".gitlab-ci.yml" "Jenkinsfile" \
  ".github/dependabot.yml" ".github/dependabot.yaml" \
  ".github/mergify.yml" ".github/mergify.yaml" \
  ".mergify.yml" ".mergify.yaml" \
  "package.json" "Dockerfile" "Containerfile" \
  "README.md" "README.MD" "Readme.md" \
  "CHANGELOG.md" "Changelog.md"

# Dedupe.
mapfile -t FILES_TO_SCAN < <(printf '%s\n' "${FILES_TO_SCAN[@]}" | awk '!seen[$0]++')

declare -i FINDINGS=0
declare -a FINDING_ROWS=()

has_branch_boundary() {
  local branch="$1"
  local text="$2"
  python3 - "$branch" "$text" <<'PY'
import sys

branch = sys.argv[1]
text = sys.argv[2]
if not branch:
    sys.exit(1)

left_boundaries = set(" \t\r\n'\"`()[]{}<>:;,.|")
right_boundaries = left_boundaries | {"/"}
start = 0
while True:
    idx = text.find(branch, start)
    if idx < 0:
        sys.exit(1)
    before = text[idx - 1] if idx > 0 else ""
    after_idx = idx + len(branch)
    after = text[after_idx] if after_idx < len(text) else ""
    left_ok = idx == 0 or before in left_boundaries
    right_ok = after_idx == len(text) or after in right_boundaries
    if left_ok and right_ok:
        sys.exit(0)
    start = idx + 1
PY
}

# Build a regex alternation of doomed branch names. Bash regex matching against
# YAML strings is brittle; we use grep -nF for literal matches plus -nE for
# branch-name boundary patterns.
for branch in "${!DOOMED[@]}"; do
  # Each branch is checked individually. Skip extremely short branch names
  # (< 4 chars) to reduce false positives unless they look distinctive.
  if [[ "${#branch}" -lt 4 ]]; then
    continue
  fi
  for rel in "${FILES_TO_SCAN[@]}"; do
    abs="$PROJECT_ABS/$rel"
    [[ -f "$abs" ]] || continue
    # Use literal grep first.
    while IFS= read -r match; do
      [[ -z "$match" ]] && continue
      lineno=$(printf '%s' "$match" | cut -d: -f1)
      text=$(printf '%s' "$match" | cut -d: -f2-)
      # Filter trivial false positives where the branch substring is only
      # part of an unrelated word: require a non-alphanumeric or path
      # boundary on at least one side.
      if has_branch_boundary "$branch" "$text"; then
        FINDINGS=$((FINDINGS+1))
        FINDING_ROWS+=("$rel"$'\t'"$lineno"$'\t'"$branch"$'\t'"$text")
      fi
    done < <(grep -nF "$branch" "$abs" 2>/dev/null || true)
  done
done

{
  printf '<!-- signature: %s -->\n' "$SIG"
  printf '# CI / workflow / docs references to soon-to-be-deleted branches\n\n'
  printf 'Project:    `%s`\n' "$PROJECT_ABS"
  printf 'Canonical:  `%s`\n' "$CANONICAL"
  printf 'Generated:  %s\n\n' "$(date -u +%FT%TZ)"
  printf 'Doomed branches (verdict ∈ {garbage, superseded, already-merged,\n'
  printf 'novel-but-stale, divergent-refactor}):\n\n'
  for b in "${!DOOMED[@]}"; do
    printf -- '- `%s`\n' "$b"
  done
  printf '\n'

  if [[ "$FINDINGS" -eq 0 ]]; then
    printf '## Findings\n\nNo references found in CI workflow / config / docs.\n\n'
  else
    printf '## Findings — %d match(es)\n\n' "$FINDINGS"
    printf '| File | Line | Doomed branch | Matched text | Suggested update |\n'
    printf '|------|-----:|---------------|--------------|------------------|\n'
    for row in "${FINDING_ROWS[@]}"; do
      file=$(printf '%s' "$row" | cut -f1)
      lineno=$(printf '%s' "$row" | cut -f2)
      branch=$(printf '%s' "$row" | cut -f3)
      text=$(printf '%s' "$row" | cut -f4)
      # Escape pipes for markdown table rendering.
      text_escaped=${text//|/\\|}
      printf '| `%s` | %s | `%s` | `%s` | replace `%s` with `%s` (or remove the line) |\n' \
        "$file" "$lineno" "$branch" "$text_escaped" "$branch" "$CANONICAL"
    done
    printf '\n'
  fi

  printf '## How to apply these updates\n\n'
  printf 'Per AGENTS.md "No Script-Based Changes", this script DOES NOT mutate\n'
  printf 'source files. Apply updates manually via the Edit tool:\n\n'
  printf '1. Open each `<file>:<line>` listed above.\n'
  printf '2. Decide whether to (a) replace the doomed branch reference with\n'
  printf '   `%s`, (b) remove the line entirely, or (c) leave it alone\n' "$CANONICAL"
  printf '   (rare — flag in handoff_report.md).\n'
  printf '3. Edit the file, run the project'"'"'s linter / CI dry-run, commit\n'
  printf '   the change to the rationalization branch.\n'
  printf '4. Re-run this script to confirm 0 remaining findings.\n'
} > "$OUT"

log "wrote $OUT"
echo "findings=$FINDINGS"
exit 0
