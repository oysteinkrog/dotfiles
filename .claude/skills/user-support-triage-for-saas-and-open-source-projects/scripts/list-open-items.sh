#!/usr/bin/env bash
# list-open-items.sh — surface-aware, read-only open-item dispatcher.
#
# Usage:
#   list-open-items.sh /path/to/project
#
# Output: support-adapter-v1 JSON array. This script never posts replies,
# changes ticket state, or mutates the target project.

set -euo pipefail

PROJECT="${1:-}"
if [[ -z "$PROJECT" || ! -d "$PROJECT" ]]; then
  echo "usage: list-open-items.sh <project-path>" >&2
  exit 2
fi
PROJECT="$(cd "$PROJECT" && pwd)"

SUPPORT_DIR="$PROJECT/.claude/support-triage"
DET="$SUPPORT_DIR/_detection.json"
PROJECT_LIST="$SUPPORT_DIR/scripts/list-open.sh"

if [[ ! -f "$DET" ]]; then
  echo "missing $DET — run detect-support-surface.sh during onboarding first" >&2
  exit 2
fi

if [[ -x "$PROJECT_LIST" ]]; then
  exec "$PROJECT_LIST" "$PROJECT"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read $DET" >&2
  exit 2
fi

mapfile -t SURFACES < <(jq -r '.surfaces[]?' "$DET")
GITHUB_REPO="$(jq -r '.github_repo // "null"' "$DET")"
BASE_URL="$(jq -r '.base_url // "null"' "$DET")"
PROVIDER="$(jq -r '.third_party_provider // "null"' "$DET")"

objects=()

emit_note() {
  local surface="$1" note="$2"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  objects+=("$(jq -nc \
    --arg surface "$surface" \
    --arg note "$note" \
    --arg now "$now" \
    '{
      adapter_version: "support-adapter-v1",
      surface: $surface,
      provider: "project-adapter",
      id: ("adapter-needed-" + $surface),
      stable_url: null,
      public_url: null,
      subject: "Project-specific support adapter needed",
      category: "adapter",
      status: "adapter_error",
      priority: "unknown",
      created_at: $now,
      updated_at: $now,
      last_customer_message_at: null,
      last_support_message_at: null,
      age_hours: 0,
      customer: {},
      sla: {status: "unknown"},
      messages: [],
      labels: ["adapter-needed"],
      attachments: [],
      safe_actions: [],
      unsafe_actions: [],
      error: {kind: "needs_project_adapter", message: $note},
      evidence: [{kind: "detection", source: "_detection.json", checked_at: $now}]
    }')")
}

