#!/usr/bin/env bash
# scaffold-ticketing.sh — auto-install ticketing skill + co-deps and emit handoff
#
# Usage:  scaffold-ticketing.sh <workspace-dir>
#
# Triggered when surface = `none-yet` AND the owner accepts the offer to
# scaffold an in-app ticketing system. Idempotent: jsm install is a no-op
# when the skill is already on disk.
#
# Behavior:
#   1. Refresh skill_inventory.json via check-skills.sh.
#   2. jsm install user-support-ticketing-system-for-saas + co-deps
#      (supabase, admin-page-for-nextjs-sites, stripe-checkout).
#   3. Re-run check-skills.sh to confirm install state.
#   4. Write triage-handoff.md with the project context the ticketing
#      skill needs to begin (framework, language, auth, base URL, missing
#      tables) — read from <workspace>/_detection.json if present.
#   5. Emit `SCAFFOLD-TICKETING-READY <handoff-path>` to stdout. The agent
#      uses this single line to know it should now invoke the ticketing
#      skill. The agent must still ✓ CONFIRM before any code is written.
#
# Exit:
#   0  — install attempted (success or graceful jsm-absent fallback) and
#        handoff written. Agent should proceed to invoke ticketing skill.
#   2  — invocation error (workspace missing, jq missing, etc.). Agent
#        should fall back to the inline ticketing-design template.

set -euo pipefail

WS="${1:-}"
if [[ -z "$WS" ]]; then
  echo "usage: scaffold-ticketing.sh <workspace-dir>" >&2
  exit 2
fi
[[ -d "$WS" ]] || { echo "workspace directory not found: $WS" >&2; exit 2; }
WS="$(cd "$WS" && pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

# Co-deps the ticketing scaffold needs in addition to the ticketing skill itself.
# Each is also in the parent skill's REFERENCED list, so they're typically
# already on disk after session-start bootstrap. This pass guarantees them.
TICKETING_SKILLS=(
  user-support-ticketing-system-for-saas
  supabase
  admin-page-for-nextjs-sites
  stripe-checkout
)

echo "→ refreshing skill inventory"
"$SCRIPT_DIR/check-skills.sh" "$WS" >/dev/null

INV="$WS/skill_inventory.json"
[[ -f "$INV" ]] || { echo "no inventory at $INV" >&2; exit 2; }

jsm_avail=$(jq -r '.jsm_available // false' "$INV")
jsm_auth=$(jq -r '.jsm_authenticated // false' "$INV")

# Targeted install pass. Always best-effort: if jsm is missing/unauthenticated,
# we log to missing_skills.md and continue — the inline fallback path remains
# the floor.
if [[ "$jsm_avail" == "true" && "$jsm_auth" == "true" ]]; then
  echo "→ ensuring ticketing skill + co-deps are installed"
  for s in "${TICKETING_SKILLS[@]}"; do
    if jq -e --arg n "$s" '.skills[] | select(.name == $n and .status == "present")' "$INV" >/dev/null 2>&1; then
      echo "  ✓ already installed: $s"
    else
      echo "  → jsm install $s"
      if jsm install "$s" 2>/dev/null; then
        echo "    ✓ installed: $s"
      else
        echo "    ✗ install failed: $s (will fall back to inline guidance)"
      fi
    fi
  done

  echo "→ refreshing inventory after install"
  "$SCRIPT_DIR/check-skills.sh" "$WS" >/dev/null
else
  cat >&2 <<'EOF'

jsm not available or not authenticated — skipping targeted install.
The agent should fall back to the inline ticketing-design template
(see /user-support-ticketing-system-for-saas/SKILL.md for the schema +
SLA engine outline, or invoke the skill directly if it's been installed
through a non-jsm path).

EOF
fi

# Build the handoff file. Read project context from _detection.json (written
# by BOOTSTRAP) if present; otherwise use placeholder values.
HANDOFF="$WS/triage-handoff.md"
DETECT="$WS/_detection.json"
get_field() {
  local key="$1" default="$2"
  if [[ -f "$DETECT" ]]; then
    # Tolerate corrupt JSON / missing field / type mismatch — fall back to default
    # rather than dying under set -e.
    jq -r --arg d "$default" ".${key} // \$d" "$DETECT" 2>/dev/null || printf '%s' "$default"
  else
    printf '%s' "$default"
  fi
}

