Ready-to-paste prompts for Phase 3 maintenance. Each file is a single prompt you can drop into a Claude Code or Codex session.

- `orient.md` — figure out where this deployment is, read the config
- `health.md` — one-shot health snapshot
- `update-os.md` — apply OS patches; schedule reboot if required
- `update-mattermost.md` — bump Mattermost to a pinned version
- `backup.md` — take a pg_dump, upload off-site, verify hash
- `db-health.md` — Postgres health: sizing, bloat, connections
- `restore-drill.md` — quarterly restore-from-backup verification
- `schedule-reboot.md` — schedule a pending reboot in the next off-hours window
- `weekly-sweep.md` — the combo sweep for Saturday nights
- `disaster-recovery.md` — rebuild from backup onto a fresh host

All prompts assume you are in the phase-3 skill's working directory with `config.env` populated. If you're not, ask the agent to run `./scripts/doctor.sh` first.
