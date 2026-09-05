#!/usr/bin/env bash
# handoff-report.sh — Phase 11: emit the final handoff report.
#
# Reads: project_profile.json, triage.tsv, apply_log.tsv, cleanup_log.tsv,
#        bundle_path.txt, harmonization_plan.md.
# Writes: <workspace>/handoff_report.md.
# Side effects (best-effort, never blocking):
#   - file a beads issue via `br create`
#   - update Agent Mail thread (if /agent-mail / mcp tooling is present — caller's job)
#   - run `bv --robot-triage` if available (output captured to handoff_report appendix)
#   - emit `git push` reminder for the rationalization branch (the user pushes; the skill never pushes).

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: handoff-report.sh <project-path>

Phase 11. Writes <workspace>/handoff_report.md, files a beads issue (best
effort), runs bv --robot-triage if available, and prints push instructions.

Env:
  WORKSPACE                       Workspace dir override.
  RATIONALIZATION_BRANCH          Override the rationalization branch name.
  HANDOFF_SKIP_BEADS=1            Skip the beads create.
  HANDOFF_SKIP_BV=1               Skip the bv triage call.

Exit codes:
  0  ok
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
PROFILE="$WORKSPACE_DIR/project_profile.json"
TRIAGE="$WORKSPACE_DIR/triage.tsv"
APPLY_LOG="$WORKSPACE_DIR/apply_log.tsv"
CLEANUP_LOG="$WORKSPACE_DIR/cleanup_log.tsv"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"
PLAN="$WORKSPACE_DIR/harmonization_plan.md"
OUT="$WORKSPACE_DIR/handoff_report.md"

[[ -f "$PROFILE" ]] || { echo "ERROR: $PROFILE missing" >&2; exit 2; }
BUNDLE="$(cat "$BUNDLE_PATH_FILE" 2>/dev/null || echo '<unknown>')"

profile_value() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then jq -r --arg key "$key" '.[$key] // ""' "$PROFILE"; return; fi
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
DATE_TAG=$(date -u +%Y-%m-%d)
RB="${RATIONALIZATION_BRANCH:-branch-rationalization-$DATE_TAG}"
BASENAME="$(basename "$PROJECT_ABS")"

count_rows() {
  if [[ -f "$1" ]]; then awk -F'\t' "$2" "$1" 2>/dev/null | wc -l; else echo 0; fi
}
verdict_count() {
  if [[ ! -f "$TRIAGE" ]]; then echo 0; return; fi
  awk -F'\t' -v v="$1" 'NR > 1 && $3 == v' "$TRIAGE" | wc -l
}

# Per-verdict counts.
N_NOVEL=$(verdict_count novel-and-accretive)
N_PARTIAL=$(verdict_count partially-novel)
N_DIV=$(verdict_count divergent-refactor)
N_DIRTY=$(verdict_count dirty-worktree-only)
N_ALREADY=$(verdict_count already-merged)
N_SUPER=$(verdict_count superseded)
N_STALE=$(verdict_count novel-but-stale)
N_GARBAGE=$(verdict_count garbage)
N_PROTO=$(verdict_count protected-preserve)
N_UNKNOWN=$(verdict_count unknown)

# Apply / cleanup tallies.
# shellcheck disable=SC2016
APPLIED_BR=$(count_rows "$APPLY_LOG" 'NR > 1 && $1 == "branch"   && $4 != "" && $6 == "passed"')
# shellcheck disable=SC2016
APPLIED_WT=$(count_rows "$APPLY_LOG" 'NR > 1 && $1 == "worktree" && $4 != "" && $6 == "passed"')
# shellcheck disable=SC2016
REMOVED_WT=$(count_rows "$CLEANUP_LOG" 'NR > 1 && $2 == "worktree"')
# shellcheck disable=SC2016
DELETED_BR=$(count_rows "$CLEANUP_LOG" 'NR > 1 && $2 == "branch"')

# Disk-freed estimate from worktree size, if available.
DISK_FREED="(unknown)"
if [[ -f "$CLEANUP_LOG" ]]; then
  bytes_total=0
  while IFS= read -r row; do
    phase=""
    kind=""
    tgt=""
    tsv_read "$row" phase kind tgt _verdict _cmd _ref _ts _notes
    [[ "$phase" == "phase" ]] && continue
    [[ "$kind" != "worktree" ]] && continue
    if [[ -d "$tgt" ]]; then
      sz=$(du -sb "$tgt" 2>/dev/null | awk '{print $1}')
      bytes_total=$((bytes_total + ${sz:-0}))
    fi
    : "$phase"
  done < "$CLEANUP_LOG"
  if [[ "$bytes_total" -gt 0 ]]; then
    DISK_FREED=$(awk -v b="$bytes_total" 'BEGIN { printf "%.1f MB", b/1048576 }')
  else
    DISK_FREED="0 (worktrees already gone)"
  fi
fi

