I've come back to a migration that's already partially run. Figure out where I am and what to do next.

1. Read `config.env` — which Track are we on, what's set.
2. `ls -la workdir/artifacts/{raw,enriched,import-ready,reports}/` — enumerate every artifact and its mtime.
3. Read `workdir/artifacts/reports/*.json` (any that exist) and tell me what the last successful stage was.
4. Based on that, recommend exactly one action: re-run stage X, or proceed to stage X+1, or investigate a specific red report.
5. Warn me about any stage where re-running is NOT safely idempotent for this specific skill (most stages are; flag any that aren't).

Do not run any stage yet. I want a situation report first.
