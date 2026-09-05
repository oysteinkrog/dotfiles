---
name: slack-migration-to-mattermost-phase-1-extraction
description: >-
  Extract Slack workspaces into Mattermost import bundles. Use when exporting
  history, DMs, private channels, files, emoji, canvases, or building
  handoff ZIP/JSONL artifacts.
---

# Phase 1: Slack Data Extraction & Transformation

> Extract everything from Slack, enrich it, transform it to Mattermost bulk-import format.
> Phase 2 (`slack-migration-to-mattermost-phase-2-setup-and-import`) handles server provisioning, import, and cutover.

## Do This First

1. Open [START-HERE.md](references/START-HERE.md).
2. Resolve the branch now: official export, slackdump-primary, grid split, or baseline+deltas.
3. Run the legal/compliance gate before export collection starts: [LEGAL-APPROVAL-GATE.md](references/playbooks/LEGAL-APPROVAL-GATE.md).
4. Put raw artifacts into a quarantined, hashed artifact tree before enrichment or transform: [QUARANTINE-AND-EVIDENCE.md](references/playbooks/QUARANTINE-AND-EVIDENCE.md).
5. Do not hand anything to Phase 2 until both `handoff.md` and machine-readable `handoff.json` exist and validation is green.

## Batteries-Included Bootstrap

Phase 1 runs on the operator's Mac, Windows, or Linux workstation (wherever
Slack desktop or a logged-in Slack browser is available). Before touching the
pipeline, bring the workstation up to spec:

```bash
./scripts/doctor.sh              # health check: deps, credentials, disk
./scripts/bootstrap-tools.sh     # install missing CLIs (brew / apt / go)
./scripts/install-mcp-servers.sh # wire Slack + Playwright MCP into Claude / Codex
./scripts/doctor.sh --require-mcp  # confirm MCP servers are registered
```

- [TOOL-BOOTSTRAP.md](references/TOOL-BOOTSTRAP.md) — platform matrix (macOS, Ubuntu/Debian, WSL, Windows PowerShell).
- [SLACK-MCP-SETUP.md](references/SLACK-MCP-SETUP.md) — Slack MCP choices (official Anthropic server vs. korotovsky stealth vs. Composio managed).
- [PLAYWRIGHT-MCP-SETUP.md](references/PLAYWRIGHT-MCP-SETUP.md) — drive the Slack admin export UI from Claude Code / Codex.

Skip only when `doctor.sh` already exits 0. Re-run `bootstrap-tools.sh` after
rotating tokens or moving to a new workstation.

## Operator Library and Quote Bank

Full operator cards (triggers, failure modes, copy-paste prompt modules) for
the seven core Phase 1 moves live in [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md).
The rules those cards cite are anchored back to the source research doc and
vendor docs in [QUOTE-BANK.md](references/QUOTE-BANK.md). Treat the quote bank
as authoritative over ad-hoc reasoning.

## Stop If Missing

- Slack plan tier is unknown
- export approval or policy basis is unresolved
- the authoritative export source is ambiguous
- raw artifacts are not being hashed into manifests
- expected gaps are not being classified

## Canonical Default Path

1. Prefer official export as source of truth whenever the plan tier and approvals allow it.
2. Use `slackdump` only as the primary source when official export scope is too limited, or as a supplement for gap-filling and validation.
3. Enrich before transform. Never rely on Slack file links surviving later.
4. Run all four gates before handoff:
   - `scripts/validate-phase1-artifacts.py`
   - `scripts/validate-phase1-jsonl.py`
   - `scripts/validate-enrichment-completeness.py`
   - `scripts/reconcile-phase1-counts.py`
5. Emit `handoff.md`, `handoff.json`, and the evidence pack before declaring Phase 1 complete.

## Migration Threat Model

- Sensitive assets: Slack session tokens, raw ZIPs, member CSVs, sidecar archives, workflow exports, final import ZIPs.
- Trust boundaries: operator workstation, Slack admin plane, browser/MCP session, artifact tree, downstream staging/production intake.
- Main failure classes: unauthorized export scope, token leakage, stale/wrong ZIP selection, silent file loss, under-documented sidecars, ambiguous handoff authority.
- Secret-handling rules: [TOKEN-HANDLING.md](references/playbooks/TOKEN-HANDLING.md)

## Operator Router

- Slack admin: [OPERATOR-ROUTER.md](references/personas/OPERATOR-ROUTER.md)
- Compliance/security reviewer: [LEGAL-APPROVAL-GATE.md](references/playbooks/LEGAL-APPROVAL-GATE.md)
- Migration lead: [CROSS-PHASE-STATE-MACHINE.md](references/specs/CROSS-PHASE-STATE-MACHINE.md)
- Handoff owner: [HANDOFF-AND-STATUS-KIT.md](references/comms/HANDOFF-AND-STATUS-KIT.md)

## Done Means

Phase 1 is only done when the artifact bundle, semantic validators, gap dispositions, and handoff contract all agree. See [DONE-DEFINITION.md](references/DONE-DEFINITION.md).

## Script Contracts

