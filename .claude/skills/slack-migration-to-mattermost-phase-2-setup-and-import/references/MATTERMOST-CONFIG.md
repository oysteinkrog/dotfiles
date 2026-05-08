# Mattermost Configuration Deep Dive

> Every config.json section relevant to migration, explained with production values.
> File location: `/opt/mattermost/config/config.json` (APT install).
> Docker: mounted as `./volumes/app/mattermost/config/config.json`.

## How Configuration Works

Mattermost has three configuration layers, applied in this priority order:

1. **Environment variables** (highest priority, cannot be overridden by UI)
2. **System Console UI** (persists to database or config.json depending on mode)
3. **config.json file** (base configuration, lowest priority)

When a setting is set via environment variable, it appears greyed out in the System Console with "This setting has been set through an environment variable" and cannot be changed through the UI.

### Environment Variable Syntax

Every config.json key maps to an environment variable with the `MM_` prefix. Nesting uses underscores. The section name and key are both uppercased.

```
config.json path                        Environment variable
─────────────────────────────────────   ──────────────────────────────────────
ServiceSettings.SiteURL                 MM_SERVICESETTINGS_SITEURL
SqlSettings.DataSource                  MM_SQLSETTINGS_DATASOURCE
FileSettings.MaxFileSize                MM_FILESETTINGS_MAXFILESIZE
EmailSettings.SMTPServer                MM_EMAILSETTINGS_SMTPSERVER
```

Set them in the systemd unit file for APT installs:

```bash
sudo systemctl edit mattermost
# Add under [Service]:
# Environment="MM_SQLSETTINGS_DATASOURCE=postgres://mmuser:pass@localhost/mattermost?sslmode=disable"
# Environment="MM_SERVICESETTINGS_SITEURL=https://chat.yourdomain.com"
```

Or in `.env` for Docker Compose deployments.

**Best practice:** Use environment variables for secrets (database password, SMTP password, S3 keys). Keep non-secret settings in config.json so they are visible in the System Console.

## ServiceSettings

```json
{
  "ServiceSettings": {
    "SiteURL": "https://chat.yourdomain.com",
    "ListenAddress": "127.0.0.1:8065",
    "ConnectionSecurity": "",
    "MaximumLoginAttempts": 10,
    "EnableOpenServer": true,
    "AllowCorsFrom": "",
    "SessionLengthWebInHours": 720,
    "SessionLengthMobileInHours": 720,
    "SessionLengthSSOInHours": 720,
    "EnablePostSearch": true,
    "EnableUserTypingMessages": true,
    "EnableLinkPreviews": true,
    "PostEditTimeLimit": -1,
    "MaxPostSize": 16383,
    "GoroutineHealthThreshold": -1,
    "EnableLocalMode": false,
    "LocalModeSocketLocation": "/var/tmp/mattermost_local.socket"
  }
}
```

Key fields:

| Setting | Migration Notes |
|---------|----------------|
| `SiteURL` | Must match your Cloudflare domain exactly, including `https://`. Used for email links, WebSocket, file URLs. Set this first. |
| `ListenAddress` | Bind to `127.0.0.1:8065` when Nginx fronts the app. Never `0.0.0.0:8065` in production. |
| `MaximumLoginAttempts` | 10 is reasonable. Protects during post-migration when users are trying passwords. |
| `EnableOpenServer` | Set `true` during import so bulk-created users can log in. Set `false` after migration completes. |
| `AllowCorsFrom` | Leave empty unless you have a custom frontend. Wildcards (`*`) are a security risk. |
| `MaxPostSize` | **Set to 16383 before import.** Default 4000 truncates Slack messages (Slack allows 40,000 chars). |
| `PostEditTimeLimit` | `-1` means unlimited. Set to `0` to disable editing, or seconds (e.g., `300` = 5 min). |
| `EnableLocalMode` | Set `true` if you want to run `mmctl --local` on the server without auth. Only accessible via Unix socket. |

## SqlSettings

```json
{
  "SqlSettings": {
    "DriverName": "postgres",
    "DataSource": "postgres://mmuser:YOUR_PASSWORD@localhost:5432/mattermost?sslmode=disable&connect_timeout=10",
    "MaxIdleConns": 20,
    "MaxOpenConns": 100,
    "ConnMaxLifetimeMilliseconds": 3600000,
    "ConnMaxIdleTimeMilliseconds": 300000,
    "Trace": false,
    "QueryTimeout": 30
  }
}
```

