# TAXONOMIES-COMPLETE-CATALOG.md — Every Bead-Attribute Enum, in One Place

<!-- TOC: Why a unified catalog | Hypothesis taxonomies | Test taxonomies | Assumption taxonomies | Anomaly taxonomies | Critique taxonomies | Evidence taxonomies | Prediction taxonomies | Persona taxonomies | Provenance taxonomies | Lookup table for ID prefixes | Anti-patterns | Cross-references -->

Brennerbot has dozens of typed enums scattered across schemas (categories, origins, types, states, statuses, severities, kinds). Without a single catalog, operators infer them from prose, get them wrong, and the linter rejects.

This file is the **authoritative reference** for every bead-attribute enum. When in doubt, check here first.

Mined from `/dp/brenner_bot/README.md` (across many sections), `specs/artifact_schema_v0.1.md`, `specs/evidence_pack_v0.1.md`, `specs/role_prompts_v0.1.md`, and the existing brennerbot-with-ntm references.

---

## Why a unified catalog

Three failures of distributed taxonomies:

1. **Inferred values** — operators write `severity: high` when valid value is `severe`; lint rejects
2. **Stale references** — references in different files reach different vocabulary; cross-session diff misclassifies
3. **No "what's all the options" answer** — operators don't know what *else* they could have used

This catalog is **canonical**. Lint rules cite it; templates cite it; cross-references cite it.

---

## Hypothesis taxonomies

### `H-NNN.state` (lifecycle FSM, 9 values)

Per HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md:

```
draft | proposed | active | under_attack | assumption_undermined | refined | dormant | killed | validated
```

### `H-NNN.category` (hypothesis classification, 5 values)

```
mechanistic           # explains via causal mechanism
phenomenological      # describes pattern without mechanism
boundary              # delimits when other Hs apply
auxiliary             # supports another H but not standalone
third_alternative     # explicit "both could be wrong" option
```

### `H-NNN.origin` (where the H came from, 4 values)

```
proposed              # standard agent proposal
third_alternative     # explicit cross-domain or null option
refinement            # evolved from prior H (with refined_from field)
anomaly_spawned       # generated from quarantined anomaly
```

### `H-NNN.confidence` (evaluation, 3 values)

```
low | medium | high
```

### `H-NNN.arena_status` (in-arena state, 4 values; per HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md)

```
active | eliminated | suspended | champion
```

---

## Test taxonomies

### `T-NNN.state` (test execution lifecycle, 5 values)

```
designed              # specified but not yet run
pending               # queued for execution
in_progress           # currently running
completed             # finished; outcome recorded
blocked               # cannot proceed (assumption falsified, etc.)
```

### `T-NNN.kind` (test type)

```
genetic               # ablation/knockout-style
pharmacological       # perturbation by chemical agent
behavioral            # observe behavior under condition
computational         # in-silico simulation
formal                # proof or derivation
empirical             # measurement-based
```

(For software/methodology archetypes, replace with: `microbenchmark | integration_test | proof_check | replication | static_analysis | runtime_audit`.)

### `T-NNN-binding` (test-to-hypothesis result, 3 values)

```
matched               # observed outcome matches H's prediction
violated              # observed outcome contradicts H's prediction
uncalled              # observed outcome doesn't decisively match either way
```

### `T-NNN.potency_check` (binary)

```
pass                  # potency control confirms assay works
fail                  # potency control failed; assay broken
```

---

## Assumption taxonomies

### `A-NNN.type` (assumption classification, 4 values)

```
background            # general background knowledge
methodological        # the method we're using assumes X works
boundary              # X holds within domain Y but maybe not outside
scale_physics         # ⊞ Scale-Check axiom (mandatory ≥1 per session)
dont_worry            # latent mechanism we're explicitly not investigating
corpus_authority      # cited authority; may need re-verification
domain_axiom          # field-specific foundational assumption
regulatory            # regulatory/compliance constraint
```

### `A-NNN.state` (assumption verification, 4 values)

```
unchecked             # claimed but not tested
challenged            # under active scrutiny
verified              # confirmed by EV or calculation
falsified             # disproved (triggers cascade per HYPOTHESIS-LIFECYCLE)
```

---

## Anomaly taxonomies

### `X-NNN.source_type` (where the anomaly came from)

```
experiment            # observed during a discriminative test
observation           # noticed by an investigator outside test
literature            # discovered in corpus / EV
calculation           # surfaced by scale-physics calc
log                   # found in operational logs / monitoring
```

### `X-NNN.quarantine_status` (4 values)

```
active                # newly observed; not yet processed
resolved              # explained (often spawned a new H)
deferred              # parked for later (must have reason)
paradigm_shifting     # this anomaly invalidates the framing
```

---

## Critique taxonomies

