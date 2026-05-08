# Slack Export ZIP Format Reference

Complete anatomy of what Slack's export ZIP contains, how messages are structured, and how to parse them programmatically.

## Top-Level Files

### channels.json
Array of public channel objects:
```json
{
  "id": "C0ABC1234",
  "name": "general",
  "created": 1580000000,
  "creator": "U0ABC1234",
  "is_archived": false,
  "is_general": true,
  "members": ["U0ABC1234", "U0DEF5678"],
  "topic": {"value": "Company-wide announcements", "creator": "U0ABC1234", "last_set": 1580000000},
  "purpose": {"value": "General discussion", "creator": "U0ABC1234", "last_set": 1580000000},
  "pins": [{"id": "F0ABC1234", "type": "F", "created": 1590000000, "user": "U0ABC1234"}]
}
```

### groups.json
Same schema as channels.json but for private channels. Only present in Business+/Enterprise all-conversations exports.

### dms.json
Array of DM conversation objects:
```json
{
  "id": "D0ABC1234",
  "created": 1580000000,
  "members": ["U0ABC1234", "U0DEF5678"]
}
```

### mpims.json
Multi-party IMs (group DMs). Same schema as dms.json but with 3+ members.

### users.json
Array of user profile objects:
```json
{
  "id": "U0ABC1234",
  "team_id": "T0ABC1234",
  "name": "jdoe",
  "deleted": false,
  "real_name": "Jane Doe",
  "profile": {
    "email": "jane@company.com",
    "display_name": "Jane",
    "image_72": "https://avatars.slack-edge.com/...",
    "title": "Senior Engineer",
    "phone": "+1-555-0123"
  },
  "is_admin": false,
  "is_owner": false,
  "is_bot": false,
  "is_restricted": false,
  "is_ultra_restricted": false
}
```

**Key fields for migration:**
- `name` -- becomes Mattermost username
- `profile.email` -- used for user matching (CRITICAL for merge)
- `is_restricted` / `is_ultra_restricted` -- guest users (need role fixing in transform)
- `is_bot` -- bot accounts appear as "System" user in Mattermost
- `deleted` -- deactivated users; still import for message attribution

**Missing emails problem:** If workspace settings hide email addresses, the `profile.email` field will be empty. This breaks mmetl user matching. Fix with `slack-advanced-exporter fetch-emails`.

### integration_logs.json
App activity audit trail. Not imported into Mattermost. Preserve for compliance.

## Per-Channel Message Files

Each channel gets a folder named after the channel. Inside are date-named JSON files (`YYYY-MM-DD.json`), each containing an array of message objects for that day.

### Message Object Schema
```json
{
  "type": "message",
  "subtype": "",
  "user": "U0ABC1234",
  "text": "Hello everyone! Check out <https://example.com|this link>",
  "ts": "1706000000.000100",
  "thread_ts": "1706000000.000100",
  "reply_count": 3,
  "reply_users_count": 2,
  "reply_users": ["U0DEF5678", "U0GHI9012"],
  "reactions": [
    {"name": "thumbsup", "users": ["U0DEF5678"], "count": 1}
  ],
  "files": [
    {
      "id": "F0ABC1234",
      "name": "document.pdf",
      "mimetype": "application/pdf",
      "size": 102400,
      "url_private": "https://files.slack.com/files-pri/T0ABC-F0ABC/document.pdf",
      "url_private_download": "https://files.slack.com/files-pri/T0ABC-F0ABC/download/document.pdf",
      "permalink": "https://company.slack.com/files/U0ABC/F0ABC/document.pdf"
    }
  ],
  "attachments": [
    {
      "title": "Unfurled Link Title",
      "title_link": "https://example.com",
      "text": "Preview text from the link"
    }
  ],
  "edited": {
    "user": "U0ABC1234",
    "ts": "1706000100.000000"
  }
}
```

### Critical Fields

| Field | Significance |
|-------|-------------|
| `ts` | **THE unique identifier** for a message. Unix timestamp with microsecond precision. Used by Mattermost for deduplication. |
| `thread_ts` | If present and equals own `ts`, this is a thread parent. If different from own `ts`, this is a reply to that thread. |
| `user` | Slack user ID. Must be resolvable to a user in users.json for proper attribution. |
| `text` | May contain Slack markup: `<@U0ABC1234>` (user mentions), `<#C0ABC1234|channel-name>` (channel links), `<!here>`, `<!channel>`, `<!everyone>`. mmetl converts these. |
| `files[].url_private` | **Links expire.** This is why enrichment is critical. Without downloading, files become irrecoverable after Slack invalidates the URLs. |
| `subtype` | Empty string for normal messages. Special values: `channel_join`, `channel_leave`, `channel_topic`, `channel_purpose`, `bot_message`, `file_share`, `me_message`, `reminder_add`, `tombstone` (deleted). |

