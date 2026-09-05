#!/usr/bin/env bash
set -euo pipefail

# validate-skill.sh — meta-doctor for the skill itself (Pattern 12).
#
# Validates the skill's internal consistency. Each "Section N" block is a
# self-contained detector for one drift class historically caught by hand.
# Adding new detectors: append a new numbered block before the violations
# summary. Use `report` to record violations.
#
#   Section 1: frontmatter description ≤ 1024 chars + name matches dir
#   Section 2: every Q-NNN citation resolves to QUOTE-BANK.md
#   Section 3: every subagent file is referenced from SKILL.md
#   Section 4: all scripts/ files are executable
#   Section 5: every markdown link resolves to an existing file
#   Section 6: forbidden destructive command forms do not appear in scripts/
#   Section 7: no orphan methodology files (every one referenced from SKILL.md)
#   Section 8: every backtick-wrapped `scripts/<name>` reference exists
#              (or is annotated planned/proposed/future)
#   Section 9: no CI-snippet line in docs invokes `./scripts/scorecard.py`
#              (cross-repo bug class — round 36/49/51)
#  Section 10: every `discover-cli.sh <target>` invocation in docs has
#              `--probe-doctor` (or `# language-only` annotation)
#              (round 52 Bugs 3/4)
#  Section 11: docs MUST NOT list `Chown` in the Op enum without an
#              "optional" qualifier — Chown is the optional 8th variant
#              (rounds 43, 52)
#  Section 12: doctor-verb-list enumerations MUST include all 7 verbs
#              (doctor/health/verify/repair/check/diagnose/fix), not just
#              the older 5-verb subset (round 19)
#  Section 13: CI YAML steps running `<tool> doctor --json` MUST handle
#              exit code 1 (findings present) explicitly to avoid `bash -e`
#              abort (round 52 Bug 2)
#  Section 14: every shell script under scripts/ has `set -euo pipefail`
#              within first 20 lines (round 16)
#  Section 15: no scripts/*.sh or scripts/*.py contains hardcoded
#              user-specific absolute paths (/data/projects/, /home/<user>/,
#              /Users/<user>/) outside example-marked comments (round 25)
#
# Usage: validate-skill.sh <skill-dir>
# Exit 0 if clean, 1 if violations on stderr.

skill_dir="${1:?usage: validate-skill.sh <skill-dir>}"
[ -d "$skill_dir" ] || { echo "error: $skill_dir is not a directory" >&2; exit 66; }
cd "$skill_dir"
[ -f SKILL.md ] || { echo "error: $skill_dir has no SKILL.md" >&2; exit 66; }

violations=0
report() {
    echo "VIOLATION: $1" >&2
    violations=$((violations + 1))
}

echo "validate-skill.sh: auditing $skill_dir" >&2

# 1. Frontmatter checks.
desc_chars=$(awk '/^---$/{n++;next} n==1' SKILL.md | wc -c)
if [ "$desc_chars" -gt 1024 ]; then
    report "SKILL.md frontmatter description is $desc_chars chars (exceeds 1024 budget)"
fi

frontmatter_name=$(awk '/^---$/{n++;next} n==1 && /^name:/{print $2; exit}' SKILL.md)
# Resolve to absolute path before basename so the user can pass `.` or a relative path.
abs_dir=$(cd "$skill_dir" 2>/dev/null && pwd) || abs_dir="$skill_dir"
dir_name=$(basename "$abs_dir")
if [ "$frontmatter_name" != "$dir_name" ]; then
    report "frontmatter name '$frontmatter_name' does not match directory name '$dir_name'"
fi

# 2. Q-NNN citations resolve.
declare -A defined_qids
if [ -f references/methodology/QUOTE-BANK.md ]; then
    while IFS= read -r qid; do
        defined_qids[$qid]=1
    done < <(grep -E '^### Q-[0-9]{3} ' references/methodology/QUOTE-BANK.md \
             | sed -E 's|^### (Q-[0-9]{3}) .*|\1|')
fi
while IFS= read -r qid; do
    if [ -z "${defined_qids[$qid]:-}" ]; then
        report "Q-NNN citation $qid not defined in QUOTE-BANK.md"
    fi
done < <(grep -hroE --include='*.md' --exclude-dir='.git' 'Q-[0-9]{3}' . | sort -u | grep -v '^Q-NNN$')