### `C-NNN.target_type` (5 values)

```
H-NNN                 # specific hypothesis
T-NNN                 # specific test
A-NNN                 # specific assumption
framing               # the question of record itself
methodology           # the session's process
```

### `C-NNN.severity` (4 values; gates Phase 8 freeze at ≥serious)

```
minor                 # style or polish issue
moderate              # reduces verdict confidence by ≤1 level
serious               # reduces verdict confidence by ≥2 levels (BLOCKS FREEZE)
critical              # invalidates the verdict (BLOCKS FREEZE; forces Phase 1 reframe)
```

### `C-NNN.status` (4 values)

```
active                # filed; not yet resolved
addressed             # target was modified to fix
dismissed             # rejected with documented reason
accepted              # critique was correct; target killed
```

### `C-NNN.action` (4 values; what was done in response)

```
modified              # target was edited
dismissed             # critique rejected (with reason)
accepted              # critique accepted; target killed
killed                # target was killed (different from accepted: more decisive)
```

---

## Evidence taxonomies

### `EV-NNN.type` (evidence record type, 7 values)

```
paper                 # peer-reviewed publication
dataset               # public/internal dataset
experiment            # internal experiment result
session               # reference to another brennerbot session
website               # non-paper web source
code                  # GitHub repo or local code reference
manual                # operator-entered with no formal source
```

### `EV-NNN.access_method` (5 values)

```
url | doi | file | session | manual
```

### `EV-NNN.verified` (boolean)

```
true                  # human has opened source + confirmed excerpt
false                 # claim only; not human-verified
```

### `EV-NNN#E<n>.type` (excerpt type, 3 values)

```
verbatim              # direct quote
paraphrase            # source's idea in different words
inference             # not in source; derived from it
```

### `EV-NNN.relationship` (per H, 3 values)

```
supports              # evidence supports the H
refutes               # evidence refutes the H
related               # evidence touches H's topic but not directly supportive/refuting
```

---

## Prediction taxonomies

### `P-NNN.type` (prediction type, 5 values; per PREDICTION-LOCK-CRYPTOGRAPHIC.md)

```
qualitative           # "X will increase"
quantitative          # "X will be > 5.0"
comparative           # "X > Y"
temporal              # "X before Y"
null                  # "No effect"
```

### `P-NNN.state` (lock state, 4 values)

```
draft                 # editable, not committed
locked                # SHA-256 sealed; immutable
revealed              # evidence collected; comparison done
amended               # modified after locking (penalty applies)
```

### `P-NNN.boldness` (4 values; per HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md)

```
vague                 # 1.0× multiplier
specific              # 1.5× multiplier
precise               # 2.0× multiplier
surprising            # 3.0× multiplier
```

### `P-NNN.result` (revealed comparison, 3 values)

```
confirmed | refuted | inconclusive
```

### `P-NNN.amendment_type` (4 values)

```
clarification         # rewording without semantic change
reinterpretation      # different meaning post-evidence
scope_change          # narrowing/broadening of claim
retraction            # full withdrawal
```

---

## Persona taxonomies

### Persona role (per MULTI-AGENT-TRIBUNAL-PERSONAS.md, 4 values)

```
devils_advocate
experiment_designer
brenner_channeler
synthesis
```

### Persona dial dimensions (4 values, each 0.0–1.0)

```
assertiveness | constructiveness | socratic_level | formality
```

---

## Provenance taxonomies

### Anchor format (per CITATION-PROVENANCE-RULES.md)

```
§n                          # Brenner transcript section
§n, §m, ...                 # multi-section quote
§n.k                        # subsection
§n-§m                       # range
EV-NNN                      # evidence record (whole)
EV-NNN#E<n>                 # specific excerpt
EV-NNN#E<n> [verbatim]      # direct quote marker
EV-NNN#E<n> [paraphrase]    # paraphrase marker
[inference]                 # agent reasoning beyond evidence
[inference] from §n         # grounded inference
[synthesis]                 # combination across multiple sources
[external: <source>]        # outside corpus + EV
[axiomatic]                 # foundational assumption
```

### Provenance category (6 values)

```
quote_backed | multi_source | inference | inference_grounded | external | axiomatic
```

---

## Operator intervention taxonomies

### `INT-NNN.type` (per OPERATOR-INTERVENTION-RECORDING.md, 6 values)

```
artifact_edit | delta_exclusion | delta_injection | decision_override | session_control | role_reassignment
```

### `INT-NNN.severity` (4 values)

```
minor | moderate | major | critical
```

---

## Roster + role taxonomies

### Agent role (per AGENT-ROSTER-AND-PRESETS.md, 3 canonical values)

```
hypothesis_generator | test_designer | adversarial_critic
```

### CLI program

```
codex-cli | claude-code | gemini-cli | <custom>
```

