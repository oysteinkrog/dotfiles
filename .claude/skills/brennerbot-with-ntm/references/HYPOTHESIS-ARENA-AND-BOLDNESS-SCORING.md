# HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md — Competitive Hypothesis Testing

<!-- TOC: Why an arena | Arena concepts | The 4 boldness tiers | The scoring formula | The comparison matrix | Discriminative power per test | The 4 hypothesis arena states | Composition with prediction lock | Per-phase arena activity | Anti-patterns | Cross-references -->

Evaluating hypotheses in isolation is easy: "this one looks plausible." The Brenner method demands they **compete head-to-head**. The Hypothesis Arena is brennerbot's structured competitive space — multiple Hs face the same discriminative tests; their performance is tracked relatively, not absolutely.

The arena introduces **boldness scoring**: bold predictions that survive earn more; bold predictions that fail cost more. This *incentivizes* specificity and risk, the opposite of conventional consensus-seeking.

Mined from `/dp/brenner_bot/README.md § Hypothesis Arena`.

---

## Why an arena

Three failures of isolation-based H evaluation:

1. **Local-comparison only** — H1 looks plausible; H2 looks plausible; we never ask which is *more* plausible against the same evidence
2. **Vague predictions reward sandbagging** — "things will improve" is unfalsifiable; specific predictions get punished for being wrong; net incentive: be vague
3. **No champion mechanism** — at session end, multiple Hs are "active"; HANDBACK is muddled

Three benefits of arena:

1. **Comparative ranking** — H1 vs H2 vs H3 on the same tests; clear winner
2. **Boldness incentive** — specific predictions earn 3× more if confirmed (and lose 3× more if refuted), so panes are rewarded for risk
3. **Champion declaration** — the arena's leader becomes the session's primary verdict

---

## Arena concepts

| Concept | Description |
|---------|-------------|
| **Arena** | A competitive space where multiple Hs face the same tests |
| **Competitor** | An H entered into the arena |
| **Shared test** | A test that applies to multiple Hs |
| **Elimination** | When a test definitively rules out an H |
| **Champion** | The H that survives with highest score |

An arena is created per session (or per program if multi-session). Each surviving H is added as a competitor; tests are shared.

```bash
brenner arena create --session RS-20260301 --topic "What causes the latency spike?"
brenner arena add-competitor <arena-id> --hypothesis H-001
brenner arena add-competitor <arena-id> --hypothesis H-002
brenner arena add-competitor <arena-id> --hypothesis H-003
```

---

## The 4 boldness tiers

Predictions are scored by specificity and risk:

| Boldness | Description | Multiplier |
|----------|-------------|------------|
| `vague` | "Things will improve" | **1.0×** |
| `specific` | "Score increases 5-10%" | **1.5×** |
| `precise` | "Score will be exactly 7.3" | **2.0×** |
| `surprising` | "Contrary to consensus, X will occur" | **3.0×** |

The multipliers are intentional design — they make bold predictions disproportionately rewarded when correct (and disproportionately punished when wrong).

### Why 3× for `surprising`

A "surprising" prediction is one that contradicts current consensus. If consensus is wrong about a thing 30% of the time, a surprising prediction has ~30% baseline probability of being right. The 3× multiplier compensates panes for the *cost of being publicly wrong* — without it, no rational pane would propose surprising predictions.

This is calibrated; the 3× isn't arbitrary. It's the multiplier needed to make surprising-and-wrong roughly cost-equivalent to vague-and-right.

---

## The scoring formula

```
score = base_score × boldness_multiplier × robustness_multiplier
```

Where:
- `base_score` is positive for `confirmed`, negative for `refuted`, 0 for `inconclusive`
- `boldness_multiplier` per the table above (1.0×–3.0×)
- `robustness_multiplier` per PREDICTION-LOCK-CRYPTOGRAPHIC.md (1.0×–0.2× depending on amendment integrity)

Example:
- H1 made a `surprising` prediction (3.0× boldness), locked it (100% integrity = 1.0× robustness), and was `confirmed` → +3.0 × 1.0 × base = strong positive
- H2 made a `vague` prediction (1.0× boldness), locked, confirmed → +1.0 × 1.0 × base = weak positive
- H3 made a `surprising` prediction, amended after evidence (50% integrity = 0.5× robustness), confirmed → +3.0 × 0.5 × base = moderate positive

The arena rewards: high boldness + high integrity + correct.

---

## The comparison matrix

The arena generates a comparison matrix per session:

| Hypothesis | Test T1 | Test T2 | Test T3 | Total Score |
|------------|---------|---------|---------|-------------|
| H1 | +3 ✓ | -2 ✗ | +4 ✓ | 5 |
| H2 | +1 ✓ | +2 ✓ | ELIM | — |
| H3 | 0 | +2 ✓ | +1 ✓ | 3 |

Reading:
- **H1**: confirmed T1 (+3, specific × confirmed), refuted T2 (-2), confirmed T3 (+4, precise × confirmed) → total 5
- **H2**: confirmed T1, T2; ELIMINATED by T3 → score = ELIM (no further accumulation)
- **H3**: inconclusive T1; confirmed T2, T3 → total 3

Champion: H1.

The matrix reveals not just *who won* but *how each test discriminated*. Test T3 was a strong discriminator (eliminated H2; positive for H1 + H3). Test T2 didn't discriminate between H2 and H3 (both confirmed).

