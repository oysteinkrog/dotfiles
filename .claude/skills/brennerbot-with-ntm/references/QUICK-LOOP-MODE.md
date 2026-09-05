# QUICK-LOOP-MODE.md — The 30-90 Minute Compressed Brenner Loop

<!-- TOC: Why a quick loop | When to use vs incident-investigation | The 6-step protocol | Time budget per step | Outputs | Per-step quality bar | Composition with the full 10-phase loop | Anti-patterns | Cross-references -->

The full 10-phase brennerbot loop targets 5-12 hours for T3+ sessions. But sometimes the question is small enough or the budget tight enough that a 30-90 minute session is the right tool.

The "quick-loop mode" is a compressed Brenner protocol that retains the *methodology essentials* — falsifiable framing, decision experiments, third-alternative — without the full multi-pane orchestration.

Mined from `/dp/brenner_bot/metaprompt_by_gpt_52.md § The "Brenner Loop"` (a 30-90 min runnable protocol described in the GPT-5.2 metaprompt).

Distinct from `incident-investigation` mode (≤60 min for production incidents, time-pressured). Quick-loop is for *non-time-pressured* but small questions where T1 tier doesn't quite fit.

---

## Why a quick loop

The full 10-phase loop is over-engineered for many real questions:

- "Should we use library A or B?" (architectural triage)
- "What's the load-bearing factor in our latency p99?" (focused investigation)
- "Does this design pattern have an obvious flaw?" (single-issue audit)

These questions don't warrant Squad rosters, multi-family triangulation, or full HANDBACK ceremonies. But they *do* warrant Brenner discipline: falsifier, third-alternative, exclusion testing.

The quick-loop is the bridge: methodology-on, ceremony-off.

---

## When to use vs incident-investigation

| Aspect | Quick-loop | Incident-investigation |
|--------|------------|-------------------------|
| Trigger | Non-urgent small question | Production incident, time-pressured |
| Wall time | 30-90 min | ≤60 min |
| Roster | 1 pane (you, the operator, with self-debate) | Pair (cc + cod) typical |
| Output | Decision memo (~1 page) | INCIDENT-VERDICT.md |
| Phase coverage | 6-step protocol (compressed) | Compressed Phases 1-7 |
| Re-engagement | Optional follow-up if needed | Mandatory post-mortem-formalization |

When in doubt: incident → incident-investigation; non-incident small → quick-loop; T2+ → standard mode.

---

## The 6-step protocol

```
Step A — Problem selection             5-10 min
Step B — Hypothesis slate (≥3)         10-15 min
Step C — Third-alternative guard        5-10 min
Step D — Discriminative tests           10-25 min
Step E — Assumption ledger              5-10 min
Step F — Next actions + stopping rule   5-10 min
                                        ───────
Total                                   40-80 min
```

Each step has a quality bar. Skip nothing; the bar is *what* counts as "done", not whether to do the step.

### Step A — Problem selection (5-10 min)

**Inputs:** vague question from user.
**Activity:** apply FRAMING-WORKBOOK.md F1-F9 (compressed). Confirm:
- Trigger (why now?)
- Stakes (what action depends on the answer?)
- Falsifier (what observation would settle it?)
- Scope (in/out)

**Outputs:** one-line question of record + falsifier (≤3 lines).

**Quality bar:** the falsifier is observable, decidable, and concrete. If you can't write it in 3 lines, the question isn't ready.

**Common failure:** vague trigger ("we always wonder about this"). Per AE-1.3 (PHASE-1-ANTI-EXAMPLES.md), probe for the specific trigger.

### Step B — Hypothesis slate (10-15 min)

**Inputs:** question of record from Step A.
**Activity:** generate ≥3 hypotheses. Each H has:
- Claim (one line)
- Mechanism (one paragraph)
- Falsifier (specific observable)
- Confidence (low/medium/high)

**Outputs:** Hypothesis Slate (table form).

**Quality bar:** ≥3 distinct mechanisms. If you can't articulate 3 distinct mechanisms, you don't yet understand the question.

**Common failure:** "the cause is X" without alternatives (per F-301).

### Step C — Third-alternative guard (5-10 min)

