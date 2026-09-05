#!/usr/bin/env bash
# harmonization-plan.sh — Phase 7: build the per-file variant matrix.
#
# For every file touched by ≥2 non-protected branches with verdict in
#   {novel-and-accretive, partially-novel, divergent-refactor, dirty-worktree-only}
# emit a row in <workspace>/harmonization_plan.md describing:
#   - file path
#   - canonical version key signatures (function names, type signatures)
#   - each contributing branch's variant (diff hunks summary)
#   - tests/fixtures touched by each variant
#   - identified intent of each variant
#     (defensive / refactor / test / fixture / type-narrowing /
#      error-handling / performance / naming)
#   - proposed best-of-all-worlds synthesis stub
#
# This script writes the PLAN ONLY. Synthesis Edits are performed by the main
# agent per AGENTS.md "No Script-Based Changes".
#
# Files touched by exactly one branch are skipped (no harmonization needed).
#
# Exit codes:
#   0  plan written (possibly with "no harmonization required")
#   2  triage.tsv missing

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: harmonization-plan.sh <project-path>

Phase 7. Builds the per-file variant matrix in <workspace>/harmonization_plan.md.

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  plan written
  2  triage.tsv or branches.tsv missing
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
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
PROFILE="$WORKSPACE_DIR/project_profile.json"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"

for f in "$TRIAGE" "$BRANCHES_TSV" "$PROFILE" "$BUNDLE_PATH_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f missing" >&2
    exit 2
  fi
done
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"
PLAN="$WORKSPACE_DIR/harmonization_plan.md"

profile_value() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg key "$key" '.[$key] // ""' "$PROFILE"
    return
  fi
  python3 - "$PROFILE" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f: data = json.load(f)
v = data.get(sys.argv[2], "")
if isinstance(v, bool): print("true" if v else "false")
elif v is None: print("")
else: print(v)
PY
}
CANONICAL=$(profile_value canonical_branch)
if git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/heads/$CANONICAL"
elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/remotes/origin/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/remotes/origin/$CANONICAL"
else
  echo "ERROR: canonical branch '$CANONICAL' does not resolve locally or as origin/$CANONICAL." >&2
  exit 2
fi

# ---- Build file → branches map for harmonization-eligible verdicts ----
HARMONIZE_VERDICTS_RE='^(novel-and-accretive|partially-novel|divergent-refactor|dirty-worktree-only)$'

# tmp file: path<TAB>branch_or_wt
TMP_FILE_BR="$WORKSPACE_DIR/.harmonization_file_branch.tmp"
: > "$TMP_FILE_BR"

while IFS= read -r row; do
  tsv_read "$row" kind name verdict conf strategy evidence files_touched
  [[ "$kind" == "kind" ]] && continue
  [[ -z "$kind" ]] && continue
  [[ "$verdict" =~ $HARMONIZE_VERDICTS_RE ]] || continue
  [[ -z "$files_touched" || "$files_touched" == "-" ]] && continue
  IFS=',' read -r -a files <<< "$files_touched"
  for f in "${files[@]}"; do
    [[ -z "$f" ]] && continue
    printf '%s\t%s\t%s\n' "$f" "$kind:$name" "$verdict" >> "$TMP_FILE_BR"
  done
done < "$TRIAGE"

# Group by file; keep only files with ≥2 distinct branch entries.
COLLISIONS_TSV="$WORKSPACE_DIR/.harmonization_collisions.tmp"
sort "$TMP_FILE_BR" | awk -F'\t' '
{
  files[$1] = files[$1] $2 "|" $3 ";"
  branches[$1 SUBSEP $2] = 1
}
END {
  for (f in files) {
    n = 0
    for (b in branches) {
      split(b, parts, SUBSEP)
      if (parts[1] == f) n++
    }
    if (n >= 2) {
      printf "%s\t%d\t%s\n", f, n, files[f]
    }
  }
}' | sort > "$COLLISIONS_TSV"

N_COLLISIONS=$(wc -l < "$COLLISIONS_TSV" || echo 0)

# ---- Helpers for variant analysis ----

# Look up a branch's slug from branches.tsv.
branch_slug() {
  awk -F'\t' -v n="$1" 'NR > 1 && $1 == n {print $2; exit}' "$BRANCHES_TSV"
}

# Extract hunks touching a specific file from a unified diff.
hunks_for_file() {
  local diff="$1" file="$2"
  awk -v f="$file" '
    /^diff --git a\// {
      in_block = 0
      sub(/^diff --git a\//, "", $0)
      split($0, parts, " b/")
      if (parts[1] == f) in_block = 1
    }
    in_block { print }
  ' "$diff"
}

