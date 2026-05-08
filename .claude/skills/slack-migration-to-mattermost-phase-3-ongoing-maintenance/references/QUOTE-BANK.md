# Phase 3 Quote Bank

Load-bearing rules trace back to anchors in Mattermost docs, PostgreSQL docs,
or prior incident notes. Operator cards in [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md)
cite these `[Q-*]` tags. Agents treat the quote bank as authoritative over
ad-hoc reasoning; if an anchor disappears, retire the rule.

## Backups

- `[Q-BAK-001]` *pg_dump is safe on a live Mattermost* :: Mattermost docs, Backup guide :: "pg_dump is a consistent online backup; no downtime required."
- `[Q-BAK-002]` *An un-restored backup is not a backup* :: industry SRE convention :: quarterly restore-drill is the canary.
- `[Q-BAK-003]` *Mattermost file storage needs its own backup if local* :: Mattermost docs, File Storage :: `pg_dump` covers the DB only; `/opt/mattermost/data/` if local-stored must be synced separately (R2 avoids this).
- `[Q-BAK-004]` *Retention follows 3-2-1* :: industry standard :: 3 copies, 2 media types (local + off-site), 1 off-site.

## Upgrades

- `[Q-UPG-001]` *Pre-upgrade pg_dump is mandatory* :: Mattermost Upgrade guide :: "Take a backup before upgrading."
- `[Q-UPG-002]` *Mattermost 10.5 ESR reached end of life in November 2025* :: source doc + Mattermost releases :: must be on 10.11+.
- `[Q-UPG-003]` *Patch releases are within-minor and low-risk* :: Mattermost release policy :: `10.11.1 → 10.11.2` rarely requires staging.
- `[Q-UPG-004]` *Minor releases may include schema migrations* :: Mattermost changelog :: `10.11 → 10.12` should be rehearsed on a scratch copy.
- `[Q-UPG-005]` *Major releases require staging rehearsal* :: Mattermost docs :: `10.x → 11.x` is non-negotiably staged.
- `[Q-UPG-006]` *Auto-rollback requires a pre-upgrade dump + previous version pinned in apt* :: `mattermost-upgrade.sh` contract :: without both, rollback is manual.

## Database

- `[Q-DB-001]` *Mattermost needs Postgres 13+ for 10.x and 15+ for 11.x* :: Mattermost docs, Supported Versions :: pin PG major version when planning Mattermost major upgrade.
- `[Q-DB-002]` *Autovacuum is on by default and usually sufficient* :: PostgreSQL docs :: only intervene when `n_dead_tup` outpaces `autovacuum_vacuum_scale_factor`.
- `[Q-DB-003]` *pg_repack over VACUUM FULL for bloat* :: PostgreSQL performance docs :: VACUUM FULL takes an exclusive lock; pg_repack does not.
- `[Q-DB-004]` *pgvector not used by stock Mattermost* :: inspection :: do not install pgvector just because it's trendy; no Mattermost feature needs it.

## Patching & reboots

- `[Q-PATCH-001]` *unattended-upgrades handles security updates* :: Debian docs :: Phase 2 `provision` enabled it; Phase 3 `update-os` triggers on-demand.
- `[Q-PATCH-002]` *Kernel updates require reboot to take effect* :: Linux convention :: `/var/run/reboot-required` is the authoritative signal.
- `[Q-PATCH-003]` *Reboots should land in an off-hours window* :: industry convention :: Phase 3 `schedule-reboot` uses `at` + configured window.
- `[Q-PATCH-004]` *Do not autoremove with --purge on the running kernel* :: Debian convention :: could remove the kernel you're running.

## Live stack

- `[Q-LIVE-001]` *`/api/v4/system/ping` is the canonical health endpoint* :: Mattermost API docs :: should return 200 + `{"status":"OK"}`.
- `[Q-LIVE-002]` *WebSocket upgrade is required for real-time* :: Mattermost docs, Nginx guide :: a working 200 ping + broken WebSocket is a visible-to-users regression.
- `[Q-LIVE-003]` *Cloudflare Origin CA has 15-year lifetime* :: Cloudflare docs :: expiry monitoring lives at the annual cadence, not weekly.
- `[Q-LIVE-004]` *Let's Encrypt certs expire every 90 days* :: LE docs :: if you use LE at origin, auto-renewal must be wired up and verified.

## Security

- `[Q-SEC-001]` *Rotate PAT quarterly* :: industry convention :: 90-day rotation on a token that has full admin reach.
- `[Q-SEC-002]` *Never commit config.env to git* :: Phase 3 threat model :: `.gitignore` excludes it; secret-scanner runs on reports.
- `[Q-SEC-003]` *SSH key rotation on operator change is non-negotiable* :: least-privilege principle :: offboarding an operator means rotating, not trusting.
- `[Q-SEC-004]` *fail2ban + UFW stay enabled post-cutover* :: hardening convention :: Phase 3 `health` verifies both services weekly.

## Operations

- `[Q-OPS-001]` *Rollback owner must be named before destructive ops* :: Phase 2 `[Q-OPS-001]` carries into Phase 3 :: `update-mattermost` and `disaster-recovery` both require it.
- `[Q-OPS-002]` *Every report carries a SHA-256 where a payload is included* :: Phase 2 `[Q-OPS-002]` carries into Phase 3 :: backups, dumps, uploads.
- `[Q-OPS-003]` *Fail closed on stage gates* :: Phase 3 contract :: `update-mattermost` refuses without a recent restore-drill.

## Using the bank

Add new rules with a `[Q-*]` tag. Remove stale entries when their anchor
moves or the rule is superseded. If a quote's anchor disappears,
`† Theory-Kill` the rule rather than leaving it orphaned.
