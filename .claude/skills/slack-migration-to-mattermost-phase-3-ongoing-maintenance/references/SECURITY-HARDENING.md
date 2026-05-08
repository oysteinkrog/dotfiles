# Security Hardening (Ongoing)

Phase 2 did the initial hardening (UFW, fail2ban, unattended-upgrades,
non-root `deploy` user). Phase 3 keeps it from drifting.

## Weekly (verified by `health`)

- `fail2ban` service active
- `ufw` service active; rules match Phase 2's baseline (22/80/443/8443)
- `unattended-upgrades` service active
- `mattermost` service active, listening only on 127.0.0.1:8065
- `nginx` service active, serving 443 only

## Monthly (manual audit, supported by `security-posture-auditor`)

- Run `security-posture-auditor` subagent: reviews PAT age, SSH
  `authorized_keys`, service status, cert expiry.
- Verify SSH `/etc/ssh/sshd_config`:
  - `PermitRootLogin no`
  - `PasswordAuthentication no`
  - `KbdInteractiveAuthentication no`
  - `PubkeyAuthentication yes`
- Verify Nginx `/etc/nginx/sites-enabled/mattermost.conf`:
  - TLS 1.2+ only
  - HSTS header present
  - Security headers: `X-Content-Type-Options nosniff`, `X-Frame-Options SAMEORIGIN`

## Quarterly (`rotate-credentials`)

- Rotate Mattermost admin PAT.
- Review Mattermost System Console → Reporting → Audits for the last 90
  days. Anything unexpected?
- Review Mattermost System Console → User Management → Users, filter
  for `system_admin` role. Remove admins who no longer need it.

## Annually (`rotate-credentials` + manual)

- Rotate SSH keypairs.
- Rotate Postmark server token.
- Rotate Cloudflare API token.
- Rotate `OFFSITE_REMOTE` rclone credentials.
- If using Let's Encrypt at origin (not recommended; Origin CA is better):
  verify ACME renewal cron is still running.
- Review Cloudflare Origin CA cert expiry (15 years; normally plenty).

## Mattermost-specific hardening

### `config.json` knobs worth reviewing annually

- `ServiceSettings.EnableSecurityFixAlert`: true
- `ServiceSettings.EnableDeveloper`: false
- `TeamSettings.MaxUsersPerTeam`: set to reasonable cap
- `PasswordSettings.MinimumLength`: 10+
- `PasswordSettings.Lowercase / Uppercase / Number / Symbol`: all true
- `ServiceSettings.EnableMultifactorAuthentication`: true (if compliance requires)
- `PluginSettings.Enable`: true only if you use plugins
- `PluginSettings.EnableUploads`: false unless actively uploading plugins
- `FileSettings.EnablePublicLink`: false unless needed
- `RateLimitSettings.Enable`: true
- `ComplianceSettings.Enable`: true on Professional Edition if you need it

### Plugin hygiene

- Pin plugin versions; don't auto-upgrade plugins alongside Mattermost.
- Audit installed plugins quarterly (`list_plugins` via MCP or System Console).
- Remove plugins you stopped using; each plugin is an attack surface.
- Favor first-party plugins (Mattermost-maintained) over third-party.

### User access hygiene

- SAML/OIDC (Professional Edition) for centralized identity if your
  org uses it. Beats per-user local passwords.
- Review `system_admin` role grants quarterly; fewer is better.
- Disable inactive users (>90 days no login) via `mmctl user deactivate`.
- Reap old bot accounts.

## File permissions (target)

- `/etc/nginx/ssl/origin-key.pem`: 0600 owned by root
- `/opt/mattermost/config/config.json`: 0600 owned by `mattermost:mattermost`
- `/opt/mattermost/data/`: 0700 owned by `mattermost:mattermost`
- `/var/backups/mattermost/`: 0700 owned by `postgres:postgres`
- `~deploy/.ssh/authorized_keys`: 0600 owned by `deploy:deploy`
- `~deploy/.ssh/`: 0700 owned by `deploy:deploy`

Phase 3's `health-check.sh` confirms the top three; the others are
verified by `security-posture-auditor`.

## Handling a CVE announcement

1. Read the advisory; identify affected versions.
2. If current version is affected: `./maintain.sh update-mattermost`
   with the fixed version pinned, within 72 hours (shorter for critical
   CVEs).
3. If the fix is a config change, not a version bump: apply via Phase 2's
   `render-config` to regenerate, then `deploy`.

## Known attack surfaces (to watch over time)

- SMTP open relay misconfiguration (Phase 2 avoids this; re-verify on
  rotation).
- Plugin sandbox escapes (mitigation: fewer plugins, pinned versions).
- CSRF tokens on admin endpoints (Mattermost enforces; don't disable).
- File-upload endpoints (rate-limit at Nginx if attacked).

## Related docs

- [playbooks/TOKEN-HANDLING.md](playbooks/TOKEN-HANDLING.md) — secret
  rotation detail
- [playbooks/QUARANTINE-AND-EVIDENCE.md](playbooks/QUARANTINE-AND-EVIDENCE.md) — compromise response
- [MIGRATION-THREAT-MODEL.md](MIGRATION-THREAT-MODEL.md) — attacker
  categories and countermoves
