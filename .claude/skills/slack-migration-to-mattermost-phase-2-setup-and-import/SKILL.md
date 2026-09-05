---
name: slack-migration-to-mattermost-phase-2-setup-and-import
description: >-
  Deploy and import Mattermost migration bundles. Use when validating handoff
  ZIPs, provisioning Mattermost, running mmctl import, configuring
  Nginx/WebSockets, or driving cutover.
---

# Phase 2: Mattermost Server Setup, Import & Cutover

> Deploy a production Mattermost instance, import the Phase 1 export, and cut over from Slack.
> Phase 1 (`slack-migration-to-mattermost-phase-1-extraction`) handles Slack data extraction.

## Do This First

1. Open [START-HERE.md](references/START-HERE.md).
2. Use `./operate.sh intake` before touching Mattermost.
3. Use `./operate.sh render-config` and `./operate.sh verify-live` before staging.
4. Use `./operate.sh staging` before production.
5. Use `./operate.sh ready` before the war-room says go.
6. Use `./operate.sh cutover` only when the readiness gate is green.
7. For remote exact-flow runs, set `ENABLE_LOCAL_MODE=1` so `operate.sh` can drive the server-bundled `mmctl --local` path over SSH instead of depending on a workstation-local `mmctl`.

## Batteries-Included Bootstrap

Phase 2 runs on your Mac / Windows / Linux workstation and talks to an Ubuntu
Mattermost host over SSH. Bring the workstation up to spec first:

```bash
./scripts/doctor.sh                       # required items only
./scripts/doctor.sh --require-remote      # additionally probe SSH to TARGET_HOST
./scripts/bootstrap-tools.sh              # mmctl + jq + psql + Python deps
./scripts/install-mcp-servers.sh          # Mattermost + Playwright MCP wiring
./scripts/doctor.sh --require-mcp         # confirm MCP registration
```

- [TOOL-BOOTSTRAP.md](references/TOOL-BOOTSTRAP.md) — per-platform install matrix.
- [MATTERMOST-MCP-SETUP.md](references/MATTERMOST-MCP-SETUP.md) — drive the live Mattermost API from Claude Code / Codex.
- Remote host provisioning lives inside `./operate.sh provision`; the bootstrap
  script only touches the workstation.

## Operator Library and Quote Bank

Full operator cards for every Phase 2 move (with triggers, failure modes, and
copy-paste prompt modules) live in [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md).
The rules those cards cite are anchored back to the source research doc and
Mattermost vendor docs in [QUOTE-BANK.md](references/QUOTE-BANK.md).

## Stop If Missing

- `handoff.json` is missing or hashless
- staging rehearsal has not passed
- rollback owner is undefined
- config validation is red
- SMTP activation path is required but not proven

## Canonical Default Path

1. Intake and validate the Phase 1 bundle.
2. Stand up staging and import there first.
3. Reconcile staging results against the handoff.
4. Validate production config and rollback inputs.
5. Freeze, import, smoke-test, activate, then close or roll back.

## Migration Threat Model

- Sensitive assets: Phase 1 ZIPs, handoff contract, SMTP credentials, Mattermost admin credentials, Cloudflare/R2 keys, production config, import logs.
- Main trust boundaries: operator workstation, staging host, production host, Cloudflare, storage provider, password-reset email path.
- Main failure classes: wrong-bundle import, config drift, permissive settings left enabled, unsafe staging shortcut, unowned rollback, silent cutover failure.
- Secret-handling rules: [TOKEN-HANDLING.md](references/playbooks/TOKEN-HANDLING.md)

## Operator Router

- Migration lead / cutover lead: [WAR-ROOM-OPS.md](references/WAR-ROOM-OPS.md)
- Infra owner: [START-HERE.md](references/START-HERE.md)
- Security reviewer: [MIGRATION-THREAT-MODEL.md](references/MIGRATION-THREAT-MODEL.md)
- Helpdesk/onboarding owner: [USER-COMMS-KIT.md](references/comms/USER-COMMS-KIT.md)
- Rollback owner: [ROLLBACK-AND-ABORT-CRITERIA.md](references/ROLLBACK-AND-ABORT-CRITERIA.md)

## Done Means

Phase 2 is only done when intake validation, config validation, staging, cutover readiness, and post-import verification all agree. See [DONE-DEFINITION.md](references/DONE-DEFINITION.md).

## Script Contracts

