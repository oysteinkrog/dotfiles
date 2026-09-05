#!/usr/bin/env bash
# install-referenced-skills.sh — Bulk-install missing skills via jsm.
#
# Reads <workspace>/phase0_skill_inventory.json and runs `jsm install <name>`
# for each skill marked status=missing. Skips if jsm isn't installed or the
# user isn't authenticated.

set -euo pipefail

WORKSPACE_DIR="${1:-.stash_janitor_workspace}"
INVENTORY="$WORKSPACE_DIR/phase0_skill_inventory.json"

if [[ ! -f "$INVENTORY" ]]; then
  echo "ERROR: inventory not found at $INVENTORY" >&2
  echo "Run check-skills.sh first." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found in PATH; this script needs jq to parse the JSON inventory." >&2
  echo "Install jq, or run \`jsm install <skill>\` manually for each missing skill" >&2
  echo "(see $INVENTORY for the list)." >&2
  exit 1
fi

JSM_AVAILABLE=$(jq -r '.jsm_available' "$INVENTORY")
JSM_AUTHED=$(jq -r '.jsm_authenticated' "$INVENTORY")

if [[ "$JSM_AVAILABLE" != "true" ]]; then
  echo "jsm not installed; skipping installation."
  echo "See https://jeffreys-skills.md to install."
  exit 0
fi
if [[ "$JSM_AUTHED" != "true" ]]; then
  echo "jsm installed but not authenticated; run \`jsm login\` first."
  exit 0
fi

MISSING=$(jq -r '.skills[] | select(.status == "missing") | .name' "$INVENTORY")
if [[ -z "$MISSING" ]]; then
  echo "Nothing missing."
  exit 0
fi

echo "Installing missing skills via jsm:"
for skill in $MISSING; do
  echo "  jsm install $skill"
  if jsm install "$skill"; then
    echo "    ✓ $skill"
  else
    echo "    ✗ $skill (continuing)" >&2
  fi
done

echo
echo "Re-running check-skills.sh to refresh inventory..."
"$(dirname "$0")/check-skills.sh" "$WORKSPACE_DIR"
