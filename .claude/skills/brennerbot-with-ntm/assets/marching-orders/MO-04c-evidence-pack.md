# MO-04c-evidence-pack.md — Per-Hypothesis Evidence Pack Template

This is **not a marching order** — it's the *artifact template* the Investigator fills (rendered by `scripts/render-evidence-pack.sh` from EV beads). Every `evidence/packs/EV-pack-H-NNN.md` follows this template.

**Parameters:** `<H_ID>`

---

```markdown
# Evidence Pack — <H_ID>

**Hypothesis claim:** <claim from H bead>
**Mechanism:** <mechanism>
**Falsifier:** <falsifier>
**Expected evidence:** <expected_evidence>
**Category:** <category>
**Origin:** <origin>
**Confidence (current):** <confidence>
**State (current):** <state>

---

## Methodology

### Proxy choice (⟂ Object-Transpose)
<which surface was investigated and why>

### Amplification (↑)
<which signal is being measured and why it's high-contrast>

### Materialization log (⌂)
<what was searched for and what was found>

### Falsifier probe (✂)
<attempted falsifier search and result: fired | not fired | not yet probed>

---

## Evidence Records

### Supporting (count: N)

#### EV-001 — <one-line claim>
- **Type:** paper | experiment | observation | code_artifact
- **Source:** <URL | file:line | DOI>
- **Verified:** yes | no
- **Key findings:**
  - <invariant 1>
  - <invariant 2>
- **Excerpts:**
  - E1 (verbatim): "<exact quote>" (location: <section/line>)
  - E2 (paraphrase): "<paraphrase>" (location: <...>)

#### EV-005 — <next supporting record>
...

### Refuting (count: M — target ≥1 per round)

#### EV-007 — <counter-evidence claim>
- **Source:** <...>
- **Excerpts:**
  - E1: "<contradicting quote>"
- **Verdict:** <does this fire the falsifier? yes | no | partial>

### Informing (count: K — neither directly supporting nor refuting)

#### EV-011 — <context-setting claim>
...

---

## Assumption Ledger (claims this evidence pack rests on)

### A-001 — <assumption statement>
- **Type:** background | methodological | boundary | scale_physics
- **Status:** unchecked | challenged | verified | falsified
- **Calculation** (if scale_physics): <math>
- **Affects:** [<H_ID>]
- **Verified by:** <EV-NNN if applicable>

---

## Anomaly Register

### AN-001 — <observation that doesn't fit>
- **Conflicts with:** [<H_ID>, others?]
- **Source type:** experiment | literature | calculation
- **Cluster with:** [<other AN-NNN if pattern>]

---

## Critique Trail

### C-001 — Devil's-advocate attack on <H_ID>
- **Severity:** moderate
- **Attack:** <one-paragraph>
- **Status:** active | addressed | dismissed | accepted
- **Response (if addressed):** <Investigator's response>

---

## Round Log

### Round 1 (<timestamp>)
- Investigator: <pane-id> filed EV-001, EV-002, EV-003 (1 refutes, 2 supports)
- Falsifier probe: not fired
- Operators applied: ⟂, ↑, ⌂, ⊞

### Round 2 (<timestamp>)
- Devil's-advocate: <pane-id> filed C-001, EV-007 (counter-evidence)
- Investigator response: EV-008 (countering C-001)
- Adjudicator: not yet engaged
- ...

---

## Phase 5 Adjudication (if reached)

### DEBATE-NNN — <H_ID> vs <H-other>
- **Outcome:** <H_ID> = confirmed | refuted | superseded | deferred
- **Reasoning:** <citation-grounded paragraph>
- **Falsifier event (if any):** <verbatim>
- **Bead state changes:** ...

---

## Next-Action

If `state == active` at the end of investigation: list specific next investigation steps.
If `state == refuted`: cite the EV that fired the falsifier.
If `state == confirmed`: cite the DEBATE-NNN that settled it AND ≥2 independent EVs.
If `state == superseded`: cite the parent or replacement.
If `state == deferred`: explain why and what trigger would reopen.
```

---

## How this is rendered

`scripts/render-evidence-pack.sh <H_ID-or-public-ref>` resolves public refs like
`H-001` to the generated `br` id where needed, then queries:

```bash
h_ref="<H_ID>"
h_id="$(br list --all --json | jq -r --arg ref "$h_ref" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' | head -1)"
br show "$h_id" --json                                                # → header fields
br list --label=evidence --json | jq 'supports/refutes/informs filters'  # → EV records
br list --label=assumption --json | jq 'affects filter'              # → A records
br list --label=anomaly --json | jq 'conflicts_with filter'          # → AN records
br list --label=critique --json | jq 'target filter'                 # → C records
br list --label=debate --json | jq 'pair filter'                     # → DEBATE records
```

And populates the markdown template above. Investigator then edits prose narrative around the structured fields. The markdown is the single source of truth for Phase 6 distillation.

---

## Anti-patterns in evidence packs

| ✗ | Why |
|---|-----|
| Citing without verbatim excerpt | Future readers can't verify; claim drifts |
| Mixing `supports` and `refutes` for the same EV | Surface as anomaly or split into two beads |
| Round Log without timestamp | Can't reconstruct timeline; resume breaks |
| Empty Falsifier probe section | Anti-Brenner; F-403 |
| Evidence Records section without Methodology section | Methodology is the *why*; without it the EVs are floating |
| Phase 5 Adjudication section filled before Phase 5 ran | Premature — adjudication can only happen after debate |
