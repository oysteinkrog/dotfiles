#!/usr/bin/env bash
# snapshot-tree.sh — Capture per-worktree working-tree state for drift detection.
#
# Used three times in the phase loop:
#   Phase 0   baseline       (phase=phase0)
#   Phase 8   pre-apply      (phase=phase8_pre_apply_<keeper-slug>)
#   Phase 10  pre-remove     (phase=phase10_pre_remove_<sanitized-path>)
#
# For every linked worktree the snapshot captures:
#   - git status --porcelain=v2 --branch --untracked-files=all
#   - git diff --stat (working tree)
#   - git diff --cached --stat (staged)
#   - first 100 untracked entries (sed-pagination, never head — head SIGPIPEs
#     under set -euo pipefail)
#
# Output one file per worktree:
#   <workspace>/wt_<phase>_<sanitized-path>.txt
#
# Per Axiom 12 / AGENTS.md "Note for Codex/GPT-5.5": this script never stashes,
# reverts, or overwrites concurrent-agent state — it just records. The diff
# between two snapshots is what tells later phases whether drift appeared.
#
# Exit codes:
#   0  one or more snapshots written
#   2  not a git work tree
#   3  invalid <phase> argument

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: snapshot-tree.sh <project-path> [<phase>]

  <phase> defaults to phase0. Recognized forms:
    phase0
    phase8_pre_apply_<keeper-slug>
    phase10_pre_remove_<sanitized-path>
    <free-form-tag>            (resume / debugging only)

Captures per-worktree status + diff + diff-cached + first-100 untracked into
<workspace>/wt_<phase>_<sanitized-path>.txt — one file per linked worktree.

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  snapshots written
  2  not a git work tree
  3  invalid <phase> form (whitespace / empty)
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PHASE="${2:-phase0}"

# Reject empty or whitespace-only phase tags — they would collide on disk.
if [[ -z "$PHASE" ]] || [[ "$PHASE" =~ ^[[:space:]]+$ ]]; then
  echo "ERROR: <phase> must be non-empty (e.g., phase0, phase8_pre_apply_<slug>)." >&2
  exit 3
fi

PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
mkdir -p "$WORKSPACE_DIR"

WS_BASENAME=$(basename "$WORKSPACE_DIR")

# Sanitize the phase tag the same way we sanitize paths so the filename is
# always safe.
PHASE_SAFE=$(printf '%s' "$PHASE" | tr -c 'A-Za-z0-9._-' '_')

# Iterate every linked worktree (the main repo plus each `git worktree add`
# checkout). We use the porcelain output to keep the parse robust against
# locked / detached / bare entries.
total=0
written=0
skipped=0
while IFS= read -r line; do
  case "$line" in
    worktree\ *)
      curr_path="${line#worktree }"
      curr_branch=""
      curr_sha=""
      curr_detached=false
      curr_bare=false
      curr_locked=false
      ;;
    HEAD\ *)        curr_sha="${line#HEAD }" ;;
    branch\ *)      curr_branch="${line#branch }" ;;
    detached)       curr_detached=true ;;
    bare)           curr_bare=true ;;
    locked|locked\ *) curr_locked=true ;;
    "")
      [[ -z "${curr_path:-}" ]] && continue
      total=$((total + 1))

      san=$(sanitize_path "$curr_path")
      out="$WORKSPACE_DIR/wt_${PHASE_SAFE}_${san}.txt"

      # Resume-aware: if the file already exists with the same content
      # signature, skip the rewrite. Signature = HEAD SHA + status hash;
      # cheap to compute, exact enough to detect drift since last snapshot.
      if [[ -f "$out" && -d "$curr_path" ]]; then
        live_sig="$(git -C "$curr_path" rev-parse HEAD 2>/dev/null || echo no-head)"
        live_status_hash=$(git -C "$curr_path" status --porcelain=v2 --branch --untracked-files=all -- . ":(exclude)$WS_BASENAME" 2>/dev/null | sha256sum | awk '{print $1}')
        prior_sig=$(grep -E '^signature=' "$out" 2>/dev/null | head -1 | cut -d= -f2- || true)
        if [[ -n "$prior_sig" && "$prior_sig" == "${live_sig}|${live_status_hash}" ]]; then
          skipped=$((skipped + 1))
          : "$curr_branch" "$curr_sha" "$curr_detached" "$curr_bare" "$curr_locked"
          curr_path=""
          continue
        fi
      fi

      {
        printf '## working-tree snapshot\n'
        printf 'project=%s\n' "$PROJECT_ABS"
        printf 'worktree=%s\n' "$curr_path"
        printf 'phase=%s\n' "$PHASE"
        printf 'timestamp=%s\n' "$(date -u +%FT%TZ)"
        printf 'branch=%s\n' "${curr_branch#refs/heads/}"
        printf 'detached=%s\n' "${curr_detached:-false}"
        printf 'bare=%s\n' "${curr_bare:-false}"
        printf 'locked=%s\n' "${curr_locked:-false}"
        if [[ -d "$curr_path" ]]; then
          live_head=$(git -C "$curr_path" rev-parse HEAD 2>/dev/null || echo unknown)
          live_status_hash=$(git -C "$curr_path" status --porcelain=v2 --branch --untracked-files=all -- . ":(exclude)$WS_BASENAME" 2>/dev/null | sha256sum | awk '{print $1}')
          printf 'head=%s\n' "$live_head"
          printf 'signature=%s|%s\n' "$live_head" "$live_status_hash"
        else
          printf 'head=(worktree path absent)\n'
          printf 'signature=absent|absent\n'
        fi

        printf '\n## status --porcelain=v2 --branch --untracked-files=all\n'
        if [[ -d "$curr_path" ]]; then
          git -C "$curr_path" status --porcelain=v2 --branch --untracked-files=all -- . ":(exclude)$WS_BASENAME" 2>/dev/null || true
        else
          printf '(worktree path absent)\n'
        fi

        printf '\n## diff --stat (working tree)\n'
        if [[ -d "$curr_path" ]]; then
          git -C "$curr_path" diff --stat -- . ":(exclude)$WS_BASENAME" 2>/dev/null || true
        fi

        printf '\n## diff --cached --stat (staged)\n'
        if [[ -d "$curr_path" ]]; then
          git -C "$curr_path" diff --cached --stat -- . ":(exclude)$WS_BASENAME" 2>/dev/null || true
        fi

        printf '\n## untracked (first 100, exclude-standard)\n'
        # Use sed -n '1,100p' instead of head -100 to avoid SIGPIPE under
        # set -euo pipefail — same reason discover-branches-worktrees.sh
        # documents in the worktree-parse loop.
        if [[ -d "$curr_path" ]]; then
          { git -C "$curr_path" ls-files --others --exclude-standard -- . ":(exclude)$WS_BASENAME" 2>/dev/null \
              | sed -n '1,100p' ; } || true
        fi
      } > "$out"

      written=$((written + 1))
      curr_path=""
      ;;
  esac
