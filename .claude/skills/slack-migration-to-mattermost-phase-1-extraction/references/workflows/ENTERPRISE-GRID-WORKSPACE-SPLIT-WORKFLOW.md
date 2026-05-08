# Enterprise Grid Workspace Split Workflow

Enterprise Grid adds one more decomposition step.

## Preferred Strategy

- prefer workspace-scoped exports when possible
- if given a grid-level export, split it into per-workspace exports before the normal pipeline

## Workflow

1. Acquire the Grid export ZIP and org-level audit artifacts.
2. Run:

```bash
./mmetl grid-transform --file enterprise-grid-export.zip
```

3. Treat each resulting workspace ZIP as its own acquisition unit.
4. Write per-workspace manifests and verification reports.
5. Keep org-level audit artifacts in the admin sidecar bundle.

## Output Model

```text
artifacts/
├── raw/
│   └── enterprise-grid-export.zip
├── workspace-a/
│   ├── raw/
│   ├── enriched/
│   ├── import-ready/
│   └── reports/
└── workspace-b/
    ├── raw/
    ├── enriched/
    ├── import-ready/
    └── reports/
```

## Important Constraints

- do not collapse multiple workspaces into one import package unless the target design explicitly requires it
- keep manifests scoped by workspace
- carry shared org artifacts in a separate admin archive

## Verification

Per workspace:
- channel count
- user count
- attachment count
- sidecar count
- known Slack Connect limits
