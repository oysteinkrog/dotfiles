#!/usr/bin/env bash
# bootstrap-session.sh — Phase 0.5 idempotent workspace + beads + ntm bootstrap
#
# Usage:
#   bootstrap-session.sh <workspace-path> "<question-or-target>" \
#       [--mode=<mode>] [--roster=<pair|squad|swarm|squad-no-mail>] [--model-mix=<spec>] [--robot-mode=<on|off>] \
#       [--coordination=<agent-mail|ntm-inbox>] [--resume=<RESUME.md path>]
#
# Idempotent: safe to re-run on existing workspace; will not overwrite existing artifacts.
#
# Per references/SKILL-FALLBACKS.md, this script handles:
#   - workspace dir creation
#   - git init
#   - beads init + label seeding
#   - phase0_scope_decision.md write
#   - check-skills.sh inventory
#   - jsm install offer

set -euo pipefail

WORKSPACE="${1:?usage: bootstrap-session.sh <workspace> <question-or-target> [flags]}"
QUESTION_OR_TARGET="${2:?usage: bootstrap-session.sh <workspace> <question-or-target> [flags]}"
shift 2

MODE="fresh-question"
ROSTER="squad"
MODEL_MIX="cc:3,cod:1,gmi:1"
ROBOT_MODE="on"
COORDINATION="agent-mail"
RESUME_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode=*) MODE="${1#*=}" ;;
    --roster=*) ROSTER="${1#*=}" ;;
    --model-mix=*) MODEL_MIX="${1#*=}" ;;
    --robot-mode=*) ROBOT_MODE="${1#*=}" ;;
    --coordination=*) COORDINATION="${1#*=}" ;;
    --resume=*) RESUME_PATH="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 1. Create workspace dirs (idempotent).
mkdir -p "$WORKSPACE"/{intake,corpus/ingested,evidence/packs,evidence/excerpts,distillations,deliverables/scripts,analyses,session-logs/ntm-pipeline-runs,.brenner_workspace,.ntm/pipelines,.beads}

# 1a. Seed .ntm/pipelines/ with the executable brennerbot pipelines so the
# operator-facing instruction `ntm pipeline run .ntm/pipelines/brennerbot-<roster>.yaml`
# resolves out of the box from the workspace. The source pipeline assets use
# skill-relative script/template paths; workspace copies must point back to this
# installed skill directory because generated workspaces intentionally do not
# copy the whole `scripts/` and `assets/` trees.
for pipeline in "$SKILL_DIR/assets/ntm-pipelines/"*.yaml; do
  [ -f "$pipeline" ] || continue
  if grep -q '^schema_version:' "$pipeline"; then
    dest="$WORKSPACE/.ntm/pipelines/$(basename "$pipeline")"
    if [ ! -e "$dest" ]; then
      script_dir_escaped=$(printf '%s' "$SCRIPT_DIR" | sed -e 's/[\/&]/\\&/g')
      skill_dir_escaped=$(printf '%s' "$SKILL_DIR" | sed -e 's/[\/&]/\\&/g')
      sed \
        -e "s/\\.\\/scripts\\//$script_dir_escaped\\//g" \
        -e "s/\\.\\/scripts/$script_dir_escaped/g" \
        -e "s/assets\\/marching-orders\\//$skill_dir_escaped\\/assets\\/marching-orders\\//g" \
        -e "s/template: subagents\\//template: $skill_dir_escaped\\/subagents\\//g" \
        "$pipeline" > "$dest"
    fi
  fi
done

# 2. git init if not already.
if [ ! -d "$WORKSPACE/.git" ]; then
  ( cd "$WORKSPACE" && git init -q )
  echo "git: initialized"
fi

# Standard .gitignore
if [ ! -f "$WORKSPACE/.gitignore" ]; then
  cat > "$WORKSPACE/.gitignore" <<'EOF'
