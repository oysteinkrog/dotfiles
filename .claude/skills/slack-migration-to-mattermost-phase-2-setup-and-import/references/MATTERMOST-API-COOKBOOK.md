# Mattermost REST API Cookbook

## Authentication

### Login and Get Token

```bash
# Login with username/password
TOKEN=$(curl -s -X POST "https://chat.yourdomain.com/api/v4/users/login" \
  -H "Content-Type: application/json" \
  -d '{"login_id": "admin@yourdomain.com", "password": "YOUR_PASSWORD"}' \
  -D - -o /dev/null 2>&1 | grep -i "^token:" | awk '{print $2}' | tr -d '\r')

echo "Token: $TOKEN"
```

### Personal Access Tokens (Preferred for Automation)

Create in Mattermost: Profile > Security > Personal Access Tokens.

Or via API (admin creates token for a bot/user):

```bash
curl -X POST "https://chat.yourdomain.com/api/v4/users/USER_ID/tokens" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"description": "Migration automation"}'
# Save the returned token -- it is shown only once
```

Personal access tokens do not expire and are ideal for bots, scripts, and CI/CD. Enable them in System Console > Integrations > Integration Management.

### Standard Header for All Requests

```bash
MM_URL="https://chat.yourdomain.com"
MM_TOKEN="YOUR_TOKEN_HERE"
AUTH_HEADER="Authorization: Bearer $MM_TOKEN"
```

## Core API Endpoints

### Users

```bash
# Create a user
curl -X POST "$MM_URL/api/v4/users" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d '{
    "email": "jane@yourdomain.com",
    "username": "jane.doe",
    "password": "TempPassword123!",
    "first_name": "Jane",
    "last_name": "Doe"
  }'

# Get user by email
curl -s "$MM_URL/api/v4/users/email/jane@yourdomain.com" \
  -H "$AUTH_HEADER" | jq '{id, username, email}'

# Get user by username
curl -s "$MM_URL/api/v4/users/username/jane.doe" \
  -H "$AUTH_HEADER" | jq '{id, username, email}'

# Deactivate a user
curl -X DELETE "$MM_URL/api/v4/users/USER_ID" \
  -H "$AUTH_HEADER"

# Update user roles (make admin)
curl -X PUT "$MM_URL/api/v4/users/USER_ID/roles" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d '{"roles": "system_user system_admin"}'
```

### Teams

```bash
# List all teams
curl -s "$MM_URL/api/v4/teams" -H "$AUTH_HEADER" | jq '.[] | {id, name, display_name}'

# Get team by name
curl -s "$MM_URL/api/v4/teams/name/your-team" -H "$AUTH_HEADER" | jq '{id, name}'

# Get team stats
curl -s "$MM_URL/api/v4/teams/TEAM_ID/stats" \
  -H "$AUTH_HEADER" | jq .
# Returns: total_member_count, active_member_count
```

### Channels

```bash
# Create a public channel
curl -X POST "$MM_URL/api/v4/channels" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d '{
    "team_id": "TEAM_ID",
    "name": "new-channel",
    "display_name": "New Channel",
    "type": "O",
    "purpose": "Channel purpose here",
    "header": "Channel header here"
  }'
# type: "O" = public (open), "P" = private

# Get channel by name
curl -s "$MM_URL/api/v4/teams/TEAM_ID/channels/name/general" \
  -H "$AUTH_HEADER" | jq '{id, name, display_name}'

# Get channel members
curl -s "$MM_URL/api/v4/channels/CHANNEL_ID/members?per_page=200" \
  -H "$AUTH_HEADER" | jq '.[] | .user_id'

# Add user to channel
curl -X POST "$MM_URL/api/v4/channels/CHANNEL_ID/members" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d '{"user_id": "USER_ID"}'

# Remove user from channel
curl -X DELETE "$MM_URL/api/v4/channels/CHANNEL_ID/members/USER_ID" \
  -H "$AUTH_HEADER"
```

### Posts (Messages)

