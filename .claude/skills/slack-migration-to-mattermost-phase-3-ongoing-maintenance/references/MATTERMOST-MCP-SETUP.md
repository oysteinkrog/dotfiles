# Mattermost MCP Setup

The Mattermost MCP server lets the Claude Code / Codex agent drive the
admin API without shelling out to `mmctl` for every call. Registered by
`scripts/install-mcp-servers.sh`.

## Why

- Some `mmctl` operations are multi-step and brittle when shelled.
- MCP exposes a structured tool surface the agent can use cleanly.
- Keeps the Mattermost PAT in one place (the MCP config) rather than
  scattered across shell invocations.
- Streaming / long-running operations work better through MCP than over
  shell pipes.

## What's registered

A single MCP server named `mattermost-phase3`, backed by the
community-maintained `mattermost-mcp-server` npm package.

- **Command**: `npx -y mattermost-mcp-server`
- **Env**: `MATTERMOST_URL`, `MATTERMOST_TOKEN`
- **Transport**: stdio

## Capabilities (agent-usable tools)

Typical toolset from the MCP (verify against your installed version):

| Tool | Purpose |
|------|---------|
| `list_users` | Users by team / role / activity |
| `get_user` | Full user record including auth service |
| `list_channels` | Channels by team |
| `get_channel_members` | Membership + last-viewed timestamps |
| `send_message` | (admin-scoped) post as admin bot |
| `list_plugins` | Installed plugins + state |
| `get_audit_events` | Recent admin-plane actions |
| `list_teams` | All teams on the server |
| `get_server_version` | Current Mattermost version + build |
| `get_config` | Read server config (may redact) |

## Registration

```bash
./scripts/install-mcp-servers.sh
```

The script tries both the `claude mcp add --flag form` and the short
form; falls back to printing the snippet for manual insertion into
`~/.claude/config.json` or `~/.codex/config.json`.

## Verification

```bash
./scripts/doctor.sh --require-mcp
```

Expects `mcp:any_agent=ok`. If it fails:
1. `claude mcp list` (or `codex mcp list`) — should show `mattermost-phase3`
2. Restart the Claude Code / Codex session (MCP servers are loaded at
   session start)
3. Try a simple tool call: *"List all Mattermost teams"*

## PAT lifecycle

The PAT in MCP config is the same as in `config.env`. On
`rotate-credentials`:

1. Rotate PAT via System Console.
2. Update `config.env.MATTERMOST_ADMIN_TOKEN`.
3. Re-run `./scripts/install-mcp-servers.sh` (it re-registers with the
   new PAT).
4. Restart agent session.

## Permissions

The MCP inherits whatever the PAT's user can do. For Phase 3 that's
system admin (needed for audits, config, full user list).

If you want a narrower-scope user for read-only auditing, create a
separate Mattermost user with team admin role, generate a PAT, and
register a second MCP instance. Not required for v1 of this skill.

## Alternatives

If `mattermost-mcp-server` doesn't meet your needs:

- **`mattermost-mcp`** (another community fork) — similar feature set.
- **Custom MCP** via `designing-mcp-servers` skill — build one that only
  exposes the tools you need.
- **Fallback to shell**: every MCP tool has a `mmctl` or `curl`
  equivalent; Phase 3 scripts use those forms as the base.

## Troubleshooting

- **Agent says "no MCP tools available"**: session not restarted after
  `install-mcp-servers.sh`. Restart.
- **MCP call hangs**: npx may be slow-cold; first call takes 10-30 sec.
- **401 on every MCP call**: PAT revoked. Rotate, re-register, restart.
- **"command not found: npx"**: Node.js not installed; install via
  `bootstrap-tools.sh` (npm is bundled with Go install step in modern
  Ubuntu).
