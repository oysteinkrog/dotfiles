# migrate.sh Command Reference

`./migrate.sh` is the Phase 1 executable spine. It prepares the workspace, acquires or ingests Slack exports, enriches them, transforms them with `mmetl`, packages the final import bundle, runs validators, and emits the handoff contract for Phase 2.

## Commands

| Command | Description | Prereqs |
|---------|-------------|---------|
| `setup` | Prepare `workdir/artifacts/` and verify local dependencies | None |
| `export` | Ingest official export artifacts or run slackdump into the raw stage | `config.env` |
| `enrich` | Run email/file enrichment, emoji export, and sidecar/workflow collection | `export` |
| `transform` | Convert the chosen Slack ZIP into `mattermost_import.jsonl` | `enrich` or `export` |
| `package` | Assemble `mattermost-bulk-import.zip` plus the import-ready manifest | `transform` |
| `verify` | Run validators, reconciliation, evidence pack, and secret scan | `package` |
| `handoff` | Generate `handoff.md`, `handoff.json`, `verification.md`, and `unresolved-gaps.md` | `verify` |
| `all` | Full pipeline: `setup > export > enrich > transform > package > verify > handoff` | `config.env` |
| `split-import` | Split the final import ZIP into yearly batch ZIPs | `package` |

## Typical Workflows

### Full Auto (Default)
```bash
cp config.env.example config.env
# Edit config.env with your values
./migrate.sh all
```

### Official Export Strategy
```bash
./migrate.sh setup
# Download ZIP from Slack admin panel and set SLACK_EXPORT_ZIP/SLACK_CHANNEL_AUDIT_CSV
./migrate.sh export
./migrate.sh enrich
./migrate.sh transform
./migrate.sh package
./migrate.sh verify
./migrate.sh handoff
```

### Step-by-Step
```bash
./migrate.sh setup
./migrate.sh export       # Interactive auth
./migrate.sh enrich
./migrate.sh transform
./migrate.sh package
./migrate.sh verify
./migrate.sh handoff
```

## setup

Creates `workdir/artifacts/` and verifies the local toolchain needed by the Phase 1 scripts:

- `python3`
- `zip`
- optional helpers such as `jq`, `unzip`, `slackdump`, `slack-advanced-exporter`, and `mmetl`

`setup` no longer claims to install tools automatically. It is a deterministic prerequisite check plus workspace bootstrap.

## export

Uses either official-export intake or slackdump to populate the raw artifact stage.

**Behavior:**
- If `SLACK_EXPORT_ZIP` is set, `export` copies the authoritative ZIP and optional audit/member CSVs into `artifacts/raw/` and hashes them immediately.
- Otherwise it calls `scripts/run-slackdump-export.sh` to export into `artifacts/raw/` and packages the result as `slack-export.zip`.
- Shows interactive auth prompt when slackdump needs it.

**Output structure:**
```
slack_export.zip
├── __uploads/          # File attachments (if -files flag)
├── channels.json
├── users.json
├── #channel-name/
│   ├── 2024-01-15.json
│   └── 2024-01-16.json
└── ...
```

## enrich

Runs the real enrichment helpers:

1. `scripts/run-slack-advanced-exporter.sh fetch-emails`
2. `scripts/run-slack-advanced-exporter.sh fetch-attachments`
3. `scripts/export-custom-emoji.py`
4. `scripts/extract-phase1-sidecars.py`
5. `scripts/build-artifact-manifest.py` for the enriched stage

If `slack-advanced-exporter` or `SLACK_TOKEN` is missing, `enrich` carries the raw ZIP forward, but the later enrichment validator will surface the resulting gaps.

## transform

Converts Slack export ZIP to Mattermost bulk-import format.

**Input:** `SLACK_EXPORT_ZIP` or `./workdir/slack_export.zip`

**Process:**
1. Validates export structure with `mmetl check`
2. Runs `mmetl transform slack --team TEAM --file ZIP --output JSONL --attachments-dir DIR`
3. Post-transform fixes:
   - Counts messages exceeding 16383 char limit
   - Fixes guest user role inconsistencies (removes `system_user` from guests)
**Stats output:** user count, channel count, and post count come from the JSONL validator in the next stage.

## package

Uses `scripts/package-phase1-import.py` to assemble:

- `mattermost_import.jsonl`
- `data/bulk-export-attachments/`
- `sidecars/`
- `workflows/`
- `emoji/`
- `mattermost-bulk-import.zip`
- `manifest.import-ready.json`

## verify

Runs the Phase 1 validation/report surface:

- `scripts/validate-phase1-artifacts.py`
- `scripts/validate-phase1-jsonl.py`
- `scripts/validate-enrichment-completeness.py`
- `scripts/reconcile-phase1-counts.py`
- `scripts/export-integration-inventory.py`
- `scripts/build-migration-evidence-pack.py`
- `scripts/scan-and-redact-migration-secrets.py`

## handoff

Generates the human and machine outputs that Phase 2 consumes:

- `handoff.md`
- `handoff.json`
- `verification.md`
- `unresolved-gaps.md`

## split-import

For exports > 10 GB:
1. Reads the final `mattermost-bulk-import.zip`
2. Buckets `post` and `direct_post` objects by year
3. Creates per-year ZIPs with only the attachments referenced by that year
4. Carries sidecars/workflows/emoji through every batch

Mattermost's idempotent import still makes repeated or staged imports safe on the Phase 2 side.

## File Structure

```
slack-migration-to-mattermost-phase-1-extraction/
├── migrate.sh
├── config.env.example
├── config.env
└── workdir/
    └── artifacts/
        ├── raw/
        ├── enriched/
        ├── import-ready/
        └── reports/
```