```bash
# Create a post
curl -X POST "$MM_URL/api/v4/posts" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d '{
    "channel_id": "CHANNEL_ID",
    "message": "Hello from the API!"
  }'

# Create a post with file attachment
# Step 1: Upload file
FILE_RESPONSE=$(curl -X POST "$MM_URL/api/v4/files?channel_id=CHANNEL_ID" \
  -H "$AUTH_HEADER" \
  -F "files=@/path/to/file.pdf")
FILE_ID=$(echo "$FILE_RESPONSE" | jq -r '.file_infos[0].id')

# Step 2: Create post referencing the file
curl -X POST "$MM_URL/api/v4/posts" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d "{
    \"channel_id\": \"CHANNEL_ID\",
    \"message\": \"Here is the report\",
    \"file_ids\": [\"$FILE_ID\"]
  }"

# Search posts
curl -s -X POST "$MM_URL/api/v4/teams/TEAM_ID/posts/search" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d '{"terms": "migration update", "is_or_search": false}' | jq '.posts | to_entries[] | {id: .key, message: .value.message}'
```

### Custom Emoji

```bash
# Upload custom emoji
curl -X POST "$MM_URL/api/v4/emoji" \
  -H "$AUTH_HEADER" \
  -F 'emoji={"name":"custom-emoji","creator_id":"USER_ID"};type=application/json' \
  -F "image=@/path/to/emoji.png"

# List custom emoji
curl -s "$MM_URL/api/v4/emoji?per_page=200" \
  -H "$AUTH_HEADER" | jq '.[] | {id, name, creator_id}'
```

## API Rate Limiting

Default Mattermost rate limits:

| Setting | Default | Notes |
|---------|---------|-------|
| Per second | 10 | Per user/token |
| Max burst | 100 | Short burst allowance |
| Memory store size | 10000 | Tracked sessions |

For bulk operations, add delays or use a dedicated automation token with higher limits:

```json
// config.json RateLimitSettings
{
  "RateLimitSettings": {
    "Enable": true,
    "PerSec": 10,
    "MaxBurst": 100,
    "MemoryStoreSize": 10000,
    "VaryByRemoteAddr": true,
    "VaryByUser": false,
    "VaryByHeader": ""
  }
}
```

For migration scripts, temporarily increase `PerSec` or set `VaryByUser: true` and use a dedicated token.

## Webhook API

### Incoming Webhooks

```bash
# Post via webhook (no auth header needed -- the webhook URL is the credential)
curl -X POST "https://chat.yourdomain.com/hooks/WEBHOOK_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Deployment to production completed",
    "username": "deploy-bot",
    "icon_emoji": ":rocket:",
    "props": {"card": "Additional details shown on expand"}
  }'
```

### List All Webhooks

```bash
# Incoming webhooks for a team
curl -s "$MM_URL/api/v4/hooks/incoming?per_page=200" \
  -H "$AUTH_HEADER" | jq '.[] | {id, display_name, channel_id}'

# Outgoing webhooks
curl -s "$MM_URL/api/v4/hooks/outgoing?per_page=200" \
  -H "$AUTH_HEADER" | jq '.[] | {id, display_name, trigger_words}'
```

## WebSocket API (Real-Time Events)

Connect to `wss://chat.yourdomain.com/api/v4/websocket` for real-time events.

```python
import websocket
import json

def on_message(ws, message):
    event = json.loads(message)
    if event.get("event") == "posted":
        post = json.loads(event["data"]["post"])
        print(f"[{event['data']['channel_display_name']}] {event['data']['sender_name']}: {post['message']}")

def on_open(ws):
    ws.send(json.dumps({
        "seq": 1,
        "action": "authentication_challenge",
        "data": {"token": "YOUR_MM_TOKEN"}
    }))

ws = websocket.WebSocketApp(
    "wss://chat.yourdomain.com/api/v4/websocket",
    on_message=on_message,
    on_open=on_open,
)
ws.run_forever()
```

## Automation Recipes

### Bulk Invite Users to a Channel

