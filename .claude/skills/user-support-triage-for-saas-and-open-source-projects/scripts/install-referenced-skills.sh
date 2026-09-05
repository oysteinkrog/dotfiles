#!/usr/bin/env bash
# install-referenced-skills.sh — bulk install missing skills via jsm
#
# Usage:  install-referenced-skills.sh <workspace-dir>
#
# Reads <workspace>/skill_inventory.json (written by check-skills.sh) and
# runs `jsm install <name>` for each skill in `.skills[] where status="missing"`.
# Idempotent (jsm skips up-to-date skills).

set -euo pipefail

WS="${1:-.}"
[[ -d "$WS" ]] || { echo "workspace directory not found: $WS" >&2; exit 2; }
WS="$(cd "$WS" && pwd)"
INV="$WS/skill_inventory.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f "$INV" ]] || { echo "no inventory at $INV — run check-skills.sh first" >&2; exit 2; }
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read $INV" >&2
  exit 2
fi

# Read jsm state from inventory
jsm_avail=$(jq -r '.jsm_available // false' "$INV")
jsm_auth=$(jq -r '.jsm_authenticated // false' "$INV")
tier=$(jq -r '.subscription_tier // "unknown"' "$INV")

if [[ "$jsm_avail" != "true" ]]; then
  cat <<'EOF' >&2
jsm not installed.

Install jsm:
  Linux/macOS:  curl -fsSL https://jeffreys-skills.md/install.sh | bash
  Windows:      irm https://jeffreys-skills.md/install.ps1 | iex

Then:  jsm login (or: jsm auth, for headless API key)

Premium skills require an active jeffreys-skills.md subscription ($20/month).
Falling back to inline guidance — onboarding will continue without these skills.
EOF
  exit 0
fi

if [[ "$jsm_auth" != "true" ]]; then
  cat <<'EOF' >&2
jsm not authenticated.

Authenticate:
  jsm login              # browser OAuth (workstation)
  jsm login --print-url  # cross-device (forward URL to a browser)
  jsm auth               # API key (headless / CI)

Then re-run this script.
EOF
  exit 0
fi

if [[ "$tier" != "active" ]]; then
  cat <<EOF >&2
jsm authenticated, but subscription tier is "$tier".

Premium skills (codebase-archaeology, multi-model-triangulation, etc.)
require an active subscription. Subscribe at https://jeffreys-skills.md
(\$20/month).

Continuing — only free/public skills will install successfully.
EOF
fi

# Read missing skills, REQUIRED first (de-slopify and any other future requireds).
# Required skills are installed before optional ones because triage cannot
# safely send customer-facing replies without them (see DE-SLOPIFY-INTEGRATION.md).
mapfile -t MISSING_REQUIRED < <(jq -r '.skills[] | select(.status == "missing" and .required == true) | .name' "$INV")
mapfile -t MISSING_OPTIONAL < <(jq -r '.skills[] | select(.status == "missing" and (.required // false) == false) | .name' "$INV")
MISSING=("${MISSING_REQUIRED[@]}" "${MISSING_OPTIONAL[@]}")

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "→ no missing skills"
  exit 0
fi

if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
  echo "→ ${#MISSING_REQUIRED[@]} REQUIRED skill(s) missing: ${MISSING_REQUIRED[*]}"
  echo "  These are mandatory for safe customer-facing sends; installing first."
  echo
fi
echo "→ ${#MISSING[@]} total missing skill(s); attempting jsm install for each"
echo

failed=()
failed_required=()
for s in "${MISSING[@]}"; do
  is_req="false"
  for r in "${MISSING_REQUIRED[@]}"; do
    [[ "$r" == "$s" ]] && is_req="true" && break
  done
  if [[ "$is_req" == "true" ]]; then
    echo "→ jsm install $s  (REQUIRED)"
  else
    echo "→ jsm install $s"
  fi
  if jsm install "$s" 2>/dev/null; then
    echo "  ✓ installed: $s"
  else
    echo "  ✗ failed: $s"
    failed+=("$s")
    [[ "$is_req" == "true" ]] && failed_required+=("$s")
  fi
done

echo
if [[ ${#failed_required[@]} -gt 0 ]]; then
  cat >&2 <<EOF

╔══════════════════════════════════════════════════════════════════════════╗
║  ⚠  REQUIRED SKILL(S) FAILED TO INSTALL: ${failed_required[*]}
║                                                                          ║
║  The triage skill applies these to every customer-facing reply.          ║
║  Without them, the inline fallback (manual AI-tell removal list in       ║
║  references/VOICE-CALIBRATION.md) MUST be used by the agent on every     ║
║  draft before owner approval. Skipping the check is a Confirmation-Rule  ║
║  violation.                                                              ║
║                                                                          ║
║  Likely causes: subscription required, network error, skill not in       ║
║  the jsm catalog. See $WS/missing_skills.md for specifics.               ║
║                                                                          ║
║  Fix: subscribe at https://jeffreys-skills.md (\$20/mo) and re-run, or    ║
║  proceed with the inline fallback (slower per-draft, same protection).   ║
╚══════════════════════════════════════════════════════════════════════════╝

EOF
fi
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "WARN: ${#failed[@]} skill(s) failed: ${failed[*]}" >&2
  echo "Optional ones use inline fallbacks. See $WS/missing_skills.md for details." >&2
fi

# Re-run check-skills.sh to refresh the inventory
echo
echo "→ refreshing inventory"
"$SCRIPT_DIR/check-skills.sh" "$WS" >/dev/null
echo "→ done"
