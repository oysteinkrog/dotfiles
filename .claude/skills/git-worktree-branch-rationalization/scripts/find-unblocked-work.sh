#!/usr/bin/env bash
# find-unblocked-work.sh — Phase 11: surface newly-actionable work.
#
# Walks the rationalization branch's recovered commits and identifies:
#
#   - Newly-actionable beads (`bv --robot-triage --diff-since
#     <pre-rationalization-tip>`) — issues that became unblocked because a
#     blocker was satisfied by a recovered commit.
#   - Beads closed-by-this-commit (cross-referenced via `bv --robot-history`).
#   - Open GitHub PRs whose head branches were rationalized — flagged as
#     potentially auto-mergeable.
#
# Output: <workspace>/unblocked_work.md.
#
# Best-effort throughout. Missing tools (bv, gh) degrade to a stub section
# rather than failing the run.
#
# Pre-rationalization tip:
#   - Read from <workspace>/pre_rationalization_tip.txt when available
#     (Phase 8 writes this before any landing).
#   - Otherwise fall back to <canonical>'s tip.
#
# Read-only — never mutates beads, GitHub, or the repo.
#
# Exit codes:
#   0  report written (possibly stubbed)
#   2  preflight failed (workspace / profile missing)
#   3  rationalization branch not found

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: find-unblocked-work.sh <project-path>

Phase 11. Identifies newly-actionable beads + auto-mergeable PRs unblocked
by rationalization commits. Writes <workspace>/unblocked_work.md.

Env:
  WORKSPACE                       Workspace dir override.
  RATIONALIZATION_BRANCH          Override the rationalization branch name.
  PRE_RATIONALIZATION_TIP         Override the pre-rationalization tip used
                                  for the bv --diff-since query.

Exit codes:
  0  report written (best-effort)
  2  preflight failed
  3  rationalization branch not found
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
PRE_TIP_FILE="$WORKSPACE_DIR/pre_rationalization_tip.txt"
TRIAGE="$WORKSPACE_DIR/triage.tsv"
GH_STATE="$WORKSPACE_DIR/github_state.json"
OUT="$WORKSPACE_DIR/unblocked_work.md"

[[ -f "$PROFILE" ]] || { echo "ERROR: $PROFILE missing" >&2; exit 2; }

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
DATE_TAG=$(date -u +%Y-%m-%d)
PROFILE_RB=$(profile_value rationalization_branch)
[[ -z "$PROFILE_RB" ]] && PROFILE_RB="branch-rationalization-$DATE_TAG"
RB="${RATIONALIZATION_BRANCH:-$PROFILE_RB}"

if ! git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$RB" >/dev/null 2>&1; then
  echo "ERROR: rationalization branch '$RB' not found." >&2
  exit 3
fi

# Resolve pre-rationalization tip.
PRE_TIP=""
if [[ -n "${PRE_RATIONALIZATION_TIP:-}" ]]; then
  PRE_TIP="$PRE_RATIONALIZATION_TIP"
elif [[ -f "$PRE_TIP_FILE" ]]; then
  PRE_TIP=$(head -1 "$PRE_TIP_FILE" 2>/dev/null || echo "")
fi
if [[ -z "$PRE_TIP" ]]; then
  if git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$CANONICAL^{commit}" >/dev/null 2>&1; then
    PRE_TIP=$(git -C "$PROJECT_ABS" rev-parse "refs/heads/$CANONICAL")
  elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/remotes/origin/$CANONICAL^{commit}" >/dev/null 2>&1; then
    PRE_TIP=$(git -C "$PROJECT_ABS" rev-parse "refs/remotes/origin/$CANONICAL")
  fi
fi

RB_TIP=$(git -C "$PROJECT_ABS" rev-parse "refs/heads/$RB")

# Walk recovered commits between PRE_TIP and RB_TIP.
declare -a RECOVERED_SHAS=()
if [[ -n "$PRE_TIP" ]]; then
  while IFS= read -r sha; do
    [[ -n "$sha" ]] && RECOVERED_SHAS+=("$sha")
  done < <(git -C "$PROJECT_ABS" rev-list --reverse "$PRE_TIP..$RB_TIP" 2>/dev/null || true)
fi

