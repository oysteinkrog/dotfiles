# PREDICTION-LOCK-CRYPTOGRAPHIC.md — SHA-256 Sealed Pre-Registration

<!-- TOC: Why cryptographic pre-registration | The 4 lock states | The 5 prediction types | The lock workflow | Amendment tracking + integrity score | Robustness multiplier | When to lock | Per-phase prediction-lock activity | Anti-patterns | Cross-references -->

A central failure mode in research: **after observing evidence, predictions silently morph to fit it**. Operators (or panes) reinterpret what they "predicted" once they see what happened. Without enforcement, this turns "we predicted X" into "we predicted whatever happened, retroactively."

Brennerbot adds **cryptographic prediction lock** — a SHA-256 hash of the prediction text + timestamp, sealed *before* evidence is collected. Once locked, the prediction is immutable. Amendments are tracked separately and *penalized* in the integrity score.

This is unprecedented infrastructure for AI-driven research. It treats Brenner-style pre-registration as a verifiable cryptographic protocol, not a courtesy.

Mined from `/dp/brenner_bot/README.md § Prediction Lock System`.

---

## Why cryptographic pre-registration

Three failures of unsealed predictions:

1. **Hindsight bias** — once you see the result, "I predicted that" feels honest, but the actual prediction wasn't precise enough
2. **Goalpost drift** — over multiple rounds, predictions get progressively softer, until "we predicted there'd be some effect"
3. **No verification** — without cryptographic seal, claimed past predictions can't be distinguished from current rationalizations

Three benefits of cryptographic lock:

1. **Verifiable** — anyone with the hash can confirm the original prediction wasn't modified
2. **Drift-proof** — locked predictions can't morph; only amend (with penalty)
3. **Calibration honesty** — operators see when their pre-registered predictions actually held vs failed

---

## The 4 lock states

| State | Symbol | Description |
|-------|--------|-------------|
| `draft` | — | Freely editable, not yet committed |
| `locked` | 🔒 | SHA-256 sealed; immutable |
| `revealed` | 🔓 | Evidence collected; prediction compared to outcome |
| `amended` | ⚠️ | Modified after locking (flagged for integrity) |

Workflow:

```
Draft → Lock (SHA-256 hash) → Evidence Collection → Reveal → Compare
                                                       ↓
                                                 [Amendment] (if changed post-hoc)
```

Once `locked`, the prediction text is stored alongside its SHA-256 hash. Any modification after lock requires explicit `amend` operation — and the amendment is logged.

---

## The 5 prediction types

| Type | Description | Example |
|------|-------------|---------|
| `qualitative` | "X will increase" | "Latency will worsen under memory pressure" |
| `quantitative` | "X will be > N" | "Recovery time constant will be < 500ms" |
| `comparative` | "X > Y" | "H1's effect will exceed H2's" |
| `temporal` | "X before Y" | "Crash recovery will complete before next request batch" |
| `null` | "No effect" | "MOM-2 RNAi will not affect MS specification" |

Prediction type drives:
- **Comparison logic** at reveal time (how to determine if observed outcome matches)
- **Boldness scoring** (per HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md): `quantitative` predictions tend to be bolder than `qualitative`
- **Lint discipline** (per ARTIFACT-LINTER-RULES.md): `qualitative` is OK for early Phase 3; `quantitative` preferred at Phase 4

---

## The lock workflow

### Step 1: Draft

```bash
brenner prediction draft \
  --hypothesis-id H-RS20260301-001 \
  --text "Recovery time constant will be < 500ms" \
  --type quantitative
```

Returns a draft prediction with mutable text.

### Step 2: Lock

```bash
brenner prediction lock <prediction-id>
```

Server computes:

```python
hash = sha256(prediction_text + iso_timestamp)
```

Stores `(text, timestamp, hash)`; transitions to `locked`. Returns the hash for external verification.

### Step 3: Evidence collection

(Time passes; tests run; data accumulates per Phase 4.)

### Step 4: Reveal

```bash
brenner prediction reveal <prediction-id> \
  --observed "487 ± 32ms" \
  --result confirmed   # confirmed | refuted | inconclusive
```

The original sealed text is unsealed; comparison logged. Transitions to `revealed`.

### Step 5: Verify (anyone can do this)

```bash
brenner prediction verify <prediction-id> --hash <claimed-hash>
```

Recomputes `sha256(stored_text + stored_timestamp)`; compares to claimed hash. Any tampering between lock and verify produces a mismatch.

---

## Amendment tracking + integrity score

If interpretations need to change post-evidence, you can `amend`:

```bash
brenner prediction amend <prediction-id> \
  --new-text "..." \
  --type clarification \
  --reason "..."
```

`--type` accepts: `clarification | reinterpretation | scope_change | retraction`.

Each amendment:

- Logs original text + new text + amendment type + reason + timestamp
- Penalizes the integrity score
- Sets state to `amended`
- Visual warning in UI / HANDBACK section

### Integrity score formula

```
integrityScore = (1 - amendmentPenalty) × 100
```

Where `amendmentPenalty` increases with:
- Number of amendments (each subtracts a fixed weight)
- Amendment severity (clarification < reinterpretation < scope_change < retraction)
- Lateness of amendment (post-evidence amendments penalized more)

