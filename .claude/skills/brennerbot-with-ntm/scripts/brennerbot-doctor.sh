#!/usr/bin/env bash
# brennerbot-doctor.sh — 7-pillar workspace health check
# Per references/BRENNERBOT-DOCTOR-RUBRIC.md
#
# Diagnoses an inherited or in-flight brennerbot workspace.
#
# Usage:
#   brennerbot-doctor.sh                       # full pass on current dir
#   brennerbot-doctor.sh --workspace=<path>    # specific workspace
#   brennerbot-doctor.sh --pillar=N            # one pillar only (1-7)
#   brennerbot-doctor.sh --robot               # JSON output

set -uo pipefail

WORKSPACE_ARG="."
PILLAR="all"
ROBOT=0

require_value() {
    if [ -z "${2:-}" ]; then
        echo "[FATAL] $1 requires a value" >&2
        exit 2
    fi
}

json_string() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -Rs .
        return
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json, sys; print(json.dumps(sys.argv[1]), end="")' "$1"
        return
    fi

    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\b'/\\b}
    value=${value//$'\f'/\\f}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '"%s"' "$value"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --workspace=*) WORKSPACE_ARG="${1#*=}"; shift ;;
        --workspace)
            require_value --workspace "${2:-}"
            WORKSPACE_ARG="$2"; shift 2
            ;;
        --pillar=*)    PILLAR="${1#*=}"; shift ;;
        --pillar)
            require_value --pillar "${2:-}"
            PILLAR="$2"; shift 2
            ;;
        --robot)       ROBOT=1; shift ;;
        --help|-h)
            sed -n '2,12p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "[FATAL] unknown flag: $1" >&2; exit 2 ;;
    esac
done

# Compute SCRIPT_DIR BEFORE we cd anywhere — `${BASH_SOURCE[0]}` may be a
# relative path (e.g., `scripts/brennerbot-doctor.sh`), so `dirname` of it
# resolves against the original cwd, not the soon-to-be workspace cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve to absolute path BEFORE cd (per session-fork.sh round-7 lesson)
WORKSPACE="$(cd "$WORKSPACE_ARG" 2>/dev/null && pwd)" \
    || { echo "[FATAL] Cannot cd to workspace: $WORKSPACE_ARG" >&2; exit 1; }

cd "$WORKSPACE" || exit 1

# Per-invocation diagnostic dir for sub-script outputs. Use mktemp so
# concurrent operators running this don't clobber each other (the previous
# /tmp/.doctor-pillar-3.out path was both predictable and racy). Keep the
# captured outputs: repo policy forbids file deletion, and retained files make
# failed doctor runs auditable.
DOCTOR_TMP="$(mktemp -d -t brennerbot-doctor.XXXXXX)"

# Per-pillar verdicts: green / yellow / red. Worst per pillar = pillar verdict.
declare -A PILLAR_VERDICT
declare -A PILLAR_NOTES
WORST="green"

worst_of() {
    local a="$1" b="$2"
    case "$a:$b" in
        red:*|*:red) echo "red" ;;
        yellow:*|*:yellow) echo "yellow" ;;
        *) echo "green" ;;
    esac
}

note() {
    local pillar="$1" verdict="$2" message="$3"
    PILLAR_VERDICT[$pillar]=$(worst_of "${PILLAR_VERDICT[$pillar]:-green}" "$verdict")
    PILLAR_NOTES[$pillar]="${PILLAR_NOTES[$pillar]:-}$verdict: $message
"
    WORST=$(worst_of "$WORST" "$verdict")
}

