Walk me through disaster-recovery against a dead or compromised Mattermost host.

1. First, confirm prerequisites (read references/DISASTER-RECOVERY.md "Prerequisites" section and check each one):
   - Recent passing restore-drill
   - Workstation has Phase 2 skill installed
   - Hetzner login is active
   - ROLLBACK_OWNER has approved

2. If any prerequisite is missing, STOP and tell me what's blocking.

3. Otherwise, walk me through the playbook phase by phase (D1 to D7). Before each phase, show me the commands you intend to run and wait for approval.

4. Keep a running log in `workdir-phase3/reports/dr-<timestamp>.md` of each phase completed + any notes.

5. At the end, produce a post-mortem skeleton: timeline, root cause, data lost, what worked, what didn't.

Refuse to do anything in Phases D4 to D6 without explicit go from me per phase. This is a destructive operation.
