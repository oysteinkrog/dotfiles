# Escalation Ladder

When to escalate beyond this skill, and to whom.

## Escalation levels

| Level | Trigger | Destination | Response SLO |
|-------|---------|-------------|--------------|
| L0 — self-fix | Yellow health, recoverable failure | Operator continues with agent | minutes |
| L1 — rollback owner | Stage blocked on gate; destructive action needed | `ROLLBACK_OWNER` (named human) | within 30 min |
| L2 — infra oncall / DBA | Postgres-level issue, host unreachable | Infra team / on-call DBA | within 1 hour |
| L3 — Mattermost Enterprise support | Bug requiring vendor fix; HA / cluster problem | `support@mattermost.com` (requires paid subscription) | per contract |
| L4 — legal / compliance | Legal-hold, PII exposure, compromise | Legal + DPO | immediately |
| L5 — executive | Multi-day outage or material user-data impact | Exec sponsor | immediately |

## By symptom

| Symptom | Start at |
|---------|----------|
| User reports Mattermost "slow" | L0 — `health`, investigate |
| User reports Mattermost "down" | L0 → L1 if not recoverable in 30 min |
| Backup failed 3 nights in a row | L1 |
| Restore-drill failed 2 quarters in a row | L1 + L2 |
| Host unreachable after reboot | L1 + L2 |
| Evidence of PAT or SSH compromise | L1 + L4 |
| Postgres error logs show `corrupt` | L1 + L2 (data integrity) |
| Mattermost crash-loops after upgrade | auto-rollback should handle; if it doesn't, L1 |
| Ransomware / destructive event | L4 + L5 |
| DR drill fails | L1 |
| Legal hold notification received | L4 |

## Contact record

Keep a current contacts list in `workdir-phase3/contacts.md`. Minimum
fields: role, name, email, phone, backup contact.

Example:

```
# Phase 3 contact list (update quarterly)

## ROLLBACK_OWNER
Name: Jane Admin
Email: jane@acme.com
Phone: +1-555-0100
Backup: John Admin <john@acme.com> / +1-555-0101

## Infra on-call
Team: acme-infra
Pager: https://oncall.acme.com/team/infra

## Mattermost support (if subscribed)
Account: acme-chat
Portal: https://customers.mattermost.com

## Legal / DPO
Name: [Legal contact]
Email: legal@acme.com

## Hosting provider (Hetzner)
Account ID: 123456
Support ticket portal: https://accounts.hetzner.com/support
```

## Escalation narrative

When escalating, include:

1. **What** happened (one sentence)
2. **When** it started (timestamp)
3. **What you tried** (actions taken so far)
4. **What's blocking** (gate, missing info, authority)
5. **What you need** (specific ask)

Example:

> Backup has failed 3 consecutive nights. Errors suggest off-site
> destination is unreachable (rclone auth error). I've re-verified creds
> against the provider console. Need: decision on whether to rotate
> rclone credentials now (3 AM UTC window), or wait for business hours.

## Do not

- Don't escalate on L0-recoverable issues that the agent has flagged.
- Don't page `ROLLBACK_OWNER` for yellow health checks.
- Don't skip L1 when L2 is needed; the rollback owner coordinates.
- Don't communicate with Mattermost support via free channels for a
  production incident; file a support ticket via the portal.
