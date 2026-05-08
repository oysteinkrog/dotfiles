Use the Phase 1 skill to run the `export` stage.

Pick the right path based on `config.env`:

- If `SLACK_EXPORT_ZIP` is set and points to a readable file → Track A (official export intake). Run `./migrate.sh export`. Confirm `workdir/artifacts/raw/manifest.raw.json` has SHA256 entries for the ZIP, channel-audit CSV, and member CSV.
- If `SLACKDUMP_PRIMARY=1` → Track B. Run `./migrate.sh export`. Watch for rate-limit backoff. If this is a headless server without a browser, read `references/AUTHENTICATION.md` for the `xoxc-`/`xoxd-` path.
- If neither is configured → stop and ask me which track to use.

After the stage finishes:
- Show me the size of `workdir/artifacts/raw/slack-export.zip` and predict disk need for enrich (roughly 2–3× the raw size because of fetched attachments).
- Flag any missing inputs in `unresolved-gaps.md` — I want to decide now which ones we accept vs. re-fetch.
