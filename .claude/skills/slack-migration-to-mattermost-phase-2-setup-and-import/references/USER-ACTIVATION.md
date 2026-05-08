# User Activation & Onboarding After Import

> Complete guide to getting users from "imported but dormant" to "actively using Mattermost."
> Covers password resets, communication, app distribution, role mapping, and rollout timeline.

## How Imported Users Work

When `mmctl import process` creates users from the Slack export JSONL, each user gets:

- Username (from Slack display name, lowercased, special chars replaced)
- Email address (from Slack profile)
- Membership in all their Slack channels (mapped to Mattermost channels)
- All their DM and group DM history
- Status: **active but no password set**

Users cannot log in until they set a password via the reset flow or an admin sets one for them.

## Password Reset Flow (Primary Method)

This is the recommended activation method for most migrations.

### What Users Do

1. Navigate to `https://chat.yourdomain.com/reset_password`
2. Enter their work email (same address they used in Slack)
3. Check their inbox for "Reset Your Password" email from Mattermost
4. Click the link in the email (valid ~24 hours)
5. Set a new password (minimum 8 characters by default)
6. Land on the Mattermost home page with all their channels visible

### Prerequisites

- SMTP must be configured and tested (see `references/SMTP-SETUP.md`)
- `EnableSignUpWithEmail` must be `true`
- `RequireEmailVerification` must be `false`
- `SiteURL` must be correct (email links use it)

### Testing Before Rollout

Test with your own account first:

```bash
# Find your imported user
mmctl user search youremail@yourdomain.com

# Trigger a password reset from the web UI or via mmctl
# Then check your inbox
```

## Bulk Password Setting (Admin Override)

For small teams or VIP users who need immediate access, set passwords directly:

```bash
# Single user
mmctl user change-password jsmith --password 'Welcome2Mattermost!'

# Bulk set from a CSV (username,password)
while IFS=',' read -r user pass; do
  mmctl user change-password "$user" --password "$pass"
  echo "Set password for: $user"
done < users_passwords.csv
```

Generate temporary passwords:

```bash
# Generate a unique password per user
mmctl user list --all --json | jq -r '.[].username' | while read -r user; do
  PASS=$(openssl rand -base64 12)
  mmctl user change-password "$user" --password "$PASS"
  echo "$user,$PASS" >> temp_passwords.csv
done
```

**Security note:** If you distribute temporary passwords, instruct users to change them immediately. Consider requiring password change on first login (System Console > Security > Password Requirements).

## Communication Templates

### Email Announcement (Send 1-2 days before cutover)

```
Subject: We're moving from Slack to Mattermost -- action required

Hi team,

We're migrating from Slack to Mattermost. Your account, channels, and
message history have already been transferred.

To activate your account:

  1. Go to https://chat.yourdomain.com/reset_password
  2. Enter your work email address
  3. Check your inbox for a password reset link
  4. Set your new password
  5. You're in -- all your channels and history are waiting

Download the apps:
  - Desktop (Mac/Windows/Linux): https://mattermost.com/apps/
  - iOS: https://apps.apple.com/app/mattermost/id1257222717
  - Android: https://play.google.com/store/apps/details?id=com.mattermost.rn

When adding the server in the app, use: https://chat.yourdomain.com

Questions? Reply to this email or message #migration-help in Mattermost.

-- IT Team
```

### Slack Announcement (Post in #general before cutover)

```
:mega: *Mattermost is live!*

Your Slack messages, channels, and files have been migrated.

:one: Go to https://chat.yourdomain.com/reset_password
:two: Enter your work email to get a password reset link
:three: Download the desktop/mobile app: https://mattermost.com/apps/
:four: Use server URL: https://chat.yourdomain.com

Slack will be set to read-only on [DATE]. Start using Mattermost today.
Questions? Ask in #migration-help (already created in Mattermost).
```

## Desktop and Mobile App Distribution

### Desktop App

Download from https://mattermost.com/apps/ or use package managers:

```bash
# macOS
brew install --cask mattermost

# Ubuntu/Debian
curl -L https://releases.mattermost.com/desktop/6.3.0/mattermost-desktop_6.3.0-1_amd64.deb -o mattermost-desktop.deb
sudo dpkg -i mattermost-desktop.deb

# Windows (winget)
winget install Mattermost.MattermostDesktop
```

For managed fleets (Jamf, Intune, etc.), deploy the MSI/PKG installer with the server URL pre-configured.

### Mobile App

