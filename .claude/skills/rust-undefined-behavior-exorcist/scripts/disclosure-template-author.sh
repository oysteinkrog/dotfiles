#!/usr/bin/env bash
# disclosure-template-author.sh — generate a RustSec advisory draft from a
# CONFIRMED_UB EXP-NNN block. See DISCLOSURE.md §RustSec advisory format.
#
# Usage:
#   disclosure-template-author.sh <workspace> <exp-id> [--crate <name>] [--out <path>] [--force]
#
# The script reads:
#   - $workspace/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md (the EXP-NNN block)
#   - $workspace/experiments/<exp-id>/repro.rs (reproducer code)
#   - $workspace/phase8_remediation_plan.md (severity, fix version) — optional
#
# Output: a draft TOML at
#   $workspace/disclosure/<exp-id>/RUSTSEC-YYYY-XXXX-draft.toml
# plus a companion advisory.md skeleton. Every NEEDS-REVIEW field is clearly
# marked so the human disclosure-author fills them in before submission.
#
# Refuses to overwrite an existing draft unless --force is passed (drafts get
# hand-edited; silent clobber would discard those edits).
#
# Exit codes:
#   0 — draft written
#   1 — EXP block not found / has no CONFIRMED_UB verdict / refusing to overwrite without --force
#   2 — usage error / workspace invalid
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 2 ]]; then
    echo "Usage: disclosure-template-author.sh <workspace> <exp-id> [--crate <name>] [--out <path>] [--force]" >&2
    exit 2
fi

WORKSPACE="$1"
EXP="$2"
shift 2

CRATE=""
OUT=""
FORCE=no

while [[ $# -gt 0 ]]; do
    case "$1" in
        --crate)    shift; CRATE="$1" ;;
        --crate=*)  CRATE="${1#--crate=}" ;;
        --out)      shift; OUT="$1" ;;
        --out=*)    OUT="${1#--out=}" ;;
        --force)    FORCE=yes ;;
        *)          echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

WORKSPACE_REAL="$(realpath -m "$WORKSPACE")"
case "$WORKSPACE_REAL" in
    */.ub-exorcism/*) ;;
    *)
        echo "Workspace must be inside <source>/.ub-exorcism/<run-id>" >&2
        exit 2
        ;;
esac
WORKSPACE="$WORKSPACE_REAL"
SOURCE="${WORKSPACE%%/.ub-exorcism/*}"

EXP_REGISTRY="$WORKSPACE/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md"
if [[ ! -f "$EXP_REGISTRY" ]]; then
    echo "Experiment registry not found: $EXP_REGISTRY" >&2
    exit 2
fi

# Extract the EXP-NNN block (heading-to-next-heading).
EXP_BLOCK="$(awk -v exp_id="$EXP" '
    BEGIN { in_block = 0 }
    /^## / {
        if (in_block) exit
        if ($0 ~ "^## " exp_id "( |$|—)") in_block = 1
    }
    in_block { print }
' "$EXP_REGISTRY")"

if [[ -z "$EXP_BLOCK" ]]; then
    echo "No '## $EXP' block found in $EXP_REGISTRY" >&2
    exit 1
fi

# Verify the experiment is CONFIRMED_UB — disclosure only applies to confirmed findings
VERDICT="$(echo "$EXP_BLOCK" | grep -E '^\*\*Verdict:\*\*' | head -1 | sed 's/^\*\*Verdict:\*\* *//')"
if [[ "$VERDICT" != "CONFIRMED_UB" ]]; then
    echo "EXP $EXP has verdict '$VERDICT' (not CONFIRMED_UB). Disclosure requires confirmation." >&2
    exit 1
fi

# Auto-detect crate name from source's Cargo.toml if not given
if [[ -z "$CRATE" ]]; then
    CRATE=$(awk -F' = ' '/^name = / { gsub(/"/, "", $2); print $2; exit }' "$SOURCE/Cargo.toml" 2>/dev/null || echo "UNKNOWN_CRATE")
fi

# Extract fields from the EXP block
FINDING_REF="$(echo "$EXP_BLOCK" | grep -E '^\*\*Finding ref:\*\*' | head -1 | sed 's/^\*\*Finding ref:\*\* *//' | awk '{print $1}')"
HYPOTHESIS="$(echo "$EXP_BLOCK" | grep -E '^\*\*Hypothesis:\*\*' | head -1 | sed 's/^\*\*Hypothesis:\*\* *//')"
SEVERITY="$(echo "$EXP_BLOCK" | grep -E '^\*\*Severity:\*\*' | head -1 | sed 's/^\*\*Severity:\*\* *//')"

# Reproducer file
REPRO_FILE="$WORKSPACE/experiments/$EXP/repro.rs"
REPRO_CODE=""
if [[ -f "$REPRO_FILE" ]]; then
    REPRO_CODE="$(sed 's/^/    /' "$REPRO_FILE")"
else
    REPRO_CODE="    // NEEDS-REVIEW: reproducer at $REPRO_FILE was not found; paste minimal Rust here"
fi

