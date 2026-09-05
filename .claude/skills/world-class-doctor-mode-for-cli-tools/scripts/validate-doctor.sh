#!/usr/bin/env bash
# validate-doctor.sh — enforce the universal safety envelope.
#
# Asserts:
#   - mutate() is the only writer under doctor --fix
#   - no destructive shell commands inside the doctor module
#   - atomic writes only (no direct std::fs::write / os.WriteFile / fs.writeFileSync
#     outside mutate())
#
# Usage: validate-doctor.sh <target>
# Exit 0 if clean, ≥ 1 with violations on stderr.

set -euo pipefail
target="${1:-.}"
cd "$target"

violations=0
report() {
    echo "VIOLATION: $1" >&2
    violations=$((violations + 1))
}

# Language detection (light).
language=""
[ -f Cargo.toml ] && language="rust"
[ -f go.mod ] && language="go"
[ -f pyproject.toml ] && language="python"
[ -f package.json ] && language="${language:-typescript}"

# Find the doctor module(s). Use `shopt -s nullglob` so that wildcard
# patterns with no matches expand to nothing (instead of staying as the
# literal pattern, which the prior `for x in $p` loop relied on but which
# would also word-split on paths containing spaces — e.g.,
# `cmd/my server/cmd/doctor.go` would split into "cmd/my" and
# "server/cmd/doctor.go", neither of which exists).
doctor_paths=()
shopt -s nullglob
case "$language" in
    rust)
        for p in src/cli/commands/doctor.rs src/doctor.rs src/doctor/; do
            [ -e "$p" ] && doctor_paths+=("$p")
        done
        ;;
    go)
        for p in cmd/*/cmd/doctor.go cmd/*/doctor/ internal/doctor/; do
            [ -e "$p" ] && doctor_paths+=("$p")
        done
        ;;
    python)
        for p in src/*/doctor.py src/*/doctor/ doctor.py; do
            [ -e "$p" ] && doctor_paths+=("$p")
        done
        ;;
    typescript)
        for p in src/doctor.ts src/cli/doctor.ts src/doctor/; do
            [ -e "$p" ] && doctor_paths+=("$p")
        done
        ;;
esac
shopt -u nullglob

if [ ${#doctor_paths[@]} -eq 0 ]; then
    echo "no doctor module found under $target — phase 4 not yet started?" >&2
    exit 0
fi

# Forbidden patterns (writes that bypass mutate()).
declare -a forbidden=(
    'std::fs::write\b'
    'std::fs::remove_file\b'
    'std::fs::remove_dir'
    'fs\.writeFileSync\b'
    'fs\.unlink\b'
    'fs\.unlinkSync\b'
    'fs\.rmSync\b'
    'fs\.rmdirSync\b'
    'os\.WriteFile\('
    'os\.Remove\('
    'os\.RemoveAll\('
    'shutil\.rmtree\b'
    'os\.unlink\b'
    '\.unlink\('
    'File\.rm\('
    'open\(.*"w"\)'
    '\brm -[a-zA-Z]*r'
    'git reset --hard'
    'git clean -[a-zA-Z]*f'
    '\bDROP TABLE\b'
    '\bkubectl delete\b'
)

for path in "${doctor_paths[@]}"; do
    for pat in "${forbidden[@]}"; do
        # Allow occurrences inside mutate()'s definition (it IS the chokepoint
        # and uses these primitives correctly). Heuristic: a match is OK if
        # within 60 lines of `fn mutate|func Mutate|def mutate|export.*function mutate`.
        while IFS= read -r line; do
            file="${line%%:*}"
            lineno="${line#*:}"
            lineno="${lineno%%:*}"
            # Search backwards 60 lines for the mutate() definition.
            start=$((lineno > 60 ? lineno - 60 : 1))
            if sed -n "${start},${lineno}p" "$file" \
                | grep -qE 'fn mutate|func Mutate|def mutate|export[[:space:]]+(async[[:space:]]+)?function mutate'; then
                continue
            fi
            # Allow when the SPECIFIC matched line is inside a string literal
            # or comment AND that line co-occurs with NEVER-language on the
            # SAME line. This is the canonical "doctor will NEVER do X"
            # negative-space spec in robot-docs / help text.
            matched_line=$(sed -n "${lineno}p" "$file")
            in_quoted_or_comment=false
            case "$matched_line" in
                # Double-quoted string, single-quoted string,
                # `#`-comment (Python/Bash/Ruby), or `//`-comment (C/Rust/Go/TS).
                *\"*\"*|*\'*\'*|*\#*|*//*) in_quoted_or_comment=true ;;
            esac
            mentions_never=false
            case "$matched_line" in
                *will\ NEVER*|*would\ NEVER*|*WILL\ NEVER*|*WOULD\ NEVER*) mentions_never=true ;;
                *NEVER\ do*|*forbidden\ by*|*never\ used*|*never\ runs*|*never\ touches*) mentions_never=true ;;
            esac
            if [ "$in_quoted_or_comment" = true ] && [ "$mentions_never" = true ]; then
                continue
            fi
            report "$file:$lineno matches forbidden pattern: $pat"
        done < <(grep -rnHE "$pat" "$path" 2>/dev/null || true)
        # NOTE: -H forces grep to always print the filename. Without it,
        # grep on a single-file argument outputs `lineno:content` (no path),
        # which would silently corrupt the file/lineno parsing above.
    done
done

if [ $violations -gt 0 ]; then
    echo "$violations violation(s); fix or add allow-list entries." >&2
    exit 1
fi

echo "validate-doctor.sh: clean" >&2
exit 0
