#!/usr/bin/env bash
# init-workspace.sh — Create the gauntlet workspace as a sibling directory of
# the target Rust port. Idempotent. If the workspace already exists, prompts
# the user to confirm re-init or resume.
#
# USAGE:
#   init-workspace.sh <target-project-path> <workspace-path>
#                     [--reference-name NAME] [--reference-version VERSION]
#                     [--force] [--re-entry]
#
# OUTPUTS:
#   <workspace>/AGENTS.md
#   <workspace>/PERF_NEGATIVE_RESULTS.md
#   <workspace>/CONFORMANCE_NEGATIVE_RESULTS.md
#   <workspace>/SURFACE_DEFERRALS.md
#   <workspace>/docs/progress/perf-negative-results.md
#   <workspace>/docs/progress/conformance-negative-results.md
#   <workspace>/docs/progress/surface-deferrals.md
#   <workspace>/<reference>_version_contract.toml
#   <workspace>/phase0_workspace_init.md   (summary)
#
# EXIT CODES:
#   0 — workspace ready (created or already valid)
#   1 — user declined re-init OR invalid args

set -euo pipefail

usage() {
  sed -n '2,20p' "$0"
  exit "${1:-2}"
}

TARGET=""
WORKSPACE=""
REF_NAME="reference"
REF_VERSION="UNPINNED"
FORCE=0
RE_ENTRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --reference-name)    REF_NAME="$2"; shift 2;;
    --reference-version) REF_VERSION="$2"; shift 2;;
    --force)             FORCE=1; shift;;
    --re-entry)          RE_ENTRY=1; shift;;
    -h|--help)           usage 0;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"
      elif [ -z "$WORKSPACE" ]; then WORKSPACE="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$TARGET" ] || usage
[ -n "$WORKSPACE" ] || usage

if [ ! -d "$TARGET" ]; then
  echo "ERROR: target path does not exist: $TARGET" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
ASSET_DIR="$SKILL_DIR/assets"

WORKSPACE_ABS="$(cd "$(dirname "$WORKSPACE")" 2>/dev/null && pwd)/$(basename "$WORKSPACE")" || WORKSPACE_ABS="$WORKSPACE"

# ---- idempotency check ----------------------------------------------------
if [ -d "$WORKSPACE" ] && [ "$FORCE" -eq 0 ] && [ "$RE_ENTRY" -eq 0 ]; then
  echo "Workspace already exists at: $WORKSPACE_ABS"
  if [ -f "$WORKSPACE/phase0_workspace_init.md" ]; then
    echo "Detected prior init. Resuming (no destructive overwrite)."
    echo "Pass --force to overwrite seed files."
    exit 0
  fi
fi

mkdir -p "$WORKSPACE"
cd "$WORKSPACE"
mkdir -p docs/contracts docs/progress reports artifacts .bench-history scripts

if [ ! -d .git ]; then
  git init -q
  echo "Initialized empty Git repository in $WORKSPACE/.git/"
fi

# ---- script bundle --------------------------------------------------------
# CI snippets in assets/github-workflows intentionally call $WORKSPACE/scripts.
# Copy a pinned snapshot of the skill scripts so generated workspaces are
# self-contained and resumable even if the installed skill later changes.
if [ ! -f scripts/gauntlet.sh ] || [ "$FORCE" -eq 1 ]; then
  cp -R "$SCRIPT_DIR/." scripts/
fi

# ---- AGENTS.md mandate paragraph -----------------------------------------
if [ ! -f AGENTS.md ] || [ "$FORCE" -eq 1 ]; then
  if [ -f "$ASSET_DIR/agents-md-mandate-paragraph.md" ]; then
    cp "$ASSET_DIR/agents-md-mandate-paragraph.md" AGENTS.md
  else
    cat > AGENTS.md <<'EOF'
# AGENTS.md — Gauntlet Workspace Mandate

For major perf campaigns, agents must also mine:
- last 60 days of CASS session history
- recent commits
- perf artifacts
- failed/rejected/slower/regressed terms

If CASS or the ledger is unavailable or reserved, the agent must record a
blocker or patch-ready entry rather than silently skipping the step.
EOF
  fi
fi

# ---- negative ledgers -----------------------------------------------------
for ledger in PERF_NEGATIVE_RESULTS.md CONFORMANCE_NEGATIVE_RESULTS.md SURFACE_DEFERRALS.md; do
  if [ ! -f "$ledger" ] || [ "$FORCE" -eq 1 ]; then
    if [ -f "$ASSET_DIR/negative-ledger-seed.md" ]; then
      cp "$ASSET_DIR/negative-ledger-seed.md" "$ledger"
    else
      cat > "$ledger" <<EOF
