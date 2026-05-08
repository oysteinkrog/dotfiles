Upgrade a Mattermost plugin. Read [references/PLUGIN-LIFECYCLE.md](../references/PLUGIN-LIFECYCLE.md).

Tell me which plugin and which target version first. Typical candidates:
Playbooks, Boards, Calls, GitHub, Jira.

Procedure:

1. Confirm plugin is installed and current version. If MCP is registered,
   list plugins via MCP; else SSH + `mmctl plugin list`.
2. Fetch the plugin's release notes; check `minServerVersion` matches
   our Mattermost version.
3. Take a fresh `./maintain.sh backup` as a rollback base.
4. In System Console → Plugins → Management, disable the plugin (prevents
   crashes during install).
5. Install new version:
   - Via System Console if Marketplace has it.
   - Or upload the .tar.gz if installing a pinned version.
6. Enable the plugin.
7. Verify: `./maintain.sh health` green; spot-check the plugin's feature
   (post via Playbooks runbook, call via Calls, etc.).
8. Read `/opt/mattermost/logs/mattermost.log` for 10 min looking for
   plugin errors.

Rollback if:
- Plugin fails to enable (error in System Console)
- `mattermost_errors=red` in health after enabling
- Users report the plugin's UI is broken

Rollback procedure:
1. Disable the plugin.
2. Uninstall the new version.
3. Reinstall the previous version from whatever archive source you have.
4. Enable.

Never skip the backup step. Plugin installs can write to the DB.
