# Scenario Pack — Growing Team (250 → 1000 users)

Operational plan for a workspace that grew through the Phase 3 lifetime.
At 250+ users, some patterns need adjustment.

## Profile

- Starts at 250 users, grows to 1,000 over 18 months
- Hardware: Hetzner AX52 from day one (or AX42 → AX52 at ~400 users)
- DB: local Postgres
- File storage: Cloudflare R2 (mandatory at this scale to avoid local disk growth)
- Off-site backups: R2 + Hetzner Storage Box (two copies)
- DB size: ~20 GB initially, grows 1-3 GB/month
- Peak concurrent users: 100 → 400
- Operator: 1 primary + 1 backup, part-time

## Key configuration differences vs small team

```bash
# Upgrade windows matter more at this scale
REBOOT_WINDOW_DAY="Sun"
REBOOT_WINDOW_HOUR_START="6"    # 06:00 UTC ≈ off-hours for mixed-timezone teams
REBOOT_WINDOW_HOUR_END="8"

# Tighter health thresholds; noise is signal at this scale
HEALTH_DISK_PCT_YELLOW="70"
HEALTH_DISK_PCT_RED="80"
HEALTH_PG_CONN_PCT_YELLOW="50"
HEALTH_PG_CONN_PCT_RED="70"

# More history: daily 30d, weekly 26w, monthly 24m
BACKUP_RETENTION_DAILY_DAYS="30"
BACKUP_RETENTION_WEEKLY_WEEKS="26"
BACKUP_RETENTION_MONTHLY_MONTHS="24"

# RESTORE_MIN_* is updated each quarter as the workspace grows
# (quarterly review catches this)

# Two operators; named primary:
ROLLBACK_OWNER="Jane <jane@acme.com>; backup: John <john@acme.com>"
```

## Cadence adjustments

| Cadence | Stage | Difference vs small-team |
|---------|-------|--------------------------|
| Daily 03:00 UTC | `backup` | Same |
| Daily 10:00 UTC | `db-health` (lightweight check) | Added at this scale |
| Sunday 02:00 UTC | `weekly-sweep` | Same but runtime longer (30 min) |
| Bi-weekly | Scan log for sustained errors | Added; at this scale slow-burn bugs matter |
| First Sunday of quarter | `restore-drill` + update `RESTORE_MIN_*` | Same; don't skip minimum update |
| Per MM release | `update-mattermost` | Rehearse on CX22 first for minor/major |
| Annually | DR drill + SSH rotation | Same |

## Growth-related Phase 3 tasks

### Disk pressure at ~40% yellow

Usually `/opt/mattermost/data/` is growing. Migrate to R2 per Phase 2's
post-cutover guide section 5.4. One-time: ~2 hours; reclaims ~80% of disk
at a typical workspace.

### DB bloat at 18-24 months

`Posts` table grows monotonically. At ~20 GB DB size, enable `pg_repack`
quarterly (outside `restore-drill` week, to avoid pressure overlap).

### Connection pressure at 200+ users

Default `max_connections=200` hits ceiling if plugins / integrations add
background workers. Raise to 300-400 in Postgres config; requires restart
so schedule in next reboot window.

### File storage growth

R2 `mattermost-files` bucket grows ~5 GB/month at 500 users. Cost stays
trivial (<$5/mo). Enable R2 lifecycle to move very old attachments (>3
years) to cheaper storage tier if budget matters.

### Mattermost major upgrade

Every ~18 months a major ships. At this scale, **always** rehearse on a
scratch CX22 first. Cost: <$1 for the CX22 during rehearsal (cancel
after). Rehearsal catches 90% of upgrade-specific issues.

## When to consider HA / Mattermost Enterprise

Signs that the single-host + Phase 3 pattern is stretching:

- ≥ 500 peak concurrent users
- Downtime windows start to conflict with a > 24-hour workday (truly
  global team)
- Compliance requires a formal SLA
- Your team wants paid support

Mattermost Enterprise + HA setup is out of scope for this skill. See
the [Mattermost HA reference architecture](https://docs.mattermost.com/deployment/deployment.html#high-availability).

## Cost profile

- Hetzner AX52: ~$70/mo
- Cloudflare R2 (~150 GB): ~$3/mo
- Postmark (5,000 emails/mo average): $15/mo
- Hetzner Storage Box 1 TB: $4/mo
- **Total**: ~$92/mo at 250-1000 users

Against Slack Business+ at 1,000 users ($150k/yr): **saves $149k/yr**.

## Handoff considerations

Two operators means:

- Both need PATs.
- Both need SSH keys in `authorized_keys`.
- `ROLLBACK_OWNER` designates primary; backup operator can substitute if
  primary unreachable.
- Share `config.env` via a private repo (NOT public); each operator
  generates their own secrets during `rotate-credentials`.

## What breaks first as you scale

1. **Backup window** — pg_dump takes longer; at ~50 GB DB the dump is
   10-20 min, still fits nightly.
2. **Disk on root volume** — if attachments stayed local, they grow into
   the root partition. Move to R2.
3. **Connection count** — plugins + integrations fill connection slots.
4. **Reboot impact** — more users notice a 1-3 minute blip. Comms matter.

Phase 3 reports surface each of these before they're a crisis.
