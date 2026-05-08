# Phase 1 Operator Library

Operators are the atomic cognitive moves that drive Phase 1. Each card is a
self-contained prompt module that an agent can invoke without re-deriving the
reasoning. The summary table in `SKILL.md` is the index; this file holds the
full cards with triggers, failure modes, and copy-paste prompts.

Operators compose. A typical Phase 1 pipeline runs:

```
🎯 TIER  →  📜 AUTH  →  🗺 SCOPE  →  🧪 ENRICH  →  ⚙ XFORM  →  🔎 VERIFY  →  🪓 SPLIT? →  📦 HANDOFF
```

---

### 🎯 TIER — Plan Tier Assessment

**Definition**: Route the migration into the correct branch based on the
Slack plan tier (Free, Pro, Business+, Enterprise Grid).

**When-to-Use Triggers**:
- At session start, before any tool installation.
- When `SLACK_PLAN_TIER` is unset or contradicts what the admin UI shows.
- When "we thought this was Business+ but got a public-only export" surprises arise.

**Failure Modes**:
- Wrong tier chosen → missing DMs / private channels silently.
- Assumed Business+ without confirming the export approval state → export never triggers.
- Pro plan treated as free → slackdump unauthorized paths wasted.

**Prompt Module**:
```text
[OPERATOR: 🎯 TIER]
1) Inspect Slack Admin > Workspace settings > Security > Import & export data.
2) Record the plan tier visible on that page AND any granted export privileges.
3) Choose the branch:
   - Free / Pro         → Track B (slackdump primary, gap report mandatory)
   - Business+ / Grid   → Track A (official export primary, slackdump supplement)
   - Grid               → optionally Track C (workspace split) if per-workspace is preferred
4) Write `SLACK_PLAN_TIER` + branch into config.env.
5) Emit a one-line handoff sentence: "plan tier X, strategy Y, with gaps Z".
```

**Anchors**: [START-HERE.md](START-HERE.md), [EXPORT-STRATEGIES.md](EXPORT-STRATEGIES.md), source doc §"Exporting Everything from Slack".

---

### 📜 AUTH — Token Acquisition

**Definition**: Obtain the right Slack credential for each enrichment /
extraction step without leaking it.

**When-to-Use Triggers**:
- Before any `slackdump`, `slack-advanced-exporter`, `export-custom-emoji.py`, or Slack MCP call.
- When an API call returns 401 / 403 / `not_authed`.
- When rotating credentials during a baseline+delta cadence.

**Failure Modes**:
- Mixing token families: using `xoxc-` where `xoxp-` is required, or vice versa.
- Logging the token to a terminal scrollback that later ships to the evidence pack.
- Leaving `config.env` tracked by git.

**Prompt Module**:
```text
[OPERATOR: 📜 AUTH]
1) Decide which flow needs what:
   - slackdump stealth mode     : xoxc- + xoxd- cookie
   - slack-advanced-exporter    : xoxp- user token with file/email scopes
   - Custom emoji export        : xoxp- user token with emoji:read
   - Anthropic Slack MCP server : xoxb- bot token + SLACK_TEAM_ID
2) For each token, set it in config.env (never echo to stdout).
3) Confirm config.env is in .gitignore and `scripts/scan-and-redact-migration-secrets.py` returns clean.
4) Run a no-op call (`mmctl --help`, `slackdump auth test`) to verify shape.
5) Emit: "auth ready for {slackdump, enricher, emoji, mcp}".
```

**Anchors**: [AUTHENTICATION.md](AUTHENTICATION.md), [SLACK-MCP-SETUP.md](SLACK-MCP-SETUP.md), [playbooks/TOKEN-HANDLING.md](playbooks/TOKEN-HANDLING.md).

---

### 🗺 SCOPE — Export Scope Decision

**Definition**: Decide *what* gets extracted and what is explicitly excluded
*before* spending hours of export time.

**When-to-Use Triggers**:
- After TIER, before the first export call.
- When disk / time budgets are finite (almost always).
- When legal has restricted certain channels / DMs from being exported.

**Failure Modes**:
- Over-export: months of data you don't need; blows through disk budget.
- Under-export: a silently missing year that only surfaces on import-day verification.
- Skipped sidecars: canvases / lists / integration logs discarded because they "don't fit".

**Prompt Module**:
```text
[OPERATOR: 🗺 SCOPE]
1) Identify the date range; default to "full history since workspace creation".
2) For each of {public, private, DMs, group DMs, canvases, lists, workflows,
   custom emoji, integration logs, admin audit} mark include/sidecar/exclude.
3) For "exclude", require a named stakeholder (legal, owner) and log that
   decision under `PHASE1_KNOWN_GAPS` in config.env with classification:
   native-importable | sidecar-only | manual-rebuild | unrecoverable.
4) Confirm 3x the raw-size disk budget is available (doctor.sh reports).
5) Emit: "scope locked; gaps={...}".
```

