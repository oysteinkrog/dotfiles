# Cross-Phase Intake Contract

Phase 1 should emit a machine-readable `handoff.json` that Phase 2 can verify without guesswork.

## Required Keys

```json
{
  "schema_version": 1,
  "generated_at": "2026-04-15T00:00:00+00:00",
  "workspace": "acme-slack",
  "plan_tier": "Business+",
  "export_basis": "official-export-plus-enrichment",
  "final_package": {
    "path": "artifacts/import-ready/mattermost-bulk-import.zip",
    "sha256": "..."
  },
  "jsonl_path": "artifacts/import-ready/mattermost_import.jsonl",
  "manifests": [
    "artifacts/raw/manifest.raw.json",
    "artifacts/enriched/manifest.enriched.json",
    "artifacts/import-ready/manifest.import-ready.json"
  ],
  "counts": {
    "users": 0,
    "channels": 0,
    "posts": 0,
    "direct_channels": 0,
    "direct_posts": 0,
    "emoji": 0,
    "attachments": 0
  },
  "sidecar_channels": [
    "slack-canvases-archive",
    "slack-lists-archive",
    "slack-export-admin"
  ],
  "known_gaps": []
}
```

## Quality Bar

- `final_package.sha256` must be present
- `counts.users` and `counts.channels` must be > 0 for non-empty migrations
- manifests must exist on disk
- sidecar channels must be named if sidecars exist
- known gaps must be explicit, not implied
