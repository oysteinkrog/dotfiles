# Handoff Artifact Contract

The ticketing system is not done when the schema, routes, and UI compile. It is
done when the triage skill can operate the queue safely without rediscovering
how the system works.

Treat this contract as a build deliverable.

## Contents

- [Required Project Artifacts](#required-project-artifacts)
- [`support-handoff.json`](#support-handoffjson)
- [Script Contracts](#script-contracts)
- [Handoff Acceptance](#handoff-acceptance)
- [Failure Mode](#failure-mode)

## Required Project Artifacts

Write these into the target project:

```text
<project>/.claude/support-triage/
├── README.md
├── 00-intake.md
├── 01-architecture.md
├── 02-channels.md
├── 03-decision-matrix.md
├── 05-policies.md
├── 06-recurring-issues.md
├── 07-secrets.md
├── 08-voice.md
├── 09-knowledge-base.md
├── 10-metrics.md
├── 11-runbooks/
├── 12-gap-dispositions.md
├── vocabularies/
│   └── themes.md
├── adapter-capabilities.json
├── artifacts/
│   ├── evidence/
│   ├── drafts/
│   ├── approvals/
│   ├── sends/
│   ├── verification/
│   └── manifests/
├── handoffs/
│   └── support-handoff.json
├── outcomes/
└── scripts/
    ├── list-open.sh
    └── post-reply.sh
```

If the triage skill already onboarded the project, update existing files in
place. Do not create parallel "new" support maps.

## `support-handoff.json`

The handoff is a machine-readable summary of what was built, what is safe, and
what must still require owner approval.

```json
{
  "schema": "support-handoff-v1",
  "project": "example",
  "generated_at": "2026-04-27T00:00:00Z",
  "risk_tier": "routine",
  "case_ids": [],
  "active_channels": ["custom-db"],
  "owner_required": true,
  "customer_visible_sends_blocked_until_approved": true,
  "current_state": "built",
  "next_owner": "support-owner",
  "support_archetypes": ["saas-subscription"],
  "system": {
    "framework": "nextjs-app-router",
    "database": "drizzle-postgres",
    "email_provider": "resend",
    "deployment": "vercel"
  },
  "routes": {
    "admin_list": "/api/admin/support/tickets",
    "admin_patch": "/api/admin/support/tickets",
    "admin_messages": "/api/admin/support/tickets/[id]/messages",
    "user_create": "/api/support/tickets",
    "user_list": "/api/support/tickets",
    "cron_sla": "/api/cron/sla-alerts"
  },
  "service_layer": {
    "path": "src/lib/services/support-tickets.ts",
    "open_statuses_export": "OPEN_TICKET_STATUSES",
    "state_machine_reference": ".claude/skills/user-support-ticketing-system-for-saas/references/STATE-MACHINE-CONFORMANCE.md"
  },
  "permissions": ["support.read", "support.assign", "support.resolve"],
  "env_vars": ["RESEND_API_KEY", "RESEND_FROM_EMAIL", "CRON_SECRET"],
  "adapters": {
    "list_open": ".claude/support-triage/scripts/list-open.sh",
    "post_reply": ".claude/support-triage/scripts/post-reply.sh",
    "adapter_version": "support-adapter-v1"
  },
  "owner_approval_required_for": [
    "send_customer_reply",
    "issue_refund",
    "issue_credit",
    "plan_upgrade",
    "account_lock",
    "security_reply",
    "privacy_request",
    "public_incident_update"
  ],
  "support_intelligence": {
    "theme_vocabulary": ".claude/support-triage/vocabularies/themes.md",
    "loop_owner": "product-or-support-owner",
    "theme_tags_exported": true,
    "persona_tags_exported": true,
    "compensation_band_exported": true,
    "keeper_consent_exported": true,
    "loopback_state_exported": true
  },
  "validation": {
    "doctor": "./scripts/doctor.sh",
    "state_machine": "state-machine conformance fixtures pass",
    "adapter": "validate-adapter-output.py passes",
    "support_map": "validate-support-map.py passes",
    "fire_drills": ["routine", "high-risk"]
  },
  "artifacts": {
    "evidence": [],
    "drafts": [],
    "approvals": [],
    "sends": [],
    "verification": []
  },
  "gap_dispositions": [
    {"gap": "no historical voice samples", "disposition": "evidence-gap", "owner": "support-owner"}
  ]
}
```

## Script Contracts

Generated project scripts should be boring and explicit.

| Script | Must do | Must not do |
|---|---|---|
| `scripts/list-open.sh` | read open tickets; emit `support-adapter-v1`; include evidence and SLA fields; exit non-zero on adapter failure | send replies, mutate customer state, hide provider errors |
| `scripts/post-reply.sh` | send only an approved draft; preserve provider message id; write audit evidence | generate unapproved copy, silently fallback to internal note |
| `scripts/export-ticket.sh` if present | export one ticket with messages and audit events for evidence packs | dump secrets or unrelated customer data |
| `scripts/smoke-support.sh` if present | create test ticket, verify email, verify admin reply path, cleanly label test data | run against production customers without a test account |

## Handoff Acceptance

- [ ] `support-handoff.json` exists and validates as JSON.
- [ ] `list-open.sh` emits `support-adapter-v1` and passes the triage validator.
- [ ] `post-reply.sh` either enforces owner-approved draft input or exits
  manual-only with a clear message.
- [ ] `adapter-capabilities.json` marks customer-visible sends as unsafe.
- [ ] `02-channels.md` documents email behavior and secondary channels.
- [ ] `05-policies.md` records owner-approved SLA/refund/security/privacy rules
  or marks them `TBD-OWNER`.
- [ ] `vocabularies/themes.md` exists if VoC/product feedback loops are in scope.
- [ ] Open-ticket export or outcome export includes theme/persona/source-stream
  fields when those loops are in scope.
- [ ] `support_archetypes` names the project shape; non-default support systems
  record their platform/order/build/employee/contract evidence keys.
- [ ] G11 accretive-loop status is recorded: either product/docs/ops loop fields
  exist with an owner, or the owner explicitly marked the loop not in scope.
- [ ] Refund/credit/upgrade records include approver and provider/account ids.
- [ ] `10-metrics.md` tells the triage skill how to measure queue health.
- [ ] routine and high-risk fire drills produced no-send draft bundles.

## Failure Mode

Without this contract, a support system can look complete while future agents
still cannot answer basic operational questions:

- Which statuses keep the SLA clock running?
- Did an admin note email the customer?
- Which permission controls assignment?
- Which env vars are required for live sends?
- Which actions require owner approval?
- How do we prove the queue is empty after a session?

If those answers live only in code or developer memory, the system is not
support-ready.
