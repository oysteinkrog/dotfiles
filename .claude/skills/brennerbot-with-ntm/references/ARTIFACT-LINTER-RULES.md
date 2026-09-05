# ARTIFACT-LINTER-RULES.md — 50+ Machine-Checkable Rules for the 7-Section Artifact

<!-- TOC: Why a linter | Rule format + severity | Section codes | Per-section rule catalog | Citation + provenance rules | Detection patterns | Running the linter | Failure semantics | Anti-patterns | Cross-references -->

The 7-section artifact (per ARTIFACT-7-SECTION-SCHEMA.md) is *machine-checkable*. This file catalogs the 50+ rules a linter applies. Without machine validation, structural drift accumulates silently across sessions; with it, structural integrity holds across operators and tiers.

Mined from `/dp/brenner_bot/specs/artifact_linter_spec_v0.1.md` and adapted to brennerbot's bead-based workflow.

---

## Why a linter

Three concrete benefits:

1. **Cross-session diff stability.** Sessions whose artifacts pass the same linter compare cleanly. Without a linter, structural drift makes diffs noisy.
2. **Onboarding compression.** New operators don't memorize structure rules — `lint-artifact.sh` enforces them (Tier-7 future addition; until then, manual application of the rule catalog below).
3. **Audit-finding generation.** Lint failures *automatically generate* `audit-finding` beads at Phase 7.

For T3+ sessions, lint-clean is required for Phase 8 freeze. For T4+, lint-clean is required for *any* HANDBACK to be considered ready for external review.

---

## Rule format + severity

Each rule has a unique ID:

```
{SEVERITY}{SECTION}-{NUMBER}
```

**Examples:**
- `EH-001` — Error in Hypothesis Slate, rule 1
- `WT-003` — Warning in Discriminative Tests, rule 3
- `IM-002` — Info in Metadata, rule 2

### Severity levels

| Level | Code | Meaning | Behavior |
|-------|------|---------|----------|
| **Error** | `E` | Must fix before artifact is valid | **Blocks Phase 8 freeze** |
| **Warning** | `W` | Should fix, may indicate quality issues | Allows freeze with notice; tracked in OPERATOR-CALIBRATION-LOG.md |
| **Info** | `I` | Style guidance | Informational only; not blocking |

### Section codes

| Code | Section |
|------|---------|
| `M` | Metadata (YAML frontmatter) |
| `S` | Structure (cross-section) |
| `R` | Research Thread |
| `H` | Hypothesis Slate |
| `P` | Predictions Table |
| `T` | Discriminative Tests |
| `A` | Assumption Ledger |
| `X` | Anomaly Register |
| `C` | Adversarial Critique |

---

## Per-section rule catalog

### Metadata (M) — 8 rules

| ID | Severity | Rule |
|----|----------|------|
| `EM-001` | Error | YAML frontmatter present (block delimited by `---`) |
| `EM-002` | Error | `session_id` field present + non-empty |
| `EM-003` | Error | `created_at` present in ISO-8601 format |
| `EM-004` | Error | `status` ∈ {draft, active, closed} |
| `WM-001` | Warning | `contributors` array present + non-empty |
| `WM-002` | Warning | `updated_at` ≥ `created_at` |
| `IM-001` | Info | `session_id` matches `RS-\d{8}-[a-z0-9-]+` |
| `IM-002` | Info | `version` field present (integer) |

### Structure (S) — 5 rules

| ID | Severity | Rule |
|----|----------|------|
| `ES-001` | Error | All 7 required sections present (H2 headers) |
| `ES-002` | Error | Sections in canonical order |
| `ES-003` | Error | All item IDs match naming convention `^(RT|H\d+|P\d+\.H\d+|T\d+|A\d+|X\d+|C\d+)$` |
| `ES-004` | Error | No duplicate item IDs |
| `WS-001` | Warning | IDs are sequential (no gaps) |

### Research Thread (R) — 4 rules

| ID | Severity | Rule |
|----|----------|------|
| `ER-001` | Error | RT statement present (`**RT**:` marker) |
| `ER-002` | Error | Context section present (`**Context**:` marker) |
| `WR-001` | Warning | Anchors section cites corpus / source |
| `IR-001` | Info | "Why it matters" section present |

### Hypothesis Slate (H) — 8 rules

| ID | Severity | Rule |
|----|----------|------|
| `EH-001` | Error | Minimum 3 hypotheses |
| `EH-002` | Error | Maximum 6 hypotheses (per F-302 hypothesis duplication risk) |
| `EH-003` | Error | Third alternative explicitly labeled (`origin: third_alternative`) |
| `EH-004` | Error | Each H has non-empty Claim |
| `EH-005` | Error | Each H has non-empty Falsifier (per F-103) |
| `WH-001` | Warning | Each H has anchors (corpus + EV citations) |
| `WH-002` | Warning | Anchors use `§n` format or `[inference]` label |
| `IH-001` | Info | Mechanism field present per H |

