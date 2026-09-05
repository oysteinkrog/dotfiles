# Runbook: DATA-LOSS

A customer reports that their data is missing or corrupted. **One of the highest-stakes categories.** Mishandling = churn + chargebacks + reputation hit + potential legal liability.

## Trigger Conditions

- "My <documents/projects/skills/posts/etc> are gone"
- "I lost data after [event: upgrade/update/switch]"
- "Something is showing the wrong info on my account"
- "I can't access my data"
- "Files I uploaded are missing"
- A 500 error mentioning the user's data not found
- The user says "this isn't what it was yesterday"

## First Hour (Triage)

Severity is everything. Determine:

1. **Was data actually lost, or is it just inaccessible?** Inaccessible (auth issue, region routing, permissions) is recoverable. Lost (deleted, overwritten, corrupted) is harder.
2. **Is this one user, or many?** One = investigate; many = INCIDENT, follow [OUTAGE-COMMS.md](OUTAGE-COMMS.md).
3. **When was it lost?** Pin to a deploy / migration / cron / backup window.
4. **Is recovery possible?** Backups, soft-delete, S3 versioning, audit log.
5. **What's the user's tier / blast radius?** Enterprise customer = different response than free user.

## Investigation Procedure

```bash
PROJECT="<project-path>"
ADMIN_KEY=$(grep ADMIN_API_KEY "$PROJECT/.env" | cut -d= -f2)
BASE="https://<project-domain>"

# 1. User context
curl -s "$BASE/api/admin/users?email=$EMAIL" \
  -H "Authorization: Bearer $ADMIN_KEY"

# 2. Check soft-delete table (if you have one)
psql -c "SELECT * FROM <table>_deleted WHERE user_id = '<user_id>' AND deleted_at > NOW() - INTERVAL '7 days';"

# 3. Audit log: who/what touched this data, when?
psql -c "SELECT * FROM audit_log WHERE entity_type = '<type>' AND entity_id = '<id>' ORDER BY ts DESC LIMIT 50;"

# 4. S3 / R2 versioning (if files)
aws s3api list-object-versions --bucket <bucket> --prefix '<user_id>/'
# Or wrangler r2 (Cloudflare):
wrangler r2 object list <bucket> --prefix='<user_id>/'

# 5. Postgres point-in-time recovery (Supabase / RDS)
# Determine the timestamp before the loss, prepare for restore

# 6. Check recent deploys / migrations
git log --since='7 days ago' -- migrations/
git log --since='7 days ago' --grep='migrat\|delet\|drop'

# 7. Cron logs (could be a runaway cron)
grep -i 'delete\|cleanup\|purge' /var/log/cron* 2>/dev/null || \
  curl -s "$BASE/api/admin/cron-runs?since=7days"
```

## Decision Tree

```
Is the data recoverable from soft-delete / audit-log / backups?
├─ Yes, fully → restore + apologize + post-mortem the cause.
│
├─ Partially → restore what's possible + explicitly tell the user what's
│              gone + offer compensation (refund / extended subscription /
│              credit).
│
└─ No → user-facing acknowledgment + post-mortem + compensation.
        For severe cases (paid customer, data integral to their workflow),
        escalate to owner immediately.
```

## Soft-Delete Recovery

If the project has a soft-delete pattern (a `deleted_at` column or a separate `_deleted` table):

```sql
-- Restore from soft-delete
BEGIN;
  -- Move from _deleted to live (or NULL the deleted_at)
  UPDATE user_content
    SET deleted_at = NULL, restored_at = NOW(), restored_by = 'support-runbook'
    WHERE id = '<id>' AND deleted_at IS NOT NULL;

  -- Verify the row reappears
  SELECT id, title, deleted_at, restored_at FROM user_content WHERE id = '<id>';
COMMIT;
```

**Always wrap restores in transactions.** Verify before commit.

## Backup / Point-in-Time Recovery

For Supabase, RDS, or Postgres-managed:

```bash
# Supabase: project dashboard → Database → Backups → Point in Time
# RDS: aws rds restore-db-instance-to-point-in-time --restore-time "2026-04-27T15:00:00Z"
```

