# BAYESIAN-FRAMEWORK.md — Brenner's Implicit Bayesianism

<!-- TOC: Why this matters | The Brenner-to-Bayesian mapping | The objective function | The loss function | The posterior update | When Brenner-style differs from naive Bayesian | Per-phase Bayesian application | KL divergence and decision experiments | Per-operator Bayesian semantics | Anti-patterns | Cross-references -->

Brenner never used formal probability theory, but his reasoning maps precisely onto Bayesian operations. The mapping is so clean that codifying it lets brennerbot make the implicit explicit — and explicit Bayesianism scores discriminative tests, weights evidence, and adjudicates debates more cleanly than vibes-based reasoning.

This file is the formal Bayesian framework underneath the operator algebra.

Mined from `/dp/brenner_bot/README.md § The Implicit Bayesianism` and triangulated against the three expert distillations.

---

## Why this matters

Operators face decisions throughout the session that are *fundamentally probabilistic*: which H to investigate first, how much weight to give an EV, when to declare convergence, when to flip an H state. Without an explicit Bayesian frame, these become "operator gut feel" — irreproducible across operators, hard to audit.

With this framework:

1. **Evidence weighting** (per EVIDENCE-WEIGHTING-TAXONOMY.md) becomes posterior-update math
2. **H state transitions** map to threshold-crossing in posterior probability
3. **Test design** maximizes KL divergence between hypothesis posteriors
4. **Phase-7 audit** verifies the operator's implicit priors weren't biased

---

## The Brenner-to-Bayesian mapping

| Brenner Move | Bayesian Operation |
|--------------|---------------------|
| Enumerate ≥3 models before experimenting | Maintain explicit prior distribution |
| Hunt paradoxes | Find high-probability contradictions in posterior |
| "Third alternative: both wrong" | Reserve probability mass for misspecification |
| Design forbidden patterns | Maximize expected information gain (KL divergence) |
| Seven-cycle log paper | Choose experiments with extreme likelihood ratios |
| Choose organism for decisive test | Modify data-generating process to separate likelihoods |
| "House of cards" theories | Interlocking constraints (posterior ≈ product of likelihoods) |
| Exception quarantine | Model anomalies as typed mixture components |
| "Don't Worry" hypothesis | Marginalize over latent mechanisms (explicitly labeled) |
| Kill theories early | Update aggressively; avoid sunk-cost fallacy |
| Scale/physics constraints | Use strong physical priors to prune before experimenting |
| Productive ignorance | Avoid over-tight priors that collapse hypothesis space |

This is not metaphor — each row is a literal mathematical correspondence.

---

## The objective function

Brenner was implicitly maximizing:

```
                Expected Information Gain × Downstream Leverage
Score(E) = ─────────────────────────────────────────────────────────
              Time × Cost × Ambiguity × Infrastructure-Dependence
```

Where:
- **Expected Information Gain** = expected KL divergence between prior and posterior after observing E (i.e., how much E discriminates between hypotheses)
- **Downstream Leverage** = expected impact of the answer on subsequent decisions (per CONFIDENCE-SCORING.md)
- **Time** = wall-time to run the test
- **Cost** = compute / token / quota cost
- **Ambiguity** = expected residual uncertainty even after E
- **Infrastructure-Dependence** = how much new tooling the test requires

His genius was making the *denominator* small (DIY, clever design, digital handles) while keeping the *numerator* large (exclusion tests, paradox resolution). The compounding ratio is what makes his methods so productive.

**In brennerbot:** every dispatch decision should implicitly score against this. The Decision Tree's tick-time choices ARE this scoring being applied. The MO library's tick-cadence advice optimizes for this ratio.

---

## The loss function

When the operator must choose between dispatches, the loss function is:

```
Loss(dispatch) = - Score(expected_evidence) + Cost
```

Where:
- `Score` is the objective function above
- `Cost` includes wall-time, token, and operator-attention budgets

Per WALL-TIME-BUDGET.md and COST-AWARE-EXECUTION.md: the cost terms aren't optional even when budget feels infinite.

**In brennerbot:** the per-phase budgets are loss-bounding. Phase 4 budget = 50% of total tells you "no single Phase 4 round can spend more than Phase 4 budget / N rounds."

---

## The posterior update

For an H bead, the posterior probability of being correct after observing EV evidence:

```
P(H | EV) ∝ P(EV | H) × P(H)
```

In brennerbot's W-axis framework (per EVIDENCE-WEIGHTING-TAXONOMY.md):

