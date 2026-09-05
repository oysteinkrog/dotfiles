#!/usr/bin/env bash
# gpg-resign.sh — Phase 8 follow-up: re-sign cherry-picked commits when the
# project requires signed commits.
#
# After `git cherry-pick`, the resulting commit is a NEW commit object — even
# if the source commit was signed, the cherry-picked commit is unsigned. On
# projects that require signed commits, every commit on the rationalization
# branch must be signed before merge.
#
# This script:
#   1. Reads <workspace>/project_profile.json:requires_signing.
#   2. If true, walks every commit between canonical and the rationalization
#      branch's tip via `git rev-list --reverse <canonical>..<RB>`.
#   3. For each unsigned commit, performs `git commit --amend --no-edit -S`
#      via an interactive rebase EXEC step (so the chain is re-signed
#      end-to-end without rewriting parent history).
#   4. Logs each amend to <workspace>/gpg_resign_log.tsv.
#
# Per AGENTS.md "Mandatory explicit plan", this script REFUSES to act unless
# explicit verbatim authorization is on file at
# <workspace>/gpg_resign_authorization.txt — because re-signing rewrites
# every recovered commit's SHA and ripples into apply_log.tsv.
#
# Skips silently when:
#   - project_profile.json:requires_signing is false / missing
#   - no commits between canonical and RB
#   - gpg / git's signing config is missing
#
# Per AGENTS.md "Irreversible Git Actions", never runs `git rebase -i` with
# `--no-edit` as a flag (that's not a valid rebase option); the EXEC commands
# use `git commit --amend --no-edit -S`. Never `--no-verify`. Never
# force-pushes — re-signing is local-only; the user pushes after review.
#
# Exit codes:
#   0  re-signed (or skipped silently)
#   2  preflight failed
#   3  rationalization branch not found
#   4  signed-commits required but signing config absent
#   5  authorization missing
#   6  amend failed mid-flight (rebase aborted; original branch tip preserved)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: gpg-resign.sh <project-path>

Phase 8 follow-up. Re-signs every unsigned commit between canonical and the
rationalization branch's tip, when the project requires signed commits.

Authorization gate: the file
  <workspace>/gpg_resign_authorization.txt
must contain (case-insensitive) the phrase:
  yes I authorize re-signing the rationalization branch
otherwise the script REFUSES to act.

Skips silently when:
  - project_profile.json:requires_signing is false / unset
  - the rationalization branch has no commits beyond canonical
  - signing config (user.signingkey + gpg/ssh helper) is missing — exit 4

Env:
  WORKSPACE                  Workspace dir override.
  RATIONALIZATION_BRANCH     Override the rationalization branch name.
Exit codes:
  0  re-signed or skipped silently
  2  preflight failed
  3  rationalization branch not found
  4  signing required but config missing
  5  authorization missing
  6  amend failed mid-flight
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
AUTH_FILE="$WORKSPACE_DIR/gpg_resign_authorization.txt"
LOG_TSV="$WORKSPACE_DIR/gpg_resign_log.tsv"
APPLY_LOG="$WORKSPACE_DIR/apply_log.tsv"

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

REQUIRES_SIGNING=$(profile_value requires_signing)
if [[ "$REQUIRES_SIGNING" != "true" && "$REQUIRES_SIGNING" != "1" ]]; then
  log "project_profile.json:requires_signing is not true; skipping silently"
  exit 0
fi

CANONICAL=$(profile_value canonical_branch)
DATE_TAG=$(date -u +%Y-%m-%d)
PROFILE_RB=$(profile_value rationalization_branch)
[[ -z "$PROFILE_RB" ]] && PROFILE_RB="branch-rationalization-$DATE_TAG"
RB="${RATIONALIZATION_BRANCH:-$PROFILE_RB}"

if ! git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$RB" >/dev/null 2>&1; then
  echo "ERROR: rationalization branch '$RB' not found." >&2
  exit 3
fi
RB_REF="refs/heads/$RB"

if git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/heads/$CANONICAL"
elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/remotes/origin/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/remotes/origin/$CANONICAL"
else
  echo "ERROR: canonical branch '$CANONICAL' does not resolve locally or as origin/$CANONICAL." >&2
  exit 2
