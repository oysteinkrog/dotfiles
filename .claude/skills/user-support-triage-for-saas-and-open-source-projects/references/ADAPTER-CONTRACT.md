# Universal Support Adapter Contract

The triage skill should consume every support surface through one normalized,
read-first contract. GitHub, a custom database, Zendesk, Intercom, Help Scout,
email, Discord, or a future support system can all keep their native APIs. The
agent should not need to remember every native shape while triaging.

This contract is the shared interface between:

- this triage skill, which operates a queue;
- `/user-support-ticketing-system-for-saas`, which may build a queue;
- provider-specific adapters for GitHub, custom SaaS tickets, or third-party
  tools.

## Contract Goals

1. **One triage input shape.** All open support items normalize into a single
   JSON array of support items.
2. **Read-only by default.** Listing, inspecting, and classifying must have zero
   customer-visible side effects.
3. **Explicit capability boundaries.** The adapter says what it can and cannot
   do; agents do not discover write actions by trial and error.
4. **Confirmation gate preserved.** Any action that can message a customer,
   issue a refund, close a public issue with comment, cancel an account, or
   publish a status update remains owner-approved.
5. **Provider independence.** Provider-specific pagination, auth, rate limits,
   and error shapes stay behind the adapter.

## Required Files In Onboarded Projects

Every onboarded project should eventually expose:

```
<project>/.claude/support-triage/scripts/list-open.sh
<project>/.claude/support-triage/adapter-capabilities.json
```

`list-open.sh` prints the adapter JSON array below. It must be read-only.

`adapter-capabilities.json` documents supported safe and unsafe actions. Unsafe
actions may exist, but the triage skill may call them only after explicit owner
approval.

## `list-open.sh` Output

The script prints a JSON array. Each element is one normalized support item:

```json
[
  {
    "adapter_version": "support-adapter-v1",
    "surface": "saas-custom",
    "provider": "custom-db",
    "id": "sup_01HV...",
    "stable_url": "https://example.com/admin/support/tickets/sup_01HV...",
    "public_url": null,
    "subject": "Unable to install after subscribing",
    "category": "access",
    "status": "open",
    "priority": "p1",
    "created_at": "2026-04-27T14:11:03Z",
    "updated_at": "2026-04-27T14:22:19Z",
    "last_customer_message_at": "2026-04-27T14:22:19Z",
    "last_support_message_at": null,
    "age_hours": 0.2,
    "customer": {
      "id": "user_123",
      "display": "Jane Example",
      "email": "jane@example.com",
      "handle": null,
      "tier": "enterprise",
      "org": "ExampleCo"
    },
    "sla": {
      "status": "at_risk",
      "deadline": "2026-04-27T18:11:03Z",
      "breached_at": null,
      "paused": false
    },
    "messages": [
      {
        "id": "msg_1",
        "author_type": "customer",
        "author_display": "Jane Example",
        "created_at": "2026-04-27T14:22:19Z",
        "body_preview": "I paid but the install command still says I am not subscribed."
      }
    ],
    "labels": ["billing", "access"],
    "attachments": [],
    "safe_actions": ["post_internal_note", "transition_status"],
    "unsafe_actions": ["send_customer_reply"],
    "evidence": [
      {
        "kind": "code",
        "source": "src/lib/services/support-tickets.ts#listOpenTickets",
        "checked_at": "2026-04-27T14:30:00Z"
      }
    ]
  }
]
```

## Field Rules

| Field | Required | Rule |
|---|---:|---|
| `adapter_version` | yes | Must be `support-adapter-v1` until a new contract is written. |
| `surface` | yes | One of `github-only`, `saas-custom`, `saas-third-party`, `email`, `community-manual`, `marketplace-or-app-store`, `internal-ops`, `chat`, or a documented extension. |
| `provider` | yes | Native provider name: `github`, `custom-db`, `zendesk`, `intercom`, `helpscout`, `plain`, etc. |
| `id` | yes | Native stable id. Do not invent random ids in the adapter. |
| `stable_url` | yes | Operator-facing URL where the owner/agent can inspect the item. |
| `subject` | yes | Human-readable ticket title. Empty native subjects should be summarized from first message. |
| `status` | yes | Native status normalized to a small string. Preserve original in `labels` or evidence if needed. |
| `priority` | yes | `p0`, `p1`, `p2`, `p3`, or `unknown`. |
| `created_at`, `updated_at` | yes | ISO-8601 UTC timestamps. |
| `customer` | yes | Object may contain null values, but must exist. |
| `sla` | yes | Object may be `{"status":"unknown"}` for systems without SLA tracking. |
| `messages` | yes | May be truncated, but include enough recent customer/support context for orientation. |
| `safe_actions` | yes | Actions that do not message customers or mutate money/account state. |
| `unsafe_actions` | yes | Actions that require owner approval before use. |
| `evidence` | yes | At least one source explaining where the adapter data came from. |

