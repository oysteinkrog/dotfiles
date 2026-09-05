# Runbook: <runbook-name>

> **Template.** Copy to `<project>/docs/runbooks/<runbook-name>.md`. Fill in. Reference real env vars + commands from THIS project, not the source guide's project.

## When this fires
[The exact alarm condition / page text / metric threshold that triggers this runbook.]

## Severity
<Critical | High | Medium>
On-call expectations: <e.g., "page on-call within 5 min during business hours; within 15 min off-hours">

## First 5 minutes
1. **Acknowledge:** <how to ack the page>
2. **Assess scope:** Run the following queries to determine blast radius:
   ```bash
   # Real command, not "investigate the logs"
   psql "$DATABASE_URL" -c "SELECT count(*) FROM payment_events WHERE processed_at IS NULL AND age(now(), created_at) > '10 minutes';"
   ```
3. **Containment options:** [link to "Containment" section below]
4. **Communications:**
   - Internal: post in #billing-incidents Slack with severity + scope
   - Customer-facing: if customer-visible, update status page

## Common root causes (most → least likely)

1. **<root cause>**
   - Detection: <how to confirm>
   - Mitigation: <exact command>
2. **<root cause>**
   - Detection: ...
   - Mitigation: ...

## Containment
[The exact SQL / curl / dashboard click sequence to STOP THE BLEED. Reversible options first.]

```bash
# e.g., manually mark stuck rows for retry
psql "$DATABASE_URL" -c "UPDATE payment_events SET retry_count = 0, last_error = NULL WHERE id = 'evt_...' AND processed_at IS NULL;"

# e.g., trigger reconciliation cron manually
curl -sS -H "Authorization: Bearer $CRON_SECRET" "$APP_URL/api/cron/webhook-reconciliation"
```

## Resolution
[How to actually fix the root cause once contained. Includes verification steps.]

## Verification (don't close the incident without these)
- [ ] Containment action confirmed (state matches expected)
- [ ] No new occurrence in last 30 minutes
- [ ] Customer-impact tally (if any) recorded
- [ ] Customer communication sent (if customer-visible)

## Escalation
- **After N minutes without containment:** page <secondary on-call name> via <pager>.
- **After N minutes without resolution:** page <engineering lead> via <pager>.
- **For customer-affecting incidents:** notify <customer-success lead> immediately.

## After-action
- [ ] Postmortem filed within 1 week (template: assets/postmortem-template.md)
- [ ] Regression test added (if cause was a code bug)
- [ ] Runbook updated (if any step was wrong / missing)
- [ ] Pattern library updated (if novel failure class)

## References
- Pattern bundle: <references/patterns/<NN>-<name>.md>
- Bead/issue tracker: <link>
- Related postmortems: <list>
- Source guide: <§ NN>
