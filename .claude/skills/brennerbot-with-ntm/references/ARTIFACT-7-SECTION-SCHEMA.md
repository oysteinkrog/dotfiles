# ARTIFACT-7-SECTION-SCHEMA.md — The Canonical 7-Section Research Artifact

<!-- TOC: Why a unified artifact | The 7 sections | Per-section content + ID conventions | Section interactions | Validation checks | When to compile to 7-section form | The artifact lifecycle | Composition with brennerbot beads | Anti-patterns | Cross-references -->

Beyond per-bead deliverables (HANDBACK.md, DECISION-MEMO.md, etc.), the brenner_bot project standardizes a **canonical 7-section artifact** that compiles a session's full state into one Markdown file. This is the format that makes sessions *replayable* and *cross-comparable* — every brennerbot session can produce one.

Mined from `/dp/brenner_bot/specs/artifact_schema_v0.1.md` and `/dp/brenner_bot/specs/artifact_linter_spec_v0.1.md`.

---

## Why a unified artifact

Per-bead state lives in the Beads store (`.beads/beads.db` plus the `.beads/issues.jsonl` export) — machine-readable but not human-readable. Per-deliverable artifacts (HANDBACK, DECISION-MEMO, THREAT-CATALOG, INCIDENT-VERDICT) are scope-specific. The 7-section artifact is the **session's full state in one document**:

- For human review: one file to read, no jumping between beads + distillations
- For cross-session diffing: structurally identical across all sessions
- For machine processing: schema-validated for downstream automation
- For replay: reconstructs the session's reasoning trail

For T3+ sessions, generating this artifact at Phase 8 freeze is recommended; for T4+, mandatory.

---

## The 7 sections

Every artifact has exactly these sections, in this order:

```
## 1. Research Thread
## 2. Hypothesis Slate
## 3. Predictions Table
## 4. Discriminative Tests
## 5. Assumption Ledger
## 6. Anomaly Register
## 7. Adversarial Critique
```

Plus YAML frontmatter:

```yaml
---
session_id: RS-YYYYMMDD-<slug>
created_at: <ISO>
updated_at: <ISO>
status: draft | active | closed
contributors: [<name>, ...]
version: 1
---
```

---

## Per-section content + ID conventions

### Section 1: Research Thread

**Purpose:** the question being investigated, why now, what's the stake.

```markdown
## 1. Research Thread

**RT**: <one-line problem statement>

**Context**: <2-3 paragraph framing — what triggered this; what's at stake; what's in/out of scope>

**Question of record (verbatim from intake/question_of_record.md)**:
> <falsifiable question with explicit Falsifier section>
```

**ID:** `RT` (singleton; no number).

**Linter rules:** `ER-001` RT statement present; `ER-002` Context section present.

### Section 2: Hypothesis Slate

**Purpose:** all current hypotheses with state + falsifier.

```markdown
## 2. Hypothesis Slate

| ID | State | Confidence | Origin | Claim | Falsifier |
|----|-------|------------|--------|-------|-----------|
| H1 | active | medium | proposer-cc | <one-line> | <observable> |
| H2 | active | medium | proposer-cod | <one-line> | <observable> |
| H3 | refuted | low | third_alternative | <one-line> | <observable> |
| ... | ... | ... | ... | ... | ... |
```

**IDs:** `H1`, `H2`, ... (sequential integers, no leading zeros to keep parsing simple).

**Linter rules:** `EH-001` ≥3 hypotheses; `EH-002` ≥1 with `origin: third_alternative`; `EH-003` every H has non-empty Falsifier; `EH-004` no duplicate H IDs.

**Maps to brennerbot beads:** each row corresponds to an `H-NNN` bead (`label: hypothesis`). The artifact is a *materialized view* of the bead state.

### Section 3: Predictions Table

**Purpose:** specific observable predictions per hypothesis.

```markdown
## 3. Predictions Table

| ID | H ref | Prediction | Confidence | Validated? |
|----|-------|------------|------------|------------|
| P1.H1 | H1 | <observable + threshold> | high | yes (EV-014) |
| P2.H1 | H1 | <observable> | medium | pending |
| P1.H2 | H2 | <observable> | low | refuted (EV-019) |
```

**IDs:** `P<seq>.H<H_id>` (e.g., `P1.H1`, `P2.H1`).

**Linter rules:** `EP-001` every active H has ≥1 prediction; `EP-002` predictions cite specific observable.

**Maps to brennerbot beads:** `expected_evidence` field on H beads compiles into this table.

### Section 4: Discriminative Tests

**Purpose:** designed tests that would distinguish between hypotheses.

