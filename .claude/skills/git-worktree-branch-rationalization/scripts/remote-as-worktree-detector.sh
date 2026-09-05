#!/usr/bin/env bash
# remote-as-worktree-detector.sh — Phase 1: detect remotes that are local-FS
# paths (a known footgun).
#
# Cass-mined real footgun: "frankensqlite's `origin` pointed to local worktree,
# needed to use `github` remote". When `git push` would target a local-fs
# clone (typically a sibling worktree directory or a personal mirror), the
# Phase 11 push instructions silently push into the wrong place.
#
# Per worktree this script:
#   1. Runs `git remote -v` against the worktree.
#   2. Classifies each URL as one of:
#        local-path   — absolute or relative filesystem path resolves to a
#                       directory on the host
#        http         — http://... / https://...
#        ssh          — ssh://... or git@host:path
#        git          — git://... protocol
#        unknown      — anything else
#   3. Recommends an action:
#        local-fork   — local-path; rename the remote to `local-fork`,
#                       add a real (http/ssh) remote
#        confirm-intentional — local-path resolving to a non-suspect target;
#                       record but don't auto-flag
#        ok           — http/ssh/git
#
# Output: <workspace>/remote_topology.md + <workspace>/remote_topology.tsv.
#
# Read-only — never `git remote set-url`, `git remote rename`, or modifies
# config. The Phase 11 handoff reads this file to embed correct push
# instructions.
#
# Resume-aware: skips re-scanning when worktrees.tsv hasn't changed.
#
# Exit codes:
#   0  scan complete (report written)
#   2  preflight failed (worktrees.tsv missing)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: remote-as-worktree-detector.sh <project-path>

Phase 1. Per worktree, classifies each remote URL as local-path / http / ssh
/ git protocol, and recommends an action. Read-only on the repo and remote
configs.

Output:
  <workspace>/remote_topology.tsv
  <workspace>/remote_topology.md

Env:
  WORKSPACE                       Workspace dir override.
  REMOTE_DETECT_FORCE=1           Force re-scan even when worktrees.tsv unchanged.

Exit codes:
  0  scan complete
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
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
TSV="$WORKSPACE_DIR/remote_topology.tsv"
MD="$WORKSPACE_DIR/remote_topology.md"

[[ -f "$WORKTREES_TSV" ]] || { echo "ERROR: $WORKTREES_TSV missing" >&2; exit 2; }

SIG=$(sha256sum "$WORKTREES_TSV" | awk '{print $1}')
if [[ -z "${REMOTE_DETECT_FORCE:-}" && -f "$MD" ]]; then
  if grep -qE "^<!-- signature: $SIG -->$" "$MD" 2>/dev/null; then
    log "remote_topology current for worktrees.tsv signature; reusing"
    echo "current: $MD"
    exit 0
  fi
fi

