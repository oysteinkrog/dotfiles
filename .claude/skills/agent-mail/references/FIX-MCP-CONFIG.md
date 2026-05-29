# Fix Claude Code MCP Configuration

When MCP server setup gets wiped out (fresh install, corruption, updates):

## Quick Fix

```bash
fix_cc_mcp
```

This restores both `mcp-agent-mail` and `morph-mcp` servers.

## Install the Script

```bash
# Create the script
cat > ~/.local/bin/fix_cc_mcp << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

MCP_URL="${MCP_URL:-http://127.0.0.1:8765/mcp/}"
MORPH_API_KEY="${MORPH_API_KEY:-YOUR_MORPH_API_KEY_HERE}"
SCOPE="${MCP_SCOPE:-user}"

# Check for claude CLI
command -v claude &>/dev/null || { echo "Install Claude Code first"; exit 1; }

# The rust server runs --no-auth on localhost — no bearer token needed.

# Remove existing, add fresh
claude mcp remove mcp-agent-mail --scope "${SCOPE}" 2>/dev/null || true
claude mcp remove morph-mcp --scope "${SCOPE}" 2>/dev/null || true

claude mcp add mcp-agent-mail "${MCP_URL}" --transport http --scope "${SCOPE}"
claude mcp add morph-mcp -e "MORPH_API_KEY=${MORPH_API_KEY}" -e "ENABLED_TOOLS=warp_grep" --scope "${SCOPE}" -- npx -y @morphllm/morphmcp

claude mcp list
echo "✓ MCP configuration restored"
SCRIPT

chmod +x ~/.local/bin/fix_cc_mcp
```

## Manual Commands

```bash
# Remove existing
claude mcp remove mcp-agent-mail --scope user
claude mcp remove morph-mcp --scope user

# Add mcp-agent-mail (HTTP transport, no auth — server runs --no-auth on localhost)
claude mcp add mcp-agent-mail "http://127.0.0.1:8765/mcp/" \
    --transport http \
    --scope user

# Add morph-mcp (stdio transport via npx)
claude mcp add morph-mcp \
    -e "MORPH_API_KEY=<key>" \
    -e "ENABLED_TOOLS=warp_grep" \
    --scope user \
    -- npx -y @morphllm/morphmcp
```

## Auth

None. The rust server runs `--no-auth` on `127.0.0.1`, so no bearer token is required.
(If you ever enable auth, add `--header "Authorization: Bearer <token>"` to the
`claude mcp add` command.)

## Configuration Options

| Variable | Default |
|----------|---------|
| `MCP_URL` | `http://127.0.0.1:8765/mcp/` |
| `MORPH_API_KEY` | (in script) |
| `MCP_SCOPE` | `user` |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "claude CLI not found" | Install Claude Code first |
| Server "not connected" | Ensure the PM2 service is up: `pm2 restart mcp-agent-mail && pm2 save`, or `am doctor fix` |

## Full Installer (Alternative)

To (re)install or update the rust Agent Mail binaries:

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail_rust/main/install.sh" | bash
```