### Predictions Table (P) — 6 rules

| ID | Severity | Rule |
|----|----------|------|
| `EP-001` | Error | Minimum 3 predictions (≥1 per active H) |
| `EP-002` | Error | Table has ID column |
| `EP-003` | Error | Table has column per hypothesis |
| `WP-001` | Warning | Predictions discriminate (not all cells in a row identical) |
| `WP-002` | Warning | P IDs include hypothesis scope `P\d+\.H\d+` |
| `IP-001` | Info | "Indeterminate" predictions marked explicitly |

### Discriminative Tests (T) — 8 rules

| ID | Severity | Rule |
|----|----------|------|
| `ET-001` | Error | Minimum 2 tests |
| `ET-002` | Error | Each test has Procedure field |
| `ET-003` | Error | Each test has Expected outcomes per H |
| `WT-001` | Warning | Each test has potency check |
| `WT-002` | Warning | Tests ranked by score (descending) |
| `WT-003` | Warning | Score breakdown present (likelihood/cost/speed/ambiguity) |
| `IT-001` | Info | Discriminates field specifies hypotheses |
| `IT-002` | Info | Feasibility assessment present |

### Assumption Ledger (A) — 7 rules

| ID | Severity | Rule |
|----|----------|------|
| `EA-001` | Error | Minimum 3 assumptions |
| `EA-002` | Error | At least 1 `scale_physics` assumption (per AE-7.7) |
| `EA-003` | Error | Each A has Statement field |
| `WA-001` | Warning | Each A has Load field (load-bearing-ness assessed) |
| `WA-002` | Warning | Each A has Test field (falsifier per A) |
| `WA-003` | Warning | Scale-physics A has explicit Calculation |
| `IA-001` | Info | Status field per A (verified / pending / refuted) |

### Anomaly Register (X) — 5 rules

| ID | Severity | Rule |
|----|----------|------|
| `EX-001` | Error | Section present (even if empty) |
| `EX-002` | Error | Empty state explicit ("None registered" if no anomalies) |
| `WX-001` | Warning | Each X has Observation field |
| `WX-002` | Warning | Each X has "Conflicts with" field |
| `IX-001` | Info | Quarantine status specified per X |

### Adversarial Critique (C) — 5 rules

| ID | Severity | Rule |
|----|----------|------|
| `EC-001` | Error | Minimum 2 critiques |
| `EC-002` | Error | Each C has Attack field |
| `WC-001` | Warning | At least one "real third alternative" critique |
| `WC-002` | Warning | Evidence field per C |
| `IC-001` | Info | Current status assessment per C |

**Total: 59 rules** across 9 sections (M:8 + S:5 + R:4 + H:9 + P:6 + T:9 + A:7 + X:5 + C:6).

---

## Citation + provenance rules

Beyond per-section structural rules, the linter checks claim-provenance:

| Provenance category | Marker | Audit requirement |
|---------------------|--------|---------------------|
| Quote-backed | `§n` | Anchor exists in corpus_index.md |
| Multi-source | `§n, §m, ...` | All anchors exist |
| Inference | `[inference]` | Marker present |
| Inference+Source | `[inference] from §n` | Anchor exists |
| External | `[external: source]` | Source identified |
| Axiomatic | `[axiomatic]` | (no further check) |

### Provenance rules (subset)

| ID | Severity | Rule |
|----|----------|------|
| `EH-006` | Error | Every H Claim with corpus reference has valid `§n` anchor |
| `WT-004` | Warning | Test procedures cite ≥1 §-anchor or [inference] |
| `WC-003` | Warning | Critique attacks cite ≥1 §-anchor or [inference] |

These check that *load-bearing claims have provenance* — not just well-formatted prose.

---

## Detection patterns

Selected machine-detection patterns (regex / structural):

```regex
# EM-001: YAML frontmatter
^---\n[\s\S]*?\n---

# ES-003: ID convention
^(RT|H\d+|P\d+\.H\d+|T\d+|A\d+|X\d+|C\d+)$

# EH-003: third alternative (case-insensitive)
third\s+alternative

# Anchor patterns:
§\d+(\.\d+)?(\s*,\s*§\d+)*  # quote-backed or multi-source
\[inference\]                # inference marker
\[inference\]\s+from\s+§\d+  # inference + source
\[external:\s*[^\]]+\]       # external citation
\[axiomatic\]                # axiomatic
```

Implementations of these checks live in:

- `scripts/lint-artifact.sh` (the main CLI; calls subcheckers)
- `scripts/check-anchor-density.sh` (already exists in skill scripts)

---

