# Enrichment Pipeline

Official Slack exports have links but not files, and may be missing email addresses. This pipeline fills the gaps before running `mmetl` transform.

## Order of Operations

```
1. fetch-emails       (adds user email addresses to the ZIP)
2. fetch-attachments  (downloads file binaries into the ZIP)
3. export emoji       (separate: downloads custom emoji images)
4. archive canvases   (preserves canvas HTML as sidecar assets)
5. archive lists      (preserves list JSON as sidecar assets)
6. verify completeness (audit: every file reference resolved?)
```

**Always do emails first, then attachments.** ZIP archives can't be modified in place efficiently; each step produces a new ZIP.

## 1. slack-advanced-exporter (Mattermost Official)

Mattermost maintains `slack-advanced-exporter` specifically for supplementing official Slack exports. Install from: `github.com/mattermost/slack-advanced-exporter`

### Add Emails
```bash
./slack-advanced-exporter \
  --input-archive raw-export.zip \
  --output-archive export-with-emails.zip \
  fetch-emails --api-token "$SLACK_TOKEN"
```
Requires: `users:read` + `users:read.email` scopes.

Why: mmetl needs email addresses to match Slack users to Mattermost accounts. If Slack hides emails in the workspace settings, they won't be in the export ZIP.

### Add File Attachments
```bash
./slack-advanced-exporter \
  --input-archive export-with-emails.zip \
  --output-archive export-with-files.zip \
  fetch-attachments --api-token "$SLACK_TOKEN"
```
Requires: `files:read` scope. Uses `url_private` / `url_private_download` with `Authorization: Bearer` header.

This downloads every file referenced in the export JSON and embeds it in the archive. Can take hours for large workspaces with many attachments.

## 2. Custom Emoji Export

Slack's built-in export does NOT include custom emoji. Three methods:

### Method A: Slackdump (Recommended)
```bash
slackdump emoji -o ./workdir/emoji/
```

### Method B: Slack API
```bash
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/emoji.list" -o emoji_list.json

# Parse and download each emoji
jq -r '.emoji | to_entries[] | "\(.key)\t\(.value)"' emoji_list.json | \
while IFS=$'\t' read -r name url; do
  [[ "$url" == alias:* ]] && continue  # Skip aliases
  ext="${url##*.}"; ext="${ext%%\?*}"
  [[ -z "$ext" || "${#ext}" -gt 5 ]] && ext="png"
  curl -sL --max-time 10 -o "emoji/${name}.${ext}" "$url"
done
```
Requires: `emoji:read` scope.

**Alias resolution:** `emoji.list` returns `alias:original_name` for aliases. Resolve to the original image, don't try to download the alias string.

### Method C: Chrome Extension
"Slack Custom Emoji Manager" extension > Customize Workspace > Download All Emojis. Manual fallback only.

### Importing Emoji to Mattermost
Emoji are imported via `/api/v4/emoji` POST endpoint (not through the bulk JSONL import). Alternatively, prepend emoji objects to the JSONL before the Team objects:

```json
{"type":"emoji","emoji":{"name":"custom-emoji","image":"data/emoji/custom-emoji.png"}}
```

## 3. Canvas and List Preservation

Slack canvases export as **HTML**, lists export as **JSON**. Mattermost has no native import types for these. Preservation strategy:

1. Extract canvas HTML and list JSON from the export ZIP
2. Create archive channels: `slack-canvases-archive`, `slack-lists-archive`
3. Inject generated posts with the HTML/JSON attached as files
4. Add these synthetic posts to the JSONL after mmetl transform

This preserves the content in a searchable, accessible form without pretending Mattermost has native canvas/list objects.

## 4. Attachment Verification

After enrichment, verify every file reference was resolved:

```bash
# Extract all url_private references from the export
find export_dir/ -name "*.json" -exec \
  jq -r '.. | .url_private? // empty' {} + 2>/dev/null | sort -u > expected_files.txt

# Count files actually downloaded
find export_dir/__uploads/ -type f | wc -l

# Compare counts
echo "Expected: $(wc -l < expected_files.txt)"
echo "Downloaded: $(find export_dir/__uploads/ -type f | wc -l)"
```

If any are missing, re-fetch via direct authenticated URL:
```bash
curl -sL -H "Authorization: Bearer $SLACK_TOKEN" \
  --max-time 60 -o "$dest/$filename" "$url_private"
```

## 5. Admin Artifacts to Archive

These don't import into Mattermost but should be preserved for audit/compliance:

- `integration_logs.json` -- app activity logs
- Channel audit CSV (Business+/Enterprise, from admin export page)
- `content_flags.json` -- if present in export
- Any moderation metadata

Store in an admin-only archive area or inject into a `slack-export-admin` channel in Mattermost.

## Rate Limiting

Slack's May 2025 rate-limit changes did NOT reduce limits for internal customer-built apps:
- `conversations.history`: 50+ req/min, up to 1,000 objects per call
- `files.info` / `files.list`: standard Tier 3/4 limits
- `emoji.list`: Tier 2 (~20 req/min)
- `users.list`: Tier 2

`slack-advanced-exporter` and `slackdump` handle rate limiting with automatic retry and backoff. For very large workspaces, enrichment can take several hours.
