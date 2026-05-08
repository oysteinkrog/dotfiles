# Phase 1 Scripts

| Script | Inputs | Outputs | Exit Behavior | When To Run |
|--------|--------|---------|---------------|-------------|
| `doctor.sh` | `config.env` + PATH | human text or `--json` health report | nonzero when a required item is missing | at session start, before `migrate.sh`, and via `--require-mcp` after wiring MCP |
| `bootstrap-tools.sh` | host platform, `config.env` | installs missing tooling (system + Go-based) | nonzero on install failure | whenever `doctor.sh` reports required items missing |
| `install-mcp-servers.sh` | `config.env` credentials | Slack + Playwright MCP registered in Claude Code / Codex | nonzero on missing node/npx or unknown `--include` | once per workstation, re-run after rotating tokens |
| `../migrate.sh` | `config.env` + local tools/artifacts | stage outputs under `workdir/artifacts/` | nonzero on missing prerequisites or failed stage | end-to-end orchestration |
| `build-artifact-manifest.py` | stage files | manifest JSON | nonzero on missing file | after each artifact stage |
| `intake-official-export.py` | official ZIP + optional audit/member CSVs | quarantined raw artifacts + raw manifest | nonzero on missing inputs or invalid ZIP | official-export intake |
| `automate-official-export.py` | export page + optional mailbox inputs + output paths | quarantined official export artifacts + provenance | nonzero on trigger, polling, or download failure | live/admin-export automation |
| `serve-official-export-fixture.py` | fixture ZIP/CSV assets + port | local export page with downloadable artifacts | nonzero on missing fixture inputs | official-export rehearsal support |
| `rehearse-official-export.sh` | optional `PHASE1_EXPORT_REHEARSAL_ROOT` | exact-flow official export rehearsal bundle | nonzero on acquisition regression | exact-flow acquisition proof |
| `run-slackdump-export.sh` | slackdump auth/env | export directory + raw ZIP | nonzero on slackdump failure | Pro/Free export path |
| `run-slack-advanced-exporter.sh` | input ZIP + Slack token | enriched ZIP | nonzero on exporter or token failure | email/file enrichment |
| `export-custom-emoji.py` | Slack token | emoji assets + manifest + alias map | nonzero on API/download failure | emoji preservation |
| `extract-phase1-sidecars.py` | raw archive + operator-supplied sidecar/workflow paths | sidecar/workflow bundle + metadata | nonzero on missing inputs | canvas/list/workflow/admin preservation |
| `patch-phase1-import.py` | JSONL + sidecar/emoji/attachment inputs | patched JSONL + summary JSON | nonzero on malformed JSONL or patch failure | native import augmentation before packaging |
| `package-phase1-import.py` | JSONL + attachments + sidecars/workflows/emoji dirs | final ZIP + import-ready manifest | nonzero on missing inputs | package final import bundle |
| `validate-phase1-artifacts.py` | artifact root | stdout + optional errors | nonzero on missing hashes/layout | before handoff |
| `validate-phase1-jsonl.py` | `mattermost_import.jsonl` | semantic summary JSON | nonzero on semantic breakage | after transform/patch |
| `validate-enrichment-completeness.py` | enriched export ZIP | gap report JSON | nonzero on invalid archive / required upload failures | after enrichment |
| `reconcile-phase1-counts.py` | raw ZIP, enriched ZIP, JSONL, optional audit CSV | reconciliation JSON | zero with warnings unless inputs missing | before handoff |
| `export-integration-inventory.py` | Slack export ZIP | integration inventory JSON/MD | nonzero on missing archive | before manual rebuild planning |
| `generate-phase1-verification.py` | validator JSON reports + handoff JSON | `verification.md` | nonzero on missing inputs | after validators + handoff |
| `generate-unresolved-gaps.py` | handoff + validator JSON reports | `unresolved-gaps.md` | nonzero on missing inputs | before Phase 2 handoff |
| `generate-phase1-handoff.py` | final ZIP, JSONL, manifests | `handoff.md` + optional `handoff.json` | nonzero on missing inputs / unknown hash unless overridden | final step of Phase 1 |
| `split-phase1-import.py` | final bulk-import ZIP | per-year batch ZIPs + split report | nonzero on invalid bundle or absent year data | large-workspace batching |
| `build-migration-evidence-pack.py` | approved files/directories | evidence pack JSON | nonzero on missing path | after validation |
| `scan-and-redact-migration-secrets.py` | logs/configs/notes | findings JSON + optional redacted copies | nonzero if findings are detected | before sharing evidence externally |
