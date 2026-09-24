#!/usr/bin/env bash
# skills-selftest.sh — Lint the skills this repo owns.
#
# Owned skills are the top-level dirs in ~/.claude/skills that dotfiles
# tracks, minus submodules, gitignored dirs, and anything installed by
# `skills-sync` or `jsm`.
#
# Checks:
#   - stale model pins: gpt-5.4, claude-fable-5 (bare), Opus 4.x, claude-sonnet-4-2*
#   - SKILL.md frontmatter not starting at line 1
#   - two skills with identical SKILL.md bodies (text after frontmatter)
#   - `codex exec ... --sandbox read-only` that is not an image (-i) call
#
# Usage:
#   skills-selftest.sh           # prints file:line per failure
#   skills-selftest.sh --list    # print the owned skill names and exit
#
# Exit code: 0 = clean, 1 = failures found

set -euo pipefail

REPO="$HOME/.dotfiles"
SKILLS_REL=".claude/skills"

# ── Owned skill set ─────────────────────────────────────────────────────

external_names() {
    if command -v skills-sync >/dev/null 2>&1; then
        skills-sync list 2>/dev/null | sed -n 's/^[[:space:]]*- \([^[:space:]]*\).*/\1/p'
    else
        echo "warn: skills-sync not found; external skills may be counted as owned" >&2
    fi
    if command -v jsm >/dev/null 2>&1; then
        # Table rows: NAME VERSION STATUS ...; skip the header and legend.
        jsm list 2>/dev/null | awk 'NF >= 3 && $1 ~ /^[a-z0-9][a-z0-9._-]*$/ && $2 ~ /^[0-9]+$/ {print $1}'
    else
        echo "warn: jsm not found; external skills may be counted as owned" >&2
    fi
}

owned_skills() {
    local -A external=() submodule=()
    local name
    while read -r name; do
        [[ -n "$name" ]] && external["$name"]=1
    done < <(external_names)
    while read -r _ _ _ path; do
        submodule["${path#"$SKILLS_REL"/}"]=1
    done < <(git -C "$REPO" ls-files -s -- "$SKILLS_REL" | awk '$1 == "160000"')

    git -C "$REPO" ls-files -- "$SKILLS_REL" \
        | awk -F/ 'NF >= 4 {print $3}' | sort -u \
        | while read -r name; do
            [[ -d "$REPO/$SKILLS_REL/$name" ]] || continue
            [[ -n "${submodule[$name]:-}" ]] && continue
            [[ -n "${external[$name]:-}" ]] && continue
            git -C "$REPO" check-ignore -q --no-index "$SKILLS_REL/$name/" && continue
            echo "$name"
        done
}

mapfile -t SKILLS < <(owned_skills)

if [[ "${1:-}" == "--list" ]]; then
    printf '%s\n' "${SKILLS[@]}"
    exit 0
fi

if [[ ${#SKILLS[@]} -eq 0 ]]; then
    echo "error: no owned skills found under $REPO/$SKILLS_REL" >&2
    exit 1
fi

# Known-good matches, as "path:pattern". cm 0.2.9 ships claude-sonnet-4-20250514
# as its default model, so the cass-memory docs quote it correctly.
PIN_ALLOW=(
    ".claude/skills/cass-memory/references/ARCHITECTURE.md:claude-sonnet-4-2"
)

# Tracked dirs under skills/ that hold scripts, not skills.
NOT_SKILLS=(lab-deploy)

FAILURES=0
fail() {
    echo "$1: $2"
    FAILURES=$((FAILURES + 1))
}

# Tracked text files of every owned skill, repo-relative.
mapfile -t FILES < <(
    for s in "${SKILLS[@]}"; do
        git -C "$REPO" ls-files -- "$SKILLS_REL/$s/"
    done | while read -r f; do
        [[ -f "$REPO/$f" ]] && grep -Iq . "$REPO/$f" 2>/dev/null && echo "$f"
    done
)

# ── Stale model pins ────────────────────────────────────────────────────

PIN_RE='gpt-5\.4(?![0-9])|claude-fable-5(?![-.0-9])|Opus 4\.|claude-sonnet-4-2'
if [[ ${#FILES[@]} -gt 0 ]]; then
    while IFS= read -r hit; do
        file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
        match=$(grep -oP "$PIN_RE" <<<"${rest#*:}" | head -1)
        [[ " ${PIN_ALLOW[*]} " == *" $file:$match "* ]] && continue
        fail "$file:$line" "stale model pin '$match'"
    done < <(cd "$REPO" && grep -nHP "$PIN_RE" -- "${FILES[@]}" || true)
fi

# ── SKILL.md frontmatter and duplicate bodies ───────────────────────────

declare -A BODY_OWNER=()
for s in "${SKILLS[@]}"; do
    skill_md=$(git -C "$REPO" ls-files -- "$SKILLS_REL/$s/" \
        | grep -iE "^$SKILLS_REL/$s/skill\.md$" | head -1 || true)
    [[ " ${NOT_SKILLS[*]} " == *" $s "* ]] && continue
    if [[ -z "$skill_md" ]]; then
        fail "$SKILLS_REL/$s" "no SKILL.md"
        continue
    fi
    path="$REPO/$skill_md"

    first=$(head -1 "$path" | tr -d '\r')
    if [[ "$first" != "---" ]]; then
        fm_line=$(grep -nx -- '---' "$path" | head -1 | cut -d: -f1 || true)
        fail "$skill_md:${fm_line:-1}" "frontmatter does not start at line 1"
    fi

    # Body = everything after the closing '---' of the first frontmatter block.
    body_hash=$(awk 'f >= 2 {print; next} /^---\r?$/ {f++}' "$path" \
        | sed -e 's/[[:space:]]*$//' | sed -e '/./,$!d' | sha1sum | cut -d' ' -f1)
    if [[ -n "${BODY_OWNER[$body_hash]:-}" ]]; then
        fail "$skill_md:1" "SKILL.md body identical to ${BODY_OWNER[$body_hash]}"
    else
        BODY_OWNER[$body_hash]="$skill_md"
    fi
done

# ── codex exec --sandbox read-only outside image calls ──────────────────

for f in "${FILES[@]}"; do
    # Join backslash-continued lines so a multi-line command is one record.
    while IFS=$'\t' read -r line cmd; do
        fail "$f:$line" "codex exec with --sandbox read-only (not an -i image call)"
    done < <(awk '
        {
            sub(/\r$/, "")
            if (buf == "") start = NR
            buf = buf " " $0
            if ($0 ~ /\\$/) next
            if (buf ~ /codex[[:space:]]+exec/ && buf ~ /--sandbox[[:space:]=]+read-only/ \
                && buf !~ /(^|[[:space:]])(-i|--image)([[:space:]=]|$)/)
                printf "%d\t%s\n", start, buf
            buf = ""
        }' "$REPO/$f")
done

# ── Result ──────────────────────────────────────────────────────────────

if [[ $FAILURES -gt 0 ]]; then
    echo "skills-selftest: $FAILURES failure(s) across ${#SKILLS[@]} owned skills" >&2
    exit 1
fi
echo "skills-selftest: ${#SKILLS[@]} owned skills clean" >&2