| Script | Input | Output | Exit Behavior | Run When |
|--------|-------|--------|---------------|----------|
| `./migrate.sh` | `config.env` + local tools/artifacts | stage outputs under `workdir/artifacts/` | fails on missing prerequisites or failed stages | default end-to-end path |
| `scripts/build-artifact-manifest.py` | stage files | manifest JSON | fails on missing file | after each stage |
| `scripts/intake-official-export.py` | official ZIP + optional admin CSVs | quarantined raw artifacts + raw manifest | fails on missing input or bad ZIP | official-export path |
| `scripts/run-slackdump-export.sh` | slackdump auth/env | export directory + raw ZIP | fails on slackdump/export ZIP failure | Pro/Free or supplement path |
| `scripts/run-slack-advanced-exporter.sh` | input ZIP + Slack token | enriched ZIP | fails on exporter/token failure | enrichment |
| `scripts/export-custom-emoji.py` | Slack token | emoji assets + manifest + aliases | fails on API/download failure | emoji preservation |
| `scripts/extract-phase1-sidecars.py` | raw archive + sidecar/workflow paths | sidecar bundle + metadata | fails on missing inputs | sidecar/workflow preservation |
| `scripts/package-phase1-import.py` | JSONL + attachments + sidecars/workflows/emoji | final ZIP + import-ready manifest | fails on missing inputs | package final bundle |
| `scripts/validate-phase1-jsonl.py` | `mattermost_import.jsonl` | semantic summary | fails on ordering/schema/linkage issues | after transform/patch |
| `scripts/validate-enrichment-completeness.py` | enriched ZIP | gap report | fails on invalid archive / required upload failure | after enrichment |
| `scripts/reconcile-phase1-counts.py` | raw ZIP + enriched ZIP + JSONL | reconciliation JSON | warns on unexplained drift | before handoff |
| `scripts/generate-phase1-verification.py` | validator JSON + handoff JSON | `verification.md` | fails on missing inputs | after validators + handoff |
| `scripts/generate-unresolved-gaps.py` | handoff + validator JSON | `unresolved-gaps.md` | fails on missing inputs | before Phase 2 handoff |
| `scripts/generate-phase1-handoff.py` | final ZIP + manifests + JSONL | `handoff.md` + `handoff.json` | fails if authoritative hash is missing unless overridden | final step |
| `scripts/split-phase1-import.py` | final bulk-import ZIP | per-year batch ZIPs + split report | fails on invalid bundle or missing year data | large-workspace batching |

## First-Hop References

- [START-HERE.md](references/START-HERE.md)
- [DONE-DEFINITION.md](references/DONE-DEFINITION.md)
- [CROSS-PHASE-INTAKE-CONTRACT.md](references/specs/CROSS-PHASE-INTAKE-CONTRACT.md)
- [CROSS-PHASE-STATE-MACHINE.md](references/specs/CROSS-PHASE-STATE-MACHINE.md)
- [SUBAGENT-CONTRACTS.md](references/SUBAGENT-CONTRACTS.md)

## Default Posture

- **Authoritative source:** the official Slack export ZIP whenever the plan tier permits it.
- **Authoritative enrichers:** `slack-advanced-exporter` first, then targeted custom workers for emoji, attachment hardening, and sidecar preservation.
- **Fallback only:** `slackdump` for Pro/Free, personal/public recovery, gap-filling, or validation against the official export.
- **Never silently drop non-native artifacts:** canvases, lists, audit CSVs, integration logs, and moderation/admin metadata must be preserved as explicit sidecars.
- **Treat artifacts as immutable evidence:** every raw ZIP, enriched ZIP, CSV, and final import package gets a SHA256 hash and manifest entry.
- **Use APIs for enrichment and verification, not as the primary whole-company extractor.**

## Quick Start Tracks

### Track A: Business+ / Enterprise Grid
1. Trigger or download the official Slack export ZIP.
2. Download the channel-audit CSV in the same run.
3. Hash both artifacts and record them in a manifest.
4. Enrich the ZIP with emails, attachments, emoji, and sidecar assets.
5. Transform with `mmetl`, patch the JSONL, package the import ZIP, and verify counts.
6. Hand off the import-ready ZIP plus evidence bundle to Phase 2.

### Track B: Pro / Free
1. Use `slackdump` as the primary extractor because the official export is too limited.
2. Scope expectations aggressively: you only get what the authenticated account can see.
3. Use the same transform, patch, package, and verification flow as Track A.
4. Produce a gap report that makes the blind spots explicit, especially private channels, DMs, and Slack Connect boundaries.

### Track C: Enterprise Grid
1. Prefer workspace-scoped official exports where available.
2. If you receive a Grid-level export, split it with `mmetl grid-transform`.
3. Produce per-workspace manifests, counts, and import packages.
4. Keep org-level audit artifacts separate from workspace import assets.

### Track D: Baseline + Deltas
1. Build a baseline full export.
2. Use recurring scheduled exports as deltas when Business+ approval exists.
3. Re-run enrichment, transform, patch, and verification for each delta.
4. Use idempotent imports to keep staging warm until final cutover.

## Phase 1 Deliverables

Phase 1 is not "done" when the ZIP exists. It is done only when all of these exist:

- Raw export ZIP and channel-audit CSV, both hashed and immutable.
- Full member-list CSV when available.
- Enriched export ZIP with emails and file binaries resolved.
- Emoji bundle plus alias manifest.
- Sidecar archive bundle for canvases, lists, and admin/audit artifacts.
- Workflow Builder JSON exports for workflows that can be exported, plus notes for workflows that cannot.
- `mattermost_import.jsonl` plus `data/bulk-export-attachments/`.
- Final `mattermost-bulk-import.zip`.
- Verification report with counts, samples, known gaps, and unresolved risks.
- A handoff summary that tells Phase 2 exactly what can be imported, what is preserved as sidecars, and what cannot be recovered.

## Artifact Contract

Use a workspace layout that preserves provenance instead of overwriting intermediate results:

