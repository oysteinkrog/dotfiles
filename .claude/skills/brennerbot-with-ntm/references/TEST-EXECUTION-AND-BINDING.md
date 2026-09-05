# TEST-EXECUTION-AND-BINDING.md — Running Tests + Binding Results to Hypotheses

<!-- TOC: Why test execution discipline | The 5 test states | The execute → bind → suggest-kills workflow | Potency-pass / potency-fail | Matched / violated / uncalled bindings | Per-test-result side effects | Auto-suggested kills | Per-phase test activity | Anti-patterns | Cross-references -->

A discriminative test produces evidence; evidence binds to hypotheses; hypotheses change state. Without disciplined binding, evidence stays "general" and never updates H states — the kill_rate stays low (per FAILURE-MODE-ANALYTICS.md pattern P-2).

This file specifies the test execution lifecycle, the binding semantics (matched / violated / uncalled), and the auto-suggest-kills feature.

Mined from `/dp/brenner_bot/README.md § Test Management` and `experiment_capture_protocol_v0.1.md`.

---

## Why test execution discipline

Three failures of ad-hoc test execution:

1. **Tests run without recording** — "we tried it" without artifact trail; replay impossible
2. **Results bind to "evidence pack" generically** — without per-H bindings, evidence doesn't kill anything
3. **Potency check missing** — we can't distinguish "no effect" from "assay failed"

Three benefits of disciplined execution:

1. **Stable test states** — designed → pending → in_progress → completed
2. **Per-H bindings** — `--matched H-001` says "this test result matches H-001's prediction"
3. **Potency check mandatory** — every executed test confirms the assay worked

---

## The 5 test states

| State | Description |
|-------|-------------|
| `designed` | Specified but not yet run; predictions per H listed |
| `pending` | Queued for execution; awaiting investigator availability |
| `in_progress` | Currently running |
| `completed` | Finished; outcome + bindings recorded |
| `blocked` | Cannot proceed (assumption falsified, infrastructure missing, etc.) |

State transitions:
```
designed → pending → in_progress → completed
                                  ↘ blocked → (re-design or abandon)
```

A test in `blocked` state must transition out (back to `designed` or to abandoned) before Phase 8 freeze.

---

## The execute → bind → suggest-kills workflow

### Step 1: Execute

```bash
brenner test execute T-RS20260301-001 \
  --result "Random fate assignment observed" \
  --potency-pass \
  --confidence high \
  --by GreenCastle \
  --notes "n=15 embryos, p<0.001"
```

This:
- Transitions T-NNN.state from `pending` → `completed`
- Records the result string
- Records `potency_check: pass` (or `fail`)
- Records confidence level
- Records by (sender) and notes

### Step 2: Bind to hypotheses

For each H the test was designed to discriminate:

```bash
brenner test bind T-RS20260301-001 H-RS20260301-002 --matched \
  --reason "Result consistent with prediction" \
  --by GreenCastle

brenner test bind T-RS20260301-001 H-RS20260301-001 --violated \
  --reason "Gradient model predicted no fate change" \
  --by GreenCastle
```

Each binding records:
- The H affected
- The match-state (matched / violated / uncalled)
- The reason
- The binding agent

### Step 3: Auto-suggest kills

```bash
brenner test suggest-kills T-RS20260301-001 --confidence high
```

Output:

```
T-RS20260301-001 (potency: pass, confidence: high)

Suggested kills:
  H-RS20260301-001 (violated, reason: "gradient model predicted no fate change")
  H-RS20260301-005 (violated, reason: "static-determination model predicted invariant fate")

Suggested validations:
  H-RS20260301-002 (matched + 2 prior matched results = strong support)
```

The system suggests; the operator decides. Per Phase 5 cross-exam, the adjudicator either accepts the suggestion or files a critique explaining why not.

---

## Potency-pass / potency-fail

The potency check is **mandatory** for every executed test. It distinguishes:

- **`potency-pass`**: positive control confirms the assay worked. The negative result is meaningful.
- **`potency-fail`**: positive control failed. The result is uninterpretable; the test must be re-run.

Without potency check, "no effect" could mean:
- The hypothesis is wrong (genuine negative)
- The assay broke (false negative)
- The system was in the wrong state

The potency check disambiguates.

Per `/dp/brenner_bot/README.md`:
> Potency checks are mandatory — they distinguish "no effect" from "assay failed." Use `--potency-pass` or `--potency-fail` to record the potency check result.

---

## Matched / violated / uncalled bindings

Three binding states per H:

| Binding | Meaning | Effect on H |
|---------|---------|-------------|
| `matched` | Observed outcome matches H's prediction | +confidence; kill candidate suggestion (rare) |
| `violated` | Observed outcome contradicts H's prediction | suggested for kill via `under_attack` → `killed` |
| `uncalled` | Observed outcome doesn't decisively match either way | no state change; tracked as inconclusive |

The binding is **per H**. A test discriminating H-001 vs H-002 vs H-003:

```
Test result: "growth observed at threshold X"
H-001 predicted: "growth at X" → binding: matched
H-002 predicted: "no growth at X" → binding: violated
H-003 predicted: "growth only above 2X" → binding: violated
```

This pattern (one matched, two violated) is decisive — H-001 wins this test.

---

## Per-test-result side effects

