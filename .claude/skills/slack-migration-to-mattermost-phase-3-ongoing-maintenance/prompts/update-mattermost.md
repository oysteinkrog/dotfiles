Bump Mattermost to a pinned version.

1. First: check the Mattermost release notes for patch versions newer than what's running. Tell me what's available and what's changed (bug fixes, security fixes, breaking changes).
2. Ask me to pick a target version. Set it in `config.env` as `MATTERMOST_TARGET_VERSION`.
3. Confirm the backup strategy: we want a fresh pg_dump immediately before the upgrade. Run `./maintain.sh backup` first; confirm it succeeded.
4. Run `./maintain.sh update-mattermost`. Watch `workdir-phase3/reports/latest-update-mattermost.json` for success / failure.
5. If status is `failed_rolled_back`, tell me what happened and that we're back on the previous version.
6. After success: run `./maintain.sh health` to confirm the upgraded server is green.

Refuse to run if `MATTERMOST_UPGRADE_ROLLBACK` is not set to `auto` and I haven't explicitly approved manual rollback.