### Message Subtypes That Affect Migration

| Subtype | Import Behavior |
|---------|----------------|
| (empty) | Normal message, imported as post |
| `bot_message` | Appears as "System" user unless `Enable Integrations to Override Usernames` is on |
| `file_share` | Message with file attachment; file must be in export or downloaded |
| `channel_join` / `channel_leave` | System messages; imported as system posts |
| `channel_topic` / `channel_purpose` | Updates channel metadata |
| `tombstone` | Deleted message placeholder; typically not imported |
| `thread_broadcast` | Thread reply also posted to channel; needs dedup handling |

### Slack Markup → Mattermost Conversion

mmetl handles these conversions:

| Slack Format | Mattermost Format |
|-------------|-------------------|
| `<@U0ABC1234>` | `@username` |
| `<#C0ABC1234\|general>` | `~general` |
| `<!here>` | `@here` |
| `<!channel>` | `@channel` |
| `<!everyone>` | `@all` |
| `:emoji_name:` | `:emoji_name:` (if emoji exists) |
| `*bold*` | `**bold**` |
| `_italic_` | `*italic*` |
| `~strikethrough~` | `~~strikethrough~~` |
| ` ```code block``` ` | ` ```code block``` ` (same) |

### Threads and Replies

Slack threading model maps to Mattermost replies:

```
Parent message:   ts=1706000000.000100, thread_ts=1706000000.000100
  Reply 1:        ts=1706000001.000200, thread_ts=1706000000.000100
  Reply 2:        ts=1706000002.000300, thread_ts=1706000000.000100
```

mmetl creates the parent post first, then creates replies referencing the parent. Thread integrity is preserved as long as the parent message exists in the export.

**Edge case:** If a parent message was deleted but replies still exist, the replies will be orphaned. mmetl may handle this by creating a placeholder parent, or the replies may appear as top-level messages.

## File Reference Resolution

The file object in messages contains multiple URL fields:

| URL Field | Purpose | Auth Required |
|-----------|---------|---------------|
| `url_private` | Direct file content URL | Yes (`Authorization: Bearer <token>`) |
| `url_private_download` | Download-optimized URL | Yes |
| `permalink` | Web UI link (not for download) | Browser session |
| `thumb_*` | Thumbnail URLs (various sizes) | Yes |

### Download Pattern
```bash
curl -sL \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -o "$LOCAL_PATH" \
  "$url_private_download"
```

### File Expiration Timeline
Slack hasn't documented exact expiration windows, but observed behavior:
- Active workspace: URLs remain valid for weeks to months
- After workspace deletion: URLs invalidate within days
- After user deletion: File URLs may break
- After plan downgrade: No observed impact on existing URLs

**Rule: download ALL files during enrichment. Never rely on links staying valid.**

## Date Range and Completeness

Each date file (e.g., `2024-01-15.json`) contains ALL messages posted on that date in that channel, regardless of when the export was triggered. However:

- Deleted messages are NOT included (unless the channel has a retention policy that preserves them)
- Edited messages only include the latest version
- Slack Connect messages from external orgs follow the external org's retention, not yours
- Files in deleted channels may have broken URLs

## Parsing Tips for Custom Scripts

```python
import json, os, glob

# Load all messages from a channel
def load_channel(export_dir, channel_name):
    messages = []
    for f in sorted(glob.glob(f"{export_dir}/{channel_name}/*.json")):
        with open(f) as fh:
            messages.extend(json.load(fh))
    return sorted(messages, key=lambda m: float(m.get('ts', '0')))

# Count files referenced but not downloaded
def find_missing_files(export_dir):
    missing = []
    for root, dirs, files in os.walk(export_dir):
        for f in files:
            if not f.endswith('.json'):
                continue
            with open(os.path.join(root, f)) as fh:
                try:
                    data = json.load(fh)
                    for msg in (data if isinstance(data, list) else [data]):
                        for file_obj in msg.get('files', []):
                            url = file_obj.get('url_private', '')
                            if url and not os.path.exists(
                                os.path.join(export_dir, '__uploads', file_obj.get('id', ''))
                            ):
                                missing.append(file_obj)
                except json.JSONDecodeError:
                    pass
    return missing
```
