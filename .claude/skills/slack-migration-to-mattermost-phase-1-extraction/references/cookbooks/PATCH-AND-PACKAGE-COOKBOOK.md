# Patch and Package Cookbook

`mmetl` gets you close. This step gets you to import-ready.

## Patch Goals

- inject custom emoji objects
- create archive channels for sidecars
- attach canvases, lists, and admin artifacts as generated posts
- preserve provenance for everything not natively representable

## Patch Order

1. keep the version line first
2. insert emoji objects after version
3. keep team/channel/user/post ordering valid
4. add archive channels before posts targeting them
5. attach sidecar files from `data/bulk-export-attachments/`

## Archive Channels

- `slack-canvases-archive`
- `slack-lists-archive`
- `slack-export-admin`

## Packaging Layout

```text
mattermost-bulk-import.zip
├── mattermost_import.jsonl
└── data/
    └── bulk-export-attachments/
```

## Packaging Command

```bash
zip -r artifacts/import-ready/mattermost-bulk-import.zip \
  data mattermost_import.jsonl
```

## Validation

```bash
mmctl import validate artifacts/import-ready/mattermost-bulk-import.zip
```

## Notes

- if you inject sidecar posts, mention them in the handoff report
- if emoji aliases collapse to a single image, preserve the alias mapping in a manifest even if the importer only sees the final file