done < <(git -C "$PROJECT_ABS" worktree list --porcelain 2>/dev/null)

# Trailing block (last worktree without a blank line terminator) — mirror the
# emit in discover-branches-worktrees.sh by re-running the body if curr_path
# is still set.
if [[ -n "${curr_path:-}" ]]; then
  total=$((total + 1))
  san=$(sanitize_path "$curr_path")
  out="$WORKSPACE_DIR/wt_${PHASE_SAFE}_${san}.txt"
  should_write=1
  if [[ -f "$out" && -d "$curr_path" ]]; then
    live_sig="$(git -C "$curr_path" rev-parse HEAD 2>/dev/null || echo no-head)"
    live_status_hash=$(git -C "$curr_path" status --porcelain=v2 --branch --untracked-files=all -- . ":(exclude)$WS_BASENAME" 2>/dev/null | sha256sum | awk '{print $1}')
    prior_sig=$(grep -E '^signature=' "$out" 2>/dev/null | head -1 | cut -d= -f2- || true)
    if [[ -n "$prior_sig" && "$prior_sig" == "${live_sig}|${live_status_hash}" ]]; then
      should_write=0
    fi
  fi

  if [[ "$should_write" -eq 1 ]]; then
    {
      printf '## working-tree snapshot\n'
      printf 'project=%s\n' "$PROJECT_ABS"
      printf 'worktree=%s\n' "$curr_path"
      printf 'phase=%s\n' "$PHASE"
      printf 'timestamp=%s\n' "$(date -u +%FT%TZ)"
      printf 'branch=%s\n' "${curr_branch#refs/heads/}"
      if [[ -d "$curr_path" ]]; then
        live_head=$(git -C "$curr_path" rev-parse HEAD 2>/dev/null || echo unknown)
        live_status_hash=$(git -C "$curr_path" status --porcelain=v2 --branch --untracked-files=all -- . ":(exclude)$WS_BASENAME" 2>/dev/null | sha256sum | awk '{print $1}')
        printf 'head=%s\n' "$live_head"
        printf 'signature=%s|%s\n' "$live_head" "$live_status_hash"
      else
        printf 'head=(absent)\n'
        printf 'signature=absent|absent\n'
      fi
      printf '\n## status --porcelain=v2 --branch --untracked-files=all\n'
      if [[ -d "$curr_path" ]]; then
        git -C "$curr_path" status --porcelain=v2 --branch --untracked-files=all -- . ":(exclude)$WS_BASENAME" 2>/dev/null || true
      fi
      printf '\n## diff --stat (working tree)\n'
      if [[ -d "$curr_path" ]]; then
        git -C "$curr_path" diff --stat -- . ":(exclude)$WS_BASENAME" 2>/dev/null || true
      fi
      printf '\n## diff --cached --stat (staged)\n'
      if [[ -d "$curr_path" ]]; then
        git -C "$curr_path" diff --cached --stat -- . ":(exclude)$WS_BASENAME" 2>/dev/null || true
      fi
      printf '\n## untracked (first 100, exclude-standard)\n'
      if [[ -d "$curr_path" ]]; then
        { git -C "$curr_path" ls-files --others --exclude-standard -- . ":(exclude)$WS_BASENAME" 2>/dev/null \
            | sed -n '1,100p' ; } || true
      fi
    } > "$out"
    written=$((written + 1))
  else
    skipped=$((skipped + 1))
  fi
fi

echo "snapshots: total=$total written=$written skipped=$skipped phase=$PHASE"
exit 0