| Script | Input | Output | Exit Behavior | Run When |
|--------|-------|--------|---------------|----------|
| `./operate.sh` | `config.env` + handoff/import/render inputs | staged Phase 2 outputs under `workdir/` | fails on missing prerequisites or failed stage | default end-to-end path |
| `scripts/validate-phase2-intake.py` | `handoff.json` + optional intake manifest | intake report | fails on hash/layout/contract mismatch | before any import |
| `scripts/validate-mattermost-config.py` | `config.json` + expected values | config report | fails on import-critical config problems | before staging and production |
| `scripts/materialize-mattermost-config.py` | site URL + DB DSN + SMTP/CORS settings | rendered `config.json` | fails on missing inputs | before deploy |
| `scripts/provision-mattermost-host.sh` | mode + target host | provision plan/report | fails on invalid mode or execution failure | host prep |
| `scripts/deploy-mattermost-stack.sh` | mode + rendered config/nginx | deploy plan/report | fails on missing inputs or execution failure | stack deployment |
| `scripts/verify-mattermost-live.py` | Mattermost URL + optional SMTP host/port | live verification JSON/MD | fails on failed HTTP/WS/SMTP probes | after deploy; retries to absorb cold-start latency |
| `scripts/run-staging-rehearsal.sh` | staging URL + import ZIP + credentials | staging summary + watch log + smoke/reconcile artifacts | fails on unsafe target or failed rehearsal | before production; exact remote flow can use the server-bundled `mmctl --local` wrapper |
| `scripts/run-import-smoke-tests.py` | handoff JSON + Mattermost DB URL/DSN | observed counts + smoke report | fails on DB/service verification failure | after staging or production import; supports SSH-backed DB queries when the DB port is intentionally closed |
| `scripts/verify-user-activation.sh` | Mattermost URL + test email | activation proof JSON/MD | fails on reset-flow trigger failure | before or after cutover |
| `scripts/validate-cutover-readiness.py` | handoff/config/live/staging/smoke/reconcile/restore reports | readiness gate JSON | fails closed when cutover must stop | immediately before cutover |
| `scripts/generate-readiness-score.py` | validation reports | weighted score JSON/MD | nonzero on missing inputs | war-room decision support |

## First-Hop References

- [START-HERE.md](references/START-HERE.md)
- [DONE-DEFINITION.md](references/DONE-DEFINITION.md)
- [CROSS-PHASE-INTAKE-CONTRACT.md](references/CROSS-PHASE-INTAKE-CONTRACT.md)
- [ROLLBACK-AND-ABORT-CRITERIA.md](references/ROLLBACK-AND-ABORT-CRITERIA.md)
- [SUBAGENT-CONTRACTS.md](references/SUBAGENT-CONTRACTS.md)
- [OPERATE-SH-REFERENCE.md](references/OPERATE-SH-REFERENCE.md)
- [CONFIG-REFERENCE.md](references/CONFIG-REFERENCE.md)

## Operating Environment

**You run Phase 2 from your local Mac/Windows machine via SSH**, connecting to an Ubuntu Linux server (VPS or bare metal) where Mattermost will live.

```
Your Mac/Windows                         Ubuntu Server (target)
┌─────────────────────┐     SSH          ┌──────────────────────────┐
│ Claude Code / Codex │ ───────────────▶ │ Mattermost + PostgreSQL  │
│ Phase 1 output ZIP  │  SCP import ZIP  │ Nginx reverse proxy      │
│ mmctl (local)       │ ◀─────────────── │ Cloudflare Origin TLS    │
│ Browser for DNS/CF  │    verify        │ UFW + fail2ban           │
└─────────────────────┘                  └──────────────────────────┘
                                                    │
                                         Cloudflare Edge (CDN/WAF/DDoS)
                                                    │
                                              Users connect
```

## The Pipeline

```
Stage 1: Provision    Order server, initial OS setup, hardening
Stage 2: Deploy       Install PostgreSQL + Mattermost (apt or Docker)
Stage 3: Network      Cloudflare DNS + Origin TLS + Nginx reverse proxy
Stage 4: Configure    Mattermost settings, SMTP, file storage
Stage 5: Import       Transfer ZIP, mmctl upload + process
Stage 6: Verify       Count reconciliation, sample checks
Stage 7: Activate     User password resets, app distribution
Stage 8: Cutover      Freeze Slack, final delta import, go live
```

## Pre-Flight Checklist

- [ ] Phase 1 complete: `mattermost-bulk-import.zip` validated and ready
- [ ] Server ordered and provisioned (Hetzner/OVH/other)
- [ ] Domain name ready (e.g., `chat.yourdomain.com`)
- [ ] Cloudflare account with domain added
- [ ] SSH key generated for server access
- [ ] SMTP credentials ready (for email notifications + password resets)
- [ ] Decided: apt install vs Docker Compose for Mattermost
- [ ] Decide whether users will access Mattermost from more than one trusted origin/domain
- [ ] Decide whether to keep file storage local initially or move directly to S3-compatible storage

## Stage 1: Server Provisioning

### Recommended Hardware (1000 users)

| Provider | Model | Specs | Monthly |
|----------|-------|-------|---------|
| Hetzner AX42-U (value) | Ryzen 7 PRO 8700GE | 8c/16t, 64GB DDR5, 2x512GB NVMe | ~$50 |
| Hetzner AX52 (recommended) | Ryzen 7 7700 | 8c/16t, 64GB DDR5, 2x1TB NVMe | ~$70 |
| OVH Advance-2 (production) | EPYC 4345P | 8c/16t, 64GB DDR5 ECC, 2x960GB NVMe | ~$90 |

Target: **8 cores / 64 GB RAM / mirrored NVMe**. OS: **Ubuntu 24.04 LTS** (or 25.10).

