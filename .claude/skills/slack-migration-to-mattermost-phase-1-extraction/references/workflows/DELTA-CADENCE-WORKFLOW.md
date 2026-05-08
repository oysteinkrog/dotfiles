# Delta Cadence Workflow

Use this for baseline + recurring delta migrations.

## Cadence Model

```text
baseline full export
    -> enrich
    -> transform
    -> patch/package
    -> verify in staging

recurring deltas
    -> same pipeline
    -> re-import into staging

final cutover delta
    -> same pipeline
    -> production import in Phase 2
```

## Baseline

- entire history when possible
- full verification pass
- establish initial manifests and counts

## Recurring Deltas

- use scheduled exports when Slack tier permits
- use clear date-window naming
- compare counts against prior baseline + deltas
- keep staging warm with repeated idempotent imports

## Final Delta

- freeze Slack to read-only
- run final export for the trailing window
- enrich, transform, patch, verify
- hand off final ZIP and reports to Phase 2

## Naming Convention

```text
slack-export-baseline-2026-04-15.zip
slack-export-delta-2026-04-22.zip
slack-export-delta-2026-04-29.zip
slack-export-final-2026-05-03.zip
```

## Verification Requirements Per Delta

- counts do not unexpectedly shrink
- attachment delta is plausible
- new users match expected email domain rules
- sample threads from the delta window survive transform

## Why This Works

Mattermost import is idempotent for repeated posts, so deltas can overlap slightly without duplicating content.