Recommended optional fields for non-default domains:

| Field | Use when | Rule |
|---|---|---|
| `source_stream` | VoC, surveys, reviews, public mentions, sales handoffs | Preserve where the evidence came from; do not collapse everything to "ticket". |
| `locale` | multilingual support | BCP-47 tag if known; never guess from name alone. |
| `market_context` | marketplace/app-store/ecommerce support | Include platform/order/review identifiers only when allowed by policy. |
| `internal_requester` | internal ops / employee support | Separate employee identity from external customer identity. |
| `legal_hold` | regulator/legal/security/privacy cases | Boolean or object pointing to chain-of-custody artifact; never auto-expire. |

## Deliberate Non-Fields

Do **not** put these in v1 of the adapter:

- `refund_preview` or refund authority. Refund logic belongs to billing/payment
  integrations and the refund runbook.
- full customer health scoring. That belongs to analytics and can be joined as
  supplemental context later.
- secrets or raw API tokens.
- entire message history when a provider has a large thread. Include recent
  context plus stable links.

Keeping the adapter narrow prevents it from becoming a universal business-data
god object.

## Capabilities File

`adapter-capabilities.json` should look like:

```json
{
  "adapter_version": "support-adapter-v1",
  "provider": "custom-db",
  "read": {
    "list_open": true,
    "fetch_item_detail": true,
    "fetch_sla": true
  },
  "safe_actions": {
    "post_internal_note": true,
    "transition_status": true,
    "file_bead": true
  },
  "unsafe_actions": {
    "send_customer_reply": {
      "supported": true,
      "confirmation_required": true
    },
    "issue_refund": {
      "supported": false,
      "confirmation_required": true,
      "delegate_to": "billing/refund runbook"
    },
    "public_close_with_comment": {
      "supported": true,
      "confirmation_required": true
    }
  },
  "limits": {
    "pagination": "adapter handles internally",
    "rate_limit": "provider default; retry after 429",
    "max_messages_per_item": 10
  }
}
```

## Error Shape

If the adapter cannot list items, it should still return valid JSON:

```json
[
  {
    "adapter_version": "support-adapter-v1",
    "surface": "saas-third-party",
    "provider": "zendesk",
    "status": "adapter_error",
    "id": "adapter-error-zendesk",
    "subject": "Zendesk adapter failed",
    "created_at": "2026-04-27T14:30:00Z",
    "updated_at": "2026-04-27T14:30:00Z",
    "priority": "unknown",
    "stable_url": null,
    "customer": {},
    "sla": {"status": "unknown"},
    "messages": [],
    "safe_actions": [],
    "unsafe_actions": [],
    "error": {
      "kind": "rate_limited",
      "message": "Zendesk returned 429",
      "retry_after_seconds": 60
    },
    "evidence": [
      {"kind": "provider", "source": "zendesk tickets API", "checked_at": "2026-04-27T14:30:00Z"}
    ]
  }
]
```

The triage agent can then tell the owner exactly what failed instead of silently
triaging a partial queue.

## Validation

Run:

```bash
python3 <skill>/scripts/validate-adapter-output.py /tmp/open-items.json
```

The validator checks:

- root JSON is an array;
- every item has required fields;
- timestamps parse as ISO-8601;
- actions are split into safe and unsafe buckets;
- high-risk fields are not smuggled into v1;
- dangerous actions such as sends, refunds, account locks, deletion, and public
  publishing are not mislabeled as `safe_actions`;
- adapter errors are explicit rather than malformed normal tickets.

## Acceptance Standard

Onboarding is not complete until:

1. `list-open.sh` returns valid adapter JSON for every channel in `02-channels.md`;
2. the adapter output passes `validate-adapter-output.py`;
3. the owner can inspect `stable_url` for at least one real or fixture item;
4. the adapter clearly says which customer-visible actions are unsafe;
5. a fire drill uses the adapter JSON as input and produces a no-send draft
   bundle.