fi

# Resolve the set of commits.
mapfile -t COMMITS < <(git -C "$PROJECT_ABS" rev-list --reverse "$CANON_REF..$RB_REF" 2>/dev/null)
if [[ ${#COMMITS[@]} -eq 0 ]]; then
  log "no commits between $CANON_REF and $RB; nothing to re-sign"
  exit 0
fi

WS_REL="$(basename "$WORKSPACE_DIR")"
if [[ -n "$(git -C "$PROJECT_ABS" status --porcelain=v2 --untracked-files=all -- . ":(exclude)$WS_REL" 2>/dev/null || true)" ]]; then
  echo "ERROR: working tree is dirty; refusing to re-sign with concurrent changes present." >&2
  echo "  Re-signing rewrites commits via rebase --exec and must run from a clean dedicated worktree." >&2
  echo "  Per AGENTS.md, this script does not stash, revert, or overwrite concurrent work." >&2
  exit 6
fi
if [[ -f "$APPLY_LOG" ]] && ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required to update apply_log.tsv after re-signing." >&2
  exit 2
fi

# Verify signing config is in place.
SIGNING_KEY=$(git -C "$PROJECT_ABS" config --get user.signingkey 2>/dev/null || true)
GPG_FORMAT=$(git -C "$PROJECT_ABS" config --get gpg.format 2>/dev/null || echo "openpgp")
if [[ -z "$SIGNING_KEY" ]]; then
  echo "ERROR: signing required but user.signingkey is unset." >&2
  echo "Set it via: git config user.signingkey <key>" >&2
  exit 4
fi
case "$GPG_FORMAT" in
  openpgp|"")
    if ! command -v gpg >/dev/null 2>&1; then
      echo "ERROR: signing required (openpgp) but gpg not on PATH." >&2
      exit 4
    fi
    ;;
  ssh)
    : # ssh-signing relies on git's bundled support
    ;;
  *)
    echo "ERROR: unsupported gpg.format='$GPG_FORMAT'." >&2
    exit 4
    ;;
esac

# Authorization gate.
AUTH_RE='yes[[:space:]]+i[[:space:]]+authorize[[:space:]]+re-?signing[[:space:]]+the[[:space:]]+rationalization[[:space:]]+branch'
if [[ ! -s "$AUTH_FILE" ]]; then
  echo "REFUSED: $AUTH_FILE missing." >&2
  echo "Re-signing rewrites every commit between $CANON_REF and $RB" >&2
  echo "(${#COMMITS[@]} commits). Per AGENTS.md 'Mandatory explicit plan', verbatim" >&2
  echo "authorization must be on file before any amend runs." >&2
  echo
  echo "To authorize, write to $AUTH_FILE:" >&2
  echo "  yes I authorize re-signing the rationalization branch" >&2
  exit 5
fi
if ! grep -iqE "$AUTH_RE" "$AUTH_FILE"; then
  echo "REFUSED: authorization phrase not found in $AUTH_FILE." >&2
  echo "Expected (case-insensitive): yes I authorize re-signing the rationalization branch" >&2
  exit 5
fi

# Identify which commits are already signed and which aren't.
declare -a UNSIGNED=()
for sha in "${COMMITS[@]}"; do
  # %G? prints G (good), B (bad), U (unknown), N (no signature), X (expired sig),
  # Y (expired key), R (revoked), E (cannot check).
  status=$(git -C "$PROJECT_ABS" log -1 --format='%G?' "$sha" 2>/dev/null || echo "N")
  case "$status" in
    G|U) : ;;          # already signed (good or untrusted-but-present)
    *) UNSIGNED+=("$sha") ;;
  esac
done