### Server Hardening
```bash
# 1. Create non-root user
adduser deploy && usermod -aG sudo deploy

# 2. SSH hardening
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# 3. Firewall
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP (redirect to HTTPS)
ufw allow 443/tcp   # HTTPS
ufw allow 8443/udp  # Mattermost Calls plugin
ufw enable

# 4. Brute-force protection
apt install -y fail2ban
systemctl enable fail2ban

# 5. Automatic security updates
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
```

## Stage 2: Deploy Mattermost

### Option A: APT Install (Recommended for Production)
```bash
# Add Mattermost repo
curl -o- https://deb.packages.mattermost.com/repo-setup.sh | sudo bash -s mattermost
apt install -y mattermost

# Mattermost installs to /opt/mattermost, runs as mattermost user
systemctl enable mattermost
```

### Option B: Docker Compose
```bash
git clone https://github.com/mattermost/docker
cd docker
cp env.example .env
# Edit .env: set domain, Postgres creds, edition
docker compose up -d
```

### Option C: Supabase as Managed Database

If you prefer managed PostgreSQL with zero DB ops, use Supabase instead of self-hosting PostgreSQL. Supabase handles backups, upgrades, PITR, connection pooling, and gives you a dashboard.

```bash
# 1. Create project at supabase.com (Pro plan recommended: $25/month)
# 2. Get connection string from Dashboard → Connect → Transaction Pooler
#    Format: postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:6543/postgres

# 3. Configure Mattermost to use Supabase
# In config.json SqlSettings.DataSource, use the SESSION POOLER (port 5432):
# postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require
# (Mattermost uses prepared statements, which require session mode, NOT transaction mode)
```

**Critical:** Mattermost uses prepared statements internally. You MUST use the **session pooler (port 5432)**, not the transaction pooler (port 6543). Transaction mode breaks prepared statements.

Full setup guide with RLS hardening: [SUPABASE-DATABASE.md](references/SUPABASE-DATABASE.md)

### PostgreSQL Setup (if APT install, self-hosted)
```bash
apt install -y postgresql
sudo -u postgres psql -c "CREATE USER mmuser WITH PASSWORD 'your-db-password';"
sudo -u postgres psql -c "CREATE DATABASE mattermost OWNER mmuser;"
```

### PostgreSQL Tuning (for 1000 users)
```
shared_buffers = 16GB          # 25% of RAM
effective_cache_size = 48GB
work_mem = 64MB
max_connections = 200
wal_buffers = 64MB
```

### Key Mattermost Config
Edit `/opt/mattermost/config/config.json`:
```json
{
  "ServiceSettings": {
    "SiteURL": "https://chat.yourdomain.com",
    "ListenAddress": "127.0.0.1:8065"
  },
  "SqlSettings": {
    "DataSource": "postgres://mmuser:password@localhost:5432/mattermost?sslmode=disable"
  },
  "FileSettings": {
    "DriverName": "local",
    "MaxFileSize": 52428800
  },
  "EmailSettings": {
    "EnableSignUpWithEmail": true,
    "SendEmailNotifications": true,
    "SMTPServer": "smtp.example.com",
    "SMTPPort": "587",
    "SMTPUsername": "noreply@yourdomain.com",
    "SMTPPassword": "smtp-password"
  }
}
```

**Bind to 127.0.0.1:8065** -- never expose Mattermost directly to the internet. Nginx handles public traffic.

## Stage 3: Cloudflare + Nginx