framework=$(get_field 'framework' 'unknown')
language=$(get_field 'language' 'unknown')
auth_strategy=$(get_field 'auth_strategy' 'unknown')
base_url=$(get_field 'base_url' 'unknown')
github_repo=$(get_field 'github_repo' 'unknown')
outbound_email=$(get_field 'outbound_email' 'unknown')

# Resolve email hint so the handoff template reads cleanly when the field is unset.
if [[ "$outbound_email" == "unknown" ]]; then
  email_hint='not detected — pick best-fit (Resend recommended for Next.js/Vercel; SES/Postmark/Sendgrid otherwise)'
else
  email_hint="$outbound_email (already wired in the project — reuse)"
fi

# Record post-run install status of the ticketing skill itself, so the handoff
# is self-contained: a downstream agent reading it knows whether to invoke the
# skill or fall back to inline guidance, without needing the script's stderr.
ticketing_status="unknown"
if [[ -f "$INV" ]] && jq -e --arg n "user-support-ticketing-system-for-saas" \
     '.skills[] | select(.name == $n and .status == "present")' "$INV" >/dev/null 2>&1; then
  ticketing_status="present"
else
  ticketing_status="missing"
fi
if [[ "$ticketing_status" == "present" ]]; then
  invoke_guidance='Invoke `/user-support-ticketing-system-for-saas` with this handoff as input. Each scaffold step gets its own ✓ CONFIRM.'
else
  invoke_guidance='**Fall back to the inline ticketing-design template** in `/user-support-ticketing-system-for-saas/SKILL.md` (schema + SLA engine outline). Do not attempt to invoke the skill — it is not installed locally and the invocation would fail.'
fi

cat > "$HANDOFF" <<EOF
# Triage → Ticketing Scaffold Handoff

Generated by \`scaffold-ticketing.sh\` after the owner accepted the
\`surface = none-yet\` scaffold offer. Read this file as the project-context
input for the scaffold work — see the **Ticketing Skill Install Status**
section below for whether to invoke \`/user-support-ticketing-system-for-saas\`
or apply the inline fallback.

## Detected Project Context

| Field | Value |
|---|---|
| framework | \`$framework\` |
| language | \`$language\` |
| auth_strategy | \`$auth_strategy\` |
| outbound_email | \`$outbound_email\` |
| base_url | \`$base_url\` |
| github_repo | \`$github_repo\` |

## Required Scaffold Surface

The scaffold must produce (gated by per-step \`✓ CONFIRM\`, regardless of whether
the canonical skill is invoked or the inline fallback is applied):

- DB schema (\`tickets\`, \`ticket_messages\`, \`ticket_audit\`)
- SLA engine (response/resolution targets per priority + tier)
- Public APIs (\`POST /api/support/tickets\`, \`GET /api/support/tickets/:id\`)
- Admin queue UI (filter, claim, reply, reassign, close)
- User inbox UI (list, detail, reply)
- Outbound email wiring: $email_hint
- Cron for SLA breach detection + escalation
- Audit log table + admin view

## Ticketing Skill Install Status

\`user-support-ticketing-system-for-saas\`: **$ticketing_status**

$invoke_guidance

## Confirmation Rule

This handoff was preceded by **one** \`✓ CONFIRM\` (offer-accepted).
Each scaffold step (DB migration, API route, UI surface, email wiring,
cron) needs its **own** \`✓ CONFIRM\` before any code lands —
whether the canonical skill is doing the work or you are applying
the inline fallback. No batch-writes without per-step approval.

## Mandatory De-Slopify

Any customer-facing copy generated during scaffolding (admin queue
empty-state copy, user inbox onboarding copy, outbound email templates)
must pass \`/de-slopify\` before being written to the codebase.

## On Failure

If the ticketing skill cannot complete (subscription required, API
keys absent, etc.), it must record the partial state in
\`<workspace>/scaffold-status.md\` and return control to triage so the
owner can continue with the manual-only cadence on existing channels.
EOF

echo
echo "SCAFFOLD-TICKETING-READY $HANDOFF"
echo "TICKETING-SKILL-STATUS $ticketing_status"
echo
if [[ "$ticketing_status" == "present" ]]; then
  echo "→ Next step: invoke /user-support-ticketing-system-for-saas with the"
  echo "  handoff file above as input context. Confirmation Rule applies per step."
else
  echo "→ Next step: ticketing skill is NOT installed locally. Read the handoff"
  echo "  for project context, then fall back to the inline ticketing-design"
  echo "  template in /user-support-ticketing-system-for-saas/SKILL.md."
fi

exit 0
