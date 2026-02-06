# Shared Services (PM2)

Persistent services managed by PM2, shared across all Claude Code instances.
Auto-started on first shell open via fish config.

Config: `~/.config/pm2/ecosystem.config.js`

## Services

| Service | Port | What |
|---------|------|------|
| **better-ccflare** | 4800 | Claude API load balancer/proxy. All Claude Code instances route through this via `ANTHROPIC_BASE_URL`. Windows exe at `/c/WORK/better-ccflare/apps/cli/dist/`. |
| **pal-mcp** | 4801 | MCP server for multi-provider LLM access (Gemini, GPT, etc). SSE transport. Python at `/c/WORK/pal-mcp-server/server.py`. |
| **google-workspace-mcp** | 4802 | MCP server for Gmail, Calendar, Drive, Docs, Sheets, Slides, Forms, Tasks, Contacts. Streamable HTTP. Uses [workspace-mcp](https://github.com/taylorwilsdon/google_workspace_mcp) via uvx. |

## Commands

```bash
pm2 status                    # check all services
pm2 logs <name>               # tail logs
pm2 restart <name>            # restart one
pm2 restart all               # restart everything
pm2 start ~/.config/pm2/ecosystem.config.js  # start all (idempotent)
```

## Remote MCP servers (shared, no local process)

These connect to hosted endpoints — zero local overhead:

| Server | Endpoint | What |
|--------|----------|------|
| **context7** | `mcp.context7.com/mcp` | Up-to-date library docs. Add "use context7" to prompts. |
| **github** | `api.githubcopilot.com/mcp/` | GitHub API — PRs, issues, code search, CI workflows. Needs `GITHUB_PERSONAL_ACCESS_TOKEN`. |

## Per-instance MCP servers (stdio, not shared)

These spawn per Claude Code session:

| Server | Notes |
|--------|-------|
| **atlassian** | Proxies to `mcp.atlassian.com` via mcp-remote. |
| **slack** | Slack workspace access. Needs `SLACK_BOT_TOKEN` + `SLACK_TEAM_ID`. |
| **sentry** | Error tracking. Needs Sentry auth token. |
| **cdb-interactive** | Windows debugger (CDB). Disabled by default. |
| **motioncatalyst-ui** | FlaUI UI automation. Disabled by default. |

## Config files

- `~/.claude/settings.json` — `ANTHROPIC_BASE_URL` points to better-ccflare on `:4800`
- `~/.claude.json` `"mcpServers"` — all MCP server configs (shared + per-instance)
- `~/.config/pm2/ecosystem.config.js` — PM2 process definitions
- `~/.config/fish/config.fish` — auto-starts PM2 on first shell open
