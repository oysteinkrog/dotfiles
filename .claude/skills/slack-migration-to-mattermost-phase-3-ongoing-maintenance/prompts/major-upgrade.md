Walk me through a major Mattermost upgrade (e.g. 10.x → 11.x). Read
[references/workflows/MAJOR-UPGRADE-WORKFLOW.md](../references/workflows/MAJOR-UPGRADE-WORKFLOW.md).

This is a 2-hour-plus operation with serious risk. Take it slow.

Phase 1 — Rehearsal (T-7 days):
1. Read the release notes for the target major version. Summarize
   breaking changes, plugin API changes, schema migrations.
2. Order a Hetzner CX22 (I'll click through the signup).
3. Run Phase 2 `provision`/`deploy` against the CX22 with CURRENT
   Mattermost version.
4. Restore latest production backup into scratch host.
5. Run Phase 3 `update-mattermost` against CX22 with the NEW major pinned.
6. Verify green. Report runtime + any issues.
7. Cancel the CX22.

Phase 2 — Plan (T-3 days):
- Pick maintenance window (2-3 hours).
- Send T-7d / T-24h user comms from USER-COMMS-KIT.md.
- Confirm ROLLBACK_OWNER available.

Phase 3 — Day-of (T=0):
1. Fresh `./maintain.sh backup`. Verify off-site upload.
2. Post T-1h user comms.
3. Run `./maintain.sh update-mattermost` with target pinned. Stream the
   target's `mattermost.log` in a separate terminal.
4. Wait for completion (5-30 min).
5. Verify: `./maintain.sh health`, log in as admin, spot-check.

Phase 4 — Post-upgrade (T+30 min):
- Post "upgrade complete" user comms.
- Run `./maintain.sh db-health` (new version may stress the DB differently).

Phase 5 — Monitoring (next 24 hours):
- Watch error rate via `scripts/inspect-mattermost-log.py --window 1h`
  hourly for the first 6 hours, then at T+12h and T+24h.

Rollback if: ping fails to return, multiple new red health checks, many
user reports of login/post failures.