RB_TIP=$(git -C "$PROJECT_ABS" rev-parse --verify --quiet "$RB^{commit}" 2>/dev/null || echo "(branch not found)")

# ---- Compose report ----
{
  printf '# Branch + Worktree Rationalization — Handoff Report\n\n'
  printf '**Project:** %s\n' "$PROJECT_ABS"
  printf '**Run date:** %s\n' "$DATE_TAG"
  printf '**Canonical branch:** %s\n' "$CANONICAL"
  printf '**Rationalization branch:** %s (tip: %s)\n' "$RB" "$RB_TIP"
  printf '**Bundle path:** %s\n\n' "$BUNDLE"

  printf '## Counts per verdict\n\n'
  printf '| verdict | count |\n|---------|-------|\n'
  printf '| novel-and-accretive | %s |\n' "$N_NOVEL"
  printf '| partially-novel | %s |\n' "$N_PARTIAL"
  printf '| divergent-refactor | %s |\n' "$N_DIV"
  printf '| dirty-worktree-only | %s |\n' "$N_DIRTY"
  printf '| already-merged | %s |\n' "$N_ALREADY"
  printf '| superseded | %s |\n' "$N_SUPER"
  printf '| novel-but-stale | %s |\n' "$N_STALE"
  printf '| garbage | %s |\n' "$N_GARBAGE"
  printf '| protected-preserve | %s |\n' "$N_PROTO"
  printf '| unknown | %s |\n\n' "$N_UNKNOWN"

  printf '## Applied keepers\n\n'
  printf -- '- branches applied: %s\n' "$APPLIED_BR"
  printf -- '- worktrees applied (dirty-state recovery): %s\n\n' "$APPLIED_WT"
  if [[ -f "$APPLY_LOG" ]] && awk 'NR > 1 && $4 != ""' "$APPLY_LOG" | grep -q .; then
    printf '| sha | kind | target | strategy | files | duration |\n'
    printf '|-----|------|--------|----------|-------|----------|\n'
    awk -F'\t' 'NR > 1 && $4 != "" {
      short = substr($4, 1, 10)
      gsub(/\|/, "\\|", $2); gsub(/\|/, "\\|", $3)
      printf "| %s | %s | %s | %s | %s | %ss |\n", short, $1, $2, $3, $5, $7
    }' "$APPLY_LOG"
    printf '\n'
  else
    printf '_No applied keepers in this run._\n\n'
  fi

  if [[ -f "$PLAN" ]]; then
    printf '## Harmonization summary\n\n'
    n_files=$(awk '/^### `/{count++} END {print count+0}' "$PLAN" 2>/dev/null)
    if [[ "$n_files" -gt 0 ]]; then
      printf "%s files harmonized via Phase 7 variant matrix; see [\`%s\`](%s).\n\n" "$n_files" "harmonization_plan.md" "harmonization_plan.md"
    else
      printf '_No harmonization required._\n\n'
    fi
  fi

  printf '## Removed worktrees\n\n'
  printf 'Disk freed (estimate): **%s**\n\n' "$DISK_FREED"
  if [[ -f "$CLEANUP_LOG" ]] && awk 'NR > 1 && $2 == "worktree"' "$CLEANUP_LOG" | grep -q .; then
    printf '| path | verdict | bundle |\n'
    printf '|------|---------|--------|\n'
    awk -F'\t' 'NR > 1 && $2 == "worktree" {
      gsub(/\|/, "\\|", $3); gsub(/\|/, "\\|", $6)
      printf "| %s | %s | %s |\n", $3, $4, $6
    }' "$CLEANUP_LOG"
    printf '\n'
  else
    printf '_No worktrees removed._\n\n'
  fi

  printf '## Deleted local branches\n\n'
  if [[ -f "$CLEANUP_LOG" ]] && awk 'NR > 1 && $2 == "branch"' "$CLEANUP_LOG" | grep -q .; then
    printf '| branch | verdict | backup ref |\n'
    printf '|--------|---------|------------|\n'
    awk -F'\t' 'NR > 1 && $2 == "branch" {
      gsub(/\|/, "\\|", $3)
      printf "| %s | %s | %s |\n", $3, $4, $6
    }' "$CLEANUP_LOG"
    printf '\n'
  else
    printf '_No branches deleted._\n\n'
  fi

  printf '## Preserved branches\n\n'
  printf 'Branches that survived this run (canonical, protected, or not yet rationalized):\n\n'
  printf '```\n'
  git -C "$PROJECT_ABS" for-each-ref refs/heads --format='%(refname:lstrip=2)' 2>/dev/null | head -50 || true
  total_preserved=$(git -C "$PROJECT_ABS" for-each-ref refs/heads 2>/dev/null | wc -l)
  if [[ "$total_preserved" -gt 50 ]]; then
    printf '...(%s total)\n' "$total_preserved"
  fi
  printf '```\n\n'

  printf '## Skipped (unknown verdicts)\n\n'
  if [[ "$N_UNKNOWN" -gt 0 ]]; then
    printf '%s entries had verdict=unknown and were not actioned. They remain intact (branches not deleted, worktrees not removed).\n\n' "$N_UNKNOWN"
  else
    printf '_None._\n\n'
  fi

  printf '## Recovery recipes (verbatim copy-paste)\n\n'
  BUNDLE_SHELL=$(printf '%q' "$BUNDLE")
  RB_SHELL=$(printf '%q' "$RB")
  cat <<RECIPES
