# Phase 2 Operator Library

Operators are the atomic cognitive moves that drive Phase 2. The summary in
`SKILL.md` is the index; this file has the full cards with triggers, failure
modes, and copy-paste prompt modules. Operators compose:

```
🧾 INTAKE → 🧱 PROV → 🚀 DEPLOY → 🛰 NET/TLS → 🔎 LIVE →
🧪 STAGE → 📧 SMTP → 🧭 READY → ⚠ CUTOVER → 👥 ACTIVATE → ♻ OPS
                                            ↘ ⛑ ROLLBACK
```

---

### 🧾 INTAKE — Bundle Intake & Validation

**Definition**: Verify the Phase 1 handoff bundle is authoritative, complete,
and hash-consistent before touching Mattermost.

**Triggers**: first Phase 2 run, every delta import, any time the handoff
hash changes, any time Phase 1 re-cuts its package.

**Failure Modes**:
- Importing a stale delta ZIP because a hash was never re-checked.
- Re-using last week's `handoff.json` against this week's import ZIP.
- Silent missing sidecar channels — intake passes but content never appears.

**Prompt Module**:
```text
[OPERATOR: 🧾 INTAKE]
1) Set HANDOFF_JSON + IMPORT_ZIP in config.env; confirm both files exist.
2) Run `./operate.sh intake`.
3) Read the JSON report:
   - status == "ready" ? continue.
   - status == "blocked" ? stop and list the specific mismatch.
4) Confirm sidecar channels in handoff.json match Phase 1's expectations.
5) Emit: "intake green for <workspace> with hash <sha256>".
```

**Anchors**: [CROSS-PHASE-INTAKE-CONTRACT.md](CROSS-PHASE-INTAKE-CONTRACT.md),
`scripts/validate-phase2-intake.py`, [playbooks/INTAKE-QUARANTINE.md](playbooks/INTAKE-QUARANTINE.md).

---

### 🧱 PROV — Host Provisioning

**Definition**: Stand up the Ubuntu host (firewall, hardening, optional local
Postgres) either via a plan script, local execution, or SSH.

**Triggers**: fresh server, reinstall, or when `doctor.sh --require-remote`
fails.

**Failure Modes**:
- Running `DEPLOY_MODE=local` by accident on your workstation.
- Missing UFW rules -> `:8065` directly exposed to the internet.
- Opening ports that Cloudflare can't proxy without documenting the exception.

**Prompt Module**:
```text
[OPERATOR: 🧱 PROV]
1) Decide: local Postgres, external (Supabase), or external (managed cluster).
2) Set PROVISION_MODE, TARGET_HOST, POSTGRES_DSN in config.env.
3) Run `./operate.sh provision`; inspect the generated plan script.
4) Confirm: UFW rules include 22/80/443/(8443 udp), fail2ban + unattended-upgrades enabled.
5) Emit: "host ready at <target_host>, db=<local|external>".
```

**Anchors**: [SERVER-PROVISIONING.md](SERVER-PROVISIONING.md), `scripts/provision-mattermost-host.sh`.

---

### 🚀 DEPLOY — Mattermost + Nginx Deployment

**Definition**: Install Mattermost (apt or docker), apply the rendered
config.json, and front it with Nginx (plus optional origin cert).

**Triggers**: after PROV green, after a Mattermost version bump, after a
config.env change that alters the rendered config.

**Failure Modes**:
- Running on a distro the Mattermost APT repo doesn't support (falls back to
  Docker silently; watch the deploy log).
- Leaving `pids_limit` in any Docker Compose file ([DOCKER-VS-APT.md](DOCKER-VS-APT.md) describes why).
- Skipping `render-config` and deploying a stale config.json.

**Prompt Module**:
```text
[OPERATOR: 🚀 DEPLOY]
1) Ensure `./operate.sh render-config` was just run — do not re-use a rendered
   config older than the current config.env.
2) Pick DEPLOY_METHOD: apt (default, production) or docker (staging/preview).
3) Run `./operate.sh deploy`; if plan-mode, review the generated script before executing.
4) After deploy, `systemctl status mattermost` OR `docker ps` should show healthy.
5) Emit: "deploy green, method=<apt|docker>, version=<mmctl system version>".
```

**Anchors**: [DOCKER-VS-APT.md](DOCKER-VS-APT.md), [MATTERMOST-CONFIG.md](MATTERMOST-CONFIG.md).

---

### 🛰 NET/TLS — Edge + Origin TLS

**Definition**: Render / provision Cloudflare DNS + Origin CA, Nginx reverse
proxy, WebSocket upgrade, and optional Calls plugin UDP exception.

**Triggers**: first cutover, adding a new hostname, rotating origin cert,
migrating to a different Cloudflare zone.

**Failure Modes**:
- Proxying UDP :8443 (impossible; must be DNS-only).
- Mixing Cloudflare "Full" with an expired origin cert -> 525 errors.
- Forgetting `AllowCorsFrom` when the site will be reached via more than one hostname.

