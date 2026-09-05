#!/usr/bin/env bash
# drop-retire-confirmed.sh — Phase 10: hard-gated worktree removal + branch
# deletion, one operation per invocation.
#
# Two invocation forms — one per individual operation, never a master flag:
#   drop-retire-confirmed.sh <project-path> worktree <path>   confirm=YES_REMOVE_WT_<basename-of-path>
#   drop-retire-confirmed.sh <project-path> branch   <name>   confirm=YES_DELETE_BR_<slug>
#
# Order policy (the orchestrator runs the cleanup-conductor in this exact
# sequence; this script enforces per-operation gates regardless):
#   1. Worktrees first.
#   2. After every worktree is explicitly removed, the orchestrator runs
#      `git worktree prune` ONCE to clean residual admin metadata. (This script
#      does not prune; pruning as a substitute for explicit remove is forbidden
#      by Axiom 9 — the prune step lives in the cleanup-conductor's plan.)
#   3. Branches second, in this verdict order:
#        garbage → superseded → already-merged → novel-stale →
#        divergent-refactor (only if user opted in) → applied-keepers
#      Prefer `git branch -d` over `-D` (Axiom 8). `-D` is used only with
#      explicit BRANCH_FORCE_OK=1 and the user's verbatim acknowledgment.
#
# Hard refusals:
#   - Currently-active worktree: NEVER removed (auto-protected; the user
#     removes it themselves from a different cwd after the run).
#   - Currently-checked-out branch: NEVER deleted.
#   - Protected (canonical, release/*, hotfix/*, dependabot/*, renovate/*,
#     gh-pages, anything in protected.tsv): NEVER deleted.
#   - Backup ref must exist for the branch and match the live SHA before any
#     branch deletion.
#
# Flags / env:
#   confirm=...                              Required, exact match per operation.
#   CLEANUP_AUTHORIZATION_OVERRIDE_OK=1      Bypass plan-level authorization (NOT recommended).
#   CLEANUP_AUDIT_GATE_OVERRIDE_OK=1         Bypass Phase 9.5 audit gate (NOT recommended).
#   BRANCH_FORCE_OK=1                        Use `git branch -D` instead of `-d`.
#   WORKTREE_FORCE_OK=1                      Use `git worktree remove --force` (dirty state must
#                                            already be in the bundle).
#   DIVERGENT_REFACTOR_DELETE_OK=1           Allow deleting a divergent-refactor branch.
#
# Exit codes:
#   0  removed/deleted
#   2  confirm flag wrong
#   3  preflight failed
#   5  refusal: protection / preconditions
#   6  operation failed at git layer
#   7  authorization missing

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage:
  drop-retire-confirmed.sh <project-path> worktree <path> confirm=YES_REMOVE_WT_<basename>
  drop-retire-confirmed.sh <project-path> branch   <name> confirm=YES_DELETE_BR_<slug>

