# Headless Server Authentication

Slackdump's default auth opens a browser (Ez-Login 3000). On headless servers without a display, use one of these alternatives.

## Option 1: Token + Cookie (Recommended for Headless)

Extract credentials from an existing browser session on your local machine:

### Get the `d` cookie (`xoxd-...`)
1. Open Slack in Chrome/Firefox on your local machine
2. Press F12 > Application tab > Cookies
3. Find the `d` cookie -- value starts with `xoxd-`

### Get the token (`xoxc-...`)
1. Press F12 > Network tab
2. Filter by `api`
3. Click any API call
4. In request headers, find the token starting with `xoxc-`

### Set Environment Variables
```bash
export SLACK_TOKEN="xoxc-your-token-here"
export SLACK_COOKIE="xoxd-your-cookie-here"
```

Or add to `config.env`:
```bash
SLACK_TOKEN="xoxc-..."
SLACK_COOKIE="xoxd-..."
```

Slackdump picks these up automatically. No browser needed.

### Token Lifetime
`xoxc-` tokens are session-bound. They expire when:
- You log out of Slack in the browser
- The session times out (varies by workspace settings)
- Admin revokes sessions

For long exports, keep the browser session alive. If the token expires mid-export, slackdump supports resumable downloads -- just re-auth and restart.

## Option 2: Run Slackdump Locally, Transfer the Export

If token extraction is too fiddly:

1. Download slackdump on your local machine (Mac/Win/Linux)
2. Run the export locally:
   ```bash
   slackdump export -o slack_export.zip -files
   ```
3. SCP the ZIP to the server:
   ```bash
   scp slack_export.zip user@server:~/slack-to-mattermost/workdir/
   ```
4. On the server, skip straight to transform:
   ```bash
   ./migrate.sh transform
   ./migrate.sh import
   ```

This is the simplest approach when you have a fast local machine and reasonable upload bandwidth. For multi-GB exports, consider `rsync --progress` instead of `scp`.

## Option 3: Slack App OAuth Token (`xoxp-...`)

For enrichment tasks (not slackdump itself), use a proper Slack App token:

1. Create a Slack App at `api.slack.com/apps`
2. Add User Token Scopes (see main skill for full list)
3. Install to workspace
4. Copy the User OAuth Token (`xoxp-...`)

This token is used by:
- `slack-advanced-exporter` for fetching emails and attachments
- Direct API calls for `emoji.list`
- File download verification

**Note:** `xoxp-` tokens are different from `xoxc-` tokens. Slackdump uses `xoxc-` + `xoxd-` cookie. The Slack API and slack-advanced-exporter use `xoxp-` or `xoxb-`.

## Security Notes

- Revoke all tokens after migration is complete
- Delete the Slack App after verification
- `config.env` contains credentials -- add to `.gitignore`
- The `xoxc-` token grants full access to your Slack session; treat it like a password
- Don't commit tokens to git
