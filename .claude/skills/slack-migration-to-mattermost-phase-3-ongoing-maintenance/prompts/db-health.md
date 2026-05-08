Run `./maintain.sh db-health` against the Postgres on TARGET_HOST.

1. Kick off the stage; it runs a handful of read-only queries.
2. When done, read `workdir-phase3/reports/latest-db-health.json` and tell me:
   - Total DB size and growth since the last check (compare to the previous report in `workdir-phase3/reports/db-health-*.json`)
   - Top 10 tables by size; flag anything unexpected
   - Connection usage % of max
   - Any lock waits or long-running queries
3. If `overall=red`, explain what's wrong and recommend remediation. For yellow, tell me what to watch.

Don't run remediation actions (VACUUM, reindex) without explicit approval.