local_path_for_url() {
  local url="$1" worktree="$2" path
  path="$url"
  [[ "$path" == file://* ]] && path="${path#file://}"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *)  printf '%s\n' "$worktree/$path" ;;
  esac
}

classify_url() {
  local url="$1" worktree="$2"
  case "$url" in
    http://*|https://*) echo http ;;
    ssh://*) echo ssh ;;
    git://*) echo git ;;
    git@*:*) echo ssh ;;
    *@*:*)
      # user@host:path style — assume ssh.
      echo ssh
      ;;
    /*|.*|file://*)
      local path
      path=$(local_path_for_url "$url" "$worktree")
      # Local filesystem path. Verify it points at a directory.
      if [[ -d "$path" || -d "$path/.git" || -d "$path/objects" ]]; then
        echo local-path
      else
        echo unknown
      fi
      ;;
    *)
      # Could be a relative path or an unknown protocol. Try resolving.
      local path
      path=$(local_path_for_url "$url" "$worktree")
      if [[ -e "$path" ]]; then
        echo local-path
      else
        echo unknown
      fi
      ;;
  esac
}

recommend_action() {
  local kind="$1" url="$2" _remote_name="${3-}"
  case "$kind" in
    http|ssh|git) echo ok ;;
    local-path)
      # Heuristic: if the path resolves into a sibling worktree (i.e., another
      # checkout of THIS repo's basename), the user probably wants to rename
      # the remote and add a real one.
      local basename
      basename=$(basename "$PROJECT_ABS")
      if [[ "$url" == *"$basename"* ]]; then
        echo local-fork
      else
        echo confirm-intentional
      fi
      ;;
    *) echo confirm-intentional ;;
  esac
}

declare -i N_LOCAL=0
declare -i N_OK=0
declare -i N_UNKNOWN=0
declare -A SEEN_PATH

# Header.
printf 'worktree\tremote_name\turl\tkind\trecommended_action\n' > "$TSV"

while IFS= read -r row; do
  tsv_read "$row" path branch _detached _bare _locked _prunable _last_sha _last_date _dirty _staged _unstaged _untracked _untrack_count _age _inside _active _subm
  [[ "$path" == "path" ]] && continue
  [[ -z "$path" ]] && continue
  # The repo root may appear once as the main worktree entry in worktrees.tsv;
  # we still want to scan it. Skip already-seen paths.
  [[ -n "${SEEN_PATH[$path]:-}" ]] && continue
  SEEN_PATH[$path]=1

  if [[ ! -d "$path" ]]; then
    printf '%s\t-\t-\tmissing\tworktree-path-absent\n' "$path" >> "$TSV"
    continue
  fi

  # Walk remotes. `git -C $path remote -v` outputs e.g.:
  #   origin  https://github.com/foo/bar.git (fetch)
  #   origin  https://github.com/foo/bar.git (push)
  # We want unique (name,url) pairs.
  remotes=$(git -C "$path" remote -v 2>/dev/null | awk '{print $1"\t"$2}' | sort -u)
  if [[ -z "$remotes" ]]; then
    printf '%s\t-\t-\tno-remotes\tn/a\n' "$path" >> "$TSV"
    continue
  fi

  while IFS=$'\t' read -r rname rurl; do
    [[ -z "$rname" || -z "$rurl" ]] && continue
    kind=$(classify_url "$rurl" "$path")
    action_url="$rurl"
    if [[ "$kind" == "local-path" ]]; then
      action_url=$(local_path_for_url "$rurl" "$path")
    fi
    action=$(recommend_action "$kind" "$action_url" "$rname")
    case "$kind" in
      local-path) N_LOCAL=$((N_LOCAL+1)) ;;
      http|ssh|git) N_OK=$((N_OK+1)) ;;
      *) N_UNKNOWN=$((N_UNKNOWN+1)) ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$rname" "$rurl" "$kind" "$action" >> "$TSV"
  done <<< "$remotes"
done < "$WORKTREES_TSV"

# Markdown summary.
{
  printf '<!-- signature: %s -->\n' "$SIG"
  printf '# Remote topology — Phase 1\n\n'
  printf "Project:    \`%s\`\n" "$PROJECT_ABS"
  printf 'Generated:  %s\n\n' "$(date -u +%FT%TZ)"

  printf '## Counts\n\n'
  printf '| Class | Count |\n'
  printf '|-------|-------|\n'
  printf '| ok (http/ssh/git) | %d |\n' "$N_OK"
  printf '| local-path        | %d |\n' "$N_LOCAL"
  printf '| unknown           | %d |\n\n' "$N_UNKNOWN"

  if [[ "$N_LOCAL" -gt 0 ]]; then
    printf '## Local-path remotes detected\n\n'
    printf '> Cass-mined footgun: a remote that resolves to a local filesystem\n'
    printf "> path (e.g., a sibling worktree) silently routes \`git push\` into\n"
    printf '> the wrong place. Phase 11 push instructions reference only the\n'
    printf '> http/ssh/git remotes — the local-path entries are flagged here.\n\n'
    printf '| Worktree | Remote name | URL | Recommended action |\n'
    printf '|----------|-------------|-----|--------------------|\n'
    awk -F'\t' 'NR>1 && $4=="local-path" {printf "| `%s` | `%s` | `%s` | %s |\n", $1, $2, $3, $5}' "$TSV"
    printf '\n'
    printf '### Suggested remediation (manual; per AGENTS.md "No Script-Based Changes")\n\n'
    printf "1. Choose the canonical remote name (typically \`github\`, \`gitlab\`, or \`upstream\`).\n"
    printf "2. Rename the local-fs remote: \`git -C <worktree> remote rename origin local-fork\`\n"
    printf "3. Add a real remote: \`git -C <worktree> remote add github git@github.com:OWNER/REPO.git\`\n"
    printf '4. Re-run this script to confirm.\n\n'
  fi

  printf '## Full topology\n\n'
  printf '| Worktree | Remote name | URL | Kind | Action |\n'
  printf '|----------|-------------|-----|------|--------|\n'
  awk -F'\t' 'NR>1 {printf "| `%s` | `%s` | `%s` | %s | %s |\n", $1, $2, $3, $4, $5}' "$TSV"
  printf '\n'
  printf 'Phase 11 push instructions read this file to ensure they reference the\n'
  printf 'correct remote (http/ssh/git only — never local-path).\n'
} > "$MD"

log "wrote $TSV"
log "wrote $MD"
echo "ok=$N_OK local_path=$N_LOCAL unknown=$N_UNKNOWN"
exit 0