```markdown
## 4. Discriminative Tests

### T1 — <one-line test name>

**Distinguishes between**: H1, H2, H3
**Procedure**: <specific steps>
**Expected output**:
- If H1: <observable>
- If H2: <observable>
- If H3: <observable>
**Cost**: <time/$/effort>
**KL divergence (estimated)**: high | medium | low
**Status**: planned | running | complete
**Result**: <if complete: which H survived>

### T2 — ...
```

**IDs:** `T1`, `T2`, ... (sequential).

**Linter rules:** `ET-001` every T has expected outputs per H; `ET-002` cost estimate present; `WT-001` KL divergence estimate.

**Maps to brennerbot beads:** `T-NNN` beads (`label: test`).

### Section 5: Assumption Ledger

**Purpose:** load-bearing assumptions made during the session.

```markdown
## 5. Assumption Ledger

| ID | Assumption | Type | Falsifier | Verified? |
|----|------------|------|-----------|-----------|
| A1 | <load-bearing claim> | scale_physics | <calculation that confirms/refutes> | yes (calc in evidence/A1-calc.md) |
| A2 | <claim> | dont_worry | <test that would refute> | no (deferred) |
| A3 | <claim> | corpus_authority | <re-verification cadence> | yes (last 2026-05-12) |
```

**IDs:** `A1`, `A2`, ...

**Types:** `scale_physics` | `dont_worry` | `corpus_authority` | `regulatory` | `domain_axiom`

**Linter rules:** `EA-001` every A has type; `EA-002` every `scale_physics` has explicit calculation; `WA-001` every `dont_worry` has falsifier.

**Maps to brennerbot beads:** `A-NNN` beads (`label: assumption`).

### Section 6: Anomaly Register

**Purpose:** observations that don't fit any current hypothesis.

```markdown
## 6. Anomaly Register

### X1 — <one-line>

**Observation**: <verbatim or specific>
**Why it's anomalous**: doesn't fit H1, H2, or H3
**Quarantine status**: quarantined (per ΔE) | promoted to H<n> (origin: anomaly_spawned)
**Cluster**: 2 other anomalies share <feature> (X3, X5)
```

**IDs:** `X1`, `X2`, ...

**Linter rules:** `EX-001` quarantine status present; `WX-001` cluster check (≥2 anomalies sharing a feature → promote consideration).

**Maps to brennerbot beads:** `AN-NNN` beads.

### Section 7: Adversarial Critique

**Purpose:** the strongest case against the session's current direction.

```markdown
## 7. Adversarial Critique

### C1 — <one-line attack>

**Target**: <H, T, A, or section>
**Attack**: <specific argument>
**Evidence**: <citation>
**Severity**: critical | serious | moderate | minor
**Status**: open | addressed | dismissed (with reason)
```

**IDs:** `C1`, `C2`, ...

**Linter rules:** `EC-001` every C has severity tag; `EC-002` every C cites specific evidence; `WC-001` ≥1 critical-severity C if confidence:high on any H.

**Maps to brennerbot beads:** `C-NNN` beads (`label: critique`).

---

## Section interactions

The 7 sections are interlocked:

- **RT (1)** sets context for everything below
- **Hypothesis Slate (2)** lists Hs; each must have a Falsifier (rule EH-003)
- **Predictions (3)** materializes Hs (rule EP-001: every active H has ≥1 prediction)
- **Tests (4)** discriminate between Hs (rule ET-001: expected outputs per H)
- **Assumptions (5)** track load-bearing claims (rule EA-002: scale_physics has calc)
- **Anomalies (6)** track non-fitting observations (rule EX-001: quarantine status)
- **Critique (7)** attacks the artifact (rule WC-001: ≥1 critical if any high-confidence H)

If you change one section, audit downstream sections for consistency. The linter (per ARTIFACT-LINTER-RULES.md) catches structural drift.

---

## Validation checks

Run `scripts/lint-artifact.sh <artifact-path>` (Tier-7 if added) to validate:

1. YAML frontmatter present + required fields
2. All 7 sections present in order
3. ID conventions followed (RT singleton; H1, H2, ... sequential; etc.)
4. Per-section structural rules (per ARTIFACT-LINTER-RULES.md)
5. Cross-section consistency (per Section interactions above)

A failed lint blocks Phase 8 freeze (per F-703 + Pillar 1 of BRENNERBOT-DOCTOR-RUBRIC.md).

---

## When to compile to 7-section form

### Mandatory at Phase 8 (T4+)

For high-stakes sessions, the 7-section artifact is the canonical handoff to external reviewers (per MO-pre-publication-review.md).

### Recommended at Phase 8 (T3)

