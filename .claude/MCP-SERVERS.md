# MCP Servers

Shared MCP servers run as persistent services via PM2, so multiple Claude Code
instances connect to the same process instead of each spawning their own.

## Shared services (PM2-managed)

Config: `~/.config/pm2/ecosystem.config.js`

| Service | Port | Transport | Package |
|---------|------|-----------|---------|
| **better-ccflare** | 4800 | HTTP | Windows exe at `/c/WORK/better-ccflare/apps/cli/dist/` |
| **pal-mcp** | 4801 | SSE | `/c/WORK/pal-mcp-server/server.py` (venv Python, `MCP_TRANSPORT=sse`) |
| **google-workspace-mcp** | 4802 | Streamable HTTP | `workspace-mcp` via uvx ([taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)) |

### Commands

```bash
pm2 status                    # check all services
pm2 logs <name>               # tail logs
pm2 restart <name>            # restart one service
pm2 restart all               # restart everything
pm2 start ~/.config/pm2/ecosystem.config.js  # start all (idempotent)
```

### Auto-start

Fish shell config (`~/.config/fish/config.fish`) starts PM2 on first shell open.

## Per-instance MCP servers (stdio)

These spawn per Claude Code session and are not shared:

| Server | Transport | Notes |
|--------|-----------|-------|
| **atlassian** | stdio (mcp-remote) | Proxies to `https://mcp.atlassian.com/v1/mcp`. Lightweight bridge per session. |
| **cdb-interactive** | stdio | Windows debugger (CDB). Project-specific, disabled by default. |
| **motioncatalyst-ui** | stdio | FlaUI automation wrapper. Project-specific, disabled by default. |

## Claude Code config

MCP server definitions live in `~/.claude.json` under `"mcpServers"` (managed by
`claude mcp add`). The shared servers use `type: "sse"` or `type: "http"` pointing
at localhost. See `mcp-servers.json` in this directory for the canonical config.

`ANTHROPIC_BASE_URL` in `~/.claude/settings.json` points to better-ccflare on `:4800`.
