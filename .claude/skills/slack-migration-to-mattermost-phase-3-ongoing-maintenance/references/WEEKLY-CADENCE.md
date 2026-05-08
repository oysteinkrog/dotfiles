# Recommended maintenance cadence

Ongoing Mattermost maintenance is deliberately boring. The skill's whole point is to automate the mechanical parts and make "everything's fine" the default outcome.

## Daily (automated, unattended)

**Backup at 03:00 UTC**. Run as a scheduled agent job or `cron` on your workstation:

```bash
0 3 * * * cd ~/mattermost-ops && ./maintain.sh backup >> /var/log/mm-backup.log 2>&1
```

Check `latest-backup.json` on Monday morning to confirm the weekend runs succeeded.

## Weekly (Saturday night, ~20 minutes attention)

Paste [weekly-sweep.md](../prompts/weekly-sweep.md) to the agent. The sweep does:

1. `health` — live status snapshot
2. `update-os` — security patches
3. `backup` — pg_dump + off-site
4. `db-health` — sizing + bloat snapshot

If `reboot_required=yes`, follow up with `./maintain.sh schedule-reboot`. The reboot lands in the next configured off-hours window; users won't notice unless they try to post during the 1 to 3 minute window.

## Monthly (first Saturday of the month, ~30 minutes)

- Review the last 4 weekly-sweep reports side by side. Any trends in disk growth, DB size, connection count, error rate?
- Check Mattermost release notes (https://mattermost.com/changelog). Any security-flagged releases? Schedule an `update-mattermost` for the next weekly sweep.
- Skim `mattermost.log` for repeating warnings you've been ignoring.

## Quarterly (first weekend of the quarter, ~60 minutes)

- **Run a restore-drill.** This is the single most important recurring task after backups themselves. Paste [restore-drill.md](../prompts/restore-drill.md).
- Audit `RESTORE_MIN_*` values against current row counts.
- Confirm the off-site backup destination's retention policy still matches yours.
- Review credentials: are all SSH keys still authorized? Has any operator rotated? Any stale PATs in Mattermost?

## Annually

- Upgrade Ubuntu LTS if a new LTS has released and stabilized (at 24.04.2+ or equivalent).
- Review Hetzner server sizing. If the workspace has doubled, consider an AX52 → AX62 bump.
- Rotate the Mattermost admin PAT and the off-site backup token.
- Reconsider off-site backup redundancy: is R2 still enough, or do you want a second provider?

## Unscheduled triggers

**Run `./maintain.sh health` when**:
- Users report Mattermost is slow, unresponsive, or silent
- Cloudflare alerts for the domain
- You got a "$TARGET_HOST disk >85%" email
- After any config change (config.json, nginx.conf)

**Run `./maintain.sh backup` when**:
- Before any `update-mattermost`
- Before any `/opt/mattermost/config/config.json` edit
- Before any DB migration (plugin install, schema change)

**Run `./maintain.sh restore-drill` when**:
- You've changed the backup destination or retention policy
- You've changed the backup schedule
- More than 90 days have elapsed since the last drill
- A restore-drill has failed and you think you've fixed the issue
