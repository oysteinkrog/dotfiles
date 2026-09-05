#!/usr/bin/env bash
# build-bundle.sh — Phase 3: build the recovery bundle for branches + worktrees.
#
# Layout produced (under <project-parent>/<basename>-branch-worktree-archive-<DATE>/):
#   refs/branch-rationalization-backup/<slug>      ← inside .git/, one per local branch
#   <bundle>/object-bundle.pack                    ← `git bundle create --all` over backup ns
#   <bundle>/branches/<slug>/commits.tsv
#   <bundle>/branches/<slug>/meta.txt
#   <bundle>/branches/<slug>/diff-vs-merge-base.diff
#   <bundle>/branches/<slug>/format-patch/0001-*.patch
#   <bundle>/worktrees/<sanitized-path>/staged.diff
#   <bundle>/worktrees/<sanitized-path>/unstaged.diff
#   <bundle>/worktrees/<sanitized-path>/status.txt
#   <bundle>/worktrees/<sanitized-path>/.untracked.list     ← NUL path manifest, only with untracked content
#   <bundle>/worktrees/<sanitized-path>/.untracked.sha256   ← NUL byte manifest, only with untracked content
#   <bundle>/worktrees/<sanitized-path>/untracked.tar.gz    ← only when untracked exists
#   <bundle>/worktrees/<sanitized-path>/meta.txt
#   <bundle>/index.tsv
#   <bundle>/README.md
#
# Followed by verify-bundle.sh.
#
# Resume-aware: if the bundle directory already has artifacts, refuse without
# explicit BUNDLE_REUSE_OK / BUNDLE_OVERRIDE / BUNDLE_REBUILD_IN_PLACE_OK.
#
# Exit codes:
#   0  bundle written
#   2  bundle already exists; no override
#   3  inventory missing
#   4  empty diff for a branch with files-changed > 0 (recovery payload missing)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: build-bundle.sh <project-path>

Phase 3 of the git-worktree-branch-rationalization skill. Materializes backup
refs, an object bundle, per-branch diffs/format-patch series, and per-worktree
dirty-state captures. Run verify-bundle.sh immediately after.

Env:
  WORKSPACE                       Override the workspace dir.
  BUNDLE_OVERRIDE                 Override the bundle directory path.
  BUNDLE_REUSE_OK=1               Reuse an existing non-empty bundle if it verifies.
  BUNDLE_REBUILD_IN_PLACE_OK=1    Overwrite an existing non-empty bundle (NOT recommended).

Exit codes:
  0  ok
  2  bundle already exists; refused (no override)
  3  inventory missing (run discover-branches-worktrees.sh first)
  4  empty recovery payload for a branch with diffstat > 0
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 3
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
PROFILE="$WORKSPACE_DIR/project_profile.json"

for f in "$BRANCHES_TSV" "$WORKTREES_TSV" "$PROFILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f missing — run prior phases first." >&2
    exit 3
  fi
done

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
  exit 3
fi

DATE_TAG=$(date -u +%Y-%m-%d)
BASENAME="$(basename "$PROJECT_ABS")"
PARENT="$(dirname "$PROJECT_ABS")"
BUNDLE="${BUNDLE_OVERRIDE:-$PARENT/${BASENAME}-branch-worktree-archive-${DATE_TAG}}"
VERIFY_SCRIPT="$SCRIPT_DIR/verify-bundle.sh"
BUNDLE_SHELL=$(printf '%q' "$BUNDLE")
PROJECT_ABS_SHELL=$(printf '%q' "$PROJECT_ABS")
VERIFY_SCRIPT_SHELL=$(printf '%q' "$VERIFY_SCRIPT")

if [[ -d "$BUNDLE" ]]; then
  existing_entry=$(find "$BUNDLE" -mindepth 1 -print -quit 2>/dev/null || true)
  if [[ -n "$existing_entry" ]]; then
    echo "$BUNDLE" > "$WORKSPACE_DIR/bundle_path.txt"
    if [[ -n "${BUNDLE_REUSE_OK:-}" ]]; then
      log "Existing bundle non-empty; verifying before reuse..."
      if "$VERIFY_SCRIPT" "$PROJECT_ABS"; then
        log "Existing bundle verifies; reusing without rewriting."
        exit 0
      fi
      echo "REFUSED: existing bundle does not verify against the current inventory." >&2
      exit 2
    fi
    if [[ -z "${BUNDLE_REBUILD_IN_PLACE_OK:-}" ]]; then
      echo "REFUSED: bundle directory already contains recovery artifacts:" >&2
      echo "  $BUNDLE" >&2
      echo "Choose one explicit path:" >&2
      echo "  BUNDLE_REUSE_OK=1 $0 \"$PROJECT_ABS\"             # verify and reuse only if byte-equal" >&2
      echo "  BUNDLE_OVERRIDE=<new-path> $0 \"$PROJECT_ABS\"    # create a fresh bundle" >&2
      echo "  BUNDLE_REBUILD_IN_PLACE_OK=1 $0 \"$PROJECT_ABS\"  # rebuild in place (NOT recommended)" >&2
      exit 2
    fi
    log "BUNDLE_REBUILD_IN_PLACE_OK=1; rebuilding in existing bundle."
  fi
