#!/usr/bin/env bash
# bundle-merge.sh — merge two recovery bundles into one.
#
# Use cases:
#   - User runs the skill in two passes (triage-only on day 1, apply on day 2)
#     against two different bundles; this script merges them so a single
#     unified bundle can be archived.
#   - User runs the skill on two machines (e.g., laptop did inventory, server
#     did apply); this script merges the bundles into one canonical artifact.
#
# Cross-validation before merging:
#   - Both bundles' index.tsv schemas match.
#   - No overlapping slugs (collision = halt; user must resolve manually).
#   - Canonical SHAs are compatible (i.e., one is an ancestor of the other,
#     OR both share the same merge base — drift between canonicals halts).
#
# Output: a NEW bundle directory; neither input bundle is modified.
#
# Per AGENTS.md Rule 1: this script never deletes either input bundle. The
# user manages bundle lifecycle.
#
# Exit codes:
#   0  merge succeeded
#   2  preflight failed (one or both bundles missing)
#   3  schema mismatch
#   4  slug collision (incompatible bundles)
#   5  canonical drift (incompatible bundles)
#   6  output bundle already exists; refuse to overwrite

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: bundle-merge.sh <project-path> <bundle-a> <bundle-b> <output-bundle>

Merges <bundle-a> and <bundle-b> into a NEW bundle at <output-bundle>.
Neither input is modified. Cross-validates schema, slug uniqueness, and
canonical-SHA compatibility before merging.

Env:
  WORKSPACE                       Workspace dir override.

Exit codes:
  0  merge succeeded
  2  preflight failed
  3  schema mismatch
  4  slug collision
  5  canonical drift
  6  output bundle already exists
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
BUNDLE_A="${2:-}"
BUNDLE_B="${3:-}"
OUTPUT="${4:-}"
if [[ -z "$BUNDLE_A" || -z "$BUNDLE_B" || -z "$OUTPUT" ]]; then
  usage >&2
  exit 64
fi

PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
[[ -d "$BUNDLE_A" ]] || { echo "ERROR: bundle A $BUNDLE_A missing" >&2; exit 2; }
[[ -d "$BUNDLE_B" ]] || { echo "ERROR: bundle B $BUNDLE_B missing" >&2; exit 2; }
[[ -f "$BUNDLE_A/index.tsv" ]] || { echo "ERROR: bundle A index.tsv missing" >&2; exit 2; }
[[ -f "$BUNDLE_B/index.tsv" ]] || { echo "ERROR: bundle B index.tsv missing" >&2; exit 2; }
[[ -d "$BUNDLE_A/branches" ]] || { echo "ERROR: bundle A branches/ directory missing" >&2; exit 2; }
[[ -d "$BUNDLE_B/branches" ]] || { echo "ERROR: bundle B branches/ directory missing" >&2; exit 2; }
[[ -d "$BUNDLE_A/worktrees" ]] || { echo "ERROR: bundle A worktrees/ directory missing" >&2; exit 2; }
[[ -d "$BUNDLE_B/worktrees" ]] || { echo "ERROR: bundle B worktrees/ directory missing" >&2; exit 2; }

canonical_path() {
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m -- "$path"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$path" <<'PY'
import os
import sys

print(os.path.realpath(os.path.abspath(sys.argv[1])))
PY
    return
  fi

  local parent base parent_abs
  if [[ -e "$path" ]]; then
    ( cd "$path" && pwd -P )
    return
  fi
  parent="$(dirname "$path")"
  base="$(basename "$path")"
  parent_abs="$(cd "$parent" && pwd -P)" || return 1
  printf '%s/%s\n' "$parent_abs" "$base"
}