# ---------------------------------------------------------------------------
# Pillar 1: Structural
# ---------------------------------------------------------------------------
pillar_1() {
    PILLAR_VERDICT[1]="green"

    # phase0_scope_decision.md
    if [ -f .brenner_workspace/phase0_scope_decision.md ]; then
        if [ "$(wc -c <.brenner_workspace/phase0_scope_decision.md)" -lt 200 ]; then
            note 1 yellow "phase0_scope_decision.md exists but suspiciously short"
        fi
    else
        note 1 red "phase0_scope_decision.md missing"
    fi

    # git
    if [ -d .git ]; then
        if ! git log -1 >/dev/null 2>&1; then
            note 1 yellow "git repo exists but has 0 commits"
        fi
    else
        note 1 red "not a git repo"
    fi

    # Required directories
    local missing=0
    for d in corpus intake evidence distillations deliverables session-logs; do
        [ -d "$d" ] || missing=$((missing + 1))
    done
    if [ "$missing" -ge 4 ]; then
        note 1 red "$missing of 6 required directories missing"
    elif [ "$missing" -ge 1 ]; then
        note 1 yellow "$missing of 6 required directories missing"
    fi

    # question_of_record
    if [ -f intake/question_of_record.md ]; then
        local falsifier_lines
        falsifier_lines=$(awk '
            /^## Falsifier/ { flag=1; next }
            flag && /^## / { flag=0 }
            flag && /\S/ { count++ }
            END { print count+0 }
        ' intake/question_of_record.md 2>/dev/null)
        if [ "$falsifier_lines" -lt 3 ]; then
            note 1 yellow "question_of_record.md exists but Falsifier section empty/thin"
        fi
    else
        note 1 red "intake/question_of_record.md missing"
    fi

    # Phase flags ordering
    local prev=0
    for n in 1 2 3 4 5 6 7 8 9 10; do
        if [ -f .brenner_workspace/phase_${n}_complete.flag ]; then
            if [ $prev -ne $((n - 1)) ]; then
                note 1 yellow "phase flags non-sequential (gap before phase $n)"
                break
            fi
            prev=$n
        else
            break
        fi
    done

    # RESUME.md if Phase 8 done
    if [ -f .brenner_workspace/phase_8_complete.flag ] && [ ! -f deliverables/RESUME.md ]; then
        note 1 red "Phase 8 complete but deliverables/RESUME.md missing"
    fi

    [ "${PILLAR_VERDICT[1]}" = "green" ] && PILLAR_NOTES[1]="all checks green"
}

# ---------------------------------------------------------------------------
# Pillar 2: Methodology
# ---------------------------------------------------------------------------
pillar_2() {
    PILLAR_VERDICT[2]="green"

    if ! command -v br >/dev/null 2>&1; then
        note 2 yellow "br not available; cannot evaluate methodology compliance"
        return
    fi

    # Third-alternative present if Phase 3 done
    if [ -f .brenner_workspace/phase_3_complete.flag ]; then
        local third_alt
        third_alt=$(br list --label=hypothesis --json 2>/dev/null \
            | jq -r '[.issues[]? | select((.description // "") | contains("origin: third_alternative") or contains("origin:third_alternative"))] | length' 2>/dev/null)
        if [ "${third_alt:-0}" -lt 1 ]; then
            note 2 red "Phase 3 done but no H with origin:third_alternative (F-301)"
        fi
    fi

    # Phase 6 disagreement_register
    if [ -f .brenner_workspace/phase_6_complete.flag ]; then
        if [ -f distillations/disagreement_register.md ]; then
            local entries
            entries=$(grep -cE '^(## |- )D-[0-9]+' distillations/disagreement_register.md 2>/dev/null)
            entries=${entries:-0}
            if [ "$entries" -lt 1 ]; then
                note 2 red "disagreement_register.md exists but empty (F-603)"
            elif [ "$entries" -lt 3 ]; then
                note 2 yellow "disagreement_register.md has only $entries entries (expected ≥3 for tri-family triangulation)"
            fi
        else
            note 2 red "Phase 6 done but disagreement_register.md missing (F-603)"
        fi
    fi

    [ "${PILLAR_VERDICT[2]}" = "green" ] && PILLAR_NOTES[2]="all checks green"
}

# ---------------------------------------------------------------------------
# Pillar 3: Bead invariants
# ---------------------------------------------------------------------------
pillar_3() {
    PILLAR_VERDICT[3]="green"

    if [ -x "$SCRIPT_DIR/audit-bead-invariants.sh" ]; then
        if "$SCRIPT_DIR/audit-bead-invariants.sh" --workspace="$WORKSPACE" --all \
                >"$DOCTOR_TMP/pillar-3.out" 2>&1; then
            : # green
        else
            # Prefer the audit's own summary line `Total violations: N` —
            # case-sensitive grep matches the canonical UPPERCASE
            # `VIOLATION [...]` line format that audit-bead-invariants emits.
            # Previous regex `^(violation|✗)` was lowercase only, so the audit
            # could emit ten clear `VIOLATION [...]` lines and we'd still
            # report "0 violations".
            local violations
            # Pull the FIRST integer from the first matching summary line.
            # Trailing `head -1` after `grep -oE '[0-9]+'` matters: if the
            # summary ever reads e.g. "Total violations: 5 (after 3 retries)",
            # grep -oE alone would emit two integers on separate lines, and
            # the resulting multi-line $violations crashes `[ -eq ]` (bash
            # `[: integer expression expected: 5\n3`).
            violations=$(grep -E '^Total violations:' "$DOCTOR_TMP/pillar-3.out" 2>/dev/null \
                | head -1 \
                | grep -oE '[0-9]+' \
                | head -1 \
                || true)
            if [ -z "$violations" ]; then
                # Fall back to counting per-line VIOLATION markers (covers
                # audit scripts that omit the summary line).
                violations=$(grep -cE '^(VIOLATION\b|violation\b|✗)' "$DOCTOR_TMP/pillar-3.out" 2>/dev/null)
                violations=${violations:-0}
            fi
            # NB: $DOCTOR_TMP is retained after exit; inline the first few
            # lines for quick triage and keep the full captured output.
            if [ "$violations" -eq 0 ]; then
                local audit_head
                audit_head=$(head -5 "$DOCTOR_TMP/pillar-3.out" 2>/dev/null \
                    | sed 's/^/        /' \
                    || echo "        (no output captured)")
                note 3 yellow "audit-bead-invariants exited non-zero but no specific violation count parsed. First lines of its output:
$audit_head
Captured output retained at: $DOCTOR_TMP/pillar-3.out"
            elif [ "$violations" -ge 5 ]; then
                note 3 red "$violations bead-invariant violations (captured output: $DOCTOR_TMP/pillar-3.out)"
            else
                note 3 yellow "$violations bead-invariant violation(s) (captured output: $DOCTOR_TMP/pillar-3.out)"
            fi
        fi
    else
        note 3 yellow "audit-bead-invariants.sh not available; cannot run check"
    fi

    [ "${PILLAR_VERDICT[3]}" = "green" ] && PILLAR_NOTES[3]="all checks green"
}

# ---------------------------------------------------------------------------
# Pillar 4: Convergence
# ---------------------------------------------------------------------------
pillar_4() {
    PILLAR_VERDICT[4]="green"

    if [ ! -x "$SCRIPT_DIR/convergence-check.sh" ]; then
        note 4 yellow "convergence-check.sh not available"
        return
    fi

    for phase in 4 6 7; do
        if [ -f ".brenner_workspace/phase_${phase}_complete.flag" ]; then
            if ! "$SCRIPT_DIR/convergence-check.sh" --workspace="$WORKSPACE" --phase=$phase >/dev/null 2>&1; then
                note 4 red "Phase $phase marked complete but convergence formula not satisfied"
            fi
        fi
    done

    [ "${PILLAR_VERDICT[4]}" = "green" ] && PILLAR_NOTES[4]="all checks green"
}

# ---------------------------------------------------------------------------
# Pillar 5: Triangulation
# ---------------------------------------------------------------------------
pillar_5() {
    PILLAR_VERDICT[5]="green"

    # Roster family count from phase0_scope_decision.md.
    # bootstrap-session.sh writes `**Model mix:** cc:3,cod:1,gmi:1` (model:count
    # syntax), NOT `family: cc` lines — so the previous `family[:=]` regex
    # silently returned 0 for every fresh workspace, making Pillar 5 always
    # yellow ("family roster cannot be parsed"). Parse the model-mix line.
    local fam_count
    local mix_line
    mix_line=$(grep -m1 -oE '\*\*Model mix:\*\*[[:space:]]*[a-z0-9_,:[:space:]-]+' \
        .brenner_workspace/phase0_scope_decision.md 2>/dev/null \
        | sed -E 's/^\*\*Model mix:\*\*[[:space:]]*//')
    if [ -n "$mix_line" ]; then
        # `cc:3,cod:1,gmi:1` -> count of distinct family slugs.
        fam_count=$(printf '%s' "$mix_line" | tr ',' '\n' \
            | awk -F: '{gsub(/[[:space:]]/,"",$1); if (length($1)) print $1}' \
            | sort -u | grep -c .)
    else
        # Backward-compatible: also accept the older `family: cc` form.
        fam_count=$(grep -oE 'family[:=][[:space:]]*[a-z0-9_-]+' \
            .brenner_workspace/phase0_scope_decision.md 2>/dev/null \
            | awk -F'[:=]' '{gsub(/[[:space:]]/, "", $2); print $2}' | sort -u | grep -c .)
    fi
    fam_count=${fam_count:-0}

    if [ "$fam_count" -lt 1 ]; then
        note 5 yellow "family roster cannot be parsed; manual check needed"
    elif [ "$fam_count" -lt 2 ]; then
        note 5 yellow "single-family roster — triangulation degraded (acceptable for Solo)"
    fi

    # Per-family distillations. Check whichever families are referenced in the
    # model-mix line OR in older `family: <slug>` declarations.
    if [ -f .brenner_workspace/phase_6_complete.flag ]; then
        local missing=0
        for fam in cc cod gmi; do
            if grep -qE "(family[:=][[:space:]]*${fam}|\*\*Model mix:\*\*[^\\n]*\\b${fam}:)" \
                .brenner_workspace/phase0_scope_decision.md 2>/dev/null; then
                if [ ! -f "distillations/by_${fam}.md" ]; then
                    missing=$((missing + 1))
                fi
            fi
        done
        if [ "$missing" -ge 2 ]; then
            note 5 red "$missing per-family distillation file(s) missing"
        elif [ "$missing" -eq 1 ]; then
            note 5 yellow "$missing per-family distillation file missing"
        fi
    fi

    [ "${PILLAR_VERDICT[5]}" = "green" ] && PILLAR_NOTES[5]="all checks green"
}

# ---------------------------------------------------------------------------
# Pillar 6: Cross-session
# ---------------------------------------------------------------------------
pillar_6() {
    PILLAR_VERDICT[6]="green"

    if [ -f .brenner_workspace/phase_10_complete.flag ]; then
        if [ ! -f deliverables/DRIFT-CHECK.md ]; then
            note 6 red "Phase 10 marked complete but DRIFT-CHECK.md missing"
        fi
    elif [ -f .brenner_workspace/phase_9_complete.flag ]; then
        # Phase 9 done but not Phase 10: yellow (lesson commit deferred)
        note 6 yellow "Phase 9 done but Phase 10 drift-check deferred"
    fi

    [ "${PILLAR_VERDICT[6]}" = "green" ] && PILLAR_NOTES[6]="all checks green"
}

# ---------------------------------------------------------------------------
# Pillar 7: Deliverability
# ---------------------------------------------------------------------------
pillar_7() {
    PILLAR_VERDICT[7]="green"

    if [ -f .brenner_workspace/phase_9_complete.flag ]; then
        if [ ! -f deliverables/HANDBACK.md ]; then
            note 7 red "Phase 9 marked complete but deliverables/HANDBACK.md missing"
        else
            local lines
            lines=$(wc -l <deliverables/HANDBACK.md 2>/dev/null)
            lines=${lines:-0}
            if [ "$lines" -gt 80 ]; then
                note 7 yellow "HANDBACK.md is $lines lines (>80; per F-901)"
            fi
        fi
    fi

    # RESUME.md hash-verify if present
    if [ -f deliverables/RESUME.md ] && [ -x "$SCRIPT_DIR/resume-session.sh" ]; then
        if ! "$SCRIPT_DIR/resume-session.sh" --dry-run --resume "$WORKSPACE/deliverables/RESUME.md" >/dev/null 2>&1; then
            note 7 red "RESUME.md hash-verification failed (corrupt or stale)"
        fi
    fi

    [ "${PILLAR_VERDICT[7]}" = "green" ] && PILLAR_NOTES[7]="all checks green"
}

# ---------------------------------------------------------------------------
# Run pillars
# ---------------------------------------------------------------------------
case "$PILLAR" in
    all)
        pillar_1; pillar_2; pillar_3; pillar_4
        pillar_5; pillar_6; pillar_7
        ;;
    1) pillar_1 ;;
    2) pillar_2 ;;
    3) pillar_3 ;;
    4) pillar_4 ;;
    5) pillar_5 ;;
    6) pillar_6 ;;
    7) pillar_7 ;;
    *) echo "[FATAL] --pillar must be 1-7 or all" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [ "$ROBOT" -eq 1 ]; then
    # JSON output. NOTE: `local` is invalid outside of function bodies in bash;
    # the variables here (`first`, `notes_json`, `emoji`) live at script scope,
    # which is fine — the script exits immediately after this block, so there
    # are no globals to leak into.
    {
        printf '{\n  "workspace": %s,\n  "verdict": %s,\n  "pillars": {\n' \
            "$(json_string "$WORKSPACE")" \
            "$(json_string "$WORST")"
        first=1
        for n in 1 2 3 4 5 6 7; do
            if [ -n "${PILLAR_VERDICT[$n]:-}" ]; then
                [ "$first" -eq 1 ] || printf ',\n'
                first=0
                notes_json=$(printf '%s' "${PILLAR_NOTES[$n]:-}" | jq -Rs . 2>/dev/null || echo '""')
                printf '    "%d": {"verdict": %s, "notes": %s}' \
                    "$n" \
                    "$(json_string "${PILLAR_VERDICT[$n]}")" \
                    "$notes_json"
            fi
        done
        printf '\n  }\n}\n'
    }
