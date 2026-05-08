# Disaster Recovery Playbook

This is the manual playbook for "the production Mattermost server is gone or
corrupted beyond fixing in place." It assumes a recent off-site backup exists
(verified by the last `./maintain.sh restore-drill`) and a working Phase 2
skill install on your workstation.

The goal: a working Mattermost at the same URL, with user data intact, within
2 to 4 hours of the decision to rebuild.

## When to invoke this

- Host is unreachable and Hetzner/OVH/Contabo has confirmed hardware failure
- Filesystem corruption that fsck cannot repair
- Postgres data directory is corrupt and no point-in-time recovery is possible
- Host was compromised and you want a clean rebuild

Do not invoke for transient problems (reboot loop, hung process, full disk).
See [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) for the day-to-day fixes.

## Prerequisites the agent should confirm before starting

1. `./maintain.sh restore-drill` has run within the last 90 days and passed.
2. `workdir-phase3/reports/latest-restore-drill.json` shows the expected row
   counts and was signed by `ROLLBACK_OWNER`.
3. A Hetzner (or OVH, Contabo) account login is active for the operator.
4. The Phase 2 skill is installed and `./scripts/doctor.sh --require-remote`
   was green against the *old* host within the last 30 days.
5. `ROLLBACK_OWNER` has explicitly approved the rebuild path.

Without all five, stop and escalate.

## Playbook

### Phase D1. Declare + communicate (5 minutes)

- Post to `#ops` (or your internal comms) that Mattermost is down and a
  rebuild is in progress.
- Optional: put up a maintenance page on `chat.<domain>` via Cloudflare Pages
  (if your domain is on Cloudflare).

### Phase D2. Order replacement host (15 to 60 minutes wall-clock)

Paste to the agent:

> Order a replacement Mattermost host at Hetzner matching the current
> `TARGET_HOST` spec (AX42 or AX52, Ubuntu 24.04 LTS). Walk me through the
> signup form; I'll click through. Return the new IP when it's live.

The agent guides you through the signup. The clock is mostly Hetzner's
provisioning queue, not operator time.

### Phase D3. Point DNS at the new host (5 minutes)

Paste to the agent:

> Update the Cloudflare A record for chat.<domain> to the new IP. Keep
> proxy ON. Lower the TTL to 300 if it's currently higher. Show me the old
> and new values before applying.

### Phase D4. Provision + deploy (20 to 40 minutes)

Switch to the Phase 2 skill working directory. Edit `config.env.phase2` to
point `TARGET_HOST` / `ORIGIN_SERVER_IP` at the new IP. Then paste to the
agent:

> Run Phase 2 stages `provision`, `edge`, `deploy`, `verify-live` against
> the new host. Skip `staging` (we're rebuilding from production backup).
> Pause before each stage.

### Phase D5. Restore from backup (30 to 60 minutes, scales with DB size)

Switch back to the Phase 3 skill. Paste to the agent:

> Run `./maintain.sh restore-drill`, but targeting the NEW production DB
> instead of SCRATCH_DB_URL. Download the latest off-site backup, restore
> it into the new host's `mattermost` database, and show me the row counts
> when done.

Alternatively, if you have an on-host backup you trust more (more recent
than the off-site copy), the agent can SCP that file into the new host
directly and skip the off-site fetch.

### Phase D6. Verify + reactivate (10 minutes)

Paste to the agent:

> Run Phase 3 `health` stage and Phase 2 `verify-live`. Summarize the
> results. Also send a password-reset to my email (`admin@<domain>`) and
> confirm the reset link arrives.

Log into the new Mattermost in a browser, confirm the channel list, a
known post, and one file attachment are present.

### Phase D7. Close the loop (5 minutes)

- Post to `#ops` that Mattermost is back.
- Cancel the old Hetzner server (the dead one) to stop billing.
- File a post-mortem: capture the failure cause, how long the outage ran,
  and whether the backup strategy and restore-drill cadence worked.

## Expected data loss

**Best case**: the time window between the most recent backup and the
failure. If backups run nightly at 03:00 UTC, worst case is 24 hours of
posts lost.

**Mitigation**: enable more frequent backups (every 6 hours) during
known high-churn periods, and consider hot-standby replication if even
24 hours is unacceptable (that's outside this playbook; talk to a
dedicated DBA or Mattermost Enterprise).

## What the agent should NOT do without explicit approval

- Re-use the old host's IP (possible stale DNS + compromised state)
- Skip the `restore-drill` verification on the new host
- Re-enable the old host (even to "grab files") without a security review
- Publish the maintenance page wording without human review
