# Troubleshooting Index

Symptom-driven. Skim for your symptom, click through to the per-stage
diagnostic for deep fixes.

## `doctor.sh` fails

| Symptom | Fix |
|---------|-----|
| `mmctl not found` | `scripts/bootstrap-tools.sh` (macOS: may need `go install`). |
| `psql not found` on macOS | `brew install libpq` + add `$(brew --prefix)/opt/libpq/bin` to PATH. |
| `config.env not found` | Copy `config.env.example` to `config.env`; fill in values. |
| `ssh:target fail` | Verify `TARGET_HOST`, key path, and that the key is in `deploy@TARGET:~/.ssh/authorized_keys`. Re-run Phase 2's SSH verification if needed. |
| `ssh:host_key fail` | SSH host key changed. Either the server was rebuilt (accept: `ssh-keygen -R TARGET_HOST`) or you're being MitM'd (investigate). |
| `mattermost:pat fail` | PAT was revoked or rotated. Regenerate in System Console → Integrations → PATs; update `config.env`. |
| `mcp:any_agent fail` | `scripts/install-mcp-servers.sh`, then restart the agent CLI / desktop app. |

## Weekly-sweep red

| Symptom | Next read |
|---------|-----------|
| `health` red | [diagnostics/HEALTH-DIAGNOSTICS.md](diagnostics/HEALTH-DIAGNOSTICS.md) |
| `update-os` red | target host disk / apt problems → [diagnostics/HEALTH-DIAGNOSTICS.md](diagnostics/HEALTH-DIAGNOSTICS.md) "Disk" |
| `backup` red | [diagnostics/BACKUP-DIAGNOSTICS.md](diagnostics/BACKUP-DIAGNOSTICS.md) |
| `db-health` red | [POSTGRES-MAINTENANCE-DEEP-DIVE.md](POSTGRES-MAINTENANCE-DEEP-DIVE.md) |

## Upgrade failures

| Symptom | Next read |
|---------|-----------|
| apt can't find target version | [diagnostics/UPGRADE-DIAGNOSTICS.md](diagnostics/UPGRADE-DIAGNOSTICS.md) "APT version not found" |
| Migration hangs >30 min | [diagnostics/UPGRADE-DIAGNOSTICS.md](diagnostics/UPGRADE-DIAGNOSTICS.md) "Long migration" |
| Ping doesn't return after upgrade | auto-rollback should trigger; see `latest-update-mattermost.json.status` |
| Auto-rollback couldn't downgrade apt | manual rollback path in [playbooks/UPGRADE-GO-NO-GO.md](playbooks/UPGRADE-GO-NO-GO.md) |
| Plugin broke after minor upgrade | [PLUGIN-LIFECYCLE.md](PLUGIN-LIFECYCLE.md) |

## Restore-drill failures

| Symptom | Fix |
|---------|-----|
| `pg_restore` errors on scratch DB | PG major-version mismatch; scratch DB's PG must be >= live PG |
| Row count below `RESTORE_MIN_*` | stale minimums or backup was truncated. Compare against a recent `db-health`. |
| `SCRATCH_DB_URL` unreachable | check credentials + network; see [CONFIG-REFERENCE.md](CONFIG-REFERENCE.md) |
| Backup file too old | latest off-site upload failed silently; check `latest-backup.json` for the last N days |

## Incident: users report Mattermost down

First: `./maintain.sh health` and read [playbooks/INCIDENT-RESPONSE.md](playbooks/INCIDENT-RESPONSE.md).

| Symptom from health | Likely cause | First move |
|---------------------|--------------|------------|
| `mattermost_ping=red` | Mattermost process crashed | `ssh target sudo systemctl status mattermost` |
| `websocket_upgrade=red` ping ok | Nginx lost Upgrade headers | Re-run Phase 2 `render-config`+`deploy`, or fix Nginx inline |
| `smtp_tcp=red` only | Provider blocked / creds rotated | Users still log in; reset-password path broken. Paste [comms/INCIDENT-STATUS-KIT.md](comms/INCIDENT-STATUS-KIT.md) "activation slow" |
| `disk_root=red` | `/var/log` or `/opt/mattermost/data` blowup | `ssh target sudo du -shx /*` to find it |
| `pg_connections=red` | Connection leak or burst | `pg_stat_activity` query + terminate idle in transaction |

## Credential rotation problems

| Symptom | Fix |
|---------|-----|
| PAT rotation broke mmctl auth | new PAT not saved to `config.env`; re-run with `--update-config` |
| Removed last SSH key by mistake | boot into Hetzner rescue (see [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) "Lost keys") |
| Cloudflare scoped token revoked mid-rotation | create a new token with identical scopes; old token is gone |

## Agent session problems

| Symptom | Fix |
|---------|-----|
| Agent doesn't see the skill | Restart the Claude Code / Codex session. Desktop apps index `~/.claude/skills/` at launch. |
| MCP tool calls fail silently | `doctor.sh --require-mcp` to check registration. `install-mcp-servers.sh` to re-register. |
| Agent generates commands that don't match stage | Paste the exact stage prompt from `prompts/`. The operator library is the authoritative source of stage behavior. |

## Escalation

See [comms/ESCALATION-LADDER.md](comms/ESCALATION-LADDER.md) for when to
escalate beyond this skill and to whom.