### Cloudflare Configuration
1. **DNS:** A record `chat.yourdomain.com` → server IP, orange-clouded (proxied)
2. **SSL/TLS:** Full (Strict) mode
3. **Origin Certificate:** Create 15-year Cloudflare Origin CA cert, install on Nginx
4. **WebSockets:** Enabled (default on all plans)
5. **Authenticated Origin Pulls:** Enable for origin hardening
6. **Page Rules:** `chat.yourdomain.com/api/*` → Cache Level: Bypass
7. **WAF:** Enable managed rules
8. **Calls plugin:** Separate DNS-only (grey cloud) record for `calls.yourdomain.com` if using voice/video (UDP can't be proxied)

**Real-time caution:** Mattermost v7.8+ validates WebSocket origins more strictly. If users will access the site from more than one trusted domain, configure `ServiceSettings.SiteURL` correctly and set `AllowCorsFrom` for additional trusted origins. See [REALTIME-ORIGIN-SETTINGS.md](references/REALTIME-ORIGIN-SETTINGS.md).

### Nginx Configuration
```nginx
upstream mattermost {
    server 127.0.0.1:8065;
    keepalive 32;
}

server {
    listen 443 ssl http2;
    server_name chat.yourdomain.com;

    ssl_certificate     /etc/nginx/ssl/origin.pem;
    ssl_certificate_key /etc/nginx/ssl/origin-key.pem;

    # WebSocket endpoint (CRITICAL for Mattermost)
    location ~ /api/v[0-9]+/(users/)?websocket$ {
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 600s;
        proxy_pass http://mattermost;
    }

    location / {
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Frame-Options SAMEORIGIN;
        client_max_body_size 50M;
        proxy_read_timeout 600s;
        proxy_pass http://mattermost;
    }
}

server {
    listen 80;
    server_name chat.yourdomain.com;
    return 301 https://$server_name$request_uri;
}
```

## Stage 4: Pre-Import Configuration

Before importing, adjust Mattermost settings:

```bash
# Via System Console (https://chat.yourdomain.com/admin_console) or config.json:
```

| Setting | Value | Why |
|---------|-------|-----|
| `MaxPostSize` | 16383 | Slack allows 40k chars; default 4000 truncates |
| `MaxFileSize` | 52428800 (50MB) | Match your file upload needs |
| `EnableOpenServer` | true | Temporarily, so imported users can be created |
| `EnableSignUpWithEmail` | true | Required for password reset activation flow |
| `MaxIdleConns` | 20 | Database connection pool |
| `MaxOpenConns` | 100 | For 1000-user imports |

## Stage 5: Import

### Transfer the ZIP
```bash
# From your local machine:
scp mattermost-bulk-import.zip deploy@server:~/

# Or for large files:
rsync --progress mattermost-bulk-import.zip deploy@server:~/
```

### Run Import
```bash
# On the server (or via mmctl from local if configured):
mmctl auth login https://chat.yourdomain.com \
  --name migration --username admin --password your-password

# Create team if needed
mmctl team create --name myteam --display-name "My Team"
mmctl team modify myteam --public  # Required for bulk import

# Upload
mmctl import upload ~/mattermost-bulk-import.zip

# List and process
mmctl import list available
mmctl import process <FILENAME>  # Use filename from list output

# Monitor
mmctl import job list --json | jq '.[0].status'
# Poll until "success" or "error"
```

### Import is Idempotent
Re-importing the same posts won't create duplicates. Safe to do baseline + delta imports.

For repeatable operator behavior, use `scripts/monitor-import.sh` to poll the active import job until `success` or `error`.

## Stage 6: Post-Import Verification

```bash
# Channel count
mmctl channel list myteam | wc -l

# User count
mmctl user list --all | wc -l

# Compare against Phase 1 JSONL counts
# (from your local machine where you ran the transform)
```

See Phase 1's [VERIFICATION-COOKBOOK.md] for detailed reconciliation scripts.

## Stage 7: User Activation

Users activate their accounts via password reset using their Slack email:

1. Users go to `https://chat.yourdomain.com/reset_password`
2. Enter their **Slack email address**
3. Mattermost sends a password reset email (SMTP must be configured)
4. They set a new password and log in
5. All their channels, DMs, and history are waiting

**Admin bulk option:**
```bash
mmctl user change-password USERNAME --password TEMPORARY_PASSWORD
```

**Announce to users:**
```
Subject: Mattermost is live -- activate your account

1. Go to https://chat.yourdomain.com/reset_password
2. Enter your work email (same as Slack)
3. Check email for reset link
4. Set a new password
5. Download apps: https://mattermost.com/apps/
6. Server URL: https://chat.yourdomain.com
```

## Stage 8: Cutover

See Phase 1's [CUTOVER-STRATEGY.md] for the full baseline+deltas+final pattern.

### Cutover Day Checklist
- [ ] Freeze Slack (read-only or announce)
- [ ] Final export from Slack (Phase 1 skill)
- [ ] Enrich + transform final delta
- [ ] SCP final import ZIP to server
- [ ] `mmctl import upload + process`
- [ ] Verify latest messages appear
- [ ] Import any new emoji
- [ ] Announce Mattermost is live
- [ ] Monitor for user issues
- [ ] T+1 week: revoke Slack tokens, delete migration app

## Anti-Patterns

| Don't | Do Instead |
|-------|------------|
| Expose Mattermost directly on :8065 | Bind to 127.0.0.1, use Nginx proxy |
| Use self-signed certs with Cloudflare | Use Cloudflare Origin CA (free, 15-year) |
| Run app + DB on same box without considering failure | Separate PostgreSQL if budget allows |
| Skip SMTP setup | Configure day 1; password resets need email |
| Import without increasing MaxPostSize | Set to 16383 before first import |
| Use Docker for HA | Kubernetes is the HA path per Mattermost docs |
| Deploy old Mattermost versions | 10.11+ required; 10.5 ESR ended Nov 2025 |
| Proxy Calls plugin through Cloudflare | UDP can't be proxied; use DNS-only record |
| Skip `EnableOpenServer` during import | Imported users can't be created without it |

## Backups

```bash
# Daily PostgreSQL backup
pg_dump -U mmuser mattermost | gzip > /backups/mattermost_$(date +%Y%m%d).sql.gz

# Config backup
cp -r /opt/mattermost/config /backups/config_$(date +%Y%m%d)

# If using local file storage:
rsync -a /opt/mattermost/data/ /backups/data/

# Ship to off-site (Hetzner Storage Box, Cloudflare R2, etc.)
```

For S3/R2 file storage, files are already off-server and don't need separate backup.

## Cloudflare R2 for File Storage (Optional)

Offload file attachments to S3-compatible Cloudflare R2:

```json
{
  "FileSettings": {
    "DriverName": "amazons3",
    "AmazonS3AccessKeyId": "R2_ACCESS_KEY",
    "AmazonS3SecretAccessKey": "R2_SECRET_KEY",
    "AmazonS3Bucket": "mattermost-files",
    "AmazonS3Endpoint": "ACCOUNT_ID.r2.cloudflarestorage.com",
    "AmazonS3Region": "",
    "AmazonS3SSL": true
  }
}
```

R2 pricing: $0.015/GB/month storage, no egress fees.

## Monitoring

Enable Mattermost metrics on port 8067:
```json
{
  "MetricsSettings": {
    "Enable": true,
    "ListenAddress": ":8067"
  }
}
```

Scrape with Prometheus, visualize with Grafana. Mattermost recommends running these off-box.

## THE EXACT PROMPT

When asked to deploy Mattermost, import Slack data, or set up a self-hosted chat server:

```
I need to deploy a Mattermost server and import data extracted from Slack.

Context:
- Phase 1 complete: I have mattermost-bulk-import.zip ready
- Target server: [Hetzner/OVH/other, specs]
- User count: [N registered users, estimated concurrent]
- Domain: [chat.yourdomain.com]
- Cloudflare: [already have account? domain added?]
- SMTP: [provider? credentials ready?]
- Budget priority: [cost vs reliability vs HA]

Run the Phase 2 setup-and-import skill. Follow the pipeline from
provisioning through cutover.
```

## Architecture Decision Trees

### Deployment Method
```
How does your team operate?
│
├─ Container-native (Docker/K8s experience)
│   ├─ Need HA? → Kubernetes (Mattermost Enterprise)
│   └─ Single node fine? → Docker Compose
│       ⚠️ Docker is NOT ideal for HA (Mattermost docs)
│       ⚠️ Previous pids_limit bugs caused PG failures; use mem_limit
│
└─ Traditional Linux ops
    └─ APT install (RECOMMENDED)
        + Automatic security updates via apt
        + Simpler debugging (systemctl, journalctl)
        + Official Mattermost PPA
        + Ubuntu 20.04/22.04/24.04 supported
```

### Database Placement
```
Budget and reliability tolerance?
│
├─ Production-critical, budget available
│   └─ SEPARATE PostgreSQL server or managed PG
│       Mattermost explicitly says NOT recommended
│       to run app+DB on same system for production
│
├─ Managed database, minimal ops
│   └─ SUPABASE (managed PostgreSQL + extras)
│       + Zero DB ops (backups, upgrades, PITR handled)
│       + Built-in connection pooling (Supavisor)
│       + Dashboard, SQL editor, real-time subscriptions
│       + RLS for locking down any custom tables you add
│       - Mattermost needs direct PG connection, not PostgREST
│       - Must use pooler connection string (port 6543)
│       - Cost: $25/month Pro, $599/month Team (vs ~$0 self-hosted)
│       See [SUPABASE-DATABASE.md](references/SUPABASE-DATABASE.md)
│
├─ Budget-constrained, acceptable risk
│   └─ LOCAL PostgreSQL on same box
│       This is the "single biggest compromise"
│       Mitigate: aggressive backups + PITR
│
└─ Zero-downtime required
    └─ Mattermost Enterprise HA
        Writer/reader PostgreSQL cluster
        Multiple Mattermost app nodes
```

### File Storage
```
How much file volume do you expect?
│
├─ Heavy file sharing (5-25 MB/user/month)
│   └─ Cloudflare R2 (S3-compatible) from day 1
│       $0.015/GB/month, no egress fees
│       Reduces local disk pressure
│       Mattermost recommends S3 for production
│
├─ Light file sharing, budget-first
│   └─ Local storage initially → R2 when needed
│       FileSettings.DriverName: "local"
│       Data lives under /opt/mattermost/data/
│
└─ Air-gapped / data sovereignty
    └─ Local storage + MinIO on same network
```

### Mattermost Licensing
```
How many users and what features?
│
├─ <50 users, basic chat
│   └─ Team Edition (free, open source)
│
├─ 50-250 users, need SSO/SAML
│   └─ Enterprise E10
│       SSO, AD/LDAP, advanced permissions
│
├─ 250-1000+ users, compliance needs
│   └─ Enterprise E20
│       HA, compliance, custom retention
│       $10/user/month (~$10k/month for 1000)
│       Still 20% of Slack Business+
│
└─ >2000 concurrent, strict uptime
    └─ Enterprise HA architecture
        Multiple app nodes + LB
        Writer/reader PostgreSQL
        Dedicated RTCD for calls
```

## Operators (Cognitive Moves)

| Op | Name | Trigger | Failure Mode |
|----|------|---------|-------------|
| `PROV` | Server Provisioning | Need bare metal/VPS | Under-spec causes import OOM; over-spec wastes money |
| `HARDEN` | Security Hardening | Fresh server, before any services | Skip = open root SSH, no firewall, brute-force vulnerable |
| `DEPLOY` | Service Deployment | Server hardened, ready for MM | Wrong method (Docker when should be APT) causes upgrade pain |
| `NET` | Network Stack | Services running, need public access | Misconfigured Nginx = WebSocket failures, no real-time updates |
| `TLS` | TLS/Origin Hardening | Cloudflare + Nginx configured | Self-signed certs = browser warnings; no AOP = origin exposed |
| `IMPORT` | Data Import | MM running, ZIP ready | Missing pre-import config = truncated messages, failed users |
| `SMTP` | Email Delivery | Before user activation | No SMTP = no password resets = users can't log in |
| `ACTIVATE` | User Onboarding | Import verified, SMTP working | Bad rollout = confusion, support burden, lost trust |
| `CUTOVER` | Production Cutover | Staging verified, users ready | No freeze = messages lost between export and import |
| `OPS` | Ongoing Operations | System live | No backups = catastrophic data loss; no monitoring = silent failures |

## Validation Gates (Non-Negotiable)

| Gate | Check | Pass Criteria |
|------|-------|---------------|
| G1: Server ready | SSH, firewall, hardening | Non-root only, UFW active, fail2ban running, auto-updates on |
| G2: Services healthy | PG + MM + Nginx running | `systemctl status` green for all three; `curl -s localhost:8065/api/v4/system/ping` returns OK |
| G3: TLS end-to-end | Cloudflare → Nginx → MM | `curl -I https://chat.yourdomain.com` returns 200 with valid cert |
| G4: WebSocket working | Real-time messaging | Browser console shows WS connected; no "upgrade header" errors |
| G5: SMTP verified | Email delivery working | Test email arrives in inbox (not spam) within 60 seconds |
| G6: Import successful | `mmctl import job` shows success | Job status = "success"; user/channel/post counts match Phase 1 |
| G7: Users can activate | Password reset flow works | Test user receives reset email, sets password, logs in, sees history |
| G8: Backup verified | Restore test passes | pg_dump restores to temp DB without errors; config files intact |

## Risk Tiering

| Risk Level | Context | Freedom |
|------------|---------|---------|
| **Critical** (exact commands) | SSH hardening, firewall rules, TLS config, DB credentials | Follow commands verbatim |
| **High** (template with constraints) | Nginx config, PostgreSQL tuning, import commands | Adapt to your server specs |
| **Medium** (guidelines) | Mattermost config.json, plugin setup, user communication | Customize for your org |
| **Low** (full autonomy) | Monitoring dashboards, channel organization, app distribution | Creative solutions welcome |

## Full Architecture

```
                    Internet
                       │
              ┌────────┴────────┐
              │   Cloudflare    │
              │   Edge Network  │
              │                 │
              │  DDoS protection│
              │  WAF rules      │
              │  TLS termination│
              │  CDN (static)   │
              │  WebSocket proxy│
              └────────┬────────┘
                       │ HTTPS (Origin CA + AOP)
              ┌────────┴────────┐
              │   Ubuntu Server │
              │   (Hetzner/OVH) │
              │                 │
              │  ┌───────────┐  │         ┌──────────────┐
              │  │   Nginx   │  │         │ Cloudflare   │
              │  │  :443/:80 │  │         │ Tunnel       │
              │  └─────┬─────┘  │         │ (SSH access) │
              │        │        │         └──────┬───────┘
              │  ┌─────┴─────┐  │                │
              │  │Mattermost │  │         ┌──────┴───────┐
              │  │127.0.0.1  │  │         │   Admin      │
              │  │  :8065    │  │         │   (you)      │
              │  │  :8067    │◄─┼─metrics─│   Mac/Win    │
              │  └─────┬─────┘  │         └──────────────┘
              │        │        │
              │  ┌─────┴─────┐  │    ┌──────────────┐
              │  │PostgreSQL │  │    │ Cloudflare   │
              │  │  :5432    │  │    │ R2 (S3)      │
              │  └───────────┘  │    │ File storage │
              │                 │    └──────────────┘
              └─────────────────┘
                                         ┌──────────────┐
           UDP :8443 (direct) ──────────▶│ Calls plugin │
           (DNS-only record              │ RTCD (opt)   │
            for calls.domain)            └──────────────┘
```

## Post-Cutover Operations

After successful cutover, the system needs ongoing care:

### Mattermost Updates
```bash
# APT install: automatic via unattended-upgrades
# Check current version:
mmctl system version

# Manual update:
apt update && apt upgrade mattermost
# ⚠️ 10.5 ESR ended Nov 2025; must be on 10.11+
```

### Plugin Management
Key plugins to install post-migration for Slack feature parity:
- **Calls** -- voice/video (requires UDP :8443, see CALLS-PLUGIN.md)
- **Playbooks** -- incident management (replaces Slack Workflows partially)
- **Boards** -- kanban/project management (replaces some Slack integrations)
- **GitHub/GitLab** -- PR notifications, slash commands

### Rebuilding Integrations
Slack integrations (bots, webhooks, apps) do NOT migrate. Rebuild plan:
- **Incoming webhooks** -- create in Mattermost, update sender URLs
- **Outgoing webhooks** -- create in Mattermost, same trigger words
- **Slash commands** -- recreate with same trigger words
- **Bot accounts** -- use Mattermost bot framework or personal access tokens
- **Custom apps** -- port to Mattermost plugin API or Apps Framework
See [INTEGRATION-REBUILDING.md](references/INTEGRATION-REBUILDING.md).

## Staging Before Production

**Always import to a staging instance first.** Mattermost explicitly recommends staging.

```bash
# Quick staging instance (Docker, throwaway)
docker run -d --name mm-staging -p 8065:8065 mattermost/mattermost-preview

# Import to staging
mmctl auth login http://localhost:8065 --name staging --username admin --password admin
mmctl import upload mattermost-bulk-import.zip
mmctl import list available
mmctl import process <FILENAME>

# Verify, iterate, then do the real import to production
```

S3-compatible file storage typically imports faster than local or NFS.

## Reference Index

### Server & Infrastructure
| Topic | File |
|-------|------|
| Server provisioning runbook | [SERVER-PROVISIONING.md](references/SERVER-PROVISIONING.md) |
| Cloudflare configuration cookbook | [CLOUDFLARE-COOKBOOK.md](references/CLOUDFLARE-COOKBOOK.md) |
| Nginx configuration reference | [NGINX-REFERENCE.md](references/NGINX-REFERENCE.md) |
| PostgreSQL tuning & backups | [POSTGRESQL-COOKBOOK.md](references/POSTGRESQL-COOKBOOK.md) |
| Supabase as managed database | [SUPABASE-DATABASE.md](references/SUPABASE-DATABASE.md) |
| Cloudflare R2 file storage setup | [R2-STORAGE-COOKBOOK.md](references/R2-STORAGE-COOKBOOK.md) |
| Cloudflare Tunnel for SSH | [CLOUDFLARE-TUNNEL-SSH.md](references/CLOUDFLARE-TUNNEL-SSH.md) |

### Architecture & Decisions
| Topic | File |
|-------|------|
| Start-here routing | [START-HERE.md](references/START-HERE.md) |
| Phase 2 done definition | [DONE-DEFINITION.md](references/DONE-DEFINITION.md) |
| Subagent output contracts | [SUBAGENT-CONTRACTS.md](references/SUBAGENT-CONTRACTS.md) |
| Cross-phase intake contract | [CROSS-PHASE-INTAKE-CONTRACT.md](references/CROSS-PHASE-INTAKE-CONTRACT.md) |
| Cross-phase lifecycle state machine | [CROSS-PHASE-STATE-MACHINE.md](references/CROSS-PHASE-STATE-MACHINE.md) |
| Migration threat model | [MIGRATION-THREAT-MODEL.md](references/MIGRATION-THREAT-MODEL.md) |
| Rollback and abort criteria | [ROLLBACK-AND-ABORT-CRITERIA.md](references/ROLLBACK-AND-ABORT-CRITERIA.md) |
| War-room operating model | [WAR-ROOM-OPS.md](references/WAR-ROOM-OPS.md) |
| Architecture trade-off analysis | [ARCHITECTURE-DECISIONS.md](references/ARCHITECTURE-DECISIONS.md) |
| Docker vs APT deployment | [DOCKER-VS-APT.md](references/DOCKER-VS-APT.md) |
| Licensing guide (Team vs Enterprise) | [LICENSING-GUIDE.md](references/LICENSING-GUIDE.md) |
| HA scaling beyond single node | [HA-SCALING.md](references/HA-SCALING.md) |

### Import & Operations
| Topic | File |
|-------|------|
| mmctl command reference | [MMCTL-REFERENCE.md](references/MMCTL-REFERENCE.md) |
| Mattermost configuration deep dive | [MATTERMOST-CONFIG.md](references/MATTERMOST-CONFIG.md) |
| SMTP & email setup | [SMTP-SETUP.md](references/SMTP-SETUP.md) |
| User activation & onboarding | [USER-ACTIVATION.md](references/USER-ACTIVATION.md) |
| Staging workflow & test imports | [STAGING-WORKFLOW.md](references/STAGING-WORKFLOW.md) |
| Import diagnostics (deep debug) | [IMPORT-DIAGNOSTICS.md](references/IMPORT-DIAGNOSTICS.md) |
| Real-time origin/CORS settings | [REALTIME-ORIGIN-SETTINGS.md](references/REALTIME-ORIGIN-SETTINGS.md) |

### Playbooks & Comms
| Topic | File |
|-------|------|
| Staging-first gate | [STAGING-FIRST-GATE.md](references/playbooks/STAGING-FIRST-GATE.md) |
| Cutover go/no-go rules | [CUTOVER-GO-NO-GO.md](references/playbooks/CUTOVER-GO-NO-GO.md) |
| Activation hardening | [ACTIVATION-HARDENING.md](references/playbooks/ACTIVATION-HARDENING.md) |
| Intake quarantine | [INTAKE-QUARANTINE.md](references/playbooks/INTAKE-QUARANTINE.md) |
| Secret handling rules | [TOKEN-HANDLING.md](references/playbooks/TOKEN-HANDLING.md) |
| User communications kit | [USER-COMMS-KIT.md](references/comms/USER-COMMS-KIT.md) |
| Escalation ladder | [ESCALATION-LADDER.md](references/comms/ESCALATION-LADDER.md) |

### Scenario Packs
| Topic | File |
|-------|------|
| Small team, staging-first cutover | [SMALL-TEAM-STAGING-FIRST.md](references/scenario-packs/SMALL-TEAM-STAGING-FIRST.md) |
| Enterprise cutover | [ENTERPRISE-CUTOVER.md](references/scenario-packs/ENTERPRISE-CUTOVER.md) |

### Plugins & Integrations
| Topic | File |
|-------|------|
| Calls plugin (voice/video/UDP) | [CALLS-PLUGIN.md](references/CALLS-PLUGIN.md) |
| Rebuilding Slack integrations | [INTEGRATION-REBUILDING.md](references/INTEGRATION-REBUILDING.md) |
| Mattermost API cookbook | [MATTERMOST-API-COOKBOOK.md](references/MATTERMOST-API-COOKBOOK.md) |

### Monitoring & Maintenance
| Topic | File |
|-------|------|
| Monitoring (Prometheus/Grafana) | [MONITORING.md](references/MONITORING.md) |
| Backup & disaster recovery | [BACKUPS.md](references/BACKUPS.md) |
| Post-cutover operations | [POST-CUTOVER-OPS.md](references/POST-CUTOVER-OPS.md) |
| Troubleshooting (all categories) | [TROUBLESHOOTING.md](references/TROUBLESHOOTING.md) |

## Tools

| Tool | Purpose |
|------|---------|
| `./operate.sh` | Orchestrate intake -> render-config -> provision -> deploy -> verify-live -> staging -> restore -> ready -> cutover/rollback |
| `scripts/render-nginx-config.sh` | Generate a Mattermost-focused Nginx reverse-proxy config from parameters |
| `scripts/materialize-mattermost-config.py` | Render `config.json` from the Phase 2 environment contract |
| `scripts/provision-mattermost-host.sh` | Build or execute the host provisioning/hardening plan |
| `scripts/deploy-mattermost-stack.sh` | Build or execute the Mattermost/Nginx deployment plan |
| `scripts/monitor-import.sh` | Poll `mmctl import job show --json`, detect stalls, and optionally emit watch logs/snapshots |
| `scripts/verify-mattermost-live.py` | Probe HTTP, WebSocket, and SMTP reachability on the live stack |
| `scripts/validate-mattermost-config.py` | Check `config.json` for import-critical deployment, SMTP, and real-time settings |
| `scripts/build-phase2-intake-manifest.py` | Hash the handoff and server-side validation inputs into an intake manifest |
| `scripts/validate-phase2-intake.py` | Verify that the Phase 1 handoff bundle is authoritative, complete, and hash-consistent |
| `scripts/run-staging-rehearsal.sh` | Run a staging-only import rehearsal and emit machine-readable evidence plus post-import smoke/reconcile artifacts |
| `scripts/run-import-smoke-tests.py` | Query Mattermost/PostgreSQL and emit observed counts plus smoke evidence |
| `scripts/reconcile-handoff-vs-import.py` | Compare Phase 1 expected counts against staging or production observations |
| `scripts/verify-user-activation.sh` | Trigger and record reset-flow proof for user activation |
| `scripts/restore-drill.sh` | Rehearse DB restore into a scratch target before cutover |
| `scripts/validate-cutover-readiness.py` | Fail closed unless the cutover gate is fully green |
| `scripts/generate-readiness-score.py` | Turn validation artifacts into a weighted readiness score |
| `scripts/generate-phase2-readiness.py` | Build a human-readable readiness summary for the war room |
| `scripts/execute-production-cutover.sh` | Execute the production import, smoke tests, reconciliation, and activation proof |
| `scripts/rollback-cutover.sh` | Execute rollback from backups after explicit confirmation |

*Run scripts directly. They are designed to turn the runbook into repeatable operator actions.*

### Script Inventory

See [scripts/README.md](scripts/README.md) for `input -> output -> exit-code -> when-to-run`.

## Subagents

| Subagent | Purpose |
|----------|---------|
| `subagents/infra-readiness-auditor.md` | Review server, network, TLS, and config posture before import |
| `subagents/import-rollout-auditor.md` | Audit import, activation, and cutover readiness with findings-first output |
| `subagents/handoff-intake-auditor.md` | Audit the Phase 1 handoff bundle from the Phase 2 side before import |
| `subagents/staging-verifier.md` | Decide whether staging proved enough to continue toward cutover |
| `subagents/cutover-war-room-coordinator.md` | Enforce state/owner/gate discipline during rehearsal and cutover |
| `subagents/helpdesk-onboarding-auditor.md` | Audit activation messaging, FAQ quality, and support readiness |
| `subagents/cutover-quarantine-auditor.md` | Verify only hash-validated, intake-approved bundles reach import |

### Subagent Contracts

See [SUBAGENT-CONTRACTS.md](references/SUBAGENT-CONTRACTS.md) for the required `Verdict: ready|blocked|needs-review` schema.

## Assets

| Asset | Purpose |
|-------|---------|
| `assets/templates/operator-cockpit.html` | Static cockpit shell for readiness, gate, and cutover dashboards |
| `assets/templates/war-room-status.md` | Status template for the migration lead during rehearsal/cutover |
| `assets/templates/helpdesk-faq.md` | Seed FAQ for support during activation week |
| `assets/scenario-packs/` | YAML presets for staging rehearsal and production cutover flows |

### Phase 1 Handoff
This skill receives `mattermost-bulk-import.zip` plus machine-readable `handoff.json` from `slack-migration-to-mattermost-phase-1-extraction`. Validate the bundle first, rehearse on staging, then decide whether to proceed, abort, or roll back.
