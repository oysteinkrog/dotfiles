# Slack MCP Server Setup for Claude Code

Connect Claude Code directly to your Slack workspace during migration. Enables interactive exploration, verification, and gap-filling without leaving the terminal.

## Why Use This for Migration?

- **Verify export completeness:** Compare channel/user counts between export and live Slack
- **Debug missing data:** Search for specific messages or threads that didn't appear in the export
- **Explore before exporting:** Browse channels to decide what to include/exclude
- **Gap-fill:** Fetch specific conversations that slackdump or official export missed
- **Real-time audit:** Cross-reference import results against live Slack data

## Option A: Official Anthropic MCP Server (Recommended for Quick Start)

### Install
```bash
# One-liner for Claude Code
claude mcp add slack \
  -e SLACK_BOT_TOKEN=xoxb-your-bot-token \
  -e SLACK_TEAM_ID=T0123456789 \
  -- npx -y @modelcontextprotocol/server-slack
```

### Prerequisites
1. Create a Slack App at `api.slack.com/apps`
2. Add **Bot Token Scopes**: `channels:history`, `channels:read`, `groups:history`, `groups:read`, `im:history`, `im:read`, `mpim:history`, `mpim:read`, `users:read`, `reactions:read`
3. Install to workspace
4. Copy Bot User OAuth Token (`xoxb-...`)
5. Get Team ID (visible in workspace URL: `https://app.slack.com/client/T0123456789`)

### Available Tools (8)
| Tool | Migration Use |
|------|--------------|
| `slack_list_channels` | Enumerate all channels for export planning |
| `slack_get_channel_history` | Verify message counts match export |
| `slack_get_thread_replies` | Debug thread integrity issues |
| `slack_search_messages` | Find specific messages missing from export |
| `slack_list_users` | Compare user list against export |
| `slack_get_user_profile` | Verify email addresses for user matching |
| `slack_post_message` | Post migration announcements (use carefully) |
| `slack_add_reaction` | Not migration-relevant |

### Limitations
- Bot token only sees channels the bot is a member of
- Must invite the bot to private channels to access them
- Can't read other users' DMs (by design)

## Option B: korotovsky/slack-mcp-server (Most Powerful)

1,400+ stars. Supports stealth mode (no bot install required), 15+ tools, DMs, group DMs, smart history pagination.

### Install
```bash
# Clone and build
git clone https://github.com/korotovsky/slack-mcp-server.git
cd slack-mcp-server
go build -o slack-mcp-server ./cmd/slack-mcp-server

# Add to Claude Code
claude mcp add slack-koro \
  -e SLACK_MCP_TOKEN=xoxc-your-session-token \
  -e SLACK_MCP_COOKIE=xoxd-your-cookie \
  -- /path/to/slack-mcp-server
```

### Stealth Mode
Uses your `xoxc-` session token + `xoxd-` cookie (same credentials as slackdump). **No Slack app install required.** Sees everything you see in Slack -- all public channels, your private channels, your DMs.

### Additional Tools Beyond Official
| Tool | Migration Use |
|------|--------------|
| `conversations_search` | Search with date/user/content filters |
| `conversations_fetch_history_by_name` | Fetch by channel name, not just ID |
| `conversations_fetch_dms` | Access DM conversations for verification |
| `users_list_all` | Full user enumeration with pagination |

### Safety
Write operations (`conversations_add_message`) disabled by default. Enable with `SLACK_MCP_ADD_MESSAGE_TOOL=true` if needed for migration announcements.

## Option C: Composio Managed Server

For teams that prefer managed infrastructure:
```bash
claude mcp add --transport http slack-composio "YOUR_MCP_URL" \
  --headers "X-API-Key:YOUR_COMPOSIO_API_KEY"
```
Handles OAuth, rate limiting, and token refresh automatically. See `composio.dev/toolkits/slack`.

## Verification Workflow with MCP

Once connected, use these Claude Code prompts:

```
# Count channels in Slack vs export
"List all public channels in Slack and count them. I have N channels in my export -- are any missing?"

# Verify specific channel history
"Get the last 20 messages from #engineering in Slack. Compare with what I have in the export."

# Check user emails
"Get the profile for user U0ABC1234. What email address does Slack have?"

# Search for missing content
"Search Slack for messages containing 'quarterly review' from last month."

# Verify thread integrity
"Get all replies to the thread starting at timestamp 1706000000.000100 in #general."
```

## Which Option to Choose

| Situation | Best Choice |
|-----------|-------------|
| Quick setup, read-only exploration | Option A (official) |
| Full access including DMs, no bot install | Option B (korotovsky, stealth mode) |
| Enterprise/managed, team deployment | Option C (Composio) |
| Already using slackdump credentials | Option B (same xoxc-/xoxd- tokens) |

## Security Notes

- MCP server runs locally on your machine
- Tokens are stored in Claude Code's MCP config (not transmitted externally)
- Revoke tokens after migration completes
- Stealth mode (xoxc-) has full session access -- treat credentials carefully
- Bot tokens (xoxb-) are more scoped and safer for shared environments