# $ledger

This ledger records ideas that were measured and rejected. Check it before
starting a new pass, and add an entry whenever a candidate is abandoned,
reverted, or kept out of the tree because the matrix did not move in the
intended direction.

Every entry requires a retry-condition predicate. Never "later", never "if it
seems important". Use one of:
- Retry only if a profiler attributes a clearly-above-noise share to <counter> on <wider workload>
- Reconsider only inside the broader <X> redesign
- Worth reconsidering when <specific gate moves>
- Not worth retrying as a standalone patch
- Do not retry from a cold read; use <evidence pipeline> instead
- Retry condition not applicable — the gain is structural, not numerical
- Retry only if this workload class exhibits measurable <property> below <threshold>
- Blocked until <architectural_dependency> lands; track as <beads_id>
EOF
    fi
  fi
done

if [ ! -f docs/progress/perf-negative-results.md ] || [ "$FORCE" -eq 1 ]; then
  cp PERF_NEGATIVE_RESULTS.md docs/progress/perf-negative-results.md
fi

if [ ! -f docs/progress/conformance-negative-results.md ] || [ "$FORCE" -eq 1 ]; then
  cp CONFORMANCE_NEGATIVE_RESULTS.md docs/progress/conformance-negative-results.md
fi

if [ ! -f docs/progress/surface-deferrals.md ] || [ "$FORCE" -eq 1 ]; then
  cp SURFACE_DEFERRALS.md docs/progress/surface-deferrals.md
fi

# ---- version contract skeleton -------------------------------------------
CONTRACT="${REF_NAME}_version_contract.toml"
if [ ! -f "$CONTRACT" ] || [ "$FORCE" -eq 1 ]; then
  if [ -f "$ASSET_DIR/version-contract-template.toml" ]; then
    ref_sed="$(printf '%s' "$REF_NAME" | sed 's/[\/&]/\\&/g')"
    version_sed="$(printf '%s' "$REF_VERSION" | sed 's/[\/&]/\\&/g')"
    sed "s/<REFERENCE_NAME>/${ref_sed}/g; s/<PINNED_VERSION>/${version_sed}/g; s/<reference>/${ref_sed}/g; s/<version>/${version_sed}/g" \
      "$ASSET_DIR/version-contract-template.toml" > "$CONTRACT"
  else
    cat > "$CONTRACT" <<EOF
[reference]
name = "${REF_NAME}"
version = "${REF_VERSION}"
EOF
  fi
fi

if [ ! -f "docs/contracts/$CONTRACT" ] || [ "$FORCE" -eq 1 ]; then
  cp "$CONTRACT" "docs/contracts/$CONTRACT"
fi

if [ ! -f docs/contracts/parity_score_contract.toml ] || [ "$FORCE" -eq 1 ]; then
  cp "$ASSET_DIR/parity-score-contract-template.toml" docs/contracts/parity_score_contract.toml
fi

if [ ! -f docs/contracts/supported_surface_matrix.toml ] || [ "$FORCE" -eq 1 ]; then
  cp "$ASSET_DIR/supported-surface-matrix-template.toml" docs/contracts/supported_surface_matrix.toml
fi

# ---- summary --------------------------------------------------------------
{
  printf '# phase0_workspace_init.md\n\n'
  printf -- '- workspace: `%s`\n' "$WORKSPACE_ABS"
  printf -- '- target:    `%s`\n' "$TARGET"
  printf -- '- reference: `%s` @ `%s`\n' "$REF_NAME" "$REF_VERSION"
  printf -- '- re_entry:  `%s`\n' "$([ "$RE_ENTRY" -eq 1 ] && echo true || echo false)"
  printf -- '- init_at:   `%s`\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '\n## Seeded files\n\n'
  for f in AGENTS.md PERF_NEGATIVE_RESULTS.md CONFORMANCE_NEGATIVE_RESULTS.md SURFACE_DEFERRALS.md docs/progress/perf-negative-results.md docs/progress/conformance-negative-results.md docs/progress/surface-deferrals.md "$CONTRACT" "docs/contracts/$CONTRACT" docs/contracts/parity_score_contract.toml docs/contracts/supported_surface_matrix.toml scripts/gauntlet.sh; do
    [ -f "$f" ] && printf -- '- `%s` (%s bytes)\n' "$f" "$(wc -c <"$f" | tr -d ' ')"
  done
} > phase0_workspace_init.md

echo "Workspace ready: $WORKSPACE_ABS"
echo "Summary at: $WORKSPACE_ABS/phase0_workspace_init.md"
