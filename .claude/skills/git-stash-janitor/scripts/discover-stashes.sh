#!/usr/bin/env bash
# discover-stashes.sh — Phase 2: list every stash with metadata; group by family.
#
# Output:
#   <project>/.stash_janitor_workspace/inventory.tsv
#   <project>/.stash_janitor_workspace/inventory_grouped.md

set -euo pipefail

PROJECT="${1:?Usage: discover-stashes.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

# Refuse to run on a non-git directory. Without this check, discover-stashes
# silently creates an empty .stash_janitor_workspace + inventory.tsv (header
# only, no rows), and the rest of the pipeline runs to completion on empty
# data — giving the user a misleading "successful" run that did nothing.
PROJECT_ABS="$(resolve_project_root "$PROJECT")"

WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
mkdir -p "$WORKSPACE"

INVENTORY_TSV="$WORKSPACE/inventory.tsv"
INVENTORY_MD="$WORKSPACE/inventory_grouped.md"

# Header
printf 'n\tref\tsha\tparent_sha\tdate\tauthor\tmessage\tfiles\tinsertions\tdeletions\thas_untracked\n' > "$INVENTORY_TSV"

STASH_COUNT=$(git -C "$PROJECT_ABS" stash list 2>/dev/null | wc -l)

if [[ "$STASH_COUNT" -eq 0 ]]; then
  echo "No stashes; inventory empty."
  printf '# Stash inventory\n\nNo stashes found.\n' > "$INVENTORY_MD"
  exit 0
fi

# Iterate each stash
git -C "$PROJECT_ABS" stash list --format='%gd|%H|%P|%ci|%an|%s' 2>/dev/null \
| while IFS='|' read -r ref sha parents ci_date author message; do
  # Extract n from ref (e.g., "stash@{34}" -> 34)
  n=$(printf '%s' "$ref" | sed -E 's/^stash@\{([0-9]+)\}$/\1/')
  parent_sha=$(printf '%s' "$parents" | awk '{print $1}')

  # Shortstat. Untracked-only stashes legitimately have no tracked stat line;
  # default them to 0/0/0 instead of letting `read` trip set -e and skip the row.
  stat_values=$(
    git -C "$PROJECT_ABS" stash show --stat "$ref" 2>/dev/null \
    | tail -1 \
    | awk -F'[, ]+' '{
        ins=0; del=0; f=0;
        for (i=1; i<=NF; i++) {
          if ($i == "insertions(+)" || $i == "insertion(+)") ins=$(i-1);
          if ($i == "deletions(-)" || $i == "deletion(-)") del=$(i-1);
          if ($i == "files" || $i == "file") f=$(i-1);
        }
        print ins, del, f
      }'
  )
  read -r insertions deletions files <<< "${stat_values:-0 0 0}"

  # Untracked detection (third parent)
  has_untracked=false
  if git -C "$PROJECT_ABS" rev-parse "${ref}^3" >/dev/null 2>&1; then
    has_untracked=true
  fi

  # Strip git-added "WIP on <branch>: <sha> " or "On <branch>: " prefix to leave
  # only the user's stash message. Sanitize tabs/newlines.
  message_clean=$(printf '%s' "$message" \
                    | sed -E 's/^WIP on [^:]+: [0-9a-f]+ //; s/^On [^:]+: //' \
                    | tr '\t\n' '  ')

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$n" "$ref" "$sha" "$parent_sha" "$ci_date" "$author" "$message_clean" \
    "$files" "$insertions" "$deletions" "$has_untracked" >> "$INVENTORY_TSV"
done

# Generate grouped markdown
{
  echo "# Stash inventory (grouped by message-prefix family)"
  echo
  echo "Total stashes: $STASH_COUNT"
  echo

  # Extract message prefix per row, group, count
  awk -F'\t' 'NR > 1 {
    msg = $7
    sub(/^WIP on [^:]+: [0-9a-f]+ /, "", msg)
    # First "word" prefix (alpha-num + dash, up to first colon/space)
    if (match(msg, /^[a-zA-Z0-9_-]+/)) {
      prefix = substr(msg, RSTART, RLENGTH)
    } else {
      prefix = "<no-prefix>"
    }
    rows[prefix] = rows[prefix] sprintf("- stash@{%s}: %s (%s)\n", $1, msg, substr($5, 1, 10))
    counts[prefix]++
  }
  END {
    PROCINFO["sorted_in"] = "@val_num_desc"
    for (p in counts) {
      printf "## `%s` (%d stashes)\n\n", p, counts[p]
      printf "%s\n", rows[p]
    }
  }' "$INVENTORY_TSV"
} > "$INVENTORY_MD"

echo "wrote $INVENTORY_TSV ($STASH_COUNT stashes)"
echo "wrote $INVENTORY_MD"
