# Browser Automation for Export Acquisition

For Business+ workspaces with recurring exports, automate the export UI flow and download without manual intervention. This is the "zero-click after initial setup" approach.

## Why Automate?

Slack has **no public API to trigger workspace exports**. The only documented path is:
1. Admin clicks through the UI
2. Slack emails when ready
3. Admin returns to download

For a baseline+delta migration strategy, you may need to trigger and download exports weekly. Automating this saves admin time and reduces human error.

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Playwright   │────▶│  Slack Admin  │────▶│  Export ZIP   │
│  Worker       │     │  UI          │     │  Download     │
└──────────────┘     └──────────────┘     └──────────────┘
                           │
                           ▼ (email notification)
                     ┌──────────────┐
                     │  Mailbox     │
                     │  Poller      │────▶ Trigger download
                     └──────────────┘
```

## Playwright Export Trigger

```typescript
// slack-export-trigger.ts
import { chromium } from 'playwright';

async function triggerSlackExport() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  // Login to Slack
  await page.goto('https://your-workspace.slack.com/admin');
  // You'll need to handle authentication - either:
  // 1. Use saved cookies from a prior session
  // 2. Go through the login flow with stored credentials
  // 3. Use SSO if applicable

  // Navigate to export page
  await page.goto('https://your-workspace.slack.com/services/export');

  // Select date range
  // The exact selectors depend on current Slack UI (they change)
  // Use page.waitForSelector() and page.click() with data-testid or aria labels

  // Click Start Export
  // await page.click('[data-qa="export-start-button"]');

  await browser.close();
  console.log('Export triggered. Watch for email notification.');
}
```

**Important caveats:**
- Slack's admin UI changes without notice; selectors may break
- Consider this fragile automation -- have a manual fallback
- Rate limit: don't trigger exports more than once per day

## Mailbox Polling

### Gmail API (Python)
```python
import base64
import time
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

def poll_for_slack_export_email(creds_path, poll_interval=300):
    """Poll Gmail for Slack export-ready notification."""
    creds = Credentials.from_authorized_user_file(creds_path)
    service = build('gmail', 'v1', credentials=creds)

    while True:
        results = service.users().messages().list(
            userId='me',
            q='from:feedback@slack.com subject:"Your Slack data is ready"',
            maxResults=1
        ).execute()

        messages = results.get('messages', [])
        if messages:
            msg = service.users().messages().get(
                userId='me', id=messages[0]['id']
            ).execute()
            
            # Extract download link from email body
            body = base64.urlsafe_b64decode(
                msg['payload']['body']['data']
            ).decode('utf-8')
            
            # Parse and return the download URL
            # (exact parsing depends on Slack's email format)
            return body

        time.sleep(poll_interval)
```

### IMAP (simpler, works with any email)
```python
import imaplib
import email
import time

def poll_imap(host, user, password, poll_interval=300):
    """Poll IMAP mailbox for Slack export notification."""
    while True:
        mail = imaplib.IMAP4_SSL(host)
        mail.login(user, password)
        mail.select('INBOX')
        
        _, messages = mail.search(None, 
            'FROM "feedback@slack.com" SUBJECT "data is ready" UNSEEN')
        
        for msg_id in messages[0].split():
            _, data = mail.fetch(msg_id, '(RFC822)')
            msg = email.message_from_bytes(data[0][1])
            body = msg.get_payload(decode=True).decode()
            # Extract download link
            mail.store(msg_id, '+FLAGS', '\\Seen')
            mail.logout()
            return body
        
        mail.logout()
        time.sleep(poll_interval)
```

## Automated Download

Once you have the export page URL from the email:

```bash
# Download with curl using Slack session cookies
curl -sL \
  -b "d=$SLACK_COOKIE" \
  -o "slack_export_$(date +%Y%m%d).zip" \
  "$EXPORT_DOWNLOAD_URL"

# Verify integrity
unzip -t "slack_export_$(date +%Y%m%d).zip"

# Generate manifest
sha256sum "slack_export_$(date +%Y%m%d).zip" >> export_manifest.txt
echo "$(date -Iseconds) Downloaded export" >> export_manifest.txt
```

## Recurring Export Strategy (Business+)

Business+ supports **scheduled recurring exports** (weekly or monthly). Once enabled:

1. Slack automatically generates exports on the schedule
2. Slack emails when each export is ready
3. Your mailbox poller catches the email
4. Download script fetches the ZIP
5. Enrichment + transform pipeline runs automatically

```bash
#!/bin/bash
# recurring-export-processor.sh
# Run via cron: 0 */6 * * * /path/to/recurring-export-processor.sh

# Check for new export email
DOWNLOAD_URL=$(python3 check_for_export_email.py)
[[ -z "$DOWNLOAD_URL" ]] && exit 0

# Download
EXPORT_FILE="slack_export_$(date +%Y%m%d).zip"
curl -sL -b "d=$SLACK_COOKIE" -o "$EXPORT_FILE" "$DOWNLOAD_URL"

# Hash for manifest
sha256sum "$EXPORT_FILE" >> export_manifest.txt

# Enrich
./slack-advanced-exporter \
  --input-archive "$EXPORT_FILE" \
  --output-archive "enriched_${EXPORT_FILE}" \
  fetch-emails --api-token "$SLACK_TOKEN"

./slack-advanced-exporter \
  --input-archive "enriched_${EXPORT_FILE}" \
  --output-archive "complete_${EXPORT_FILE}" \
  fetch-attachments --api-token "$SLACK_TOKEN"

# Transform
SLACK_EXPORT_ZIP="complete_${EXPORT_FILE}" ./migrate.sh transform

echo "$(date): Delta export processed: $EXPORT_FILE" >> migration.log
```

## Channel Audit CSV

Also downloadable from the same admin area. Contains:
- Channel name, ID, creation date
- Member count
- Message count
- Last activity date

Useful for migration planning (what to migrate, what to archive) and post-migration verification.

```bash
# Download channel audit CSV (manual or via Playwright)
# Compare against import results
python3 -c "
import csv
with open('channel_audit.csv') as f:
    reader = csv.DictReader(f)
    for row in reader:
        print(f'{row[\"name\"]}: {row[\"num_members\"]} members, {row[\"num_messages\"]} msgs')
"
```

## Limitations

- Slack UI selectors change without notice -- Playwright scripts need maintenance
- Session cookies expire -- need periodic refresh
- Export processing time varies (minutes to days for large workspaces)
- Email notifications can be delayed
- This entire approach is "unofficial" -- Slack doesn't provide a programmatic export API
