#!/usr/bin/env bash
# ast-grep-ub-patterns.sh — apply every pattern in scripts/patterns/ against
# the source tree.
#
# Usage: ast-grep-ub-patterns.sh <source-dir> [bucket]
#
# If bucket is given, only runs patterns/<bucket>-*.yml. Otherwise runs all.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 1 ]]; then
    echo "Usage: ast-grep-ub-patterns.sh <source-dir> [bucket]" >&2
    exit 2
fi

SOURCE="$1"
BUCKET="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERN_DIR="$SCRIPT_DIR/patterns"

if ! command -v ast-grep >/dev/null 2>&1; then
    echo "ast-grep not installed. cargo install ast-grep" >&2
    exit 127
fi

if [[ ! -d "$PATTERN_DIR" ]]; then
    echo "Pattern dir not found: $PATTERN_DIR" >&2
    exit 1
fi

if [[ -n "$BUCKET" ]]; then
    mapfile -t PATTERNS < <(ls "$PATTERN_DIR"/"$BUCKET"-*.yml 2>/dev/null || true)
else
    mapfile -t PATTERNS < <(ls "$PATTERN_DIR"/*.yml 2>/dev/null || true)
fi

if [[ ${#PATTERNS[@]} -eq 0 ]]; then
    echo "No patterns found." >&2
    exit 1
fi

for p in "${PATTERNS[@]}"; do
    name=$(basename "$p" .yml)
    echo "=== $name ==="
    ast-grep scan --rule "$p" "$SOURCE" || true
    echo
done
