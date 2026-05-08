# Incident Response

A user reports Mattermost is broken. Work this playbook.

## First 5 minutes

1. **Confirm reachability from your workstation.**
   ```
   ./maintain.sh health
   ```
   Read `latest-health.json.overall`.

2. **If health shows red, note which checks.** The pattern tells you the
   layer:
   - `mattermost_ping` red → app process
   - `websocket_upgrade` red, ping ok → Nginx / TLS / Cloudflare
   - `smtp_tcp` red → email provider (login-impacting if users need reset)
   - `disk_root` red → OS / disk full
   - `pg_connections` red → DB saturation
   - `mattermost_errors` red → bug or config regression

3. **Post a status update within 10 minutes.** Template: [../comms/INCIDENT-STATUS-KIT.md](../comms/INCIDENT-STATUS-KIT.md).

## Next 15 minutes — diagnose

Pair the red checks above with the corresponding diagnostic:

| Red check | Read | Common cause | First move |
|-----------|------|--------------|------------|
| `mattermost_ping` | [../diagnostics/HEALTH-DIAGNOSTICS.md](../diagnostics/HEALTH-DIAGNOSTICS.md) §app-process | OOM, crashed migration, port collision | `ssh target sudo systemctl status mattermost` + restart if down |
| `websocket_upgrade` | [../diagnostics/HEALTH-DIAGNOSTICS.md](../diagnostics/HEALTH-DIAGNOSTICS.md) §nginx-websocket | Nginx config drift | Re-run Phase 2 `render-config` + `deploy` |
| `disk_root` | [../diagnostics/HEALTH-DIAGNOSTICS.md](../diagnostics/HEALTH-DIAGNOSTICS.md) §disk | log blowup, data blowup, forgotten rotation | `ssh target sudo du -shx /* | sort -h` |
| `pg_connections` | [../POSTGRES-MAINTENANCE-DEEP-DIVE.md](../POSTGRES-MAINTENANCE-DEEP-DIVE.md) §saturation | connection leak from plugin or integration | `pg_stat_activity` query, terminate idle-in-tx |
| `mattermost_errors` | [../diagnostics/HEALTH-DIAGNOSTICS.md](../diagnostics/HEALTH-DIAGNOSTICS.md) §logs | recent upgrade or config change | `scripts/inspect-mattermost-log.py --window 1h` |

## Take a pre-action snapshot

Before mutating anything on the live host (restarting services, deleting
files, changing config), run:

```
./maintain.sh backup
```

Even a partial / degraded backup is better than no snapshot. Takes ~2 min.

## Remediation bands

### Band A: fix-in-place (most incidents)

Restart a service, free some disk, tune a Nginx param, restart a plugin,
kill a runaway query. Target: ≤ 30 minutes.

### Band B: config rollback

Recent config change caused the issue. Restore the previous config file
from Phase 2's `workdir-phase2/rendered/` or your backup.

### Band C: DB rollback

Recent DB-impacting change caused the issue (usually a plugin). Restore
from the most recent pre-change pg_dump. Accept data-loss for the delta
window. Bounded by your nightly backup cadence.

### Band D: disaster recovery

Host lost, corrupted beyond fix-in-place, or compromised. See
[../DISASTER-RECOVERY.md](../DISASTER-RECOVERY.md). Target: 2 to 4 hours.

## Status cadence during the incident

Post every 15 minutes until resolved:

```
[UPDATE HH:MM] Mattermost status: <investigating/mitigating/resolved>.
Current: <1-sentence description>.
Next update: <HH:MM>.
```

Templates in [../comms/INCIDENT-STATUS-KIT.md](../comms/INCIDENT-STATUS-KIT.md).

## Resolution

- Confirm `./maintain.sh health` returns green or yellow.
- Spot-check: log in as a non-admin test user in a browser.
- Post final "Resolved" update with duration and one-sentence root cause.
- Within 24 hours, write a short incident note at
  `workdir-phase3/reports/incidents/<ts>-<tag>.md`. Keep it blameless.

## Escalation triggers

Escalate immediately (see [../comms/ESCALATION-LADDER.md](../comms/ESCALATION-LADDER.md)) if:

- Mattermost unreachable for > 30 minutes with no clear remediation path.
- Evidence of data integrity concern (Postgres error logs mention
  `corrupt`, `invalid page`, or `unexpected chunk`).
- Evidence of compromise (unauthorized PAT use, unexpected `authorized_keys`
  entry, unfamiliar systemd unit running).
- The incident requires `ROLLBACK_OWNER` approval for a destructive move
  (DR, DB restore).

## Post-incident

Run through [QUARANTINE-AND-EVIDENCE.md](QUARANTINE-AND-EVIDENCE.md) if
compromise or data-integrity concern. Otherwise:

- Capture the relevant logs / reports into
  `workdir-phase3/reports/incidents/<ts>/`.
- Write a short post-mortem (what happened, timeline, root cause, fix,
  prevention).
- If the incident revealed a gap in the skill (missing diagnostic, missing
  alert), add it to the operator library.
