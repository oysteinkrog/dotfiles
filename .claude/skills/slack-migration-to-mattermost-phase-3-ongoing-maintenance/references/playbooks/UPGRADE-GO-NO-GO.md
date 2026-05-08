# Upgrade Go / No-Go

Decision tree for whether to run `./maintain.sh update-mattermost` right now.

## Preconditions (all must be true)

- `MATTERMOST_TARGET_VERSION` is pinned to a specific release (never empty,
  never "latest").
- The release notes for the target version have been read. Agent prompt:
  *"Fetch the Mattermost release notes for version X. Summarize: security
  fixes, deprecations, schema changes, breaking changes, plugin API
  changes."*
- Last `./maintain.sh restore-drill` was within 90 days and passed.
- `./maintain.sh backup` ran in the last 24 hours and passed.
- `./maintain.sh health` is currently green or yellow.
- For minor or major bumps: rehearsal done on a scratch copy (spin up a
  Hetzner CX22, restore the latest backup into it, run `update-mattermost`
  there first).

## Severity → cadence

| Release type | Example | Max delay after publication |
|--------------|---------|------------------------------|
| Security patch | `10.11.1 → 10.11.2` with CVE fix | 72 hours |
| Regular patch | `10.11.1 → 10.11.2` bug fixes only | 1 week |
| Minor | `10.11 → 10.12` | 30 days |
| Major | `10.x → 11.x` | 90 days (only after rehearsal) |

## Gate decisions

### GO if...

- preconditions all met, AND
- the release fits its severity cadence window, AND
- you have a 30-minute downtime window available (for rollback + manual
  investigation if auto-rollback triggers), AND
- `ROLLBACK_OWNER` is available to be paged within 30 minutes.

### NO-GO if...

- a precondition fails. The fix is to address the precondition (take a
  backup, run a restore-drill, etc.), not to waive it.
- the release notes flag a plugin API change and your deployment uses a
  third-party plugin that has not been confirmed compatible.
- a major version bump has not been rehearsed on a scratch copy.
- the cluster is in INCIDENT RESPONSE state. Stabilize first.
- `health` is red.

## Rollback procedure

Automatic (default when `MATTERMOST_UPGRADE_ROLLBACK=auto`):

1. `update-mattermost` detects post-upgrade `/api/v4/system/ping` does not
   return 200 within 3 minutes.
2. Script stops Mattermost.
3. `apt-get install --allow-downgrades mattermost=<previous>` reinstalls
   the prior version.
4. `gunzip -c pre-upgrade-<ts>.sql.gz | psql mattermost` restores the
   pre-upgrade database dump.
5. Starts Mattermost; pings until 200 or operator intervention.

Manual rollback (when auto fails):

1. SSH to target.
2. `sudo systemctl stop mattermost`.
3. `apt list --installed mattermost` to confirm current version.
4. `sudo apt-get install --allow-downgrades mattermost=<previous-version>`.
5. `sudo -u postgres dropdb mattermost && sudo -u postgres createdb mattermost`.
6. `gunzip -c /var/backups/mattermost/pre-upgrade-<ts>.sql.gz | sudo -u postgres psql mattermost`.
7. `sudo systemctl start mattermost`.
8. Wait for ping.

If the manual rollback also fails (rare: both the new version and the old
version refuse to start with the dump), escalate per [../comms/ESCALATION-LADDER.md](../comms/ESCALATION-LADDER.md).

## Post-upgrade checks

- `./maintain.sh health` — green or yellow expected.
- Spot-check a plugin if any: System Console → Plugins → verify status ok.
- Log in as a non-admin user in a browser: check you can post, receive
  messages in real-time, see file attachments.
- Monitor `/opt/mattermost/logs/mattermost.log` for error bursts in the
  first hour. Use `scripts/inspect-mattermost-log.py --window 1h` for an
  agent-readable summary.

## When to escalate major upgrades to Mattermost Enterprise support

- Multi-year deferred upgrade chains (e.g. `8.x → 11.x` across multiple
  majors in one shot).
- Schema migrations that estimate > 4 hours on production DB size.
- HA / clustered deployments.
- Plugins developed in-house with tight coupling to Mattermost internals.

For these, buy Professional Edition + a support plan. The $10/user/month
tag is cheap insurance when the change set is large.