```text
artifacts/
├── raw/
│   ├── slack-export-YYYY-MM-DD.zip
│   ├── channel-audit-YYYY-MM-DD.csv
│   ├── member-list-YYYY-MM-DD.csv
│   └── manifest.raw.json
├── enriched/
│   ├── export-with-emails.zip
│   ├── export-with-files.zip
│   ├── emoji/
│   ├── sidecars/
│   ├── workflows/
│   └── manifest.enriched.json
├── import-ready/
│   ├── mattermost_import.jsonl
│   ├── data/bulk-export-attachments/
│   ├── mattermost-bulk-import.zip
│   └── manifest.import-ready.json
└── reports/
    ├── verification.md
    ├── unresolved-gaps.md
    ├── handoff.md
    ├── handoff.json
    └── evidence-pack.json
```

Use [ARTIFACT-CONTRACT.md](references/specs/ARTIFACT-CONTRACT.md) and [HANDOFF-CONTRACT.md](references/specs/HANDOFF-CONTRACT.md) as the canonical shape.

## Operating Environment

**Phase 1 runs on your local Mac or Windows machine** where you have Slack desktop access, a browser, and Claude Code or Codex. This machine does the extraction, enrichment, and transformation work. The output is a ready-to-import ZIP file that Phase 2 transfers to the target Linux server.

**Phase 2 runs primarily via SSH** from this same local machine, connecting to an Ubuntu Linux VPS/bare-metal server where Mattermost will be deployed.

```
Phase 1 (this skill):                    Phase 2 (separate skill):
┌─────────────────────┐                  ┌──────────────────────────┐
│ Your Mac/Windows    │    SCP/rsync     │ Ubuntu VPS / Bare Metal  │
│ - Slack desktop     │ ─────────────▶   │ - Mattermost server      │
│ - Browser (tokens)  │  import ZIP      │ - PostgreSQL             │
│ - Claude Code/Codex │                  │ - Nginx + Cloudflare     │
│ - slackdump         │                  │ - mmctl import           │
│ - mmetl transform   │                  │ - User activation        │
│ - Slack MCP server  │                  │                          │
└─────────────────────┘                  └──────────────────────────┘
```

## Slack MCP Server (Optional but Powerful)

Connect Claude Code directly to your Slack workspace for interactive exploration, verification, and gap-filling during migration. See [SLACK-MCP-SETUP.md](references/SLACK-MCP-SETUP.md) for full setup.

**Quick setup:**
```bash
# Official Anthropic MCP server (8 tools: list channels, get history, search, etc.)
claude mcp add slack \
  -e SLACK_BOT_TOKEN=xoxb-your-bot-token \
  -e SLACK_TEAM_ID=T0123456789 \
  -- npx -y @modelcontextprotocol/server-slack

# Or: korotovsky/slack-mcp-server (15+ tools, stealth mode, no bot required)
# Uses your xoxc- session token -- sees everything you see in Slack
```

**Migration-relevant MCP tools:** list channels, get channel history, search messages, get thread replies, list users, get user profiles. Useful for verifying export completeness and debugging missing data.

## Decision: Which Export Strategy?

```
What Slack plan are you on?
|
+-- Business+ / Enterprise Grid
|   |
|   +-- STRATEGY A: Official Slack Admin Export (primary)
|   |   + Gets public, private, DMs, group DMs
|   |   + Compliance-friendly, auditable
|   |   - Files are LINKS only (must enrich)
|   |   - Requires admin UI + email flow
|   |
|   +-- Then enrich with slack-advanced-exporter + API
|
+-- Pro plan
|   |
|   +-- STRATEGY B: Slackdump (primary)
|   |   + Gets everything you can access INCLUDING files
|   |   + Outputs Mattermost-compatible format directly
|   |   - Only sees channels/DMs you're a member of
|   |   - May trigger Enterprise security alerts
|   |
|   +-- Official export for public channels as supplement
|
+-- Free plan
    |
    +-- STRATEGY B: Slackdump only
        (official export = public channels only, no files)
```

**For maximum fidelity:** Use Strategy A as authoritative source + enrich with API + Slackdump as fallback gap-filler.

## Pre-Flight Checklist

- [ ] Confirm Slack plan tier (Pro / Business+ / Enterprise)
- [ ] Workspace Owner or Admin access confirmed
- [ ] Disk space: 3x expected export size available
- [ ] System deps: `curl`, `jq`, `zip`, `unzip`, `tar`, `python3`
- [ ] Slack App created with required scopes (see below)
- [ ] Export full member-list CSV for identity reconciliation
- [ ] Export Workflow Builder JSON for supported workflows that matter operationally
- [ ] If Business+: applied for and received all-conversations export approval
- [ ] Decided: include file attachments? (slower but preserves everything)
- [ ] For very large workspaces: decide whether to use `slackdump archive` + `resume` before final export conversion

## Create a Slack App (Required for Enrichment)

1. Go to `api.slack.com/apps` > Create New App > From Scratch
2. Name: "Migration Export", select your workspace
3. OAuth & Permissions > add **User Token Scopes**:

| Scope | Purpose |
|-------|---------|
| `channels:history`, `channels:read` | Public channels |
| `groups:history`, `groups:read` | Private channels |
| `im:history`, `im:read` | DMs |
| `mpim:history`, `mpim:read` | Group DMs |
| `users:read`, `users:read.email` | User profiles + emails |
| `emoji:read` | Custom emoji export |
| `files:read` | File attachment downloads |

4. Install to Workspace > authorize > copy **User OAuth Token** (`xoxp-...`)

## The Pipeline

