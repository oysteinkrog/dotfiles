Run the quarterly restore-drill to prove our backups actually work.

1. Confirm `SCRATCH_DB_URL` is set in config.env and points at a DB we don't mind wiping. If not, stop and ask me to set it.
2. Run `./maintain.sh restore-drill`. This downloads the newest off-site backup (or uses the newest local one if no off-site), recreates the scratch DB, and restores into it.
3. When finished, read `workdir-phase3/reports/latest-restore-drill.json`. Tell me:
   - Which backup was used (source + path)
   - Observed row counts vs. configured minimums
   - Status (ok / failed)
4. If status is `failed`, show me the note and recommend what to check (stale RESTORE_MIN_* values? recent DB shrinkage?).

This is the canary test for disaster recovery. If it fails, our backup strategy is broken; do not let me deploy new code until it's fixed.
