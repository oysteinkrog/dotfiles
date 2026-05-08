PRODUCTION CUTOVER. Only run this when the war room has explicitly called go AND `./operate.sh ready` is green on the latest handoff.

1. Before running anything: confirm `cutover-readiness.json.status == "ready"` NOW (not from a stale run).
2. Confirm Slack is frozen (Workspace Settings → Permissions → posting disabled for everyone except admins).
3. Confirm the war room is watching. Do NOT proceed without explicit operator go.
4. Run `./operate.sh cutover`. Each run writes a timestamped `workdir-phase2/reports/cutover/cutover-status.<timestamp>.json`. Find the newest with `ls -t workdir-phase2/reports/cutover/cutover-status.*.json | head -1`.
5. Post-import: confirm smoke tests green (`workdir-phase2/reports/latest-smoke.json`), reconciliation green (`workdir-phase2/reports/latest-reconciliation.json`), SMTP activation proof at `workdir-phase2/reports/latest-activation.json` (password-reset email arrives at `SMTP_TEST_EMAIL`).
6. If the newest `cutover-status.*.json` has `"status": "failed"`: stop. Read the `note` field. Decide with me: fix in place or roll back.
