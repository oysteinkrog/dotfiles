Use the Phase 2 skill to run the `staging` stage.

IMPORTANT: This targets a STAGING Mattermost, not production. The skill refuses to run against URLs that look like prod unless `ALLOW_NON_STAGING=1`. Set `STAGING_URL=https://staging.chat.acme.com` (or localhost) first.

1. Run `./operate.sh staging`. This does: mmctl auth login, import upload, import process, monitor-import polling, post-import smoke tests, reconciliation against handoff.
2. Watch `workdir-phase2/reports/import-watch.*.jsonl` stream. If stuck in `pending` > 10 min, check `/opt/mattermost/logs/mattermost.log` on the staging host.
3. After success: open `workdir-phase2/reports/latest-staging.json` (operate.sh keeps a `latest-*.json` convenience copy next to the timestamped originals). Verify `status=success` and observed counts match `handoff.json.counts` within tolerance. Also glance at `latest-smoke.json` and `latest-reconciliation.json` in the same directory.
4. If counts off: stop, tell me whether to re-run or go back to Phase 1.
