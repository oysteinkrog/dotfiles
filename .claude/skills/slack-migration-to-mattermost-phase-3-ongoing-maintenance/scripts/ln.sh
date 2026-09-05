#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "ERROR: scripts/ln.sh was an accidental filename." >&2
echo "Use ${SCRIPT_DIR}/rotate-tokens.sh instead." >&2
exit 2