**Anchors**: [CUTOVER-STRATEGY.md](CUTOVER-STRATEGY.md), [playbooks/GAP-DISPOSITION-TAXONOMY.md](playbooks/GAP-DISPOSITION-TAXONOMY.md), [specs/ARTIFACT-CONTRACT.md](specs/ARTIFACT-CONTRACT.md).

---

### 🧪 ENRICH — Enrichment Gate

**Definition**: Convert the official export (which contains links, not files)
into a self-contained archive with emails + attachments + emoji + sidecars.

**When-to-Use Triggers**:
- After a raw ZIP is hashed into `artifacts/raw/`.
- Before any `mmetl transform` call.
- Any time the `validate-enrichment-completeness.py` report shows unresolved gaps.

**Failure Modes**:
- Skipping enrichment → dead file URLs post-cutover; users see broken links.
- Enriching in the wrong order (attachments before emails forces a second rewrite).
- Mutating the original ZIP in place → loses auditability.

**Prompt Module**:
```text
[OPERATOR: 🧪 ENRICH]
1) Copy the raw ZIP's hash-stamped name into `artifacts/enriched/`.
2) Run, in order:
   - scripts/run-slack-advanced-exporter.sh fetch-emails
   - scripts/run-slack-advanced-exporter.sh fetch-attachments
   - scripts/export-custom-emoji.py
   - scripts/extract-phase1-sidecars.py
3) Invoke `scripts/validate-enrichment-completeness.py` and read the JSON:
   - attachments_missing == 0  → continue
   - emails_unresolved > 0     → decide: is each an ex-employee? Record in gaps.
4) Rewrite `artifacts/enriched/manifest.enriched.json` via build-artifact-manifest.py.
5) Emit: "enrichment ready; residual gaps={...}".
```

**Anchors**: [ENRICHMENT-PIPELINE.md](ENRICHMENT-PIPELINE.md), [cookbooks/SLACK-ADVANCED-EXPORTER-COOKBOOK.md](cookbooks/SLACK-ADVANCED-EXPORTER-COOKBOOK.md), [diagnostics/ENRICHMENT-DIAGNOSTICS.md](diagnostics/ENRICHMENT-DIAGNOSTICS.md).

---

### ⚙ XFORM — Transform Validation

**Definition**: Turn the enriched Slack ZIP into a Mattermost bulk-import JSONL
plus attachment tree, then patch in emoji, archive channels, and sidecar posts.

**When-to-Use Triggers**:
- After ENRICH reports green.
- When `mmetl` emits non-fatal warnings (Guest role, invalid props, etc.) that need targeted handling.

**Failure Modes**:
- Running `mmetl` on Windows (explicitly unsupported).
- Forgetting `--default-email-domain` for workspaces where slack usernames aren't email-like.
- Omitting `patch-phase1-import.py` — emoji + sidecars never show up in Mattermost.

**Prompt Module**:
```text
[OPERATOR: ⚙ XFORM]
1) Run `mmetl check slack --file <enriched.zip>`; block on exit != 0.
2) Run `mmetl transform slack ...` with --default-email-domain when needed.
3) Run `scripts/patch-phase1-import.py` to inject emoji + archive channels + sidecars.
4) Run `scripts/validate-phase1-jsonl.py`; require:
   - version line first
   - users, channels, posts, direct_channels, direct_posts all present (or justified absent)
   - thread_ts references resolve within the same JSONL
5) Emit: "transform+patch ready; artifacts/import-ready/ populated".
```

**Anchors**: [MMETL-DEEP-DIVE.md](MMETL-DEEP-DIVE.md), [cookbooks/PATCH-AND-PACKAGE-COOKBOOK.md](cookbooks/PATCH-AND-PACKAGE-COOKBOOK.md), [diagnostics/TRANSFORM-DIAGNOSTICS.md](diagnostics/TRANSFORM-DIAGNOSTICS.md).

---

### 🔎 VERIFY — Count Reconciliation

**Definition**: Prove that the final import bundle matches what Slack actually
contains.

**When-to-Use Triggers**:
- After package.
- Before handoff.
- On every delta re-run.

**Failure Modes**:
- "It looks right" without numbers.
- Ignoring channel-audit CSV deltas as "noise".
- Accepting a 10% message-count drop as acceptable because mmetl "probably deduped it".