# 3. Subagent files referenced.
if [ -d subagents ]; then
    for f in subagents/*.md; do
        name=$(basename "$f")
        if ! grep -q "subagents/$name" SKILL.md; then
            report "subagents/$name is present but not referenced from SKILL.md"
        fi
    done
fi

# 4. Scripts executable.
if [ -d scripts ]; then
    for f in scripts/*.sh scripts/*.py; do
        [ -e "$f" ] || continue
        if [ ! -x "$f" ]; then
            report "$f is not executable (chmod +x required)"
        fi
    done
fi

# 5. Cross-references resolve.
while IFS= read -r ref; do
    target=$(echo "$ref" | awk -F'|' '{print $1}')
    src=$(echo "$ref" | awk -F'|' '{print $2}')
    src_dir=$(dirname "$src")
    case "$target" in
        http://*|https://*|/*) continue ;;
        ../../*) continue ;;  # external skill references; not our problem
    esac
    resolved=$(cd "$src_dir" 2>/dev/null && readlink -m "$target" 2>/dev/null || echo "")
    if [ -n "$resolved" ] && [ ! -e "$resolved" ]; then
        report "broken markdown link in $src: $target (resolved: $resolved)"
    fi
done < <(
    find . -name '*.md' -print0 | while IFS= read -r -d '' f; do
        { grep -oE '\]\(([^)]*\.md)(#[^)]*)?\)' "$f" 2>/dev/null || true; } \
          | sed -E 's|^\]\(||; s|\)$||; s|#.*$||' \
          | while IFS= read -r link; do
              printf '%s|%s\n' "$link" "$f"
          done
    done
)

# 6. No destructive shell in scripts/ outside well-marked exemption blocks.
if [ -d scripts ]; then
    for pat in 'rm -rf' 'git reset --hard' 'git clean -fd'; do
        while IFS= read -r line; do
            file="${line%%:*}"
            lineno="${line#*:}"
            lineno="${lineno%%:*}"
            content=$(sed -n "${lineno}p" "$file")
            # Trim leading whitespace for comment-detection.
            stripped="${content#"${content%%[![:space:]]*}"}"
            # Allow if the line is exempt under any of:
            #   (a) shell comment (post-strip starts with #) AND mentions a
            #       documented "we do NOT do this" marker;
            #   (b) the pattern appears inside a single-quoted forbidden-array
            #       declaration (the validator listing what to BLOCK in OTHER
            #       code), detected by absence of any unescaped command form
            #       on the same line.
            #
            # We do NOT place the literal forbidden strings inside case
            # patterns here, because backticks/escapes in case-pattern words
            # can be parse-time hazards in some shells. Per AGENTS.md, route
            # through a string comparison built up at runtime instead.
            exempt=false
            case "$stripped" in
                \#*NEVER*|\#*never*|\#*forbidden*|\#*do\ NOT*|\#*do\ not*) exempt=true ;;
                \#*Per\ AGENTS.md*|\#*"No "*|\#*"NOT "*) exempt=true ;;
            esac
            if [ "$exempt" = false ]; then
                # Substring tests via [[ ... == ... ]] (not case patterns).
                # The forbidden-array declaration uses single-quoted strings,
                # which we detect by 'pat' as a substring with surrounding quotes.
                quoted_form="'${pat}'"
                regex_form="'\b${pat%% *}"
                if [[ "$content" == *"$quoted_form"* ]] \
                || [[ "$content" == *"$regex_form"* ]]; then
                    exempt=true
                fi
            fi
            if [ "$exempt" = true ]; then
                continue
            fi
            report "$file:$lineno contains forbidden pattern '$pat'"
        done < <(grep -rnHE "$pat" scripts/ 2>/dev/null || true)
    done
fi

# 7. Methodology orphan check.
if [ -d references/methodology ]; then
    for f in references/methodology/*.md; do
        name=$(basename "$f")
        if ! grep -q "$name" SKILL.md; then
            report "references/methodology/$name is orphaned (not in SKILL.md)"
        fi
    done
fi

# 8. Every backtick-wrapped `scripts/<name>` reference must either
#    (a) point to a file that exists on disk, OR
#    (b) appear on a line that explicitly marks it planned/proposed/future/optional.
#    This is the gap that allowed `validate-scorecard.py`, `render-heatmap.py`,
#    `snapshot-baseline.sh`, and `corrupt-fixture.sh` to drift undetected
#    across multiple rounds.
# shellcheck disable=SC2016  # Literal regex for backticked script references.
while IFS= read -r ref_line; do
    # Format: <file>:<lineno>:<full line text>
    file="${ref_line%%:*}"
    rest="${ref_line#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"
    # Extract every backticked `scripts/<name>` token on the line.
    # shellcheck disable=SC2016  # Literal regex for backticked script references.
    tokens=$(echo "$content" | grep -oE '`scripts/[a-zA-Z0-9._-]+`' || true)
    [ -z "$tokens" ] && continue
    # Skip if the line marks the reference planned/proposed/future/optional/etc.
    lower_content=$(echo "$content" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower_content" == *"planned"* ]] \
    || [[ "$lower_content" == *"proposed"* ]] \
    || [[ "$lower_content" == *"future"* ]] \
    || [[ "$lower_content" == *"optionally write"* ]] \
    || [[ "$lower_content" == *"not implemented"* ]] \
    || [[ "$lower_content" == *"will exist"* ]] \
    || [[ "$lower_content" == *"when it exists"* ]] \
    || [[ "$lower_content" == *"does not exist"* ]] \
    || [[ "$lower_content" == *"removed"* ]] \
    || [[ "$lower_content" == *"replaced"* ]] \
    || [[ "$lower_content" == *"wrong path"* ]]; then
        continue
    fi
    while IFS= read -r tok; do
        # Strip backticks → bare path.
        path="${tok//\`/}"
        if [ ! -e "$path" ]; then
            report "$file:$lineno references missing $path (mark planned/proposed/future, or create the script)"
        fi
    done <<< "$tokens"
done < <(
    find . -name '*.md' ! -name 'CHANGELOG.md' -print0 2>/dev/null \
      | xargs -0 -r grep -nHE '`scripts/[a-zA-Z0-9._-]+`' 2>/dev/null \
      || true
)

# 9. Cross-repo CI invocation: docs MUST NOT show CI snippets that invoke
#    `./scripts/scorecard.py` from a target's CI runner — the script lives in
#    THIS skill's repo, not the target's CI workdir. Caught in rounds 36/49/51.
#    Detection: any *.md line (excluding CHANGELOG.md) starting with `- run:`
#    or `run:` and invoking `./scripts/scorecard.py`.
while IFS= read -r ref_line; do
    file="${ref_line%%:*}"
    rest="${ref_line#*:}"
    lineno="${rest%%:*}"
    report "$file:$lineno is a CI snippet invoking ./scripts/scorecard.py — script lives in skill repo, not target's CI workdir; use the canonical jq-based pattern from subagents/integration-wirer.md § Step 2"
done < <(
    find . -name '*.md' ! -name 'CHANGELOG.md' -print0 2>/dev/null \
      | xargs -0 grep -nHE '^[[:space:]]*-?[[:space:]]*run:[[:space:]]*\./scripts/scorecard\.py' 2>/dev/null \
      || true
)

# 10. discover-cli.sh invocations in docs MUST include --probe-doctor when the
#     surrounding text describes upgrade-mode behavior (existing-doctor probe).
#     Caught in round-52 (Bugs 3 + 4). Detection: any code-fence-context line
#     in *.md that invokes `discover-cli.sh <target>` or `discover-cli.sh .`
#     without `--probe-doctor`. Allow `--probe-doctor=false` in CHANGELOG-history.
while IFS= read -r match_line; do
    file="${match_line%%:*}"
    rest="${match_line#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"
    # Skip lines with an explicit "language-only" or "skip probe" marker.
    if [[ "$content" == *"# language-only"* ]] \
    || [[ "$content" == *"# skip probe"* ]] \
    || [[ "$content" == *"# no probe"* ]]; then
        continue
    fi
    report "$file:$lineno invokes discover-cli.sh without --probe-doctor — required for the upgrade-mode heuristic; add the flag or annotate '# language-only'"
done < <(
    find . -name '*.md' ! -name 'CHANGELOG.md' -print0 2>/dev/null \
      | xargs -0 grep -nHE 'discover-cli\.sh[[:space:]]+(<target>|\.)' 2>/dev/null \
      | grep -v -- '--probe-doctor' \
      || true
)

# 11. Canonical Op-list MUST be 7 variants (no Chown) unless explicitly marked
#     optional. Caught in round 43 (MUTATE-CHOKEPOINT.md) + round 52 (GLOSSARY.md
#     sweep gap). The 5 reference recipes (rust/go/python/typescript/jvm) all
#     implement exactly 7. Detection: any line listing Chown alongside the
#     other Ops without a nearby "optional" qualifier (within 200 chars).
while IFS= read -r match_line; do
    file="${match_line%%:*}"
    rest="${match_line#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"
    # Skip if "optional" appears on the same line (qualifier present).
    if echo "$content" | grep -qiE 'optional|8th variant|opt-in|may.*implement'; then
        continue
    fi
    report "$file:$lineno lists Chown in the Op enum without an 'optional' qualifier — Chown is the optional 8th variant; the 5 reference recipes implement only 7"
done < <(
    find . -name '*.md' ! -name 'CHANGELOG.md' ! -name 'MUTATE-CHOKEPOINT.md' -print0 2>/dev/null \
      | xargs -0 grep -nHE '(WriteFile.*Chown|Chmod.*Chown|Chown.*DbExec|Chown.*DbMigrate)' 2>/dev/null \
      || true
)

# 12. 7-verb-list completeness: when a doc enumerates "doctor surface verbs",
#     it must list all 7 (doctor/health/verify/repair/check/diagnose/fix) —
#     not the older 5-verb subset. Caught in round 19. Detection: any line
#     enumerating ≥3 of the early verbs (doctor/health/verify/repair/check)
#     joined by ` / ` MUST also include diagnose AND fix on the same line.
while IFS= read -r match_line; do
    file="${match_line%%:*}"
    rest="${match_line#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"
    # Heuristic: match a "verb-list" pattern (3+ early verbs joined by "/").
    if echo "$content" | grep -qE 'doctor[[:space:]]*/[[:space:]]*health[[:space:]]*/[[:space:]]*verify'; then
        if ! echo "$content" | grep -qE 'diagnose' \
        || ! echo "$content" | grep -qE 'fix'; then
            report "$file:$lineno enumerates the doctor verb-list but is missing 'diagnose' and/or 'fix' — discover-cli.sh probes all 7; lists must match"
        fi
    fi
