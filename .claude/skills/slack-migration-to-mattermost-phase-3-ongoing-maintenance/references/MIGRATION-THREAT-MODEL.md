# Threat Model — Ongoing Ops

Phase 3 runs against a live system with real user data. The threats are
different from Phase 1 (data extraction) and Phase 2 (first cutover):
insiders with stale access, upstream-dependency drift, backup theater
(backups that don't restore), silent credential leak.

## Assets

- Mattermost admin PAT (full-admin API access, full history read/write)
- `POSTGRES_DSN` password (direct DB access, bypasses Mattermost ACLs)
- SSH private key for `TARGET_SSH_USER` (root-equivalent via `sudo -n`)
- `OFFSITE_REMOTE` credentials (rclone token / R2 access keys)
- Postmark / SMTP token (can send email on behalf of the domain)
- Cloudflare API token (DNS + origin-cert rotation, scoped to one zone)
- `pg_dump` files on disk (full conversation history, unencrypted)
- `/opt/mattermost/data/` file attachments (if local-stored)
- `workdir-phase3/reports/` (audit trail; not sensitive alone but combined leaks deployment shape)

## Trust Boundaries

- **Operator workstation** — the agent runs here; secrets live in a password
  manager and `config.env`. Compromise here is game over for this instance.
- **Live Mattermost host** — root access via SSH from the workstation. Phase 2
  hardened it (UFW, fail2ban, unattended-upgrades, non-root `deploy` user).
- **Off-site backup destination** — rclone-managed credentials with scoped
  permissions (write + list only, not delete; lifecycle policy handles
  retention).
- **Cloudflare edge** — scoped API token (`Zone.DNS:Edit` + `Zone.SSL:Edit`
  on one zone); no account-level permissions.
- **Upstream Mattermost APT repo** — trusted HTTPS with repo signing; a
  compromise here is a broader supply-chain event outside Phase 3's scope.
- **Scratch DB host** — usually same box as live DB, different database
  name; isolated via Postgres role. Contents are disposable (wiped by every
  `restore-drill`).

## Adversarial Concerns

- **Stale PAT** — operator left company, PAT still active; `rotate-credentials`
  on 90-day cadence bounds the window.
- **SSH key sprawl** — multiple operators over time, authorized_keys
  accumulates; `rotate-credentials` audits and prunes.
- **Backup theater** — nightly backups exist but don't restore; quarterly
  `restore-drill` is the canary. If the drill fails the skill refuses
  `update-mattermost` until fixed.
- **Silent upgrade regression** — new Mattermost version introduces a
  subtle bug; auto-rollback on ping failure bounds the damage but does not
  catch slow-burn bugs. Post-upgrade `health` + user comms are the manual
  catch.
- **Credential leak via logs** — `mmctl auth login --password ...` leaves
  history; Phase 3 uses PAT-based `mmctl auth --token-file` to avoid
  passwords on the command line.
- **DNS hijacking** — a compromised Cloudflare token could repoint the
  zone. Scoped token minimizes blast radius; quarterly verification of
  the DNS record against expected IP is in `health`.
- **Off-site backup theft** — an attacker with read access to off-site
  storage has the full history. Countermove: encrypt at rest with `rclone
  crypt` remote or `gpg` pre-upload (configure at operator discretion).
- **Insider wipe** — a compromised admin PAT could delete channels. Phase 3
  backups give you recovery via `restore-drill`-proven backups; DB soft
  deletes allow row-level recovery for recent deletions.
- **Unpatched CVE on the host** — `update-os` + `schedule-reboot` bound the
  exposure window. Security-flagged releases ship faster than the normal
  weekly cadence; on-demand `update-os` should follow a CVE announcement.

## Required Countermoves

- Hash every backup (SHA-256) and verify the upload.
- Fail closed on gates (restore-drill + PAT validity before upgrade).
- Rotate credentials on a named cadence.
- Scan reports for secret patterns before writing (shared
  `scan-and-redact-migration-secrets.py` from Phase 1 can be invoked).
- Use SSH `BatchMode=yes` and refuse on host-key change until acknowledged.
- Encrypt the off-site remote at rest (or use a provider that does this
  transparently, like R2 with SSE).
- Review `authorized_keys` on the target quarterly (`rotate-credentials`
  has a sub-step).

## Out of Scope

- **HA and zero-downtime** — stock Phase 3 is single-host. HA requires
  Kubernetes + external DB + shared storage; see Mattermost Enterprise
  reference architecture.
- **Intrusion detection** — Phase 3 verifies fail2ban is running but does
  not parse logs for intrusion patterns. Use Wazuh, OSSEC, or a managed
  SIEM.
- **End-user device compromise** — outside the server's control.
- **Slack-side residual access** — once cutover is complete, Phase 1's
  tokens are revoked; Slack workspace hygiene is the admin's job.
