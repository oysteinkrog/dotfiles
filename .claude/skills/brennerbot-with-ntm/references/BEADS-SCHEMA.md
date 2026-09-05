# BEADS-SCHEMA.md — Bead Types, Fields, Invariants

<!-- TOC: Field encoding | q-of-record | hypothesis | evidence | test | assumption | anomaly | critique | debate | distillation | audit-finding | Field grammar | Common queries | Initialization -->

Beads (`br`) is the structured ledger for hypotheses, evidence, debates, distillations, audits. Every concept from brenner_bot's CLI maps to a `br` label + field convention here.

**Field encoding:** `br` doesn't have native typed fields. We encode structured fields in the bead's `description` (markdown body) using a `key: value` block and `key:` prefixed paragraphs. The `audit-bead-invariants.sh` script parses these.

**Actual IDs vs public refs:** current `br create` generates the actual issue ID
(for example `bb-h-001-k4m2`). BrennerBot labels such as `H-001`, `EV-014`,
and `DEBATE-001` are public refs for humans. Store them in the title prefix and
`--external-ref`, capture `br create --silent` output, and use the captured
actual ID for later `br show` / `br update` commands.

```bash
h_ref="H-001"
h_id="$(br create "$h_ref: <one-line claim>" \
  --type=task --labels=hypothesis --priority=2 \
  --slug="$h_ref" --external-ref="$h_ref" --silent \
  --description="$(cat <<'EOF'
claim: <full claim sentence>
mechanism: <production rule that would make the claim true>
falsifier: <what observation, if seen, kills this hypothesis>
expected_evidence: <what observation, if seen, supports this hypothesis>
category: mechanistic
origin: proposed
confidence: medium
parent: H-000
session: RS-20260506-event-log

## Detail
<longer narrative if helpful>
EOF
)")"
printf 'created %s as %s\n' "$h_ref" "$h_id"
```

---

## Bead Types & Their Schemas

### `q-of-record` — the question of record (one per session)

**Public ref pattern:** `Q-001`

**Required fields:**

```yaml
question: <the research question, one sentence>
falsifier: <what would, if observed, prove the question is malformed or already answered>
scope: <bounded list of what's in scope>
out_of_scope: <bounded list of what's NOT in scope>
mode: fresh-question | code-investigation | corpus-distillation | resume-session | methodology-drift-check | incident-investigation
provenance: <where the question came from — user ask, prior session, paradox in corpus>
session: <RS-YYYYMMDD-slug>
```

**State machine:** `open → closed` (closed at end of Phase 1).

**Invariants:**

- `falsifier` field MUST be non-empty.
- `scope` and `out_of_scope` MUST both be non-empty.

---

### `hypothesis` — a candidate explanatory model

**Public ref pattern:** `H-NNN` (zero-padded; `H-000` reserved for the paradox bead from Phase 1)

**Required fields:**

```yaml
claim: <one-sentence assertion>
mechanism: <the production rule / causal pathway that would make the claim true>
falsifier: <what observation kills this hypothesis>          # ✂ Exclusion-Test
expected_evidence: <what observation supports it>             # ⌂ Materialize
category: mechanistic | phenomenological | boundary | auxiliary | third_alternative   # ⊘ Level-Split
origin: proposed | third_alternative | refinement | anomaly_spawned
confidence: high | medium | low | speculative
session: <session id>
```

**Optional fields:**

```yaml
parent: <H-NNN link target; original H for refinements, replacement H when this H is superseded>
refuted_by: <EV-NNN or T-NNN that fired the falsifier>
adjudication: <DEBATE-NNN that settled the state>
```

**State machine (compact, used by scripts and bead `state:` field):** `proposed → active → confirmed | refuted | superseded | deferred`.

