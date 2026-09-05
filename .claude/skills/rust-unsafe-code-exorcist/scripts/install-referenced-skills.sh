#!/usr/bin/env bash
# install-referenced-skills.sh — bulk-install missing skills via jsm
# Usage: ./install-referenced-skills.sh <audit-dir>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:-.}"
AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ROOT")
INVENTORY="$AUDIT_DIR/phase0_skill_inventory.json"

if [ ! -f "$INVENTORY" ]; then
  echo "error: $INVENTORY not found. Run check-skills.sh first." >&2
  exit 1
fi

if ! command -v jsm >/dev/null 2>&1; then
  echo "error: jsm not installed. See SKILL-FALLBACKS.md for inline fallbacks." >&2
  exit 1
fi

if ! jsm whoami >/dev/null 2>&1; then
  echo "error: jsm not authenticated. Run 'jsm login' first." >&2
  exit 1
fi

MISSING=$(jq -r '.skills[] | select(.state == "missing") | .name' "$INVENTORY")
if [ -z "$MISSING" ]; then
  echo "All referenced skills are installed."
  exit 0
fi

echo "Installing missing skills via jsm:"
for s in $MISSING; do
  echo "  - $s"
done
echo

if [ -t 0 ]; then
  if ! read -r -p "Proceed with installation? [y/N] " ANS; then
    echo "aborted"
    exit 0
  fi
elif { true </dev/tty; } 2>/dev/null; then
  if ! read -r -p "Proceed with installation? [y/N] " ANS </dev/tty; then
    echo "aborted"
    exit 0
  fi
else
  echo "no interactive tty available; aborted"
  exit 0
fi
case "$ANS" in
  y|Y|yes|Yes) ;;
  *) echo "aborted"; exit 0 ;;
esac

for s in $MISSING; do
  echo "==> jsm install $s"
  jsm install "$s" || echo "failed: $s"
done

# Re-run check
"$SCRIPT_DIR/check-skills.sh" "$AUDIT_DIR"
