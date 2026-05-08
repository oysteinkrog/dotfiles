Run `./maintain.sh backup`.

1. Kick off the stage. Expect ~5 to 30 minutes of runtime depending on DB size.
2. When done, read `workdir-phase3/reports/latest-backup.json` and summarize:
   - Local path and size of the dump
   - SHA-256 hash
   - Whether off-site upload succeeded and where it landed
   - Whether the hash verified after upload
3. If `verify_status=mismatch` or `offsite_status=failed`, tell me what failed and offer to retry.

The backup is local-only if `OFFSITE_REMOTE` is unset. That's not recommended for production; warn me if I haven't set it.
