# DISCRIMINATIVE-TEST-DESIGN.md — Designing Decision Experiments

<!-- TOC: Why discriminative testing | The decision-experiment pattern | KL divergence as the optimization target | The 7-step design protocol | Cost-benefit ranking | Per-archetype emphases | Quickie pilot vs flagship | Anti-patterns | Composition with operators | Cross-references -->

Brenner's signature move: design a test that *eliminates whole families of explanations at once*. This is the single highest-leverage activity in the entire methodology — a well-designed discriminative test scores 10× the information of a naive observation.

This file is the formal design protocol.

Mined from `/dp/brenner_bot/specs/operator_library_v0.1.md`, `/dp/brenner_bot/README.md § Decision Experiment`, and the GPT-5.2 metaprompt's "Step D — Discriminative tests / decision experiments."

---

## Why discriminative testing

Without discriminative discipline:

- Every Phase 4 round produces evidence; few rounds *eliminate* hypotheses
- kill_rate stays low; add_rate stays high (per F-403 confirmation bias)
- Phase 5 debates devolve into rhetoric (per F-503)
- The session converges on whichever H had the most patient advocate

With discriminative discipline:

- Each EV is designed to *kill* hypothesis space
- Phase 4 converges quickly (kill_rate ≥ add_rate)
- Phase 5 verdicts are evidence-grounded
- The session converges on the H that survived the most rigorous tests

---

## The decision-experiment pattern

A decision experiment has the following structure:

```
Hypothesis space: {H1, H2, H3, ...}
Test: T_n
For each H:
  P(observation | H) = <prediction>
The test is "discriminative" if and only if:
  ≥1 pair of H gives substantially different P(observation | H)
```

The "substantially different" threshold determines test value (per BAYESIAN-FRAMEWORK.md KL divergence).

**Practical rule:** if you can predict the same outcome under all candidate Hs, the test is NOT discriminative. Skip it.

**Practical rule:** if exactly ONE H predicts a unique outcome, the test is decisive (max KL): the outcome confirms or refutes that H against all others.

---

## KL divergence as the optimization target

Per BAYESIAN-FRAMEWORK.md, the test's information value is:

```
EIG(T) = E_x[ KL(P(H | x) || P(H)) ]
```

Where:
- `x` is the test outcome
- `P(H | x)` is the posterior over hypotheses given outcome `x`
- `P(H)` is the prior

In practice, you don't compute KL literally. You estimate qualitatively:

| Test category | Qualitative KL | Action |
|---------------|----------------|--------|
| All Hs predict same outcome | ~0 | skip — not discriminative |
| Two Hs predict same outcome (vs others) | low | partial; sometimes worth running |
| Each H predicts a different outcome | high | run; each outcome distinguishes one H |
| One H predicts a forbidden pattern | very high | a single observation refutes that H |

Aim for tests in the bottom half of the table.

---

## The 7-step design protocol

When the operator dispatches `MO-04a-investigate.md` for an H, the Investigator should follow this protocol:

### Step 1: Enumerate the hypothesis space

Don't design a test for one H in isolation. Enumerate:

```
Active hypotheses: H1, H2, H3, [third_alternative H4]
```

If only one H is being tested, the test isn't discriminative — it's confirmatory. Per F-403.

### Step 2: List each H's prediction under candidate observations

For each candidate observation, derive what each H predicts:

| Observation | P(obs \| H1) | P(obs \| H2) | P(obs \| H3) | P(obs \| H4) |
|-------------|-------------|-------------|-------------|-------------|
| obs_a | 0.9 | 0.1 | 0.5 | 0.5 |
| obs_b | 0.1 | 0.9 | 0.5 | 0.5 |
| obs_c | 0.5 | 0.5 | 0.9 | 0.1 |

A perfect discriminator would be one where each row has exactly one high probability.

### Step 3: Identify forbidden patterns

For each H, what observation is *forbidden* under that H? (per BRENNER-VOCABULARY.md "Forbidden pattern")

If H1 forbids `obs_a`, then observing `obs_a` refutes H1 with single-shot certainty (max KL).

Tests that fire forbidden patterns are the highest-leverage tests.

### Step 4: Apply digital-handle filter

Per BRENNER-VOCABULARY.md "Digital handle" + TEN-PRINCIPLES.md #3:

- Can the outcome be reliably classified as "yes/no" or "regime A / regime B" without statistics?
- If yes → digital handle; high-quality test
- If no → continuous variable; statistical test required; lower quality

Prefer digital handles when possible. Per `MO-quickie-pilot.md`.

### Step 5: Apply ⊞ Scale-Check

For each candidate test:

- Does the test's expected magnitude exceed measurement noise floor?
- Are physical/scale constraints satisfied (per ⊞)?
- Is the test physically possible at our scale?

Per AE-7.7 (in PHASE-7-ANTI-EXAMPLES.md): tests that violate scale-physics fail before being run.

### Step 6: Apply 🔧 DIY filter

For each candidate test:

- Can we run this with current infrastructure?
- Does the cost / effort scale with our budget?
- If we wait 2 weeks for new tooling, do we still need the answer?

Prefer tests that can run *now* with crude apparatus. Per TEN-PRINCIPLES.md #6.

### Step 7: Rank by cost-benefit

Per BAYESIAN-FRAMEWORK.md objective function:

```
Score(T) = (Expected Information Gain × Downstream Leverage) /
           (Time × Cost × Ambiguity × Infrastructure-Dependence)
```

Rank candidate tests; dispatch the highest-scoring first.

---

## Cost-benefit ranking

For ≥3 candidate tests, build the ranking table:

| Test | Predicted KL | Time (h) | Cost ($) | Ambiguity | Infrastructure | Score |
|------|--------------|----------|----------|-----------|----------------|-------|
| T1 (microbenchmark) | 0.8 | 0.5 | 0 | low | none | 1.6 |
| T2 (full prod test) | 0.9 | 8 | 100 | low | high | 0.011 |
| T3 (formal proof) | 1.0 | 40 | 0 | very low | medium | 0.025 |

Run T1 first (highest score). If T1 inconclusive, escalate to T3 (next-highest). T2 is dominated; skip unless T1 and T3 both fail.

This is the "quickie pilot first" pattern (per `MO-quickie-pilot.md`).

---

## Per-archetype emphases

| Archetype | Test design emphasis |
|-----------|----------------------|
| A1 design-space | Each design candidate predicts different scaling behavior; test at 10× scale |
| A2 codebase | Each H predicts different file:line code path; instrument the path |
| A3 methodology | Each method predicts different metric on benchmark; replicate per MO-academic-replication.md |
| A4 incident | Each cause predicts different signature in logs; correlate timestamps |
| A6 adversarial | Each attack predicts different observable side-effect; instrument the side-effect |
| A7 decision | Each option predicts different outcome at decision horizon; pre-register |

The general pattern: per-H *unique* prediction; instrument the unique observable; observe.

---

## Quickie pilot vs flagship

Per `MO-quickie-pilot.md`:

### Quickie pilot

- Cost: ≤30 min wall-time, ≤10k tokens
- Goal: cheap rough discrimination — does the basic prediction hold?
- Outcome: "yes" → likely H; "no" → suspect H; "unclear" → flagship needed
- Use first; high cost-benefit ratio

### Flagship

- Cost: 1-3h+ wall-time, ≥50k tokens, possibly external resources
- Goal: rigorous discrimination — fire the falsifier under specific regime
- Outcome: H state transition (per `MO-falsifier-fired.md`) or refined falsifier
- Use second, only when quickie inconclusive

The pattern: quickie filters cheaply; flagship resolves rigorously. Most quickies are decisive; few flagships needed.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Design test for one H without comparing to others | Not discriminative; per F-403 |
| Run flagship first | Burns budget; quickies often decisive (per MO-quickie-pilot) |
| Use continuous variable when digital handle exists | Statistical noise; weaker test (per principle #3) |
| Skip the prediction table | Without per-H predictions, you don't know what would discriminate |
| Test at unit scale when production scale is what matters | Scale-physics mismatch (per ⊞) |
| Pick test by ease ("we have these tools available") | Sometimes the right test requires DIY (per principle #6) |
| Run all tests in parallel | Sequential cost-benefit ordering captures dominated tests |
| Forget to update H state after definitive test result | The test was meaningless if state doesn't transition (per F-401) |

---

## Composition with operators

| Step | Operator most active |
|------|----------------------|
| 1 enumerate hypothesis space | ⊘ Level-Split (ensure third-alt) |
| 2 list predictions per H | ⌂ Materialize |
| 3 identify forbidden patterns | ✂ Exclusion-Test |
| 4 digital handle filter | ⊞ Scale-Check |
| 5 scale check | ⊞ Scale-Check |
| 6 DIY filter | 🔧 DIY |
| 7 cost-benefit rank | (objective function from BAYESIAN-FRAMEWORK) |

The 7-step protocol IS an applied composition of the operator algebra.

---

## Validation: was the test discriminative?

After running:

```
Did exactly one H change state? → high-quality discriminator (success)
Did multiple H change state? → unclear; design issue
Did no H change state? → not discriminative (skip future similar tests)
Did all H change state same direction? → confirmatory, not discriminative (F-403)
```

Per Phase 7 audit: count the kill_rate vs add_rate per investigator. Investigators who consistently produce add_rate without kill_rate are likely designing non-discriminative tests.

Per OPERATOR-CALIBRATION-LOG.md: track per-operator discriminative-test-design quality.

---

## When the framework breaks

Sometimes hypothesis predictions are *fundamentally underspecified* — even with the best test design, all candidate Hs predict the same outcome. This is a Phase 1 framing issue:

- The hypothesis space lacks distinct mechanisms (per ⊘ Level-Split failure)
- The Hs are restatements of the same idea (per F-302 hypothesis duplication)
- The question is genuinely under-determined

In each case, return to Phase 1 — the question shape is wrong.

---

## Cross-references

- [BAYESIAN-FRAMEWORK.md](BAYESIAN-FRAMEWORK.md) — KL divergence math
- [BRENNER-VOCABULARY.md](BRENNER-VOCABULARY.md) — decision experiment, digital handle, forbidden pattern
- [TEN-PRINCIPLES.md](TEN-PRINCIPLES.md) — principles 3 (digital), 5 (materialize), 6 (DIY)
- [OPERATORS.md](OPERATORS.md) — ✂ Exclusion-Test, ⌂ Materialize, ⊞ Scale-Check
- [MO-quickie-pilot.md](../assets/marching-orders/MO-quickie-pilot.md) — cheap-first protocol
- [MO-falsifier-fired.md](../assets/marching-orders/MO-falsifier-fired.md) — H state transition discipline
- [ARTIFACT-7-SECTION-SCHEMA.md](ARTIFACT-7-SECTION-SCHEMA.md) — Section 4 holds these tests
- /dp/brenner_bot/specs/operator_library_v0.1.md — formal operator definitions
- /dp/brenner_bot/specs/artifact_schema_v0.1.md — Discriminative Tests section schema
