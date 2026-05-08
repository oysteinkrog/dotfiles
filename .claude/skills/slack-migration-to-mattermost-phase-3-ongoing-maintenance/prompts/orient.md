Use the Phase 3 ongoing-maintenance skill to orient on this deployment.

1. Read `config.env` (or `$PHASE3_CONFIG`). Confirm: MATTERMOST_URL, TARGET_HOST, MATTERMOST_ADMIN_TOKEN present, ROLLBACK_OWNER set.
2. Run `./scripts/doctor.sh`. Walk me through any red required items.
3. `ls -la workdir-phase3/reports/` and read the newest `latest-*.json` files. Tell me: when did we last take a backup, when did we last upgrade Mattermost, when did we last run a restore-drill, when did we last apply OS updates.
4. Recommend the next move: is there maintenance due this week? Any alerts from the most recent health check?

Do not run any stage without explicit approval.
