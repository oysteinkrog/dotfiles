# config.env Full Reference

Copy `config.env.example` to `config.env`. Never commit `config.env` to git.

## Required Variables

| Variable | Example | Description |
|----------|---------|-------------|
| `WORKSPACE_NAME` | `acme-slack` | Workspace label written into manifests and reports |
| `PHASE1_WORKSPACE_ROOT` | `./workdir` | Where `migrate.sh` writes `artifacts/` and reports |
| `MATTERMOST_TEAM_NAME` | `acme-corp` | Lowercase, hyphens allowed, no spaces |

## Optional: Team Display

| Variable | Default | Description |
|----------|---------|-------------|
| `MATTERMOST_TEAM_DISPLAY_NAME` | same as team name | Shown in Mattermost UI |

## Optional: Slack Export Source

| Variable | Default | Description |
|----------|---------|-------------|
| `SLACK_EXPORT_ZIP` | empty | Path to official Slack export ZIP. Leave empty for slackdump. |
| `SLACK_CHANNEL_AUDIT_CSV` | empty | Channel-audit CSV from Slack admin export UI |
| `SLACK_MEMBER_CSV` | empty | Member directory CSV or equivalent admin export |
| `SLACKDUMP_VERSION` | `latest` | Slackdump version tag (e.g., `v3.0.0`) |
| `SLACKDUMP_BIN` | `slackdump` | Slackdump binary or wrapper path |
| `SLACKDUMP_ARGS` | empty | Extra args appended to `run-slackdump-export.sh` |
| `SLACKDUMP_WITH_FILES` | `1` | Include file attachments in slackdump export |
| `SLACKDUMP_PRIMARY` | `0` | Set to `1` when slackdump is the primary acquisition path |

## Optional: Slack API Access

| Variable | Default | Description |
|----------|---------|-------------|
| `SLACK_TOKEN` | empty | `xoxp-` (User OAuth) or `xoxb-` (Bot) token for API enrichment |
| `SLACK_COOKIE` | empty | `xoxd-` cookie for slackdump headless auth |
| `SLACK_ADVANCED_EXPORTER_BIN` | `slack-advanced-exporter` | Advanced exporter binary for email/file enrichment |

**Token types:**
- `xoxp-...` User OAuth Token -- for slack-advanced-exporter, emoji API, file downloads
- `xoxb-...` Bot Token -- for bot-scoped API calls (more limited)
- `xoxc-...` Session Token -- for slackdump only, paired with `xoxd-` cookie

## Optional: Export Filtering

| Variable | Default | Description |
|----------|---------|-------------|
| `PHASE1_SIDECAR_INPUTS` | empty | Comma-separated paths copied into the `sidecars/` bundle |
| `PHASE1_WORKFLOW_INPUTS` | empty | Comma-separated workflow export paths copied into `workflows/` |
| `PHASE1_KNOWN_GAPS` | empty | Comma-separated human-authored gaps passed into `handoff.json` |
| `PHASE1_SIDECAR_CHANNELS` | `slack-canvases-archive,slack-lists-archive,slack-export-admin` | Sidecar channel names declared in the handoff |
| `PHASE1_EVIDENCE_PATHS` | empty | Extra files or directories to hash into the evidence pack |

## Optional: Transform and Batching

| Variable | Default | Description |
|----------|---------|-------------|
| `MMETL_BIN` | `mmetl` | mmetl binary path |
| `MMETL_DEFAULT_EMAIL_DOMAIN` | empty | Fallback domain if mmetl needs to synthesize emails |
| `MMETL_EXTRA_FLAGS` | empty | Extra args appended to `mmetl transform slack` |
| `SPLIT_IMPORT_YEARS` | empty | Comma-separated years for `./migrate.sh split-import` |

## Example Minimal config.env

```bash
WORKSPACE_NAME="acme-slack"
PHASE1_WORKSPACE_ROOT="./workdir"
MATTERMOST_TEAM_NAME="acme"
MATTERMOST_TEAM_DISPLAY_NAME="Acme Corporation"
SLACK_TOKEN="xoxp-1234567890-1234567890-abcdef"
```

## Example Full config.env

```bash
WORKSPACE_NAME="acme-slack"
PHASE1_WORKSPACE_ROOT="./workdir"
MATTERMOST_TEAM_NAME="acme"
MATTERMOST_TEAM_DISPLAY_NAME="Acme Corporation"

SLACK_EXPORT_ZIP="/absolute/path/to/slack-export.zip"
SLACK_CHANNEL_AUDIT_CSV="/absolute/path/to/channel-audit.csv"
SLACK_MEMBER_CSV="/absolute/path/to/member-list.csv"
SLACKDUMP_BIN="slackdump"
SLACKDUMP_ARGS=""
SLACKDUMP_WITH_FILES="1"

SLACK_TOKEN="xoxp-1234567890-1234567890-abcdef"
SLACK_ADVANCED_EXPORTER_BIN="slack-advanced-exporter"

PHASE1_SIDECAR_INPUTS="/tmp/admin-sidecars,/tmp/canvas-export"
PHASE1_WORKFLOW_INPUTS="/tmp/workflow-builder"
PHASE1_KNOWN_GAPS="Slack Connect history is partial,Bookmarks must be rebuilt manually"
PHASE1_EVIDENCE_PATHS="/tmp/approval-screenshot.png"

MMETL_BIN="mmetl"
MMETL_DEFAULT_EMAIL_DOMAIN="acme.com"
MMETL_EXTRA_FLAGS="--skip-empty-emails --discard-invalid-props"
SPLIT_IMPORT_YEARS="2023,2024"
```