Per /dp/brenner_bot/README.md, the `kill` event for an H has cascade side effects:

When `T-NNN.bind H-NNN --violated` is followed by an explicit `H-NNN.kill`:

| Side effect | What happens |
|-------------|--------------|
| H state | active or under_attack → killed |
| H.kill_reason | Recorded with citation to T-NNN |
| H.refuted_by | List of T-NNN that fired the falsifier |
| Arena update | If H is in arena: status `eliminated` |
| Per H in arena | Recompute matrix scores |
| Critique cascade | If H supports other Hs (auxiliary), they may transition under_attack |

Per HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md: this cascade is the FSM's `kill` event.

For `assumption_undermined`: when a test result violates an A-NNN that supports H, H transitions to `assumption_undermined` (not directly killed). The cascade differs.

---

## Auto-suggested kills

The `suggest-kills` command surfaces opportunity:

```
For each H bound `violated` to a `completed` test with `potency-pass` and `confidence: high`:
  Suggest: kill H with reason linking to T-NNN
For each H bound `matched` to ≥3 `completed` tests with `potency-pass`:
  Suggest: validate H
```

The threshold (`≥3 matched + potency-pass + high confidence`) prevents single-test validation, which is unsafe.

Operators can override:

```bash
# Decline suggested kill:
brenner critique create \
  --target H-RS20260301-001 \
  --attack "T-001 violated H-001, but T-001's potency was marginal; recommend re-run before kill" \
  --severity moderate
```

Per TRIBUNAL-AND-OBJECTION-REGISTER.md, the critique blocks the kill until resolved.

---

## Per-phase test activity

| Phase | Test activity |
|-------|---------------------|
| 3 hypothesis | T beads in `designed` state; per-H predictions populated |
| 4 investigation | T transitions `pending` → `in_progress` → `completed`; bindings recorded; suggest-kills surfaced |
| 5 cross-exam | Adjudicator reviews bindings; H state transitions executed |
| 6 distillation | Test results aggregate per family-distillation |
| 7 audit | Verify potency-checks pass; check binding consistency |
| 8 freeze | Tests locked; future re-runs require new T-NNN |
| 9 handback | HANDBACK § Verdict cites decisive test bindings |

---

## CLI reference

```bash
# List tests for a session:
brenner test list --session-id RS-...

# Show test details:
brenner test show T-RS-...-001

# Execute (records result + potency):
brenner test execute T-RS-...-001 \
  --result "<observation>" \
  --potency-pass \
  --confidence <low|medium|high> \
  --by <agent> \
  --notes "<details>"

# Bind result to a hypothesis:
brenner test bind T-RS-...-001 H-RS-...-NNN \
  --matched | --violated | --uncalled \
  --reason "<rationale>" \
  --by <agent>

# Suggest kills based on bindings:
brenner test suggest-kills T-RS-...-001 --confidence <threshold>
```

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Execute test without `--potency-pass` or `--potency-fail` | Lint rejects; assay-failure invisible |
| Bind result to "the session" not to specific Hs | Per-H state can't update; kill_rate stays low |
| Bind to one H but not the others the test was designed for | Other Hs miss their state-update opportunity |
| Use `--matched` and `--violated` for same H (different rounds) | Different test runs need different T-NNN |
| Suggest-kills without threshold (`--confidence low`) | False-positive kills; high audit-finding rate |
| Manual H.kill without binding-to-T citation | Per HYPOTHESIS-LIFECYCLE: kill_reason must cite |
| Re-execute completed test without new T-NNN | History lost; per AGENTS.md no-deletion |
| Skip uncalled binding | Inconclusive results matter for audit; record them |
| `potency-fail` without re-running | Test result is uninterpretable; can't bind |

---

## Composition with brennerbot

Test execution + binding integrates with:

- **Hypothesis Lifecycle FSM** (per HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md): bind triggers transitions
- **Hypothesis Arena** (per HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md): binding feeds matrix scores
- **Prediction Lock** (per PREDICTION-LOCK-CRYPTOGRAPHIC.md): test result `reveals` locked predictions
- **Failure-mode analytics** (per FAILURE-MODE-ANALYTICS.md): kill_rate driven by binding discipline
- **Beads** (per BEADS-SCHEMA.md): T-NNN bead schema includes binding fields
- **Linter** (per ARTIFACT-LINTER-RULES.md): potency-check rule WT-001

---

## Cross-references

- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — kill event tied to binding
- [HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md](HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md) — bindings feed matrix
- [PREDICTION-LOCK-CRYPTOGRAPHIC.md](PREDICTION-LOCK-CRYPTOGRAPHIC.md) — reveal on test execution
- [DISCRIMINATIVE-TEST-DESIGN.md](DISCRIMINATIVE-TEST-DESIGN.md) — pre-execution design protocol
- [FAILURE-MODE-ANALYTICS.md](FAILURE-MODE-ANALYTICS.md) — pattern P-2 (test-design weakness)
- [TAXONOMIES-COMPLETE-CATALOG.md](TAXONOMIES-COMPLETE-CATALOG.md) — test enums
- [ARTIFACT-LINTER-RULES.md](ARTIFACT-LINTER-RULES.md) — WT-001 potency check
- /dp/brenner_bot/README.md § Test Management — original source
- /dp/brenner_bot/specs/experiment_capture_protocol_v0.1.md — capture protocol
