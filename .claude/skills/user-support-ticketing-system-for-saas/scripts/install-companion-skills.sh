#!/usr/bin/env bash
# install-companion-skills.sh — install every missing companion skill via jsm.
#
# Reads skill_inventory.json (from check-companion-skills.sh) and runs
# `jsm install <name>` for each entry whose status is "missing".
#
# /de-slopify is a HARD requirement: if it's missing AND can't be installed,
# this script exits non-zero so the build is blocked. Other skills degrade
# gracefully (logged to skill_inventory_install.md, build continues).
#
# Usage:
#   install-companion-skills.sh [<workspace-dir>]

set -uo pipefail

WORKSPACE="${1:-.support_ticketing_workspace}"
INV="$WORKSPACE/skill_inventory.json"
LOG="$WORKSPACE/skill_inventory_install.md"

if [[ ! -f "$INV" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "skill_inventory.json not found; running check-companion-skills.sh first..."
  if ! "$SCRIPT_DIR/check-companion-skills.sh" "$WORKSPACE" >/dev/null; then
    echo "check-companion-skills.sh failed; cannot proceed." >&2
    exit 2
  fi
  if [[ ! -f "$INV" ]]; then
    echo "check-companion-skills.sh ran but did not produce $INV; cannot proceed." >&2
    exit 2
  fi
fi

if ! command -v jsm >/dev/null 2>&1; then
  cat <<'EOF' >&2
jsm not installed; cannot auto-install companion skills.

Install jsm with:
  curl -fsSL https://jeffreys-skills.md/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
  jsm login

Then re-run this script. Without /de-slopify the Hard Invariant
("every customer-visible reply runs through /de-slopify") cannot be
enforced — fix this before shipping.
EOF
  exit 2
fi

# Authentication check (loose — `jsm whoami` text rather than exit code)
if ! jsm_whoami=$(jsm whoami 2>&1) || echo "$jsm_whoami" | grep -qi 'not logged in'; then
  cat <<'EOF' >&2
jsm is installed but not authenticated. Run:

  jsm login

(Browser OAuth via Google. For headless / SSH sessions see
references/SKILL-INSTALLATION.md § Authenticate.)

Aborting install — /de-slopify cannot be auto-installed without auth.
EOF
  exit 2
fi

# Extract missing skills (and remember their requirement level) without jq
missing_required=$(grep -oE '"name": "[^"]+", "status": "missing", "requirement": "required"' "$INV" \
  | sed -E 's/.*"name": "([^"]+)".*/\1/' || true)
missing_optional=$(grep -oE '"name": "[^"]+", "status": "missing", "requirement": "optional"' "$INV" \
  | sed -E 's/.*"name": "([^"]+)".*/\1/' || true)

if [[ -z "$missing_required" && -z "$missing_optional" ]]; then
  echo "✅ All companion skills already installed. Nothing to do."
  exit 0
fi

: > "$LOG"
{
  echo "# Companion-skill install log ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo
  echo "Attempting \`jsm install\` for each missing skill:"
  echo
} >> "$LOG"

required_failed=0
installed=0
failed=0
# Reset IFS to default whitespace; downstream loops rely on word-splitting
# the newline-separated grep output via unquoted expansion.
IFS=$' \t\n'
for skill in $missing_required $missing_optional; do
  is_required=0
  for r in $missing_required; do
    [[ "$r" == "$skill" ]] && is_required=1 && break
  done
  label=$([[ $is_required -eq 1 ]] && echo "REQUIRED" || echo "optional")
  printf '  jsm install %-60s [%s] ... ' "$skill" "$label"

  # </dev/null protects against jsm prompting interactively in scripted use.
  if out=$(jsm install "$skill" </dev/null 2>&1); then
    echo "ok"
    installed=$((installed+1))
    echo "- \`$skill\` ($label) — **installed via jsm**" >> "$LOG"
  else
    if echo "$out" | grep -qi 'subscription'; then
      reason='subscription required (paid jeffreys-skills.md account needed)'
    elif echo "$out" | grep -qi 'not found'; then
      reason='not in jsm catalog'
    else
      reason="$(echo "$out" | head -2 | tr '\n' ' ')"
    fi
    echo "FAILED ($reason)"
    failed=$((failed+1))
    echo "- \`$skill\` ($label) — **not installed**: $reason" >> "$LOG"
    if [[ $is_required -eq 1 ]]; then
      required_failed=$((required_failed+1))
    fi
  fi
done

{
  echo
  echo "## Summary"
  echo
  echo "- installed: $installed"
  echo "- failed:    $failed"
  echo "- required failures: $required_failed"
  echo
  if (( required_failed > 0 )); then
    echo "⛔ \`/de-slopify\` failed to install. The Hard Invariant"
    echo "   '/de-slopify on every customer-visible reply' cannot be enforced."
    echo "   Subscribe at https://jeffreys-skills.md and re-run."
  fi
} >> "$LOG"

echo
echo "logged to $LOG"
echo "installed=$installed failed=$failed required_failed=$required_failed"

if (( required_failed > 0 )); then
  exit 1
fi
exit 0
