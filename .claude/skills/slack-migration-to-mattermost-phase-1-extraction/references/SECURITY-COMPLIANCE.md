# Security & Compliance

Token management, data handling, legal considerations, and security hardening for the migration process.

## Token Security

### Token Inventory

| Token | Where Used | Sensitivity | Storage |
|-------|-----------|-------------|---------|
| `xoxp-` Slack User OAuth | slack-advanced-exporter, API calls | HIGH: accesses all user-visible data | config.env (gitignored) |
| `xoxb-` Slack Bot Token | Zulip import, limited API | MEDIUM: limited to bot scopes | config.env |
| `xoxc-` Slack Session Token | slackdump | CRITICAL: full session access | env var only, never persist |
| `xoxd-` Slack Cookie | slackdump (paired with xoxc-) | CRITICAL: session credential | env var only, never persist |
| MM admin password | mmctl, import | HIGH: Mattermost admin access | config.env (gitignored) |

### Token Lifecycle

```
CREATE → USE → VERIFY → REVOKE → DELETE

1. CREATE: Generate tokens with minimum required scopes
2. USE: Set as environment variables or in gitignored config files
3. VERIFY: Confirm migration is complete and data is intact
4. REVOKE: Disable tokens in Slack app settings
5. DELETE: Remove the Slack app entirely, clear config.env
```

### Minimum Scopes Rule
Only request the scopes you need:
- **For enrichment only (emails + files + emoji):** `users:read`, `users:read.email`, `files:read`, `emoji:read`
- **For verification (also read conversations):** add `channels:read`, `channels:history`, etc.
- **Never request:** `chat:write`, `files:write`, or any write scopes

## Data Handling

### Sensitive Data in Exports
Slack exports may contain:
- Employee personal information (emails, phone numbers, addresses)
- Confidential business communications
- Financial data shared in channels
- HR/legal discussions (DMs)
- Authentication tokens/secrets inadvertently shared in messages
- Customer PII shared in support channels

### Data Protection Measures

```
1. Encryption at rest
   - Encrypt export ZIPs: gpg -c slack_export.zip
   - Use LUKS/dm-crypt for the working directory
   - Consider full-disk encryption on the migration host

2. Access control
   - Limit migration server access to authorized admins
   - Use SSH keys, not passwords
   - Consider Cloudflare Access/Tunnel for SSH

3. Network security
   - Transfer exports via SCP/SFTP, not HTTP
   - Don't expose migration tools to the internet
   - Use VPN or Cloudflare Tunnel for remote access

4. Retention
   - Delete working copies after verified migration
   - Keep encrypted backups of original export ZIPs
   - Document retention decisions for compliance
```

### gitignore Requirements
Never commit these to version control:
```gitignore
config.env
*.zip
workdir/
tools/
migration.log
emoji/
```

## Legal Considerations

### Export Authorization
- **Workspace Owner/Admin** rights required for official exports
- **Business+ all-conversations export** requires applying to Slack for approval
- Document who authorized the export and when
- Retain the authorization email/confirmation

### Employee Privacy
- Some jurisdictions require employee notification before exporting DMs
- GDPR (EU), CCPA (California), and similar laws may apply
- Consult legal counsel before exporting private conversations
- Consider whether deactivated employees' DMs should be included

### Data Residency
- Slack data may be stored in various regions depending on plan
- Self-hosted Mattermost gives you explicit control over data location
- Ensure the migration host location aligns with your data residency requirements

### Compliance Chain of Custody
For regulated industries, maintain:
```
1. Export manifest: timestamp, who initiated, what was exported
2. SHA256 hashes of all export ZIPs (immutable fingerprint)
3. Transform log: mmetl output, any patches applied
4. Import log: mmctl output, job IDs, success/failure
5. Verification report: counts reconciliation
6. Token creation and revocation timestamps
```

## Security Checklist

### Before Migration
- [ ] Migration server hardened (no root SSH, firewall, fail2ban)
- [ ] Export ZIPs stored on encrypted filesystem
- [ ] config.env has restrictive permissions (`chmod 600`)
- [ ] config.env is in .gitignore
- [ ] Slack tokens created with minimum scopes
- [ ] Legal/HR approval for DM export (if applicable)

### During Migration
- [ ] Working directory not accessible to other users
- [ ] No tokens in shell history (`set +o history` before setting env vars)
- [ ] Transfer via encrypted channel (SCP, not HTTP)
- [ ] Monitor for unauthorized access to migration server

### After Migration
- [ ] Slack tokens revoked in Slack app settings
- [ ] Slack app deleted from workspace
- [ ] config.env tokens removed or file deleted
- [ ] Working directory cleared (export ZIPs, JSONL, temp files)
- [ ] Encrypted backup of original export stored securely
- [ ] Migration server access reviewed/restricted
- [ ] Document what was migrated and what was left behind

## Incident Response

### If tokens are compromised
1. Immediately revoke the token in Slack app settings
2. Delete the Slack app
3. Notify workspace admins
4. Audit Slack access logs for unauthorized activity
5. Re-create tokens with new app if migration is still in progress

### If export data is exposed
1. Assess what data was in the export (channels, DMs, files)
2. Notify affected users per applicable privacy laws
3. Identify and close the exposure vector
4. Document the incident
5. Consider re-exporting with narrower scope if possible
