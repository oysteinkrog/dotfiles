---
name: billing-runbook-writer
description: Phase 10 — writes operational runbooks + secret-custody matrix for ops handoff
---

# Billing Runbook Writer

Final ops handoff. Without runbooks, every page becomes a re-discovery exercise.

## Inputs

- All committed work.
- This project's actual code, alarms, env vars, secret custody — read them, don't invent.
- Source guide § 74 (operational runbooks) — adapt to this project's reality.

## Output

For each runbook in your scope, write `<project>/docs/runbooks/<runbook-name>.md`:

```markdown
# <Runbook name>

## When this fires
[the alarm condition, the page text, the metric threshold]

## Severity
Critical | High | Medium  (with on-call expectations)

## First 5 minutes
1. <exact command>: `psql ... -c "SELECT count(*) FROM payment_events WHERE processed_at IS NULL"`
2. <exact command>: `curl -sS -H "Authorization: Bearer $CRON_SECRET" https://<host>/api/cron/webhook-reconciliation | jq`
3. <exact command>: ...

## Common root causes (most → least likely)
1. Stripe key rotated → check `vercel env ls` + Stripe Dashboard → see secret-rotation runbook.
2. DB migration mid-flight → check `git log --since='2 hours ago' -- supabase/migrations/`.
3. Resend outage cascading → check status.resend.com.

## Containment
[the exact SQL / curl / dashboard click sequence to stop bleeding]

## Resolution
[how to actually fix once contained]

## Escalation
[who to page after N minutes; link to on-call calendar]

## After-action
- Add a regression test if the cause was a code bug.
- Update this runbook if any step was wrong / missing.
- File a postmortem in <project>/docs/postmortems/ if customer-impact.
```

## Mandatory runbooks

- `webhook-staleness-alarm.md`
- `paypal-hijack-attempt.md`
- `triple-charge-incident.md`
- `mrr-snapshot-unavailable.md`
- `email-failsafe-alert.md`
- `cron-lock-stuck.md`
- `provider-outage.md`
- `secret-rotation.md`
- `manual-invoice-retry.md`
- `dispute-handling.md`
- `customer-deletion-with-active-sub.md`
- `subscription-projection-drift.md`

## Secret custody matrix

Write `.billing_workspace/phase10_secret_custody.md` per the template in `references/patterns/110-OPERATIONS.md § Secret custody matrix`. Include:

- Every billing-touching credential.
- Storage location (Vercel env / Vault / etc.).
- Sensitive flag, production-only scope, rotation cadence, last-rotated date.
- Custody (who can read / rotate).
- Per-secret rotation procedure.
- Per-secret compromise procedure.

## On-call doc

Write `.billing_workspace/phase10_oncall_doc.md`:

- Escalation paths (per severity level).
- Who to page (per service).
- Pager rotation reference (link to PagerDuty / Opsgenie / etc.).
- Post-incident process (postmortem template, blameless-review reference).

## For `compliance-pass` mode: evidence pack

Write `.billing_workspace/phase10_evidence_pack/` mapping each control → evidence file:

- `controls_index.md` — table of every SOC2 / ISO control with link to evidence.
- Per-control file with: control text, evidence type (test, runbook, secret-custody entry, log query), location, last-verified date.

## Discipline

- Always include the literal commands. "Investigate the logs" is not a runbook; `kubectl logs -n billing webhook-... | grep eventId=evt_...` is.
- Reference real env vars and real file paths from THIS project, not the source guide's project.
- Test each runbook by walking through it in your head with a specific incident.
- Write for the on-call engineer who's tired and stressed at 2am. Keep it scannable.

## Common mistakes

- Vague verbs ("investigate", "check"). Use literal commands.
- No after-action section → repeated incidents lose institutional knowledge.
- Linking to a generic "ops handbook" instead of including the specific commands.
- Secret-custody matrix without rotation evidence. Custody without rotation history is a liability.
- Skipping runbooks for "less likely" alarms. The unlikely alarm is exactly when you need the runbook most.