```bash
#!/usr/bin/env bash
# bulk_invite_to_channel.sh CHANNEL_ID emails.txt
CHANNEL_ID="$1"
EMAIL_FILE="$2"
MM_URL="https://chat.yourdomain.com"
MM_TOKEN="YOUR_TOKEN"

while IFS= read -r email; do
  [ -z "$email" ] && continue
  USER_ID=$(curl -s "$MM_URL/api/v4/users/email/$email" \
    -H "Authorization: Bearer $MM_TOKEN" | jq -r '.id')

  if [ "$USER_ID" = "null" ] || [ -z "$USER_ID" ]; then
    echo "SKIP: $email -- user not found"
    continue
  fi

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$MM_URL/api/v4/channels/$CHANNEL_ID/members" \
    -H "Authorization: Bearer $MM_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"user_id\": \"$USER_ID\"}")

  if [ "$HTTP_CODE" = "201" ]; then
    echo "OK: $email added"
  else
    echo "FAIL ($HTTP_CODE): $email"
  fi

  sleep 0.2  # Rate limit courtesy
done < "$EMAIL_FILE"
```

### Export Channel Member List

```bash
#!/usr/bin/env bash
# export_channel_members.sh CHANNEL_ID
CHANNEL_ID="$1"
MM_URL="https://chat.yourdomain.com"
MM_TOKEN="YOUR_TOKEN"
PAGE=0

echo "username,email,full_name"
while true; do
  MEMBERS=$(curl -s "$MM_URL/api/v4/channels/$CHANNEL_ID/members?page=$PAGE&per_page=200" \
    -H "Authorization: Bearer $MM_TOKEN")

  COUNT=$(echo "$MEMBERS" | jq 'length')
  [ "$COUNT" -eq 0 ] && break

  for USER_ID in $(echo "$MEMBERS" | jq -r '.[].user_id'); do
    USER=$(curl -s "$MM_URL/api/v4/users/$USER_ID" \
      -H "Authorization: Bearer $MM_TOKEN")
    echo "$USER" | jq -r '[.username, .email, (.first_name + " " + .last_name)] | @csv'
    sleep 0.1
  done

  PAGE=$((PAGE + 1))
done
```

### Post Announcement to All Public Channels

```bash
#!/usr/bin/env bash
# announce_to_all_channels.sh "Your announcement message"
MESSAGE="$1"
MM_URL="https://chat.yourdomain.com"
MM_TOKEN="YOUR_TOKEN"
TEAM_ID="YOUR_TEAM_ID"
PAGE=0

while true; do
  CHANNELS=$(curl -s "$MM_URL/api/v4/teams/$TEAM_ID/channels?page=$PAGE&per_page=200" \
    -H "Authorization: Bearer $MM_TOKEN")

  COUNT=$(echo "$CHANNELS" | jq 'length')
  [ "$COUNT" -eq 0 ] && break

  for CHANNEL_ID in $(echo "$CHANNELS" | jq -r '.[] | select(.type=="O") | .id'); do
    curl -s -X POST "$MM_URL/api/v4/posts" \
      -H "Authorization: Bearer $MM_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"channel_id\": \"$CHANNEL_ID\", \"message\": \"$MESSAGE\"}" > /dev/null
    echo "Posted to $CHANNEL_ID"
    sleep 0.2
  done

  PAGE=$((PAGE + 1))
done
```

### Deactivate Users by Email List

```bash
#!/usr/bin/env bash
# deactivate_users.sh emails_to_deactivate.txt
EMAIL_FILE="$1"
MM_URL="https://chat.yourdomain.com"
MM_TOKEN="YOUR_TOKEN"

while IFS= read -r email; do
  [ -z "$email" ] && continue
  USER=$(curl -s "$MM_URL/api/v4/users/email/$email" \
    -H "Authorization: Bearer $MM_TOKEN")
  USER_ID=$(echo "$USER" | jq -r '.id')
  USERNAME=$(echo "$USER" | jq -r '.username')

  if [ "$USER_ID" = "null" ] || [ -z "$USER_ID" ]; then
    echo "SKIP: $email -- not found"
    continue
  fi

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X DELETE "$MM_URL/api/v4/users/$USER_ID" \
    -H "Authorization: Bearer $MM_TOKEN")

  if [ "$HTTP_CODE" = "200" ]; then
    echo "DEACTIVATED: $username ($email)"
  else
    echo "FAIL ($HTTP_CODE): $email"
  fi

  sleep 0.2
done < "$EMAIL_FILE"
```