- iOS: [App Store](https://apps.apple.com/app/mattermost/id1257222717)
- Android: [Google Play](https://play.google.com/store/apps/details?id=com.mattermost.rn)

Users enter the server URL (`https://chat.yourdomain.com`) on first launch.

### Pre-configuring Server URL

Create a managed app config (MDM) or use Mattermost's `config.json`:

```json
{
  "NativeAppSettings": {
    "AppCustomURLSchemes": ["mattermost://"],
    "AppDownloadLink": "https://mattermost.com/apps/",
    "AndroidAppDownloadLink": "https://play.google.com/store/apps/details?id=com.mattermost.rn",
    "IosAppDownloadLink": "https://apps.apple.com/app/mattermost/id1257222717"
  }
}
```

## Role Mapping (Slack to Mattermost)

| Slack Role | Mattermost Role | How to Set |
|------------|-----------------|------------|
| Workspace Owner | System Admin | `mmctl roles system-admin username` |
| Workspace Admin | System Admin or Team Admin | `mmctl roles system-admin username` |
| Channel Manager | Channel Admin | Set per-channel in System Console |
| Regular Member | Member | Default, no action needed |
| Guest | Guest | `mmctl user convert --guest username` |
| Bot | Bot Account | `mmctl user convert --bot username` |

```bash
# Promote Slack admins to Mattermost system admins
for admin in jsmith mjones akumar; do
  mmctl roles system-admin "$admin"
  echo "Promoted $admin to system admin"
done
```

## Deactivated User Handling

Slack users who were deactivated before export appear in the JSONL with `"delete_at": <timestamp>`. They are imported as deactivated users in Mattermost.

```bash
# List deactivated users
mmctl user list --all --json | jq -r '.[] | select(.delete_at > 0) | .username'

# Their messages and channel history are preserved
# They cannot log in
# Reactivate if needed:
mmctl user activate former_employee
```

Keep deactivated users in the system -- their message history provides context in channels. Only delete users if legally required (GDPR right-to-erasure).

## Guest User Activation

Mattermost supports guest accounts with restricted access (specific channels only, no team browsing).

```bash
# Convert an imported user to guest
mmctl user convert --guest external_contractor

# Guests can only see channels they're explicitly added to
mmctl channel users add myteam:project-x external_contractor

# Demote from guest back to full member
mmctl user convert --user external_contractor
```

Guest accounts are ideal for imported Slack guest/external users.

## Bot Account Migration

Slack bots appear in the export as users. Convert them to Mattermost bot accounts:

```bash
# Convert user to bot
mmctl user convert --bot slackbot_name

# Bots don't consume a license seat
# They can't log in interactively
# They post via personal access tokens or incoming webhooks

# Create a token for the bot
mmctl token generate slackbot_name "migration token"
# Save the printed token -- it won't be shown again
```

For Slack incoming webhooks, create equivalent Mattermost incoming webhooks in System Console > Integrations > Incoming Webhooks.

## SSO / SAML Setup (Enterprise)

If you plan to use SSO instead of email/password:

1. Complete the migration with email/password first
2. Verify all users can log in
3. Configure SAML/LDAP/OAuth in System Console > Authentication
4. Map SAML attributes to Mattermost fields (email, username, first/last name)
5. Enable the SSO provider
6. Users log in via SSO on next session

Supported providers: Okta, OneLogin, Azure AD/Entra ID, Google Workspace SAML, ADFS, generic SAML 2.0.

```json
{
  "SamlSettings": {
    "Enable": true,
    "IdpUrl": "https://your-idp.example.com/sso/saml",
    "IdpDescriptorUrl": "https://your-idp.example.com/metadata",
    "IdpCertificateFile": "/opt/mattermost/config/saml-idp.crt",
    "EmailAttribute": "email",
    "UsernameAttribute": "username",
    "FirstNameAttribute": "firstName",
    "LastNameAttribute": "lastName"
  }
}
```

**Critical:** The `EmailAttribute` in SAML must match the email addresses imported from Slack. This is how Mattermost links SSO identities to existing accounts.

## Rollout Timeline

### Recommended Phased Rollout

```
Day -7:  Pilot group (5-10 IT/power users)
         - Activate accounts, test all features
         - Verify channels, DMs, file access
         - Test desktop and mobile apps
         - Confirm SMTP/password reset works

Day -3:  Early adopters (department heads, team leads, ~20% of org)
         - Send activation email to this group only
         - Gather feedback, fix issues
         - Test Calls plugin, integrations

Day 0:   Full company rollout
         - Send activation email to all remaining users
         - Post Slack announcement
         - Set Slack to read-only (or announce freeze date)

Day +1:  Final delta import
         - Export last 24h from Slack (Phase 1 skill)
         - Import delta to catch messages sent during transition

Day +3:  Slack wind-down
         - Confirm all active users have logged into Mattermost
         - Follow up with stragglers via email

Day +7:  Slack decommission
         - Revoke Slack API tokens
         - Delete migration Slack app
         - Archive Slack workspace (or keep read-only if paid plan)

Day +30: Post-migration cleanup
         - Disable EnableOpenServer
         - Review and archive unused channels
         - Set up SSO if planned
         - Enable MFA if required
```

### Tracking Activation Progress

```bash
# Count users who have logged in (last login timestamp > 0)
TOTAL=$(mmctl user list --all --json | jq length)
ACTIVE=$(mmctl user list --all --json | jq '[.[] | select(.last_activity_at > 0)] | length')
echo "Activated: $ACTIVE / $TOTAL ($(( ACTIVE * 100 / TOTAL ))%)"

# List users who have NOT logged in yet
mmctl user list --all --json | \
  jq -r '.[] | select(.last_activity_at == 0 and .delete_at == 0) | "\(.username)\t\(.email)"'
```

Send follow-up emails to users who haven't activated after 3 days. Direct outreach (Slack DM or personal email) for stragglers after 5 days.
