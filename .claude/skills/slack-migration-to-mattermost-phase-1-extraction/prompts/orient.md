Use the `slack-migration-to-mattermost-phase-1-extraction` skill. Before doing anything:

1. Read `SKILL.md` for the canonical default path and the stop-if-missing list.
2. Read `references/START-HERE.md` to resolve my branch (official export / slackdump-primary / grid split / baseline+deltas).
3. Read `config.env` and tell me which values are still empty and which Track (A/B/C) we're on.
4. Read `references/OPERATOR-LIBRARY.md` so you have the operator cards (TIER, AUTH, SCOPE, ENRICH, XFORM, VERIFY, SPLIT, HANDOFF) loaded as context.
5. Summarize in 6-8 bullets: which Track we're on, what the next stage is, what's blocking it, what the rollback story looks like if it fails.

Do not run any stage yet. I want to align on the plan first.
