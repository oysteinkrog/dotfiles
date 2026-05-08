# operate.sh Command Reference

`./operate.sh` is the Phase 2 executable spine. It validates intake, renders config, provisions and deploys the server stack, verifies live reachability, rehearses staging, computes readiness, executes production cutover, and runs rollback when needed.

## Commands

| Command | Description | Prereqs |
|---------|-------------|---------|
| `intake` | Build the Phase 2 intake manifest and validate the Phase 1 handoff bundle | `HANDOFF_JSON`, import ZIP |
| `render-config` | Render `config.json`, render Nginx config, and validate the Mattermost config | `MATTERMOST_URL`, `POSTGRES_DSN` |
| `provision` | Build or execute the host-provisioning plan | target host optional |
| `deploy` | Build or execute the Mattermost/Nginx deployment plan | rendered config + rendered nginx |
| `verify-live` | Probe `/api/v4/system/ping`, WebSocket upgrade, and optional SMTP reachability (with retries) | running target |
| `staging` | Upload/process the ZIP on staging, then run smoke tests and reconciliation | import ZIP + DB URL/DSN |
| `restore` | Rehearse restore into a scratch DB target | backup + scratch DB URL |
| `ready` | Compute the fail-closed cutover gate, readiness score, and human summary | intake/config/staging/restore/live reports |
| `cutover` | Execute the production import, smoke tests, reconciliation, and activation proof | readiness report green |
| `rollback` | Restore the DB and optional config/data backups | explicit rollback confirmation |
| `all` | Default path: `intake -> render-config -> provision -> deploy -> verify-live -> staging -> restore -> ready` | `config.env` |

## Typical Flow

```bash
cp config.env.example config.env
# Edit config.env with your server, DB, SMTP, and handoff paths.
./operate.sh intake
./operate.sh render-config
./operate.sh provision
./operate.sh deploy
./operate.sh verify-live
./operate.sh staging
./operate.sh restore
./operate.sh ready
```

## Production Flow

```bash
./operate.sh cutover
# If abort criteria are met:
ROLLBACK_CONFIRMATION=I_UNDERSTAND_THIS_RESTORES_BACKUPS ./operate.sh rollback
```

## Notes

- `PROVISION_MODE` and `DEPLOY_MODE` control whether the host scripts only plan or actually execute (`plan`, `local`, `ssh`).
- When `TARGET_HOST` is set and `ENABLE_LOCAL_MODE=1`, `operate.sh` materializes an SSH-backed `mmctl` wrapper that uses the server-bundled `mmctl --local` path. That exact flow is what passed against a real remote Docker deployment.
- `verify-live` expects the public front door, not direct `:8065` exposure. The exact-flow deploy path binds Mattermost to `127.0.0.1:8065` and fronts it with Nginx on `80` or `443`.
- Smoke tests prefer `SMOKE_DATABASE_URL`, then `POSTGRES_DSN`, then `STAGING_DATABASE_URL` / `DATABASE_URL`. When the selected DSN points at `localhost` / `127.0.0.1` / `::1`, `operate.sh` routes `psql` over `TARGET_HOST`; if local `psql` is unavailable it also routes external DSNs through `TARGET_HOST`. Otherwise external DSNs such as Supabase are queried locally.
- `SMTP_TEST_EMAIL` enables reset-flow proof during cutover.
