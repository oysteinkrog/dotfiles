# Mattermost upgrade strategy

## Cadence

- **Patch releases** (e.g. 10.11.1 → 10.11.2): apply within a week of publication if the release notes mention any security fix.
- **Minor releases** (e.g. 10.11 → 10.12): apply within a month, after reading the upgrade notes for deprecations and breaking changes.
- **Major releases** (e.g. 10.x → 11.x): apply within a quarter, and only after:
  - reading the full upgrade guide for the new major
  - running the upgrade on a staging copy of production first (spin up a throwaway Hetzner CX22 and restore the latest backup into it; point the Phase 3 skill at the staging copy)
  - getting explicit approval from `ROLLBACK_OWNER`

## Pinning

Always pin a version in `MATTERMOST_TARGET_VERSION` before running the upgrade. Never upgrade "to latest" blind; the apt package's `latest` pointer can move under you and you lose determinism.

## Pre-upgrade checklist

1. `./maintain.sh health` — green overall.
2. `./maintain.sh backup` — success, verified, off-site.
3. `./maintain.sh restore-drill` result within 90 days — passed.
4. Read the target version's release notes.
5. For minor/major bumps, run an upgrade on a staging copy first and verify users / channels / posts counts.
6. Announce a 15-minute maintenance window to users (optional for patch releases, required for minor/major).

## What the upgrade script does

1. Records the current version via the running server's `/api/v4/config/client?format=old`.
2. Takes a fresh `pg_dump` (separate from the nightly backup) to `BACKUP_PATH/pre-upgrade-<timestamp>.sql.gz`.
3. `sudo systemctl stop mattermost` — downs the service cleanly.
4. `apt-get install -y mattermost=<version>` — installs the target version.
5. `sudo systemctl start mattermost` — the Mattermost process handles any DB migrations automatically on startup.
6. Polls `/api/v4/system/ping` for up to 3 minutes waiting for a 200.
7. Confirms the running version matches target.

On any failure, if `MATTERMOST_UPGRADE_ROLLBACK=auto`:
- Reinstall the previous version via `apt-get install --allow-downgrades mattermost=<prev>`
- Restore from `pre-upgrade-<timestamp>.sql.gz`
- Restart the service

## Things that go wrong, and fixes

- **Long migration**: some major upgrades include heavy DDL. Don't kill the service; the upgrade script's 3-minute poll will time out but the migration continues in the background. Tail `/opt/mattermost/logs/mattermost.log` and wait. After it finishes, re-ping manually.
- **Plugin incompatibility**: a plugin pinned to an older API breaks. Disable the plugin in System Console → Plugins → Management → Deactivate, upgrade Mattermost, then re-enable (or upgrade the plugin).
- **Config.json schema change**: upgraded Mattermost rejects the old config. The rollback restores the old binary which accepts the old config; then check the release notes for a migration flag.
- **Disk pressure from the pre-upgrade dump**: the dump is usually 20 to 40% of raw DB size. Make sure `BACKUP_PATH` has headroom before running.

## Downgrading

Never downgrade across major versions without vendor guidance. Postgres schema changes between majors can be one-way. The script's auto-rollback only supports patch and minor downgrades where the schema didn't change.
