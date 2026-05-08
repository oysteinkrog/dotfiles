# Slack API Cookbook

Every API endpoint, scope, and pattern needed for migration enrichment. These are for **supplementing** the official export, not replacing it.

## Token Types

| Token | Prefix | Source | Use Case |
|-------|--------|--------|----------|
| User OAuth | `xoxp-` | Slack App > OAuth & Permissions | slack-advanced-exporter, emoji API, file downloads |
| Bot | `xoxb-` | Slack App > Bot Token | Limited scopes, good for Zulip import |
| Session | `xoxc-` | Browser DevTools (Network tab) | slackdump authentication |
| Cookie | `xoxd-` | Browser DevTools (Application > Cookies) | Paired with xoxc- for slackdump |
| Config | `xoxe-` | Enterprise Grid admin | Org-level operations |

**For migration enrichment, use `xoxp-` (User OAuth Token).** It has the broadest access to conversations the user is in.

## Required Scopes for Migration

### Minimum (emails + files + emoji)
```
users:read
users:read.email
files:read
emoji:read
```

### Full Access (also read conversations for verification)
```
channels:history
channels:read
groups:history
groups:read
im:history
im:read
mpim:history
mpim:read
users:read
users:read.email
emoji:read
files:read
team:read
```

## Endpoint Reference

### Users

**List all users:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/users.list?limit=200" | jq '.members | length'
```
- Scope: `users:read` + `users:read.email` for email field
- Rate limit: Tier 2 (~20 req/min)
- Paginated: use `cursor` parameter
- Returns: `members[]` with full profile including email

**Get single user:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/users.info?user=U0ABC1234" | jq '.user'
```

### Conversations (Channels, DMs)

**List all conversations:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/conversations.list?types=public_channel,private_channel,mpim,im&limit=200"
```
- Scope: `channels:read`, `groups:read`, `im:read`, `mpim:read`
- `types` parameter controls what's returned
- Paginated with `cursor`

**Get conversation history (verification only):**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/conversations.history?channel=C0ABC1234&limit=100"
```
- Scope: `channels:history` (public), `groups:history` (private), `im:history` (DMs)
- Rate limit: 50+ req/min for internal apps (post-May 2025)
- Up to 1,000 messages per call
- **DO NOT use as primary export method.** Use for gap-filling and verification only.

**Get thread replies:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/conversations.replies?channel=C0ABC1234&ts=1706000000.000100"
```
- Returns all replies in a thread
- Same rate limits as conversations.history

### Files

**List files:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/files.list?count=100&page=1"
```
- Scope: `files:read`
- Can filter by channel, user, date range, type

**Get file info:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/files.info?file=F0ABC1234"
```

**Download file content:**
```bash
curl -sL -H "Authorization: Bearer $SLACK_TOKEN" \
  -o "output_filename" \
  "https://files.slack.com/files-pri/T0ABC-F0ABC/document.pdf"
```
- The `url_private` and `url_private_download` fields require Bearer auth
- Files from deleted users/channels may return 404

### Emoji

**List all custom emoji:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/emoji.list" | jq '.emoji | keys | length'
```
- Scope: `emoji:read`
- Rate limit: Tier 2 (~20 req/min)
- Returns `emoji` object: `{"custom_name": "https://emoji.slack-edge.com/...", "alias_name": "alias:original_name"}`

**Parse and download all emoji:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/emoji.list" \
  | jq -r '.emoji | to_entries[] | select(.value | startswith("alias:") | not) | "\(.key)\t\(.value)"' \
  | while IFS=$'\t' read -r name url; do
    ext="${url##*.}"; ext="${ext%%\?*}"
    [[ -z "$ext" || "${#ext}" -gt 5 ]] && ext="png"
    curl -sL --max-time 10 -o "emoji/${name}.${ext}" "$url"
  done
```

**Resolve aliases:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/emoji.list" \
  | jq -r '.emoji | to_entries[] | select(.value | startswith("alias:")) | "\(.key) -> \(.value)"'
```
Aliases point to other custom emoji OR built-in Unicode emoji. Only download non-alias entries.

### Team/Workspace Info

**Get workspace info:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/team.info" | jq '.team'
```
- Returns workspace name, domain, icon, email domain
- Useful for `--default-email-domain` flag in mmetl

### Auth Verification

**Verify token is valid:**
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/auth.test" | jq '.'
```
Returns: `ok`, `user`, `team`, `url`, `team_id`, `user_id`. Always run this first.

## Rate Limits

### Post-May 2025 Rate Limits for Internal Apps

| Method | Tier | Rate | Objects/call |
|--------|------|------|-------------|
| `conversations.history` | Tier 3 | 50+ req/min | 1,000 |
| `conversations.replies` | Tier 3 | 50+ req/min | 1,000 |
| `conversations.list` | Tier 2 | ~20 req/min | 1,000 |
| `users.list` | Tier 2 | ~20 req/min | 200 |
| `files.list` | Tier 3 | ~50 req/min | 100 |
| `emoji.list` | Tier 2 | ~20 req/min | all |
| `auth.test` | Tier 4 | ~100 req/min | 1 |

**Key distinction:** These limits apply to **internal customer-built apps**. Third-party distributed apps may have lower limits. Slack's May 2025 changes did NOT reduce limits for internal apps.

### Handling Rate Limits

Slack returns `429 Too Many Requests` with a `Retry-After` header (seconds):
```bash
retry_after=$(curl -sI -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/users.list" | grep -i retry-after | awk '{print $2}')
sleep "$retry_after"
```

`slack-advanced-exporter` and `slackdump` handle this automatically with exponential backoff.

## Pagination Pattern

Most list endpoints return `response_metadata.next_cursor`. Loop until cursor is empty:
```bash
cursor=""
while true; do
  response=$(curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
    "https://slack.com/api/conversations.list?limit=200&cursor=$cursor")

  # Process response...
  echo "$response" | jq '.channels[] | .name'

  cursor=$(echo "$response" | jq -r '.response_metadata.next_cursor // empty')
  [[ -z "$cursor" ]] && break
done
```

## API Dead Ends (Don't Waste Time)

| API | Why It's Useless for Migration |
|-----|-------------------------------|
| Audit Logs API | Metadata only, no message content |
| Legal Holds API | Preserves data but does NOT provide access to contents |
| `admin.analytics.messages.metadata` | Message structure WITHOUT actual content |
| Discovery API | Requires approved third-party eDiscovery partner |
| SCIM API | User provisioning, not content export |

These APIs look promising but are dead ends for data extraction. The only reliable whole-workspace content path is the official admin export.
