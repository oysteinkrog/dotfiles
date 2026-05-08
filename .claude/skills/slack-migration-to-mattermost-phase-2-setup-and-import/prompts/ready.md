Use the Phase 2 skill to run the `ready` stage (fail-closed readiness gate).

1. Run `./operate.sh ready`. This produces `cutover-readiness.json`, `readiness-score.md`, `phase2-readiness.md`.
2. Read all three and summarize. `status` should be exactly `"ready"`. Anything else = blocked, list the reasons.
3. Confirm specifically: ROLLBACK_OWNER is a named human, staging passed, SMTP verified, reconciliation green.
4. Paste `phase2-readiness.md` in a format I can share with the war room.

NEVER let the session proceed to `cutover` if this is `blocked`. Fix the gaps, re-run `ready`, and come back.
