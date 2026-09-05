#!/usr/bin/env bash
# Resolve the repo root. Always operate from there.
set -euo pipefail
project="${1:-.}"
git -C "$project" rev-parse --show-toplevel 2>/dev/null || {
    echo "ERROR: $project is not a git work tree" >&2
    exit 1
}
