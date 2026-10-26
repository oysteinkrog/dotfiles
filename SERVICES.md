# Shared Services

Long-running services that every Claude Code session on the desktop shares. Each is a
systemd user unit in `.config/systemd/user/`, linked into `~/.config/systemd/user/` by
`install.sh` and enabled by `setup/steps/70-services.sh`. Units only one machine runs
are listed in that machine's `host.sh` (`HOST_USER_UNITS`) in the life repo.

## Services

| Unit | Port | What |
|------|------|------|
| `agent-mail.service` | 4809 | MCP Agent Mail (`am serve-http`), localhost only, no auth. Registered once at user scope as `mcp-agent-mail`. Storage root `~/.mcp_agent_mail_git_mailbox_repo`. Repair and restart: the `agent-mail-ops` skill. |
| `qmd-ifkb.service` | 8181 | qmd search server for the ifkb knowledge base (GPU, localhost, no auth). |
| `aiolos-rc-shim.service` | | Shared TLS shim for `--no-pin` aiolos-rc Claude sessions. See `.config/aiolos-rc/README.md`. |

## Commands

```bash
systemctl --user status agent-mail.service     # state, last log lines
journalctl --user -u agent-mail.service -f     # follow the log
systemctl --user restart agent-mail.service    # restart one
systemctl --user list-units --type=service     # everything running as me
```

## MCP servers without a local service

These start per Claude Code session (stdio) or are hosted elsewhere, so nothing runs
between sessions:

- The claude.ai connectors (Gmail, Google Calendar, Google Drive, Claude Docs, TinyFish).
- The stdio servers in `.claude/mcp-servers.json`, restored into `~/.claude.json` by
  `bin/claude-restore-mcp`.

## Config files

- `.config/systemd/user/*.service`, `*.timer`: the unit files.
- `~/.claude.json` `"mcpServers"`: MCP server registrations at user scope.
- `.claude/mcp-servers.json`: the stdio MCP server definitions kept in git.
