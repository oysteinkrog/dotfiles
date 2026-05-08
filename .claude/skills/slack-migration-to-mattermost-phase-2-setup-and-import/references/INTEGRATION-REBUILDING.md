# Rebuilding Slack Integrations in Mattermost

## The Hard Truth

Slack integrations, bots, apps, and workflows **do not migrate** to Mattermost. The Slack export contains messages and files only -- not integration configurations, bot tokens, or workflow definitions. Every integration must be inventoried, evaluated, and rebuilt or replaced.

## Phase 1: Inventory All Slack Integrations

Before migration, catalog everything. You will forget integrations that post infrequently.

### Pull the Full Integration List

In Slack admin (requires Workspace Owner/Admin):

1. Go to `https://YOUR-WORKSPACE.slack.com/apps/manage`
2. Export or screenshot every installed app
3. Check **Custom Integrations** tab separately (legacy bots, webhooks)

### Automated Inventory via Slack API

```bash
# List all installed apps (requires admin token with admin.apps:read scope)
curl -s "https://slack.com/api/team.integrationLogs?token=xoxp-YOUR-TOKEN&count=200" | jq '.logs[] | {app_id, user_name, service_type, channel}' > slack_integrations_inventory.json

# List all incoming webhooks
curl -s "https://slack.com/api/incoming-webhooks.list?token=xoxp-YOUR-TOKEN" | jq .

# List all custom bots
curl -s "https://slack.com/api/bots.list?token=xoxp-YOUR-TOKEN" | jq '.bots[] | {id, name, deleted}'
```

### Build the Catalog Spreadsheet

For each integration, record:

| Integration | Type | Channels Used | Owner | Criticality | MM Equivalent | Status |
|-------------|------|---------------|-------|-------------|---------------|--------|
| GitHub | App | #dev, #pr-reviews | @alice | High | Official plugin | Pending |
| Jenkins CI | Webhook | #deploys | @bob | High | Incoming webhook | Pending |
| Standup Bot | Custom bot | #standup | @carol | Medium | Rebuild or replace | Pending |
| PagerDuty | App | #incidents | @dave | Critical | Webhook + Playbooks | Pending |

## Mattermost Integration Types

### Incoming Webhooks

Accept POST requests and create messages in a channel. The closest Slack equivalent and the easiest to migrate -- many services just need the URL updated.

**Create in Mattermost:**

1. Main Menu > Integrations > Incoming Webhooks > Add
2. Choose channel, set display name and description
3. Copy the webhook URL

**Or via API:**

```bash
# Create incoming webhook
curl -X POST "https://chat.yourdomain.com/api/v4/hooks/incoming" \
  -H "Authorization: Bearer YOUR_MM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "channel_id": "CHANNEL_ID",
    "display_name": "Jenkins CI",
    "description": "Build notifications from Jenkins"
  }'
```

