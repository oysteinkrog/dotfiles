# SHARPENING-AND-REVISION-EDITORS.md — Iterative Refinement of Hypotheses, Tests, Assumptions

<!-- TOC: Why iterative refinement | Sharpening vs revision | The sharpening editor | The revision editor | Per-target editor patterns | Versioning + history preservation | When to sharpen vs revise | Anti-patterns | Cross-references -->

A first-draft hypothesis is rarely a Brenner-grade hypothesis. It needs **sharpening** — making the falsifier crisper, the mechanism more specific, the prediction more discriminative. As evidence arrives, it may need **revision** — modification in response to new information.

The two operations are different:

- **Sharpen**: improve the H *as expressed*; same intent, tighter words
- **Revise**: change the H *in light of new evidence*; intent shifts

Without distinct editors, both collapse into "edit"; audit trails get muddy; refinement chains lose meaning.

Mined from `/dp/brenner_bot/CHANGELOG.md` v0.2.0 § Add sharpening and revision editors to brenner-loop.

---

## Why iterative refinement

Three failures of write-once H:

1. **First drafts are weak** — vague mechanisms, hedge-words, missing falsifiers
2. **Evidence accumulates** — Phase 4 EVs reveal what wasn't anticipated; H needs to absorb
3. **Critique pressure** — Devil's-Advocate finds flaws; the H must respond or die

Three benefits of dedicated editors:

1. **Sharpen pre-evidence** — improve the H's *expression* before it's tested
2. **Revise post-evidence** — modify the H *in response* to what was learned
3. **Distinct audit trails** — sharpenings vs revisions tell different stories

---

## Sharpening vs revision

### Sharpening

**Intent unchanged**; expression improved.

```
Before: "Memory pressure causes high tail latency"
After:  "Sustained memory pressure (>80% utilization for >30s) causes p99 latency to exceed 500ms via increased GC pause frequency"
```

The **same idea**, expressed with:
- Specific quantitative thresholds
- Specified causal mechanism (GC pauses)
- Discriminative observable (p99 > 500ms)

Sharpening can happen at any time. Per OPERATOR-INTERVENTION-RECORDING.md, it's `severity: minor` — improves expression without changing what's being claimed.

### Revision

**Intent changed**; in light of new evidence.

```
Before: "Memory pressure causes high tail latency"
Evidence (EV-007): Tail latency spikes precede memory-pressure spikes by 2-5s
After:  "GC-induced object retention causes both memory pressure AND high tail latency; the apparent causal direction is reverse"
```

The **idea has changed**:
- Original: A → B (memory → latency)
- Revised: C → A AND C → B (GC retention → both)

Revision creates a new H lineage (per HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md): `H-001 → state: refined; refined_into: H-001.b`. The new H starts in `draft`.

Per OPERATOR-INTERVENTION-RECORDING.md, revision is `severity: major` — the intent has changed.

---

## The sharpening editor

The sharpening editor is a workflow for tightening an H without changing its intent:

```bash
brenner hypothesis sharpen H-RS20260301-001 \
  --target falsifier \
  --before "Latency stays the same" \
  --after  "p99 latency stays below 500ms (statistical significance: p<0.001) under load >1000 req/s"
```

Or via the web UI's sharpening interface:

```
[Sharpen H-001]

Statement:    Memory pressure causes high tail latency
Mechanism:    [vague]
Predictions:  [missing specifics]
Falsifier:    [unfalsifiable hedging]

Sharpening targets:
  ☐ Statement   — make claim specific
  ☐ Mechanism   — specify causal pathway
  ☑ Predictions — add quantitative thresholds
  ☑ Falsifier   — make refutable observation explicit
```

Each sharpening is recorded as an EDIT in the H's edit history; the H stays in its current FSM state.

---

## The revision editor

The revision editor is a workflow for modifying an H in light of evidence:

```bash
brenner hypothesis revise H-RS20260301-001 \
  --evidence EV-007 \
  --new-claim "GC-induced object retention causes both memory pressure AND high tail latency"
```

Effects:
- Original H-001 transitions `active` → `refined`
- New H-001.b created in `draft` state
- `refined_from: H-001` set on H-001.b
- `refined_into: H-001.b` set on H-001
- Mail thread `RS-...-H-001-revision` opened
- Devil's-Advocate notified for adversarial review of the revision

The new H needs its own predictions, tests, and assumption ledger; it's effectively a new investigation.

Per HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md: revision creates a NEW H, doesn't mutate the existing one. Lineage preserved.

---

## Per-target editor patterns

Both editors target specific fields:

### H-NNN sharpening targets

- `statement` — the claim itself
- `mechanism` — the causal story
- `predictions` — what we'd see if H were true
- `falsifier` — what observation would refute
- `expected_evidence` — types of evidence we'd find
- `category` — mechanistic / phenomenological / etc.
- `confidence` — pre-evidence assessment

### T-NNN sharpening targets

- `description` — what the test does
- `predictions` — per-H expected outcomes
- `potency_check` — control specification
- `cost` — time/$ estimate
- `feasibility` — can we run it?

### A-NNN sharpening targets

- `statement` — the assumption
- `falsifier` — what would break it
- `calculation` — for scale_physics: explicit numbers
- `affects` — which H/T depend on it

### C-NNN sharpening targets

- `attack` — the adversarial argument
- `evidence` — citations
- `severity` — calibrated severity
- `suggested_resolution` — proposed fix