```
Stage 1: Setup        ./migrate.sh setup
Stage 2: Export       ./migrate.sh export  (or official admin export)
Stage 3: Enrich       ./migrate.sh enrich  (advanced exporter + emoji + sidecars/workflows)
Stage 4: Transform    ./migrate.sh transform  (mmetl: Slack ZIP -> MM JSONL)
Stage 5: Package      ./migrate.sh package  (ZIP + manifest)
Stage 6: Verify       ./migrate.sh verify   (validators + evidence + secret scan)
Stage 7: Handoff      ./migrate.sh handoff  (handoff + verification + gaps)
```

### Stage 1: Prepare Workspace

```bash
./migrate.sh setup   # Creates workdir/artifacts and checks local dependencies
```

`setup` no longer claims to auto-install tooling. It is the repeatable bootstrap/check stage for `python3`, `zip`, `slackdump`, `slack-advanced-exporter`, and `mmetl`.

### Stage 2: Export from Slack

**Strategy A (Official Export):**
1. Slack Admin > Workspace Settings > Security > Import & Export Data > Export
2. Select date range > Start Export
3. Wait for email > download ZIP
4. Download the channel-audit CSV from the same admin area
5. Hash both artifacts immediately and record them in a manifest
6. Set `SLACK_EXPORT_ZIP="/path/to/zip"` in `config.env`

**Strategy B (Slackdump):**
```bash
./migrate.sh export   # Interactive auth via browser (Ez-Login 3000)
```

For headless servers, see [AUTHENTICATION.md](references/AUTHENTICATION.md).
For zero-click admin export automation, see [OFFICIAL-EXPORT-AUTOMATION-WORKFLOW.md](references/workflows/OFFICIAL-EXPORT-AUTOMATION-WORKFLOW.md).
For member CSVs, workflow exports, and admin sidecars, see [ADMIN-SIDECAR-ARTIFACTS.md](references/cookbooks/ADMIN-SIDECAR-ARTIFACTS.md).

### Stage 3: Enrich the Export

Official Slack exports have **links but not files**. Enrich before transform:

```bash
./migrate.sh enrich
# Internally runs:
# - scripts/run-slack-advanced-exporter.sh fetch-emails
# - scripts/run-slack-advanced-exporter.sh fetch-attachments
# - scripts/export-custom-emoji.py
# - scripts/extract-phase1-sidecars.py
```

Also run: custom emoji export, canvas/list preservation, attachment verification.
Details: [ENRICHMENT-PIPELINE.md](references/ENRICHMENT-PIPELINE.md)

**Critical ordering:** fetch emails first, then attachments, then run attachment hardening and sidecar extraction. ZIP archives are inefficient to mutate in place. See [SLACK-ADVANCED-EXPORTER-COOKBOOK.md](references/cookbooks/SLACK-ADVANCED-EXPORTER-COOKBOOK.md).

### Stage 4: Transform

```bash
./migrate.sh transform
# Runs: mmetl check slack --file ZIP
# Then: mmetl transform slack --team TEAM --file ZIP --output mattermost_import.jsonl --attachments-dir data/bulk-export-attachments
```

Key `mmetl` flags: `--default-email-domain`, `--skip-empty-emails`, `--discard-invalid-props`, `--allow-download`.

**Do not stop at raw transform output.** After `mmetl`, patch in:
- custom emoji objects after the version line
- archive channels for canvases, lists, and admin artifacts
- generated posts that attach sidecar HTML/JSON/CSV files

Use [PATCH-AND-PACKAGE-COOKBOOK.md](references/cookbooks/PATCH-AND-PACKAGE-COOKBOOK.md) for the post-transform patch step.

### Stage 5: Package the Bundle

```bash
./migrate.sh package
```

This writes `mattermost-bulk-import.zip`, `manifest.import-ready.json`, and a package summary with sidecars/workflows/emoji carried alongside the native import bundle.

### Stage 6: Validate Output

```bash
./migrate.sh verify
./migrate.sh handoff
```

## Large Workspace Handling

For exports > 10 GB, split into yearly batches:

```bash
./migrate.sh split-import   # Extracts, filters by year, transforms+imports each
```

Mattermost import is **idempotent** -- re-importing the same posts won't create duplicates. Safe to do multiple passes.

**Tips:** 4-6 GB per batch. Start with test import on throwaway instance. NVMe SSDs help.

For recurring exports and staged warm-imports, use [DELTA-CADENCE-WORKFLOW.md](references/workflows/DELTA-CADENCE-WORKFLOW.md).
For Slackdump-heavy large workspaces, prefer `archive`/`resume`/`convert` over repeated raw exports. See [RESUMABLE-ARCHIVE-WORKFLOW.md](references/workflows/RESUMABLE-ARCHIVE-WORKFLOW.md).

## What Gets Migrated vs. What Doesn't

| Data | Official Export | Slackdump | Notes |
|------|:-:|:-:|-------|
| Public channels | yes | yes | |
| Private channels | Biz+ only | your channels | |
| DMs | Biz+ only | your DMs | |
| File attachments | links only | full download | Enrich official with slack-advanced-exporter |
| Threaded replies | yes | yes | |
| Reactions | yes | partial | |
| Custom emoji | no | separate cmd | Use `emoji.list` API |
| User profiles | yes | yes | |
| Canvases | HTML export | no | Preserve as sidecar archives |
| Lists | JSON export | no | Preserve as sidecar archives |
| Bookmarks | no | no | Manual recreation |
| Member directory CSV | separate admin export | no | Preserve as verification/admin sidecar |
| Workflow Builder workflows | separate JSON export | no | Export supported workflows manually; custom steps/triggers/connectors cannot export |
| Workflows | no | no | Must reconfigure |
| App integrations | no | no | Must reconfigure |
| Slack Connect | your msgs only | your msgs only | External org controls theirs |

