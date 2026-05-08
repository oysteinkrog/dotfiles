Use the `slack-migration-to-mattermost-phase-2-setup-and-import` skill. Before doing anything:

1. Read `SKILL.md` for the canonical default path + stop-if-missing list.
2. Read `references/START-HERE.md`, `references/WAR-ROOM-OPS.md`, `references/ROLLBACK-AND-ABORT-CRITERIA.md`.
3. Read `config.env` (or the file `PHASE2_CONFIG` points at) and tell me which values are still empty.
4. Read `references/OPERATOR-LIBRARY.md` so the operator cards (INTAKE, PROV, DEPLOY, NET/TLS, LIVE, STAGE, SMTP, READY, CUTOVER, ACTIVATE, OPS, ROLLBACK) are in context.
5. Summarize in 8-10 bullets: which stage is next, what's blocking it, whether `ROLLBACK_OWNER` is set (MUST be a named human, not a role), whether staging has a separate URL, whether SMTP has been tested.

Do not run any stage yet.