Each editor knows the field schema (per ARTIFACT-LINTER-RULES.md) and validates as you sharpen.

---

## Versioning + history preservation

Per AGENTS.md no-deletion: every sharpen/revise preserves the prior version.

H-NNN edit history schema:

```yaml
id: H-001
version: 4
edits:
  - version: 1
    field: statement
    before: "Memory pressure causes latency"
    after: "Sustained memory pressure causes high tail latency"
    type: sharpening
    by: BlueLake
    at: 2026-03-01T14:00:00Z
  - version: 2
    field: falsifier
    before: ""
    after: "p99 latency stays below 500ms under load >1000 req/s"
    type: sharpening
    by: BlueLake
    at: 2026-03-01T14:05:00Z
  - version: 3
    field: mechanism
    before: ""
    after: "GC pause frequency increases under memory pressure"
    type: sharpening
    by: PurpleMountain
    at: 2026-03-01T14:30:00Z
  - version: 4
    type: revision
    revised_into: H-001.b
    reason: "EV-007 reveals reversed causality"
    by: GreenValley
    at: 2026-03-01T16:15:00Z
```

The history shows: 3 sharpenings (intent stable), 1 revision (intent changed). The audit trail is complete.

---

## When to sharpen vs revise

Decision rule:

```
If the new H means the SAME thing more precisely → SHARPEN
If the new H means a DIFFERENT thing → REVISE
```

Per `/dp/brenner_bot/CHANGELOG.md` v0.2.0:
> Add sharpening and revision editors to brenner-loop

The two operations were added together because they're complementary; neither alone is sufficient.

Common scenario sequence:

```
Phase 3: H-001 drafted (vague)
Phase 3.5: SHARPEN H-001 (add mechanism, falsifier, predictions)
Phase 4: EV-007 collected; reverses apparent causality
Phase 5: REVISE H-001 → H-001.b (intent shifted to "GC-induced retention")
Phase 5: SHARPEN H-001.b (predictions specific to GC-retention model)
Phase 7: validated H-001.b
```

Sharpenings (3 in this scenario) are the dominant operation; revisions (1) are rare and high-cost.

---

## Editor + checkpoint integration

Per COACH-MODE-GUIDED-LEARNING.md, the sharpening editor surfaces quality checkpoints:

```
Sharpening H-001 → field: statement

Quality check: Does the statement specify a causal mechanism?
  ☐ "X causes Y" — vague (no mechanism)
  ☑ "X causes Y via Z" — mechanism specified
  ✓ Pass → save sharpening
```

The checkpoint catches vagueness *before* the sharpening is saved. The operator can iterate within the editor without committing weak sharpenings to history.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Use sharpen when intent has changed | Audit trail muddied; should be revise |
| Use revise when intent unchanged | Creates unnecessary new H; lineage clutter |
| Edit H directly without sharpen/revise tooling | Bypasses editor checkpoints; bypasses history |
| Skip recording who sharpened | Per OPERATOR-INTERVENTION-RECORDING.md: every change has an actor |
| Multiple sharpenings in one save | Each sharpening atomic; one field per save |
| Revise without filing critique that motivated revision | Revision should reference the C-NNN that triggered it |
| Sharpen vague statement to "be less vague" | Specifically — what's the new specificity? |
| Treat sharpening as cosmetic | Sharpening matters; vague H produces vague Phase 5 verdicts |

---

## CLI reference

```bash
# Sharpen a hypothesis (intent unchanged):
brenner hypothesis sharpen H-NNN \
  --target <statement|mechanism|predictions|falsifier|...> \
  --before "<old>" \
  --after  "<new>" \
  --by <agent>

# Revise a hypothesis (intent changed; creates new H):
brenner hypothesis revise H-NNN \
  --evidence <EV-NNN> \
  --reason "<why-revising>" \
  --new-claim "<new-claim>" \
  --by <agent>

# Show edit history:
brenner hypothesis history H-NNN
```

Same patterns for `test sharpen/revise`, `assumption sharpen/revise`, `critique sharpen/revise`.

---

## Composition with brennerbot

Sharpening + revision integrates with:

- **HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md**: revision = `refine` event; sharpen = no state change
- **OPERATOR-INTERVENTION-RECORDING.md**: sharpenings logged as `severity: minor`; revisions as `major`
- **COACH-MODE-GUIDED-LEARNING.md**: editor surfaces quality checkpoints
- **EVALUATION-RUBRIC-14-CRITERIA.md**: sharpening produces higher rubric scores
- **HANDBACK-VOICE-GUIDE.md**: sharp falsifiers ground crisp HANDBACK verdicts

---

## Cross-references

- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — refine event
- [OPERATOR-INTERVENTION-RECORDING.md](OPERATOR-INTERVENTION-RECORDING.md) — severity calibration
- [COACH-MODE-GUIDED-LEARNING.md](COACH-MODE-GUIDED-LEARNING.md) — quality checkpoints
- [EVALUATION-RUBRIC-14-CRITERIA.md](EVALUATION-RUBRIC-14-CRITERIA.md) — rubric criteria
- [ARTIFACT-LINTER-RULES.md](ARTIFACT-LINTER-RULES.md) — field schemas
- [TAXONOMIES-COMPLETE-CATALOG.md](TAXONOMIES-COMPLETE-CATALOG.md) — H/T/A/C field enums
- /dp/brenner_bot/CHANGELOG.md v0.2.0 § Sharpening/revision editors — feature source