## Anti-Patterns

| Don't | Do Instead |
|-------|------------|
| Unzip and re-zip official Slack export | Keep original ZIP intact for mmetl |
| Use slackdump as sole source for company migration | Use official export as authoritative; slackdump as supplement |
| Try to extract DMs via API crawler on Pro plan | Upgrade to Business+ for all-conversations export |
| Skip enrichment step for official exports | Always run slack-advanced-exporter for emails + files |
| Import everything at once for large workspaces | Split into yearly batches |
| Rely on Slack file links "for later" | Download files immediately; links expire |
| Ignore `MaxPostSize` setting | Increase to 16383 before import (Slack allows 40k chars) |
| Run mmetl on Windows | Linux or macOS only |

## Config Reference

Copy `config.env.example` to `config.env`. Minimum useful vars:

```bash
WORKSPACE_NAME="acme-slack"
MATTERMOST_TEAM_NAME="my-team"
SLACK_EXPORT_ZIP="/absolute/path/to/slack-export.zip"
SLACK_TOKEN="xoxp-..."
```

Full reference: [CONFIG-REFERENCE.md](references/CONFIG-REFERENCE.md)

## THE EXACT PROMPT

When asked to help migrate from Slack to Mattermost, or to extract Slack data:

```
I need to extract all data from a Slack workspace for migration to Mattermost.

Context:
- Slack plan: [Free / Pro / Business+ / Enterprise Grid]
- Workspace size: [N users, estimated export size]
- Must preserve: [files? DMs? private channels? custom emoji? canvases?]
- Server situation: [headless? local machine? both?]
- Timeline: [when is cutover?]

Run the Phase 1 extraction skill. Follow the pre-flight checklist,
choose the right export strategy, execute enrichment, transform, and validate.
```

## Operators (Cognitive Moves)

These are the key decision points and actions throughout the extraction. Each has triggers (when to invoke) and failure modes (what goes wrong if you skip or botch it).

| Op | Name | Trigger | Failure Mode |
|----|------|---------|-------------|
| `TIER` | Plan Tier Assessment | Start of any migration | Wrong strategy chosen; missing DMs/private channels |
| `AUTH` | Token Acquisition | Before any API/slackdump call | 403 errors, empty exports, wasted hours |
| `SCOPE` | Export Scope Decision | Before export | Over-export (months of processing) or under-export (missing data) |
| `ENRICH` | Enrichment Gate | After official export, before transform | Missing emails = broken user matching; missing files = dead links |
| `XFORM` | Transform Validation | After mmetl, before packaging | Guest role errors, truncated posts, hex channel names |
| `VERIFY` | Count Reconciliation | After packaging, before import | Silent data loss; import looks successful but channels are empty |
| `SPLIT` | Batch Size Decision | When export > 5 GB | OOM on server, stuck imports, disk exhaustion |

## Validation Gates (Non-Negotiable)

These checks MUST pass before proceeding to the next stage. Failing them blocks progress.

| Gate | Check | Pass Criteria |
|------|-------|---------------|
| G1: Pre-flight | System deps + disk space + credentials | All deps present, 3x export space free, valid tokens |
| G2: Export integrity | ZIP not corrupt, expected files present | `mmetl check slack --file` exits 0; users.json + channels.json exist |
| G3: Enrichment completeness | Files downloaded, emails added | File count matches url_private count; user emails > 90% populated |
| G4: Transform sanity | JSONL well-formed, counts reasonable | user/channel/post counts > 0; no nil-pointer panics in mmetl output |
| G5: Package structure | ZIP has correct layout | Contains `mattermost_import.jsonl` + `data/bulk-export-attachments/` |
| G6: Import readiness | `mmctl import validate` passes | Exit code 0; no CRITICAL errors in validation output |

## Risk Tiering (Degrees of Freedom)

| Risk Level | Context | Freedom |
|------------|---------|---------|
| **Critical** (exact commands) | Token handling, export triggering, transform flags | Follow commands verbatim; no improvisation |
| **High** (template with constraints) | Enrichment pipeline, batch sizing, JSONL patching | Adapt to workspace size but preserve ordering |
| **Medium** (guidelines) | Verification sampling, channel selection, emoji curation | Use judgment on what to verify and how deeply |
| **Low** (full autonomy) | Workspace cleanup pre-export, channel renaming, documentation | Creative problem-solving welcome |

## Core Invariants

- Official export beats scraping whenever it is available.
- Channel-audit CSV is a first-class artifact, not an optional extra.
- APIs enrich and verify; they do not replace the export for whole-org history.
- Every phase transition must leave behind a manifest and a verification note.
- If an artifact cannot become native Mattermost data, preserve it as an explicit sidecar.
- Known blind spots must be written down, never inferred away.

## Slack Export ZIP Anatomy

Understanding the raw export structure is essential for debugging and custom enrichment.

```
slack_export.zip
├── channels.json          # Public channel metadata (id, name, members, topic, purpose)
├── groups.json            # Private channel metadata (same schema)
├── dms.json               # DM conversation metadata (id, members)
├── mpims.json             # Group DM metadata (id, members)
├── users.json             # User profiles (id, name, real_name, email, is_bot, is_admin)
├── integration_logs.json  # App/bot activity audit trail
├── #general/              # Per-channel message folders
│   ├── 2024-01-15.json    # Messages for that date
│   └── 2024-01-16.json    # Each contains array of message objects
├── D0ABC1234/             # DM conversations (by channel ID)
│   └── 2024-03-01.json
└── __uploads/             # File attachments (slackdump only; official exports omit this)
    └── F0123456789/
        └── document.pdf
```

