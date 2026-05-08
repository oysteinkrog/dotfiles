# SMTP Setup for Mattermost

> Configure email delivery so password resets, notifications, and invitations work.
> SMTP must be working before user activation -- password reset emails are the primary onboarding path.

## config.json EmailSettings

```json
{
  "EmailSettings": {
    "EnableSignUpWithEmail": true,
    "EnableSignInWithEmail": true,
    "SendEmailNotifications": true,
    "RequireEmailVerification": false,
    "FeedbackName": "Mattermost",
    "FeedbackEmail": "noreply@yourdomain.com",
    "ReplyToAddress": "noreply@yourdomain.com",
    "SMTPServer": "",
    "SMTPPort": "",
    "SMTPUsername": "",
    "SMTPPassword": "",
    "ConnectionSecurity": "STARTTLS",
    "SkipServerCertificateVerification": false,
    "EnableSMTPAuth": true
  }
}
```

Set `RequireEmailVerification` to `false` during migration. Imported users already have verified emails from Slack. Enabling it would force re-verification and block logins.

## Provider-Specific Configuration

### AWS SES

```json
{
  "SMTPServer": "email-smtp.us-east-1.amazonaws.com",
  "SMTPPort": "587",
  "SMTPUsername": "YOUR_SES_SMTP_USERNAME",
  "SMTPPassword": "YOUR_SES_SMTP_PASSWORD",
  "ConnectionSecurity": "STARTTLS"
}
```

SES SMTP credentials are NOT your AWS access keys. Generate them in SES Console > SMTP Settings > Create SMTP Credentials. Verify your sending domain or email in SES first (sandbox mode only sends to verified addresses). Request production access to send to any address.

### SendGrid

```json
{
  "SMTPServer": "smtp.sendgrid.net",
  "SMTPPort": "587",
  "SMTPUsername": "apikey",
  "SMTPPassword": "SG.your_api_key_here",
  "ConnectionSecurity": "STARTTLS"
}
```

Username is literally the string `apikey`. Password is your SendGrid API key (starts with `SG.`). Free tier: 100 emails/day. Enough for migration password resets if you batch.

### Mailgun

```json
{
  "SMTPServer": "smtp.mailgun.org",
  "SMTPPort": "587",
  "SMTPUsername": "postmaster@mg.yourdomain.com",
  "SMTPPassword": "YOUR_MAILGUN_SMTP_PASSWORD",
  "ConnectionSecurity": "STARTTLS"
}
```

### Gmail SMTP Relay

```json
{
  "SMTPServer": "smtp.gmail.com",
  "SMTPPort": "587",
  "SMTPUsername": "your-account@gmail.com",
  "SMTPPassword": "YOUR_APP_PASSWORD",
  "ConnectionSecurity": "STARTTLS"
}
```

Requires a Google App Password (not your account password). Go to Google Account > Security > 2-Step Verification > App Passwords. Gmail limits: 500 emails/day for personal, 2000/day for Workspace. Fine for small teams, not for 500+ user migration.

### Self-Hosted Postfix (localhost relay)

```json
{
  "SMTPServer": "127.0.0.1",
  "SMTPPort": "25",
  "SMTPUsername": "",
  "SMTPPassword": "",
  "ConnectionSecurity": "",
  "EnableSMTPAuth": false
}
```

```bash
# Install Postfix on the Mattermost server
apt install -y postfix
# Choose "Internet Site" during setup, enter your domain

# Verify it's listening
ss -tlnp | grep :25
```

Postfix on localhost has no auth overhead and is the fastest option. However, emails from an unknown IP will go to spam unless you configure SPF, DKIM, and DMARC for your domain.

## Testing Email Delivery

### From System Console

1. Go to System Console > Environment > SMTP
2. Fill in all fields
3. Click "Test Connection" button
4. Check that the test email arrives

### From Command Line

```bash
# Send a test email using the Mattermost invite system
mmctl user invite user@example.com myteam

# Or trigger a password reset (also tests SMTP)
mmctl user reset-password user@example.com
```

### Direct SMTP Test (bypass Mattermost)

```bash
# Test SMTP connectivity from the server
sudo apt install -y swaks
swaks --to test@yourdomain.com \
  --from noreply@yourdomain.com \
  --server smtp.example.com:587 \
  --auth LOGIN \
  --auth-user noreply@yourdomain.com \
  --auth-password 'YOUR_PASSWORD' \
  --tls
```

## Troubleshooting

### Connection Refused (port 587/465/25)

```bash
# Check if the port is reachable from the server
telnet smtp.example.com 587
# Or:
nc -zv smtp.example.com 587

# Some VPS providers block outbound port 25 by default
# Use port 587 (STARTTLS) or 465 (implicit TLS) instead
# Hetzner blocks port 25 on new accounts -- request unblock or use 587
```

### Authentication Failures

- SES: You used AWS access keys instead of SMTP credentials. They are different.
- SendGrid: Username must be literally `apikey`, not your account email.
- Gmail: Must use an App Password, not your account password.
- General: URL-encode special characters in passwords when set via environment variables.

### TLS / Certificate Errors

```json
{
  "ConnectionSecurity": "STARTTLS",
  "SkipServerCertificateVerification": false
}
```

- `STARTTLS` (port 587): starts unencrypted, upgrades to TLS. Most common.
- `TLS` (port 465): implicit TLS from the start.
- Empty string (port 25): no encryption. Only safe for `127.0.0.1` (localhost Postfix).

If you get certificate errors with a private/internal CA, set `SkipServerCertificateVerification: true` temporarily but fix the CA trust chain for production.

### Emails Going to Spam

Configure these DNS records for your sending domain:

**SPF** (TXT record on `yourdomain.com`):
```
v=spf1 include:amazonses.com ~all
```
Replace `amazonses.com` with your provider's SPF include (e.g., `sendgrid.net`, `mailgun.org`).

**DKIM**: Provider-specific. Follow SES/SendGrid/Mailgun docs to add the DKIM CNAME or TXT records.

**DMARC** (TXT record on `_dmarc.yourdomain.com`):
```
v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com
```

All three are required for reliable inbox delivery. Without them, Gmail and Microsoft 365 will flag your emails.

### Password Reset Flow

When a user visits `https://chat.yourdomain.com/reset_password` and enters their email:

1. Mattermost looks up the user by email address
2. Generates a time-limited reset token (valid ~24 hours)
3. Sends an email with a link: `https://chat.yourdomain.com/reset_password_complete?token=TOKEN`
4. User clicks the link, sets a new password
5. User is logged in and sees all their imported channels and messages

If the email doesn't arrive: check Mattermost logs at `/opt/mattermost/logs/mattermost.log` for SMTP errors. Search for `smtp` or `email`:

```bash
grep -i smtp /opt/mattermost/logs/mattermost.log | tail -20
grep -i "error.*email" /opt/mattermost/logs/mattermost.log | tail -20
```