for surface in "${SURFACES[@]}"; do
  case "$surface" in
    github-only)
      if [[ "$GITHUB_REPO" != "null" && "$GITHUB_REPO" != "" ]] && command -v gh >/dev/null 2>&1; then
        issues_json="$(gh issue list -R "$GITHUB_REPO" --state open --json number,title,createdAt,updatedAt,labels,author,url 2>/dev/null || printf '[]')"
        prs_json="$(gh pr list -R "$GITHUB_REPO" --state open --json number,title,createdAt,updatedAt,author,url 2>/dev/null || printf '[]')"
        while IFS= read -r item; do
          objects+=("$item")
        done < <(jq -c --arg surface "$surface" --arg repo "$GITHUB_REPO" '
          .[] | {
            adapter_version: "support-adapter-v1",
            surface: $surface,
            provider: "github",
            id: ("issue-" + (.number|tostring)),
            stable_url: .url,
            public_url: .url,
            subject: .title,
            category: "github_issue",
            status: "open",
            priority: "unknown",
            created_at: .createdAt,
            updated_at: (.updatedAt // .createdAt),
            last_customer_message_at: .createdAt,
            last_support_message_at: null,
            age_hours: (((now - (.createdAt | fromdateiso8601)) / 3600) * 100 | round / 100),
            customer: {
              id: (.author.login // null),
              display: (.author.login // "unknown"),
              email: null,
              handle: (.author.login // null),
              tier: "unknown",
              org: null
            },
            sla: {status: "unknown"},
            messages: [{
              id: ("issue-" + (.number|tostring) + "-summary"),
              author_type: "customer",
              author_display: (.author.login // "unknown"),
              created_at: .createdAt,
              body_preview: .title
            }],
            labels: [(.labels[]?.name // empty)],
            attachments: [],
            safe_actions: ["post_internal_note"],
            unsafe_actions: ["public_close_with_comment"],
            evidence: [{kind: "provider", source: ("gh issue list -R " + $repo), checked_at: (now | todateiso8601)}]
          }' <<<"$issues_json")
        while IFS= read -r item; do
          objects+=("$item")
        done < <(jq -c --arg surface "$surface" --arg repo "$GITHUB_REPO" '
          .[] | {
            adapter_version: "support-adapter-v1",
            surface: $surface,
            provider: "github",
            id: ("pr-" + (.number|tostring)),
            stable_url: .url,
            public_url: .url,
            subject: .title,
            category: "github_pr",
            status: "open",
            priority: "unknown",
            created_at: .createdAt,
            updated_at: (.updatedAt // .createdAt),
            last_customer_message_at: .createdAt,
            last_support_message_at: null,
            age_hours: (((now - (.createdAt | fromdateiso8601)) / 3600) * 100 | round / 100),
            customer: {
              id: (.author.login // null),
              display: (.author.login // "unknown"),
              email: null,
              handle: (.author.login // null),
              tier: "unknown",
              org: null
            },
            sla: {status: "unknown"},
            messages: [{
              id: ("pr-" + (.number|tostring) + "-summary"),
              author_type: "customer",
              author_display: (.author.login // "unknown"),
              created_at: .createdAt,
              body_preview: .title
            }],
            labels: ["pull-request"],
            attachments: [],
            safe_actions: ["post_internal_note"],
            unsafe_actions: ["public_close_with_comment"],
            evidence: [{kind: "provider", source: ("gh pr list -R " + $repo), checked_at: (now | todateiso8601)}]
          }' <<<"$prs_json")
      else
        emit_note "$surface" "GitHub repo or gh CLI unavailable; fill 02-channels.md and scripts/list-open.sh."
      fi
      ;;
    saas-custom)
      emit_note "$surface" "Custom SaaS support needs project-specific auth/base URL. base_url=$BASE_URL. Implement $PROJECT_LIST after onboarding."
      ;;
    saas-third-party)
      emit_note "$surface" "Provider=$PROVIDER needs a provider adapter or MCP tool. Implement $PROJECT_LIST after credential setup."
      ;;
    email)
      emit_note "$surface" "Email/contact-channel support was detected. Document inbox ownership, review cadence, and read-only export in 02-channels.md before live triage."
      ;;
    community-manual)
      emit_note "$surface" "Community/social support was detected. Treat as manual-only until the project records channel owner, cadence, and public/private reply rules."
      ;;
    marketplace-or-app-store)
      emit_note "$surface" "Marketplace/app-store support was detected. Map review/order/platform ids and manual response rules before attempting automation."
      ;;
    internal-ops)
      emit_note "$surface" "Internal-ops support was detected. Map employee identity, audit, escalation, and notification policy before triage."
      ;;
    none-yet)
      emit_note "$surface" "No support system detected. Offer /user-support-ticketing-system-for-saas before triage. If owner says yes, run scripts/scaffold-ticketing.sh \"\$WS\" to auto-install ticketing + co-deps (supabase, admin-page-for-nextjs-sites, stripe-checkout) via jsm and hand off to that skill."
      ;;
    *)
      emit_note "$surface" "Unknown support surface; update _detection.json and 02-channels.md."
      ;;
  esac
done

if [[ ${#objects[@]} -eq 0 ]]; then
  printf '[]\n'
else
  printf '%s\n' "${objects[@]}" | jq -s '.'
fi