**Message object anatomy:** `ts` (Unix timestamp, THE unique ID), `user`, `text`, `type`, `thread_ts` (if reply), `files[]` (with `url_private`), `reactions[]`, `attachments[]`. See [SLACK-EXPORT-FORMAT.md](references/SLACK-EXPORT-FORMAT.md).

## Mattermost JSONL Import Format

The transform produces a JSONL file where object ordering matters:

```
1. {"type":"version","version":1}           # Must be first line
2. {"type":"emoji",...}                      # Custom emoji (before teams)
3. {"type":"team",...}                       # Team definitions
4. {"type":"channel",...}                    # Channel definitions
5. {"type":"user",...}                       # User accounts
6. {"type":"post",...}                       # Messages (with replies, reactions, attachments)
7. {"type":"direct_channel",...}             # DM/group DM definitions
8. {"type":"direct_post",...}               # DM messages
```

See [JSONL-FORMAT-REFERENCE.md](references/JSONL-FORMAT-REFERENCE.md) for complete schemas.

## Clustered References

### Workflow Cluster
| Workflow | File |
|----------|------|
| Official export acquisition + mailbox automation | [OFFICIAL-EXPORT-AUTOMATION-WORKFLOW.md](references/workflows/OFFICIAL-EXPORT-AUTOMATION-WORKFLOW.md) |
| Slackdump fallback / supplement path | [SLACKDUMP-SUPPLEMENT-WORKFLOW.md](references/workflows/SLACKDUMP-SUPPLEMENT-WORKFLOW.md) |
| Baseline + deltas cadence | [DELTA-CADENCE-WORKFLOW.md](references/workflows/DELTA-CADENCE-WORKFLOW.md) |
| Enterprise Grid split workflow | [ENTERPRISE-GRID-WORKSPACE-SPLIT-WORKFLOW.md](references/workflows/ENTERPRISE-GRID-WORKSPACE-SPLIT-WORKFLOW.md) |
| Slackdump archive/resume workflow | [RESUMABLE-ARCHIVE-WORKFLOW.md](references/workflows/RESUMABLE-ARCHIVE-WORKFLOW.md) |

### Cookbook Cluster
| Cookbook | File |
|----------|------|
| `slack-advanced-exporter` exact usage | [SLACK-ADVANCED-EXPORTER-COOKBOOK.md](references/cookbooks/SLACK-ADVANCED-EXPORTER-COOKBOOK.md) |
| Artifact hashing + manifest generation | [ARTIFACT-MANIFEST-COOKBOOK.md](references/cookbooks/ARTIFACT-MANIFEST-COOKBOOK.md) |
| Post-transform patching + packaging | [PATCH-AND-PACKAGE-COOKBOOK.md](references/cookbooks/PATCH-AND-PACKAGE-COOKBOOK.md) |
| Member CSV + workflow JSON + admin sidecars | [ADMIN-SIDECAR-ARTIFACTS.md](references/cookbooks/ADMIN-SIDECAR-ARTIFACTS.md) |

### Diagnostics Cluster
| Diagnostics | File |
|-------------|------|
| Export acquisition failures | [ACQUISITION-DIAGNOSTICS.md](references/diagnostics/ACQUISITION-DIAGNOSTICS.md) |
| Enrichment failures | [ENRICHMENT-DIAGNOSTICS.md](references/diagnostics/ENRICHMENT-DIAGNOSTICS.md) |
| Transform and packaging failures | [TRANSFORM-DIAGNOSTICS.md](references/diagnostics/TRANSFORM-DIAGNOSTICS.md) |
| Count reconciliation + gap reporting | [RECONCILIATION-DIAGNOSTICS.md](references/diagnostics/RECONCILIATION-DIAGNOSTICS.md) |

### Spec Cluster
| Spec | File |
|------|------|
| Artifact tree, naming, and provenance rules | [ARTIFACT-CONTRACT.md](references/specs/ARTIFACT-CONTRACT.md) |
| Phase 1 operating model and tool boundaries | [OPERATING-MODEL.md](references/specs/OPERATING-MODEL.md) |
| Phase 2 handoff contract | [HANDOFF-CONTRACT.md](references/specs/HANDOFF-CONTRACT.md) |
| Machine-readable Phase 1 -> Phase 2 intake contract | [CROSS-PHASE-INTAKE-CONTRACT.md](references/specs/CROSS-PHASE-INTAKE-CONTRACT.md) |
| Shared migration lifecycle state machine | [CROSS-PHASE-STATE-MACHINE.md](references/specs/CROSS-PHASE-STATE-MACHINE.md) |

### Playbook Cluster
| Playbook | File |
|----------|------|
| Legal/compliance export gate | [LEGAL-APPROVAL-GATE.md](references/playbooks/LEGAL-APPROVAL-GATE.md) |
| Quarantine and evidence handling | [QUARANTINE-AND-EVIDENCE.md](references/playbooks/QUARANTINE-AND-EVIDENCE.md) |
| Gap disposition taxonomy | [GAP-DISPOSITION-TAXONOMY.md](references/playbooks/GAP-DISPOSITION-TAXONOMY.md) |
| Secret handling rules | [TOKEN-HANDLING.md](references/playbooks/TOKEN-HANDLING.md) |

### Persona / Comms Cluster
| Topic | File |
|-------|------|
| Operator persona router | [OPERATOR-ROUTER.md](references/personas/OPERATOR-ROUTER.md) |
| Handoff and status templates | [HANDOFF-AND-STATUS-KIT.md](references/comms/HANDOFF-AND-STATUS-KIT.md) |
| Escalation ladder | [ESCALATION-LADDER.md](references/comms/ESCALATION-LADDER.md) |

