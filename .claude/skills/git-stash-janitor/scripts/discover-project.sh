#!/usr/bin/env bash
# discover-project.sh — Detect primary branch, build/test/lint commands,
# stash message conventions for the target project.
#
# Output: writes <project>/.stash_janitor_workspace/project_profile.json
# Stdout: human-readable summary + path to the JSON file.

set -euo pipefail

PROJECT="${1:?Usage: discover-project.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
mkdir -p "$WORKSPACE"

# Refuse mid-merge / mid-rebase / mid-cherry-pick / mid-revert / mid-bisect.
# Resolve the absolute git-dir (handles worktrees and submodules where
# .git is a file pointing elsewhere).
GIT_DIR=$(cd "$PROJECT_ABS" && git rev-parse --git-dir)
case "$GIT_DIR" in
  /*) GIT_DIR_ABS="$GIT_DIR" ;;
  *)  GIT_DIR_ABS="$PROJECT_ABS/$GIT_DIR" ;;
esac
mid_op=""
[[ -d "$GIT_DIR_ABS/rebase-merge"  ]] && mid_op="rebase (interactive)"
[[ -d "$GIT_DIR_ABS/rebase-apply"  ]] && mid_op="rebase / am"
[[ -f "$GIT_DIR_ABS/MERGE_HEAD"    ]] && mid_op="merge"
[[ -f "$GIT_DIR_ABS/CHERRY_PICK_HEAD" ]] && mid_op="cherry-pick"
[[ -f "$GIT_DIR_ABS/REVERT_HEAD"   ]] && mid_op="revert"
[[ -f "$GIT_DIR_ABS/BISECT_LOG"    ]] && mid_op="bisect"
if [[ -n "$mid_op" ]]; then
  echo "ERROR: $PROJECT_ABS is mid-$mid_op. Finish the operation first." >&2
  exit 2
fi

# --- Primary branch detection (cascading fallbacks) ---
detect_primary_branch() {
  # 1. origin/HEAD
  local pb
  pb=$(git -C "$PROJECT_ABS" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
       | sed 's@^origin/@@' || true)
  if [[ -n "$pb" ]]; then echo "$pb"; return; fi

  # 2. init.defaultBranch config
  pb=$(git -C "$PROJECT_ABS" config --get init.defaultBranch 2>/dev/null || true)
  if [[ -n "$pb" ]]; then
    # verify the branch actually exists
    if git -C "$PROJECT_ABS" show-ref --verify --quiet "refs/heads/$pb"; then
      echo "$pb"; return
    fi
  fi

  # 3. heuristic: look for canonical names in priority order
  local candidate
  for candidate in main master develop trunk default; do
    if git -C "$PROJECT_ABS" show-ref --verify --quiet "refs/heads/$candidate"; then
      echo "$candidate"; return
    fi
    if git -C "$PROJECT_ABS" show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
      echo "$candidate"; return
    fi
  done

  # 4. fallback: current branch
  git -C "$PROJECT_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown
}

PRIMARY_BRANCH=$(detect_primary_branch)

# --- Test / typecheck / lint command detection ---
detect_test_command() {
  if [[ -f "$PROJECT_ABS/Cargo.toml" ]]; then
    echo "cargo test --workspace"
  elif [[ -f "$PROJECT_ABS/package.json" ]]; then
    if command -v bun >/dev/null 2>&1 && [[ -f "$PROJECT_ABS/bun.lockb" || -f "$PROJECT_ABS/bun.lock" ]]; then
      echo "bun test"
    elif jq -e '.scripts.test' "$PROJECT_ABS/package.json" >/dev/null 2>&1; then
      if [[ -f "$PROJECT_ABS/pnpm-lock.yaml" ]]; then echo "pnpm test"
      elif [[ -f "$PROJECT_ABS/yarn.lock" ]]; then echo "yarn test"
      else echo "npm test"; fi
    else
      echo ""
    fi
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

has_file_matching() {
  local pattern="$1"
  local match
  while IFS= read -r match; do
    [[ -f "$match" ]] && return 0
  done < <(compgen -G "$pattern" || true)
  return 1
}

detect_lint_command() {
  if [[ -f "$PROJECT_ABS/Cargo.toml" ]]; then
    echo "cargo clippy --workspace -- -D warnings"
  elif has_file_matching "$PROJECT_ABS/.eslintrc*" || [[ -f "$PROJECT_ABS/eslint.config.js" || -f "$PROJECT_ABS/eslint.config.mjs" ]]; then
    echo "npx eslint ."
  elif [[ -f "$PROJECT_ABS/pyproject.toml" ]] && grep -q ruff "$PROJECT_ABS/pyproject.toml" 2>/dev/null; then
    echo "ruff check ."
  elif [[ -f "$PROJECT_ABS/go.mod" ]]; then
    if command -v golangci-lint >/dev/null 2>&1; then echo "golangci-lint run"
    else echo "go vet ./..."; fi
  else
    echo ""
  fi
}

detect_format_command() {
  if [[ -f "$PROJECT_ABS/Cargo.toml" ]]; then echo "cargo fmt --check"
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

# --- UBS detection ---
UBS_AVAILABLE=false
if command -v ubs >/dev/null 2>&1; then UBS_AVAILABLE=true; fi
if [[ -f "$PROJECT_ABS/.ubsignore" ]]; then UBS_AVAILABLE=true; fi

# --- DCG detection ---
DCG_AVAILABLE=false
if command -v dcg >/dev/null 2>&1; then DCG_AVAILABLE=true; fi

# --- Pre-commit hook detection ---
PRE_COMMIT_HOOKS=()
if [[ -f "$PROJECT_ABS/.husky/pre-commit" || -f "$PROJECT_ABS/.husky/_/pre-commit" ]]; then PRE_COMMIT_HOOKS+=(husky); fi
if [[ -f "$PROJECT_ABS/lefthook.yml" || -f "$PROJECT_ABS/lefthook.yaml" ]]; then PRE_COMMIT_HOOKS+=(lefthook); fi
if [[ -f "$PROJECT_ABS/.pre-commit-config.yaml" ]]; then PRE_COMMIT_HOOKS+=(pre-commit); fi
if [[ -f "$PROJECT_ABS/.git/hooks/pre-commit" ]]; then PRE_COMMIT_HOOKS+=(git-hook); fi

# --- Commit message convention sampling ---
detect_commit_convention() {
  local sample
  sample=$(git -C "$PROJECT_ABS" log -50 --format='%s' 2>/dev/null || echo "")
  if echo "$sample" | grep -qE '^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)(\([^)]+\))?:'; then
    echo conventional
  elif echo "$sample" | grep -qE '^[A-Z]+-[0-9]+'; then
    echo ticket-id
  elif echo "$sample" | grep -qE '^:[a-z_]+:'; then
    echo gitmoji
  else
    echo freeform
  fi
}
COMMIT_CONVENTION=$(detect_commit_convention)

# --- Stash message conventions ---
# Sample stash messages, strip git's "WIP on <branch>: <sha> " / "On <branch>: "
# prefix, take the first message-prefix token, and tally the top families.
collect_stash_prefixes() {
  # `head -10` triggers SIGPIPE on the upstream `sort -rn` once head closes
  # its stdin after 10 lines. Under `set -euo pipefail` that makes the whole
  # pipeline exit non-zero, the surrounding `|| echo ""` swallows it, and the
  # script silently loses prefix data on any project whose stashes have >10
  # message-prefix families — exactly the messy projects this skill targets.
  # `sed -n '1,10p'` reads all of stdin and prints only lines 1..10, so the
  # upstream commands never see a closed stdin.
  git -C "$PROJECT_ABS" stash list --format='%s' 2>/dev/null \
    | sed -E 's/^(WIP on [^:]+: [0-9a-f]+ |On [^:]+: )//' \
    | awk -F'[ :_-]' 'NF { print $1 }' \
    | sort | uniq -c | sort -rn | sed -n '1,10p' \
    | awk '{prefix=$2; count=$1; printf "%s=%d;", prefix, count}'
}
STASH_PREFIXES=$(collect_stash_prefixes 2>/dev/null || echo "")

json_string() {
  local s="${1-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

# --- Output JSON ---
OUT="$WORKSPACE/project_profile.json"
{
  printf '{\n'
  printf '  "project_path": '; json_string "$PROJECT_ABS"; printf ',\n'
  printf '  "primary_branch": '; json_string "$PRIMARY_BRANCH"; printf ',\n'
  printf '  "test_command": '; json_string "$TEST_CMD"; printf ',\n'
  printf '  "typecheck_command": '; json_string "$TYPECHECK_CMD"; printf ',\n'
  printf '  "lint_command": '; json_string "$LINT_CMD"; printf ',\n'
  printf '  "format_command": '; json_string "$FORMAT_CMD"; printf ',\n'
  printf '  "ubs_available": %s,\n' "$UBS_AVAILABLE"
  printf '  "dcg_available": %s,\n' "$DCG_AVAILABLE"
  printf '  "pre_commit_hooks": ['
  for i in "${!PRE_COMMIT_HOOKS[@]}"; do
    [[ $i -gt 0 ]] && printf ', '
    json_string "${PRE_COMMIT_HOOKS[$i]}"
  done
  printf '],\n'
  printf '  "commit_message_convention": '; json_string "$COMMIT_CONVENTION"; printf ',\n'
  printf '  "stash_count": %s,\n' "$(git -C "$PROJECT_ABS" stash list 2>/dev/null | wc -l)"
  printf '  "stash_message_prefixes_top10": '; json_string "$STASH_PREFIXES"; printf '\n'
  printf '}\n'
} > "$OUT"

# --- Human summary ---
echo
echo "=== Project profile for $PROJECT_ABS ==="
echo "  primary_branch:           $PRIMARY_BRANCH"
echo "  test_command:             ${TEST_CMD:-<none>}"
echo "  typecheck_command:        ${TYPECHECK_CMD:-<none>}"
echo "  lint_command:             ${LINT_CMD:-<none>}"
echo "  format_command:           ${FORMAT_CMD:-<none>}"
echo "  ubs_available:            $UBS_AVAILABLE"
echo "  dcg_available:            $DCG_AVAILABLE"
echo "  pre_commit_hooks:         ${PRE_COMMIT_HOOKS[*]:-<none>}"
echo "  commit_convention:        $COMMIT_CONVENTION"
echo "  stash_count:              $(git -C "$PROJECT_ABS" stash list 2>/dev/null | wc -l)"
echo
echo "wrote $OUT"