- `P(H)` (prior) = operator's pre-evidence confidence (low/medium/high)
- `P(EV | H)` (likelihood) ≈ W_composite of the EV (the higher W, the more confident the EV's evidential weight)
- `P(H | EV)` (posterior) = updated confidence per CONFIDENCE-SCORING.md aggregation rules

The aggregate over multiple EVs:

```
P(H | EV_1, EV_2, ..., EV_N) ∝ P(H) × ∏_i P(EV_i | H)
```

Which in W-space (per EVIDENCE-WEIGHTING-TAXONOMY.md `H_strength_after`):

```
H_strength_after ≈ ∏_i (1 + W_supporting_i) / ∏_j (1 + W_refuting_j)
```

(Or the simpler additive form per CONFIDENCE-SCORING.md.)

**In brennerbot:** `scripts/score-ev.sh` computes per-EV W. The operator (or scripts/explain-decision.sh) aggregates per-H.

---

## When Brenner-style differs from naive Bayesian

Brenner-style Bayesianism deliberately diverges from textbook Bayesianism in several ways:

### 1. Reserve probability mass for misspecification

Naive Bayesian: prior over the *complete* hypothesis space. If your hypothesis space is `{H1, H2}`, then `P(H1) + P(H2) = 1`.

Brenner-style: always reserve mass for "neither H1 nor H2 — the model is wrong." Per the third-alternative discipline. The hypothesis space is `{H1, H2, third-alternative}` minimum.

**Implementation:** Phase 3 mandates ≥1 H with `origin: third_alternative` (per F-301).

### 2. Aggressive likelihood updates

Naive Bayesian: small evidence → small posterior shift.

Brenner-style: certain evidence types are "mass-killing" — a single forbidden-pattern observation moves a hypothesis from active to refuted. Per ✂ Exclusion-Test.

**Implementation:** EV beads with `refutes:[H-NNN]` and high W_composite trigger immediate H state transitions per `MO-falsifier-fired.md`.

### 3. Calculation-prior dominance

Naive Bayesian: priors are subjective.

Brenner-style: certain priors come from *physical calculation* — they're not subjective, they're constraints. ⊞ Scale-Check assigns probability ~0 to physically impossible hypotheses regardless of how much "evidence" suggests them.

**Implementation:** assumption beads with `type:scale_physics` provide hard prior constraints; H beads incompatible with verified scale-physics assumptions get auto-refuted at Phase 7 audit.

### 4. Productive ignorance as flat prior

Naive Bayesian: use the best prior available.

Brenner-style: in some pane roles, *deliberately use a flat prior* (per ⊙ Productive-Ignorance). Ignore corpus prior. The flat-prior pane often surfaces hypotheses the consensus-prior panes missed.

**Implementation:** ⊙ pane onboarding restricts corpus access; its hypotheses are tagged `prior: uniform`.

### 5. Don't Worry as marginalization

Naive Bayesian: include all latent variables in the joint.

Brenner-style: explicitly mark some latent variables as "don't worry — assume they exist." This is *labeled marginalization* — we're not computing the integral, we're making the abstraction explicit.

**Implementation:** assumption beads with `type:dont_worry` document the latent variable + the test that would falsify the assumption.

---

## Per-phase Bayesian application

| Phase | Bayesian operation |
|-------|---------------------|
| 1 framing | Define hypothesis space S; reserve mass for "S is wrong" (third-alternative) |
| 3 hypotheses | Enumerate explicit prior `P(H_i)` per H; spread mass per ⊙ for some pane |
| 4 investigation | Per-EV likelihood update `P(EV | H)`; aggregate per-H posterior |
| 5 debate | Adjudicator scores: which H has higher posterior given combined evidence |
| 6 distillation | Per-family marginal `P(H | EV) marginalized over family-bias` |
| 7 audit | Verify priors weren't biased (per F-403); scale-physics-prior audit |
| 9 handback | Posterior + caveats; what would change the verdict |

---

## KL divergence and decision experiments

A "decision experiment" (per BRENNER-VOCABULARY.md) maximizes:

```
KL(P(H | EV) || P(H))   over all candidate EV designs
```

Where `KL` is the Kullback-Leibler divergence between posterior and prior. Higher KL = more information from the evidence = better discriminator.

Practically:

- **Low-KL evidence:** "EV tells us roughly the same as we already knew" → skip; not worth the cost
- **High-KL evidence:** "EV would dramatically shift our beliefs" → priority dispatch
- **Asymmetric KL:** different scenarios have very different posteriors → run the test (decisive)
- **Symmetric KL:** all scenarios equally likely after the test → not a decision experiment; redesign

**In brennerbot:** `MO-quickie-pilot.md` is for cheap high-KL probes; flagship investigations follow when the cheap probe doesn't suffice.

---

## Per-operator Bayesian semantics

Each operator in OPERATORS.md has a Bayesian interpretation:

| Operator | Bayesian semantics |
|----------|---------------------|
| ◊ Paradox-Hunt | Find low-posterior states under current model = strong update signal |
| ⊘ Level-Split | Distinguish hypothesis spaces (level-1 vs level-2 are different parameter spaces) |
| 𝓛 Recode | Change parameterization; same probability mass, different observable |
| ≡ Invariant-Extract | Find conditional independence; reduces parameter count |
| ✂ Exclusion-Test | Maximize KL divergence per test |
| ⟂ Object-Transpose | Modify data-generating process to separate likelihoods |
| ↑ Amplify | Push the system to regime where likelihoods diverge maximally |
| ⌂ Materialize | Compile latent prediction into observable likelihood |
| 🔧 DIY | Reduce experimental cost to enable more updates per budget |
| ⊞ Scale-Check | Apply physical priors as hard constraints (≈0 mass on impossible) |
| 🤝 GAN | Adversarial training: discriminator probes likelihood ratios |
| ΔE Exception-Quarantine | Mixture-model the anomalies; don't pollute mainstream H |
| † Theory-Kill | Aggressive update; avoid sunk-cost fallacy |
| ∿ Dephase | Avoid local-optimum priors (consensus = local mode) |
| ⊙ Productive-Ignorance | Use flat prior; don't let corpus constrain hypothesis space |

These mappings make explicit the math that the operator algebra implicitly performs.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| "Bayesian reasoning is too formal for our session" | The operators ARE Bayesian operations whether you label them or not |
| Compute literal posteriors via `python3 -c 'pymc...'` | Overkill; the W-axis framework approximates correctly |
| Skip third-alternative because "we know it's H1 or H2" | Reserve probability mass for misspecification — always |
| Use physical-impossibility hypotheses to "spread the prior" | ⊞ Scale-Check assigns 0 mass; don't include in slate |
| Ignore likelihood ratio when designing tests | KL maximization is the optimal test design objective |
| Update H state without recomputing W aggregate | The state transition IS the posterior update; do the math |
| Forget "Don't Worry" implies marginalization | Latent variables don't disappear; they're integrated over |

---

## Calibration loop

Per OPERATOR-CALIBRATION-LOG.md, track:

- For each Phase 8 freeze, record predicted H states + their posterior probabilities
- After 30 days, check: did high-posterior Hs hold up? Did low-posterior Hs get refuted?
- Calibration error = |predicted P - empirical P|

Operators with persistently miscalibrated priors get coaching (per `subagents/calibration-coach.md`).

---

## When the framework breaks down

The Bayesian framework assumes:
1. The hypothesis space is finite (or at least compact)
2. Likelihoods are computable
3. Priors are coherent

When these fail:
- **Infinite hypothesis space** (e.g., "any architecture") — frame more narrowly OR use ⊙ pane to flat-prior the space
- **Likelihoods uncomputable** — use surrogate (W-axis) per EVIDENCE-WEIGHTING-TAXONOMY.md
- **Incoherent priors** (different panes assign different priors to same H) — surface as Phase 6 disagreement; reconcile via meta-synthesis

The framework is robust to *approximate* application. Don't treat it as a strait-jacket.

---

## Cross-references

- [EVIDENCE-WEIGHTING-TAXONOMY.md](EVIDENCE-WEIGHTING-TAXONOMY.md) — W-axis approximation of likelihoods
- [CONFIDENCE-SCORING.md](CONFIDENCE-SCORING.md) — H confidence rubric (posterior thresholds)
- [TEN-PRINCIPLES.md](TEN-PRINCIPLES.md) — principles 4-8 are explicit Bayesianism
- [DISCRIMINATIVE-TEST-DESIGN.md](DISCRIMINATIVE-TEST-DESIGN.md) — KL-divergence-driven test design
- [METRICS.md](METRICS.md) — session quality metrics including calibration
- [scripts/score-ev.sh](../scripts/score-ev.sh) — W aggregation
- /dp/brenner_bot/README.md § The Implicit Bayesianism — original source