**Prompt Module**:
```text
[OPERATOR: 🛰 NET/TLS]
1) Set CLOUDFLARE_ENABLED=1, ORIGIN_SERVER_IP, CALLS_HOSTNAME (if applicable).
2) Run `./operate.sh edge` then `./operate.sh verify-live`.
3) Check edge-report JSON for DNS proxy state, origin CA validity, Calls DNS-only record.
4) Emit: "edge green, cert expires=<YYYY-MM-DD>, ws=ok, calls_udp=<enabled|n/a>".
```

**Anchors**: [CLOUDFLARE-COOKBOOK.md](CLOUDFLARE-COOKBOOK.md), [NGINX-REFERENCE.md](NGINX-REFERENCE.md), [REALTIME-ORIGIN-SETTINGS.md](REALTIME-ORIGIN-SETTINGS.md), [CALLS-PLUGIN.md](CALLS-PLUGIN.md).

---

### 🔎 LIVE — Live Stack Probes

**Definition**: Prove that HTTP, WebSocket, and (when configured) SMTP are
reachable end-to-end.

**Triggers**: post-deploy, post-cert-rotation, before any staging rehearsal.

**Failure Modes**:
- 200 from Cloudflare while Mattermost is actually down (WAF cached a page).
- WebSocket silently HTTP/1.1 downgrade; everything "works" but real-time is gone.
- SMTP cert changed and the probe fails quietly.

**Prompt Module**:
```text
[OPERATOR: 🔎 LIVE]
1) Run `./operate.sh verify-live`.
2) Read the live-stack JSON: each of http, websocket, smtp should be "ok".
3) Retry up to 3 times if cold-start; anything else blocks.
4) Emit: "live stack green, probe=<json path>".
```

**Anchors**: `scripts/verify-mattermost-live.py`.

---

### 🧪 STAGE — Staging Rehearsal

**Definition**: Upload and process the import ZIP against a staging target,
smoke-test the database, reconcile against the handoff.

**Triggers**: every migration (mandatory), every delta before production.

**Failure Modes**:
- Using `MATTERMOST_URL` as the staging URL by accident (staging guard trips
  unless `ALLOW_NON_STAGING=1`).
- Skipping post-import smoke when the import job reports success but data is partial.
- Comparing observed counts to the wrong handoff file.

**Prompt Module**:
```text
[OPERATOR: 🧪 STAGE]
1) Set STAGING_URL + STAGING_DATABASE_URL distinct from production.
2) Run `./operate.sh staging`.
3) Confirm `staging-summary.json.status == "success"` AND the post-import
   smoke report shows observed counts within tolerance of handoff counts.
4) If any channel count is 0 where handoff.counts.channels > 0 -> STOP.
5) Emit: "staging green, observed vs expected = <table>".
```

**Anchors**: `scripts/run-staging-rehearsal.sh`, `scripts/run-import-smoke-tests.py`, [STAGING-WORKFLOW.md](STAGING-WORKFLOW.md).

---

### 📧 SMTP — Email Activation Path

**Definition**: Prove that password-reset email reaches the destination
before cutover, since activation depends on it.

**Triggers**: any SMTP change, new domain, new sender, before every cutover.

**Failure Modes**:
- Reset email lands in spam; users blame the migration.
- Wrong `FeedbackEmail` -> users reply to a black hole.
- SPF/DKIM/DMARC not set on the sender domain.

**Prompt Module**:
```text
[OPERATOR: 📧 SMTP]
1) Set SMTP_SERVER/PORT/USERNAME/PASSWORD and SMTP_TEST_EMAIL.
2) Run `./operate.sh cutover --smtp-probe-only` (or execute verify-user-activation.sh directly).
3) Expect an email in the test inbox within 60s; open it, click reset link,
   confirm redirect to MATTERMOST_URL/reset_password.
4) Verify SPF/DKIM/DMARC records for the sender domain in Cloudflare DNS.
5) Emit: "smtp green, test reset delivered + link clickable".
```

**Anchors**: [SMTP-SETUP.md](SMTP-SETUP.md), `scripts/verify-user-activation.sh`.

---

### 🧭 READY — Cutover Readiness Gate

**Definition**: Compute a fail-closed readiness gate from every prior report;
produce the score used by the war room.

**Triggers**: the last step before production cutover and whenever the war
room asks "are we go?".

**Failure Modes**:
- Skipping a required report input (restore drill, for instance).
- Greenlight without a named `ROLLBACK_OWNER`.
- Treating the readiness score as advisory when it says "blocked".

**Prompt Module**:
```text
[OPERATOR: 🧭 READY]
1) Confirm intake, render-config, live, staging, restore, smoke, reconcile reports all exist.
2) Set ROLLBACK_OWNER to a named individual.
3) Run `./operate.sh ready`.
4) Read readiness-score.md; confirm status="ready" AND each rubric bucket is green.
5) Emit: "ready gate green, rollback owner=<name>".
```