.ntm/checkpoints/*.tar.gz
!.ntm/checkpoints/latest.tar.gz
.brenner_workspace/tick_history.jsonl
session-logs/ntm-pipeline-runs/
node_modules/
*.swp
.DS_Store
EOF
fi

# 3. beads init.
if [ ! -f "$WORKSPACE/.beads/issues.jsonl" ] && [ ! -f "$WORKSPACE/.beads/beads.jsonl" ] && [ ! -f "$WORKSPACE/.beads/beads.db" ]; then
  if ( cd "$WORKSPACE" && br init --prefix=bb 2>/dev/null ); then
    echo "br: initialized"
  else
    echo "warning: br init skipped or failed; install/repair br before Phase 1" >&2
  fi
fi

# 4. Run check-skills.sh.
"$SCRIPT_DIR/check-skills.sh" "$WORKSPACE" > "$WORKSPACE/.brenner_workspace/phase0_skill_inventory.json"

# 5. Auto-detect mode if not overridden.
if [ "$MODE" = "fresh-question" ] && [ -z "$RESUME_PATH" ]; then
  if [ -f "$WORKSPACE/deliverables/RESUME.md" ]; then
    MODE="resume-session"
    RESUME_PATH="$WORKSPACE/deliverables/RESUME.md"
  elif [ -d "$QUESTION_OR_TARGET/.git" ]; then
    MODE="code-investigation"
  elif [ -d "$QUESTION_OR_TARGET" ] && find "$QUESTION_OR_TARGET" -maxdepth 2 \( -name '*.md' -o -name '*.pdf' -o -name '*.txt' \) -print 2>/dev/null | head -1 | grep -q .; then
    MODE="corpus-distillation"
  fi
fi

# 5b. If MODE was explicitly set to resume-session but --resume= was not provided,
# auto-fill RESUME_PATH from the workspace's deliverables/RESUME.md so the printed
# summary and next-step suggestion are coherent.
if [ "$MODE" = "resume-session" ] && [ -z "$RESUME_PATH" ]; then
  if [ -f "$WORKSPACE/deliverables/RESUME.md" ]; then
    RESUME_PATH="$WORKSPACE/deliverables/RESUME.md"
  else
    echo "warning: --mode=resume-session was set but no RESUME.md found at $WORKSPACE/deliverables/RESUME.md and no --resume=<path> was provided" >&2
  fi
fi

# 6. Generate slug from question/target. Truncate first, then strip trailing/leading hyphens that
# the truncation may have produced.
SLUG=$(echo "$QUESTION_OR_TARGET" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | tr -s - | head -c 30 | sed 's/^-//;s/-$//')
[ -z "$SLUG" ] && SLUG="session"
SESSION_ID="RS-$(date -u +%Y%m%d)-$SLUG"

# 7. Write phase0_scope_decision.md (don't overwrite if exists).
if [ ! -f "$WORKSPACE/.brenner_workspace/phase0_scope_decision.md" ]; then
  cat > "$WORKSPACE/.brenner_workspace/phase0_scope_decision.md" <<EOF
# Phase 0 Scope Decision — $SESSION_ID

**Created at:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Workspace:** $WORKSPACE
**Question or target:** $QUESTION_OR_TARGET
**Mode:** $MODE
**Roster:** $ROSTER
**Model mix:** $MODEL_MIX
**Robot mode:** $ROBOT_MODE
**Coordination:** $COORDINATION
**Resume from:** ${RESUME_PATH:-(fresh start)}

## Roster

(Filled in during Phase 2 by dispatch_onboarding step. Updated here as roster_changes occur.)

## Skill inventory

See \`phase0_skill_inventory.json\` for installed/missing helper skills + active fallbacks.

## Phase plan

Standard 10-phase loop per references/PHASES.md, adjusted for mode:
$(case "$MODE" in
  resume-session) echo "- Skip Phase 1; re-enter at next_loop_recommendation phase per RESUME.md" ;;
  code-investigation) echo "- Phase 1 invokes /codebase-archaeology and /codebase-report" ;;
  corpus-distillation) echo "- Phase 1 ingests corpus into corpus/ingested/ with §-anchor scheme" ;;
  methodology-drift-check) echo "- Phase 10 only (read-only audit of prior session)" ;;
  incident-investigation) echo "- Compressed incident loop: Phase 1 + Phase 3 + Phase 4 inline with Phase 5 + Phase 7; produces INCIDENT-VERDICT.md and skips distillation/full freeze/drift" ;;
  *) echo "- All 10 phases" ;;
esac)

## Roster changes log

(Append entries here when panes are killed, restarted, or re-roled mid-session.)

## Fallbacks active

(Auto-populated from phase0_skill_inventory.json fallbacks_active.)
EOF
  echo "phase0_scope_decision.md: written"
fi

# 8. Print summary.
echo ""
echo "=== brennerbot-with-ntm bootstrap complete ==="
echo "Workspace:    $WORKSPACE"
echo "Session ID:   $SESSION_ID"
echo "Mode:         $MODE"
echo "Roster:       $ROSTER"
echo "Model mix:    $MODEL_MIX"
echo "Coordination: $COORDINATION"
echo ""
echo "Next steps:"
case "$MODE" in
  resume-session)
    echo "  $SCRIPT_DIR/resume-session.sh --resume $RESUME_PATH"
    ;;
  methodology-drift-check)
    echo "  Operator: dispatch subagents/drift-auditor.md to a fresh general-purpose Agent."
    echo "  Workspace to audit: \$prior_workspace"
    ;;
  *)
    # Pick the canonical pipeline by mode first, then fall back to roster. The
    # mode-specific pipelines (incident-investigation) compress phases — using
    # the roster's full pipeline instead would skip the compression. The
    # spec-only modes point at phase-outline YAMLs that are not directly
    # executable; the operator drives those modes manually.
    SPEC_ONLY_PIPELINE=""
    case "$MODE" in
      incident-investigation)             PIPELINE_FILE="brennerbot-incident.yaml" ;;
      post-mortem-formalization)          SPEC_ONLY_PIPELINE="brennerbot-post-mortem.yaml" ;;
      academic-replication)               SPEC_ONLY_PIPELINE="brennerbot-academic.yaml" ;;
      design-review)                      SPEC_ONLY_PIPELINE="brennerbot-design-review.yaml" ;;
      living-review)                      SPEC_ONLY_PIPELINE="brennerbot-living-review.yaml" ;;
      *)                                  PIPELINE_FILE="brennerbot-$ROSTER.yaml" ;;
    esac
    echo "  1. Run MO-01-frame-question.md (Phase 1 framing) — operator-driven."
    if [ -n "$SPEC_ONLY_PIPELINE" ]; then
      echo "  2. Use $SKILL_DIR/assets/ntm-pipelines/$SPEC_ONLY_PIPELINE as a phase outline only; it is not an ntm pipeline-run input."
      echo "     Drive the mode manually with the matching marching order and reference playbook."
    elif [ ! -f "$WORKSPACE/.ntm/pipelines/$PIPELINE_FILE" ]; then
      echo "  2. No executable pipeline asset exists for roster '$ROSTER' ($PIPELINE_FILE)."
      echo "     Spawn the ntm session named $SESSION_ID manually, then dispatch marching orders with $SCRIPT_DIR/dispatch-marching-order.sh."
    else
      echo "  2. Spawn an ntm session named $SESSION_ID using the roster in phase0_scope_decision.md (default squad: ntm spawn $SESSION_ID --cc=3 --cod=1 --gmi=1)."
      echo "  3. Dry-run: ntm pipeline run .ntm/pipelines/$PIPELINE_FILE --session $SESSION_ID --var workspace_path=$WORKSPACE --var session_id=$SESSION_ID --var question_of_record_path=intake/question_of_record.md --var mode=$MODE --var model_mix=$MODEL_MIX --dry-run"
      echo "     If the installed ntm rejects schema fields, build/upgrade ntm or drive phases manually."
    fi
    echo "  4. Or: dispatch marching orders manually via $SCRIPT_DIR/dispatch-marching-order.sh"
    ;;
esac
echo ""
echo "Skill inventory: $WORKSPACE/.brenner_workspace/phase0_skill_inventory.json"
echo "Scope decision:  $WORKSPACE/.brenner_workspace/phase0_scope_decision.md"