### Connection String Format

```
postgres://USER:PASSWORD@HOST:PORT/DATABASE?sslmode=disable&connect_timeout=10
```

For passwords with special characters, URL-encode them: `@` becomes `%40`, `#` becomes `%23`.

| Setting | Recommendation | Why |
|---------|---------------|-----|
| `MaxIdleConns` | 20 | Keeps 20 connections warm. Reduces latency for sporadic queries. |
| `MaxOpenConns` | 100 | Upper bound on DB connections. Match your PostgreSQL `max_connections` (leave headroom for pg admin). |
| `ConnMaxLifetimeMilliseconds` | 3600000 (1hr) | Recycle connections to prevent stale TCP sessions behind load balancers. |
| `QueryTimeout` | 30 | Seconds. Import jobs run their own transactions, so this mainly affects user queries. |
| `Trace` | false | Set `true` temporarily to debug SQL issues. Extremely verbose -- never in production. |

**During import:** The import worker uses its own connections. If you see `pq: too many connections`, increase PostgreSQL's `max_connections` or raise `MaxOpenConns`.

## FileSettings

```json
{
  "FileSettings": {
    "DriverName": "local",
    "Directory": "./data/",
    "MaxFileSize": 52428800,
    "EnablePublicLink": false,
    "AmazonS3AccessKeyId": "",
    "AmazonS3SecretAccessKey": "",
    "AmazonS3Bucket": "",
    "AmazonS3Region": "",
    "AmazonS3Endpoint": "",
    "AmazonS3SSL": true,
    "AmazonS3PathPrefix": ""
  }
}
```

### Local File Storage

Default. Files go to `/opt/mattermost/data/`. Works well for single-server deployments. Back up this directory.

### Cloudflare R2 Configuration

R2 is S3-compatible with zero egress fees. Ideal for Mattermost file storage.

```json
{
  "FileSettings": {
    "DriverName": "amazons3",
    "AmazonS3AccessKeyId": "YOUR_R2_ACCESS_KEY_ID",
    "AmazonS3SecretAccessKey": "YOUR_R2_SECRET_ACCESS_KEY",
    "AmazonS3Bucket": "mattermost-files",
    "AmazonS3Region": "",
    "AmazonS3Endpoint": "YOUR_ACCOUNT_ID.r2.cloudflarestorage.com",
    "AmazonS3SSL": true,
    "AmazonS3PathPrefix": ""
  }
}
```

R2 quirks: leave `Region` empty (R2 auto-selects), use `S3SSL: true`, and the endpoint must NOT include the bucket name. Set `AmazonS3Region` to empty string, not "auto".

`MaxFileSize` is in bytes. Common values: 50 MB = 52428800, 100 MB = 104857600, 250 MB = 262144000.

## TeamSettings

```json
{
  "TeamSettings": {
    "MaxUsersPerTeam": 1500,
    "MaxChannelsPerTeam": 50000,
    "EnableOpenServer": true,
    "RestrictDirectMessage": "any",
    "EnableTeamCreation": false,
    "AllowOpenInvite": false,
    "EnableCustomBrand": false,
    "CustomBrandText": "",
    "RestrictCreationToDomains": "yourdomain.com"
  }
}
```

| Setting | Migration Notes |
|---------|----------------|
| `MaxUsersPerTeam` | Set higher than your Slack workspace member count. Default 50 is too low. |
| `EnableOpenServer` | `true` during migration, `false` after. Controls whether new accounts can be created. |
| `AllowOpenInvite` | Keep `false`. You don't want public signups; users activate via password reset. |
| `EnableTeamCreation` | `false` prevents users from creating random teams. |
| `RestrictCreationToDomains` | Comma-separated list. Restricts signups to your email domain(s). |

## EmailSettings

See `references/SMTP-SETUP.md` for full SMTP configuration. Key fields:

```json
{
  "EmailSettings": {
    "EnableSignUpWithEmail": true,
    "EnableSignInWithEmail": true,
    "EnableSignInWithUsername": true,
    "SendEmailNotifications": true,
    "RequireEmailVerification": false,
    "FeedbackName": "Mattermost",
    "FeedbackEmail": "noreply@yourdomain.com",
    "ReplyToAddress": "noreply@yourdomain.com",
    "SMTPServer": "smtp.example.com",
    "SMTPPort": "587",
    "SMTPUsername": "noreply@yourdomain.com",
    "SMTPPassword": "SMTP_PASSWORD",
    "ConnectionSecurity": "STARTTLS",
    "SkipServerCertificateVerification": false
  }
}
```