done < <(
    find . -name '*.md' ! -name 'CHANGELOG.md' -print0 2>/dev/null \
      | xargs -0 grep -nHE 'doctor[[:space:]]*/[[:space:]]*health' 2>/dev/null \
      || true
)

# 13. CI exit-code handling for `<tool> doctor --json`: doctor exits 1 when
#     findings are present (canonical), so CI YAML steps invoking it bare
#     under `bash -e` will abort. Caught in round 52 (Bug 2). Detection: any
#     *.md line in a YAML context starting with `- run: <tool> doctor --json`
#     OR `- run: <tool> doctor --quick --json` that is NOT inside a `- run: |`
#     multiline block AND doesn't have explicit exit-code handling.
while IFS= read -r match_line; do
    file="${match_line%%:*}"
    rest="${match_line#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"
    # Allow: lines that catch the exit code via `|| rc=$?` or `|| doctor_rc=$?`.
    if echo "$content" | grep -qE '\|\|[[:space:]]*(rc|doctor_rc|status|ec)=\$\?'; then
        continue
    fi
    # Allow: lines that are inside an `if !` guard.
    if echo "$content" | grep -qE 'if[[:space:]]+!'; then
        continue
    fi
    # Allow: pre-commit YAML hook entries (pre-commit handles exit-code semantics).
    if echo "$content" | grep -qE 'entry:[[:space:]]*[a-zA-Z_<][a-zA-Z_>0-9-]*[[:space:]]+doctor'; then
        continue
    fi
    report "$file:$lineno is a CI YAML step running 'doctor --json' bare; under bash -e exit code 1 (findings present) aborts the step. Wrap with '|| rc=\$?; case \"\$rc\" in 0|1) ;; *) exit \"\$rc\";; esac' (see subagents/integration-wirer.md § Step 2)"
