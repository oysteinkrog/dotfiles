# Agent Mail Installation & Recovery

## Table of Contents
- [Quick Install](#quick-install)
- [Configuration](#configuration)
- [Disaster Recovery](#disaster-recovery)
- [Health Checks](#health-checks)
- [Docker](#docker)

---

## Quick Install

### One-Liner (Recommended)

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail_rust/main/install.sh?$(date +%s)" | bash
```

Installs two binaries to `~/.local/bin`: `mcp-agent-mail` (MCP server) and `am` (operator CLI).
Useful flags: `--no-easy` (don't touch shell rc PATH), `--no-migrate` (skip Python import),
`--from-source` (build with cargo instead of downloading a release).

### Change Port After Install

```bash
am config set-port 9000
```

---

## Configuration

### Start Server

On this machine the server runs as a **PM2 service** (`~/.config/pm2/ecosystem.config.js`):

```bash
pm2 restart mcp-agent-mail && pm2 save        # managed restart
# manual / one-off (headless, localhost, no auth):
am serve-http --no-tui --no-auth --port 8765
# interactive operator console (reuses the running server):
am
```

### Key Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `STORAGE_ROOT` | `~/.mcp_agent_mail_git_mailbox_repo` | Root for git archive + SQLite |
| `HTTP_PORT` | `8765` | Server port |

Auth: the PM2 service runs with `--no-auth` (localhost only), so no bearer token is needed.
See [ADVANCED.md](ADVANCED.md#environment-variables) for the full list.

### Claude Code MCP Config

Prefer user-scope in `~/.claude.json` (projects inherit it). No auth header needed:

```json
{
  "mcpServers": {
    "mcp-agent-mail": {
      "type": "http",
      "url": "http://127.0.0.1:8765/mcp/"
    }
  }
}
```

The server also answers the legacy `/api/` path, so older project configs keep working.

---

## Disaster Recovery

### Create Backup

```bash
am archive save --label nightly
```

### List Restore Points

```bash
am archive list --json
```

### Restore After Disaster

```bash
am archive restore <file>.zip --force
```

---

## Health Checks

### Run Diagnostics

```bash
am doctor check
```

**Checks:**
- Stale locks
- Database integrity
- Orphaned records
- FTS sync
- Expired reservations

### Preview Repairs

```bash
am doctor repair --dry-run
```

### Apply Repairs

```bash
# Creates backup first
am doctor repair
```

### Quick Health Check

```bash
curl http://127.0.0.1:8765/health
# {"status": "healthy"}
```

---

## Docker

### Build

```bash
docker build -t mcp-agent-mail .
```

### Run

```bash
docker run --rm -p 8765:8765 \
  -e HTTP_HOST=0.0.0.0 \
  -v agent_mail_data:/data \
  mcp-agent-mail
```

---

## Static Mailbox Export

Export for auditors, stakeholders, or archives:

### Interactive Wizard (Recommended)

```bash
am share wizard
```

### Manual Export

```bash
am share export --output ./bundle
```

### With Signing

```bash
am share export \
  --output ./bundle \
  --signing-key ./keys/signing.key
```

### Preview Locally

```bash
am share preview ./bundle
```

### Export Features

- Ed25519 cryptographic signing
- Age encryption for confidential distribution
- Scrub presets: `standard` (removes secrets) or `strict` (redacts bodies)
- Deploy to GitHub Pages or Cloudflare Pages via wizard

See [RECOVERY.md](RECOVERY.md#static-mailbox-export) for full options.

---

## Pre-Commit Guard

Install to enforce file reservations at commit time:

```
install_precommit_guard(project_key="/abs/path", code_repo_path="/abs/path")
```

**Quick reference:**
- Set `AGENT_NAME` env var so guard knows who you are
- Bypass: `AGENT_MAIL_BYPASS=1 git commit -m "fix"`
- Uninstall: `uninstall_precommit_guard(code_repo_path="/abs/path")`

**Features:** Composition-safe (preserves existing hooks), rename-aware, NUL-safe, Git wildmatch pathspec.