### Generate Migration Report (Channel/User/Post Counts)

```python
#!/usr/bin/env python3
"""Generate a migration health report from Mattermost API."""
import requests
import json

MM_URL = "https://chat.yourdomain.com"
MM_TOKEN = "YOUR_TOKEN"
HEADERS = {"Authorization": f"Bearer {MM_TOKEN}"}

def api_get(path):
    r = requests.get(f"{MM_URL}/api/v4{path}", headers=HEADERS)
    r.raise_for_status()
    return r.json()

def paginated_get(path, per_page=200):
    results = []
    page = 0
    while True:
        batch = api_get(f"{path}?page={page}&per_page={per_page}")
        if not batch:
            break
        results.extend(batch)
        if len(batch) < per_page:
            break
        page += 1
    return results

# --- Gather data ---
teams = api_get("/teams")
print(f"Teams: {len(teams)}")

for team in teams:
    tid = team["id"]
    tname = team["display_name"]
    stats = api_get(f"/teams/{tid}/stats")
    print(f"\n=== {tname} ===")
    print(f"  Total members: {stats['total_member_count']}")
    print(f"  Active members: {stats['active_member_count']}")

    channels = paginated_get(f"/teams/{tid}/channels")
    public = [c for c in channels if c["type"] == "O"]
    private = [c for c in channels if c["type"] == "P"]
    print(f"  Public channels: {len(public)}")
    print(f"  Private channels: {len(private)}")

    total_posts = sum(c.get("total_msg_count", 0) for c in channels)
    print(f"  Total posts (all channels): {total_posts}")

    # Top 10 channels by post count
    top = sorted(channels, key=lambda c: c.get("total_msg_count", 0), reverse=True)[:10]
    print(f"  Top channels by posts:")
    for c in top:
        print(f"    #{c['name']}: {c.get('total_msg_count', 0)} posts")

# All users
users = paginated_get("/users")
active = [u for u in users if u.get("delete_at", 0) == 0]
deactivated = [u for u in users if u.get("delete_at", 0) != 0]
bots = [u for u in users if u.get("is_bot", False)]
print(f"\n=== Users ===")
print(f"  Total: {len(users)}")
print(f"  Active: {len(active)}")
print(f"  Deactivated: {len(deactivated)}")
print(f"  Bots: {len(bots)}")
```

### Python Requests Pattern (Reusable Client)

```python
import requests

class MattermostClient:
    def __init__(self, url, token):
        self.url = url.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        })

    def get(self, path, **params):
        r = self.session.get(f"{self.url}/api/v4{path}", params=params)
        r.raise_for_status()
        return r.json()

    def post(self, path, data):
        r = self.session.post(f"{self.url}/api/v4{path}", json=data)
        r.raise_for_status()
        return r.json()

    def delete(self, path):
        r = self.session.delete(f"{self.url}/api/v4{path}")
        r.raise_for_status()
        return r.json()

    def paginated(self, path, per_page=200):
        results, page = [], 0
        while True:
            batch = self.get(path, page=page, per_page=per_page)
            if not batch:
                break
            results.extend(batch)
            if len(batch) < per_page:
                break
            page += 1
        return results

# Usage:
mm = MattermostClient("https://chat.yourdomain.com", "YOUR_TOKEN")
users = mm.paginated("/users")
channels = mm.paginated("/teams/TEAM_ID/channels")
mm.post("/posts", {"channel_id": "CHAN_ID", "message": "Hello from Python!"})
```