---

## Discriminative power per test

For each test in the arena:

```
discriminativePower = variance(predictions across hypotheses)
```

A test where all Hs predict the same outcome has zero variance → zero discriminative power. The arena flags these as **non-discriminative** — they don't earn arena credit.

This is the arena's automatic filter for confirmatory-only tests (per F-403). A pane that designs a test with low discriminative power gets no arena reward; the incentive structure pushes panes toward genuinely discriminating tests.

---

## The 4 hypothesis arena states

In the arena context, an H has one of these states (different from the FSM):

| Status | Description |
|--------|-------------|
| `active` | Still competing |
| `eliminated` | Definitively ruled out by a test |
| `suspended` | Temporarily set aside (operator decision) |
| `champion` | Won the arena |

The arena state is *separate* from the FSM state (per HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md), which is broader. An H can be FSM `active` but arena `eliminated` if the arena had a decisive test and the H lost.

The mapping (arena → FSM):

| Arena | FSM transition |
|-------|----------------|
| `eliminated` | `under_attack` → `killed` (with arena-test as kill_reason) |
| `champion` | `active` → `validated` |
| `suspended` | `active` → `dormant` |
| `active` | (no FSM change) |

---

## Composition with prediction lock

Per PREDICTION-LOCK-CRYPTOGRAPHIC.md: the arena **requires** locked predictions for non-trivial scoring. An unlocked prediction can't be reliably "confirmed" or "refuted" — without lock, the prediction-text could have been amended after evidence.

```bash
brenner arena add-test <arena-id> \
  --description "Measure response time under condition Y" \
  --predictions '{
    "H-001": { "outcome": "< 500ms", "boldness": "specific", "prediction_id": "P-001" },
    "H-002": { "outcome": "> 1000ms", "boldness": "specific", "prediction_id": "P-002" },
    "H-003": { "outcome": "500-1000ms", "boldness": "vague", "prediction_id": "P-003" }
  }'
```

Each `prediction_id` references a `P-NNN` bead with `state: locked` (or `revealed` post-evidence). Arena scoring uses the locked prediction; if no lock, score = 0.

---

## Per-phase arena activity

| Phase | Arena activity |
|-------|---------------------|
| 3 hypothesis | Arena created; competitors added |
| 4 investigation | Tests added with per-H predictions; predictions locked |
| 5 cross-exam | Test results recorded; scores computed |
| 6 distillation | Distillations cite arena leader |
| 7 audit | Verify arena scores; check for non-discriminative tests |
| 8 freeze | Champion declared; matrix frozen |
| 9 handback | HANDBACK § Verdict cites champion + score; § Caveats cites surviving competitors |

For T1-T2 sessions: arena optional (can use FSM directly).
For T3: arena recommended.
For T4+: arena mandatory; champion declaration is the verdict.

---

## Cross-arena patterns

Per BRENNERBOT-AT-SCALE.md: track patterns across arenas:

- **Recurring boldness sandbagging** — operators consistently choosing `vague` predictions → calibration coaching D-Cal-12
- **Tests with consistently low discriminative power** — operator's test-design weakness → DISCRIMINATIVE-TEST-DESIGN.md re-training
- **Champion-overrule** — H wins arena but operator overrides for reasons not evidence-based → audit-finding (per Phase 7)

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip arena; declare verdict by operator gut | Loses comparative ranking + boldness incentive |
| Add only one competitor | Need ≥2 for comparison; arena is meaningless with one |
| Predictions without lock | Robustness multiplier defaults to 0.2× (low integrity) |
| All predictions `vague` to avoid risk | No bold predictions = no signal |
| All predictions `surprising` even when not | Cap surprising tier; can't all contradict consensus |
| Run arena without computing discriminative power per test | Misses confirmatory-only test detection |
| Override champion declaration without documenting reason | Audit-finding |
| Re-enter arena after declaration | Champion is terminal in this arena; create new arena for re-test |

---

## CLI reference

```bash
brenner arena create --session <RS-...> --topic "..."
brenner arena add-competitor <arena-id> --hypothesis H-NNN
brenner arena add-test <arena-id> --description "..." --predictions <json>
brenner arena record-result <arena-id> --test-id T-NNN \
  --observed "..." \
  --hypothesis-results <H-001:confirmed,H-002:refuted,H-003:confirmed>
brenner arena matrix <arena-id>      # show comparison matrix
brenner arena leader <arena-id>      # show current champion
brenner arena freeze <arena-id>      # declare champion; lock arena
```

---

## Cross-references

- [PREDICTION-LOCK-CRYPTOGRAPHIC.md](PREDICTION-LOCK-CRYPTOGRAPHIC.md) — boldness × robustness composition
- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — arena → FSM mapping
- [DISCRIMINATIVE-TEST-DESIGN.md](DISCRIMINATIVE-TEST-DESIGN.md) — non-discriminative test detection
- [EVALUATION-RUBRIC-14-CRITERIA.md](EVALUATION-RUBRIC-14-CRITERIA.md) — scoring composition
- [BAYESIAN-FRAMEWORK.md](BAYESIAN-FRAMEWORK.md) — KL divergence + posterior updates
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — cross-arena patterns
- [HANDBACK-VOICE-GUIDE.md](HANDBACK-VOICE-GUIDE.md) — verdict reporting from arena
- /dp/brenner_bot/README.md § Hypothesis Arena — original source