## Running the linter

> **Status:** `scripts/lint-artifact.sh` is a Tier-7 planned addition. Until it lands, run rules manually against the rule tables above. The closest existing tools are `scripts/audit-bead-invariants.sh` (covers a subset of rules) and `scripts/check-anchor-density.sh` (covers anchor-density rules).

```bash
# Future:
./scripts/lint-artifact.sh <path-to-artifact.md>

# Available now:
./scripts/audit-bead-invariants.sh
./scripts/check-anchor-density.sh artifacts/<thread_id>
```

Output format (per check):

```
PASS  EM-001  YAML frontmatter present
PASS  EM-002  session_id non-empty
FAIL  EH-003  Third alternative not labeled (no `origin: third_alternative` in H slate)
WARN  WH-001  H2 lacks corpus anchors
INFO  IH-001  H1 missing Mechanism field
...

Total: 50 checks   PASS: 47   FAIL: 1   WARN: 1   INFO: 1
```

The exit code:
- `0` = all errors pass (warnings/info OK)
- `1` = ≥1 error
- `2` = lint script itself errored

For Phase 8 freeze: exit code MUST be 0. Per `scripts/check-six-layer-validation.sh` Layer 4.

---

## Failure semantics

When a lint fails, the operator's response depends on severity:

### Error fails

- Block Phase 8 freeze (per F-803)
- Auto-generate audit-finding bead with `severity: high` and citation to lint rule
- Operator must address the rule violation (rewrite section, add field, etc.)
- Re-run linter; iterate until clean

### Warning fails

- Don't block freeze
- Auto-generate audit-finding bead with `severity: medium`
- Track in OPERATOR-CALIBRATION-LOG.md (operator should reduce warnings over time)
- Acceptable to ship with warnings IF documented in HANDBACK § Caveats

### Info fails

- Don't block; don't generate beads
- Logged for operator self-improvement (per OPERATOR-ONBOARDING-CURRICULUM.md)

---

## Composition with brennerbot beads

The linter integrates with the bead system:

- Lint failures → audit-finding beads (when `scripts/lint-artifact.sh --emit-beads` lands; until then, file beads manually via `br create --labels=audit-finding ...`)
- Audit-finding beads in Phase 7 reflect lint state at freeze
- Phase 7 completion gate: `audit-finding` beads with `severity: high` count = 0

Per BRENNERBOT-DOCTOR-RUBRIC.md Pillar 1 (Structural): the doctor's structural pass = the linter's clean run.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip linter for "small" sessions | Drift accumulates; small sessions become harder to compare to large ones |
| Treat warnings as errors | Block freeze unnecessarily; defeats severity tiering |
| Treat errors as warnings | Lint-clean discipline lost; freeze-ready definition collapses |
| Hand-edit ARTIFACT.md to satisfy linter | Edit beads instead; ARTIFACT is *generated* (per ARTIFACT-7-SECTION-SCHEMA.md) |
| Add custom rules without versioning | Rule IDs become ambiguous; cross-session tooling breaks |
| Run linter only at Phase 8 | Run during Phases 4-7 to catch issues early |
| Ignore failure semantics | Errors block; warnings warn; mixing them defeats automation |

---

## Versioning

This rule catalog is version 1 (matches `/dp/brenner_bot/specs/artifact_linter_spec_v0.1.md` v0.1).

Changes to the catalog should follow:

- New rule → next sequential ID; add to per-section table
- Severity change → bump catalog version; document in METHODOLOGY-EVOLUTION-LOG.md
- Removed rule → mark deprecated; do NOT recycle ID

Per BRENNERBOT-AT-SCALE.md, the rule catalog evolves quarterly based on observed failure modes.

---

## Cross-references

- [ARTIFACT-7-SECTION-SCHEMA.md](ARTIFACT-7-SECTION-SCHEMA.md) — what the linter validates
- [BEADS-SCHEMA.md](BEADS-SCHEMA.md) — the underlying bead structure
- [PHASE-7-ANTI-EXAMPLES.md](PHASE-7-ANTI-EXAMPLES.md) — AE-7.7 (scale-physics calculation skip)
- [BRENNERBOT-DOCTOR-RUBRIC.md](BRENNERBOT-DOCTOR-RUBRIC.md) — Pillar 1 structural integrity
- [OPERATOR-CALIBRATION-LOG.md](OPERATOR-CALIBRATION-LOG.md) — track lint-warning trends
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — rule version changes
- [scripts/check-anchor-density.sh](../scripts/check-anchor-density.sh) — anchor-pattern checker
- [scripts/check-six-layer-validation.sh](../scripts/check-six-layer-validation.sh) — Layer 4 invokes lint
- /dp/brenner_bot/specs/artifact_linter_spec_v0.1.md — original specification
