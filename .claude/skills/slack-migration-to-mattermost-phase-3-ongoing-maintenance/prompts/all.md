Run every Phase 3 stage end-to-end (for audit / compliance; not a normal
operation). Takes 30-90 minutes. Requires operator attention for any gates.

1. `./scripts/doctor.sh` + `--require-remote` + `--require-mcp`. Stop if red.
2. `./maintain.sh health` — capture baseline.
3. `./maintain.sh backup` — fresh pre-run snapshot.
4. `./maintain.sh db-health` — DB posture snapshot.
5. `./maintain.sh restore-drill` — prove backup restores.
6. `./maintain.sh update-os` — OS patches.
7. If reboot required, pause and get operator decision on scheduling.
8. `./maintain.sh health` again — post-patch.
9. Tally all `latest-*.json` reports; produce one consolidated summary.

Surface any red metric. Do not auto-proceed if any stage flips red.

Don't run `update-mattermost` or `rotate-credentials` as part of this combo;
those are deliberate, per-event operations.
