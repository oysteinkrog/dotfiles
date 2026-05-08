Use the Phase 1 skill to run the `enrich` stage.

1. Run `./migrate.sh enrich`. This downloads every `url_private` attachment, resolves user emails, exports custom emoji, and extracts sidecars (canvases, lists, workflows, audit CSVs).
2. When it finishes, run `scripts/validate-enrichment-completeness.py --archive workdir/artifacts/enriched/slack-export.enriched.zip --output-json /tmp/enrich.json` and read the result.
3. If `missing_file_references` in that JSON is non-empty (the operator cards call this "attachments_missing"), show me the top 10 entries with context and ask whether to accept each as unrecoverable or re-try. Also surface `users_missing_email` if non-empty.
4. Confirm `manifest.enriched.json` has fresh SHA256 entries for the enriched ZIP + emoji manifest + sidecar bundle.

Do NOT proceed to `transform` until `missing_file_references` is empty or every remaining entry has been documented in `unresolved-gaps.md`.