### Roster mode (2 values)

```
role_separated | unified
```

---

## Tribunal trigger taxonomies

### Invocation triggers (7 values)

```
hypothesis_submitted | hypothesis_refined | prediction_locked | evidence_supports | test_designed | tribunal_requested | phase_transition
```

---

## Subject prefix taxonomy

### Mail subject prefix (10 values; per MESSAGE-BODY-SCHEMA-PER-TYPE.md)

```
KICKOFF | DELTA[role] | COMPILED | CRITIQUE | ACK | CLAIM | HANDOFF | BLOCKED | QUESTION | INFO
```

### DELTA role shorthand (5 values)

```
opus | gpt | gemini | claude | human
```

---

## Lookup table for ID prefixes

**Important:** brennerbot uses two parallel identifier conventions:

1. **Bead IDs** (in the `br` ledger; `<prefix>-NNN` with 3-digit zero-padding) — the canonical brennerbot-with-ntm convention; per BEADS-SCHEMA.md
2. **In-artifact labels** (in the 7-section artifact; `<prefix>N` without zero-padding) — per ARTIFACT-7-SECTION-SCHEMA.md, mined from /dp/brenner_bot's spec

The two are linked but use different prefixes for *anomaly*: bead is `AN-` (consistent with the brennerbot-with-ntm bead schema since Tier-1); 7-section in-artifact label is `X` (per /dp/brenner_bot's spec).

| Bead prefix | In-artifact label | Bead type | Section in 7-section artifact |
|-------------|--------------------|-----------|-------------------------------|
| `H-` | `H` | hypothesis | hypothesis_slate |
| `T-` | `T` | test | discriminative_tests |
| `A-` | `A` | assumption | assumption_ledger |
| `AN-` | `X` | anomaly | anomaly_register |
| `C-` | `C` | critique | adversarial_critique |
| `EV-` | (cited as `EV-NNN`) | evidence record | (separate evidence pack) |
| `P-` | (cited inside H) | prediction | (linked to H) |
| `D-` | (per-family) | distillation | (per-family distillations) |
| (none) | `RT` | research thread | research_thread (singleton) |
| `Q-` | (cited as `Q-NNN`) | question of record | (intake) |
| `INT-` | (separate log) | operator intervention | (separate audit log) |
| `CF-` | (in artifact) | counterfactual | counterfactual_register |
| `RP-` | (program-level) | research program | (multi-session container) |
| `RS-` | (thread ID) | research session | (thread ID prefix) |
| `REC-` | (record file) | session record | (replay format) |
| `AF-` | (separate) | audit finding (label: `audit-finding`) | (Phase 7 output) |

When mining /dp/brenner_bot specs (round-18+ references like ARTIFACT-7-SECTION-SCHEMA.md, ARTIFACT-LINTER-RULES.md), the in-artifact label `X` may appear; that's the artifact-section convention, not the bead prefix. In bead operations (`br create ...`), use `AN-NNN`.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Use values not in this catalog | Lint rejects |
| Capitalize values inconsistently (`Active` vs `active`) | All values are lowercase |
| Add custom values without spec update | Cross-session aggregation breaks |
| Mix old and new vocabulary across sessions | Per AGENTS.md no-deletion: old terms preserved but new sessions use canonical |
| `severity: high` (not in C-NNN severity catalog) | Use `serious` or `critical` per the actual catalog |
| `confidence: very high` | Only `low`/`medium`/`high` |
| Use multiple values where catalog allows one | Each field is single-valued |

---

## Cross-references

- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — H state FSM
- [HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md](HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md) — boldness tiers
- [PREDICTION-LOCK-CRYPTOGRAPHIC.md](PREDICTION-LOCK-CRYPTOGRAPHIC.md) — prediction states
- [TRIBUNAL-AND-OBJECTION-REGISTER.md](TRIBUNAL-AND-OBJECTION-REGISTER.md) — critique taxonomies
- [EVIDENCE-PACK-PROTOCOL.md](EVIDENCE-PACK-PROTOCOL.md) — EV taxonomies
- [CITATION-PROVENANCE-RULES.md](CITATION-PROVENANCE-RULES.md) — anchor format catalog
- [MULTI-AGENT-TRIBUNAL-PERSONAS.md](MULTI-AGENT-TRIBUNAL-PERSONAS.md) — persona taxonomies
- [OPERATOR-INTERVENTION-RECORDING.md](OPERATOR-INTERVENTION-RECORDING.md) — INT taxonomies
- [BEADS-SCHEMA.md](BEADS-SCHEMA.md) — bead-level schema
- [ARTIFACT-LINTER-RULES.md](ARTIFACT-LINTER-RULES.md) — lint rules cite this catalog
- /dp/brenner_bot/README.md (multiple sections) — original sources
