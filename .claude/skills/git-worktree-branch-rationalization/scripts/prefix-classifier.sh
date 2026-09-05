#!/usr/bin/env bash
# prefix-classifier.sh — Phase 2 / Phase 5 fast pre-filter.
#
# Classify a branch name into one of the canonical smell-categories defined in
# references/BRANCH-WORKTREE-SMELLS.md. Used by triage-batch.sh as a pre-filter
# before the heavyweight FINGERPRINT + VERIFY-ON-CANONICAL pass; the smell
# acts as a verdict prior with confidence ~0.7 (the user can always override).
#
# Two invocation forms:
#   prefix-classifier.sh <branch-name>            classify a single name
#   prefix-classifier.sh --tsv <project-path>     classify every branch in
#                                                 branches.tsv and write
#                                                 <workspace>/prefix_classification.tsv
#
# When called with no arg AND stdin is a pipe, reads names from stdin.
#
# Output for the single-name form: one TSV row to stdout —
#   <name>\t<smell-category>\t<verdict-prior>\t<confidence>
#
# Smell categories (canonical strings):
#   agent-attempt | wip-take | agent-cli | pre-deploy | release | hotfix |
#   dependabot | ticket-id | user-sandbox | feature | integration | train |
#   cherry-pick | revert | gone-upstream | merge-into | tag-equivalent |
#   unknown
#
# The `gone-upstream` category is data-dependent (needs branches.tsv); the
# single-name form never returns it.
#
# Exit codes:
#   0  classified
#   2  not a git work tree (--tsv only)
#   3  branches.tsv missing (--tsv only)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

usage() {
  cat <<USAGE
Usage:
  prefix-classifier.sh <branch-name>
  prefix-classifier.sh --tsv <project-path>
  echo branch-name | prefix-classifier.sh

Classifies a branch name into a smell category from BRANCH-WORKTREE-SMELLS.md.

Single-name form prints one TSV row to stdout:
  <name>\t<smell>\t<verdict-prior>\t<confidence>

--tsv form reads every branch from branches.tsv and writes:
  <workspace>/prefix_classification.tsv

Categories:
  agent-attempt  wip-take    agent-cli  pre-deploy  release   hotfix
  dependabot     ticket-id   user-sandbox  feature  integration train
  cherry-pick    revert      gone-upstream  merge-into  tag-equivalent
  unknown

Env:
  WORKSPACE   Workspace dir override (--tsv only).

Exit codes:
  0  classified
  2  not a git work tree (--tsv only)
  3  branches.tsv missing (--tsv only)
USAGE
}

