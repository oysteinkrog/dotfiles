# Mattermost JSONL Bulk Import Format

Complete schema reference for the JSONL file that `mmetl` produces and `mmctl import` consumes.

## Ordering Rules (Strict)

Objects MUST appear in this order. Violations cause import failures.

```
1. version      (exactly one, must be first)
2. emoji        (zero or more, before teams)
3. team         (one or more)
4. channel      (zero or more, after their team)
5. user         (zero or more)
6. post         (zero or more, after their channel and user)
7. direct_channel  (zero or more)
8. direct_post     (zero or more, after their direct_channel)
```

## Object Schemas

### Version (Required First Line)
```json
{"type":"version","version":1}
```

### Emoji
```json
{
  "type": "emoji",
  "emoji": {
    "name": "custom-parrot",
    "image": "data/emoji/custom-parrot.gif"
  }
}
```
- `name`: lowercase, alphanumeric + hyphens/underscores
- `image`: relative path to image file within the import ZIP

### Team
```json
{
  "type": "team",
  "team": {
    "name": "acme-corp",
    "display_name": "Acme Corporation",
    "type": "O",
    "description": "Main company team",
    "allow_open_invite": true
  }
}
```
- `type`: `"O"` (open) or `"I"` (invite-only)
- `allow_open_invite`: must be `true` for bulk import to work

### Channel
```json
{
  "type": "channel",
  "channel": {
    "team": "acme-corp",
    "name": "engineering",
    "display_name": "Engineering",
    "type": "O",
    "header": "Engineering team discussions",
    "purpose": "General engineering chat"
  }
}
```
- `team`: must match a team `name` that appears earlier in the JSONL
- `type`: `"O"` (public) or `"P"` (private)
- `name`: lowercase, no spaces, max 64 chars

### User
```json
{
  "type": "user",
  "user": {
    "username": "jdoe",
    "email": "jane@company.com",
    "auth_service": "",
    "nickname": "Jane",
    "first_name": "Jane",
    "last_name": "Doe",
    "position": "Senior Engineer",
    "roles": "system_user",
    "locale": "en",
    "delete_at": 0,
    "teams": [
      {
        "name": "acme-corp",
        "roles": "team_user",
        "channels": [
          {"name": "engineering", "roles": "channel_user", "favorite": false}
        ]
      }
    ]
  }
}
```
- `roles`: `"system_user"` for regular users, `"system_admin system_user"` for admins, `"system_guest"` for guests (**never** combine `system_user` and `system_guest`)
- `email`: REQUIRED. Import fails if empty. Use `--default-email-domain` in mmetl or enrich with slack-advanced-exporter
- `teams[].channels[]`: defines which channels the user is a member of
- `delete_at`: 0 = active, Unix timestamp = deactivated

### Post
```json
{
  "type": "post",
  "post": {
    "team": "acme-corp",
    "channel": "engineering",
    "user": "jdoe",
    "message": "Hello team! Check out this doc.",
    "props": {},
    "create_at": 1706000000000,
    "reactions": [
      {"user": "bsmith", "emoji_name": "thumbsup", "create_at": 1706000100000}
    ],
    "replies": [
      {
        "user": "bsmith",
        "message": "Looks great!",
        "create_at": 1706000200000
      }
    ],
    "attachments": [
      {"path": "data/bulk-export-attachments/document.pdf"}
    ]
  }
}
```
- `create_at`: Unix timestamp in **milliseconds** (not seconds like Slack's `ts`)
- `channel`: must match a channel `name` defined earlier
- `user`: must match a user `username` defined earlier
- `replies`: nested array of reply objects (Mattermost threading)
- `attachments[].path`: relative path to file within the import ZIP
- **Idempotency:** Posts are deduped by `create_at` + `channel` + `user`. Re-importing won't create duplicates.

### Direct Channel
```json
{
  "type": "direct_channel",
  "direct_channel": {
    "members": ["jdoe", "bsmith"],
    "header": ""
  }
}
```
- `members`: array of exactly 2 usernames (DM) or 3+ (group DM)
- Usernames must match existing users

### Direct Post
```json
{
  "type": "direct_post",
  "direct_post": {
    "channel_members": ["jdoe", "bsmith"],
    "user": "jdoe",
    "message": "Hey, quick question...",
    "create_at": 1706000000000,
    "reactions": [],
    "replies": [],
    "attachments": []
  }
}
```
- `channel_members`: must match a `direct_channel.members` array exactly

## ZIP Package Structure

The final import ZIP must contain:
```
mattermost-bulk-import.zip
├── mattermost_import.jsonl
└── data/
    ├── bulk-export-attachments/
    │   ├── document.pdf
    │   ├── image.png
    │   └── ...
    └── emoji/                    # If injecting custom emoji
        ├── custom-parrot.gif
        └── ...
```

**Critical:** File paths in the JSONL (`attachments[].path`, `emoji.image`) must exactly match the paths inside the ZIP.

## Validation

```bash
# Validate before uploading
mmctl import validate ./mattermost-bulk-import.zip

# Check JSONL line by line
python3 -c "
import json, sys
types_seen = []
for i, line in enumerate(open(sys.argv[1]), 1):
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        t = obj.get('type', 'MISSING')
        types_seen.append(t)
        if i == 1 and t != 'version':
            print(f'ERROR: First line must be version, got {t}')
    except json.JSONDecodeError as e:
        print(f'Line {i}: Invalid JSON: {e}')

from collections import Counter
print('Object counts:', dict(Counter(types_seen)))
" mattermost_import.jsonl
```

## Common JSONL Errors

| Error | Cause | Fix |
|-------|-------|-----|
| "User roles are not consistent" | `system_user` + `system_guest` on same user | Remove `system_user` from guest users |
| "Channel not found" | Post references channel that doesn't exist in JSONL | Ensure all channels are defined before posts |
| "User not found" | Post references username not in JSONL | Ensure all users are defined before posts |
| "Invalid email" | Empty or malformed email on user | Use `--default-email-domain` or `--skip-empty-emails` |
| "Post too long" | Message exceeds `MaxPostSize` | Increase to 16383 or truncate in JSONL |

## Timestamp Conversion

Slack uses seconds with microsecond decimal: `"1706000000.000100"`
Mattermost uses milliseconds as integer: `1706000000000`

```python
# Slack ts → Mattermost create_at
slack_ts = "1706000000.000100"
mm_create_at = int(float(slack_ts) * 1000)  # → 1706000000000
```

mmetl handles this conversion automatically.
