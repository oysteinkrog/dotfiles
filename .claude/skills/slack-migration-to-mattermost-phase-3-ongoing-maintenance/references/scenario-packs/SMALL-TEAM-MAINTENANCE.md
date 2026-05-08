# Scenario Pack — Small Team Maintenance (40-user workspace)

Concrete operational plan for a small workspace. Matches Alex Cohen's
profile from the guide: 40 users, Hetzner AX42, Postmark SMTP, Cloudflare
R2 backups.

## Profile

- **Users**: 40
- **Hardware**: Hetzner AX42 (~$50/mo)
- **DB**: local Postgres on same host
- **File storage**: Cloudflare R2
- **Off-site backups**: R2 bucket `mm-backups-acme`
- **DB size**: ~2 GB growing ~100 MB/month
- **Peak concurrent users**: 15
- **Operator**: one person, part-time
- **Time zone**: US Pacific (UTC-7/8)

## config.env defaults for this profile

```bash
WORKSPACE_NAME="acme-mm"
MATTERMOST_URL="https://chat.acme.com"
TARGET_HOST="chat.acme.com"
TARGET_SSH_USER="deploy"
POSTGRES_DSN="postgres://mmuser:<pw>@localhost:5432/mattermost?sslmode=disable"
BACKUP_PATH="/var/backups/mattermost"
OFFSITE_REMOTE="r2:mm-backups-acme"
SCRATCH_DB_URL="postgres://mmuser:<pw>@localhost:5432/mm_restore_drill?sslmode=disable"
OS_UPDATE_POLICY="security"
REBOOT_WINDOW_DAY="Sun"
REBOOT_WINDOW_HOUR_START="10"   # 10:00 UTC = 02:00-04:00 Pacific (off-hours)
REBOOT_WINDOW_HOUR_END="12"
ROLLBACK_OWNER="Alex <alex@acme.com>"
RESTORE_MIN_USERS="35"
RESTORE_MIN_CHANNELS="20"
RESTORE_MIN_POSTS="50000"
```

## Cadence

| Cadence | Stage | Time needed |
|---------|-------|-------------|
| Daily 10:00 UTC | `backup` (cron) | 0 min (automated) |
| Monday morning | Read latest-backup.json | 2 min |
| Sunday 10:00 UTC | `weekly-sweep` | 20 min agent runtime, 5 min operator read |
| First Sunday of quarter | `restore-drill` | 30 min |
| Per Mattermost release | `update-mattermost` | 30 min (plan + run + verify) |
| Annually | DR drill | 2-4 hours |

## Cost profile

- Hetzner AX42: $50/mo
- Cloudflare R2 (backups + files): ~$3/mo
- Postmark transactional email: $15/mo
- Hetzner Storage Box (optional 2nd backup copy): $4/mo
- **Total**: ~$72/mo

Compared to Alex's $21k/year Slack Business+ quote: **saves ~$20,000/year**.

## What's different at this scale

- Full restore from backup: ~2 minutes (small DB). Disaster recovery
  wall-clock is dominated by server provisioning (~30 min), not data
  restore.
- `db-health` is almost always green; bloat doesn't accumulate meaningfully
  at this scale.
- Backup size: ~200 MB compressed. Off-site transfer finishes in seconds.
- A 2-hour maintenance window is visible but not disruptive; post 24 hours
  ahead.

## Operator checklist for this profile

Weekly (Saturday or Sunday evening, 10 minutes):

- [ ] `./maintain.sh weekly-sweep`
- [ ] Read latest summary; green = done
- [ ] Glance at `latest-backup.json` (confirm last 7 nights all ok)
- [ ] If `reboot_required=yes`: `./maintain.sh schedule-reboot`

Monthly (30 minutes):

- [ ] Scan Mattermost release notes for new patch / minor
- [ ] If available + worth taking, schedule `update-mattermost` for the
      next Sunday's window
- [ ] Check Cloudflare bill for the month (unlikely to change)
- [ ] Check Postmark email volume (unlikely to hit plan cap)

Quarterly (1 hour):

- [ ] `./maintain.sh restore-drill`
- [ ] `./maintain.sh rotate-credentials` for PAT
- [ ] Review `workdir-phase3/contacts.md` and update if team changed

Annually (4 hours on a Saturday):

- [ ] Full DR drill: provision CX22, restore backup, verify
- [ ] Rotate SSH keys if any operator changed
- [ ] Rotate Cloudflare / Postmark / R2 tokens
- [ ] Review whether the AX42 is still right-sized (usually yes for <100
      users)

## When to upgrade tier

Move to AX52 when any of these is true:

- DB > 50 GB
- Peak concurrent users > 100
- Observed `pg_connections` regularly > 50% of max
- File storage (if local) > 200 GB

Phase 3 health reports give you the data to make this call.