**Inputs:** Hypothesis Slate from Step B.
**Activity:** force ≥1 H with `origin: third_alternative`. Specifically: "what if both H1 and H2 are wrong, and the actual cause is something we haven't considered?"

**Outputs:** updated Hypothesis Slate with explicit third-alternative.

**Quality bar:** the third-alternative is *testable*, not "we don't know."

**Common failure:** rubber-stamping "neither" as the third-alternative without articulating a mechanism.

### Step D — Discriminative tests (10-25 min)

**Inputs:** Hypothesis Slate (≥3 H now).
**Activity:** per DISCRIMINATIVE-TEST-DESIGN.md 7-step protocol. For each H:
- What observation would distinguish this H from the others?
- Forbidden patterns (per BRENNER-VOCABULARY.md)?
- Digital handle preference
- Cost vs information gain ranking

Run the cheapest 1-2 tests. Update H states based on results.

**Outputs:** test results + updated Hypothesis Slate states (`active`, `confirmed`, `refuted`, `deferred`).

**Quality bar:** each H's state changes (or maintains) based on specific evidence — not on operator gut.

**Common failure:** running confirmatory tests that don't discriminate. Per F-403.

### Step E — Assumption ledger (5-10 min)

**Inputs:** updated Hypothesis Slate.
**Activity:** for the surviving H(s), enumerate load-bearing assumptions. Per BRENNER-VOCABULARY.md "Assumption ledger":
- Each assumption has a falsifier
- `scale_physics` assumptions get explicit calculation
- `dont_worry` assumptions are flagged for follow-up

**Outputs:** assumption ledger (≤5 entries typical).

**Quality bar:** every load-bearing assumption is on the ledger; none are ambient/implicit.

**Common failure:** "we'll just assume X holds" without ledger entry → silent drift later.

### Step F — Next actions + stopping rule (5-10 min)

**Inputs:** session state from Steps A-E.
**Activity:** decide:
- Is the question answered? (verdict + confidence)
- If not, what's the next step? (additional tests, escalate to full session, defer)
- What's the stopping rule? (when do we stop following up?)

**Outputs:** Decision Memo (≤1 page) per a compressed version of `assets/templates/decision-memo-template.md`.

**Quality bar:** explicit verdict OR explicit "we don't know — here's why we're stopping anyway".

**Common failure:** infinite follow-up. Per WALL-TIME-BUDGET.md, set a stopping rule.

---

## Time budget per step

```
Step A — 10% of budget   (= 5-10 min)
Step B — 15%             (= 10-15 min)
Step C — 10%             (= 5-10 min)
Step D — 35%             (= 20-30 min)  ← largest
Step E — 10%             (= 5-10 min)
Step F — 10%             (= 5-10 min)
Buffer — 10%             (= unallocated)
```

If Step D blows past 30 min, you're treating the quick-loop as a flagship investigation. Either:
- Hard-cap Step D and accept partial discrimination
- Escalate to standard mode (`fresh-question`) with full 10-phase budget

---

## Outputs

### Single artifact: `QUICK-LOOP-MEMO.md`

```markdown
# Quick Loop Memo — <YYYY-MM-DD-slug>

**Question:** <one-line>
**Falsifier:** <specific observable>
**Verdict:** <answer + confidence>
**Wall time:** <total>
**Operator:** <single instance>

## 1. Hypothesis slate (final)
| ID | State | Claim | Falsifier |
|----|-------|-------|-----------|
| H1 | refuted | ... | (fired by test T1) |
| H2 | confirmed | ... | (held under test T2) |
| H3 | deferred (origin: third_alternative) | ... | (test required for full discrimination) |

## 2. Discriminative tests run
| ID | Distinguishes | Cost | Result |
|----|---------------|------|--------|
| T1 | H1 vs H2 | 5 min | H1 refuted |
| T2 | H2 vs H3 | 15 min | H2 confirmed |

## 3. Assumption ledger
| ID | Assumption | Type | Verified? |
|----|------------|------|-----------|
| A1 | ... | scale_physics | yes (calc inline) |
| A2 | ... | dont_worry | no (scheduled) |

## 4. Verdict + Action

<one paragraph: what we now believe, why, what would change it>

## 5. Stopping rule

<when to re-engage; what would warrant a full T3 session>
```

