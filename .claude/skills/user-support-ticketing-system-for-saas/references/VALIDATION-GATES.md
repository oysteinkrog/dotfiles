# Validation Gates

Use these gates for builds, audits, and migrations. They turn "the ticketing
system works" into a sequence of proofs that future agents can inspect.

## Gate Sequence

| Gate | Name | Proof |
|---|---|---|
| G0 | Prerequisite doctor | `scripts/doctor.sh` passes or blockers are explicitly routed |
| G1 | Mode and policy | complexity mode declared; owner policy decisions recorded or marked `TBD-OWNER` |
| G2 | Schema and state machine | migration runs; state-machine conformance fixtures pass |
| G3 | Service-layer invariants | all mutations go through service layer; open statuses shared; SLA tests pass |
| G4 | API security | user ownership, admin permission keys, reason/audit, rate-limit tier tests pass |
| G5 | Email and external side effects | created/response/resolved sends verified; provider ids stored; no silent internal-note path |
| G6 | UI workflow | user can create/read/reply; admin can filter/assign/reply; accessibility basics pass |
| G7 | Cron and observability | cron flags at-risk/breached idempotently; logs/metrics expose queue health |
| G8 | Handoff adapters | `list-open.sh` emits `support-adapter-v1`; support map validator passes |
| G9 | Fire drills | one routine and one high-risk no-send drill produce draft/evidence/outcome |
| G10 | Production smoke | test ticket in production path sends/receives expected emails and verifies queue state |
| G11 | Accretive loop | tickets export support-intelligence fields or an explicit "not in scope" decision; KB/docs/product loop owner named |

Do not skip from G2 to G11. Most real support failures live in the glue between
schema, side effects, permissions, and operational handoff.

## Gate Record Template

Write a gate record in the PR, implementation note, or
`<project>/.claude/support-triage/handoffs/`:

```markdown
# Support Ticketing Validation Record

Date:
Mode:
Commit / deployment SHA:

| Gate | Status | Evidence |
|---|---|---|
| G0 Prerequisite doctor | pass/fail/blocked | command output or blocker |
| G1 Mode and policy | pass/fail/blocked | policy file / owner answer |
| G2 Schema and state machine | pass/fail/blocked | migration + test command |
| G3 Service-layer invariants | pass/fail/blocked | test command |
| G4 API security | pass/fail/blocked | test command |
| G5 Email side effects | pass/fail/blocked | provider ids / test |
| G6 UI workflow | pass/fail/blocked | E2E / screenshot / test |
| G7 Cron and observability | pass/fail/blocked | cron run / logs |
| G8 Handoff adapters | pass/fail/blocked | validator output |
| G9 Fire drills | pass/fail/blocked | artifact links |
| G10 Production smoke | pass/fail/blocked | smoke proof |
| G11 Accretive loop | pass/fail/blocked | VoC/KB/product loop fields, owner, or not-in-scope decision |

Open risks:
- ...
```

## Minimum Bar By Mode

| Mode | Required gates before launch |
|---|---|
| Minimal | G0-G6, G8, G11 as pass or explicit not-in-scope, one routine fire drill |
| Standard | G0-G11 |
| Enterprise | G0-G11 plus named owner escalation proof |
| Regulated | G0-G11 plus evidence pack and security/privacy review |
| Migration | G0-G11 plus import/export reconciliation and rollback proof |
| OSS-hybrid | G0-G8, G11, plus public/private channel boundary proof |

## Common False Greens

- Unit tests pass but admin reply does not send email.
- Email provider accepts a message but no delivery event is captured.
- Admin list works for first page but counts/pagination are wrong.
- UI count pills use unfiltered client state.
- Cron endpoint runs locally but production lacks `CRON_SECRET` or schedule.
- `list-open.sh` reads only custom DB tickets and misses email/GitHub/social.
- AI suggestions are tested as strings, not as untrusted customer content.
- Production smoke uses an admin test path, not the customer path.
- The queue works, but support evidence cannot improve docs, product quality,
  onboarding, reliability, or retention because no fields/export/owner exist.

When a gate is blocked, write the blocker and owner. Do not downgrade the gate
into a vague "manual QA needed" note.
