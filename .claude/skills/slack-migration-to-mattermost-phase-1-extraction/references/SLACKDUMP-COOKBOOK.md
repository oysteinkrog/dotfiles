# Slackdump Cookbook

Complete command reference for slackdump -- the community tool for extracting Slack data. Covers every mode, flag, authentication method, and edge case.

GitHub: `github.com/rusq/slackdump`

## Installation

```bash
# Auto-detect platform (handled by migrate.sh setup)
# Manual install:
curl -sL "https://api.github.com/repos/rusq/slackdump/releases/latest" \
  | jq -r '.assets[] | select(.name | test("linux.*amd64")) | .browser_download_url' \
  | head -1 | xargs curl -sL -o slackdump.tar.gz
tar -xzf slackdump.tar.gz
chmod +x slackdump
./slackdump version
```

Supported: Linux (amd64/arm64), macOS (amd64/arm64), Windows.

## Authentication Methods

### Method 1: Interactive Browser (Ez-Login 3000)
```bash
slackdump export -o output.zip
# Opens browser → log into Slack → session captured automatically
```
Default method. Requires display (not headless).

### Method 2: Token + Cookie (Headless)
```bash
export SLACK_TOKEN="xoxc-your-session-token"
export SLACK_COOKIE="xoxd-your-d-cookie"
slackdump export -o output.zip
```
Extract from browser DevTools. See `references/AUTHENTICATION.md`.

### Method 3: Saved Credentials
```bash
# First time: authenticate and save
slackdump auth login

# Subsequent runs: uses saved credentials
slackdump export -o output.zip
```

### Verify Authentication
```bash
slackdump auth test
# Should print workspace name and authenticated user
```

## Export Commands

### Full Workspace Export
```bash
# Everything, with files, Mattermost format (default in v4+)
slackdump export -o slack_export.zip -files

# Without files (faster, links only)
slackdump export -o slack_export.zip
```

### Export Specific Channels
```bash
# By channel ID
slackdump export -o export.zip C0123456789 C9876543210

# By channel name (if supported in your version)
slackdump export -o export.zip general random engineering
```

### Exclude Channels
```bash
# Prefix with ^ to exclude
slackdump export -o export.zip ^C0123456789 ^C9876543210
```

### Export Only DMs
```bash
# List DM conversations first
slackdump list -type dm

# Export specific DM by ID
slackdump export -o dms.zip D0ABC1234
```

### Export Format Options

```bash
# Mattermost-compatible (default in v4+)
slackdump export -o export.zip -type mattermost

# Standard Slack export format
slackdump export -o export.zip -type standard

# Dump format (raw JSON, for inspection)
slackdump dump C0123456789
```

### Incremental / Resumable

Slackdump supports resumable downloads:
```bash
# If interrupted, just re-run the same command
slackdump export -o export.zip -files
# It will pick up where it left off
```

For workspaces with 90-day retention limits, slackdump can create incremental archives.

## Emoji Export

```bash
# Download all custom emoji to a directory
slackdump emoji -o ./emoji/

# Output:
# emoji/
# ├── custom_emoji_1.png
# ├── custom_emoji_2.gif
# └── ...
```

This is often the cleanest way to get custom emoji since the official export omits them entirely.

## List Commands

```bash
# List all channels
slackdump list

# List only public channels
slackdump list -type public

# List only private channels
slackdump list -type private

# List DMs
slackdump list -type dm

# List group DMs
slackdump list -type mpim

# JSON output for scripting
slackdump list -json
```

## Key Flags Reference

| Flag | Description | Default |
|------|-------------|---------|
| `-o FILE` | Output file path | required |
| `-files` | Include file attachments | false |
| `-type FORMAT` | Export format: `mattermost`, `standard` | `mattermost` (v4+) |
| `-enterprise` | Enterprise workspace mode | false |
| `-older TIMESTAMP` | Messages older than this | none |
| `-latest TIMESTAMP` | Messages newer than this | none |
| `-limiter N/Ns` | Rate limiter (e.g., `20/60s`) | auto |
| `-user-cache-retention DURATION` | Cache user data | 4h |

## Access Model Deep Dive

Slackdump authenticates as YOUR user session. What it can access:

| Content | Access |
|---------|--------|
| All public channels | YES (even if not a member) |
| Private channels you're in | YES |
| Private channels you're NOT in | NO |
| Your DMs | YES |
| Other people's DMs | NO |
| Group DMs you're in | YES |
| Group DMs you're NOT in | NO |
| Deactivated users' messages | YES (messages persist in channels) |
| Deleted messages | NO (already gone) |
| Files in accessible channels | YES (with `-files`) |
| Custom emoji | YES (`slackdump emoji`) |

**For company-wide migration:** If you're a Workspace Owner on Business+, you can see all public and private channels. But you still can't see OTHER people's DMs. That's why the official all-conversations export is the authoritative source.

## Performance and Timing

| Workspace Size | Estimated Time (with -files) | Without -files |
|---------------|------------------------------|----------------|
| Small (<50 users, <1k msgs) | 5-15 minutes | 1-3 minutes |
| Medium (50-500 users, 10k+ msgs) | 1-4 hours | 15-60 minutes |
| Large (500+ users, 100k+ msgs) | 4-24 hours | 1-4 hours |
| Very large (1000+ users, 1M+ msgs) | 1-3 days | 4-12 hours |

File downloads are the bottleneck. Slack rate limits file access more aggressively than message history.

## Common Issues

### "Initialising: rate limited" on startup
Normal. Slackdump hits rate limits during initial channel enumeration. It backs off automatically.

### Export seems stuck at a specific channel
Large channels with thousands of messages take time. Check progress by monitoring output file size growth.

### "unauthorized" errors after working for a while
Session token (`xoxc-`) expired. Re-authenticate:
```bash
slackdump auth login
# or re-extract token+cookie from browser
```

### Empty or very small export
1. Check you're authenticated to the right workspace
2. Verify channels exist with `slackdump list`
3. Ensure you haven't excluded everything with `^` patterns

### Enterprise security alerts
Slackdump's own README warns that Enterprise workspaces may trigger security notifications to admins. If you're the admin doing the migration, this is expected. If not, get authorization first.

## Slackdump vs slack-advanced-exporter

| Tool | Purpose | When to Use |
|------|---------|-------------|
| slackdump | Full export from scratch | Pro plans, need files, no admin access |
| slack-advanced-exporter | Enrich existing official export | Business+, have official ZIP, need to add emails/files |

They complement each other. For maximum fidelity:
1. Get official export (Business+)
2. Enrich with slack-advanced-exporter
3. Use slackdump for gap-filling if needed