That's the quick-loop deliverable. ~1 page; ≤80 lines per HANDBACK-VOICE-GUIDE.md applies.

---

## Per-step quality bar (summary)

| Step | Skip if | Don't skip if |
|------|---------|----------------|
| A | Question is already framed (rare) | Almost always; framing is load-bearing |
| B | You only have 2 Hs (very rare) | Default — generate ≥3 |
| C | A and B already produced a valid third-alternative | Default — explicit guard |
| D | All Hs are obviously wrong (rare) | Default — at least 1 cheap test per pair of Hs |
| E | No load-bearing assumptions (very rare) | Default — every surviving H has assumptions |
| F | The verdict is unambiguous and self-stopping | Always explicit, even if "we don't know" |

---

## Composition with the full 10-phase loop

The quick-loop maps to the full loop's phases:

| Quick-loop step | Full-loop phase(s) |
|-----------------|---------------------|
| A — Problem selection | Phase 1 (compressed) |
| B — Hypothesis slate | Phase 3a (compressed) |
| C — Third-alternative | Phase 3c |
| D — Discriminative tests | Phases 4 + 5 (compressed) |
| E — Assumption ledger | Phase 4 (assumption beads) |
| F — Decision memo | Phase 9 (compressed HANDBACK) |

Phases 2 (bootstrap), 6 (distillation), 7 (audit), 8 (freeze), 10 (drift) are skipped.

If after the quick-loop the verdict is unsatisfactory, escalate to standard mode by:

1. Promote the QUICK-LOOP-MEMO.md content into intake/question_of_record.md
2. Bootstrap a workspace per Phase 0.5
3. Re-enter Decision Tree at Phase 2 (skipping Phase 1 since framing already done)

The quick-loop work is preserved; only the bootstrap was deferred.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Quick-loop for an actual incident | Use incident-investigation mode instead |
| Quick-loop for T4+ stakes | Quick-loop sacrifices triangulation; T4+ needs the full loop |
| Skip Step C (third-alternative) | F-301 risk; the methodology essential |
| Skip Step D (discriminative tests) | Without testing, you produced opinion not analysis |
| Inflate Step D past budget | Use stopping rule; escalate if needed |
| Skip Step F (next actions + stopping rule) | Without explicit stopping, you'll re-litigate later |
| Re-run quick-loop instead of escalating | If verdict isn't clear after quick-loop, escalate |
| Treat as Solo (no self-debate) | Even single-pane operators benefit from explicit Devil's-Advocate moves |

---

## Single-pane self-debate technique

A single operator running quick-loop mode plays multiple roles:

1. **Proposer self**: generate Hs in Step B
2. **Devil's-Advocate self**: in Step C and Step D, deliberately switch perspective; argue against the leading H
3. **Adjudicator self**: in Step F, evaluate the evidence pack and decide

This is mentally taxing — operator-context can drift toward the "winning" perspective. Mitigation:
- Write down the perspective shifts explicitly (per BEADS-WORKFLOW-CHEATSHEET.md format)
- Use 5-min "switch poles" cadence
- For T3+ stakes, don't do single-pane; use Pair tier instead

---

## Cross-references

- [TEN-PRINCIPLES.md](TEN-PRINCIPLES.md) — what's preserved in the compression
- [DISCRIMINATIVE-TEST-DESIGN.md](DISCRIMINATIVE-TEST-DESIGN.md) — Step D protocol
- [FRAMING-WORKBOOK.md](FRAMING-WORKBOOK.md) — Step A compressed F1-F9
- [PHASE-1-ANTI-EXAMPLES.md](PHASE-1-ANTI-EXAMPLES.md) — Step A failure modes
- [WALL-TIME-BUDGET.md](WALL-TIME-BUDGET.md) — quick-loop budget vs T1/T2 budgets
- [TIER-TRIAGE.md](TIER-TRIAGE.md) — when quick-loop is right tier
- [REQUIRED-CONTRADICTIONS.md](REQUIRED-CONTRADICTIONS.md) — single-pane self-debate is conversation-pole
- /dp/brenner_bot/metaprompt_by_gpt_52.md § The "Brenner Loop" — original source
