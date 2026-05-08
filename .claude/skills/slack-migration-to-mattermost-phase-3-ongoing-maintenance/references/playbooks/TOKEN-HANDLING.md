# Secret Handling

Phase 3 touches real admin-plane secrets. Handle with care.

## Rules

1. **Never in git.** `.gitignore` excludes `config.env` and `workdir-phase3/`.
   If you're turning your migration working directory into a repo, verify
   the `.gitignore` before your first commit.
2. **Never in agent chat.** Secrets in agent sessions stay in session history
   which is preserved longer than ideal. Paste credentials once, then ask the
   agent to reference them via `config.env` for future stages.
3. **Never on the command line with `--password`.** Use `mmctl auth --token-file`
   or the PAT flow, never `mmctl auth login --password`.
4. **Never in reports.** Every Phase 3 script passes output through a redactor
   before writing to `workdir-phase3/reports/`; the redactor is the same one
   from Phase 1 (`scan-and-redact-migration-secrets.py`).
5. **Rotate on a cadence.** See cadence table below.

## Credential inventory and cadence

| Credential | Stored in | Rotation | Rotation trigger |
|------------|-----------|----------|------------------|
| Mattermost admin PAT | `config.env.MATTERMOST_ADMIN_TOKEN` + password manager | 90 days | quarterly `rotate-credentials` |
| `mmuser` Postgres password | `config.env.POSTGRES_DSN` + password manager | 180 days | twice-yearly `rotate-credentials` |
| SSH private key | `~/.ssh/id_ed25519` + Keychain / password manager | 365 days or on operator change | annual `rotate-credentials` |
| `OFFSITE_REMOTE` token | rclone config + password manager | 365 days | annual `rotate-credentials` |
| Cloudflare API token | rclone / password manager | 365 days | annual `rotate-credentials` |
| Postmark server token | Phase 2 config.env + password manager | 365 days | annual `rotate-credentials` |
| Mattermost admin password | password manager (almost never used; PAT preferred) | 365 days | annual |

## Rotation procedure (per credential, high-level)

The agent-driven `rotate-credentials` stage wraps this; the manual flow is:

1. **Create new credential.** Generate via the provider UI (Mattermost
   System Console for PAT, Cloudflare dashboard for API token, `ssh-keygen`
   for a fresh SSH keypair).
2. **Test new credential independently.** For PAT: `curl -H "Authorization:
   Bearer $NEW_TOKEN" "$MATTERMOST_URL/api/v4/users/me"` returns 200.
3. **Update `config.env`.** The `rotate-credentials` stage has a
   `--update-config` flag that does this via an atomic rewrite (old file
   backed up with `.bak.<ts>` suffix).
4. **Run `doctor.sh --require-remote --require-mcp`.** All green before
   proceeding.
5. **Revoke the old credential.** PAT: delete in System Console. SSH:
   remove from `authorized_keys`. API tokens: delete in provider console.
6. **Verify old credential revoked.** Rerun the independent test; should
   now 401/403.
7. **Log in audit trail.** Append to
   `workdir-phase3/rotate-credentials-audit.json`.

## Emergency revocation (compromise suspected)

If you suspect a PAT or SSH key leaked:

1. Revoke the credential immediately in the provider console (don't wait
   for the rotation stage).
2. Check for unauthorized activity:
   - Mattermost: System Console → Reporting → Audits (or query `Audits`
     table directly for recent admin actions).
   - SSH: `ssh deploy@TARGET last` and `sudo journalctl _SYSTEMD_UNIT=ssh.service`
     on the target.
3. If evidence of compromise: follow [QUARANTINE-AND-EVIDENCE.md](QUARANTINE-AND-EVIDENCE.md).
4. Rotate everything the compromised credential could touch:
   - PAT: rotate PAT, review recent user/channel/role changes.
   - SSH: rotate SSH key, audit `authorized_keys` on target, check for
     unexpected cron jobs / systemd units.

## Where secrets live, explicitly

| Location | What |
|----------|------|
| `config.env` | PAT, DSN, SSH key path, SMTP token |
| Password manager | Primary copy of every secret |
| `~/.ssh/id_*` | SSH private key + passphrase (Keychain / ssh-agent) |
| `rclone.conf` | Off-site backup remote credentials |
| System keychain (macOS / Windows) | Aggregated by OS for SSH agent forwarding |
| MCP server config | Mattermost PAT (registered via `install-mcp-servers.sh`) |

The MCP server config file may persist the PAT; it lives at
`~/.claude/config.json` or `~/.codex/config.json` and should be
`chmod 600`.

## "Don't do this"

- Don't share `config.env` with another operator; they should copy the
  template and fill in their own values (Mattermost PAT is per-operator).
- Don't check `config.env` into a "private" git repo as a backup; use the
  password manager for that.
- Don't paste full PAT into a chat, even with Claude. Use env var
  references: "use the token from `$MATTERMOST_ADMIN_TOKEN` in config.env".
- Don't `echo` secrets in prompts; the agent may include them in logs.