# Heuristic intent classifier from a hunk subset.
classify_intent() {
  local hunks="$1"
  # Quick keyword counts.
  local n_assert n_test n_type n_err n_perf n_def n_rename
  n_test=$(printf  '%s' "$hunks" | grep -cE '^\+.*\b(test|assert|expect|describe|it\()' || true)
  n_def=$(printf   '%s' "$hunks" | grep -cE '^\+.*\b(if[ \t]+[^=]+(==|!=|is None|is null|is_none))' || true)
  n_type=$(printf  '%s' "$hunks" | grep -cE '^\+.*\b(:[ \t]*[A-Z][A-Za-z0-9_<>,]*|->[ \t]*[A-Z]|Optional|Result|Vec)' || true)
  n_err=$(printf   '%s' "$hunks" | grep -cE '^\+.*\b(try|except|catch|raise|throw|panic|Err\(|Result|errors\.New|fmt\.Errorf)' || true)
  n_perf=$(printf  '%s' "$hunks" | grep -cE '^\+.*\b(cache|memoize|lazy|parallel|async|await|select!|spawn)' || true)
  n_rename=$(printf '%s' "$hunks" | grep -cE '^(rename from |rename to )' || true)
  n_assert=$(printf '%s' "$hunks" | grep -cE '^\+.*\b(assert|debug_assert|invariant|ensure|require)' || true)

  # Pick the highest-signal label; tie-break by category importance.
  local best=naming best_score=0
  if [[ "$n_test" -gt "$best_score" ]]; then best="test"; best_score=$n_test; fi
  if [[ "$n_def" -gt "$best_score" ]]; then best="defensive"; best_score=$n_def; fi
  if [[ "$n_err" -gt "$best_score" ]]; then best="error-handling"; best_score=$n_err; fi
  if [[ "$n_type" -gt "$best_score" ]]; then best="type-narrowing"; best_score=$n_type; fi
  if [[ "$n_perf" -gt "$best_score" ]]; then best="performance"; best_score=$n_perf; fi
  if [[ "$n_assert" -gt "$best_score" ]]; then best="defensive"; best_score=$n_assert; fi
  if [[ "$n_rename" -gt 0 ]]; then best="refactor"; fi
  if [[ "$best_score" -eq 0 && "$n_rename" -eq 0 ]]; then best="refactor"; fi
  printf '%s' "$best"
}

# Extract the canonical version's signature lines for a file (ast-grep would be
# nicer but we keep dependencies minimal — plain grep for `^(fn|def|class|type|struct|...)`).
canonical_signatures() {
  local file="$1"
  if ! git -C "$PROJECT_ABS" cat-file -e "$CANON_REF:$file" 2>/dev/null; then
    echo "(file not on canonical)"
    return
  fi
  git -C "$PROJECT_ABS" show "$CANON_REF:$file" 2>/dev/null \
    | grep -nE '^\s*(pub\s+)?(fn|def|function|class|struct|enum|trait|interface|type|const|impl|module)\b' \
    | head -10 || true
}

# ---- Emit harmonization_plan.md ----
{
  printf '# Harmonization plan (Phase 7)\n\n'
  printf '_Project: %s_\n' "$PROJECT_ABS"
  printf '_Canonical: %s_\n' "$CANONICAL"
  printf '_Generated: %s_\n\n' "$(date -u +%FT%TZ)"

  if [[ "$N_COLLISIONS" -eq 0 ]]; then
    printf '## No harmonization required\n\n'
    printf 'No files are touched by ≥2 non-protected branches with harmonization-eligible verdicts.\n'
    printf 'Phase 8 may proceed with straightforward apply strategies (cherry-pick / squash-merge / rebase-and-merge / dirty-worktree-only).\n'
    exit 0
  fi

  printf 'This plan covers **%s files** touched by ≥2 non-protected branches.\n' "$N_COLLISIONS"
  printf 'For each file: canonical signature anchors, per-branch variant analysis, identified intent, and a synthesis stub.\n\n'
  printf '> **The synthesis is performed by the main agent via the Edit tool.** This script provides the variant matrix; '
  printf 'the main agent reads it and authors the final code (per AGENTS.md "No Script-Based Changes").\n\n'

  printf '## Intent legend\n\n'
  printf '| label | meaning |\n'
  printf '|-------|---------|\n'
  printf '| defensive       | adds null-/bounds-/error-checks |\n'
  printf '| refactor        | restructures without semantic change |\n'
  printf '| test            | adds or modifies tests/assertions |\n'
  printf '| fixture         | adds or modifies test fixtures |\n'
  printf '| type-narrowing  | tightens types or signatures |\n'
  printf '| error-handling  | adds error propagation/wrapping |\n'
  printf '| performance     | adds caching/lazy/parallel changes |\n'
  printf '| naming          | renames or rephrases identifiers |\n\n'

  printf '## Per-file variant matrices\n\n'
} > "$PLAN"

