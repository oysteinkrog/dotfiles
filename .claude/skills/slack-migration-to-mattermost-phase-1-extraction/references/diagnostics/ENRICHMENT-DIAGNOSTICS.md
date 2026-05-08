# Enrichment Diagnostics

Use these when the raw ZIP exists but the enriched ZIP is incomplete.

## Missing Emails

Check:
- `users:read.email` scope
- workspace policy hiding emails
- bot token used where user token is required

Response:
- retry with proper token
- record unresolved email gaps
- decide whether `--default-email-domain` is safe

## Missing Attachments After Enrichment

Check:
- `files:read` scope
- deleted or inaccessible files
- private file URLs requiring direct authenticated fetch

Response:
- parse remaining `url_private` references
- fetch missing binaries directly
- generate an attachment gap report

## Emoji Export Gaps

Check:
- `emoji:read` scope
- alias chains resolving to missing source emoji
- duplicates or name collisions

Response:
- write alias manifest
- collapse aliases carefully
- preserve unresolved aliases in the report

## Canvas/List Sidecars Missing

Check:
- whether the export tier actually includes them
- whether you searched the ZIP thoroughly
- whether the workspace had any canvases/lists at all

Response:
- if absent, say "not present in source export" rather than "none existed"