# Map a single branch name → "smell|verdict-prior|confidence".
# Confidence is the 0–1 prior the smell category alone supports; per
# BRANCH-WORKTREE-SMELLS.md, this is an input to triage-batch's verdict tree,
# not a final verdict.
classify_one() {
  local name="$1"
  case "$name" in
    # B5: release/* — protected
    release/*)
      printf 'release|protected-preserve|0.95'; return ;;
    # B6: hotfix/* — protected
    hotfix/*)
      printf 'hotfix|protected-preserve|0.95'; return ;;
    # B7: dependabot/* / renovate/* — protected, auto-managed
    dependabot/*|renovate/*)
      printf 'dependabot|protected-preserve|0.90'; return ;;
    # B11: integration branches by convention
    develop|staging|next|trunk|gh-pages)
      printf 'integration|protected-preserve|0.90'; return ;;
    # B12: train branches
    train/*|train-*)
      printf 'train|protected-preserve|0.85'; return ;;
    # B13: cherry-pick branches — usually transient
    cherry-pick/*|cherry-pick-*|cherry/*|cherry-*)
      printf 'cherry-pick|superseded|0.75'; return ;;
    # B14: revert branches — verify the revert is still wanted
    revert/*|revert-*)
      printf 'revert|superseded|0.70'; return ;;
    # B16: merge-X-into-Y integration branches
    merge-*-into-*|merge/*-into-*)
      printf 'merge-into|superseded|0.65'; return ;;
    # B4: pre-deploy / before- — often garbage
    pre-deploy*|pre-release*|pre-merge*|pre-push*|pre-migration*|pre-cutover*|pre-refactor*|pre-risky-op*)
      printf 'pre-deploy|superseded|0.70'; return ;;
    before-deploy*|before-release*|before-merge*|before-push*|before-migration*|before-cutover*|before-refactor*|before-risky-op*|before-tokio-bump*)
      printf 'pre-deploy|superseded|0.70'; return ;;
    # B17: tag-equivalent branches
    v[0-9]*.[0-9]*.[0-9]*|v[0-9]*.[0-9]*)
      printf 'tag-equivalent|protected-preserve|0.80'; return ;;
    # B9: <user>/sandbox-* / <user>/scratch-*
    */sandbox-*|*/sandbox/*|*/scratch-*|*/scratch/*)
      printf 'user-sandbox|protected-preserve|0.80'; return ;;
    # B10: feature/* — real work; verify against canonical
    feature/*|feat/*)
      printf 'feature|unknown|0.60'; return ;;
    # B2: wip-<ticket>(-take-N)
    wip-*|wip/*|WIP-*|WIP/*|*-wip-*|*-WIP-*)
      printf 'wip-take|superseded|0.70'; return ;;
    # B3: cc-*, cod-*, gmi-*, claude-*, codex-*, gemini-*, grok-*
    cc-*|cc/*|cod-*|cod/*|gmi-*|gmi/*|claude-*|claude/*|codex-*|codex/*|gemini-*|gemini/*|grok-*|grok/*)
      printf 'agent-cli|superseded|0.70'; return ;;
    # B1: agent-<task>-<date>-attempt-N (and friends)
    agent-*attempt*|agent-*try*|agent-*-pass-*|agent-*-run-*)
      printf 'agent-attempt|garbage|0.80'; return ;;
    agent-*|agent/*)
      printf 'agent-cli|superseded|0.65'; return ;;
    # B8: ticket-id-style (PROJ-1234-...)
    [A-Z][A-Z]*-[0-9]*|[A-Z][A-Z]*[0-9]*-*)
      printf 'ticket-id|superseded|0.65'; return ;;
    *)
      printf 'unknown|unknown|0.50'; return ;;
  esac
}

# --tsv form: classify every row in branches.tsv into a per-workspace TSV.
if [[ "${1:-}" == "--tsv" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "ERROR: --tsv requires a project-path argument." >&2
    usage >&2
    exit 64
  fi
  PROJECT_ABS="$(resolve_project_root "$2")" || exit 2
  WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
  BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
  OUT="$WORKSPACE_DIR/prefix_classification.tsv"
  if [[ ! -f "$BRANCHES_TSV" ]]; then
    echo "ERROR: $BRANCHES_TSV missing — run discover-branches-worktrees.sh first." >&2
    exit 3
  fi

  # Resume-aware: same branches.tsv content hash → reuse.
  current_hash=$(sha256sum "$BRANCHES_TSV" | awk '{print $1}')
  if [[ -f "$OUT" ]]; then
    prior_hash=$(grep -E '^# branches_tsv_sha256=' "$OUT" 2>/dev/null | head -1 | cut -d= -f2 || true)
    if [[ "$prior_hash" == "$current_hash" ]]; then
      printf '%s up-to-date for branches.tsv hash %s\n' "$OUT" "${current_hash:0:12}"
      exit 0
    fi
  fi

  {
    printf '# branches_tsv_sha256=%s\n' "$current_hash"
    printf 'name\tslug\tsmell_category\tdefault_verdict_prior\tconfidence\tupstream_status\n'
  } > "$OUT"

  while IFS= read -r row; do
    name=""; slug=""; upstream_status=""
    tsv_read "$row" name slug head_sha last_date author subject ahead behind commits_ahead cherry_plus cherry_minus upstream upstream_status wt_path touched insertions deletions files_changed age_days prefix
    [[ "$name" == "name" ]] && continue
    [[ -z "$name" ]] && continue

    cls=$(classify_one "$name")
    smell=${cls%%|*}
    rest=${cls#*|}
    prior=${rest%%|*}
    conf=${rest#*|}

    # Upgrade to gone-upstream when applicable. Per Smell B15 / Axiom 17 the
    # [gone] state is a hint, not a verdict — we tag it but keep the verdict
    # prior the name pattern produced.
    if [[ "$upstream_status" == "gone" ]]; then
      smell="gone-upstream"
      conf=0.65
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$slug" "$smell" "$prior" "$conf" "${upstream_status:-none}" >> "$OUT"
  done < "$BRANCHES_TSV"

  echo "wrote $OUT"
  echo
  echo "Smell distribution:"
  # Skip the comment line and the header row; the header has $3 == "smell_category".
  awk -F'\t' 'substr($0,1,1) != "#" && $3 != "smell_category" && NF >= 3 {counts[$3]++} END {for (s in counts) printf "  %-20s %s\n", s, counts[s]}' "$OUT" \
    | sort -k2 -rn
  exit 0
fi

# Single-name form (or stdin).
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '')
    if [[ -t 0 ]]; then
      usage >&2
      exit 64
    fi
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      cls=$(classify_one "$line")
      smell=${cls%%|*}; rest=${cls#*|}; prior=${rest%%|*}; conf=${rest#*|}
      printf '%s\t%s\t%s\t%s\n' "$line" "$smell" "$prior" "$conf"
    done
    exit 0
    ;;
  *)
    cls=$(classify_one "$1")
    smell=${cls%%|*}; rest=${cls#*|}; prior=${rest%%|*}; conf=${rest#*|}
    printf '%s\t%s\t%s\t%s\n' "$1" "$smell" "$prior" "$conf"
    exit 0
    ;;
esac
