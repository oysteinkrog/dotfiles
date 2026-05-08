# Quarantine and Evidence Preservation

When an incident looks like it might be a compromise, a data-integrity
event, or a legal-hold trigger: preserve state before mutating anything.

## Triggers

Quarantine mode starts when any of these is true:

- evidence of unauthorized admin activity (PAT use from unfamiliar IP,
  unexpected channels / users created, permissions changes not matching
  the admin log)
- evidence of credential compromise (SSH connection from unknown IP in
  `/var/log/auth.log`, new key in `authorized_keys`)
- Postgres logs mention `corrupt`, `invalid page`, or `unexpected chunk`
- legal hold notice received for a specific user / channel
- ransomware-like behavior (file attachments renamed, `.encrypted` suffix,
  ransom note in `/opt/mattermost/data/`)

## Don't do this yet

- **Do not restart Mattermost.** Running state (process memory, open file
  handles) is evidence.
- **Do not delete logs.** `/opt/mattermost/logs/`, `/var/log/auth.log`,
  `/var/log/nginx/`, Postgres WAL — all evidence.
- **Do not rotate credentials yet.** Old credential's audit trail needs to
  stay viewable for forensics.
- **Do not run an `update-os` or `update-mattermost`.** You'll lose
  package-pin evidence.
- **Do not push new config.** You'll lose "as attacked" state.

## First 15 minutes — preserve

1. **Pre-action backup** of the DB:
   ```
   ./maintain.sh backup
   ```
   Label the resulting dump filename with an `-incident-<id>` suffix so
   rotation doesn't touch it.

2. **Snapshot the filesystem** of the target (if Hetzner / OVH, use the
   provider's snapshot feature for a point-in-time image):
   - Hetzner: robot → server → Snapshots → Create.
   - OVH / Contabo: similar via control panel.
   This captures logs + Postgres state + attachments without touching the
   running host.

3. **Copy logs off-target** for operator-local analysis:
   ```
   rsync -az deploy@$TARGET_HOST:/opt/mattermost/logs/         workdir-phase3/reports/incidents/<id>/mm-logs/
   rsync -az deploy@$TARGET_HOST:/var/log/nginx/               workdir-phase3/reports/incidents/<id>/nginx-logs/
   rsync -az deploy@$TARGET_HOST:/var/log/auth.log*            workdir-phase3/reports/incidents/<id>/auth-logs/
   rsync -az deploy@$TARGET_HOST:/var/log/syslog*              workdir-phase3/reports/incidents/<id>/syslog/
   ```

4. **Capture running state** (for compromise cases):
   ```
   ssh deploy@$TARGET_HOST "ps auxf; ss -tulpn; who; sudo last -n 50; sudo lastlog" \
       > workdir-phase3/reports/incidents/<id>/process-state.txt
   ```

5. **Hash the incident-quarantine bundle** so later integrity is verifiable:
   ```
   find workdir-phase3/reports/incidents/<id>/ -type f -exec sha256sum {} \; \
       > workdir-phase3/reports/incidents/<id>/SHA256SUMS
   ```

## Next 30 minutes — decide

Based on the severity:

- **Credential compromise only** (no data tampering evidence): rotate all
  credentials per [TOKEN-HANDLING.md](TOKEN-HANDLING.md) "Emergency
  revocation". Keep server running. Write post-mortem.
- **Data tampering confirmed**: disaster-recover onto a fresh host from a
  pre-incident backup; the compromised host is forensic evidence and stays
  offline. See [../DISASTER-RECOVERY.md](../DISASTER-RECOVERY.md).
- **Ransomware / destructive event**: same as data tampering. The old
  host is a total loss.
- **Legal hold for specific users/channels**: do not delete their data;
  flag in `workdir-phase3/reports/incidents/<id>/legal-hold.md` with
  scope and duration. Coordinate with legal on retention beyond the
  skill's normal rotation.

## Chain of custody

Every evidence artifact goes into
`workdir-phase3/reports/incidents/<id>/` with:

- SHA-256 hash recorded in `SHA256SUMS`
- timestamp of acquisition
- operator name / agent session ID
- reason for capture

If this matters legally (it usually does if a third party caused harm),
share the encrypted bundle with counsel; do not publish in chat.

## Involve ROLLBACK_OWNER

Don't proceed to DR or credential rotation without the named human's
explicit approval. If `ROLLBACK_OWNER` is you, document the approval to
yourself with timestamp and reason.

## After the incident

- Write a post-mortem with timeline, evidence captured, root cause, and
  remediation. Keep it under `workdir-phase3/reports/incidents/<id>/POSTMORTEM.md`.
- File durable fixes: if the incident exploited a stale PAT, shorten the
  rotation cadence. If the incident was an insider, revisit access model.
- Retention: keep the encrypted incident bundle for at least as long as
  your compliance policy requires (typically 7 years for SOC2, GDPR, HIPAA).