**Payload format** (compatible with Slack's format):

```bash
# Mattermost accepts Slack-compatible payloads:
curl -X POST "https://chat.yourdomain.com/hooks/YOUR_WEBHOOK_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Build #142 passed",
    "username": "jenkins-bot",
    "icon_url": "https://example.com/jenkins.png",
    "channel": "deploys"
  }'

# Mattermost also supports its own richer attachment format:
curl -X POST "https://chat.yourdomain.com/hooks/YOUR_WEBHOOK_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Build completed",
    "attachments": [{
      "color": "#00FF00",
      "title": "Build #142",
      "title_link": "https://jenkins.example.com/job/142",
      "fields": [
        {"short": true, "title": "Status", "value": "Passed"},
        {"short": true, "title": "Duration", "value": "3m 22s"}
      ]
    }]
  }'
```

**Migration shortcut**: for services that post to Slack via webhook, just swap the Slack webhook URL for the Mattermost one. The payload format is largely compatible.

### Outgoing Webhooks

Trigger on specific words or channels and POST message data to your endpoint.

**Create in Mattermost:**

1. Main Menu > Integrations > Outgoing Webhooks > Add
2. Set trigger words and/or channel
3. Set callback URL(s)

```bash
# Create outgoing webhook via API
curl -X POST "https://chat.yourdomain.com/api/v4/hooks/outgoing" \
  -H "Authorization: Bearer YOUR_MM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "team_id": "TEAM_ID",
    "channel_id": "CHANNEL_ID",
    "display_name": "Ticket Bot",
    "trigger_words": ["!ticket", "!bug"],
    "callback_urls": ["https://your-service.example.com/mm-webhook"],
    "content_type": "application/json"
  }'
```

### Slash Commands

Custom commands users type in the message box. Very similar to Slack's custom slash commands.

**Create in Mattermost:**

1. Main Menu > Integrations > Slash Commands > Add
2. Set command trigger (e.g., `/deploy`)
3. Set request URL and method

```bash
# Create slash command via API
curl -X POST "https://chat.yourdomain.com/api/v4/commands" \
  -H "Authorization: Bearer YOUR_MM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "team_id": "TEAM_ID",
    "trigger": "deploy",
    "method": "P",
    "url": "https://your-service.example.com/deploy",
    "display_name": "Deploy",
    "description": "Trigger a deployment",
    "auto_complete": true,
    "auto_complete_hint": "[environment] [branch]"
  }'
```

### Bot Accounts

Mattermost bots are first-class accounts that can post messages, react, and interact without occupying a user seat.

```bash
# Create a bot account
curl -X POST "https://chat.yourdomain.com/api/v4/bots" \
  -H "Authorization: Bearer YOUR_MM_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "deploy-bot",
    "display_name": "Deploy Bot",
    "description": "Handles deployment commands"
  }'
# Response includes bot user_id

# Create a personal access token for the bot
curl -X POST "https://chat.yourdomain.com/api/v4/users/BOT_USER_ID/tokens" \
  -H "Authorization: Bearer YOUR_MM_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"description": "Deploy bot token"}'
# Response includes token -- save it, it is only shown once
```

Enable bot accounts in System Console > Integrations > Bot Accounts > Enable.

Enable personal access tokens in System Console > Integrations > Integration Management > Enable Personal Access Tokens.

### Mattermost Plugin API (for Slack App equivalents)

Complex Slack apps (interactive messages, modals, event subscriptions) map to Mattermost plugins or the Apps Framework:

- **Plugins** (Go): full server-side and webapp hooks, stored in the plugin marketplace
- **Apps Framework** (any language): lighter-weight, uses HTTP/REST callbacks

For custom Slack apps, the migration strategy depends on complexity. Simple notification bots map to webhooks. Interactive bots with buttons/dialogs need the Plugin API or Apps Framework.

## Common Slack Integrations and Mattermost Equivalents

### Official Mattermost Plugins (Install from Marketplace)

| Slack Integration | Mattermost Plugin | Notes |
|-------------------|-------------------|-------|
| GitHub | `github` | PR notifications, slash commands, sidebar links |
| GitLab | `gitlab` | MR notifications, slash commands |
| Jira | `jira` | Issue creation, notifications, slash commands |
| Zoom | `zoom` | Start meetings from channel header |
| Microsoft Teams | `msteams-sync` | Bridge channels to Teams |
| ServiceNow | `servicenow` | Incident management |
| Confluence | `confluence` | Page update notifications |
| Welcome Bot | `welcomebot` | Auto-welcome new channel members |

Install any of these:

```bash
mmctl plugin marketplace install PLUGIN_ID --local
mmctl plugin enable PLUGIN_ID --local

# Example:
mmctl plugin marketplace install github --local
mmctl plugin enable github --local
```

### Integrations That Need Webhook Rebuilding

| Slack Integration | Mattermost Approach |
|-------------------|---------------------|
| PagerDuty | Incoming webhook + Mattermost Playbooks for incident response |
| Jenkins / CircleCI / GitHub Actions | Incoming webhook (swap URL in CI config) |
| Datadog / Grafana / Prometheus | Incoming webhook (most monitoring tools support custom webhook URLs) |
| Google Calendar | Community plugin or incoming webhook via Google Apps Script |
| Trello / Asana | Incoming webhook (configure in the project management tool) |
| Sentry | Incoming webhook (Sentry supports custom webhook URLs) |
| Statuspage | Incoming webhook |

### Slack Workflow Builder

Slack Workflow Builder has **no direct equivalent** in Mattermost. Alternatives:

- **Mattermost Playbooks**: for incident response, onboarding checklists, recurring processes. Supports stages, tasks, retrospectives, and automation triggers.
- **Custom slash commands + webhooks**: for simple automation (e.g., form submissions that create tickets)
- **n8n / Make / Zapier**: external automation platforms with Mattermost webhook integration
- **Custom plugin**: for complex, interactive workflows

## Migration Strategy for Custom Slack Bots

### Phase 1: Dual-Posting (Transition Period)

During migration, have bots post to both Slack and Mattermost:

```python
import requests

SLACK_WEBHOOK = "https://hooks.slack.com/services/T.../B.../xxx"
MM_WEBHOOK = "https://chat.yourdomain.com/hooks/YOUR_WEBHOOK_ID"

def notify(message):
    payload = {"text": message}
    # Post to both during transition
    requests.post(SLACK_WEBHOOK, json=payload)
    requests.post(MM_WEBHOOK, json=payload)
```

### Phase 2: Full Port to Mattermost

For bots that use the Slack Events API or interactive components, port to Mattermost equivalents:

| Slack Concept | Mattermost Equivalent |
|---------------|----------------------|
| Events API | Outgoing webhook or Plugin hooks |
| Interactive Messages (buttons) | Message attachments with actions |
| Modals / Dialogs | Interactive dialogs (`/api/v4/actions/dialogs/open`) |
| Slack Block Kit | Mattermost markdown + attachments |
| `chat.postMessage` | `POST /api/v4/posts` |
| `reactions.add` | `POST /api/v4/reactions` |
| `files.upload` | `POST /api/v4/files` |

### Phase 3: Decommission Slack Bots

After verifying Mattermost equivalents work:

1. Remove Slack bot tokens from your secrets manager
2. Revoke Slack app tokens in Slack admin
3. Remove Slack webhook URLs from all services
4. Uninstall Slack apps from the workspace

## Verification Checklist

After rebuilding each integration, verify:

- [ ] Messages arrive in the correct Mattermost channel
- [ ] Bot display name and icon render correctly
- [ ] Attachments / formatting render properly
- [ ] Interactive elements (buttons, menus) function if applicable
- [ ] Slash commands respond correctly
- [ ] Error notifications still work (test with a deliberate failure)
- [ ] Rate limiting is acceptable (Mattermost default: 10 req/sec per user)

## Bulk Webhook Creation Script

For teams with many webhooks to recreate:

```bash
#!/usr/bin/env bash
# bulk_create_webhooks.sh
# Reads a CSV of channel_name,webhook_display_name and creates incoming webhooks

MM_URL="https://chat.yourdomain.com"
MM_TOKEN="YOUR_ADMIN_TOKEN"
TEAM_NAME="your-team"

# Get team ID
TEAM_ID=$(curl -s -H "Authorization: Bearer $MM_TOKEN" \
  "$MM_URL/api/v4/teams/name/$TEAM_NAME" | jq -r '.id')

while IFS=',' read -r channel_name webhook_name; do
  # Get channel ID
  CHANNEL_ID=$(curl -s -H "Authorization: Bearer $MM_TOKEN" \
    "$MM_URL/api/v4/teams/$TEAM_ID/channels/name/$channel_name" | jq -r '.id')

  if [ "$CHANNEL_ID" = "null" ] || [ -z "$CHANNEL_ID" ]; then
    echo "SKIP: channel '$channel_name' not found"
    continue
  fi

  # Create webhook
  RESULT=$(curl -s -X POST "$MM_URL/api/v4/hooks/incoming" \
    -H "Authorization: Bearer $MM_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"channel_id\": \"$CHANNEL_ID\",
      \"display_name\": \"$webhook_name\",
      \"description\": \"Migrated from Slack\"
    }")

  HOOK_ID=$(echo "$RESULT" | jq -r '.id')
  echo "OK: $webhook_name -> $MM_URL/hooks/$HOOK_ID"
done < webhooks.csv
```

Example `webhooks.csv`:

```
deploys,Jenkins CI
alerts,PagerDuty Alerts
general,Standup Bot
```