\`\`\`bash
# Recover a deleted branch by backup ref:
git branch <new-name> refs/branch-rationalization-backup/<slug>

# Recover from the object bundle into a fresh clone:
git fetch ${BUNDLE_SHELL}/object-bundle.pack \\
  '+refs/branch-rationalization-backup/*:refs/branch-rationalization-backup/*'

# Apply a branch's full diff onto the current HEAD:
git apply --3way ${BUNDLE_SHELL}/branches/<slug>/diff-vs-merge-base.diff

# Replay a branch's commits via git am (preserves authorship):
git am ${BUNDLE_SHELL}/branches/<slug>/format-patch/*.patch

# Recover a removed worktree's dirty state:
git worktree add <new-path> <branch-or-sha>
git -C <new-path> apply --3way --cached \\
  ${BUNDLE_SHELL}/worktrees/<sanitized>/staged.diff
git -C <new-path> apply --3way \\
  ${BUNDLE_SHELL}/worktrees/<sanitized>/unstaged.diff
tar --null -xzf ${BUNDLE_SHELL}/worktrees/<sanitized>/untracked.tar.gz \\
  -C <new-path> \\
  -T ${BUNDLE_SHELL}/worktrees/<sanitized>/.untracked.list
\`\`\`
RECIPES
  printf '\n'

  printf '## Push instructions\n\n'
  printf 'The skill never pushes. To land the rationalization branch:\n\n'
  printf '```bash\n'
  printf 'git push origin %s\n' "$RB_SHELL"
  printf '# Then open a PR against %s for review.\n' "$CANONICAL"
  printf '```\n\n'

  printf '## Bundle lifecycle\n\n'
  printf -- '- Keep at least one release cycle (1–4 weeks).\n'
  printf "%s\n" "- DCG blocks \`rm -rf\`; the skill will never touch this bundle."
  printf "%s\n\n" "- When you are sure nothing was missed, \`mv\` the bundle to a trash location."

  printf '## Backup refs in this repo\n\n'
  printf '```\n'
  git -C "$PROJECT_ABS" for-each-ref refs/branch-rationalization-backup/ --format='%(refname:short) %(objectname:short)' 2>/dev/null | head -20 || true
  total_backup=$(git -C "$PROJECT_ABS" for-each-ref refs/branch-rationalization-backup/ 2>/dev/null | wc -l)
  if [[ "$total_backup" -gt 20 ]]; then printf '...(%s total)\n' "$total_backup"; fi
  printf '```\n\n'

  printf '## Done\n\n'
  printf 'Push the rationalization branch when ready.\n'
} > "$OUT"

# ---- File a beads issue (best-effort) ----
BEADS_SKIPPED=false
if [[ -z "${HANDOFF_SKIP_BEADS:-}" ]] && command -v br >/dev/null 2>&1; then
  TITLE="branch+worktree rationalization on $BASENAME ($N_NOVEL+$N_PARTIAL+$N_DIV branches kept, $REMOVED_WT worktrees removed)"
  if ! ( cd "$PROJECT_ABS" && br create --title "$TITLE" --type task --priority 2 ) 2>/dev/null; then
    BEADS_SKIPPED=true
  fi
else
  BEADS_SKIPPED=true
fi

# ---- Run bv --robot-triage (best-effort, append) ----
if [[ -z "${HANDOFF_SKIP_BV:-}" ]] && command -v bv >/dev/null 2>&1; then
  {
    printf '\n## bv --robot-triage (post-run)\n\n'
    printf '```json\n'
    ( cd "$PROJECT_ABS" && bv --robot-triage 2>/dev/null | head -200 ) || true
    printf '\n```\n'
  } >> "$OUT"
fi

if [[ "$BEADS_SKIPPED" == "true" ]]; then
  {
    printf '\n## Beads tracking\n\n'
    printf '_Beads issue creation skipped (br not present, HANDOFF_SKIP_BEADS=1, or call failed)._\n'
  } >> "$OUT"
fi

echo "wrote $OUT"
echo
echo "=== HANDOFF SUMMARY ==="
echo "  rationalization branch: $RB ($RB_TIP)"
echo "  applied keepers: $APPLIED_BR branches, $APPLIED_WT worktree dirty-state captures"
echo "  removed worktrees: $REMOVED_WT"
echo "  deleted branches:  $DELETED_BR"
echo "  bundle: $BUNDLE"
echo
echo "Push when ready:  git push origin $RB"
