#!/usr/bin/env bash
# discover-project.sh — Phase 1: profile the target project.
#
# Detects:
#   - canonical branch (origin/HEAD → init.defaultBranch → heuristic ref scan)
#   - branching model (trunk-based / gitflow / release-branches / unknown)
#   - test / typecheck / lint / format commands
#   - merge-style preference (squash / rebase-and-merge / merge / unknown)
#   - protected-by-convention name patterns
#   - commit message convention (conventional / ticket-id / gitmoji / freeform)
#   - CI gate hints (.github/workflows, lefthook, husky, pre-commit, ubs)
#
# Output: writes <workspace>/project_profile.json
# Stdout: human-readable summary.
#
# Exit codes:
#   0 — profile written successfully
#   2 — project is mid-rebase / merge / cherry-pick / revert / bisect (refused)
#   3 — project path is not a git work tree
#
# Env: WORKSPACE override → write profile under that dir instead of the default.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: discover-project.sh <project-path>

Phase 1 of the git-worktree-branch-rationalization skill. Detects canonical
branch, build commands, branching model, merge style, and protected-by-convention
patterns. Writes <workspace>/project_profile.json.

Env:
  WORKSPACE    Override the workspace directory (default:
               <project>/.worktree_branch_rationalization_workspace)

Exit codes:
  0  ok
  2  project is mid-operation (rebase/merge/cherry-pick/revert/bisect)
  3  project path is not a git work tree
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 3
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
mkdir -p "$WORKSPACE_DIR"

