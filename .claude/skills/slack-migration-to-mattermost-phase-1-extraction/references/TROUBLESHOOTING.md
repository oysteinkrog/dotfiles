# Troubleshooting

## Export Issues

### slackdump hangs during authentication
**Cause:** Headless server with no display, Ez-Login 3000 can't open browser.
**Fix:** Use token+cookie method or run slackdump locally. See `references/AUTHENTICATION.md`.

### slackdump rate limited / slow
**Cause:** Slack rate limits API calls (50+ req/min for internal apps).
**Fix:** Normal behavior for large workspaces. Slackdump handles retries/backoff automatically. Export may take hours for workspaces with thousands of channels.

### Official export email never arrives
**Cause:** Large workspace, Slack processing queue, or email filtering.
**Fix:** Check spam folder. For very large workspaces, Slack can take 24+ hours. Check the export page directly -- sometimes the download link appears before the email.

### Official export missing DMs / private channels
**Cause:** You're on Pro plan (only exports public channels).
**Fix:** Upgrade to Business+ and apply for all-conversations export approval. Or use slackdump as primary export (gets everything you can access).

### Export ZIP is unexpectedly small
**Cause:** Only public channels exported (Pro plan), or date range filter too narrow.
**Fix:** Verify plan tier. Check date range settings. Confirm all-conversations export is approved on Business+.

## Enrichment Issues

### slack-advanced-exporter: "email not found" for many users
**Cause:** Workspace hides email addresses, or token lacks `users:read.email` scope.
**Fix:** Ensure Slack App has `users:read.email` scope. Some workspaces restrict email visibility even to admins -- check Slack admin settings.

### File downloads fail with 403
**Cause:** Token expired, lacks `files:read` scope, or file was deleted.
**Fix:** Regenerate token. Verify scope. Deleted files are irrecoverable -- log them and move on.

### emoji.list returns ok=false
**Cause:** Token invalid or lacks `emoji:read` scope.
**Fix:** Verify token is valid (`curl -s -H "Authorization: Bearer $TOKEN" https://slack.com/api/auth.test`). Add `emoji:read` to app scopes.

## Transform Issues

### mmetl: nil pointer / panic errors
**Cause:** Corrupt ZIP, unexpected JSON structure, or mmetl version bug.
**Fix:**
1. Don't unzip and re-zip the Slack export (breaks expected structure)
2. Try importing in smaller batches
3. Update mmetl to latest version
4. Check that the ZIP isn't truncated (verify file size matches expected)

### "User roles are not consistent with guest status"
**Cause:** Guest users assigned conflicting `system_user` + `guest` roles in JSONL.
**Fix:** The transform script auto-fixes this. If it persists, manually patch the JSONL:
```bash
python3 -c "
import json, sys
for line in open(sys.argv[1]):
    obj = json.loads(line.strip())
    if obj.get('type') == 'user':
        u = obj.get('user', {})
        r = u.get('roles', '')
        if 'guest' in r and 'system_user' in r:
            u['roles'] = r.replace('system_user', '').strip()
    print(json.dumps(obj))
" mattermost_import.jsonl > fixed.jsonl
mv fixed.jsonl mattermost_import.jsonl
```

### Messages exceeding Mattermost character limit
**Cause:** Slack allows 40,000 chars per message; Mattermost defaults to 4,000.
**Fix:** In Mattermost System Console > General > Restrictions, increase `MaxPostSize` to 16383 BEFORE importing. Messages longer than the limit are truncated during import.

### Unicode channel names imported as hex IDs (e.g., `c3afdb16`)
**Cause:** mmetl can't handle non-ASCII channel names.
**Fix:** Rename channels to ASCII in Slack before exporting. Or rename in Mattermost after import. No automated fix exists.

### mmetl: "team not found" or team-related errors
**Cause:** The `--team` name passed to mmetl doesn't match what exists on your Mattermost server.
**Fix:** The team specified in mmetl transform is embedded in the JSONL. The actual team must exist on the server before import. Create it manually or let `./migrate.sh import` create it.

## Import Issues

### Import stuck at "in_progress" for hours
**Cause:** Disk full, memory exhaustion, extremely long messages, or very large import.
**Fix:**
1. Check server logs: `docker logs mattermost` or `/opt/mattermost/logs/`
2. Check disk space: `df -h`
3. Check memory: `free -h`
4. For Docker: ensure Postgres container has adequate memory (8GB+ for 1000 users)

### "We could not count the users" error
**Cause:** Importing into server with existing users whose emails match import data.
**Fix:** Expected behavior -- import merges matching accounts. Try with `mmctl import validate` first to preview. Edge cases may require manual user cleanup.

### "websocket: could not find upgrade header"
**Cause:** Reverse proxy (Nginx/Cloudflare) not passing WebSocket upgrade headers.
**Fix:** This is a Phase 2 server setup issue, not an extraction issue. Ensure Nginx has the WebSocket location block with `Upgrade` and `Connection` headers.

### Upload fails with timeout
**Cause:** Large import ZIP, slow connection, or mmctl timeout.
**Fix:** If using Docker, you may need to increase Nginx `client_max_body_size`. For very large ZIPs, consider using `split-import` to break into smaller batches.

## General

### How to verify export completeness
```bash
# Count entities in the JSONL
grep -c '"type":"user"' mattermost_import.jsonl
grep -c '"type":"channel"' mattermost_import.jsonl
grep -c '"type":"post"' mattermost_import.jsonl

# Compare against Slack channel audit CSV (if available)
# Compare user count against Slack admin user list
```

### How to do a dry run
```bash
# Validate without importing
mmctl import validate ./mattermost-bulk-import.zip

# Import to a throwaway Mattermost instance first
# (spin up a temporary Docker instance for testing)
docker run -d --name mm-test -p 8065:8065 mattermost/mattermost-preview
```

### Cleanup after migration
1. Revoke Slack API tokens
2. Delete the Slack App
3. Secure or delete export ZIPs (contain sensitive data)
4. Remove tokens from config.env
5. Consider encrypting backup copies of export ZIPs