**RequireEmailVerification**: Keep `false` during migration. Imported users already have verified emails from Slack. Enabling this would block them from logging in until they re-verify.

## MessageExportSettings

```json
{
  "MessageExportSettings": {
    "EnableExport": false,
    "DailyRunTime": "01:00",
    "ExportFromTimestamp": 0,
    "BatchSize": 10000,
    "GlobalRelaySettings": {
      "CustomerType": "",
      "SMTPUsername": "",
      "SMTPPassword": "",
      "EmailAddress": ""
    }
  }
}
```

If your organization has compliance requirements, enable export. Supports Actiance, Global Relay, and CSV formats. `ExportFromTimestamp` is Unix ms -- set to `0` to export everything, or set to your go-live timestamp to export only post-migration messages.

## PluginSettings

```json
{
  "PluginSettings": {
    "Enable": true,
    "EnableUploads": true,
    "Directory": "./plugins",
    "ClientDirectory": "./client/plugins"
  }
}
```

### Calls Plugin (Voice/Video)

The Calls plugin is built into Mattermost 10.x. Key settings in System Console > Plugins > Calls:

| Setting | Value | Notes |
|---------|-------|-------|
| Enable | true | Enables voice/video calls |
| UDP Server Address | 0.0.0.0 | Binds to all interfaces |
| UDP Server Port | 8443 | Must match your UFW rule |
| ICE Host Override | calls.yourdomain.com | DNS-only record (grey cloud in Cloudflare) |
| Max call participants | 200 | Default 200 |

**Cloudflare limitation:** UDP cannot be proxied through Cloudflare. Create a separate DNS-only (grey cloud) A record for `calls.yourdomain.com` pointing directly to your server IP. The Calls plugin handles its own DTLS encryption.

## RateLimitSettings

```json
{
  "RateLimitSettings": {
    "Enable": true,
    "PerSec": 10,
    "MaxBurst": 100,
    "MemoryStoreSize": 10000,
    "VaryByRemoteAddr": true,
    "VaryByUser": false,
    "VaryByHeader": "X-Forwarded-For"
  }
}
```

When behind Cloudflare + Nginx, set `VaryByHeader` to `X-Forwarded-For` so rate limiting tracks real client IPs, not Nginx's `127.0.0.1`.

## LogSettings

```json
{
  "LogSettings": {
    "EnableConsole": true,
    "ConsoleLevel": "INFO",
    "ConsoleJson": true,
    "EnableFile": true,
    "FileLevel": "INFO",
    "FileJson": true,
    "FileLocation": "",
    "EnableWebhookDebugging": false
  }
}
```

Default log location: `/opt/mattermost/logs/mattermost.log`. Set `FileLevel` to `DEBUG` temporarily during import to catch issues, then revert to `INFO`.

## Full Config Reset via mmctl

```bash
# Read current value
mmctl config get ServiceSettings.SiteURL

# Set a value
mmctl config set ServiceSettings.SiteURL "https://chat.yourdomain.com"
mmctl config set TeamSettings.MaxUsersPerTeam 1500
mmctl config set ServiceSettings.MaxPostSize 16383

# Dump entire config (redacts secrets)
mmctl config show

# Reset a setting to its default
mmctl config reset ServiceSettings.MaxPostSize
```

## Pre-Import Config Checklist

Run these before your first `mmctl import process`:

```bash
mmctl config set ServiceSettings.SiteURL "https://chat.yourdomain.com"
mmctl config set ServiceSettings.MaxPostSize 16383
mmctl config set TeamSettings.MaxUsersPerTeam 1500
mmctl config set TeamSettings.EnableOpenServer true
mmctl config set FileSettings.MaxFileSize 52428800
mmctl config set SqlSettings.MaxIdleConns 20
mmctl config set SqlSettings.MaxOpenConns 100
```

After migration completes, lock down:

```bash
mmctl config set TeamSettings.EnableOpenServer false
mmctl config set TeamSettings.RestrictCreationToDomains "yourdomain.com"
```
