# Support Evidence And Artifact Contract

Use this whenever onboarding or triage touches money, account access, security,
privacy, legal risk, hostile users, public incidents, or high-volume failures.
Routine tickets can use the lighter Phase 6 outcome record, but high-risk work
needs an artifact pack that another agent or human can audit later.

## Contents

- [Artifact Tree](#artifact-tree)
- [Evidence Pack Contents](#evidence-pack-contents)
- [Trust Boundaries](#trust-boundaries)
- [Gap Dispositions](#gap-dispositions)
- [`support-handoff.json`](#support-handoffjson)
- [High-Risk Acceptance Gate](#high-risk-acceptance-gate)

## Artifact Tree

Create artifacts under the target project, not inside this skill:

```text
<project>/.claude/support-triage/
├── artifacts/
│   ├── evidence/
│   │   └── <YYYYMMDD>-<case-id>.md
│   ├── drafts/
│   │   └── <YYYYMMDD>-<case-id>.md
│   ├── approvals/
│   │   └── <YYYYMMDD>-<case-id>.md
│   ├── sends/
│   │   └── <YYYYMMDD>-<case-id>.md
│   ├── verification/
│   │   └── <YYYYMMDD>-<case-id>.md
│   └── manifests/
│       └── <YYYYMMDD>-<case-id>.json
├── handoffs/
│   ├── support-handoff.json
│   └── <YYYYMMDD>-<case-id>-handoff.md
└── 12-gap-dispositions.md
```

Do not store raw secrets. Redact personal data unless the exact value is needed
to prove the action, and prefer provider ids over full payloads.

## Evidence Pack Contents

For a high-risk case, collect:

| Artifact | Required contents |
|---|---|
| Evidence | ticket id, channel, customer segment, timestamps, quoted user symptom, exact reproduction path, logs/queries used, source links |
| Drafts | all proposed customer-facing messages, internal notes, and owner questions |
| Approval | exact owner approval text, timestamp, approved draft hash or pasted approved draft |
| Sends | provider API used, provider message id, status, timestamp, actor, customer-visible URL if any |
| Verification | re-fetch result, email delivery check, status/SLA after action, remaining open items |
| Manifest | artifact filenames, optional hashes, risk tier, gap dispositions, next owner |

The pack should let a future agent answer: what did we know, what did we do,
who approved it, did it reach the user, and what remains unsafe?

## Trust Boundaries

Support work crosses systems with different truth guarantees. Name the boundary
before trusting evidence.

| Boundary | Trust question | Typical proof |
|---|---|---|
| Support provider | Did the ticket/message actually exist and update? | provider id, fetched thread, audit event |
| Project database | Did the app state change? | read-after-write query, row version, audit log |
| Email provider | Did a customer-visible message send? | provider message id, delivery/event webhook |
| Billing provider | Did refund/charge/subscription state change? | provider id, idempotency key, dashboard/API readback |
| Identity provider | Is the requester allowed to control the account? | verified auth session, ownership proof, recovery policy |
| Deployment system | Is the fix live for affected users? | deployed SHA, environment, smoke test |
| Owner approval | Did a human approve this external action? | copied approval text and approved draft |
| Customer channel | Did the customer see the message? | public comment URL, email delivery, chat transcript |
| Logs/analytics | Is the observed symptom real and scoped? | query text, time window, sample size, dashboard URL |
| AI provider | Did model output influence the action? | prompt/output snapshot, human edits, final approved text |

## Gap Dispositions

Every gap gets one disposition. Do not leave ambiguous "todo" notes in support
maps; they become future hallucination seeds.

| Disposition | Meaning | Allowed next action |
|---|---|---|
| confirmed | Evidence exists and behavior/policy is known | automate or template within policy |
| not-applicable | The project truly does not have this surface/risk | ignore until surface changes |
| manual-only | Human must handle this channel/action | document owner, cadence, and escalation |
| blocked-by-access | Agent lacks credentials or provider access | ask owner for access or manual export |
| provider-gap | External tool cannot supply needed proof/action | add workaround or manual check |
| policy-gap | Owner has not decided rule | batch into policy prompt; do not guess |
| evidence-gap | Claim may be true but lacks proof | investigate before drafting |
| deferred | Known improvement but not needed for current safe operation | file backlog item with owner |
| unknown | Insufficient information even after investigation | escalate; avoid automation |

## `support-handoff.json`

Machine-readable handoff for live escalations, migrations, or multi-agent
support runs:

```json
{
  "schema": "support-handoff-v1",
  "project": "example",
  "generated_at": "2026-04-27T00:00:00Z",
  "risk_tier": "money|access|security|privacy|incident|routine",
  "case_ids": ["ticket-123"],
  "active_channels": ["custom-db", "email"],
  "owner_required": true,
  "customer_visible_sends_blocked_until_approved": true,
  "current_state": "investigating|drafting|awaiting_owner|approved|sent|verified|blocked",
  "next_owner": "role-or-person",
  "artifacts": {
    "evidence": ["artifacts/evidence/20260427-ticket-123.md"],
    "drafts": ["artifacts/drafts/20260427-ticket-123.md"],
    "approvals": [],
    "sends": [],
    "verification": []
  },
  "gap_dispositions": [
    {"gap": "refund authority above $200", "disposition": "policy-gap", "owner": "founder"}
  ],
  "commands_to_resume": [
    ".claude/support-triage/scripts/list-open.sh"
  ]
}
```

## High-Risk Acceptance Gate

Before closing a high-risk support session:

- [ ] evidence pack exists;
- [ ] customer-facing draft was approved or explicitly not sent;
- [ ] provider ids or public URLs prove sends/actions;
- [ ] verification re-fetched the relevant queue/state;
- [ ] each remaining gap has a disposition;
- [ ] `support-handoff.json` names the next owner if work remains;
- [ ] outcome record links the artifact pack.

If this feels heavy for a routine ticket, use the normal Phase 6 outcome record
instead. If it feels heavy for a refund, account lock, privacy request,
security report, or outage, that is the signal that the artifact pack is doing
its job.
