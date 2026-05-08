# Cross-Phase Intake Contract (Phase 2 → Phase 3)

Phase 3 accepts state produced by Phase 2. This doc is the "contract" —
what Phase 2 commits to leaving behind, and what Phase 3 expects to find.

## Inputs Phase 3 expects from Phase 2

### Files / artifacts

- `workdir-phase2/reports/latest-cutover-status.json` with `status=success`
  (proves cutover completed).
- `workdir-phase2/reports/latest-activation.json` with `reset_link_received=true`
  (proves SMTP activation path).
- Phase 2 `config.env` — Phase 3 reuses `TARGET_HOST`, `TARGET_SSH_USER`,
  `MATTERMOST_URL`, `POSTGRES_DSN`, SMTP settings, Cloudflare settings.

### Live state on TARGET_HOST

- Mattermost installed via APT (or Docker, in which case Phase 3 runs
  against the container; see [DOCKER-VS-APT.md](../../slack-migration-to-mattermost-phase-2-setup-and-import/references/DOCKER-VS-APT.md)).
- PostgreSQL available (local or managed) with `mattermost` database.
- Nginx + Cloudflare Origin CA cert at `/etc/nginx/ssl/origin.pem`.
- Non-root `deploy` user exists with `sudo -n` for specific commands.
- UFW + fail2ban + unattended-upgrades enabled.
- `BACKUP_PATH=/var/backups/mattermost` exists with 0700 perms.

### Credentials

- Operator has an admin PAT created post-deploy (recorded in Phase 2's
  credential inventory; see guide Part 10.12).
- Operator has SSH access as the `deploy` user with a known_hosts entry.
- Off-site backup credentials configured in rclone (or explicitly deferred
  and scheduled for Phase 3 setup).

## What Phase 3 produces and guarantees

### On first setup

- `config.env` reusing the Phase 2 values above, plus Phase-3-specific
  additions (`SCRATCH_DB_URL`, `REBOOT_WINDOW_*`, `HEALTH_*_*`, etc.).
- MCP registration via `scripts/install-mcp-servers.sh`.
- Initial baseline `health` + `db-health` reports.

### Ongoing

- Daily `latest-backup.json` with SHA-256 + off-site verify.
- Weekly `latest-health.json`, `latest-update-os.json`, `latest-db-health.json`.
- Quarterly `latest-restore-drill.json`.
- Per-upgrade `latest-update-mattermost.json` with pre-upgrade dump path.
- Annual DR drill post-mortem under `workdir-phase3/reports/dr/`.

## Incompatible states (Phase 3 refuses)

- `TARGET_HOST` unreachable → Phase 3 blocks on `doctor.sh --require-remote`.
- `MATTERMOST_ADMIN_TOKEN` invalid → same.
- Mattermost < 10.11 → `[Q-DEP-001]` / `[Q-UPG-002]`; upgrade first.
- PostgreSQL major < 13 → upgrade first (Mattermost 10.x minimum).
- `/var/backups/mattermost` not writable → Phase 2 `provision` didn't
  complete; re-run Phase 2 `provision`+`deploy`.

## Handoff walkthrough (for a fresh Phase 3 setup)

1. Copy `slack-migration-to-mattermost-phase-2-setup-and-import/config.env`
   to `slack-migration-to-mattermost-phase-3-ongoing-maintenance/config.env`
   and rename variables that are Phase 3-specific.
2. Add the Phase-3-only variables: `OFFSITE_REMOTE`, `SCRATCH_DB_URL`,
   `REBOOT_WINDOW_*`, `ROLLBACK_OWNER` (if different from Phase 2's).
3. Verify Phase 2 post-cutover reports are still on disk (Phase 3 may read
   them for context; see `prompts/orient.md`).
4. Run `./scripts/doctor.sh --require-remote --require-mcp`.
5. Run `./maintain.sh health` to take a baseline.

Phase 3 is then the steady-state operator; Phase 2 retires until the next
major cutover event.

## Cross-phase secret rotation

When Phase 3 rotates credentials (PAT, SSH key, off-site token), Phase 2's
config becomes stale. If a future Phase 2 re-run is ever needed (e.g. to
re-import a delta batch), the operator must update Phase 2's config.env
to match the current Phase 3 state. This is handled by the
`rotate-credentials` stage writing an "also update Phase 2 config.env"
reminder in its audit trail.