Phase 10. Removes ONE worktree or deletes ONE branch with hard verbatim
confirmation. Worktrees first; the cleanup-conductor runs \`git worktree prune\`
between phases — never as a substitute for explicit removal.

Env:
  CLEANUP_AUTHORIZATION_OVERRIDE_OK=1   Bypass plan-level authorization (NOT recommended).
  CLEANUP_AUDIT_GATE_OVERRIDE_OK=1      Bypass Phase 9.5 audit gate (NOT recommended).
  BRANCH_FORCE_OK=1                     Use \`-D\` instead of \`-d\`.
  WORKTREE_FORCE_OK=1                   Use \`worktree remove --force\`.
  DIVERGENT_REFACTOR_DELETE_OK=1        Allow deleting a divergent-refactor branch.

Exit codes:
  0  done
  2  confirm flag wrong
  3  preflight failed
  5  refusal
  6  git operation failed
  7  authorization missing
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
KIND="${2:?missing kind: worktree | branch}"
TARGET="${3:?missing target}"
CONFIRM="${4:-}"

PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 3
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
PROFILE="$WORKSPACE_DIR/project_profile.json"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
TRIAGE="$WORKSPACE_DIR/triage.tsv"
APPLY_LOG="$WORKSPACE_DIR/apply_log.tsv"
PLAN="$WORKSPACE_DIR/harmonization_plan.md"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"
PROTECTED_TSV="$WORKSPACE_DIR/protected.tsv"
CLEANUP_LOG="$WORKSPACE_DIR/cleanup_log.tsv"
AUTH_FILE="$WORKSPACE_DIR/cleanup_authorization.txt"
AUDIT_GATE_FILE="$WORKSPACE_DIR/audit_gate.txt"
AUDIT_REPORT="$WORKSPACE_DIR/audit_report.md"

for f in "$PROFILE" "$BRANCHES_TSV" "$WORKTREES_TSV" "$TRIAGE" "$BUNDLE_PATH_FILE"; do
  [[ -f "$f" ]] || {
    echo "ERROR: $f missing — Phase 10 cannot run before Phases 1, 2, 3, and 6 produce their artifacts." >&2
    case "$(basename "$f")" in
      project_profile.json) echo "  Fix: scripts/discover-project.sh <project-path> (Phase 1)" >&2 ;;
      branches.tsv|worktrees.tsv) echo "  Fix: scripts/discover-branches-worktrees.sh <project-path> (Phase 2)" >&2 ;;
      bundle_path.txt) echo "  Fix: scripts/build-bundle.sh <project-path> (Phase 3)" >&2 ;;
      triage.tsv) echo "  Fix: scripts/merge-triage.sh <project-path> after Phase 5 batches; triage must be frozen by Phase 6 user gate." >&2 ;;
    esac
    exit 3
  }
done
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"

# Plan-level authorization gate.
# Two acceptable phrase shapes (per AGENTS.md "Mandatory explicit plan"):
#   1. Count-bearing (canonical, used in user-facing intake/handoff/templates):
#        "yes I understand and want to remove <N> worktrees and delete <M> branches per the plan above"
#   2. Generic short form (used in scripts/templates that don't know the counts at write time):
#        "yes I understand and want to rationalize per the plan above"
# Either is accepted (case-insensitive). The count-bearing form is preferred when counts are known.
AUTH_RE_COUNT='^[[:space:]]*yes[[:space:]]+i[[:space:]]+understand[[:space:]]+and[[:space:]]+want[[:space:]]+to[[:space:]]+remove[[:space:]]+[0-9]+[[:space:]]+worktrees?[[:space:]]+and[[:space:]]+delete[[:space:]]+[0-9]+[[:space:]]+branch(es)?[[:space:]]+per[[:space:]]+the[[:space:]]+plan[[:space:]]+above[[:space:]]*$'
AUTH_RE_SHORT='^[[:space:]]*yes[[:space:]]+i[[:space:]]+understand[[:space:]]+and[[:space:]]+want[[:space:]]+to[[:space:]]+rationalize[[:space:]]+per[[:space:]]+the[[:space:]]+plan[[:space:]]+above[[:space:]]*$'
if [[ -z "${CLEANUP_AUTHORIZATION_OVERRIDE_OK:-}" ]]; then
  if [[ ! -s "$AUTH_FILE" ]]; then
    echo "REFUSED: cleanup_authorization.txt is missing or empty." >&2
    echo "  $AUTH_FILE" >&2
    echo "Per AGENTS.md 'Mandatory explicit plan', the user's verbatim authorization" >&2
    echo "must be on file before any destructive Phase 10 operation runs." >&2
    exit 7
  fi
  if ! { grep -Eiq "$AUTH_RE_COUNT" "$AUTH_FILE" || grep -Eiq "$AUTH_RE_SHORT" "$AUTH_FILE"; }; then
    echo "REFUSED: cleanup_authorization.txt does not contain a recognized authorization sentence." >&2
    echo "Expected one of (case-insensitive):" >&2
    echo "  1. yes I understand and want to remove <N> worktrees and delete <M> branches per the plan above" >&2
    echo "  2. yes I understand and want to rationalize per the plan above" >&2
    exit 7
  fi
fi

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

hash_or_missing() {
  local path="$1"
  if [[ -f "$path" ]]; then
    sha256sum "$path" | awk '{print $1}'
  else
    printf 'missing'
  fi
}
CANONICAL=$(profile_value canonical_branch)
BACKUP_NS="refs/branch-rationalization-backup"
AUDITED_RB=""
AUDITED_RB_TIP=""

require_audit_gate_passed() {
  local gate_value="" date_tag profile_rb rb rb_ref rb_tip sig_profile sig sig_apply sig_plan sig_inputs

  if [[ -n "${CLEANUP_AUDIT_GATE_OVERRIDE_OK:-}" ]]; then
    echo "WARNING: CLEANUP_AUDIT_GATE_OVERRIDE_OK=1 bypasses the Phase 9.5 audit gate." >&2
    date_tag=$(date -u +%Y-%m-%d)
    profile_rb=$(profile_value rationalization_branch)
    [[ -z "$profile_rb" ]] && profile_rb="branch-rationalization-$date_tag"
    AUDITED_RB="${RATIONALIZATION_BRANCH:-$profile_rb}"
    AUDITED_RB_TIP=$(git -C "$PROJECT_ABS" rev-parse --verify HEAD 2>/dev/null || true)
    if [[ -z "$AUDITED_RB_TIP" ]]; then
      echo "REFUSED: current HEAD does not resolve for audit-gate override cleanup." >&2
      return 1
    fi
    return 0
  fi

  if [[ ! -s "$AUDIT_GATE_FILE" ]]; then
    echo "REFUSED: Phase 9.5 audit gate is missing at $AUDIT_GATE_FILE." >&2
    echo "Run audit-rationalization-branch.sh and require a passing audit before Phase 10 cleanup." >&2
    return 1
  fi

  IFS= read -r gate_value < "$AUDIT_GATE_FILE" || gate_value=""
  if [[ "$gate_value" != "0" ]]; then
    echo "REFUSED: Phase 9.5 audit gate is not passing (value='$gate_value')." >&2
    echo "Phase 10 cleanup is blocked until audit-rationalization-branch.sh writes 0." >&2
    return 1
  fi

  date_tag=$(date -u +%Y-%m-%d)
  profile_rb=$(profile_value rationalization_branch)
  [[ -z "$profile_rb" ]] && profile_rb="branch-rationalization-$date_tag"
  rb="${RATIONALIZATION_BRANCH:-$profile_rb}"
  rb_ref="refs/heads/$rb"
  if ! rb_tip=$(git -C "$PROJECT_ABS" rev-parse --verify "$rb_ref" 2>/dev/null); then
    echo "REFUSED: rationalization branch '$rb' does not resolve for audit-gate validation." >&2
    return 1
  fi

  if [[ ! -f "$AUDIT_REPORT" ]]; then
    echo "REFUSED: audit report missing at $AUDIT_REPORT." >&2
    return 1
  fi
  sig_profile=$(sha256sum "$PROFILE" | awk '{print $1}')
  sig="audit/v1 rb=$rb tip=$rb_tip profile=$sig_profile"
  if ! grep -qxF "<!-- signature: $sig -->" "$AUDIT_REPORT"; then
    echo "REFUSED: audit report signature does not match the current rationalization tip." >&2
    echo "  expected: $sig" >&2
    echo "Re-run audit-rationalization-branch.sh before Phase 10 cleanup." >&2
    return 1
  fi
  sig_apply=$(hash_or_missing "$APPLY_LOG")
  sig_plan=$(hash_or_missing "$PLAN")
  sig_inputs="audit-inputs/v1 apply=$sig_apply plan=$sig_plan"
  if ! grep -qxF "<!-- inputs: $sig_inputs -->" "$AUDIT_REPORT"; then
    echo "REFUSED: audit report inputs do not match current apply_log.tsv / harmonization_plan.md." >&2
    echo "  expected: $sig_inputs" >&2
    echo "Re-run audit-rationalization-branch.sh before Phase 10 cleanup." >&2
    return 1
  fi
  AUDITED_RB="$rb"
  AUDITED_RB_TIP="$rb_tip"
}

require_audit_gate_passed || exit 5

# Initialize cleanup log.
if [[ ! -f "$CLEANUP_LOG" ]]; then
  printf 'phase\tkind\ttarget\tverdict\tcommand_run\tbackup_ref\ttimestamp_utc\tnotes\n' > "$CLEANUP_LOG"
fi

# Active branch / active worktree (must NEVER be deleted/removed).
ACTIVE_BR=$(git -C "$PROJECT_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
ACTIVE_WT="$PROJECT_ABS"
CALLER_PWD=$(pwd -P 2>/dev/null || pwd)
CALLER_WT=$(git -C "$CALLER_PWD" rev-parse --show-toplevel 2>/dev/null || true)

canonical_dir() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd -- "$path" && pwd -P) 2>/dev/null || printf '%s\n' "$path"
  else
    printf '%s\n' "$path"
  fi
}

ACTIVE_WT_REAL=$(canonical_dir "$ACTIVE_WT")
CALLER_WT_REAL=""
if [[ -n "$CALLER_WT" ]]; then
  CALLER_WT_REAL=$(canonical_dir "$CALLER_WT")
fi

is_protected_branch() {
  local name="$1"
  [[ "$name" == "$CANONICAL" ]] && return 0
  [[ "$name" == "$ACTIVE_BR" ]] && return 0
  # Patterns from project_profile.protected_patterns.
  if command -v jq >/dev/null 2>&1; then
    local pats
    pats=$(jq -r '.protected_patterns[]?' "$PROFILE" 2>/dev/null || true)
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      # shellcheck disable=SC2053  # glob match against $name is intentional
      [[ "$name" == $p ]] && return 0
    done <<< "$pats"
  fi
  if [[ -f "$PROTECTED_TSV" ]]; then
    awk -F'\t' -v n="$name" 'NR > 1 && $1 == "branch" && $2 == n {found=1} END {exit !found}' "$PROTECTED_TSV" && return 0
  fi
  return 1
}

is_protected_worktree() {
  local path="$1"
  local path_real
  path_real=$(canonical_dir "$path")
  [[ "$path" == "$ACTIVE_WT" ]] && return 0
  [[ "$path_real" == "$ACTIVE_WT_REAL" ]] && return 0
  [[ -n "$CALLER_WT" && "$path" == "$CALLER_WT" ]] && return 0
  [[ -n "$CALLER_WT_REAL" && "$path_real" == "$CALLER_WT_REAL" ]] && return 0
  if [[ -f "$PROTECTED_TSV" ]]; then
    awk -F'\t' -v p="$path" 'NR > 1 && $1 == "worktree" && $2 == p {found=1} END {exit !found}' "$PROTECTED_TSV" && return 0
  fi
  return 1
}

cleanup_phase_for_branch() {
  case "$1" in
    garbage) echo "B" ;;
    superseded) echo "C" ;;
    already-merged) echo "D" ;;
    novel-but-stale) echo "E" ;;
    divergent-refactor) echo "F" ;;
    novel-and-accretive|partially-novel|dirty-worktree-only) echo "G" ;;
    *) echo "?" ;;
  esac
}

require_matching_bundle_file() {
  local label="$1" live_hash="$2" file="$3" bundle_hash
  if [[ ! -f "$file" ]]; then
    echo "REFUSED: bundle $label capture missing at $file; removal would be irreversible." >&2
    return 1
  fi
  bundle_hash=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
  if [[ "$live_hash" != "$bundle_hash" ]]; then
    echo "REFUSED: worktree $label drifted since the bundle was built." >&2
    echo "  live_sha256=$live_hash" >&2
    echo "  bundle_sha256=$bundle_hash" >&2
    echo "Re-run inventory + bundle build before removing this worktree." >&2
    return 1
  fi
}

require_worktree_bundle_current() {
  local wt_path="$1" wt_bundle="$2"
  local live_status_hash live_staged_hash live_unstaged_hash current_untracked_count
  local live_untracked_hash bundle_untracked_hash

  if [[ ! -d "$wt_path" ]]; then
    echo "REFUSED: worktree path $wt_path is absent; cannot verify live dirty state." >&2
    return 1
  fi

  if ! live_status_hash=$(git -C "$wt_path" status --porcelain=v2 --untracked-files=all 2>/dev/null | sha256sum | awk '{print $1}'); then
    echo "REFUSED: cannot snapshot current worktree status for $wt_path." >&2
    return 1
  fi
  require_matching_bundle_file STATUS "$live_status_hash" "$wt_bundle/status.txt" || return 1

  if ! live_staged_hash=$(git -C "$wt_path" diff --binary --cached 2>/dev/null | sha256sum | awk '{print $1}'); then
    echo "REFUSED: cannot snapshot current staged diff for $wt_path." >&2
    return 1
  fi
  require_matching_bundle_file STAGED "$live_staged_hash" "$wt_bundle/staged.diff" || return 1

  if ! live_unstaged_hash=$(git -C "$wt_path" diff --binary 2>/dev/null | sha256sum | awk '{print $1}'); then
    echo "REFUSED: cannot snapshot current unstaged diff for $wt_path." >&2
    return 1
  fi
  require_matching_bundle_file UNSTAGED "$live_unstaged_hash" "$wt_bundle/unstaged.diff" || return 1

  if ! current_untracked_count=$(git -C "$wt_path" ls-files --others --exclude-standard -z 2>/dev/null \
    | tr -cd '\000' | wc -c | awk '{print $1 + 0}'); then
    echo "REFUSED: cannot enumerate current untracked files for $wt_path." >&2
    return 1
  fi
  if [[ "$current_untracked_count" -gt 0 ]]; then
    if [[ ! -f "$wt_bundle/untracked.tar.gz" ]]; then
      echo "REFUSED: current worktree has $current_untracked_count untracked file(s), but bundle has no untracked.tar.gz." >&2
      return 1
    fi
    if [[ ! -s "$wt_bundle/.untracked.list" ]]; then
      echo "REFUSED: current worktree has $current_untracked_count untracked file(s), but bundle has no NUL manifest at $wt_bundle/.untracked.list." >&2
      return 1
    fi
    if ! tar --null -tzf "$wt_bundle/untracked.tar.gz" -T "$wt_bundle/.untracked.list" >/dev/null 2>&1; then
      echo "REFUSED: bundle untracked.tar.gz is unreadable at $wt_bundle/untracked.tar.gz." >&2
      return 1
    fi
    if [[ ! -s "$wt_bundle/.untracked.sha256" ]]; then
      echo "REFUSED: current worktree has $current_untracked_count untracked file(s), but bundle has no byte manifest at $wt_bundle/.untracked.sha256." >&2
      return 1
    fi
    if ! live_untracked_hash=$(untracked_content_manifest_hash_for_root "$wt_path" <(git -C "$wt_path" ls-files --others --exclude-standard -z | sort -z) 2>/dev/null); then
      echo "REFUSED: cannot hash current untracked content for $wt_path." >&2
      return 1
    fi
    bundle_untracked_hash=$(sha256sum "$wt_bundle/.untracked.sha256" 2>/dev/null | awk '{print $1}')
    if [[ "$live_untracked_hash" != "$bundle_untracked_hash" ]]; then
      echo "REFUSED: untracked content drifted since the bundle was built." >&2
      echo "  live_untracked_sha256=$live_untracked_hash" >&2
      echo "  bundle_untracked_sha256=$bundle_untracked_hash" >&2
      echo "Re-run inventory + bundle build before removing this worktree." >&2
      return 1
    fi
  fi
}

require_applied_keeper_current() {
  local name="$1" verdict="$2" applied_sha=""

  case "$verdict" in
    novel-and-accretive|partially-novel|dirty-worktree-only) ;;
    *) return 0 ;;
  esac

  if [[ ! -f "$APPLY_LOG" ]]; then
    echo "REFUSED: $name has verdict '$verdict' but $APPLY_LOG is missing." >&2
    echo "Applied-keeper branches may be deleted only after a passed apply_log.tsv row." >&2
    return 1
  fi

  applied_sha=$(awk -F'\t' -v t="$name" '
    NR > 1 && $1 == "branch" && $2 == t && $4 != "" && $6 == "passed" {print $4; exit}
  ' "$APPLY_LOG" 2>/dev/null || true)
  if [[ -z "$applied_sha" ]]; then
    echo "REFUSED: $name has verdict '$verdict' but no passed branch apply row." >&2
    echo "Apply the keeper onto the rationalization branch before deleting its source branch." >&2
    return 1
  fi
  if ! git -C "$PROJECT_ABS" rev-parse --verify --quiet "$applied_sha^{commit}" >/dev/null 2>&1; then
    echo "REFUSED: apply_log.tsv points at non-resolving commit $applied_sha for $name." >&2
    return 1
  fi
  if ! git -C "$PROJECT_ABS" merge-base --is-ancestor "$applied_sha" "$AUDITED_RB_TIP" 2>/dev/null; then
    echo "REFUSED: applied commit $applied_sha for $name is not reachable from the audited rationalization branch tip." >&2
    echo "Re-run Phase 8 and Phase 9.5 before deleting its source branch." >&2
    return 1
  fi
}

require_branch_cleanup_head_context() {
  local current_head=""
  current_head=$(git -C "$PROJECT_ABS" rev-parse --verify HEAD 2>/dev/null || true)
  if [[ -z "$current_head" || "$current_head" != "$AUDITED_RB_TIP" ]]; then
    echo "REFUSED: branch cleanup must run with HEAD at the audited rationalization tip." >&2
    echo "  audited_branch=$AUDITED_RB" >&2
    echo "  audited_tip=$AUDITED_RB_TIP" >&2
    echo "  current_head=${current_head:-unresolved}" >&2
    echo "This keeps git branch -d's merged-into check aligned with the passed audit." >&2
    return 1
  fi
}

require_branch_object_bundle_current() {
  local backup_ref="$1" expected_sha="$2"
  local pack="$BUNDLE/object-bundle.pack"
  local heads pack_sha

  if [[ ! -f "$pack" ]]; then
    echo "REFUSED: object-bundle.pack missing; branch deletion would rely only on an in-repo backup ref." >&2
    echo "  expected_pack=$pack" >&2
    return 1
  fi
  if ! git -C "$PROJECT_ABS" bundle verify "$pack" >/dev/null 2>&1; then
    echo "REFUSED: object-bundle.pack does not pass git bundle verify." >&2
    echo "  pack=$pack" >&2
    return 1
  fi

  heads=$(git -C "$PROJECT_ABS" bundle list-heads "$pack" 2>/dev/null || true)
  pack_sha=$(awk -v ref="$backup_ref" '$2 == ref {print $1; exit}' <<< "$heads")
  if [[ -z "$pack_sha" ]]; then
    echo "REFUSED: object-bundle.pack does not contain $backup_ref." >&2
    echo "Re-run inventory + bundle build before deleting this branch." >&2
    return 1
  fi
  if [[ "$pack_sha" != "$expected_sha" ]]; then
    echo "REFUSED: object-bundle.pack SHA for $backup_ref does not match the live backup ref." >&2
    echo "  pack_sha=$pack_sha" >&2
    echo "  backup_sha=$expected_sha" >&2
    return 1
  fi
  if ! bundle_fetch_roundtrip "$pack" "$BACKUP_NS" "$WORKSPACE_DIR"; then
    echo "REFUSED: object-bundle.pack cannot fetch the backup namespace into a fresh object database." >&2
    echo "Recovery would fail after deletion; rebuild the bundle first." >&2
    return 1
  fi
}

# ---- Branch case ----
if [[ "$KIND" == "branch" ]]; then
  NAME="$TARGET"
  SLUG=$(slugify_branch "$NAME")
  EXPECTED="confirm=YES_DELETE_BR_${SLUG}"
  if [[ "$CONFIRM" != "$EXPECTED" ]]; then
    echo "REFUSED: confirm flag must be exactly \"$EXPECTED\"" >&2
    echo "Got: \"$CONFIRM\"" >&2
    exit 2
  fi

  if is_protected_branch "$NAME"; then
    echo "REFUSED: $NAME is protected (canonical / active / pattern-protected / explicit list)." >&2
    exit 5
  fi

  # Backup ref existence + byte-equality.
  BACKUP_REF="$BACKUP_NS/$SLUG"
  BACKUP_SHA=$(git -C "$PROJECT_ABS" rev-parse --verify --quiet "$BACKUP_REF^{commit}" 2>/dev/null || true)
  LIVE_SHA=$(git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$NAME^{commit}" 2>/dev/null || true)
  if [[ -z "$BACKUP_SHA" ]]; then
    echo "REFUSED: backup ref $BACKUP_REF does not exist; deletion would be irreversible." >&2
    exit 5
  fi
  if [[ -z "$LIVE_SHA" ]]; then
    echo "REFUSED: branch $NAME does not exist (already deleted?)." >&2
    exit 5
  fi
  if [[ "$BACKUP_SHA" != "$LIVE_SHA" ]]; then
    echo "REFUSED: backup ref SHA ($BACKUP_SHA) != live branch SHA ($LIVE_SHA)." >&2
    echo "Re-run inventory + bundle build before deleting." >&2
    exit 5
  fi
  require_branch_object_bundle_current "$BACKUP_REF" "$BACKUP_SHA" || exit 5

  # Verdict bucket gate.
  VERDICT=$(awk -F'\t' -v t="$NAME" 'NR > 1 && $1 == "branch" && $2 == t {print $3; exit}' "$TRIAGE" || true)
  case "$VERDICT" in
    garbage|superseded|already-merged|novel-but-stale|divergent-refactor|novel-and-accretive|partially-novel|dirty-worktree-only) ;;
    "" )
      echo "REFUSED: $NAME has no triage verdict; resolve it before deletion." >&2
      exit 5
      ;;
    protected-preserve|unknown|*)
      echo "REFUSED: $NAME has verdict '$VERDICT' (not deletable in Phase 10)." >&2
      exit 5
      ;;
  esac
  if [[ "$VERDICT" == "divergent-refactor" && -z "${DIVERGENT_REFACTOR_DELETE_OK:-}" ]]; then
    echo "REFUSED: $NAME has verdict 'divergent-refactor' and requires DIVERGENT_REFACTOR_DELETE_OK=1." >&2
    echo "This verdict is opt-in because it may contain intentionally divergent design work." >&2
    exit 5
  fi
  require_applied_keeper_current "$NAME" "$VERDICT" || exit 5
  require_branch_cleanup_head_context || exit 5

  # Currently checked out (in any worktree)? Refuse — git itself would refuse, surface it cleanly.
  CHECKED_OUT_AT=$(git -C "$PROJECT_ABS" worktree list --porcelain 2>/dev/null \
    | awk -v b="refs/heads/$NAME" '
        BEGIN { p="" }
        /^worktree / { p=$2 }
        /^branch / && $2 == b { print p; exit }')
  if [[ -n "$CHECKED_OUT_AT" ]]; then
    echo "REFUSED: branch $NAME is checked out at $CHECKED_OUT_AT." >&2
    echo "Remove that worktree first, then re-run." >&2
    exit 5
  fi

  PHASE=$(cleanup_phase_for_branch "$VERDICT")
  if [[ "$PHASE" == "?" ]]; then
    echo "REFUSED: $NAME has verdict '$VERDICT' with no cleanup phase mapping." >&2
    exit 5
  fi

  if [[ -n "${BRANCH_FORCE_OK:-}" ]]; then
    printf -v COMMAND_RUN 'git -C %q branch -D %q' "$PROJECT_ABS" "$NAME"
  else
    printf -v COMMAND_RUN 'git -C %q branch -d %q' "$PROJECT_ABS" "$NAME"
  fi

  # Restate verbatim.
  log "About to run: $COMMAND_RUN"
  log "  Backup ref:    $BACKUP_REF"
  log "  Backup SHA:    $BACKUP_SHA"
  log "  Verdict:       $VERDICT"

  # Prefer -d over -D (Axiom 8). -D only with explicit force flag.
  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ -n "${BRANCH_FORCE_OK:-}" ]]; then
    if ! git -C "$PROJECT_ABS" branch -D "$NAME"; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$PHASE" "branch" "$NAME" "$VERDICT" "$COMMAND_RUN" "$BACKUP_REF" "$TIMESTAMP" "delete-D-failed" >> "$CLEANUP_LOG"
      exit 6
    fi
  else
    if ! git -C "$PROJECT_ABS" branch -d "$NAME"; then
      echo "REFUSED by git: branch $NAME is not fully merged into HEAD." >&2
      echo "If the user has explicitly authorized losing those commits, re-run with BRANCH_FORCE_OK=1." >&2
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$PHASE" "branch" "$NAME" "$VERDICT" "$COMMAND_RUN" "$BACKUP_REF" "$TIMESTAMP" "delete-d-refused-unmerged" >> "$CLEANUP_LOG"
      exit 6
    fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$PHASE" "branch" "$NAME" "$VERDICT" "$COMMAND_RUN" "$BACKUP_REF" "$TIMESTAMP" "deleted" >> "$CLEANUP_LOG"
  log "✓ Deleted branch $NAME; backup ref $BACKUP_REF intact."
  exit 0
fi

# ---- Worktree case ----
if [[ "$KIND" == "worktree" ]]; then
  WT_PATH="$TARGET"
  BASENAME_WT=$(basename "$WT_PATH")
  EXPECTED="confirm=YES_REMOVE_WT_${BASENAME_WT}"
  if [[ "$CONFIRM" != "$EXPECTED" ]]; then
    echo "REFUSED: confirm flag must be exactly \"$EXPECTED\"" >&2
    echo "Got: \"$CONFIRM\"" >&2
    exit 2
  fi

  if is_protected_worktree "$WT_PATH"; then
    echo "REFUSED: $WT_PATH is the active worktree or explicitly protected; never removed." >&2
    exit 5
  fi

  # Verify the worktree's dirty state (if any) is captured in the bundle.
  san=$(sanitize_path "$WT_PATH")
  WT_BUNDLE="$BUNDLE/worktrees/$san"
  if [[ ! -d "$WT_BUNDLE" ]]; then
    echo "REFUSED: bundle worktree dir missing at $WT_BUNDLE; removal would be irreversible." >&2
    exit 5
  fi

  # Verdict.
  VERDICT=$(awk -F'\t' -v t="$WT_PATH" 'NR > 1 && $1 == "worktree" && $2 == t {print $3; exit}' "$TRIAGE" || true)
  case "$VERDICT" in
    garbage|dirty-worktree-only) ;;
    "" )
      echo "REFUSED: $WT_PATH has no triage verdict; resolve it before removal." >&2
      exit 5
      ;;
    protected-preserve|unknown|*)
      echo "REFUSED: $WT_PATH has verdict '$VERDICT' (not removable in Phase 10)." >&2
      exit 5
      ;;
  esac

  require_worktree_bundle_current "$WT_PATH" "$WT_BUNDLE" || exit 5

  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  REMOVE_ARGS=()
  if [[ -n "${WORKTREE_FORCE_OK:-}" ]]; then
    REMOVE_ARGS+=(--force)
  fi
  if [[ ${#REMOVE_ARGS[@]} -gt 0 ]]; then
    printf -v COMMAND_RUN 'git -C %q worktree remove --force %q' "$PROJECT_ABS" "$WT_PATH"
  else
    printf -v COMMAND_RUN 'git -C %q worktree remove %q' "$PROJECT_ABS" "$WT_PATH"
  fi

  log "About to run: $COMMAND_RUN"
  log "  Bundle archive: $WT_BUNDLE"
  log "  Verdict:        $VERDICT"

  if ! git -C "$PROJECT_ABS" worktree remove "${REMOVE_ARGS[@]}" "$WT_PATH"; then
    echo "git worktree remove refused (likely dirty state). Inspect, then re-run with WORKTREE_FORCE_OK=1 only after confirming dirty state is in the bundle." >&2
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "A" "worktree" "$WT_PATH" "$VERDICT" "$COMMAND_RUN" "$WT_BUNDLE" "$TIMESTAMP" "remove-refused" >> "$CLEANUP_LOG"
    exit 6
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "A" "worktree" "$WT_PATH" "$VERDICT" "$COMMAND_RUN" "$WT_BUNDLE" "$TIMESTAMP" "removed" >> "$CLEANUP_LOG"
  log "✓ Removed worktree $WT_PATH; bundle archive $WT_BUNDLE intact."
  log "  (Run \`git worktree prune\` once after the full worktree-removal pass to clean residual metadata.)"
  exit 0
fi

echo "ERROR: unknown kind '$KIND' (expected 'worktree' or 'branch')" >&2
exit 3
