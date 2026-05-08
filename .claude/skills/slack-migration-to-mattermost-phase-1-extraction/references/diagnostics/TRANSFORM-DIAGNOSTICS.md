# Transform Diagnostics

Use these when `mmetl` or packaging fails.

## `mmetl check slack` Fails

Check:
- raw ZIP is not corrupt
- expected files exist
- official ZIP was not unpacked and re-zipped

## `mmetl transform slack` Panics or Nil-Pointers

Check:
- malformed export JSON
- unsupported edge-case props
- outdated `mmetl` release

Response:
- retry with latest `mmetl`
- use `--discard-invalid-props` if the loss is acceptable and documented
- split large exports into smaller units

## User Role Errors

If guest role combinations are inconsistent:
- patch the JSONL
- document the patch in the manifest/report

## Oversized Messages

Check:
- Mattermost `MaxPostSize`
- whether truncation was merely flagged versus silently applied

## Packaging Errors

If `mmctl import validate` fails:
- inspect ZIP layout
- confirm `mattermost_import.jsonl` is top-level
- confirm attachments are under `data/bulk-export-attachments/`
