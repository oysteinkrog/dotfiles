Roll back a failed production cutover. This is DESTRUCTIVE — it restores the DB and optionally /opt/mattermost/{config,data}.

1. Confirm with me: we're actually rolling back, not fixing in place. Once you run this, new messages sent after the pre-cutover backup are lost.
2. Confirm `ROLLBACK_DB_BACKUP` points at the right pre-cutover PG dump.
3. Run: `ROLLBACK_CONFIGURATION="I_UNDERSTAND_THIS_RESTORES_BACKUPS" ./operate.sh rollback`. The phrase is required verbatim.
4. After: unfreeze Slack, tell users we're rolling back, commit to a new date.
5. Save the rollback artifact tree — we'll want it for the retrospective.
