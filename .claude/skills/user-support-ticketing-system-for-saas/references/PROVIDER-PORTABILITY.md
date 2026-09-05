# Provider Portability

Provider choices should be swappable implementation details. The support system
must not become a Resend-only, Slack-only, OpenAI-only, or Vercel-only design
unless the host project explicitly wants that tradeoff.

This page defines provider boundaries for email, observability, AI assist,
third-party ticket imports, and the triage handoff.

## Email Provider Contract

The system needs these operations:

| Operation | Required Behavior |
|---|---|
| `sendTicketCreatedEmail` | Confirms ticket receipt; includes short ticket id. |
| `sendTicketResponseEmail` | Sends support reply; exactly one send per approved reply. |
| `sendTicketResolvedEmail` | Optional but must be idempotent. |
| `recordProviderMessageId` | Stores provider id for audit/debugging. |
| `handleProviderFailure` | Does not mark reply as sent if provider failed. |

Provider implementations may use Resend, Postmark, SES, SendGrid, Mailgun, or a
project-local mailer. The service-layer semantics stay the same.

## Observability Provider Contract

Emit events for:

- ticket created;
- admin acknowledged;
- customer replied;
- support replied;
- SLA at risk;
- SLA breached;
- provider send failed;
- AI suggestion accepted/rejected;
- ticket resolved/closed.

Each event should include:

- ticket id;
- org/user id where allowed;
- priority;
- status before/after where relevant;
- SLA status;
- provider name;
- correlation/request id.

Do not log raw PII or full message bodies unless the product's privacy policy
explicitly permits it.

## AI Assist Provider Contract

AI assist may classify, summarize, dedupe, or draft suggestions. It must not be
the system of record.

Required boundaries:

- Suggestions are stored separately from messages.
- Suggestions include model/provider/version.
- Customer-visible output goes through `/de-slopify` and owner/admin approval.
- Rejection reason is recorded when an admin discards a suggestion.
- No AI action sends, refunds, closes public issues with comment, or cancels
  accounts.

Useful metrics:

- suggestions generated;
- suggestions accepted;
- suggestions edited heavily;
- suggestions rejected;
- top rejection reasons;
- categories where AI assist is disabled.

## Third-Party Migration Provider Contract

When migrating from Zendesk, Intercom, Help Scout, Freshdesk, Plain, Linear,
Front, Gorgias, HubSpot Service Hub, Salesforce Service Cloud, JSM, or Zoho
Desk:

- preserve external ids;
- keep provider links in admin UI;
- import message authors and timestamps;
- mark imported messages as historical, not newly sent;
- do not recompute old SLA breaches as current emergencies unless owner asks;
- provide rollback or read-only dual-run during cutover.

## Triage Handoff Provider Contract

Every provider-backed system should still expose the same triage adapter:

```
<project>/.claude/support-triage/scripts/list-open.sh
<project>/.claude/support-triage/adapter-capabilities.json
```

The triage skill should not need to know which email, observability, or AI
provider was chosen. It needs normalized open items, evidence links, and clear
safe/unsafe action boundaries.

## Acceptance Standard

A provider integration is support-ready when:

- provider failure does not create false "sent" or "resolved" state;
- customer-visible sends are idempotent;
- audit records include provider ids;
- observability captures lifecycle events without leaking message bodies;
- AI assist records accept/reject outcomes;
- the triage adapter remains valid after provider changes.
