#!/usr/bin/env bash
# provenance-trace.sh — Phase 11+: trace a file:line on the rationalization
# branch back to its source.
#
# Given <file>:<line> on the rationalization branch's tip, identifies:
#   - the rationalization-branch commit that introduced the line
#   - the apply_log.tsv row for that commit (kind / target / strategy / new_sha)
#   - the source branch (or worktree) that the line came from
#   - the source commit on the source branch (via `git blame` against the
#     bundle's backup ref)
#   - the source hunk in the bundle's diff-vs-merge-base.diff
#   - the harmonization intent (for `harmonized-synthesis` commits) extracted
#     from harmonization_plan.md's per-file section
#
# Output: a single JSON object on stdout (or to <workspace>/provenance/<sig>.json
# when run with --persist).
#
# Reads only — never mutates. Useful for post-merge audits ("who introduced
# this regression?").
#
# Exit codes:
#   0  trace produced
#   2  preflight failed (workspace / bundle missing)
#   3  file:line out of range or no commit found
#   4  rationalization branch not found

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: provenance-trace.sh <project-path> <file>:<line> [--persist]

Trace a file:line on the rationalization branch back to its source branch,
source commit, source hunk, and harmonization intent. Reads:
  - <workspace>/apply_log.tsv
  - <workspace>/harmonization_plan.md
  - <bundle>/index.tsv
  - <bundle>/branches/<slug>/diff-vs-merge-base.diff
  - <bundle>/branches/<slug>/format-patch/*.patch (when present)

--persist saves the JSON to <workspace>/provenance/<sig>.json (idempotent
keyed on file/line/rb-tip).

Env:
  WORKSPACE                       Workspace dir override.
  RATIONALIZATION_BRANCH          Override the rationalization branch name.

Exit codes:
  0  trace produced
  2  preflight failed
  3  no commit found at that file:line
  4  rationalization branch not found
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
TARGET="${2:-}"
PERSIST=0
if [[ "${3:-}" == "--persist" ]]; then
  PERSIST=1
fi
if [[ -z "$TARGET" ]]; then
  usage >&2
  exit 64
fi

# Parse <file>:<line>.
case "$TARGET" in
  *:*)
    FILE="${TARGET%:*}"
    LINE="${TARGET##*:}"
    ;;
  *)
    echo "ERROR: target must be <file>:<line>; got '$TARGET'" >&2
    exit 64
    ;;
esac
if [[ ! "$LINE" =~ ^[0-9]+$ ]]; then
  echo "ERROR: line must be a positive integer; got '$LINE'" >&2
  exit 64
fi

PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
PROFILE="$WORKSPACE_DIR/project_profile.json"
APPLY_LOG="$WORKSPACE_DIR/apply_log.tsv"
PLAN="$WORKSPACE_DIR/harmonization_plan.md"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"

[[ -f "$BUNDLE_PATH_FILE" ]] || { echo "ERROR: $BUNDLE_PATH_FILE missing" >&2; exit 2; }
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"
INDEX_TSV="$BUNDLE/index.tsv"
[[ -f "$INDEX_TSV" ]] || { echo "ERROR: bundle index $INDEX_TSV missing" >&2; exit 2; }

profile_rationalization_branch() {
  [[ -f "$PROFILE" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '.rationalization_branch // ""' "$PROFILE" 2>/dev/null || true
    return
  fi
  python3 - "$PROFILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
print(data.get("rationalization_branch") or "")
PY
}

DATE_TAG=$(date -u +%Y-%m-%d)
PROFILE_RB=$(profile_rationalization_branch)
[[ -z "$PROFILE_RB" ]] && PROFILE_RB="branch-rationalization-$DATE_TAG"
RB="${RATIONALIZATION_BRANCH:-$PROFILE_RB}"
RB_REF="refs/heads/$RB"
if ! git -C "$PROJECT_ABS" rev-parse --verify --quiet "$RB_REF^{commit}" >/dev/null 2>&1; then
  echo "ERROR: rationalization branch '$RB' not found." >&2
  exit 4
fi
RB_TIP=$(git -C "$PROJECT_ABS" rev-parse "$RB_REF")

# Step 1: who introduced this line on $RB?
INTRO_SHA=$(git -C "$PROJECT_ABS" log -1 --format='%H' -L "$LINE,$LINE:$FILE" "$RB_REF" -- "$FILE" 2>/dev/null \
  | head -1 || true)
if [[ -z "$INTRO_SHA" ]]; then
  # Fallback: blame at the rb tip.
  INTRO_SHA=$(git -C "$PROJECT_ABS" blame -L "$LINE,$LINE" --root --line-porcelain "$RB_REF" -- "$FILE" 2>/dev/null \
    | awk '$1=="boundary"||NR==1{print $1; exit}' || true)
  if [[ -z "$INTRO_SHA" || "$INTRO_SHA" == "boundary" ]]; then
    INTRO_SHA=$(git -C "$PROJECT_ABS" blame -L "$LINE,$LINE" "$RB_REF" -- "$FILE" 2>/dev/null \
      | awk '{print $1}' | head -1 || true)
  fi
fi
if [[ -z "$INTRO_SHA" ]]; then
  echo "ERROR: cannot resolve introducing commit for $FILE:$LINE on $RB" >&2
  exit 3
fi
INTRO_SUBJECT=$(git -C "$PROJECT_ABS" log -1 --format='%s' "$INTRO_SHA" 2>/dev/null || echo "")
INTRO_AUTHOR=$(git -C "$PROJECT_ABS" log -1 --format='%an' "$INTRO_SHA" 2>/dev/null || echo "")
INTRO_DATE=$(git -C "$PROJECT_ABS" log -1 --format='%cI' "$INTRO_SHA" 2>/dev/null || echo "")

# Step 2: locate the apply_log row whose new_commit_sha matches.
SOURCE_KIND=""
SOURCE_TARGET=""
SOURCE_STRATEGY=""
if [[ -f "$APPLY_LOG" ]]; then
  while IFS= read -r row; do
    k=; t=; s=; sha=
    tsv_read "$row" k t s sha _f _g _d _drift
    [[ "$k" == "kind" ]] && continue
    [[ "$sha" == "$INTRO_SHA" ]] || continue
    SOURCE_KIND="$k"
    SOURCE_TARGET="$t"
    SOURCE_STRATEGY="$s"
    break
  done < "$APPLY_LOG"
fi

# Step 3: resolve the source slug (if branch) so we can dive into the bundle.
SOURCE_SLUG=""
SOURCE_HEAD_SHA=""
if [[ "$SOURCE_KIND" == "branch" && -n "$SOURCE_TARGET" && -f "$BRANCHES_TSV" ]]; then
  while IFS= read -r row; do
    name=; slug=; head_sha=
    tsv_read "$row" name slug head_sha _rest
    [[ "$name" == "name" ]] && continue
    if [[ "$name" == "$SOURCE_TARGET" ]]; then
      SOURCE_SLUG="$slug"
      SOURCE_HEAD_SHA="$head_sha"
      break
    fi
  done < "$BRANCHES_TSV"
fi

# Step 4: find the source commit via blame against the backup ref.
SOURCE_COMMIT=""
SOURCE_COMMIT_SUBJECT=""
if [[ -n "$SOURCE_SLUG" ]]; then
  BACKUP_REF="refs/branch-rationalization-backup/$SOURCE_SLUG"
  if git -C "$PROJECT_ABS" rev-parse --verify --quiet "$BACKUP_REF" >/dev/null 2>&1; then
    # Blame the same file at the backup ref, looking for the line content's
    # introducing commit. We can't blame line-N exactly because the file may
    # have shifted; use a fuzzy approach: locate the line text on the
    # rationalization branch, then blame for that text on the backup ref.
    LINE_TEXT=$(git -C "$PROJECT_ABS" show "$RB_REF:$FILE" 2>/dev/null | awk -v n="$LINE" 'NR==n{print; exit}' || true)
    if [[ -n "$LINE_TEXT" ]]; then
      SOURCE_COMMIT=$(git -C "$PROJECT_ABS" log -1 --format='%H' -S"$LINE_TEXT" "$BACKUP_REF" -- "$FILE" 2>/dev/null || true)
      if [[ -n "$SOURCE_COMMIT" ]]; then
        SOURCE_COMMIT_SUBJECT=$(git -C "$PROJECT_ABS" log -1 --format='%s' "$SOURCE_COMMIT" 2>/dev/null || echo "")
      fi
    fi
  fi
fi

# Step 5: locate the source hunk in diff-vs-merge-base.diff.
SOURCE_HUNK=""
if [[ -n "$SOURCE_SLUG" ]]; then
  DIFF_FILE="$BUNDLE/branches/$SOURCE_SLUG/diff-vs-merge-base.diff"
  if [[ -f "$DIFF_FILE" ]]; then
    # Pluck the first hunk header that mentions the file.
    SOURCE_HUNK=$(awk -v f="$FILE" '
      $0 ~ "^diff --git " { in_file=0; if ($0 ~ f) in_file=1 }
      in_file && /^@@/ { print; exit }
    ' "$DIFF_FILE" 2>/dev/null || true)
  fi
fi

# Step 6: harmonization intent (only for harmonized-synthesis commits).
HARMONIZATION_INTENT=""
HARMONIZATION_SOURCES=""
if [[ "$SOURCE_STRATEGY" == "harmonized-synthesis" && -f "$PLAN" ]]; then
  # Read the per-file section that mentions $FILE.
  HARMONIZATION_INTENT=$(awk -v f="$FILE" '
    $0 ~ "^### file: " && index($0, f) { capture=1; next }
    capture && $0 ~ "^### file: " { exit }
    capture && $0 ~ "^- intent:" { sub(/^- intent:[[:space:]]*/, ""); print; exit }
  ' "$PLAN" 2>/dev/null || true)
  HARMONIZATION_SOURCES=$(awk -v f="$FILE" '
    $0 ~ "^### file: " && index($0, f) { capture=1; next }
    capture && $0 ~ "^### file: " { exit }
    capture && match($0, /branch:[[:space:]]*`?[^`[:space:]]+`?/) {
      s=substr($0, RSTART, RLENGTH)
      sub(/^branch:[[:space:]]*`?/, "", s)
      sub(/`?$/, "", s)
      print s
    }
  ' "$PLAN" 2>/dev/null | sort -u | paste -sd, - || true)
fi

# Build JSON.
EMIT_JSON=$(
  {
    printf '{\n'
    printf '  "schema": "provenance-trace/v1",\n'
    printf '  "queried_at": '; json_string "$(date -u +%FT%TZ)"; printf ',\n'
    printf '  "project": '; json_string "$PROJECT_ABS"; printf ',\n'
    printf '  "rationalization_branch": '; json_string "$RB"; printf ',\n'
    printf '  "rationalization_tip": '; json_string "$RB_TIP"; printf ',\n'
    printf '  "file": '; json_string "$FILE"; printf ',\n'
    printf '  "line": %d,\n' "$LINE"
    printf '  "introducing_commit": {\n'
    printf '    "sha": '; json_string "$INTRO_SHA"; printf ',\n'
    printf '    "subject": '; json_string "$INTRO_SUBJECT"; printf ',\n'
    printf '    "author": '; json_string "$INTRO_AUTHOR"; printf ',\n'
    printf '    "date": '; json_string "$INTRO_DATE"; printf '\n'
    printf '  },\n'
    printf '  "apply_log_entry": {\n'
    printf '    "kind": '; json_string "$SOURCE_KIND"; printf ',\n'
    printf '    "target": '; json_string "$SOURCE_TARGET"; printf ',\n'
    printf '    "strategy": '; json_string "$SOURCE_STRATEGY"; printf '\n'
    printf '  },\n'
    printf '  "source": {\n'
    printf '    "slug": '; json_string "$SOURCE_SLUG"; printf ',\n'
    printf '    "head_sha": '; json_string "$SOURCE_HEAD_SHA"; printf ',\n'
    printf '    "commit_sha": '; json_string "$SOURCE_COMMIT"; printf ',\n'
    printf '    "commit_subject": '; json_string "$SOURCE_COMMIT_SUBJECT"; printf ',\n'
    printf '    "hunk_header": '; json_string "$SOURCE_HUNK"; printf '\n'
    printf '  },\n'
    printf '  "harmonization": {\n'
    printf '    "intent": '; json_string "$HARMONIZATION_INTENT"; printf ',\n'
    printf '    "source_branches": '; json_string "$HARMONIZATION_SOURCES"; printf '\n'
    printf '  }\n'
    printf '}\n'
  }
)

if [[ "$PERSIST" -eq 1 ]]; then
  PROV_DIR="$WORKSPACE_DIR/provenance"
  mkdir -p "$PROV_DIR"
  if command -v sha1sum >/dev/null 2>&1; then
    sig=$(printf '%s:%s:%s' "$RB_TIP" "$FILE" "$LINE" | sha1sum | awk '{print substr($1,1,16)}')
  else
    sig=$(printf '%s:%s:%s' "$RB_TIP" "$FILE" "$LINE" | shasum -a 1 | awk '{print substr($1,1,16)}')
  fi
  OUT="$PROV_DIR/${sig}.json"
  printf '%s' "$EMIT_JSON" > "$OUT"
  echo "wrote $OUT"
fi

printf '%s' "$EMIT_JSON"
exit 0
