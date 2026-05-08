Use the Phase 2 skill to run the `restore` (backup restore drill) stage.

Not strictly blocking, but the readiness gate will flag an unproven backup path. If you haven't done this at least once, do it now.

1. Make sure `BACKUP_PATH` points at an actual pg_dump file and `SCRATCH_DB_URL` points at a separate DB you can safely overwrite.
2. Run `./operate.sh restore`. This runs `pg_restore` into the scratch DB.
3. After: confirm the scratch DB has the expected tables and row counts roughly match production. Drop the scratch DB when done.

"Untested backup" = "wishful thinking". Do not skip this.