# Refuse if the active worktree is mid-operation. The skill needs a clean
# checkout state to snapshot from.
GIT_DIR=$(cd "$PROJECT_ABS" && git rev-parse --git-dir)
case "$GIT_DIR" in
  /*) GIT_DIR_ABS="$GIT_DIR" ;;
  *)  GIT_DIR_ABS="$PROJECT_ABS/$GIT_DIR" ;;
esac
mid_op=""
[[ -d "$GIT_DIR_ABS/rebase-merge"     ]] && mid_op="rebase (interactive)"
[[ -d "$GIT_DIR_ABS/rebase-apply"     ]] && mid_op="rebase / am"
[[ -f "$GIT_DIR_ABS/MERGE_HEAD"       ]] && mid_op="merge"
[[ -f "$GIT_DIR_ABS/CHERRY_PICK_HEAD" ]] && mid_op="cherry-pick"
[[ -f "$GIT_DIR_ABS/REVERT_HEAD"      ]] && mid_op="revert"
[[ -f "$GIT_DIR_ABS/BISECT_LOG"       ]] && mid_op="bisect"
if [[ -n "$mid_op" ]]; then
  echo "ERROR: $PROJECT_ABS is mid-$mid_op. Finish the operation first." >&2
  exit 2
fi

# Refuse on a bare repo — `git worktree` and the rationalization story are
# meaningful only on work trees.
if [[ "$(git -C "$PROJECT_ABS" rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
  echo "ERROR: $PROJECT_ABS is a bare repository; the skill operates on work trees only." >&2
  exit 3
fi

# --- Canonical branch detection (NEVER assumes 'main') ---
detect_canonical_branch() {
  # 1. origin/HEAD: the explicit upstream default.
  local pb
  pb=$(git -C "$PROJECT_ABS" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
       | sed 's@^origin/@@' || true)
  if [[ -n "$pb" ]]; then echo "$pb"; return; fi

  # 2. init.defaultBranch — repo-level config.
  pb=$(git -C "$PROJECT_ABS" config --get init.defaultBranch 2>/dev/null || true)
  if [[ -n "$pb" ]] && git -C "$PROJECT_ABS" show-ref --verify --quiet "refs/heads/$pb"; then
    echo "$pb"; return
  fi

  # 3. heuristic against the actual ref list, in priority order.
  local candidate
  for candidate in main master develop trunk default; do
    if git -C "$PROJECT_ABS" show-ref --verify --quiet "refs/heads/$candidate"; then
      echo "$candidate"; return
    fi
    if git -C "$PROJECT_ABS" show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
      echo "$candidate"; return
    fi
  done

  # 4. fallback: the active branch.
  git -C "$PROJECT_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown
}
CANONICAL_BRANCH="$(detect_canonical_branch)"

resolve_canonical_ref() {
  local branch="$1"
  if git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$branch^{commit}" >/dev/null 2>&1; then
    printf 'refs/heads/%s\n' "$branch"
  elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/remotes/origin/$branch^{commit}" >/dev/null 2>&1; then
    printf 'refs/remotes/origin/%s\n' "$branch"
  else
    printf '\n'
  fi
}
CANONICAL_REF="$(resolve_canonical_ref "$CANONICAL_BRANCH")"

# --- Branching-model heuristic ---
detect_branching_model() {
  local refs
  refs=$(git -C "$PROJECT_ABS" for-each-ref refs/heads --format='%(refname:lstrip=2)' 2>/dev/null | tr '\n' ' ' || true)
  local has_develop=false has_release=false has_hotfix=false has_feature=false
  echo "$refs" | grep -qE '(^| )develop($| )'      && has_develop=true
  echo "$refs" | grep -qE '(^| )release/'          && has_release=true
  echo "$refs" | grep -qE '(^| )hotfix/'           && has_hotfix=true
  echo "$refs" | grep -qE '(^| )feature/'          && has_feature=true
  if   [[ "$has_develop" == "true" && "$has_release" == "true" && "$has_hotfix" == "true" ]]; then
    echo gitflow
  elif [[ "$has_release" == "true" || "$has_hotfix" == "true" ]]; then
    echo release-branches
  elif [[ "$has_feature" == "true" ]]; then
    echo feature-branches
  else
    echo trunk-based
  fi
}
BRANCHING_MODEL="$(detect_branching_model)"

# --- Merge-style preference ---
# Inspect recent commits on the canonical branch for tell-tale shapes:
#   - many merge commits w/ "Merge pull request" subjects → merge
#   - linear history w/ author == committer && multiple parents == 1 → rebase-and-merge
#   - linear history w/ "(#NNN)" suffix (GH squash style) → squash
detect_merge_style() {
  local sample merges total squash_pct
  if [[ -z "$CANONICAL_REF" ]]; then echo unknown; return; fi
  sample=$(git -C "$PROJECT_ABS" log -100 --format='%P|%s' "$CANONICAL_REF" 2>/dev/null || true)
  if [[ -z "$sample" ]]; then echo unknown; return; fi
  total=$(printf '%s\n' "$sample" | wc -l)
  merges=$(printf '%s\n' "$sample" | awk -F'|' '{n=split($1,a," "); if (n>1) print}' | wc -l)
  squash_pct=$(printf '%s\n' "$sample" | awk -F'|' '$2 ~ /\(#[0-9]+\)$/ {c++} END {print c+0}')
  if   [[ "$total" -gt 0 ]] && (( merges * 100 / total >= 30 )); then echo merge
  elif [[ "$total" -gt 0 ]] && (( squash_pct * 100 / total >= 30 )); then echo squash
  elif [[ "$merges" -eq 0 ]]; then echo rebase-and-merge
  else echo unknown
  fi
}
MERGE_STYLE="$(detect_merge_style)"

# --- Test / typecheck / lint / format command detection ---
has_file_matching() {
  local pattern="$1"
  local match
  while IFS= read -r match; do
    [[ -f "$match" ]] && return 0
  done < <(compgen -G "$pattern" || true)
  return 1
}

detect_test_command() {
  if [[ -f "$PROJECT_ABS/Cargo.toml" ]]; then
    echo "cargo test --workspace"
  elif [[ -f "$PROJECT_ABS/package.json" ]]; then
    if command -v bun >/dev/null 2>&1 && [[ -f "$PROJECT_ABS/bun.lockb" || -f "$PROJECT_ABS/bun.lock" ]]; then
      echo "bun test"
    elif command -v jq >/dev/null 2>&1 && jq -e '.scripts.test' "$PROJECT_ABS/package.json" >/dev/null 2>&1; then
      if   [[ -f "$PROJECT_ABS/pnpm-lock.yaml" ]]; then echo "pnpm test"
      elif [[ -f "$PROJECT_ABS/yarn.lock"      ]]; then echo "yarn test"
      else echo "npm test"; fi
    else echo ""; fi
  elif [[ -f "$PROJECT_ABS/pyproject.toml" || -f "$PROJECT_ABS/setup.py" ]]; then
    if grep -q '\[tool.pytest' "$PROJECT_ABS/pyproject.toml" 2>/dev/null || [[ -d "$PROJECT_ABS/tests" ]]; then
      echo "pytest"
    elif grep -q '\[tool.poetry' "$PROJECT_ABS/pyproject.toml" 2>/dev/null; then
      echo "poetry run pytest"
    else echo ""; fi
  elif [[ -f "$PROJECT_ABS/go.mod" ]]; then
    echo "go test ./..."
  elif [[ -f "$PROJECT_ABS/Gemfile" ]]; then
    echo "bundle exec rake test"
  else
    echo ""
  fi
}

detect_typecheck_command() {
  if [[ -f "$PROJECT_ABS/Cargo.toml" ]]; then
    echo "cargo check --workspace"
  elif [[ -f "$PROJECT_ABS/tsconfig.json" ]]; then
    if command -v bun >/dev/null 2>&1 && [[ -f "$PROJECT_ABS/bun.lockb" || -f "$PROJECT_ABS/bun.lock" ]]; then
      echo "bun tsc --noEmit"
    else echo "npx tsc --noEmit"; fi
  elif [[ -f "$PROJECT_ABS/pyproject.toml" ]] && grep -q mypy "$PROJECT_ABS/pyproject.toml" 2>/dev/null; then
    echo "mypy ."
  elif [[ -f "$PROJECT_ABS/go.mod" ]]; then
    echo "go vet ./..."
  else
    echo ""
  fi
}

detect_lint_command() {
  if [[ -f "$PROJECT_ABS/Cargo.toml" ]]; then
    echo "cargo clippy --workspace -- -D warnings"
  elif has_file_matching "$PROJECT_ABS/.eslintrc*" || [[ -f "$PROJECT_ABS/eslint.config.js" || -f "$PROJECT_ABS/eslint.config.mjs" ]]; then
    echo "npx eslint ."
  elif [[ -f "$PROJECT_ABS/pyproject.toml" ]] && grep -q ruff "$PROJECT_ABS/pyproject.toml" 2>/dev/null; then
    echo "ruff check ."
  elif [[ -f "$PROJECT_ABS/go.mod" ]]; then
    if command -v golangci-lint >/dev/null 2>&1; then echo "golangci-lint run"; else echo "go vet ./..."; fi
  else
    echo ""
  fi
}

detect_format_command() {
  if   [[ -f "$PROJECT_ABS/Cargo.toml" ]]; then echo "cargo fmt --check"
  elif has_file_matching "$PROJECT_ABS/.prettierrc*" || [[ -f "$PROJECT_ABS/prettier.config.js" ]]; then echo "npx prettier --check ."
  elif [[ -f "$PROJECT_ABS/pyproject.toml" ]] && grep -q ruff "$PROJECT_ABS/pyproject.toml" 2>/dev/null; then echo "ruff format --check ."
  elif [[ -f "$PROJECT_ABS/go.mod" ]]; then echo "gofmt -l ."
  else echo ""
  fi
}

TEST_CMD=$(detect_test_command)
TYPECHECK_CMD=$(detect_typecheck_command)
LINT_CMD=$(detect_lint_command)
FORMAT_CMD=$(detect_format_command)

# --- Tooling availability ---
UBS_AVAILABLE=false
command -v ubs >/dev/null 2>&1 && UBS_AVAILABLE=true
[[ -f "$PROJECT_ABS/.ubsignore" ]] && UBS_AVAILABLE=true
DCG_AVAILABLE=false
command -v dcg >/dev/null 2>&1 && DCG_AVAILABLE=true

# --- Pre-commit hooks ---
PRE_COMMIT_HOOKS=()
[[ -f "$PROJECT_ABS/.husky/pre-commit" || -f "$PROJECT_ABS/.husky/_/pre-commit" ]] && PRE_COMMIT_HOOKS+=(husky)
[[ -f "$PROJECT_ABS/lefthook.yml" || -f "$PROJECT_ABS/lefthook.yaml" ]]            && PRE_COMMIT_HOOKS+=(lefthook)
[[ -f "$PROJECT_ABS/.pre-commit-config.yaml" ]]                                    && PRE_COMMIT_HOOKS+=(pre-commit)
[[ -f "$PROJECT_ABS/.git/hooks/pre-commit" ]]                                      && PRE_COMMIT_HOOKS+=(git-hook)

# --- CI workflow detection ---
CI_GATES=()
if [[ -d "$PROJECT_ABS/.github/workflows" ]]; then
  while IFS= read -r wf; do
    [[ -n "$wf" ]] && CI_GATES+=("$(basename "$wf")")
  done < <(find "$PROJECT_ABS/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
fi

# --- Commit message convention sampling ---
detect_commit_convention() {
  local sample
  sample=$(git -C "$PROJECT_ABS" log -50 --format='%s' 2>/dev/null || echo "")
  if   echo "$sample" | grep -qE '^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)(\([^)]+\))?:'; then echo conventional
  elif echo "$sample" | grep -qE '^[A-Z]+-[0-9]+'; then echo ticket-id
  elif echo "$sample" | grep -qE '^:[a-z_]+:'; then echo gitmoji
  else echo freeform
  fi
}
COMMIT_CONVENTION=$(detect_commit_convention)

# --- Protected-by-convention patterns ---
# Defaults: release/*, hotfix/*, dependabot/*, renovate/*, gh-pages.
# Add the canonical branch and the active branch automatically (the orchestrator
# inserts these into the user-facing protection list at Phase 4).
PROTECTED_PATTERNS=(
  "release/*"
  "hotfix/*"
  "dependabot/*"
  "renovate/*"
  "gh-pages"
)
# Project-specific: scan for .github/branch-protection.yml or CODEOWNERS hints.
if [[ -f "$PROJECT_ABS/.github/branch-protection.yml" ]]; then
  while IFS= read -r line; do
    pat=$(echo "$line" | sed -nE 's/.*pattern:[[:space:]]*"?([^"#]+)"?.*/\1/p' | head -1)
    [[ -n "$pat" ]] && PROTECTED_PATTERNS+=("$pat")
  done < "$PROJECT_ABS/.github/branch-protection.yml"
