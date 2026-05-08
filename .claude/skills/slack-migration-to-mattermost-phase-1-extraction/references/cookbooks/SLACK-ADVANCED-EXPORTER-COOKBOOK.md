# slack-advanced-exporter Cookbook

Mattermost's `slack-advanced-exporter` is the canonical enrichment tool for official Slack exports.

## Golden Rule

Fetch emails first, then attachments. Each output ZIP becomes the next input ZIP.

## Commands

```bash
./slack-advanced-exporter \
  --input-archive artifacts/raw/slack-export.zip \
  --output-archive artifacts/enriched/export-with-emails.zip \
  fetch-emails --api-token "$SLACK_TOKEN"

./slack-advanced-exporter \
  --input-archive artifacts/enriched/export-with-emails.zip \
  --output-archive artifacts/enriched/export-with-files.zip \
  fetch-attachments --api-token "$SLACK_TOKEN"
```

## Token Scopes

- `users:read`
- `users:read.email`
- `files:read`

Optional but adjacent:
- `emoji:read`

## Validation Checklist

After `fetch-emails`:
- inspect `users.json`
- confirm emails are populated for the vast majority of non-bot users

After `fetch-attachments`:
- confirm binary files are present
- compare downloaded files against `url_private` references

## Recovery Pattern

If `fetch-attachments` leaves gaps:
1. parse remaining file refs from the export JSON
2. fetch directly using `Authorization: Bearer $SLACK_TOKEN`
3. write missing file report
4. repackage into a new ZIP and update manifest

## Common Mistakes

- reusing the raw ZIP path as output
- using the wrong token type (`xoxc-` instead of `xoxp-` or `xoxb-`)
- skipping email enrichment and then wondering why user matching breaks