**Anchors**: `scripts/validate-cutover-readiness.py`, `scripts/generate-readiness-score.py`, [playbooks/CUTOVER-GO-NO-GO.md](playbooks/CUTOVER-GO-NO-GO.md).

---

### ⚠ CUTOVER — Production Cutover

**Definition**: Execute the production import, smoke, reconcile, and
activation-proof gate, all via one command.

**Triggers**: only after READY is green.

**Failure Modes**:
- No Slack freeze in place, so new Slack messages are lost during the window.
- Skipping activation proof (then users can't log in next morning).
- Running cutover while the readiness report is stale.

**Prompt Module**:
```text
[OPERATOR: ⚠ CUTOVER]
1) Freeze Slack (announce read-only; revoke new-post permissions).
2) Run `./operate.sh cutover`.
3) Watch cutover-status.json; on "failed" jump to ⛑ ROLLBACK immediately.
4) On "success", capture the cutover-report folder for the evidence pack.
5) Emit: "cutover complete at <ts>, watch log=<path>, activation=<ok|n/a>".
```

**Anchors**: `scripts/execute-production-cutover.sh`, [WAR-ROOM-OPS.md](WAR-ROOM-OPS.md).

---

### 👥 ACTIVATE — User Activation Rollout

**Definition**: Drive users through the password-reset flow, help desk
readiness, and early-issue triage.

**Triggers**: immediately after cutover success, then T+1h / T+24h checkpoints.

**Failure Modes**:
- Mass announcement without a verified test activation first.
- No on-call bucket for "I can't log in" tickets.

**Prompt Module**:
```text
[OPERATOR: 👥 ACTIVATE]
1) Do one real end-to-end activation (you or a volunteer) before the announcement.
2) Send the kickoff message from [comms/USER-COMMS-KIT.md](comms/USER-COMMS-KIT.md).
3) Monitor help-desk tickets for 2h; apply [playbooks/ACTIVATION-HARDENING.md](playbooks/ACTIVATION-HARDENING.md) if spikes appear.
4) Emit: "activation N/total, tickets=<count> open".
```

**Anchors**: [USER-ACTIVATION.md](USER-ACTIVATION.md), [comms/USER-COMMS-KIT.md](comms/USER-COMMS-KIT.md).

---

### ♻ OPS — Ongoing Operations

**Definition**: Turn the migration into a steady-state system: backups,
monitoring, plugin rollouts.

**Triggers**: after the first week post-cutover.

**Failure Modes**: no backup == catastrophic loss; no monitoring == silent failure.

**Prompt Module**:
```text
[OPERATOR: ♻ OPS]
1) Confirm `pg_dump` cron + off-site copy (Hetzner Storage Box or R2).
2) Confirm Prometheus scrape on :8067, Grafana dashboards loaded.
3) Revoke Slack migration tokens; delete the migration Slack app.
4) Schedule the delete of staging Mattermost if unused.
5) Emit: "ops hand-off complete; backup cron=<schedule>, monitoring=<url>".
```

**Anchors**: [BACKUPS.md](BACKUPS.md), [MONITORING.md](MONITORING.md), [POST-CUTOVER-OPS.md](POST-CUTOVER-OPS.md).

---

### ⛑ ROLLBACK — Guided Rollback

**Definition**: Restore DB + optional config/data backups to a last-known-good
state when cutover goes sideways.

**Triggers**: CUTOVER failed; readiness score retroactively red; a broken
critical integration discovered post-cutover.

**Failure Modes**:
- Rollback without naming the owner / exact restore timestamp.
- Restoring DB while Mattermost is still writing to it.
- No `ROLLBACK_CONFIRMATION` env -> the script refuses, but the operator
  panics and edits the script in place.

**Prompt Module**:
```text
[OPERATOR: ⛑ ROLLBACK]
1) Stop accepting new work: pause mattermost service.
2) Confirm ROLLBACK_DB_BACKUP path, DATABASE_URL, and named ROLLBACK_OWNER.
3) Export ROLLBACK_CONFIRMATION="I_UNDERSTAND_THIS_RESTORES_BACKUPS" and run `./operate.sh rollback`.
4) Start Mattermost; run verify-live; run a mini smoke against handoff expectations.
5) Emit: "rollback complete, restored to=<timestamp>, owner=<name>".
```

**Anchors**: [ROLLBACK-AND-ABORT-CRITERIA.md](ROLLBACK-AND-ABORT-CRITERIA.md), `scripts/rollback-cutover.sh`.

---

## Hygiene Operators

- **ΔE Exception Quarantine** — every unexpected log line in the import
  watch log becomes a quarantined entry in the cutover report, not a
  "probably fine" dismissal.
- **🧾 Provenance** — every report (`*.json`/`*.md`) gets copied into
  `workdir/reports` with a timestamp. The evidence pack is the sum of those.
- **† Theory-Kill** — if a working hypothesis ("mmctl will find the bundle
  under /imports") fails, don't update it in place; delete and replace.