fi

# --- Counts up front ---
WT_COUNT=$(git -C "$PROJECT_ABS" worktree list 2>/dev/null | wc -l)
# `worktree list` includes the main repo entry; subtract 1 if there is at least
# one row.
[[ "$WT_COUNT" -gt 0 ]] && WT_COUNT=$((WT_COUNT - 1))
BR_COUNT=$(git -C "$PROJECT_ABS" for-each-ref refs/heads --format='%(refname:lstrip=2)' 2>/dev/null | wc -l)
# Subtract canonical from the user-visible branch count.
NON_CANONICAL=$((BR_COUNT > 0 ? BR_COUNT - 1 : 0))

ACTIVE_BRANCH=$(git -C "$PROJECT_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)

json_string() {
  local s="${1-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

OUT="$WORKSPACE_DIR/project_profile.json"
{
  printf '{\n'
  printf '  "project_path": ';            json_string "$PROJECT_ABS";       printf ',\n'
  printf '  "canonical_branch": ';        json_string "$CANONICAL_BRANCH";  printf ',\n'
  printf '  "active_branch": ';           json_string "$ACTIVE_BRANCH";     printf ',\n'
  printf '  "branching_model": ';         json_string "$BRANCHING_MODEL";   printf ',\n'
  printf '  "merge_style": ';             json_string "$MERGE_STYLE";       printf ',\n'
  printf '  "test_command": ';            json_string "$TEST_CMD";          printf ',\n'
  printf '  "typecheck_command": ';       json_string "$TYPECHECK_CMD";     printf ',\n'
  printf '  "lint_command": ';            json_string "$LINT_CMD";          printf ',\n'
  printf '  "format_command": ';          json_string "$FORMAT_CMD";        printf ',\n'
  printf '  "ubs_available": %s,\n' "$UBS_AVAILABLE"
  printf '  "dcg_available": %s,\n' "$DCG_AVAILABLE"
  printf '  "pre_commit_hooks": ['
  for i in "${!PRE_COMMIT_HOOKS[@]}"; do
    [[ $i -gt 0 ]] && printf ', '
    json_string "${PRE_COMMIT_HOOKS[$i]}"
  done
  printf '],\n'
  printf '  "ci_gates": ['
  for i in "${!CI_GATES[@]}"; do
    [[ $i -gt 0 ]] && printf ', '
    json_string "${CI_GATES[$i]}"
  done
  printf '],\n'
  printf '  "commit_message_convention": '; json_string "$COMMIT_CONVENTION"; printf ',\n'
  printf '  "protected_patterns": ['
  for i in "${!PROTECTED_PATTERNS[@]}"; do
    [[ $i -gt 0 ]] && printf ', '
    json_string "${PROTECTED_PATTERNS[$i]}"
  done
  printf '],\n'
  printf '  "worktree_count": %s,\n' "$WT_COUNT"
  printf '  "branch_count": %s,\n' "$BR_COUNT"
  printf '  "non_canonical_branch_count": %s\n' "$NON_CANONICAL"
  printf '}\n'
} > "$OUT"

# Workspace .gitignore so the transient dir doesn't pollute git status. The skill
# never modifies .git/info/exclude — the file lives inside the workspace itself,
# and the workspace path is conventionally already gitignored by the project, but
# emit a self-contained marker so tooling that scans the workspace knows it's
# transient.
GI="$WORKSPACE_DIR/.gitignore"
if [[ ! -f "$GI" ]]; then
  printf '*\n' > "$GI"
fi

# Human summary
echo
echo "=== Project profile for $PROJECT_ABS ==="
echo "  canonical_branch:            $CANONICAL_BRANCH"
echo "  active_branch:               $ACTIVE_BRANCH"
echo "  branching_model:             $BRANCHING_MODEL"
echo "  merge_style:                 $MERGE_STYLE"
echo "  test_command:                ${TEST_CMD:-<none>}"
echo "  typecheck_command:           ${TYPECHECK_CMD:-<none>}"
echo "  lint_command:                ${LINT_CMD:-<none>}"
echo "  format_command:              ${FORMAT_CMD:-<none>}"
echo "  ubs_available:               $UBS_AVAILABLE"
echo "  dcg_available:               $DCG_AVAILABLE"
echo "  pre_commit_hooks:            ${PRE_COMMIT_HOOKS[*]:-<none>}"
echo "  ci_gates:                    ${CI_GATES[*]:-<none>}"
echo "  commit_convention:           $COMMIT_CONVENTION"
echo "  protected_patterns:          ${PROTECTED_PATTERNS[*]}"
echo "  worktree_count (excl. main): $WT_COUNT"
echo "  branch_count:                $BR_COUNT (non-canonical: $NON_CANONICAL)"
echo
echo "wrote $OUT"
