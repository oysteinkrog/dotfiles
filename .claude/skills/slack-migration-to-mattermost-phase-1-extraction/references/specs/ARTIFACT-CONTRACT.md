# Artifact Contract

This contract keeps the migration auditable and repeatable.

## Directory Shape

```text
artifacts/
├── raw/
├── enriched/
├── import-ready/
└── reports/
```

Use date-stamped names and never replace a prior artifact silently.

## Naming Convention

```text
raw/slack-export-2026-04-15-full.zip
raw/channel-audit-2026-04-15.csv
enriched/export-with-emails-2026-04-15.zip
enriched/export-with-files-2026-04-15.zip
import-ready/mattermost-import-2026-04-15.jsonl
import-ready/mattermost-bulk-import-2026-04-15.zip
reports/verification-2026-04-15.md
reports/handoff-2026-04-15.md
```

## Required Manifests

Each phase writes a manifest:
- `manifest.raw.json`
- `manifest.enriched.json`
- `manifest.import-ready.json`

## Minimum Manifest Fields

```json
{
  "created_at": "2026-04-15T18:20:00Z",
  "workspace": "acme-slack",
  "plan_tier": "Business+",
  "artifacts": [
    {
      "path": "raw/slack-export-2026-04-15-full.zip",
      "sha256": "abc123...",
      "bytes": 123456789,
      "source": "official-slack-export-ui",
      "notes": "all-conversations export"
    }
  ],
  "known_gaps": [
    "Slack Connect external-org content remains governed by external org retention."
  ]
}
```

## Provenance Rules

- Every artifact gets a SHA256 hash.
- Every manifest says whether the artifact came from official export, API enrichment, `slackdump`, or custom patching.
- Every rewritten ZIP gets a new filename and new hash.
- Reports must reference the manifest they were derived from.

## Sidecar Rules

Sidecar assets must live under `enriched/sidecars/` and later be copied into the import package:
- `canvases/`
- `lists/`
- `admin/`
- `emoji/`

If an artifact is not importable as a native Mattermost object, keep it as a sidecar and note that explicitly in the handoff.
