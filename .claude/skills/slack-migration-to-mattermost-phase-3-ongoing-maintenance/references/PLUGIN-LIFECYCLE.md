# Plugin Lifecycle

Plugins are the highest-variance piece of Mattermost operation. They
upgrade on their own cadence, break on their own schedule, and often
maintain themselves poorly. Treat them with skepticism.

## Categories

| Category | Examples | Upgrade cadence | Risk |
|----------|----------|-----------------|------|
| First-party core | GitHub, JIRA, AWS SNS | Aligned with Mattermost releases | Low |
| First-party optional | Playbooks, Boards, Calls | Own release train | Medium |
| Community / third-party | Various | Random | High |
| Custom / in-house | Anything your team built | Your cadence | Whatever you make it |

## Install / upgrade policy

1. **Pin version.** Never "install latest" via the marketplace.
2. **Rehearse first.** On a minor/major plugin upgrade, rehearse on a
   scratch copy before production.
3. **Backup before.** `./maintain.sh backup` is mandatory before any
   plugin install or upgrade.
4. **Disable stale plugins.** Plugins you stopped using should be
   disabled (not just ignored); each plugin is an attack surface.

## When Mattermost upgrades break a plugin

Mattermost minor versions occasionally break the plugin API. If `update-mattermost`
leaves a plugin non-functional:

1. In System Console → Plugins → Management, disable the plugin.
2. Verify Mattermost health is green without it.
3. Check the plugin's changelog for a new version compatible with your
   new Mattermost version.
4. Install the compatible version, enable, verify.

If no compatible version exists:
- Stay on the older Mattermost until the plugin catches up, OR
- Drop the plugin.
- Never patch the plugin in-place to "make it work"; you lose upgrade
  path.

## Playbooks / Boards / Calls specifics

| Plugin | Hosts data in | Separate backup? |
|--------|---------------|------------------|
| Playbooks | Mattermost PG | No; pg_dump covers it |
| Boards | Mattermost PG (since consolidation) | No |
| Calls | Stateless, UDP flows | No data to back up |

Calls plugin requires:
- UDP 8443 open through UFW (Phase 2 did this)
- DNS-only (grey-cloud) record for `calls.your-domain`
- `ICEHostOverride` set to your public IP in Calls config
- Phase 3's `calls-plugin-health.sh` probes this weekly

## Custom plugins (in-house)

If you built a plugin:

- Treat it like any other Go / TypeScript service.
- Pin Mattermost server API version in your build; test against each
  Mattermost minor before deploying.
- Keep source in your own git repo; the plugin binary in Mattermost's
  System Console is installed from an uploaded .tar.gz.
- Run its unit tests in CI.
- Don't couple it to Mattermost internals that aren't public API.

## Disabling vs uninstalling

- **Disable**: plugin stays installed, tables stay in DB, data stays.
  Reversible instantly.
- **Uninstall**: plugin removed from Mattermost. Data in the plugin's
  key-value store and tables may remain orphaned.

Default to disable first, then uninstall later if you're sure.

## Discovery of installed plugins

Via MCP: *"List all Mattermost plugins with their state."*

Via CLI: `mmctl plugin list`

Via HTTP: `GET /api/v4/plugins` with PAT.

## Phase 3 touchpoints

- `health-check.sh` verifies Mattermost service is up, which implicitly
  verifies plugin loader didn't crash.
- `update-mattermost` asks the operator to review plugin compatibility
  from release notes before running.
- `db-bloat-auditor` may flag plugin-owned tables with bloat.

## When a plugin goes wrong in production

See [playbooks/INCIDENT-RESPONSE.md](playbooks/INCIDENT-RESPONSE.md)
"mattermost_errors=red" plus:

```bash
ssh $TARGET sudo tail -n 200 /opt/mattermost/logs/mattermost.log | grep -i plugin
```

Most plugin crashes show `level=error plugin_id=com.example.foo msg="..."`.
Disable the plugin in System Console; verify Mattermost stabilizes.
