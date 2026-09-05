#!/usr/bin/env bash
# build-bundle.sh — Phase 3: create the recovery bundle with backup refs,
# diffs, meta files, untracked-files materialization, index, and README.
#
# Output:
#   refs/stash-backup/<NNN> for each stash
#   <bundle>/diffs/<NNN>.diff
#   <bundle>/meta/<NNN>.txt
#   <bundle>/stashed-untracked/<NNN>/ (only when stash had -u)
#   <bundle>/index.tsv
#   <bundle>/README.md
#
# Followed by verify-bundle.sh.

set -euo pipefail

PROJECT="${1:?Usage: build-bundle.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
INVENTORY="$WORKSPACE/inventory.tsv"

if [[ ! -f "$INVENTORY" ]]; then
  echo "ERROR: inventory not found at $INVENTORY" >&2
  echo "Run discover-stashes.sh first." >&2
  exit 1
fi

DATE_TAG=$(date -u +%Y-%m-%d)
BASENAME="$(basename "$PROJECT_ABS")"
PARENT="$(dirname "$PROJECT_ABS")"
BUNDLE="${BUNDLE_OVERRIDE:-$PARENT/${BASENAME}-stash-archive-${DATE_TAG}}"
BUNDLE_SHELL=$(printf '%q' "$BUNDLE")
PROJECT_ABS_SHELL=$(printf '%q' "$PROJECT_ABS")
VERIFY_SCRIPT="$SCRIPT_DIR/verify-bundle.sh"
VERIFY_SCRIPT_SHELL=$(printf '%q' "$VERIFY_SCRIPT")

if [[ -d "$BUNDLE" ]]; then
  existing_entry=$(find "$BUNDLE" -mindepth 1 -print -quit 2>/dev/null || true)
  if [[ -n "$existing_entry" ]]; then
    echo "$BUNDLE" > "$WORKSPACE/bundle_path.txt"

    if [[ -n "${BUNDLE_REUSE_OK:-}" ]]; then
      echo "Existing bundle directory is non-empty: $BUNDLE"
      echo "Verifying current artifacts before reuse..."
      if "$SCRIPT_DIR/verify-bundle.sh" "$PROJECT_ABS"; then
        echo "Existing bundle matches the current inventory; reusing without rewriting artifacts."
        exit 0
      fi
      echo "REFUSED: existing bundle does not verify against the current inventory." >&2
      echo "Use BUNDLE_OVERRIDE=<new-path> for a fresh bundle, or inspect the mismatch." >&2
      exit 2
    fi

    if [[ -z "${BUNDLE_REBUILD_IN_PLACE_OK:-}" ]]; then
      echo "REFUSED: bundle directory already contains recovery artifacts:" >&2
      echo "  $BUNDLE" >&2
      echo "Default rebuild would overwrite diffs/meta/index evidence before proving it matches." >&2
      echo "Choose one explicit path:" >&2
      echo "  BUNDLE_REUSE_OK=1 $0 \"$PROJECT_ABS\"          # verify and reuse only if byte-equal" >&2
      echo "  BUNDLE_OVERRIDE=<new-path> $0 \"$PROJECT_ABS\" # create a fresh bundle" >&2
      echo "  BUNDLE_REBUILD_IN_PLACE_OK=1 $0 \"$PROJECT_ABS\" # rebuild in place only after user approval" >&2
      exit 2
    fi

    echo "WARNING: BUNDLE_REBUILD_IN_PLACE_OK=1 set; rebuilding in existing bundle." >&2
    echo "Only use this after explicit user approval or for same-run partial-bundle repair." >&2
  fi
fi

mkdir -p "$BUNDLE"/{diffs,meta,stashed-untracked}
echo "$BUNDLE" > "$WORKSPACE/bundle_path.txt"

