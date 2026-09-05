#!/usr/bin/env bash
# install-referenced-skills.sh — Bulk-install missing skills via jsm.
#
# Usage: ./scripts/install-referenced-skills.sh <workspace-dir>
#
# Reads <workspace-dir>/phase0_skill_inventory.json (produced by check-skills.sh),
# picks the missing list, runs `jsm install <name>` for each. Failures logged
# but do not abort.

set -uo pipefail

WORKSPACE_DIR="${1:-.billing_workspace}"
INVENTORY="$WORKSPACE_DIR/phase0_skill_inventory.json"

if [[ ! -f "$INVENTORY" ]]; then
  echo "Inventory file missing: $INVENTORY" >&2
  echo "Run scripts/check-skills.sh first." >&2
  exit 1
fi

if ! command -v jsm >/dev/null 2>&1; then
  echo "jsm is not installed. Install via:" >&2
  echo "  curl -fsSL https://jeffreys-skills.md/install.sh | bash" >&2
  exit 1
fi

if ! jsm whoami >/dev/null 2>&1; then
  echo "jsm is installed but not authenticated. Run:" >&2
  echo "  jsm login" >&2
  exit 1
fi

# Parse missing skills (jq required for parsing JSON)
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for parsing the inventory. Install jq and retry." >&2
  exit 1
fi

MISSING=$(jq -r '.missing[]' "$INVENTORY")

if [[ -z "$MISSING" ]]; then
  echo "No missing skills to install."
  exit 0
fi

echo "Will attempt to install:"
echo "$MISSING" | sed 's/^/  - /'
echo

INSTALL_LOG="$WORKSPACE_DIR/phase0_install_log.txt"
> "$INSTALL_LOG"

while IFS= read -r skill; do
  [[ -z "$skill" ]] && continue
  echo "==> Installing $skill ..."
  if jsm install "$skill" 2>&1 | tee -a "$INSTALL_LOG"; then
    echo "    OK"
  else
    echo "    FAILED (continuing)"
  fi
  echo
done <<< "$MISSING"

echo "Done. Log written to $INSTALL_LOG"
echo "Re-run scripts/check-skills.sh to refresh the inventory."
