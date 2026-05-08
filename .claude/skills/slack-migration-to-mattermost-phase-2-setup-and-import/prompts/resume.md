I'm picking up a migration that's already partially run. Figure out where we are.

1. Read `config.env` (or `$PHASE2_CONFIG`) — confirm target URL, admin creds present, handoff path valid.
2. `ls -la workdir-phase2/reports/` — enumerate reports and their timestamps.
3. Read `workdir-phase2/reports/latest-staging.json`, `latest-smoke.json`, `latest-reconciliation.json`, `latest-activation.json`, `latest-restore.json` (any that exist), plus the newest `workdir-phase2/reports/cutover/cutover-status.*.json` if it exists. Tell me what the last successful stage was and whether the current state is consistent.
4. Check if the live stack is actually up: `curl -fsS "$MATTERMOST_URL/api/v4/system/ping"`.
5. Recommend: re-run a specific stage, proceed to the next, or investigate a specific red report.

Do not run cutover or rollback without explicit operator go.
