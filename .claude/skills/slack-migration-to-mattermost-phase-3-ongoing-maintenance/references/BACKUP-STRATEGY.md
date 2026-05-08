# Backup strategy

## What the skill backs up

- **Postgres**: full logical dump via `pg_dump --no-owner --no-privileges` piped through gzip. Covers the `mattermost` database completely.

## What the skill does NOT back up

- **File attachments** if stored locally at `/opt/mattermost/data/`. If you store attachments locally, add a separate rclone job to sync that directory; or, better, move file storage to Cloudflare R2 (see Phase 2's post-cutover guide, section 5.4). R2 gives you multi-region durability for free.
- **Mattermost config.json**. Render it from source via Phase 2's `render-config` stage if you ever need to rebuild. Keep a copy checked in to a private git repo.
- **Nginx and Postgres server configs**. Same approach: keep the Phase 2 rendered versions as the source of truth.
- **SSH host keys** of the target. These are ephemeral; if the server is rebuilt, your client will accept the new fingerprint once.

## Retention

Default tiered retention (configurable in `config.env`):

- **Daily dumps**: last 30 days (one per day)
- **Weekly dumps**: last 12 weeks (first dump of each week)
- **Monthly dumps**: last 12 months (first dump of each month)

Total storage footprint for a 340-user workspace: approx 50 GB of compressed dumps across all tiers. At Hetzner Storage Box 1 TB (€4/mo) this is comfortable.

## Off-site destinations

Any rclone remote works. Recommended:

- **Cloudflare R2**: `~$0.015/GB/month storage, zero egress`. Cheapest for active use cases.
- **Hetzner Storage Box**: €4/mo for 1 TB, SFTP-based, simple. Good second copy.
- **AWS S3 Glacier Deep Archive**: ~$0.001/GB/month but high egress and retrieval cost. Only makes sense for truly cold archives.

Configure two remotes for redundancy:

```
OFFSITE_REMOTE="r2:mm-backups-acme"
OFFSITE_REMOTE_2="hetzner-storagebox:mm-backups"   # advisory, not used by the skill yet
```

The skill currently uploads to one `OFFSITE_REMOTE`. A nightly `rclone sync r2:mm-backups-acme hetzner-storagebox:mm-backups` handled separately gives you the second copy cheaply.

## Integrity

Every backup is SHA-256 hashed before upload. After upload, the skill re-reads the remote copy's hash file and compares. A mismatch marks the run failed and skips rotation (so you keep the previous good copy).

## Encryption

By default, backups are unencrypted. If Mattermost contents are sensitive enough to warrant at-rest encryption (HIPAA, financial data), configure `rclone crypt` on the backend; the skill doesn't need to know about it, the encryption is transparent at the rclone remote level.

## What to verify during a quarterly restore-drill

- `pg_restore` exit code is 0
- Row counts for `users`, `channels`, `posts` meet or exceed `RESTORE_MIN_*`
- A known post ID exists after restore (optional; configure `RESTORE_SPOT_CHECK_POST_ID`)
- Total elapsed restore time is within acceptable bounds for DR purposes

If any of these fails, treat it as a production incident: backups are your last line of defense, and the skill will refuse to auto-run an `update-mattermost` if the most recent drill is failed or missing.
