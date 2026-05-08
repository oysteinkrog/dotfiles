# Phase 2 Quote Bank

Load-bearing rules here trace back to specific anchors in the source research
doc, Mattermost documentation, and prior incident notes. Operators in
[OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) cite these tags.

## Deployment

- `[Q-DEP-001]` *Minimum version 10.11+* :: [DOCKER-VS-APT.md](DOCKER-VS-APT.md) :: "Mattermost 10.5 ESR reached end of life in November 2025. You must use 10.11+."
- `[Q-DEP-002]` *APT preferred for production, Docker for staging* :: [DOCKER-VS-APT.md](DOCKER-VS-APT.md) :: native systemd + unattended-upgrades; Docker is fine for dev/staging.
- `[Q-DEP-003]` *Docker is not recommended for HA* :: source doc §"Deployment Method" + Mattermost docs :: "For HA, use Kubernetes."
- `[Q-DEP-004]` *pids_limit is a known footgun* :: [DOCKER-VS-APT.md](DOCKER-VS-APT.md) §"The pids_limit Bug" :: remove `pids_limit` from any Docker Compose; use `mem_limit`.

## Networking & TLS

- `[Q-NET-001]` *Bind Mattermost to 127.0.0.1:8065, front with Nginx* :: source doc §"3. Server Setup & Mattermost Deployment" :: never expose :8065 publicly.
- `[Q-NET-002]` *Cloudflare cannot proxy UDP* :: source doc §"Calls plugin caveat" + [CALLS-PLUGIN.md](CALLS-PLUGIN.md) :: use a DNS-only (grey cloud) record for Calls.
- `[Q-NET-003]` *WebSocket upgrade block is required in Nginx* :: source doc §"Nginx configuration" :: `location ~ /api/v[0-9]+/(users/)?websocket$` sets `Upgrade` + `Connection` upgrade headers.
- `[Q-NET-004]` *Full (Strict) + Origin CA on Cloudflare* :: source doc §"Cloudflare Configuration" :: 15-year origin cert trusted by Cloudflare only.
- `[Q-NET-005]` *WebSocket origin checks tightened in 7.8+* :: [REALTIME-ORIGIN-SETTINGS.md](REALTIME-ORIGIN-SETTINGS.md) :: set `ServiceSettings.SiteURL` correctly and `AllowCorsFrom` for additional origins.

## Database

- `[Q-DB-001]` *Mattermost needs the Supabase SESSION pooler (port 5432), not transaction (6543)* :: [SUPABASE-DATABASE.md](SUPABASE-DATABASE.md) :: prepared statements break in transaction mode.
- `[Q-DB-002]` *PostgreSQL tuning targets* :: source doc §"PostgreSQL tuning" :: `shared_buffers=25% RAM`, `effective_cache_size≈75% RAM`, `work_mem=64MB`, `max_connections=200`.

## Import

- `[Q-IMP-001]` *Mattermost import is idempotent* :: source doc §"Import is Idempotent" :: safe to re-import the same bundle.
- `[Q-IMP-002]` *Pre-import MaxPostSize must be 16383* :: source doc §"Stage 4: Pre-Import Configuration" :: Slack allows 40 000 chars; default 4000 truncates.
- `[Q-IMP-003]` *EnableOpenServer=true during import* :: source doc §"Pre-Import Configuration" :: imported users can't be created otherwise.
- `[Q-IMP-004]` *Staging before production is mandatory* :: Mattermost docs + [STAGING-WORKFLOW.md](STAGING-WORKFLOW.md) :: the import ZIP is expensive to debug post-cutover.

## Activation

- `[Q-ACT-001]` *SMTP must be proven before cutover* :: [SMTP-SETUP.md](SMTP-SETUP.md) :: without working reset email, users can't log in.
- `[Q-ACT-002]` *Slack email → Mattermost user merge* :: source doc §"4. Importing into Mattermost" :: matching emails link existing accounts.
- `[Q-ACT-003]` *Users activate via `/reset_password`* :: source doc §"Stage 7: User Activation" :: not a first-time signup; email-based flow.

## Integrations

- `[Q-INT-001]` *Slack integrations do not migrate* :: source doc §"Rebuilding Integrations" :: webhooks, slash commands, bots, apps — all must be recreated.
- `[Q-INT-002]` *Calls plugin uses UDP 8443 direct* :: [CALLS-PLUGIN.md](CALLS-PLUGIN.md) :: separate DNS-only record, not proxied.

## Operations

- `[Q-OPS-001]` *Rollback owner must be named before cutover* :: [ROLLBACK-AND-ABORT-CRITERIA.md](ROLLBACK-AND-ABORT-CRITERIA.md) :: an unowned rollback is a late-night war-room discussion.
- `[Q-OPS-002]` *Every approved output carries a SHA256 + manifest entry* :: Phase 1 [specs/HANDOFF-CONTRACT.md](CROSS-PHASE-INTAKE-CONTRACT.md) + `scripts/build-phase2-intake-manifest.py` :: matched across the phase boundary.
- `[Q-OPS-003]` *R2 file storage recommended for production* :: source doc §"File Storage" + [R2-STORAGE-COOKBOOK.md](R2-STORAGE-COOKBOOK.md) :: $0.015/GB/mo, no egress, already S3-compatible.

## Using the Bank

Add new rules with a `[Q-*]` tag. Remove stale entries when their anchor moves
or the rule is superseded. Agents treat the quote bank as authoritative over
ad-hoc reasoning; if an anchor disappears, `† Theory-Kill` the rule.
