#!/usr/bin/env bash
# shape-sweep.sh — given a confirmed bug at one site, find every other site
# with the same syntactic/lexical/semantic shape so the remediation can be
# applied uniformly. See SHAPE-SWEEP.md for the methodology.
#
# Usage:
#   shape-sweep.sh <source-dir> <pattern> [--tool=rg|ast-grep|semgrep]
#                                         [--output <file>]
#
# Tools dispatch:
#   --tool=rg        — lexical regex (default for `*.[Test patterns containing regex chars]`)
#   --tool=ast-grep  — syntactic tree pattern (the default; needs Rust grammar)
#   --tool=semgrep   — semantic pattern (caller supplies a semgrep rule path)
#
# Output:
#   stdout: file:line  matching content (one per line)
#   exit 0 if ≥1 match; exit 1 if no matches (so it composes with `|| true`)
#   exit 2 on usage error / missing tool
#
# Example:
#   shape-sweep.sh /src 'as_bytes\(\)\[' --tool=rg
#   shape-sweep.sh /src '$E as *const $T as *mut $T' --tool=ast-grep
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 2 ]]; then
    cat <<EOF >&2
Usage: shape-sweep.sh <source-dir> <pattern> [--tool=rg|ast-grep|semgrep] [--output <file>]

Examples:
  shape-sweep.sh /repo 'as_bytes\(\)\[' --tool=rg
  shape-sweep.sh /repo '\$E as *const \$T as *mut \$T' --tool=ast-grep
  shape-sweep.sh /repo /path/to/rule.yml --tool=semgrep
EOF
    exit 2
fi

SOURCE="$1"
PATTERN="$2"
shift 2

TOOL="ast-grep"
OUTPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tool=*)   TOOL="${1#--tool=}" ;;
        --tool)     shift; TOOL="$1" ;;
        --output)   shift; OUTPUT="$1" ;;
        --output=*) OUTPUT="${1#--output=}" ;;
        *)          echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

if [[ ! -d "$SOURCE" ]]; then
    echo "Source dir not found: $SOURCE" >&2
    exit 2
fi

# Dispatch on tool. Each tool's own exit code is propagated.
run_sweep() {
    case "$TOOL" in
        rg)
            if ! command -v rg >/dev/null 2>&1; then
                echo "rg (ripgrep) not installed; falling back to grep -rn" >&2
                grep -rn --include='*.rs' -E "$PATTERN" "$SOURCE" || return $?
            else
                rg -n --type rust "$PATTERN" "$SOURCE" || return $?
            fi
            ;;
        ast-grep)
            if ! command -v ast-grep >/dev/null 2>&1; then
                echo "ast-grep not installed (try: cargo install ast-grep)" >&2
                exit 2
            fi
            # --json is good for downstream tooling but plain output reads cleaner;
            # use --heading-style=none to suppress group headers.
            ast-grep run -l Rust -p "$PATTERN" "$SOURCE" || return $?
            ;;
        semgrep)
            if ! command -v semgrep >/dev/null 2>&1; then
                echo "semgrep not installed (try: pip install semgrep)" >&2
                exit 2
            fi
            semgrep --config="$PATTERN" "$SOURCE" || return $?
            ;;
        *)
            echo "Unknown tool: $TOOL (expected rg|ast-grep|semgrep)" >&2
            exit 2
            ;;
    esac
}

# Capture output so we can tee to --output AND count hits for exit code.
TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT

if run_sweep > "$TMP_OUT" 2>&1; then
    :
fi

HITS=$(wc -l < "$TMP_OUT" | tr -d ' ')

if [[ -n "$OUTPUT" ]]; then
    cp "$TMP_OUT" "$OUTPUT"
    echo "Wrote $HITS line(s) to $OUTPUT" >&2
fi

cat "$TMP_OUT"

if [[ "$HITS" -eq 0 ]]; then
    echo "(no matches)" >&2
    exit 1
fi
exit 0