done < <(
    # Match either the placeholder form (<tool>) or any literal tool name —
    # tools the skill is applied to use their actual binary name (e.g.,
    # `br doctor --json`), so the detector must catch both. Required pattern:
    # `- run: <name> doctor` followed (eventually) by `--json` on same line,
    # without `health` between (since health's exit-1 IS an intentional gate).
    find . -name '*.md' ! -name 'CHANGELOG.md' -print0 2>/dev/null \
      | xargs -0 grep -nHE '^[[:space:]]*-[[:space:]]+run:[[:space:]]+(<tool>|[a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]+doctor[[:space:]]+(--quick[[:space:]]+)?--json' 2>/dev/null \
      || true
)

# 14. Every shell script under scripts/ MUST have `set -euo pipefail` near
#     its top (within first 20 lines). Caught in round 16 (regression-test-template
#     lacked it). Detection: enumerate scripts/*.sh and assert the option is set.
if [ -d scripts ]; then
    for f in scripts/*.sh; do
        [ -e "$f" ] || continue
        # Look for any of: `set -euo pipefail`, or all three of -e, -u, and pipefail
        # set independently. Allow modular forms.
        head_text=$(head -20 "$f")
        has_e=false; has_u=false; has_pipefail=false
        # All three flags must appear on a `set` line (anchored to start
        # of line, possibly indented). Otherwise the literal strings would
        # match inside echo bodies and other prose.
        if echo "$head_text" | grep -qE '^[[:space:]]*set[[:space:]]+-[a-z]*e'; then has_e=true; fi
        if echo "$head_text" | grep -qE '^[[:space:]]*set[[:space:]]+-[a-z]*u'; then has_u=true; fi
        if echo "$head_text" | grep -qE '^[[:space:]]*set[[:space:]]+(-o[[:space:]]+pipefail|-[a-z]*o[[:space:]]+pipefail)'; then has_pipefail=true; fi
        if [ "$has_e" = false ] || [ "$has_u" = false ] || [ "$has_pipefail" = false ]; then
            missing=""
            [ "$has_e" = false ] && missing+="-e "
            [ "$has_u" = false ] && missing+="-u "
            [ "$has_pipefail" = false ] && missing+="pipefail"
            report "$f is missing 'set -euo pipefail' (missing: $missing) — required for safe failure handling"
        fi
    done
fi

# 15. No hardcoded user-specific paths in scripts/. Caught in round 25
#     (an absolute path under /data/projects/<author>/ made the script work
#     on one machine and silently miss installations on others). Detection: scan
#     scripts/*.sh and scripts/*.py for absolute paths under /data/projects/,
#     /home/<user>/, /Users/<user>/ that are NOT inside comments or string
#     literals containing the word "example".
if [ -d scripts ]; then
    while IFS= read -r match_line; do
        file="${match_line%%:*}"
        rest="${match_line#*:}"
        lineno="${rest%%:*}"
        content="${rest#*:}"
        # Trim leading whitespace.
        stripped="${content#"${content%%[![:space:]]*}"}"
        # Allow: shell comments mentioning "example" or "WRONG" or "DON'T".
        if [[ "$stripped" == \#* ]]; then
            if echo "$stripped" | grep -qiE 'example|wrong|do[[:space:]]*not|never|forbidden|previously|round-25'; then
                continue
            fi
        fi
        # Allow: Python docstrings/comments containing "example".
        if echo "$content" | grep -qiE '"""|example|wrong'; then
            continue
        fi
        report "$file:$lineno contains hardcoded user-specific path — use \$(cd \"\$(dirname \"\$0\")/...\" && pwd) or env-var-based discovery"
    done < <(
        # Exclude validate-skill.sh from its own self-scan: this script's detector
        # regex literally contains the patterns it's looking for, which would
        # produce permanent self-references.
        for f in scripts/*.sh scripts/*.py; do
            [ -e "$f" ] || continue
            case "$(basename "$f")" in
                validate-skill.sh) continue ;;
            esac
            grep -nHE '/data/projects/|/home/[a-z][a-z0-9_-]+/[^[:space:]"]+|/Users/[a-zA-Z][a-zA-Z0-9_-]+/[^[:space:]"]+' "$f" 2>/dev/null
        done | grep -v '/home/ubuntu' || true
    )
fi

# 16. Numerical-claim consistency. Round-55 idea: extend Section 11/12's
#     pattern (Op-list, verb-list) to ALL canonical-counted claims. Each
#     entry maps a NOUN-PHRASE to its canonical count; the detector reads
#     `<number><noun-phrase>` constructs and flags any mismatch.
#       - "dimension rubric"        → 10  (SCORING-RUBRIC.md anchors)
#       - "canonical subcommand"    → 10
#       - "doctor subcommand"       → 10
#       - "canonical exit code"     → 11
#       - "canonical Op variant"    → 7
#       - "axiom kernel"            → 24
#       - "canonical CASS quer"     → 13
#     If the canonical count itself ever changes, update BOTH this dict AND
#     the source-of-truth file in the same edit (the dict IS the contract
#     for this detector).
declare -A CANONICAL_PHRASES=(
    ["dimension rubric"]="10"
    ["canonical subcommand"]="10"
    ["doctor subcommand"]="10"
    ["canonical exit code"]="11"
    ["canonical Op variant"]="7"
    ["axiom kernel"]="24"
    ["canonical CASS quer"]="13"
)
for phrase in "${!CANONICAL_PHRASES[@]}"; do
    expected="${CANONICAL_PHRASES[$phrase]}"
    # Match: optional [0-9]+ followed by 0-1 space-or-hyphen followed by the
    # phrase. Capture the number (if any). Skip lines where no number was
    # captured — those are noun-only mentions, not counted claims.
    while IFS= read -r match_line; do
        file="${match_line%%:*}"
        rest="${match_line#*:}"
        lineno="${rest%%:*}"
        content="${rest#*:}"
        # Pull every count-then-phrase occurrence on the line; verify each.
        # The grep extracts the full match (e.g., "8-dimension rubric");
        # then we strip down to the leading digits.
        while IFS= read -r match; do
            actual=$(echo "$match" | grep -oE '^[0-9]+' || true)
            [ -z "$actual" ] && continue
            if [ "$actual" != "$expected" ]; then
                report "$file:$lineno claims '$match' but canonical is '$expected $phrase' (round-55 detector 16)"
            fi
        done < <(echo "$content" | grep -oE "[0-9]+[ -]?$phrase" || true)
    done < <(
        find . -name '*.md' ! -name 'CHANGELOG.md' -print0 2>/dev/null \
          | xargs -0 grep -nHE "[0-9]+[ -]?$phrase" 2>/dev/null \
          || true
    )
done

# 17. Shell code blocks parse cleanly. Round-55 idea #9: every ```bash``` (or
#     ```sh```) code block in markdown should be syntactically valid; otherwise
#     copy-paste examples in the docs are silently broken. We pipe each block
#     through `bash -n` (parse-only mode; doesn't execute). Skip blocks that
#     contain template placeholders (`<tool>`, `{{var}}`, `<workspace>`, etc.)
#     or are explicitly marked `<!-- noverify -->` on the preceding line.
#
#     Implementation note: extracting code blocks from markdown reliably
#     requires a small awk filter — we look for lines ` ```bash` or ` ```sh`
#     and accumulate until the closing ` ``` `, then write to a temp file
#     and run bash -n.
verify_shell_blocks() {
    local md="$1"
    local in_block=0
    local block=""
    local block_start=0
    local lineno=0
    local prev_line=""
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        if [ "$in_block" -eq 0 ]; then
            case "$line" in
                '```bash'*|'```sh')
                    # Skip if previous line had noverify marker.
                    case "$prev_line" in
                        *'<!-- noverify -->'*) prev_line="$line"; continue ;;
                    esac
                    in_block=1
                    block=""
                    block_start=$lineno
                    ;;
            esac
        else
            case "$line" in
                '```'*)
                    # End of block; check it.
                    # Skip if it contains template placeholders.
                    if echo "$block" | grep -qE '<tool>|<N>|\{\{[a-z_]+\}\}|<workspace>|<target>|<run-id>|<fm[_-]id>|<bin>|<some_other_target>|<tool-binary-path>|<sub-bin>|<sub-crate-dir>|<your-skills-dir>|<repo>|<doctor[_-][ab][_-]?cmd>|<doctor_a>|<doctor_b>|<fixture_root>|<branch>|<workspace-basename>|<run_dir>|<history_jsonl>|<system>|<name>|<id>|<finding-id>|<short>|<paste-ready>|<sym>|<int>|<related-skill>|<rel-path>|<path>|<tag>|<sha>|<sub-(name|run-id)>|\.\.\.'; then
                        :
                    else
                        if ! bash -n <<< "$block" 2>/dev/null; then
                            report "$md:$block_start shell code block fails 'bash -n' syntax check (use <!-- noverify --> above the block to exempt)"
                        fi
                    fi
                    in_block=0
                    block=""
                    ;;
                *)
                    block="$block$line"$'\n'
                    ;;
            esac
        fi
        prev_line="$line"
    done < "$md"
}
while IFS= read -r md; do
    [ -f "$md" ] || continue
    verify_shell_blocks "$md"
done < <(
    find . -name '*.md' ! -name 'CHANGELOG.md' 2>/dev/null
)

if [ "$violations" -gt 0 ]; then
    echo "validate-skill.sh: $violations violation(s)" >&2
    exit 1
fi

echo "validate-skill.sh: OK ($skill_dir is consistent)" >&2
exit 0