if [[ ${#UNSIGNED[@]} -eq 0 ]]; then
  log "all ${#COMMITS[@]} commits already signed; nothing to do"
  exit 0
fi

log "${#UNSIGNED[@]} of ${#COMMITS[@]} commits unsigned; re-signing via rebase --exec"

# Initialize log if absent.
if [[ ! -f "$LOG_TSV" ]]; then
  printf 'old_sha\tnew_sha\ttimestamp_utc\tnotes\n' > "$LOG_TSV"
fi

# Stash old tip so we can roll back on failure.
PRE_TIP=$(git -C "$PROJECT_ABS" rev-parse "$RB_REF")
log "pre-resign tip: $PRE_TIP"

# Use rebase --exec from a clean worktree only. The --exec command runs AFTER
# each commit is replayed, amending it to add the signature. We do not
# pass --no-edit to rebase itself (that's not a valid rebase option); we pass
# it to commit --amend.
ORIG_BRANCH=$(git -C "$PROJECT_ABS" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
ORIG_COMMIT=$(git -C "$PROJECT_ABS" rev-parse HEAD 2>/dev/null || echo "")
SWITCHED=0
if [[ "$ORIG_BRANCH" != "$RB" ]]; then
  git -C "$PROJECT_ABS" switch --quiet "$RB"
  SWITCHED=1
fi

restore_checkout_state() {
  local branch="$1" commit="$2"
  if [[ -n "$branch" ]]; then
    git -C "$PROJECT_ABS" switch --quiet "$branch" 2>/dev/null || true
  elif [[ -n "$commit" ]]; then
    git -C "$PROJECT_ABS" checkout --quiet --detach "$commit" 2>/dev/null || true
  fi
}

restore_branch() {
  # shellcheck disable=SC2317  # Invoked by the EXIT trap.
  if [[ "$SWITCHED" -eq 1 ]]; then
    # shellcheck disable=SC2317  # Invoked by the EXIT trap.
    restore_checkout_state "$ORIG_BRANCH" "$ORIG_COMMIT"
  fi
}
trap restore_branch EXIT

if git -C "$PROJECT_ABS" rebase --exec 'git commit --amend --no-edit -S' "$CANON_REF" >/dev/null 2>&1; then
  POST_TIP=$(git -C "$PROJECT_ABS" rev-parse "$RB_REF")
  log "rebase --exec re-sign succeeded: $PRE_TIP -> $POST_TIP"

  # Walk new commits, log old->new mapping by paired position.
  mapfile -t NEW_COMMITS < <(git -C "$PROJECT_ABS" rev-list --reverse "$CANON_REF..$RB_REF" 2>/dev/null)
  if [[ ${#NEW_COMMITS[@]} -eq ${#COMMITS[@]} ]]; then
    ts=$(date -u +%FT%TZ)
    for i in "${!COMMITS[@]}"; do
      old_sha="${COMMITS[$i]}"
      new_sha="${NEW_COMMITS[$i]}"
      printf '%s\t%s\t%s\t%s\n' "$old_sha" "$new_sha" "$ts" "re-signed via gpg-resign.sh" >> "$LOG_TSV"
    done
    if [[ -f "$APPLY_LOG" ]]; then
      python3 - "$APPLY_LOG" "${COMMITS[@]}" -- "${NEW_COMMITS[@]}" <<'PY'
import sys

path = sys.argv[1]
sep = sys.argv.index("--")
old = sys.argv[2:sep]
new = sys.argv[sep + 1:]
mapping = dict(zip(old, new))

with open(path, encoding="utf-8", newline="") as f:
    lines = f.readlines()

out = []
for line in lines:
    stripped = line.rstrip("\n")
    cols = stripped.split("\t")
    if len(cols) >= 4 and cols[3] in mapping:
        cols[3] = mapping[cols[3]]
        out.append("\t".join(cols) + ("\n" if line.endswith("\n") else ""))
    else:
        out.append(line)

tmp = path + ".gpg-resign-new"
with open(tmp, "w", encoding="utf-8", newline="") as f:
    f.writelines(out)
PY
      mv "$APPLY_LOG.gpg-resign-new" "$APPLY_LOG"
      log "updated apply_log.tsv commit SHAs after re-sign"
    fi
  fi
  echo "re-signed ${#UNSIGNED[@]} commit(s); new tip: $POST_TIP"
  exit 0
else
  rc=$?
  log "rebase --exec failed (exit $rc); aborting rebase"
  git -C "$PROJECT_ABS" rebase --abort >/dev/null 2>&1 || true
  echo "ERROR: re-sign failed; rebase aborted; $RB tip unchanged at $PRE_TIP" >&2
  exit 6
fi
