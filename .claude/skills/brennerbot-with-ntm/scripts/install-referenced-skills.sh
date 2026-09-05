#!/usr/bin/env bash
# install-referenced-skills.sh — Bulk-install missing helper skills via jsm.
#
# Reads phase0_skill_inventory.json from the workspace; for each skill marked
# {"installed": false}, runs `jsm install <name>`. Prints summary at end.

set -uo pipefail

WORKSPACE="${1:-.}"
INVENTORY="$WORKSPACE/.brenner_workspace/phase0_skill_inventory.json"

if [ ! -f "$INVENTORY" ]; then
  echo "Error: $INVENTORY not found. Run check-skills.sh first." >&2
  exit 1
fi

# Verify jsm
if ! command -v jsm >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Error: jsm not installed. Install via:
  curl -fsSL https://jeffreys-skills.md/install.sh | bash
  jsm login

Then re-run this script.
EOF
  exit 1
fi

if ! jsm whoami 2>/dev/null | grep -q '@'; then
  echo "Error: jsm not authenticated. Run: jsm login" >&2
  exit 1
fi

# Find missing skills
MISSING=$(jq -r '.fallbacks_active[]' "$INVENTORY" 2>/dev/null || true)

if [ -z "$MISSING" ]; then
  echo "All referenced skills installed; nothing to do."
  exit 0
fi

INSTALLED=""
FAILED=""

for skill in $MISSING; do
  echo "Installing: $skill ..."
  if jsm install "$skill" 2>&1; then
    INSTALLED="$INSTALLED $skill"
  else
    FAILED="$FAILED $skill"
  fi
done

# Summary
echo ""
echo "=== install-referenced-skills.sh complete ==="
[ -n "$INSTALLED" ] && echo "Installed:$INSTALLED"
[ -n "$FAILED" ] && echo "Failed:$FAILED" >&2

# Re-run check-skills.sh to refresh inventory. The previous form sent stdout
# to /dev/null, which discarded the JSON inventory the script emits — leaving
# phase0_skill_inventory.json stale and the "fallbacks_active" array stuck on
# whatever was there before install. Mirror bootstrap-session.sh's redirect so
# subsequent phase-readiness checks see the up-to-date inventory.
"$(dirname "$0")/check-skills.sh" "$WORKSPACE" \
  > "$WORKSPACE/.brenner_workspace/phase0_skill_inventory.json" 2>/dev/null || true

[ -z "$FAILED" ]