> **Bridge to the 9-state FSM.** The compact 6-state vocabulary above is what `H-NNN` bead descriptions hold and what scripts like `audit-bead-invariants.sh` grep for. The conceptually-richer 9-state FSM (`draft / proposed / active / under_attack / assumption_undermined / refined / dormant / killed / validated`) lives in [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md § State-name mapping](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md#state-name-mapping-bead-state-field--fsm-state). Treat them as two views of the same lifecycle: scripts use the compact names; methodology prose uses the granular ones.

**Invariants:**

- `falsifier` MUST be non-empty for any hypothesis.
- `expected_evidence` MUST be non-empty.
- `category` MUST be one of the enum.
- A hypothesis with `state: refuted` MUST have non-empty `refuted_by`.
- A hypothesis with `state: confirmed` MUST cite ≥1 `DEBATE-NNN` and ≥2 `EV-NNN` from independent sources (independence = different `EV.source` URLs/files/sessions).
- A hypothesis with `state: superseded` MUST have a `parent: H-NNN` field pointing at the replacement/canonical hypothesis. A replacement hypothesis SHOULD use `origin:refinement` when it is a revised version, but the machine-checkable pointer on the superseded bead points forward to the replacement.
- The slate MUST include ≥1 hypothesis with `origin=third_alternative` (Brenner §103).

**Lookup queries:**

```bash
br list --label=hypothesis --status=open --json | jq '.issues[]? | {id, status, fields: (.description // "")}'
```

---

### `evidence` — a citation supporting / refuting / informing a hypothesis

**Public ref pattern:** `EV-NNN`

**Required fields:**

```yaml
type: paper | experiment | observation | prior_session | expert_opinion | code_artifact | benchmark
source: <URL | file path with line range | DOI | session URL>
relevance: <one-sentence explanation>
imported_at: <ISO-8601>
imported_by: <pane id or operator>
verified: false | true
session: <session id>

## Excerpts
- E1 (verbatim): "<exact quote>" (location: <section/line>)
- E2 (paraphrase): "<paraphrase>" (location: <...>)
```

**Optional fields:**

```yaml
supports: [H-001, H-007]       # H-IDs this EV supports
refutes: [H-005]                # H-IDs this EV refutes
informs: [T-002]                # T-IDs (tests) this EV informs
verification_notes: <how it was verified>
authors: [<name>, ...]
date: <ISO date>
key_findings:                   # ≡ Invariant-Extract
  - <finding 1>
  - <finding 2>
access_method: url | doi | file | session | manual
```

**State machine:** `unverified → verified`.

**Invariants:**

- `source` MUST be non-empty.
- For Phase 4 to mark `verified:true`, at least one excerpt MUST have `verbatim:true`.
- An `EV-*` cited as `refuted_by:` for a hypothesis MUST be `verified:true`.

---

### `test` (or `probe`) — a designed discriminative experiment

**Public ref pattern:** `T-NNN`

**Required fields:**

```yaml
discriminates_between: [H-001, H-005]
potency_check: <chastity-vs-impotence test — distinguishes "intervention failed" from "hypothesis wrong">
expected_signal: <what magnitude / shape — must be ≥10× or binary>     # ↑ Amplify
cost_estimate: <wall-clock time, infra dependence>
session: <session id>
```

**Optional fields:**

```yaml
ran_at: <ISO-8601>
result: matched | violated | inconclusive
result_evidence: <EV-NNN that captured the result>
notes: <free text>
```

**State machine:** `designed → ready → in_progress → completed | blocked | abandoned`.

**Invariants:**

- `potency_check` MUST be non-empty (per Brenner §50).
- `expected_signal` MUST specify magnitude (≥10×, binary, or "qualitatively visible").
- `discriminates_between` MUST list ≥2 H-IDs.

---

### `assumption` — a load-bearing background or scale-physics assumption

**Public ref pattern:** `A-NNN`

**Required fields:**

```yaml
statement: <one-sentence assumption>
type: background | methodological | boundary | scale_physics
load_description: <what fails if this assumption is false>
affects: [H-001, T-002]
session: <session id>
```

**Optional fields, conditionally required:**

```yaml
calculation: <REQUIRED if type=scale_physics — the math showing the bound holds>
test_method: <how to verify>
verified_by: <EV-NNN or operator note>
```

**State machine:** `unchecked → challenged → verified | falsified`.

**Invariants:**

- If `type=scale_physics`, `calculation:` MUST be non-empty (per ⊞ Scale-Check).

---

### `anomaly` — observation that doesn't fit any active hypothesis

**Public ref pattern:** `AN-NNN`

**Required fields:**

```yaml
observation: <what was seen>
conflicts_with: [H-001, H-005]
source_type: experiment | literature | discussion | calculation
session: <session id>
```

**Optional fields:**

```yaml
spawned_hypothesis: <H-NNN if Phase 4 promoted to a new hypothesis>
cluster_with: [AN-002]   # if multiple anomalies share a feature
```

**State machine:** `active → resolved | deferred | paradigm_shifting`.

**Invariants:**

- `conflicts_with` MUST list ≥1 H-ID OR explicitly `none` (genuinely orphan observation).

---

### `critique` — adversarial attack on a hypothesis/test/assumption/framing

**Public ref pattern:** `C-NNN`

**Required fields:**

```yaml
target: H-NNN | T-NNN | A-NNN | framing | methodology
attack: <the criticism>
severity: minor | moderate | serious | critical
evidence_to_confirm: <what would, if found, confirm the attack>
session: <session id>
by: <pane id>
```

**Optional fields:**

```yaml
anchors: [§-NNN, ...]      # corpus anchors supporting the attack
response: <hypothesizer's response>
action: none | modified | killed | new_test
new_test_id: <T-NNN>
```

**State machine:** `active → addressed | dismissed | accepted`.

**Invariants:**

- `target` MUST be one of the enum (or specific bead id).
- `evidence_to_confirm` MUST be non-empty (otherwise it's rhetoric, not critique).

---

### `debate` — pairwise adversarial debate record

**Public ref pattern:** `DEBATE-NNN`

**Required fields:**

```yaml
debate_ref: DEBATE-NNN
pair: H-Hi vs H-Hj
rounds: <int>
champions: {H-Hi: <pane-id>, H-Hj: <pane-id>}
adjudicator: <pane-id>
adjudication: <which H won, with reasoning>
session: <session id>
```

**Optional fields:**

```yaml
falsifier_fired: <EV-NNN that triggered the kill, if any>
mail_thread: RS-...-DEBATE-<H_I>-vs-<H_J>   # bead IDs interpolated, e.g. RS-...-DEBATE-H-001-vs-H-002
```

**State machine:** `open → settled`.

**Invariants:**

- Champions MUST be from different model families when possible (apply 🤝 GAN).
- Adjudicator MUST NOT be the same pane as either champion.
- An adjudication MUST cite specific `EV-*` or `T-*`, not vibes.

---

### `distillation` — a per-model-family or meta synthesis

**Public ref pattern:** `D-<family>-NNN`, e.g., `D-cc-001`, `D-cod-001`, `D-meta-001`

**Required fields:**

```yaml
by_model: cc | cod | gmi | meta
kernel_axioms: [<axiom 1>, <axiom 2>]
generative_loop: <restated for this question's domain>
operator_algebra_adapted: <list of which operators apply specifically here>
disagreements_flagged: [<one per other model family>]   # required for meta only
session: <session id>
```

**State machine:** `draft → final`.

**Invariants:**

- The `meta` distillation MUST have ≥1 entry per pair of model-family distillations in `disagreements_flagged`.

---

### `audit-finding` — Phase 7 fresh-eyes finding

**Public ref pattern:** `AF-NNN`

**Required fields:**

```yaml
severity: critical | high | medium | low
target_artifact: <file path or bead id>
recommendation: <what to fix>
by_pane: <pane id>
prompt_used: 1 | 2 | 3   # which of the trio fired this finding
session: <session id>
```

**State machine:** `open → addressed | deferred`.

**Invariants:**

- `severity=critical` findings MUST be addressed before Phase 7 exits.
- `severity=high` findings deferred MUST have a recorded reason.

---

## Field Grammar

In bead descriptions, structured fields use this grammar:

```
<key>: <value>          # single-line value
<key>:                  # multi-line block
  <line 1>
  <line 2>
<key>: [<v1>, <v2>]     # list value (comma-separated, square-bracketed)
```

The audit script `scripts/audit-bead-invariants.sh` parses with this grammar; deviating breaks audits silently. Stick to it.

Multi-line markdown sections (e.g. `## Detail`, `## Excerpts`) come *after* the `key: value` block.

---

## Common Queries (jq cookbook)

```bash
# All active hypotheses
br list --label=hypothesis --status=open --json | jq '.issues[]?'

# Find hypotheses missing falsifier (invariant violation)
br list --label=hypothesis --json | \
  jq '.issues[]? | select((.description // "") | contains("falsifier:") | not) | .id'

# Hypotheses that survived debate
br list --label=hypothesis --json | \
  jq '.issues[]? | select((.description // "") | contains("state: confirmed")) | .id'

# Evidence packs per hypothesis
br list --label=evidence --json | \
  jq '[.issues[]? | {id, supports: (((.description // "") | capture("supports: \\[(?<supports>.*?)\\]")? | .supports) // "")}]'

# Anomalies clustered (for ΔE check)
br list --label=anomaly --json | \
  jq '[.issues[]? | {id, cluster: (((.description // "") | capture("cluster_with: \\[(?<cluster>.*?)\\]")? | .cluster) // "")}]'

# Open audit findings exiting Phase 7
br list --label=audit-finding --status=open --json | \
  jq '.issues[]? | {id, severity: (((.description // "") | capture("severity: (?<severity>\\w+)")? | .severity) // "unknown")}'
```

---

## Initialization Script (executed by `bootstrap-session.sh`)

```bash
br init --prefix=bb

# Seed labels (these are advisory; `br` doesn't enforce label registry)
for L in q-of-record hypothesis evidence test assumption anomaly critique debate distillation audit-finding; do
  echo "Label seeded: $L"
done

# Optional: seed Q-001. Keep Q-001 as the public ref and capture the actual br id.
q_ref="Q-001"
q_id="$(br create "$q_ref: <question goes here>" \
  --type=question --labels=q-of-record --priority=0 \
  --slug="$q_ref" --external-ref="$q_ref" --silent \
  --description="...")"
printf 'created %s as %s\n' "$q_ref" "$q_id"
```

After every phase: `br sync --flush-only && git add .beads/ && git commit -m "Phase N: ..."`.