else
    # Human-readable
    cat <<EOF

=== Brennerbot Doctor Report ===
Workspace: $WORKSPACE
Verdict:   $(echo "$WORST" | tr '[:lower:]' '[:upper:]')
Date:      $(date -u +%Y-%m-%dT%H:%M:%SZ)

Per-pillar verdicts:

EOF
    for n in 1 2 3 4 5 6 7; do
        if [ -n "${PILLAR_VERDICT[$n]:-}" ]; then
            case "${PILLAR_VERDICT[$n]}" in
                green)  emoji="🟢" ;;
                yellow) emoji="🟡" ;;
                red)    emoji="🔴" ;;
            esac
            printf "  Pillar %d: %s %s\n" "$n" "$emoji" "${PILLAR_VERDICT[$n]}"
            printf '%s' "${PILLAR_NOTES[$n]:-}" | sed 's/^/    /'
        fi
    done

    cat <<EOF

Per references/BRENNERBOT-DOCTOR-RUBRIC.md, recovery sequencing:
  Pillar 1 → 3 → 5 → 2 → 4 → 6 → 7

Worst verdict ($WORST) determines:
  green  → continue normally
  yellow → continue with caveats; document
  red    → recover specific pillar before continuing
EOF
fi

# Exit code: 0 green, 1 yellow, 2 red
case "$WORST" in
    green)  exit 0 ;;
    yellow) exit 1 ;;
    red)    exit 2 ;;
esac