fi

mkdir -p "$BUNDLE"/{branches,worktrees}
echo "$BUNDLE" > "$WORKSPACE_DIR/bundle_path.txt"

BACKUP_NS="refs/branch-rationalization-backup"

log "Creating backup refs for every local branch..."
declare -a BACKUP_REFS=()
while IFS= read -r br; do
  [[ -z "$br" ]] && continue
  slug=$(slugify_branch "$br")
  sha=$(git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$br^{commit}" 2>/dev/null || true)
  if [[ -z "$sha" ]]; then
    log "WARNING: branch $br does not resolve to a commit; skipping."
    continue
  fi
  git -C "$PROJECT_ABS" update-ref "$BACKUP_NS/$slug" "$sha"
  BACKUP_REFS+=("$BACKUP_NS/$slug")
done < <(git -C "$PROJECT_ABS" for-each-ref refs/heads --format='%(refname:lstrip=2)' 2>/dev/null)

# Object bundle. Span ALL backup refs in one pack so a single file recovers the
# whole namespace, including unreachable-from-canonical commits. We use
# `--all` scoped to the backup ns via a glob; falling back to enumerated refs
# if --all has issues with the scope.
log "Writing object-bundle.pack (this can take a moment on large repos)..."
PACK="$BUNDLE/object-bundle.pack"
if ((${#BACKUP_REFS[@]} > 0)); then
  # `git bundle create` accepts ref globs but not directly with --all; pass the
  # explicit ref list to guarantee determinism.
  git -C "$PROJECT_ABS" bundle create "$PACK" "${BACKUP_REFS[@]}" 2>&1 | sed 's/^/  /'
else
  log "No backup refs; skipping object bundle (empty pack would fail to create)."
fi

# ---- Per-branch artifacts ----
log "Writing per-branch artifacts..."
declare -a INDEX_ROWS=()

while IFS= read -r row; do
  name=""
  slug=""
  head_sha=""
  last_date=""
  author=""
  subject=""
  ahead=""
  behind=""
  commits_ahead=""
  cherry_plus=""
  cherry_minus=""
  upstream=""
  upstream_status=""
  wt_path=""
  touched=""
  insertions=""
  deletions=""
  files_changed=""
  age_days=""
  prefix=""
  tsv_read "$row" name slug head_sha last_date author subject ahead behind commits_ahead cherry_plus cherry_minus upstream upstream_status wt_path touched insertions deletions files_changed age_days prefix
  [[ "$name" == "name" ]] && continue
  [[ -z "$slug" ]] && continue
  branch_ref="refs/heads/$name"
  out_dir="$BUNDLE/branches/$slug"
  mkdir -p "$out_dir/format-patch"

  merge_base=$(git -C "$PROJECT_ABS" merge-base "$CANON_REF" "$branch_ref" 2>/dev/null || echo "")

  # commits.tsv — one row per commit not on canonical.
  {
    printf 'sha\tdate\tauthor\tsubject\n'
    if [[ -n "$merge_base" ]]; then
      git -C "$PROJECT_ABS" log --format='%H%x09%cI%x09%an%x09%s' "$merge_base..$branch_ref" 2>/dev/null || true
    fi
  } > "$out_dir/commits.tsv"

  # diff-vs-merge-base.diff — binary-safe full diff.
  if [[ -n "$merge_base" ]]; then
    git -C "$PROJECT_ABS" diff --binary "$merge_base" "$branch_ref" > "$out_dir/diff-vs-merge-base.diff" 2>/dev/null || true
  else
    : > "$out_dir/diff-vs-merge-base.diff"
  fi

  # If branches.tsv claims files_changed > 0 but the diff is empty, that's a
  # recovery-payload corruption — halt before destructive phases (Axiom 4).
  if [[ "${files_changed:-0}" -gt 0 ]] && [[ ! -s "$out_dir/diff-vs-merge-base.diff" ]]; then
    echo "ERROR: branch $name has files_changed=$files_changed but bundle diff is empty." >&2
    echo "  diff: $out_dir/diff-vs-merge-base.diff" >&2
    echo "  Recovery payload would be missing. Halting." >&2
    exit 4
  fi

  # format-patch series — one .patch per commit on the branch above merge-base.
  # Unlike git-stash-janitor (where format-patch is meaningless for stashes),
  # branches ARE normal commit chains and format-patch is part of the recovery
  # contract. Cross-linked in the README.
  if [[ -n "$merge_base" ]] && [[ "${commits_ahead:-0}" -gt 0 ]]; then
    git -C "$PROJECT_ABS" format-patch --binary "$merge_base..$branch_ref" -o "$out_dir/format-patch" >/dev/null 2>&1 || true
  fi

  # meta.txt
  {
    printf 'name=%s\n' "$name"
    printf 'slug=%s\n' "$slug"
    printf 'head_sha=%s\n' "$head_sha"
    printf 'merge_base=%s\n' "$merge_base"
    printf 'canonical=%s\n' "$CANONICAL"
    printf 'ahead=%s\n' "$ahead"
    printf 'behind=%s\n' "$behind"
    printf 'commits_ahead=%s\n' "$commits_ahead"
    printf 'cherry_plus=%s\n' "$cherry_plus"
    printf 'cherry_minus=%s\n' "$cherry_minus"
    printf 'upstream=%s\n' "$upstream"
    printf 'upstream_status=%s\n' "$upstream_status"
    printf 'last_date=%s\n' "$last_date"
    printf 'author=%s\n' "$author"
    printf 'subject=%s\n' "$subject"
    printf 'age_days=%s\n' "$age_days"
    printf 'worktree_path=%s\n' "$wt_path"
    printf 'touched_files=%s\n' "$touched"
    printf 'insertions=%s\n' "$insertions"
    printf 'deletions=%s\n' "$deletions"
    printf 'files_changed=%s\n' "$files_changed"
    printf 'prefix_family=%s\n' "$prefix"
  } > "$out_dir/meta.txt"

  branch_bundle_paths="branches/$slug/,branches/$slug/meta.txt,branches/$slug/commits.tsv,branches/$slug/diff-vs-merge-base.diff,branches/$slug/format-patch/"
  INDEX_ROWS+=("branch	$name	$slug	$head_sha	$merge_base	$ahead	$behind	triage-pending	false	unknown	$branch_bundle_paths")
done < "$BRANCHES_TSV"

# ---- Per-worktree artifacts ----
log "Writing per-worktree artifacts..."
while IFS= read -r row; do
  path=""
  branch=""
  detached=""
  bare=""
  locked=""
  prunable=""
  last_sha=""
  last_date=""
  dirty=""
  staged_size=""
  unstaged_size=""
  untracked_size=""
  untracked_count=""
  age_days=""
  inside_main=""
  active=""
  subm=""
  tsv_read "$row" path branch detached bare locked prunable last_sha last_date dirty staged_size unstaged_size untracked_size untracked_count age_days inside_main active subm
  [[ "$path" == "path" ]] && continue
  # Skip the bare "main" worktree if it's flagged that way.
  san=$(sanitize_path "$path")
  out_dir="$BUNDLE/worktrees/$san"
  mkdir -p "$out_dir"

  # status.txt
  if [[ -d "$path" ]]; then
    git -C "$path" status --porcelain=v2 --untracked-files=all > "$out_dir/status.txt" 2>/dev/null || true
  else
    echo "(worktree path not present at bundle time)" > "$out_dir/status.txt"
  fi

  # staged + unstaged diffs
  if [[ -d "$path" ]]; then
    git -C "$path" diff --binary --cached > "$out_dir/staged.diff"   2>/dev/null || true
    git -C "$path" diff --binary          > "$out_dir/unstaged.diff" 2>/dev/null || true
  else
    : > "$out_dir/staged.diff"
    : > "$out_dir/unstaged.diff"
  fi

  # untracked.tar.gz — only if there ARE untracked files.
  if [[ "$dirty" == "true" && "$untracked_count" -gt 0 && -d "$path" ]]; then
    untracked_out_dir="$(cd "$out_dir" && pwd -P)"
    untracked_list_file="$untracked_out_dir/.untracked.list"
    if git -C "$path" ls-files --others --exclude-standard -z | sort -z > "$untracked_list_file"; then
      if [[ -s "$untracked_list_file" ]]; then
        if ! write_untracked_content_manifest "$path" "$untracked_list_file" "$untracked_out_dir/.untracked.sha256"; then
          echo "ERROR: cannot hash untracked files for $path; recovery payload would be unverifiable." >&2
          exit 4
        fi
        if ! ( cd "$path" && tar --null -czf "$untracked_out_dir/untracked.tar.gz" -T "$untracked_list_file" ); then
          echo "ERROR: tar of untracked files for $path failed; recovery payload would be incomplete." >&2
          exit 4
        fi
      fi
    else
      echo "ERROR: cannot enumerate untracked files for $path; recovery payload would be incomplete." >&2
      exit 4
    fi
  fi

  # meta.txt
  {
    printf 'path=%s\n' "$path"
    printf 'branch=%s\n' "$branch"
    printf 'detached=%s\n' "$detached"
    printf 'bare=%s\n' "$bare"
    printf 'locked=%s\n' "$locked"
    printf 'prunable=%s\n' "$prunable"
    printf 'last_sha=%s\n' "$last_sha"
    printf 'last_date=%s\n' "$last_date"
    printf 'dirty=%s\n' "$dirty"
    printf 'staged_diff_lines=%s\n' "$staged_size"
    printf 'unstaged_diff_lines=%s\n' "$unstaged_size"
    printf 'untracked_total_bytes=%s\n' "$untracked_size"
    printf 'untracked_file_count=%s\n' "$untracked_count"
    printf 'age_days=%s\n' "$age_days"
    printf 'inside_main_repo=%s\n' "$inside_main"
    printf 'active_worktree=%s\n' "$active"
    printf 'submodules_initialized=%s\n' "$subm"
  } > "$out_dir/meta.txt"

  intake_protected=false
  [[ "$active" == "true" ]] && intake_protected=true
  worktree_bundle_paths="worktrees/$san/,worktrees/$san/meta.txt,worktrees/$san/status.txt,worktrees/$san/staged.diff,worktrees/$san/unstaged.diff"
  if [[ -f "$out_dir/.untracked.list" ]]; then
    worktree_bundle_paths="$worktree_bundle_paths,worktrees/$san/.untracked.list,worktrees/$san/.untracked.sha256,worktrees/$san/untracked.tar.gz"
  fi
  INDEX_ROWS+=("worktree	$path	$san	$last_sha	-	-	-	triage-pending	$intake_protected	unknown	$worktree_bundle_paths")
done < "$WORKTREES_TSV"

# ---- index.tsv ----
{
  printf 'kind\tname_or_path\tslug\thead_sha\tmerge_base\tahead\tbehind\tsmell\tintake_protected\tverdict\tbundle_paths\n'
  for row in "${INDEX_ROWS[@]}"; do
    printf '%s\n' "$row"
  done
} > "$BUNDLE/index.tsv"

# ---- README.md ----
N_BR=$(awk 'NR > 1' "$BRANCHES_TSV"  | wc -l)
N_WT=$(awk 'NR > 1' "$WORKTREES_TSV" | wc -l)

cat > "$BUNDLE/README.md" <<EOF
# Branch + Worktree Recovery Bundle (v1.0)

Project: $PROJECT_ABS
Canonical branch: $CANONICAL
Bundle path: $BUNDLE
Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Branches: $N_BR     Worktrees: $N_WT

This bundle is the recovery story for every local branch and every worktree
that existed at run start. Branches and worktrees are different objects with
different smells and different removal mechanics, but they share a single
recovery story (Axiom 0).

## What's here

### Branches

Each local branch has FIVE recovery layers:

1. \`refs/branch-rationalization-backup/<slug>\` — a permanent ref inside
   \`.git/refs/\`. Survives \`git branch -D\` and the reflog gc window.
2. \`object-bundle.pack\` — \`git bundle create\` over the entire backup
   namespace. Recoverable on any clone via \`git fetch <pack> <ref>\`.
3. \`branches/<slug>/diff-vs-merge-base.diff\` — \`git diff --binary
   <merge-base> <branch>\`. Applies via \`git apply --3way\` against any
   compatible base.
4. \`branches/<slug>/format-patch/0001-…patch\` — \`git format-patch
   <merge-base>..<branch>\`. **Unlike stash-janitor**, format-patch IS valid
   for branches: a branch is a normal commit chain. The patches preserve
   commit metadata (subject, author, date) and apply via \`git am\`.
5. \`branches/<slug>/meta.txt\` + \`branches/<slug>/commits.tsv\` — head SHA,
   merge-base, ahead/behind, cherry summary, per-commit log.

### Worktrees

Each worktree has FOUR recovery layers:

1. \`worktrees/<sanitized-path>/staged.diff\` — \`git diff --binary --cached\`
2. \`worktrees/<sanitized-path>/unstaged.diff\` — \`git diff --binary\`
3. \`worktrees/<sanitized-path>/.untracked.list\` + \`.untracked.sha256\` +
   \`untracked.tar.gz\` — only when untracked content existed. The manifests
   are NUL-delimited so unusual filenames can be restored exactly, and the
   sha256 manifest proves same-path untracked files did not drift before
   removal.
4. \`worktrees/<sanitized-path>/status.txt\` + \`meta.txt\` — porcelain v2
   snapshot + path/branch/locked/prunable/dirty flags.

## Recovery recipes

### Recover a deleted branch by backup ref

\`\`\`
# Slug = the slug column from index.tsv
git branch <new-name> ${BACKUP_NS}/<slug>
\`\`\`

### Recover from the object bundle (e.g., into a fresh clone)

\`\`\`
git fetch ${BUNDLE_SHELL}/object-bundle.pack \\
  '+${BACKUP_NS}/*:${BACKUP_NS}/*'
\`\`\`

### Apply a branch's full diff onto an arbitrary base

\`\`\`
git apply --3way --check ${BUNDLE_SHELL}/branches/<slug>/diff-vs-merge-base.diff
git apply --3way        ${BUNDLE_SHELL}/branches/<slug>/diff-vs-merge-base.diff
\`\`\`

### Replay a branch's commits via \`git am\` (preserves authorship)

\`\`\`
git am ${BUNDLE_SHELL}/branches/<slug>/format-patch/*.patch
\`\`\`

### Recover a worktree's dirty state

\`\`\`
# Re-create the worktree first if it was removed:
git worktree add <new-path> <branch-or-sha>

# Re-apply staged changes:
git -C <new-path> apply --3way --cached \\
  ${BUNDLE_SHELL}/worktrees/<sanitized>/staged.diff

# Re-apply unstaged changes:
git -C <new-path> apply --3way \\
  ${BUNDLE_SHELL}/worktrees/<sanitized>/unstaged.diff

# Re-create untracked files:
tar --null -xzf ${BUNDLE_SHELL}/worktrees/<sanitized>/untracked.tar.gz \\
  -C <new-path> \\
  -T ${BUNDLE_SHELL}/worktrees/<sanitized>/.untracked.list
\`\`\`

## ⚠ Footgun cross-link

If you used \`git-stash-janitor\` recently, you know that for stashes
\`git format-patch\` is **wrong** — a stash is a merge commit and format-patch
emits a tiny, unhelpful diff. **That rule does not generalize.** A branch
is a normal commit chain; format-patch is the canonical way to ship its
contents around. The \`branches/<slug>/format-patch/\` directory is part of
this bundle's recovery contract.

For worktree dirty state, the analogue is \`git diff --binary\` /
\`git diff --binary --cached\` — which DO work for worktrees because the
working tree is just a checkout, not a merge commit.

## Bundle integrity

Re-verify byte-equality:

\`\`\`
${VERIFY_SCRIPT_SHELL} ${PROJECT_ABS_SHELL}
\`\`\`

Re-list the object bundle's heads:

\`\`\`
git bundle list-heads ${BUNDLE_SHELL}/object-bundle.pack
\`\`\`

## Lifecycle

This bundle is yours to keep (Axiom 18). Recommended:
- Keep at least one release cycle (1–4 weeks).
- DCG blocks \`rm -rf\`; the skill will never touch this bundle.
- When you're sure nothing was missed, \`mv\` it to a trash location.

## Index

See \`index.tsv\` for the full per-entry index.
EOF

N_BACKUP_REFS=$(git -C "$PROJECT_ABS" for-each-ref "$BACKUP_NS/" 2>/dev/null | wc -l)

echo
echo "wrote bundle at $BUNDLE"
echo "  $N_BR branches   $N_WT worktree captures   $N_BACKUP_REFS backup refs"
[[ -f "$PACK" ]] && echo "  object bundle:  $(stat -c%s "$PACK" 2>/dev/null || echo ?) bytes"
echo
echo "Now run: $VERIFY_SCRIPT $PROJECT_ABS"