### Scenario Cluster
| Scenario | File |
|----------|------|
| Enterprise Grid, full-history migration | [ENTERPRISE-GRID-FULL-HISTORY.md](references/scenario-packs/ENTERPRISE-GRID-FULL-HISTORY.md) |
| Pro, file-heavy recovery migration | [PRO-RECOVERY-FILE-HEAVY.md](references/scenario-packs/PRO-RECOVERY-FILE-HEAVY.md) |

## Reference Index

### Core Pipeline
| Topic | File |
|-------|------|
| Export strategy comparison | [EXPORT-STRATEGIES.md](references/EXPORT-STRATEGIES.md) |
| Enrichment pipeline details | [ENRICHMENT-PIPELINE.md](references/ENRICHMENT-PIPELINE.md) |
| Headless server authentication | [AUTHENTICATION.md](references/AUTHENTICATION.md) |
| config.env full reference | [CONFIG-REFERENCE.md](references/CONFIG-REFERENCE.md) |
| migrate.sh command reference | [MIGRATE-SH-REFERENCE.md](references/MIGRATE-SH-REFERENCE.md) |
| Cutover strategy (baseline+deltas) | [CUTOVER-STRATEGY.md](references/CUTOVER-STRATEGY.md) |

### Workflow Runbooks
| Topic | File |
|-------|------|
| Official export automation + artifact capture | [OFFICIAL-EXPORT-AUTOMATION-WORKFLOW.md](references/workflows/OFFICIAL-EXPORT-AUTOMATION-WORKFLOW.md) |
| Slackdump primary/fallback workflow | [SLACKDUMP-SUPPLEMENT-WORKFLOW.md](references/workflows/SLACKDUMP-SUPPLEMENT-WORKFLOW.md) |
| Delta export cadence | [DELTA-CADENCE-WORKFLOW.md](references/workflows/DELTA-CADENCE-WORKFLOW.md) |
| Enterprise Grid split/import-ready workflow | [ENTERPRISE-GRID-WORKSPACE-SPLIT-WORKFLOW.md](references/workflows/ENTERPRISE-GRID-WORKSPACE-SPLIT-WORKFLOW.md) |
| Slackdump archive/resume/import-ready workflow | [RESUMABLE-ARCHIVE-WORKFLOW.md](references/workflows/RESUMABLE-ARCHIVE-WORKFLOW.md) |

### Deep-Dive Cookbooks
| Topic | File |
|-------|------|
| Slack export ZIP format & message schemas | [SLACK-EXPORT-FORMAT.md](references/SLACK-EXPORT-FORMAT.md) |
| Slack API cookbook (endpoints, scopes, rate limits) | [SLACK-API-COOKBOOK.md](references/SLACK-API-COOKBOOK.md) |
| slackdump command cookbook | [SLACKDUMP-COOKBOOK.md](references/SLACKDUMP-COOKBOOK.md) |
| mmetl deep dive (flags, transforms, debugging) | [MMETL-DEEP-DIVE.md](references/MMETL-DEEP-DIVE.md) |
| Mattermost JSONL bulk-import format | [JSONL-FORMAT-REFERENCE.md](references/JSONL-FORMAT-REFERENCE.md) |
| Canvas & list preservation (sidecar pattern) | [CANVAS-LIST-PRESERVATION.md](references/CANVAS-LIST-PRESERVATION.md) |
| slack-advanced-exporter cookbook | [SLACK-ADVANCED-EXPORTER-COOKBOOK.md](references/cookbooks/SLACK-ADVANCED-EXPORTER-COOKBOOK.md) |
| Artifact manifest cookbook | [ARTIFACT-MANIFEST-COOKBOOK.md](references/cookbooks/ARTIFACT-MANIFEST-COOKBOOK.md) |
| Patch and package cookbook | [PATCH-AND-PACKAGE-COOKBOOK.md](references/cookbooks/PATCH-AND-PACKAGE-COOKBOOK.md) |
| Admin sidecar artifacts cookbook | [ADMIN-SIDECAR-ARTIFACTS.md](references/cookbooks/ADMIN-SIDECAR-ARTIFACTS.md) |

### Diagnostics & Verification
| Topic | File |
|-------|------|
| Troubleshooting (all phases) | [TROUBLESHOOTING.md](references/TROUBLESHOOTING.md) |
| Verification cookbook (scripts, sampling, reconciliation) | [VERIFICATION-COOKBOOK.md](references/VERIFICATION-COOKBOOK.md) |
| Diagnostics scripts & health checks | [DIAGNOSTICS.md](references/DIAGNOSTICS.md) |
| Acquisition diagnostics | [ACQUISITION-DIAGNOSTICS.md](references/diagnostics/ACQUISITION-DIAGNOSTICS.md) |
| Enrichment diagnostics | [ENRICHMENT-DIAGNOSTICS.md](references/diagnostics/ENRICHMENT-DIAGNOSTICS.md) |
| Transform diagnostics | [TRANSFORM-DIAGNOSTICS.md](references/diagnostics/TRANSFORM-DIAGNOSTICS.md) |
| Reconciliation diagnostics | [RECONCILIATION-DIAGNOSTICS.md](references/diagnostics/RECONCILIATION-DIAGNOSTICS.md) |

