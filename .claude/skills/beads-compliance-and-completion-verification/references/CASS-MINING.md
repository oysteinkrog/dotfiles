# CASS-MINING.md — Mine Prior Sessions For Project-Specific False-Closed Patterns

<!-- TOC: When to mine | Pre-flight | 5 mining queries | Aggregating into patterns.md | Adding patterns to the audit | Output discipline | Handling false positives | Privacy/sensitivity | When NOT helpful -->

`/cass` indexes every prior agent conversation across Claude Code, Codex, Cursor, Gemini, ChatGPT, etc. Before Phase 1 of an audit on a new project (or as part of an Onboarding-mode pass), mine cass for **project-specific patterns** that the generic `FAILURE-MODES.md` catalog won't catch.

> **Why.** Every project develops its own theater conventions. One project might have a recurring "agent X always closes beads in batches of 5 at the end of session." Another might have "agent Y always uses `tokio::time::sleep` to fake async I/O." These are catchable by tightening `rubric.md#project_specific_patterns` *before* Phase 5 runs.

---

## When to mine cass

| Scenario | CASS mining recommendation |
|----------|----------------------------|
| First audit on a new project | **Required**. Mine 6 months of session history. |
| Onboarding mode | **Required**. The whole point is project-specific calibration. |
| Standard re-verification | Skip. Project's rubric.md already has the patterns from the first onboarding pass. |
| Triage mode | Skip. Triage trades depth for speed. |
| When false-closed rate spikes between passes | **Recommended**. A new agent or workflow change may have introduced new theater patterns. |
| When a specific bead's score is inexplicable | **Recommended**. Mine the closer's prior sessions on this project. |

---

## Pre-flight: confirm cass is healthy and indexed

```bash
cass health
# Expected: ✓ Healthy. If "index stale" → cass index --full first.

cass capabilities --json | jq '.search_engines, .indexed_session_count'
```

If cass isn't installed: skip this phase entirely. Record `cass_available: false` in `manifest.json#tools` so future passes know.

---

## Mining queries

Run these searches early in Phase 1 (after `br doctor`, before `br list`). Save raw outputs under `passes/<UTC>/cass_mining/`.

### Query 1: who closes beads in this project?

```bash
cass search "br close" --robot --limit 50 --workspace "$PROJECT_ABS" \
  --fields agent,session_id,timestamp,snippet \
  > passes/<UTC>/cass_mining/closers.json
```

Aggregate by `closed_by_session`: which agent / session has closed the most beads? If a single session closed N>10 beads, audit those N first — likely batch-close pattern.

### Query 2: agent-stated apologies / hedges in close reasons

These patterns appear in close reasons that signal "I closed it but didn't actually finish":

```bash
cass search "closing this for now" --robot --limit 20 --workspace "$PROJECT_ABS" \
  > passes/<UTC>/cass_mining/hedge_closes.json

cass search "haven't fully implemented" --robot --limit 20 --workspace "$PROJECT_ABS" \
  >> passes/<UTC>/cass_mining/hedge_closes.json

cass search "will follow up" --robot --limit 20 --workspace "$PROJECT_ABS" \
  >> passes/<UTC>/cass_mining/hedge_closes.json
```

Beads matching these phrases in `close_reason` are auto-flagged as suspect during Phase 8.

### Query 3: project-specific theater patterns

```bash
# Generic theater
cass search "todo unimplemented panic placeholder" --robot --limit 20 \
  --workspace "$PROJECT_ABS" > passes/<UTC>/cass_mining/theater_phrases.json

# Test theater
cass search "assert true expect true" --robot --limit 20 \
  --workspace "$PROJECT_ABS" >> passes/<UTC>/cass_mining/theater_phrases.json

# "I added a stub for now"
cass search "stub for now" --robot --limit 20 \
  --workspace "$PROJECT_ABS" >> passes/<UTC>/cass_mining/theater_phrases.json
```

### Query 4: prior bead-related conversations

```bash
# Find prior conversations about each closed bead
for ID in $(jq -r 'select(.status == "closed") | .id' passes/<UTC>/inventory.jsonl); do
  cass search "$ID" --robot --limit 5 --workspace "$PROJECT_ABS" \
    > "passes/<UTC>/beads/$ID/cass_history.json" 2>/dev/null || true
done
```

The per-bead cass history is added to `evidence.json#cass_context` and may surface prior agent struggles, abandoned approaches, or "I'll come back to this" markers that indicate the bead wasn't really finished.

### Query 5: methodology drift

If the project uses a specific methodology (e.g., "always use real-DB tests"), mine for sessions where that methodology was abandoned:

```bash
cass search "let me just mock" --robot --limit 10 --workspace "$PROJECT_ABS"
cass search "skip the integration test for now" --robot --limit 10 --workspace "$PROJECT_ABS"
cass search "// TODO: replace with real" --robot --limit 10 --workspace "$PROJECT_ABS"
```

Each match suggests a bead that was closed despite drifting from the project's stated standards.

---

## Aggregating into project-specific patterns

After mining, the orchestrator emits `passes/<UTC>/cass_mining/patterns.md`:

```markdown
# Project-specific false-closed patterns mined from cass

## Pattern 1: batch-close by session <session-id>
Session `2026-04-15-abc123` closed 11 beads in 4 minutes.
Likely pattern: status-flip without verification.
Affected beads: bd-XXX, bd-YYY, ...

## Pattern 2: hedge phrases in close reasons
Found 7 beads with hedge phrases ("for now", "will follow up", "first pass") in
their close_reason. Patterns:
- bd-AAA: "first pass at this; will iterate"
- bd-BBB: "closing for now to unblock CI; real fix coming"
- ...

## Pattern 3: tokio::time::sleep in production paths
Project has 4 instances of `tokio::time::sleep` in src/ (not tests/). The
mining query "tokio sleep production" surfaced an agent commenting "I'll
replace this with real polling later" in session <id>.

## Pattern 4: Drizzle migrations without down() reverse
4 migrations in this project have an empty / no `down()` function. Sessions
showed agents saying "no rollback needed for now."

## Recommended rubric.md additions
project_specific_patterns:
  - name: hedge_close_reason
    severity: MAJOR
    detection: close_reason matches /(for now|will follow up|first pass|coming next)/i
  - name: batch_close
    severity: MAJOR
    detection: closed_by_session has > 5 closes within 5 minutes
  - name: tokio_sleep_in_prod
    severity: BLOCKING
    detection: rg 'tokio::time::sleep' src/ (excluding tests/)
  - name: empty_migration_down
    severity: MAJOR
    detection: migration file exports `up` but no `down`
```

---

## Adding patterns to the audit

The discovered patterns get folded into:

1. **`rubric.md#project_specific_patterns`** — so they apply to every future pass.
2. **`scripts/theater-scan.sh`** — extended to grep for the discovered patterns over evidence files.
3. **`subagents/theater-detector.md`** — instructed to look for the project-specific patterns alongside generic ones.

After the first Onboarding pass, subsequent passes don't need to re-mine cass (the patterns are baked in). Re-mine when:
- A new agent joins the team (their conventions may differ).
- Project conventions change (e.g., a new "no mocks" mandate).
- False-closed rate spikes inexplicably between passes.

---

## Cass output discipline

cass output can be very large (multiple MB). Follow these rules:

1. Always use `--robot` (machine-readable).
2. Always use `--limit N` with explicit N.
3. Use `--fields minimal` for aggregate queries; full fields only for per-bead context.
4. Persist raw outputs under `passes/<UTC>/cass_mining/` for replay.
5. Summarize into `patterns.md` so downstream phases don't re-read the raw data.

---

## Handling false positives from cass

A cass match is **evidence of conversation**, not evidence of theater. The conversation may have been:
- A discarded approach that was later replaced with a real fix.
- A peer-review comment from another agent that the closer addressed.
- Documentation discussing the pattern (legitimately).

Always cross-reference cass findings with current code state. If `tokio::time::sleep` appeared in a session 6 months ago but `git log -p src/x.rs` shows it was removed in a later commit, that's a stale signal — drop it.

The `theater-detector.md` subagent does this cross-check automatically: cass findings are NOT added to `theater.json` unless the matching code is still present on HEAD.

---

## Privacy / sensitivity

cass indexes all sessions, including ones with API keys or sensitive data. Before persisting cass mining outputs into the audit dir, scrub:

```bash
# Strip likely-secret patterns from cass mining outputs.
sed -i.bak -E '
  s/sk-[A-Za-z0-9]{32,}/sk-REDACTED/g
  s/ghp_[A-Za-z0-9]{36}/ghp_REDACTED/g
  s/[A-Za-z0-9]{40}/REDACTED-40CHAR-TOKEN/g
' passes/<UTC>/cass_mining/*.json
rm -f passes/<UTC>/cass_mining/*.json.bak
```

The audit dir is git-tracked; secrets in mining output would land in git. Always scrub before commit.

---

## When cass is NOT helpful

- Project is too new (< 1 month of sessions) — no patterns yet.
- Project changed agents recently (old patterns no longer apply).
- All beads were created/closed via web UI or external system (cass only sees CLI agents).

In those cases, skip the mining step and rely on the generic `FAILURE-MODES.md` catalog. Record in `manifest.json#cass_mining_skipped: true` with reason.