# Per-file emit loop.
while IFS= read -r row; do
  file=""; n_branches=""; branch_list=""
  tsv_read "$row" file n_branches branch_list
  {
    printf '### `%s`\n\n' "$file"
    printf '_%s contributing entries._\n\n' "$n_branches"

    printf '#### Canonical anchors (top 10 signatures from `%s:%s`)\n\n' "$CANON_REF" "$file"
    printf '```\n'
    canonical_signatures "$file"
    printf '```\n\n'

    printf '#### Variant matrix\n\n'
    printf '| source | verdict | intent | hunks (lines added) |\n'
    printf '|--------|---------|--------|---------------------|\n'
  } >> "$PLAN"

  # Iterate the entries in branch_list (semicolon-separated kind:name|verdict).
  IFS=';' read -r -a entries <<< "${branch_list%;}"
  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue
    src="${entry%|*}"     # e.g. "branch:feature/foo"
    verdict="${entry#*|}"
    kind="${src%%:*}"
    name="${src#*:}"

    diff_path=""
    if [[ "$kind" == "branch" ]]; then
      slug=$(branch_slug "$name")
      [[ -n "$slug" ]] && diff_path="$BUNDLE/branches/$slug/diff-vs-merge-base.diff"
    elif [[ "$kind" == "worktree" ]]; then
      san=$(sanitize_path "$name")
      # Worktree dirty state lives in two diffs; merge them for the analysis.
      diff_path="$BUNDLE/worktrees/$san/staged.diff"
      if [[ -f "$BUNDLE/worktrees/$san/unstaged.diff" ]]; then
        cat_path="$WORKSPACE_DIR/.harmon_${san}.diff"
        cat "$BUNDLE/worktrees/$san/staged.diff" "$BUNDLE/worktrees/$san/unstaged.diff" 2>/dev/null > "$cat_path" || true
        diff_path="$cat_path"
      fi
    fi

    intent=unknown
    n_added=0
    if [[ -n "$diff_path" && -f "$diff_path" ]]; then
      hunks=$(hunks_for_file "$diff_path" "$file")
      if [[ -n "$hunks" ]]; then
        intent=$(classify_intent "$hunks")
        n_added=$(printf '%s\n' "$hunks" | grep -c '^+' || true)
      fi
    fi

    # Markdown-escape pipes/backticks in the source name.
    src_md=$(printf '%s' "$src" | sed 's/|/\\|/g; s/`/\\`/g')
    printf '| %s | %s | %s | %s |\n' "$src_md" "$verdict" "$intent" "$n_added" >> "$PLAN"
  done

  {
    printf '\n#### Synthesis stub\n\n'
    printf 'The main agent will Edit `%s` on the rationalization branch to combine:\n' "$file"
    printf -- '- canonical structure as the base\n'
    printf -- '- the strongest contribution from each variant grouped by intent above\n\n'
    printf 'Strategy hints:\n'
    printf -- '- defensive checks → keep the most-paranoid superset\n'
    printf -- '- type-narrowing → adopt the most precise type signature\n'
    printf -- '- error-handling → unify on canonical error type if compatible\n'
    printf -- '- test/fixture additions → keep all (no fixture is harmful)\n'
    printf -- '- refactor/naming → defer to canonical naming unless a variant introduces a new public API\n\n'
    printf '_When synthesis lands, file the apply commit message:_\n'
    printf '`harmonize <file> from <kind>:<name>+<kind>:<name>+... — <intent-summary>`\n\n'
    printf -- '---\n\n'
  } >> "$PLAN"
done < "$COLLISIONS_TSV"

# Final pointer.
{
  printf '## Next step\n\n'
  printf 'Review the synthesis plan above. When ready, type `harmonize` to authorize Phase 8 to proceed.\n'
  printf 'The main agent will perform the syntheses via the Edit tool, run gates per apply, and commit each file as a focused harmonized commit on `branch-rationalization-<DATE>`.\n'
} >> "$PLAN"

echo "wrote $PLAN ($N_COLLISIONS files)"
