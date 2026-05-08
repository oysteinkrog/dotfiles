# Workflow — Major Mattermost Upgrade

E.g. 10.x → 11.x. Treated much more carefully than patch / minor bumps.

## Prerequisites

- Last `restore-drill` passed within 14 days (not 90; tighten for majors).
- Last `backup` within 6 hours.
- A scratch host (Hetzner CX22, ~€0.10 for the duration).
- Read the Mattermost upgrade guide for the target major (look for
  breaking changes, plugin API changes, schema migrations).
- `ROLLBACK_OWNER` available and aware.
- 2-3 hour maintenance window available.

## Phase 1 — Rehearse on scratch host (T-7 to T-3 days)

1. Order Hetzner CX22 (~€4/mo, but cancel right after; effective cost
   ~€0.10).
2. Point `staging-dr.chat.<domain>` at it (or use IP directly).
3. Copy Phase 2 `config.env` to the scratch host context, tweak for
   scratch.
4. Run Phase 2 `provision` + `deploy` on the scratch host with the
   **current** Mattermost version.
5. Restore latest backup into scratch host's PG.
6. Verify: Phase 2 `verify-live` + Phase 3 `health` against scratch.
7. Now the rehearsal proper: run Phase 3 `update-mattermost` against
   scratch with the new major pinned.
8. Observe migration runtime, any errors, plugin compatibility.
9. Verify post-upgrade: `health`, log in as admin, spot-check a few
   channels.

**Pass criterion**: everything green on scratch. Cancel scratch host.

## Phase 2 — Plan (T-3 to T-1 days)

- Pick maintenance window (2-3 hours; production).
- Send T-7d / T-24h comms per [comms/USER-COMMS-KIT.md](../comms/USER-COMMS-KIT.md).
- Confirm `ROLLBACK_OWNER` available on the day.
- Freeze other changes (no config edits, no plugin installs) in the 48
  hours before.

## Phase 3 — Day-of (T = 0)

1. Fresh backup: `./maintain.sh backup`. Verify success and off-site
   upload.
2. Post T-1h comms: maintenance starting.
3. Run `./maintain.sh update-mattermost` with target pinned.
4. Watch log tail in a separate terminal:
   `ssh $TARGET sudo tail -f /opt/mattermost/logs/mattermost.log`
5. Wait for `update-mattermost` to complete. Expect 5-30 min depending
   on DB size and migration scope.
6. Verify: `./maintain.sh health`, log in as admin, spot-check.

## Phase 4 — Post-upgrade verification (T+0 to T+30 min)

- `./maintain.sh health` green.
- Log in as admin; verify System Console loads.
- Log in as a non-admin test user; post a message, receive real-time.
- Check plugin status: all plugins should be "running" (or explicitly
  disabled if you disabled them pre-upgrade).
- Read `/opt/mattermost/logs/mattermost.log` tail for 10 min.

## Phase 5 — Communications (T+30 min)

Post "upgrade complete" message. Include:
- New version
- Any visible user-facing changes
- Link to full release notes for curious users

## Phase 6 — Monitoring (T+1 to T+24 hours)

- Monitor error rate closely.
- Watch for user reports in `#support` or ops channel.
- Run `./maintain.sh db-health` at T+12 hours; new version may have
  different DB access patterns.

## Rollback triggers

During or immediately after:
- `/api/v4/system/ping` doesn't return 200 within 3 minutes of apt install
- Health reports multiple red checks that weren't red before
- Large numbers of users reporting login / post failures
- Evidence of data corruption (very rare)

If auto-rollback doesn't complete cleanly, follow manual rollback in
[playbooks/UPGRADE-GO-NO-GO.md](../playbooks/UPGRADE-GO-NO-GO.md).

## Things that often go wrong on majors

- **Plugin API breaking change.** Disable incompatible plugins before
  upgrading, upgrade plugin versions after.
- **Long schema migration.** Mattermost's `Posts` table can be huge;
  some migrations iterate it. Plan for 20-60 min of additional downtime
  beyond the apt install.
- **config.json rejected.** The new major may require a config schema
  change. Compare old config against new defaults; your `config.json`
  may need fields added or removed.
- **Postgres major version requirement.** Mattermost 11.x may require
  PG 15+; if you're on 13, a separate PG upgrade is required first.

## After settling in (T+1 week)

- Tighten `MATTERMOST_TARGET_VERSION` to the current patch.
- Update any docs / runbooks that reference version-specific behavior.
- Write a brief post-mortem of the upgrade (even when it went well):
  what took longer than expected, what surprised you.

## Related

- [../playbooks/UPGRADE-GO-NO-GO.md](../playbooks/UPGRADE-GO-NO-GO.md)
- [../diagnostics/UPGRADE-DIAGNOSTICS.md](../diagnostics/UPGRADE-DIAGNOSTICS.md)
- [../MATTERMOST-VERSIONING-POLICY.md](../MATTERMOST-VERSIONING-POLICY.md)