# Process each stash row in inventory.tsv
awk -F'\t' 'NR > 1' "$INVENTORY" | while IFS=$'\t' read -r n ref sha parent_sha date author message _files _ins _dels has_untracked; do
  npad=$(printf '%03d' "$n")

  # 1. Backup ref
  git -C "$PROJECT_ABS" update-ref "refs/stash-backup/$npad" "$sha"

  # 2. Diff via stash show -p --binary (NOT format-patch). Address by SHA, NOT $ref:
  # `stash@{N}` is a STACK POSITION that can shift if a concurrent agent runs
  # `git stash push` or if the user manually drops a stash between Phase 2
  # (inventory) and Phase 3 (build-bundle). Using $sha (the frozen identity
  # captured in inventory.tsv) pins the diff to the same commit the backup
  # ref points at; using $ref would mismatch ref vs. diff for the same N
  # without any check ever surfacing it.
  if ! git -C "$PROJECT_ABS" stash show -p --binary "$sha" > "$BUNDLE/diffs/$npad.diff" 2>/dev/null; then
    echo "WARNING: stash show -p --binary failed for sha=$sha (n=$n, ref=$ref); diff file may be incomplete" >&2
  fi

  # Sanity: if inventory says this stash had tracked changes (files > 0) and
  # our captured diff is empty, something is off (corrupt stash, git error
  # silently swallowed). An empty diff here would silently pass verify-bundle
  # because verify-bundle re-derives via the same path — both sides are empty,
  # both hashes match, and the bundle "verifies" with no recovery payload.
  if [[ "${_files:-0}" -gt 0 ]] && [[ ! -s "$BUNDLE/diffs/$npad.diff" ]]; then
    echo "ERROR: inventory says n=$n has _files=$_files tracked changes, but diff is empty." >&2
    echo "  diff: $BUNDLE/diffs/$npad.diff" >&2
    echo "  ref:  $ref  sha: $sha" >&2
    echo "Recovery payload would be missing. Halting before destructive phases." >&2
    exit 3
  fi

  # 3. Meta
  {
    printf 'sha=%s\n' "$sha"
    printf 'parent_sha=%s\n' "$parent_sha"
    printf 'date=%s\n' "$date"
    printf 'author=%s\n' "$author"
    printf 'has_untracked=%s\n' "$has_untracked"
    printf 'message=%s\n' "$message"
  } > "$BUNDLE/meta/$npad.txt"

	  # 4. Untracked files (third parent). Same identity-pinning rationale as
	  # step 2: address the third parent by $sha^3, not ${ref}^3, so a shifted
	  # stack position can't quietly tar files from a different stash.
	  if [[ "$has_untracked" == "true" ]]; then
	    if git -C "$PROJECT_ABS" rev-parse "${sha}^3" >/dev/null 2>&1; then
	      mkdir -p "$BUNDLE/stashed-untracked/$npad"
	      if ! git -C "$PROJECT_ABS" archive --format=tar "${sha}^3" \
	        | tar -x -C "$BUNDLE/stashed-untracked/$npad/"; then
	        echo "ERROR: failed to materialize untracked files for sha=$sha (n=$n, ref=$ref)" >&2
	        exit 3
	      fi
	    fi
	  fi
	done

# 5. index.tsv (mirror of inventory.tsv + bundle_artifacts column)
{
  printf 'n\tref\tsha\tparent_sha\tdate\tauthor\tmessage\tfiles\tinsertions\tdeletions\thas_untracked\tbundle_artifacts\n'
  awk -F'\t' 'NR > 1 {
    npad = sprintf("%03d", $1)
    artifacts = sprintf("diffs/%s.diff,meta/%s.txt,refs/stash-backup/%s", npad, npad, npad)
    if ($11 == "true") artifacts = artifacts ",stashed-untracked/" npad "/"
    printf "%s\t%s\n", $0, artifacts
  }' "$INVENTORY"
} > "$BUNDLE/index.tsv"

# 6. README.md
cat > "$BUNDLE/README.md" <<EOF
# Stash Recovery Bundle (v1.0)

Project: $PROJECT_ABS
Bundle path: $BUNDLE
Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Stash count: $(awk 'NR > 1' "$INVENTORY" | wc -l)

