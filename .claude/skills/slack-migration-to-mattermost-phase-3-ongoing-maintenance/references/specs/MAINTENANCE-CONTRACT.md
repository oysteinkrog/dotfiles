# Maintenance Contract

What the Phase 3 skill guarantees to its users (operators and their
Mattermost's users).

## To the operator

The skill guarantees:

1. **Every stage is recorded.** `workdir-phase3/reports/<stage>-<ts>.json`
   exists for every run that got past the config-load step.
2. **Every stage has a pass criterion.** See [../DONE-DEFINITION.md](../DONE-DEFINITION.md).
3. **Destructive stages refuse to run without gates.** See "Stop Immediately
   If" in SKILL.md.
4. **Auto-rollback on Mattermost upgrades** when `MATTERMOST_UPGRADE_ROLLBACK=auto`
   and a pre-upgrade dump exists.
5. **Hash everything persistent.** Backups carry SHA-256; config changes
   are diff-able against Phase 2's rendered versions.
6. **Idempotent by default.** Re-running `health`, `backup`, `db-health`,
   `restore-drill`, `update-os`, `weekly-sweep` does not cause harm.
7. **No state in git.** Secrets and reports are local only.
8. **Operator can resume after any interruption.** If the agent session
   dies mid-stage, re-run the same stage; it will pick up from idempotent
   state or start fresh safely.

## To the Mattermost users

The skill guarantees (indirectly, by running correctly):

1. **Downtime stays in the configured window.** `REBOOT_WINDOW_*` bounds
   scheduled reboots. Upgrades aim for ≤ 15 minutes.
2. **Backup-grade restore** every 24 hours (nightly cadence). RPO:
   whatever your backup schedule says (default 24 hours).
3. **Incident response triage within 10 minutes** per [../playbooks/INCIDENT-RESPONSE.md](../playbooks/INCIDENT-RESPONSE.md).
4. **Rollback available** within 30 minutes for any stage that went
   wrong (auto-rollback) or 2-4 hours for a full DR event.

## To the compliance reviewer / auditor

- Every destructive operation has a named `ROLLBACK_OWNER`.
- Every credential rotation has an audit trail.
- Quarterly restore-drills are logged.
- Incident responses produce a post-mortem.
- Secret scanner runs on report writes.
- Off-site backup integrity is verified by hash comparison.

See [DONE-DEFINITION.md](../DONE-DEFINITION.md) for the full compliance
evidence list.

## What the skill does NOT guarantee

- **Zero downtime.** Single-host architecture has scheduled downtime
  windows. HA is out of scope.
- **Sub-minute RPO.** Default nightly backup; RPO = up to 24 hours.
  Shorter RPO requires streaming replication (out of scope).
- **Real-time anomaly detection.** Weekly health snapshots only. For
  continuous monitoring, see [../OBSERVABILITY-LADDER.md](../OBSERVABILITY-LADDER.md).
- **Intrusion detection.** `fail2ban` + UFW are perimeter only; the skill
  does not run SIEM on logs.
- **Automatic incident communication.** Operator drafts user-facing
  updates from templates; the skill does not auto-post to your status page.

## SLO targets (informational)

If you want to set SLOs around the operator's performance using this skill:

| SLO | Target |
|-----|--------|
| Mattermost availability (excl. maintenance windows) | 99.9% monthly |
| Max maintenance-window impact | 15 min/month |
| Backup success rate | 99% of nightly runs |
| Restore-drill pass rate | 100% (quarterly) |
| Mean time to detect incident | 10 min (manual via user reports) |
| Mean time to resolve incident | 60 min (Band A/B) |
| Mean time to resolve with DR | 4 hours (Band D) |

These are achievable with correct operation of the skill. Missing them
persistently suggests a skill or operator issue; investigate.
