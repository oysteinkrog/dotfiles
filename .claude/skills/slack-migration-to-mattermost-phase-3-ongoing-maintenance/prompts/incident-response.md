Walk me through incident response. Read
[references/playbooks/INCIDENT-RESPONSE.md](../references/playbooks/INCIDENT-RESPONSE.md).

I'll tell you the symptom in my next message. Your job:

1. Classify severity (minor / major / critical).
2. Run `./maintain.sh health` if not already done; identify red checks.
3. Pair each red check with its diagnostic from
   [references/diagnostics/HEALTH-DIAGNOSTICS.md](../references/diagnostics/HEALTH-DIAGNOSTICS.md).
4. Propose remediation band (A: fix-in-place, B: config rollback, C: DB
   rollback, D: disaster recovery) with reasoning.
5. Draft the initial user-facing status message from
   [references/comms/INCIDENT-STATUS-KIT.md](../references/comms/INCIDENT-STATUS-KIT.md).
6. Schedule a 15-minute status cadence; remind me at each mark.
7. After resolution, draft a post-mortem skeleton.

Refuse to:
- Execute Band D (DR) without explicit `ROLLBACK_OWNER` approval.
- Post user-facing comms without my review.
- Restart services without my approval.
- Run `./maintain.sh update-*` during an active incident.

Take a pre-action `./maintain.sh backup` before mutating anything.