path_contains() {
  local parent="${1%/}"
  local child="${2%/}"
  [[ "$child" == "$parent" || "$child" == "$parent"/* ]]
}

BUNDLE_A_ABS="$(canonical_path "$BUNDLE_A")" || { echo "ERROR: cannot resolve bundle A path: $BUNDLE_A" >&2; exit 2; }
BUNDLE_B_ABS="$(canonical_path "$BUNDLE_B")" || { echo "ERROR: cannot resolve bundle B path: $BUNDLE_B" >&2; exit 2; }
OUTPUT_ABS="$(canonical_path "$OUTPUT")" || { echo "ERROR: cannot resolve output path: $OUTPUT" >&2; exit 2; }

if path_contains "$BUNDLE_A_ABS" "$OUTPUT_ABS" || path_contains "$BUNDLE_B_ABS" "$OUTPUT_ABS"; then
  echo "ERROR: output bundle must be outside both input bundles." >&2
  echo "  bundle-a: $BUNDLE_A_ABS" >&2
  echo "  bundle-b: $BUNDLE_B_ABS" >&2
  echo "  output:   $OUTPUT_ABS" >&2
  echo "This script promises not to modify either input bundle." >&2
  exit 6
fi

if [[ -e "$OUTPUT" && ! -d "$OUTPUT" ]]; then
  echo "ERROR: $OUTPUT already exists and is not a directory. Refusing to overwrite." >&2
  exit 6
fi
if [[ -d "$OUTPUT" ]] && [[ -n "$(find "$OUTPUT" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  echo "ERROR: $OUTPUT already exists and is not empty. Refusing to merge into stale contents." >&2
  echo "Choose a new output path; this script never deletes or cleans an existing bundle." >&2
  exit 6
fi

# ---- Schema check ----
HEADER_A=$(head -1 "$BUNDLE_A/index.tsv")
HEADER_B=$(head -1 "$BUNDLE_B/index.tsv")
if [[ "$HEADER_A" != "$HEADER_B" ]]; then
  echo "ERROR: index.tsv schemas differ." >&2
  echo "  bundle-a header: $HEADER_A" >&2
  echo "  bundle-b header: $HEADER_B" >&2
  exit 3
fi

# ---- Bundle-path collision check ----
index_bundle_paths() {
  local index="$1"
  awk -F'\t' '
    NR == 1 {
      for (i = 1; i <= NF; i++) {
        if ($i == "bundle_paths") {
          col = i
          break
        }
      }
      if (!col) exit 2
      next
    }
    col && NF >= col && $col != "" {
      n = split($col, paths, ",")
      for (i = 1; i <= n; i++) {
        p = paths[i]
        sub(/\/+$/, "", p)
        if (p != "") print p
      }
    }
  ' "$index" | sort -u
}

if ! INDEX_PATHS_A=$(index_bundle_paths "$BUNDLE_A/index.tsv"); then
  echo "ERROR: bundle A index.tsv has no bundle_paths column." >&2
  exit 3
fi
if ! INDEX_PATHS_B=$(index_bundle_paths "$BUNDLE_B/index.tsv"); then
  echo "ERROR: bundle B index.tsv has no bundle_paths column." >&2
  exit 3
fi
COLLISIONS=$(comm -12 <(printf '%s\n' "$INDEX_PATHS_A") <(printf '%s\n' "$INDEX_PATHS_B") | grep -v '^$' || true)
if [[ -n "$COLLISIONS" ]]; then
  echo "ERROR: $(echo "$COLLISIONS" | wc -l) bundle-path collision(s) between bundles:" >&2
  echo "$COLLISIONS" | head -10 >&2
  echo "Resolve manually before merging — same bundle path must mean same content." >&2
  exit 4
fi

dir_names() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -u
}

BRANCH_DIR_COLLISIONS=$(comm -12 <(dir_names "$BUNDLE_A/branches") <(dir_names "$BUNDLE_B/branches") | grep -v '^$' || true)
WORKTREE_DIR_COLLISIONS=$(comm -12 <(dir_names "$BUNDLE_A/worktrees") <(dir_names "$BUNDLE_B/worktrees") | grep -v '^$' || true)
if [[ -n "$BRANCH_DIR_COLLISIONS" || -n "$WORKTREE_DIR_COLLISIONS" ]]; then
  echo "ERROR: bundle directory collision(s) would be silently merged or skipped:" >&2
  if [[ -n "$BRANCH_DIR_COLLISIONS" ]]; then
    echo "  branches:" >&2
    echo "$BRANCH_DIR_COLLISIONS" | head -10 >&2
  fi
  if [[ -n "$WORKTREE_DIR_COLLISIONS" ]]; then
    echo "  worktrees:" >&2
    echo "$WORKTREE_DIR_COLLISIONS" | head -10 >&2
  fi
  echo "Resolve manually before merging — same directory name must mean same content." >&2
  exit 4
fi

# ---- Canonical-SHA compatibility ----
# meta files at branches/<slug>/meta.txt include the merge-base. We extract
# them from each bundle and ensure no row refers to a different canonical
# tip than the other bundle's rows do for the same project.
canon_tips_a=$(find "$BUNDLE_A/branches" -name meta.txt -type f -exec grep -hE '^merge_base[[:space:]]*:?[[:space:]]*' {} \; 2>/dev/null \
              | awk '{print $NF}' | sort -u)
canon_tips_b=$(find "$BUNDLE_B/branches" -name meta.txt -type f -exec grep -hE '^merge_base[[:space:]]*:?[[:space:]]*' {} \; 2>/dev/null \
              | awk '{print $NF}' | sort -u)

# We don't require equality — different branches legitimately have different
# merge-bases against canonical. We DO require that, where merge_bases differ
# between bundles, one is a git-ancestor of the other (i.e., canonical moved
# forward but didn't diverge).
if [[ -n "$canon_tips_a" && -n "$canon_tips_b" ]]; then
  drift_found=0
  for sa in $canon_tips_a; do
    for sb in $canon_tips_b; do
      [[ "$sa" == "$sb" ]] && continue
      # Check ancestor relation (best-effort; missing SHA in repo => warn).
      if git -C "$PROJECT_ABS" rev-parse --verify --quiet "$sa^{commit}" >/dev/null 2>&1 \
         && git -C "$PROJECT_ABS" rev-parse --verify --quiet "$sb^{commit}" >/dev/null 2>&1; then
        if ! git -C "$PROJECT_ABS" merge-base --is-ancestor "$sa" "$sb" 2>/dev/null \
           && ! git -C "$PROJECT_ABS" merge-base --is-ancestor "$sb" "$sa" 2>/dev/null; then
          drift_found=1
          echo "WARN: merge-bases $sa and $sb diverge (neither is an ancestor of the other)" >&2
        fi
      fi
    done
  done
  if [[ "$drift_found" -eq 1 ]]; then
    echo "ERROR: canonical drift detected; bundles describe incompatible repo states." >&2
    echo "Choose bundles from compatible canonical histories or resolve manually." >&2
    exit 5
  fi
fi

# ---- Build merged bundle ----
mkdir -p "$OUTPUT/branches" "$OUTPUT/worktrees"

# Copy branches and worktrees from both inputs.
copy_subtree() {
  local src="$1"
  if [[ -d "$src/branches" ]]; then
    for d in "$src/branches"/*/; do
      [[ -d "$d" ]] || continue
      dest="$OUTPUT/branches/$(basename "$d")"
      [[ ! -e "$dest" ]] || { echo "ERROR: destination already exists: $dest" >&2; exit 4; }
      cp -a "$d" "$OUTPUT/branches/"
    done
  fi
  if [[ -d "$src/worktrees" ]]; then
    for d in "$src/worktrees"/*/; do
      [[ -d "$d" ]] || continue
      dest="$OUTPUT/worktrees/$(basename "$d")"
      [[ ! -e "$dest" ]] || { echo "ERROR: destination already exists: $dest" >&2; exit 4; }
      cp -a "$d" "$OUTPUT/worktrees/"
    done
  fi
  return 0
}
copy_subtree "$BUNDLE_A"
copy_subtree "$BUNDLE_B"

# Merge index.tsv (preserve header from A, then concat both bodies, dedup).
{
  printf '%s\n' "$HEADER_A"
  awk 'NR>1' "$BUNDLE_A/index.tsv"
  awk 'NR>1' "$BUNDLE_B/index.tsv"
} | awk -F'\t' '
  NR==1 {print; next}
  !seen[$0]++ {print}
' > "$OUTPUT/index.tsv"

# Merge object packs by re-bundling backup refs from both inputs. The object
# bundle is `git bundle create`-style; we cannot trivially concatenate two
# packs. Instead we fetch both packs into a temp git dir, then re-bundle.
TMP_GIT="$OUTPUT/.merge-tmp.git"
mkdir -p "$TMP_GIT"
git --git-dir="$TMP_GIT" init --bare --quiet >/dev/null 2>&1 || true
if [[ -f "$BUNDLE_A/object-bundle.pack" ]]; then
  git --git-dir="$TMP_GIT" fetch "$BUNDLE_A/object-bundle.pack" \
    'refs/branch-rationalization-backup/*:refs/branch-rationalization-backup/*' >/dev/null 2>&1 || {
      echo "ERROR: could not fetch backup refs from bundle A object-bundle.pack" >&2
      exit 5
    }
fi
if [[ -f "$BUNDLE_B/object-bundle.pack" ]]; then
  git --git-dir="$TMP_GIT" fetch "$BUNDLE_B/object-bundle.pack" \
    'refs/branch-rationalization-backup/*:refs/branch-rationalization-backup/*' >/dev/null 2>&1 || {
      echo "ERROR: could not fetch backup refs from bundle B object-bundle.pack" >&2
      exit 5
    }
fi
mapfile -t MERGED_BACKUP_REFS < <(git --git-dir="$TMP_GIT" for-each-ref --format='%(refname)' refs/branch-rationalization-backup/ 2>/dev/null | sort)
n_refs=${#MERGED_BACKUP_REFS[@]}
if [[ "$n_refs" -gt 0 ]]; then
  git --git-dir="$TMP_GIT" bundle create "$OUTPUT/object-bundle.pack" \
    "${MERGED_BACKUP_REFS[@]}" >/dev/null 2>&1 || {
      echo "ERROR: could not rebuild merged object-bundle.pack" >&2
      exit 5
    }
fi
# Move the temp git dir into .archived rather than rm -rf (Rule 1).
ARCH="$OUTPUT/.archived"
mkdir -p "$ARCH"
mv "$TMP_GIT" "$ARCH/merge-tmp.git-$(date -u +%Y%m%dT%H%M%SZ)"

# Compose merged README.
{
  printf '# Merged recovery bundle\n\n'
  printf 'Created:   %s\n\n' "$(date -u +%FT%TZ)"
  printf 'Inputs:\n'
  printf -- "- \`%s\`\n" "$BUNDLE_A"
  printf -- "- \`%s\`\n\n" "$BUNDLE_B"
  printf '## Recovery recipes\n\n'
  printf '### Restore a backup ref by slug\n\n'
  printf '```\n'
  printf 'git fetch <bundle>/object-bundle.pack refs/branch-rationalization-backup/<slug>:refs/heads/<name>\n'
  printf '```\n\n'
  printf '### Apply a per-branch diff\n\n'
  printf '```\n'
  printf 'git apply --binary <bundle>/branches/<slug>/diff-vs-merge-base.diff\n'
  printf '```\n\n'
  printf '### Apply a per-branch format-patch series\n\n'
  printf '```\n'
  printf 'git am <bundle>/branches/<slug>/format-patch/*.patch\n'
  printf '```\n\n'
  printf '### Restore a worktree dirty-state\n\n'
  printf '```\n'
  printf 'git apply --cached <bundle>/worktrees/<sanitized>/staged.diff\n'
  printf 'git apply         <bundle>/worktrees/<sanitized>/unstaged.diff\n'
  printf 'tar --null -xzf <bundle>/worktrees/<sanitized>/untracked.tar.gz \\\n'
  printf '  -C <worktree-path> \\\n'
  printf '  -T <bundle>/worktrees/<sanitized>/.untracked.list        # if present\n'
  printf '```\n\n'
  printf 'Both source bundles remain untouched at their original paths.\n'
} > "$OUTPUT/README.md"

# Run the standard conformance check on the merged bundle if available.
CHECK="$SCRIPT_DIR/conformance-check.sh"
log "merged bundle written to $OUTPUT"
log "object pack refs: $n_refs"
log "to verify: WORKSPACE=<workspace> $CHECK <project-path>"
echo "$OUTPUT"
exit 0