{
  printf '# Unblocked work — post-rationalization\n\n'
  printf 'Project:                 `%s`\n' "$PROJECT_ABS"
  printf 'Rationalization branch:  `%s` (tip `%s`)\n' "$RB" "${RB_TIP:0:12}"
  printf 'Pre-rationalization tip: `%s`\n' "${PRE_TIP:0:12}"
  printf 'Generated:               %s\n\n' "$(date -u +%FT%TZ)"
  printf 'Recovered commits:        **%d**\n\n' "${#RECOVERED_SHAS[@]}"

  # ---- bv --robot-triage --diff-since ----
  printf '## Newly-actionable beads (bv --robot-triage --diff-since)\n\n'
  if command -v bv >/dev/null 2>&1; then
    if [[ -n "$PRE_TIP" ]]; then
      if triage_json=$(cd "$PROJECT_ABS" && bv --robot-triage --diff-since "$PRE_TIP" 2>/dev/null); then
        if [[ -n "$triage_json" ]]; then
          printf '```json\n'
          printf '%s\n' "$triage_json" | head -200
          printf '\n```\n\n'
        else
          printf '_(bv returned empty output)_\n\n'
        fi
      else
        printf '_(bv --robot-triage --diff-since failed; bv may not have a beads database here)_\n\n'
      fi
    else
      printf '_(no pre-rationalization tip resolvable)_\n\n'
    fi
  else
    printf '_(bv not installed; install via `jsm install bv` for richer output)_\n\n'
  fi

  # ---- bv --robot-history closed-by ----
  printf '## Beads closed by recovered commits (bv --robot-history)\n\n'
  if command -v bv >/dev/null 2>&1 && [[ ${#RECOVERED_SHAS[@]} -gt 0 ]]; then
    history_json=""
    if history_json=$(cd "$PROJECT_ABS" && bv --robot-history 2>/dev/null); then
      :
    else
      history_json=""
    fi
    if [[ -n "$history_json" ]]; then
      printf 'For each recovered commit, search the bv history for matching SHAs:\n\n'
      for sha in "${RECOVERED_SHAS[@]}"; do
        short="${sha:0:12}"
        if printf '%s' "$history_json" | grep -q "$short"; then
          subj=$(git -C "$PROJECT_ABS" log -1 --format='%s' "$sha" 2>/dev/null || echo "")
          printf -- '- `%s` %s — referenced in bv history\n' "$short" "$subj"
        fi
      done
      printf '\n'
    else
      printf '_(bv --robot-history returned no data)_\n\n'
    fi
  else
    printf '_(bv unavailable or no recovered commits)_\n\n'
  fi

  # ---- Auto-mergeable GitHub PRs ----
  printf '## Open GitHub PRs whose head branches were rationalized\n\n'
  if command -v gh >/dev/null 2>&1 && (cd "$PROJECT_ABS" && gh auth status >/dev/null 2>&1); then
    declare -A RATIONALIZED_BRANCHES=()
    if [[ -f "$TRIAGE" ]]; then
      while IFS= read -r row; do
        kind=; name=; verdict=
        tsv_read "$row" kind name verdict _rest
        [[ "$kind" == "kind" ]] && continue
        [[ "$kind" != "branch" ]] && continue
        case "$verdict" in
          garbage|superseded|already-merged|novel-but-stale|divergent-refactor|novel-and-accretive|partially-novel)
            RATIONALIZED_BRANCHES["$name"]=1
            ;;
        esac
      done < "$TRIAGE"
    fi
    pr_list=$(cd "$PROJECT_ABS" && gh pr list --state open --json number,title,headRefName,mergeable 2>/dev/null || echo "[]")
    found=0
    if command -v jq >/dev/null 2>&1; then
      while IFS=$'\t' read -r num title head_ref mergeable; do
        [[ -z "$num" ]] && continue
        if [[ -n "${RATIONALIZED_BRANCHES[$head_ref]:-}" ]]; then
          found=1
          printf -- '- PR #%s `%s` (head=`%s`, mergeable=%s) — head branch was rationalized; review whether to close or rebase onto `%s`\n' \
            "$num" "$title" "$head_ref" "$mergeable" "$RB"
        fi
      done < <(printf '%s' "$pr_list" | jq -r '.[] | [.number, .title, .headRefName, .mergeable] | @tsv' 2>/dev/null || true)
    fi
    if [[ "$found" -eq 0 ]]; then
      printf '_(no open PRs whose head branch was in the rationalized set)_\n\n'
    else
      printf '\n'
    fi
  elif [[ -f "$GH_STATE" ]]; then
    printf '_(gh unauthenticated; using cached `%s`)_\n\n' "$GH_STATE"
  else
    printf '_(gh not installed or unauthenticated; PR awareness unavailable)_\n\n'
  fi

  # ---- Recovered commits summary ----
  if [[ ${#RECOVERED_SHAS[@]} -gt 0 ]]; then
    printf '## Recovered commits (between pre-rationalization tip and `%s`)\n\n' "$RB"
    for sha in "${RECOVERED_SHAS[@]}"; do
      short="${sha:0:12}"
      subj=$(git -C "$PROJECT_ABS" log -1 --format='%s' "$sha" 2>/dev/null || echo "")
      printf -- '- `%s` %s\n' "$short" "$subj"
    done
    printf '\n'
  fi

  printf '## How to act on this report\n\n'
  printf -- '- Newly-actionable beads → run `bv --robot-triage` to pick the highest-priority next item.\n'
  printf -- '- Closed-by-this-commit beads → close them via `br close <id> --reason "Closed by rationalization run"` once verified.\n'
  printf -- '- Auto-mergeable PRs → review case-by-case. The skill never closes or merges PRs on the user'"'"'s behalf.\n'
} > "$OUT"

log "wrote $OUT"
echo "$OUT"
exit 0
