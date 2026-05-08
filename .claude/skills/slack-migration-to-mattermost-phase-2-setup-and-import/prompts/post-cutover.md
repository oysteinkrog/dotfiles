Drive post-cutover operations.

T+0 to T+4h:
- Monitor import job final state, activation proof, help-desk bucket.
- Check `mmctl user list --all --json | jq 'length'` vs handoff user count.

T+24h:
- Count activated users (users with `last_activity_at > 0`). If <50%, send reminder (reference USER-COMMS-KIT.md).
- Skim `integration-inventory.md` for Slack integrations we need to rebuild. Start creating Mattermost webhooks/slash commands.

T+7d:
- Revoke Slack migration app tokens, delete the Slack admin app, archive workdirs.
- Write the retrospective (what went right, what to do differently).
- Remove any emergency MaxPostSize/OpenServer flags that are no longer needed.

Ask me before each "send announcement" or "revoke tokens" step.