# Output dir
OUT_DIR="$WORKSPACE/disclosure/$EXP"
mkdir -p "$OUT_DIR"
TODAY="$(date -u +%Y-%m-%d)"
YEAR="${TODAY%%-*}"
OUT="${OUT:-$OUT_DIR/RUSTSEC-${YEAR}-XXXX-draft.toml}"
ADVISORY_MD="$OUT_DIR/advisory.md"

# Refuse to clobber human edits — disclosure drafts get hand-edited between
# generations to fill in NEEDS-REVIEW markers; silently overwriting them would
# discard work. Pass --force if regeneration is intentional.
# Note: --out moves only the TOML; advisory.md always lives in $OUT_DIR, so
# --out alone doesn't fully isolate from existing drafts in this EXP's dir.
if [[ "$FORCE" != "yes" ]]; then
    existing_paths=()
    [[ -e "$OUT" ]] && existing_paths+=("$OUT")
    [[ -e "$ADVISORY_MD" ]] && existing_paths+=("$ADVISORY_MD")
    if (( ${#existing_paths[@]} )); then
        echo "Refusing to overwrite existing draft file(s):" >&2
        for p in "${existing_paths[@]}"; do echo "  $p" >&2; done
        echo "Pass --force to regenerate, OR move the existing draft(s) aside first." >&2
        exit 1
    fi
fi

# Default CVSS for typical Rust UB: Local attack vector, Low complexity, High impact
DEFAULT_CVSS="CVSS:3.1/AV:L/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"

cat > "$OUT" <<TOMLEOF
# ┌────────────────────────────────────────────────────────────────────────────┐
# │  DRAFT — fill in every "NEEDS-REVIEW:" before submitting to advisory-db.   │
# │  Coordinate disclosure timeline with the crate maintainer FIRST.           │
# └────────────────────────────────────────────────────────────────────────────┘

[advisory]
id          = "RUSTSEC-${YEAR}-XXXX"      # NEEDS-REVIEW: RustSec coordinator assigns the actual id
package     = "${CRATE}"
date        = "${TODAY}"
title       = "NEEDS-REVIEW: <one-line UB summary, e.g., 'Use-after-free in foo::bar'>"
description = """
${HYPOTHESIS}

Source finding: ${FINDING_REF}
Audit experiment: ${EXP}
Verdict: ${VERDICT}
Severity (auditor): ${SEVERITY}

Reproducer:
\`\`\`rust
${REPRO_CODE}
\`\`\`

Miri/sanitizer evidence: see audit workspace
  ${WORKSPACE}/phase5_experiment_results/${EXP}.log
"""
url        = "NEEDS-REVIEW: https://github.com/<owner>/<repo>/issues/N"
categories = ["memory-corruption"]    # NEEDS-REVIEW: pick from advisory-db category list
keywords   = ["NEEDS-REVIEW", "<bucket>"]
cvss       = "${DEFAULT_CVSS}"        # NEEDS-REVIEW: rescore per impact (calculator: https://www.first.org/cvss/calculator/3.1)

[affected]
patched_versions    = ["NEEDS-REVIEW: >= X.Y.Z"]
unaffected_versions = ["NEEDS-REVIEW: < A.B.C"]
# Optional: function-level scope if the UB is in a specific API
# functions = ["${CRATE}::module::function"]
TOMLEOF

# Companion advisory.md
cat > "$ADVISORY_MD" <<MDEOF
# RUSTSEC-${YEAR}-XXXX — ${CRATE}

**Status:** DRAFT (auto-generated $(date -u +%FT%TZ) from $EXP)

## Summary

<NEEDS-REVIEW: 1–2 sentence summary of the UB and its trigger.>

## Technical detail

${HYPOTHESIS}

## Reproducer

\`\`\`rust
${REPRO_CODE}
\`\`\`

Miri output: \`${WORKSPACE}/phase5_experiment_results/${EXP}.log\`

## Impact

<NEEDS-REVIEW: who is affected; what an attacker can achieve.>

## Remediation

<NEEDS-REVIEW: copy from phase8_remediation_plan.md §R-NNN.>

## Timeline

- ${TODAY}: UB confirmed via ${EXP} audit
- NEEDS-REVIEW: <YYYY-MM-DD>: maintainer notified privately
- NEEDS-REVIEW: <YYYY-MM-DD>: patch released as <version>
- NEEDS-REVIEW: <YYYY-MM-DD>: public disclosure

## Credit

Auditor: NEEDS-REVIEW (this audit)
Coordinator: NEEDS-REVIEW
MDEOF

echo "Wrote draft advisory: $OUT"
echo "Wrote draft prose:    $ADVISORY_MD"
echo
echo "REVIEW CHECKLIST before submitting to advisory-db:"
echo "  [ ] Replace every NEEDS-REVIEW marker"
echo "  [ ] Confirm CVSS score with the actual attack scenario"
echo "  [ ] Coordinate with maintainer FIRST (90-day window is standard)"
echo "  [ ] Open the maintainer issue or email; record url in [advisory].url"
echo "  [ ] After patch ships, fill patched_versions; submit PR to rustsec/advisory-db"
exit 0