For strategic-tier sessions, generating the artifact provides a single-file replay artifact that's easier to share than a workspace tree.

### Optional (T1-T2)

For curiosity/decision-supporting tier, the per-bead state may suffice. HANDBACK.md is the primary deliverable.

### Mandatory at cross-session reconciliation

When reconciling two prior sessions per RECONCILIATION-OF-PRIOR-SESSIONS.md, both should be compiled to 7-section form before comparison. Structurally-identical artifacts diff cleanly.

---

## The artifact lifecycle

1. **Draft (Phase 4-7):** sections are populated as beads are filed; updates are cheap
2. **Active (during freeze):** locked structure; only addressing audit findings
3. **Closed (post-freeze):** snapshot; future changes require a new artifact version

Per `version` field in YAML frontmatter: increment on substantive changes after `closed`. Cross-session reconciliation tracks artifact versions.

---

## Composition with brennerbot beads

The 7-section artifact is a *projection* of the bead ledger. Render it:

```bash
./scripts/render-artifact.sh --workspace=. --out=deliverables/ARTIFACT.md
```

This script (per existing scripts/) walks the .beads/ directory and assembles the 7 sections per the schema. The render is deterministic — same beads → same artifact.

Edits go through beads:
- Add a hypothesis → `br create ... --labels=hypothesis`
- Mark refuted → resolve `H-NNN` to the actual br ID, then `br update "$h_id" --description=... state: refuted`
- Re-render artifact

Don't edit ARTIFACT.md directly; per AGENTS.md "no script-based code changes" applies — but ARTIFACT.md is *generated*, so direct edits will get overwritten on re-render.

---

## Delta operations (ADD / EDIT / KILL)

Per `/dp/brenner_bot/specs/artifact_delta_spec_v0.1.md`, operations on the artifact follow ADD / EDIT / KILL semantics:

```yaml
# Delta JSON (per pane dispatch output):
[
  {"op": "ADD", "section": "hypothesis_slate", "id": "H4", "claim": "...", "falsifier": "..."},
  {"op": "EDIT", "section": "hypothesis_slate", "id": "H1", "field": "state", "value": "refuted"},
  {"op": "KILL", "section": "anomaly_register", "id": "X3", "reason": "Promoted to H4 (origin: anomaly_spawned)"}
]
```

Pane dispatches (MOs) emit deltas; the operator (or `scripts/apply-deltas.sh` if added) applies them to the artifact + corresponding beads.

This formalism supports:
- **Concurrent edits** without race (each delta is atomic)
- **Replay** (replaying deltas reconstructs the artifact)
- **Audit trail** (every change has an op + reason)

For brennerbot, this is captured naturally by `br create` / `br update` / `br update --status=closed`. The 7-section artifact is the materialized view.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Edit ARTIFACT.md directly | Generated file; manual edits get overwritten |
| Skip the artifact for T4+ | Loses replay + cross-session diffing capability |
| Add 8th section "Random notes" | Schema is fixed; non-canonical sections break linter and downstream tooling |
| Use prose instead of tables | Linter expects structured tables; prose loses ID parseability |
| Reuse IDs (e.g., two `H1`s) | Linter `ES-004` rejects; cross-references break |
| Skip Predictions Table because "the H mentions the prediction" | Predictions are first-class artifacts; rule EP-001 |
| Critique section says "no critique necessary" | If any high-confidence H, critique is mandatory (rule WC-001) |
| Don't update Adversarial Critique after Phase 5 debate | The strongest critique should always be present |

---

## Cross-references

- [BEADS-SCHEMA.md](BEADS-SCHEMA.md) — bead-level data; the artifact projects these
- [BEADS-WORKFLOW-CHEATSHEET.md](BEADS-WORKFLOW-CHEATSHEET.md) — concrete `br` commands
- [ARTIFACT-LINTER-RULES.md](ARTIFACT-LINTER-RULES.md) — the 50+ machine-checkable rules
- [HANDBACK-VOICE-GUIDE.md](HANDBACK-VOICE-GUIDE.md) — HANDBACK is a *summary* of the 7-section artifact
- [DISCRIMINATIVE-TEST-DESIGN.md](DISCRIMINATIVE-TEST-DESIGN.md) — formal design of Section 4 tests
- [scripts/render-artifact.sh](../scripts/render-artifact.sh) — the renderer
- /dp/brenner_bot/specs/artifact_schema_v0.1.md — original schema specification
- /dp/brenner_bot/specs/artifact_delta_spec_v0.1.md — ADD/EDIT/KILL operation spec
- /dp/brenner_bot/specs/artifact_linter_spec_v0.1.md — full linter rule catalog
