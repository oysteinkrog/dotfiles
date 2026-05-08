# config.env Full Reference

Copy `config.env.example` to `config.env`. Never commit `config.env` to git.

## Required Variables

| Variable | Example | Description |
|----------|---------|-------------|
| `WORKSPACE_NAME` | `acme-slack` | Workspace label written into intake/readiness reports |
| `HANDOFF_JSON` | `/abs/path/to/handoff.json` | Machine-readable Phase 1 handoff contract |
| `IMPORT_ZIP` | `/abs/path/to/mattermost-bulk-import.zip` | Final import bundle from Phase 1 |
| `MATTERMOST_URL` | `https://chat.acme.com` | Public Mattermost URL |
| `MATTERMOST_ADMIN_USER` | `admin` | Admin user used by `mmctl` scripts |
| `MATTERMOST_ADMIN_PASS` | `super-secret` | Admin password used by `mmctl` scripts |
| `MATTERMOST_TEAM_NAME` | `acme` | Target team name for smoke checks and imports |
| `POSTGRES_DSN` | `postgres://mmuser:...` | Data source written into rendered `config.json` |
| `SMOKE_DATABASE_URL` | empty | Optional override for smoke/reconciliation queries; if unset, `operate.sh` prefers `POSTGRES_DSN` and then falls back to `STAGING_DATABASE_URL` / `DATABASE_URL`. Loopback hosts are queried via `TARGET_HOST`; external DSNs also route via `TARGET_HOST` when local `psql` is unavailable. |
| `DATABASE_URL` | `postgres://mmuser:...` | Legacy/general DB endpoint for smoke tests and cutover reconciliation when `SMOKE_DATABASE_URL` / `POSTGRES_DSN` are not more appropriate; loopback hosts route through `TARGET_HOST`, and external DSNs do too when the operator machine lacks `psql`. |

## Optional: Host and Deployment

| Variable | Default | Description |
|----------|---------|-------------|
| `PHASE2_WORKSPACE_ROOT` | `./workdir` | Where `operate.sh` writes rendered configs and reports |
| `TARGET_HOST` | empty | Remote host for `ssh` provisioning/deploy execution |
| `TARGET_SSH_USER` | `deploy` | SSH user for remote execution |
| `DEPLOY_METHOD` | `apt` | `apt` or `docker` |
| `PROVISION_MODE` | `plan` | `plan`, `local`, or `ssh` |
| `DEPLOY_MODE` | `plan` | `plan`, `local`, or `ssh` |

## Optional: Rendered Config

| Variable | Default | Description |
|----------|---------|-------------|
| `MATTERMOST_SERVICE_NAME` | `mattermost` | systemd service name |
| `MATTERMOST_CONFIG_PATH` | `/opt/mattermost/config/config.json` | Target config path on the server |
| `MATTERMOST_DATA_PATH` | `/opt/mattermost/data` | Docker-mode data mount on the server |
| `MATTERMOST_LISTEN_ADDRESS` | `127.0.0.1:8065` | Listen address written into `config.json` |
| `ENABLE_LOCAL_MODE` | `0` | Set to `1` when you want the rendered config to expose the local-mode socket for server-side `mmctl --local` operations. In exact remote-flow validation, `operate.sh` uses this to materialize an SSH-backed `mmctl` wrapper that drives the server-bundled binary. |
| `LOCAL_MODE_SOCKET_PATH` | `/var/tmp/mattermost_local.socket` | Unix socket path used when local mode is enabled |
| `MMCTL_REMOTE_IMPORT_DIR` | `/opt/mattermost/data/imports` for docker, `/tmp/mattermost-imports` otherwise | Server-side staging path used by the SSH-backed `mmctl` wrapper |
| `NGINX_SITE_PATH` | `/etc/nginx/sites-available/mattermost.conf` | Nginx site file |
| `NGINX_SITE_LINK` | `/etc/nginx/sites-enabled/mattermost.conf` | Nginx symlink path |
| `NGINX_ENABLE_TLS` | `0` | Set to `1` when Nginx should render a TLS listener and require cert/key paths |
| `NGINX_CERT_PATH` | `/etc/nginx/ssl/origin.pem` | Origin certificate path |
| `NGINX_KEY_PATH` | `/etc/nginx/ssl/origin-key.pem` | Origin key path |
| `ALLOW_CORS_ORIGINS` | empty | Comma-separated trusted origins for `AllowCorsFrom` |

## Optional: SMTP and Activation

| Variable | Default | Description |
|----------|---------|-------------|
| `SMTP_SERVER` | empty | SMTP host for rendered config and live verification |
| `SMTP_PORT` | `587` | SMTP port |
| `SMTP_USERNAME` | empty | SMTP username |
| `SMTP_PASSWORD` | empty | SMTP password |
| `SMTP_TEST_EMAIL` | empty | Test email address for activation proof during cutover |
| `SMTP_PROOF_FILE` | empty | Optional screenshot or `.eml` artifact checked by `verify-user-activation.sh` |

## Optional: Staging, Restore, and Rollback

| Variable | Default | Description |
|----------|---------|-------------|
| `STAGING_URL` | `MATTERMOST_URL` | Separate staging URL if needed |
| `STAGING_DATABASE_URL` | empty | Separate staging DB URL for smoke checks when `POSTGRES_DSN` / `SMOKE_DATABASE_URL` are not sufficient |
| `BACKUP_PATH` | empty | Backup used by `restore` |
| `SCRATCH_DB_URL` | empty | Scratch DB target used by `restore` |
| `ROLLBACK_OWNER` | empty | Name/identifier for the rollback owner in the readiness gate |
| `ROLLBACK_DB_BACKUP` | empty | Backup file used by `rollback` |
| `ROLLBACK_CONFIG_BACKUP` | empty | Config backup directory restored by `rollback` |
| `ROLLBACK_CONFIG_TARGET` | `/opt/mattermost/config` | Config restore target |
| `ROLLBACK_DATA_BACKUP` | empty | Data backup directory restored by `rollback` |
| `ROLLBACK_DATA_TARGET` | `/opt/mattermost/data` | Data restore target |