**Prompt Module**:
```text
[OPERATOR: 🔎 VERIFY]
1) Run `scripts/reconcile-phase1-counts.py` with --raw-archive, --enriched-archive,
   --jsonl, and --channel-audit-csv when available.
2) For every nonzero delta, classify:
   - legitimate (tombstoned channel, bot user filtered) → record rationale
   - suspicious (random 3% posts missing) → block and dig in.
3) Sample 5 random channels: list first and last message timestamps in both
   Slack (via Slack MCP) and the JSONL; confirm identical.
4) Emit: "verification green | blocked(reason)".
```

**Anchors**: [VERIFICATION-COOKBOOK.md](VERIFICATION-COOKBOOK.md), [diagnostics/RECONCILIATION-DIAGNOSTICS.md](diagnostics/RECONCILIATION-DIAGNOSTICS.md).

---

### 🪓 SPLIT — Batch Size Decision

**Definition**: Break an outsized bundle into per-year importable ZIPs so the
import step can fit in RAM and be resumable.

**When-to-Use Triggers**:
- `mattermost-bulk-import.zip` > 5 GiB.
- Phase 2 staging OOMed on first attempt.
- Legal wants year-by-year retention + verification.

**Failure Modes**:
- Splitting at arbitrary byte boundaries (breaks thread continuity).
- Forgetting to re-emit per-batch handoff metadata, making Phase 2 confused about which bundle is canonical.

**Prompt Module**:
```text
[OPERATOR: 🪓 SPLIT]
1) Confirm the unsplit bundle validates (VERIFY green).
2) Run `scripts/split-phase1-import.py` with --input-zip and --output-dir workdir/artifacts/import-ready/batches.
3) For each per-year batch: re-hash, re-manifest, re-verify, re-generate a batch-local handoff.json (path: batches/YYYY/handoff.json).
4) Confirm thread continuity in cross-year threads is preserved (spot check one).
5) Emit: "split ready: N batches, years X..Y".
```

**Anchors**: `scripts/split-phase1-import.py`, [workflows/DELTA-CADENCE-WORKFLOW.md](workflows/DELTA-CADENCE-WORKFLOW.md).

---

### 📦 HANDOFF — Authoritative Handoff to Phase 2

**Definition**: Produce the machine-readable + human-readable handoff that
Phase 2 can validate against without guesswork.

**When-to-Use Triggers**:
- All gates above are green.
- Before Phase 2's `./operate.sh intake` is run.
- When a delta run needs a fresh handoff.json.

**Failure Modes**:
- Missing `final_package.sha256` → Phase 2 refuses intake.
- Known gaps implied rather than spelled out → cutover surprises.
- Pointing Phase 2 at a previous delta's ZIP accidentally.

**Prompt Module**:
```text
[OPERATOR: 📦 HANDOFF]
1) Run `scripts/generate-phase1-handoff.py`; confirm handoff.md + handoff.json both exist.
2) Run `scripts/generate-phase1-verification.py` and `scripts/generate-unresolved-gaps.py`.
3) Run `scripts/build-migration-evidence-pack.py`.
4) Open handoff.json, verify:
   - schema_version, final_package.sha256, counts.users, counts.channels, counts.posts all non-empty.
   - known_gaps array is explicit and each entry has a classification.
5) Print the Phase 2 intake command the operator should run next:
   `cd ../slack-migration-to-mattermost-phase-2-setup-and-import && HANDOFF_JSON=<path> IMPORT_ZIP=<path> ./operate.sh intake`
```

**Anchors**: [specs/HANDOFF-CONTRACT.md](specs/HANDOFF-CONTRACT.md), [specs/CROSS-PHASE-INTAKE-CONTRACT.md](specs/CROSS-PHASE-INTAKE-CONTRACT.md), [DONE-DEFINITION.md](DONE-DEFINITION.md).

---

## Hygiene Operators (apply throughout)

### ΔE — Exception Quarantine

When an enrichment or validator flags an unexpected artifact (an unknown
channel type, a message without `ts`, a file missing `url_private`), do not
paper over it. Quarantine it into a named report line, classify it, and decide
before handoff whether to include, sidecar, or drop it. Never silently continue.

### † — Theory Kill

If a working hypothesis about the export ("this workspace has no DMs",
"emoji aren't used") turns out false, delete it from the handoff notes rather
than updating it in place. A stale explanation in the handoff is worse than
no explanation — Phase 2 will plan around it.

### 🧾 — Provenance

Every artifact that leaves this phase carries a SHA256 + a stage manifest
entry. If something was downloaded by hand (e.g. admin CSV from the Slack UI),
`build-artifact-manifest.py` must be invoked to stamp it before it moves into
`artifacts/raw/`. No unhashed artifact crosses the Phase 2 boundary.