Restore to a separate database (don't overwrite production), pull just the affected rows, copy them back.

```sql
-- After restoring the snapshot to a separate database:
-- (from snapshot DB)
COPY (SELECT * FROM <table> WHERE user_id = '<user_id>') TO '/tmp/recover.csv' CSV HEADER;

-- (on production DB)
COPY <table>_temp FROM '/tmp/recover.csv' CSV HEADER;
INSERT INTO <table> SELECT * FROM <table>_temp WHERE NOT EXISTS (
  SELECT 1 FROM <table> WHERE id = <table>_temp.id
);
```

## File / Object Storage Recovery

If S3/R2 versioning is enabled:

```bash
# List versions including deleted markers
aws s3api list-object-versions --bucket <b> --prefix '<user_id>/'

# Restore: delete the delete-marker
aws s3api delete-object --bucket <b> --key '<key>' --version-id '<delete-marker-version-id>'
```

**If versioning is NOT enabled**: lost is lost (unless caught within Cloudflare R2's 24h retention or AWS S3 Glacier window).

## Drafts

### DATA-LOSS-RECOVERED-FULLY

```
Confirmed — we found and restored the missing <data>. You should see
it back on your account now. Please verify and let us know if anything
still looks off.

Root cause: <one-sentence>.

We're sorry for the scare. <If applicable: we've identified a fix to
prevent this class of issue going forward and are deploying it this
week.>
```

### DATA-LOSS-PARTIAL-RECOVERY

```
Mixed news:

Recovered: <list of items + dates>
Could not recover: <list> — the <reason: backup window expired / soft-delete
was hard-deleted by a cron / etc.>

What we're doing:
1. Restoring everything we can right now (already in your account)
2. Compensating: <offer: refund / N months free / credit>
3. Investigating root cause and fixing so this doesn't happen again

We're deeply sorry. If you have local copies / exports that include
the lost <items>, send them and we'll re-import.
```

### DATA-LOSS-COMPLETE-LOSS

```
We have very bad news. After a full investigation, we couldn't recover
<data>. Here's what we know:

What was lost: <specific>
When: <timestamp>
Why: <root cause, plain language>

What we did wrong: <honest, specific, blameless>

What we're offering:
- Refund of <amount> for <period>
- <Additional compensation>: <e.g., 6 months of [Plan] free, $X account
  credit>
- Direct line to <owner-name> for any further conversation

This is the worst category of incident a service can have, and we're
genuinely sorry. We are running a postmortem and will share findings with
you within <N> days.

If you have local exports or copies, we can re-import them. If you've lost
work that has business consequences, please tell us what they are — we
want to do right by you.
```

## Postmortem (Always — Even For Single-User Loss)

```markdown
# Postmortem: Data loss for <customer> — <date>

## Summary
<1 paragraph>

## Timeline
- <when data was created>
- <when something changed>
- <when loss happened>
- <when reported>
- <when recovered (or not)>

## Root cause
<technical detail>

## What we recovered
<list>

## What we couldn't
<list + reason>

## Customer comms
<what we told them, when>

## Compensation offered
<list>

## Action items
- [ ] Fix root cause: <task>
- [ ] Add safeguard: <regression test, alert, etc.>
- [ ] Add backup: <if relevant>
- [ ] Document in 06-recurring-issues.md
```

Even for one-user losses, do this. Patterns surface; the next loss is preventable.

## Common Root Causes

1. **Migration without backup**: schema change deleted a column without dump-first.
2. **Foreign-key cascade**: deleting parent removed all children.
3. **Cron with bad WHERE clause**: `DELETE FROM x` ran on the wrong condition.
4. **Soft-delete defeated by hard-delete cron**: `_deleted` table swept after 7 days; user reported on day 8.
5. **S3 lifecycle rule**: objects auto-deleted after N days.
6. **Race condition**: concurrent writes; "last write wins" overwrote without merging.
7. **Idempotency bug**: same delete request retried, deleted both copies of an item.
8. **User-side**: they deleted it themselves and don't remember (usually recoverable from soft-delete; tell them honestly).

## Anti-Patterns

| Don't | Why |
|---|---|
| Promise recovery before you've verified | If you can't recover, customer feels lied to |
| Restore to production without verification | Easy to make it worse with a bad restore |
| Skip the postmortem because it was "just one user" | The pattern matters; the next loss is bigger |
| Avoid saying "we lost your data" | Sugarcoating breaks trust permanently |
| Default to "your data is fine" before investigating | Customer comes back angrier when it isn't |
| Compensate too generously to silence them | Buys silence not loyalty; document policy |
| Compensate too little | Trust never recovers |
| Defer comms while engineering investigates | Customer needs SOMETHING within an hour |

## Companion Refs

- [BILLING-DEEP.md](BILLING-DEEP.md) — when the "data" is billing state
- [OUTAGE-COMMS.md](OUTAGE-COMMS.md) — when many customers lost data
- [POST-INCIDENT-RETRO.md](../POST-INCIDENT-RETRO.md) — internal retro process
- [SECURITY-DISCLOSURE.md](SECURITY-DISCLOSURE.md) — if data loss was a security incident