### Context & Planning
| Topic | File |
|-------|------|
| Start-here routing | [START-HERE.md](references/START-HERE.md) |
| Phase 1 done definition | [DONE-DEFINITION.md](references/DONE-DEFINITION.md) |
| Subagent output contracts | [SUBAGENT-CONTRACTS.md](references/SUBAGENT-CONTRACTS.md) |
| Phase 1 threat model | [MIGRATION-THREAT-MODEL.md](references/MIGRATION-THREAT-MODEL.md) |
| Slack MCP server setup for Claude Code | [SLACK-MCP-SETUP.md](references/SLACK-MCP-SETUP.md) |
| Enterprise Grid specifics | [ENTERPRISE-GRID.md](references/ENTERPRISE-GRID.md) |
| Cost analysis (Slack vs self-hosted) | [COST-ANALYSIS.md](references/COST-ANALYSIS.md) |
| Security & compliance | [SECURITY-COMPLIANCE.md](references/SECURITY-COMPLIANCE.md) |
| Browser automation for export acquisition | [BROWSER-AUTOMATION.md](references/BROWSER-AUTOMATION.md) |
| Alternative targets (Zulip, Rocket.Chat) | [ALTERNATIVE-TARGETS.md](references/ALTERNATIVE-TARGETS.md) |
| Artifact and provenance rules | [ARTIFACT-CONTRACT.md](references/specs/ARTIFACT-CONTRACT.md) |
| Operating model | [OPERATING-MODEL.md](references/specs/OPERATING-MODEL.md) |
| Phase 2 handoff | [HANDOFF-CONTRACT.md](references/specs/HANDOFF-CONTRACT.md) |

## Tools

| Tool | Purpose |
|------|---------|
| `./migrate.sh` | Orchestrate the default Phase 1 acquisition -> enrichment -> transform -> package -> verify -> handoff path |
| `scripts/build-artifact-manifest.py` | Hash artifacts and write stage manifests |
| `scripts/intake-official-export.py` | Quarantine official export ZIPs and admin CSVs into the raw artifact tree |
| `scripts/run-slackdump-export.sh` | Export Slack data via slackdump and package it into a raw ZIP |
| `scripts/run-slack-advanced-exporter.sh` | Wrap `slack-advanced-exporter` email/file enrichment subcommands |
| `scripts/export-custom-emoji.py` | Export custom emoji assets plus alias metadata from Slack |
| `scripts/extract-phase1-sidecars.py` | Collect sidecars/workflows from the raw archive and operator-provided exports |
| `scripts/package-phase1-import.py` | Assemble the final import ZIP plus manifest |
| `scripts/validate-phase1-artifacts.py` | Verify hashes, ZIP layout, and JSONL object counts |
| `scripts/validate-phase1-jsonl.py` | Verify JSONL ordering, record types, and cross-link sanity before handoff |
| `scripts/validate-enrichment-completeness.py` | Emit attachment/email/sidecar gap reports from the enriched export |
| `scripts/reconcile-phase1-counts.py` | Compare raw ZIP, enriched ZIP, audit CSV, and JSONL counts |
| `scripts/export-integration-inventory.py` | Extract a concrete integration rebuild backlog from `integration_logs.json` |
| `scripts/generate-phase1-verification.py` | Build `verification.md` from validator outputs plus the handoff contract |
| `scripts/generate-unresolved-gaps.py` | Aggregate unresolved gaps into `unresolved-gaps.md` |
| `scripts/generate-phase1-handoff.py` | Build `handoff.md` plus optional machine-readable `handoff.json` |
| `scripts/split-phase1-import.py` | Split the final import ZIP into per-year batch ZIPs for large workspaces |
| `scripts/build-migration-evidence-pack.py` | Hash approved outputs into an auditable evidence pack |
| `scripts/scan-and-redact-migration-secrets.py` | Detect and optionally redact secrets before sharing evidence outside the core operator set |

*Run scripts directly. They have shebangs and are meant to be executed, not copy-pasted into ad hoc one-offs.*

### Script Inventory

See [scripts/README.md](scripts/README.md) for `input -> output -> exit-code -> when-to-run`.

## Subagents

| Subagent | Purpose |
|----------|---------|
| `subagents/acquisition-auditor.md` | Audit export strategy, source artifacts, and acquisition blind spots |
| `subagents/reconciliation-analyst.md` | Compare manifests, counts, and known gaps before handoff |
| `subagents/compliance-approval-auditor.md` | Block unsafe or unauthorized export flows before acquisition starts |
| `subagents/slack-plan-tier-router.md` | Route the migration into the correct branch for plan tier and scope |
| `subagents/gap-hunter.md` | Hunt for silent losses, missing sidecars, and under-documented gaps |
| `subagents/token-exposure-redteam.md` | Red-team token handling, raw exports, and evidence sharing for secret leakage |

### Subagent Contracts

See [SUBAGENT-CONTRACTS.md](references/SUBAGENT-CONTRACTS.md) for the required `Verdict: ready|blocked|needs-review` schema.

## Assets

| Asset | Purpose |
|-------|---------|
| `assets/fixtures/slack-export-sample/` | Minimal Slack export fixture tree for rehearsal and validator development |
| `assets/goldens/` | Example manifest and JSONL goldens for regression and examples |
| `assets/scenario-packs/` | YAML scenario presets for common migration shapes |
| `assets/templates/lineage-cockpit.html` | Static cockpit template for showing stage-to-stage lineage and evidence |

### Phase 2 Handoff
Phase 1 produces a `mattermost-bulk-import.zip` ready for import plus a machine-readable `handoff.json`. Hand off to `slack-migration-to-mattermost-phase-2-setup-and-import`, which consumes the contract, validates the bundle, rehearses staging, and drives the actual import/cutover path.