A perfectly-honest pre-registration: integrity = 100%. A "we changed our mind 3 times after seeing the data" prediction: integrity could drop to 20% or below.

---

## Robustness multiplier

Predictions with higher integrity get weighted more heavily in confidence updates. Per HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md, the score for a confirmed prediction is:

```
score = base_score × boldness_multiplier × robustness_multiplier
```

| Integrity | Robustness multiplier |
|-----------|------------------------|
| 100% (no amendments) | 1.0× |
| 75-99% | 0.8× |
| 50-74% | 0.5× |
| < 50% | 0.2× |

A prediction amended into "obvious correctness" after seeing the data wins almost no points. A locked prediction that survives evidence wins full credit.

---

## When to lock

Lock predictions:

- **Before Phase 4 investigation begins** (default for all H predictions)
- **Before each discriminative test runs** (test predictions per H)
- **At Phase 5 cross-exam** (when adjudicator commits to a verdict prediction)
- **At Phase 7 audit pre-publication** (T4+ sessions: lock final verdict before external review)

Don't lock predictions during Phase 3 hypothesis brainstorming — the predictions are still being shaped.

---

## Per-phase prediction-lock activity

| Phase | Activity |
|-------|----------|
| 3 hypothesis | Predictions drafted (no lock yet) |
| 4 investigation | **Lock predictions** before EV collection begins; reveal as EVs arrive |
| 5 cross-exam | Lock verdict-predictions for high-stakes Hs |
| 7 audit | Verify all locked predictions; flag amended-with-low-integrity for review |
| 8 freeze | Final integrity scores aggregated |
| 9 handback | HANDBACK § Verdict cites integrity scores per H |

---

## Composition with brennerbot

The prediction lock integrates with:

- **Hypothesis Arena** (per HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md): boldness × robustness multipliers
- **Evaluation Rubric** (per EVALUATION-RUBRIC-14-CRITERIA.md): test designer's "Score Calibration Honesty" criterion penalizes inflated likelihood without lock
- **Operator Calibration** (per OPERATOR-CALIBRATION-LOG.md): track per-operator amendment-rate over time
- **Failure-Mode Analytics** (per FAILURE-MODE-ANALYTICS.md): persistent low-integrity is its own pattern (P-11 "post-hoc rationalization")

---

## Per-prediction lifecycle bead

Predictions become first-class beads:

```yaml
id: P-001
label: prediction
hypothesis: H-001
type: quantitative
state: locked | revealed | amended
text: "Recovery time constant will be < 500ms"
locked_at: 2026-03-01T14:23:00Z
hash: sha256:7f3a4b2c...
revealed_at: 2026-03-08T09:15:00Z
observed: "487 ± 32ms"
result: confirmed | refuted | inconclusive
boldness: vague | specific | precise | surprising
amendments: []
integrity_score: 100
```

The bead is queryable: "show me all locked predictions revealed in the past 30 days that were refuted" → calibration insight.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip lock; just write a prediction in prose | No verification; goalpost drift inevitable |
| Lock too early (during draft brainstorming) | Wastes the lock mechanism on shapes-still-shifting predictions |
| Amend post-evidence without `--reason` | Validator rejects |
| Treat amendment as cost-free "clarification" | Integrity score penalizes; cumulative penalty is deterrent |
| Lock vague predictions ("things will improve") | Boldness multiplier is 1.0×; prediction adds little signal |
| Lock contradictory predictions across panes | One will be wrong; doesn't help converge unless designed to discriminate |
| Verify hash only at Phase 9 | Verify after lock to confirm seal worked |
| Use prediction-lock as compliance theater | The discipline is *honest pre-registration*, not box-ticking |

---

## When the framework breaks

In some research domains, predictions are fundamentally exploratory ("we don't yet know what to predict"). The lock framework:

- **Allows null-prediction** (`type: null`) — "we predict no effect"
- **Allows qualitative predictions** with explicit imprecision
- **Tracks integrity** even with vague predictions; "we predicted something vague" gets some credit but lower boldness

For genuinely exploratory Phase 1 framing where no prediction is possible: don't lock. But Phase 4 *must* have ≥1 locked prediction per active H — otherwise Phase 5 verdicts can't be evaluated honestly.

---

## Cross-references

- [HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md](HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md) — boldness × robustness multipliers
- [EVALUATION-RUBRIC-14-CRITERIA.md](EVALUATION-RUBRIC-14-CRITERIA.md) — Score Calibration Honesty
- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — predictions per H
- [OPERATOR-CALIBRATION-LOG.md](OPERATOR-CALIBRATION-LOG.md) — amendment-rate tracking
- [FAILURE-MODE-ANALYTICS.md](FAILURE-MODE-ANALYTICS.md) — pattern P-11 (post-hoc rationalization)
- [BAYESIAN-FRAMEWORK.md](BAYESIAN-FRAMEWORK.md) — prediction precision + posterior update
- [DISCRIMINATIVE-TEST-DESIGN.md](DISCRIMINATIVE-TEST-DESIGN.md) — pre-test predictions
- /dp/brenner_bot/README.md § Prediction Lock System — original source