This bundle is the recovery story for every stash that existed at run start.
Each stash has FOUR layers of recoverability:

  1. \`refs/stash-backup/<NNN>\` — a permanent ref inside the project's
     \`.git/refs/\`. Survives \`git stash drop\`, \`git stash clear\`, and
     \`git gc\` (it's a real ref, so gc treats it as a root).
	  2. \`diffs/<NNN>.diff\` — the tracked/index diff from
	     \`git stash show -p --binary <inventory-sha>\`. Applies via \`git apply --3way\`
	     against any compatible base. Untracked files are stored separately in
	     layer 4.
  3. \`meta/<NNN>.txt\` — sha, parent, date, author, untracked flag, message.
  4. \`stashed-untracked/<NNN>/\` — materialized untracked files (only when
     the original stash was \`git stash -u\`).

## Recovery recipes

### Recover a single stash by backup ref (preferred)

	\`\`\`
	git cherry-pick -m 1 refs/stash-backup/034
	\`\`\`

	Stash backup refs point at merge commits. \`-m 1\` selects the original
	HEAD parent and recovers the tracked/index changes. If \`index.tsv\` says
	\`has_untracked=true\`, also copy \`stashed-untracked/034/\` as shown below.

### Recover a single stash by bundle diff

		\`\`\`
		git apply --3way --check ${BUNDLE_SHELL}/diffs/034.diff
		git apply --3way        ${BUNDLE_SHELL}/diffs/034.diff
	# If index.tsv says has_untracked=true, also copy stashed-untracked/034/.
	git add <changed-files>
	git commit -m "recover stash@{34} from bundle"
	\`\`\`

### Recover untracked files specifically

		\`\`\`
		( cd ${BUNDLE_SHELL}/stashed-untracked/034 && tar -cf - . ) | ( cd ${PROJECT_ABS_SHELL} && tar -xf - )
	git add <new-files>
	git commit
	\`\`\`

### Re-create the stash entry itself (rare)

	\`\`\`
	if grep -q '^diff --git ' ${BUNDLE_SHELL}/diffs/034.diff; then
	  git apply --3way --check ${BUNDLE_SHELL}/diffs/034.diff
	  git apply --3way        ${BUNDLE_SHELL}/diffs/034.diff
	fi
	if awk -F'\t' '\$1 == 34 {print \$11}' ${BUNDLE_SHELL}/index.tsv | grep -qx true; then
	  ( cd ${BUNDLE_SHELL}/stashed-untracked/034 && tar -cf - . ) | ( cd ${PROJECT_ABS_SHELL} && tar -xf - )
fi
git stash push --include-untracked -m "recovered stash@{34} from bundle"
\`\`\`

## ⚠️  Footgun: \`git format-patch\` is the WRONG recovery source

	\`git format-patch -1 stash@{N}\` is not the stash recovery diff. A stash is
	a merge commit, and format-patch can emit a tiny, empty, or unrelated patch
	depending on the merge parents. It also does not materialize untracked files.

**Always use \`git stash show -p --binary stash@{N}\`** for the recovery diff.
The diffs in this bundle were generated via \`git stash show -p --binary\` and ARE the
authoritative recovery source.

## Bundle integrity

To re-verify byte-equality of every backup ref vs. its diff:

\`\`\`
${VERIFY_SCRIPT_SHELL} ${PROJECT_ABS_SHELL}
\`\`\`

Should report 0 mismatches.

## Lifecycle

This bundle is yours to keep. Recommended:

  - Keep for at least one release cycle (typically 1–4 weeks)
  - Once you're sure nothing important was missed, you can \`mv\` it to a
    trash location (DCG would block \`rm -rf\`; that's fine — \`mv\` works)

## Index

See \`index.tsv\` for the full per-stash index.
EOF

echo "wrote bundle at $BUNDLE"
echo "  $({ find "$BUNDLE/diffs" -maxdepth 1 -type f -name '*.diff' 2>/dev/null || true; } | wc -l) diffs"
echo "  $({ find "$BUNDLE/meta" -maxdepth 1 -type f -name '*.txt' 2>/dev/null || true; } | wc -l) meta files"
echo "  $({ find "$BUNDLE/stashed-untracked" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true; } | wc -l) untracked-file dirs"
echo
echo "Now run: $SCRIPT_DIR/verify-bundle.sh $PROJECT_ABS"
