# FRAMING-WORKBOOK.md — Adaptive Phase 1 Question-of-Record Framing

<!-- TOC: Why a workbook | The 9 framing phases | Branch logic | Self-test gates | Common framing failures | Operator self-prompts | When framing fails -->

Mirrors wills-and-estate-planning's INTERVIEW-FLOW.md. Phase 1 framing is load-bearing; if the question of record is wrong-framed, every downstream phase is wasted. This workbook is the *adaptive interview* the operator runs with the user (and with themselves) to produce a sound question of record.

This is more granular than `MO-01-frame-question.md` (the dispatch template). The workbook is for cases where the user's raw ask is vague, multi-question, or under-scoped. For T3+ sessions, walk through the workbook explicitly.

---

## Why a workbook

The user almost never gives you a Brenner-grade question of record on the first ask. Common forms of vague:

- "What's the best way to <do X>?" (no scope, no falsifier)
- "Should we <decision>?" (no decision-rule)
- "Investigate <topic>" (no constraint, no goal)
- "Find weaknesses in <thing>" (no severity threshold)

The workbook produces a sharp question of record by adaptive Q&A. Don't ask all 9 phase questions front-loaded — branch based on what the user reveals.

---

## The 9 framing phases

```
Phase F1 — Trigger     ("Why are you asking this NOW? What changed?")
Phase F2 — Stakes      ("What action depends on the answer?")
Phase F3 — Scope       ("What's clearly in and clearly out?")
Phase F4 — Paradox     ("What's the tension that makes this hard?")
Phase F5 — Falsifier   ("What observation would prove the question malformed/answered?")
Phase F6 — Mode        ("Fresh-question, code-investigation, corpus, etc?")
Phase F7 — Corpus      ("What sources are available? Which authoritative?")
Phase F8 — Constraints ("Time, budget, model availability, ethics?")
Phase F9 — Tier        ("What tier matches stakes × reversibility?")
```

After F9, you have a question of record. Run the self-test (per QUESTION-OF-RECORD-TEMPLATE.md) before exiting Phase 1.

---

## Phase F1 — Trigger

**Goal:** understand why the user is asking *now*.

**Questions:**
- "What triggered this question? Did something change recently that made it urgent?"
- "Have you investigated this before? If yes, what changed since?"
- "Is there a specific event or decision deadline driving this?"

**Why this matters:** the trigger surfaces the *real* question. "What's the best on-disk format" is sometimes really "we hit perf issues with our current format and need to migrate." Trigger reveals the underlying need.

**Branch:**
- If trigger is incident → likely incident-investigation mode
- If trigger is upcoming decision → A7 archetype
- If trigger is curiosity → T1 likely
- If trigger is "we always wonder about this" → may be too vague; sharpen

**Common failure:** user gives a "neutral" framing that hides the actual driver. Probe for the trigger.

---

## Phase F2 — Stakes

**Goal:** quantify what's riding on the answer.

**Questions:**
- "What action would you take if the answer is X? Y? Z?"
- "Who's affected by acting on this answer?"
- "What's the cost of being wrong? Of inaction?"
- "Reversible or one-way?"

**Why this matters:** stakes determine tier. Low-stakes question with T4 effort wastes resources; high-stakes question with T1 effort produces unsafe answers.

**Branch:**
- Low stakes (no immediate action, exploratory) → T1
- Medium stakes (engineering decision, reversible) → T2-T3
- High stakes (production / customer-facing / pre-launch) → T4
- Existential stakes (multi-year commitment, regulatory, foundational) → T5

**Common failure:** "we just want to know" — push back; if no action depends, the question may be curiosity (T1) at most.

---

## Phase F3 — Scope

**Goal:** define what's in and out of scope.

**Questions:**
- "What's clearly in scope? List 3-5 specifics."
- "What's clearly out of scope? List 3-5 specifics."
- "Are there constraint regimes (workload class, time horizon, geography) we should bound?"

**Why this matters:** scope is the most common Phase 1 failure mode. "Out of scope" is harder to articulate than "in scope" — push for both.

**Branch:**
- Scope unclear → ask for specific examples; "is this in scope? this? this?"
- Out-of-scope empty → user hasn't thought about it; surface boundary cases
- Scope keeps expanding → user is fishing; probably needs reframing

**Common failure:** user says "scope is everything important" — that's not scope. Force specificity.

---

## Phase F4 — Paradox

**Goal:** identify the tension that makes this question hard.

**Questions:**
- "What two facts seem to contradict each other?"
- "If the obvious answer were correct, why hasn't everyone already adopted it?"
- "What surprises you about this domain?"

**Why this matters:** per ◊ Paradox-Hunt operator. Without a paradox, the question may not need a brennerbot session — it may be a quick lookup.

**Branch:**
- Clear paradox → proceed
- No paradox → question may not warrant a session; recommend simpler approach
- Multiple paradoxes → split into multiple questions

**Common failure:** user gives a "paradox" that's actually well-explained in the literature. Probe: is this genuinely open, or just unfamiliar to user?

---

## Phase F5 — Falsifier

**Goal:** specify what observation would settle the question.

**Questions:**
- "What evidence, if found in <X> hours of searching, would prove the question is malformed (or already answered)?"
- "What concrete observable would distinguish 'we know the answer' from 'we don't'?"
- "If after the session you got verdict X, what would convince you that X is wrong?"

**Why this matters:** ✂ Exclusion-Test is the load-bearing operator; sessions without observable falsifiers are research theater.

**Branch:**
- Clear, decidable, observable falsifier → proceed
- Vague ("we'll know it when we see it") → keep probing; falsifier must be specific
- Unfalsifiable ("it depends on intuition") → question is metaphysical; reframe or decline

**Common failure:** user proposes a falsifier that requires resources we don't have. Negotiate: tighter falsifier reachable now, OR escalate to T4+ with budget for the harder probe.

---

## Phase F6 — Mode

**Goal:** route to the right operating mode.

**Questions:**
- "Is the question primarily about a codebase, a corpus of documents, or first-principles?"
- "Are we resuming prior work, doing a drift check, or fresh?"
- "Time-pressed (incident) or methodical?"

**Why this matters:** different modes have different exit criteria and required artifacts (per OPERATING-MODES.md and EXTENDED-OPERATING-MODES.md).

**Branch tree:**
- Codebase target → `code-investigation`
- Corpus directory → `corpus-distillation`
- Production incident → `incident-investigation`
- Resuming prior workspace → `resume-session`
- Methodology drift → `methodology-drift-check`
- Pre-publication / pre-launch → consider `hypothesis-pre-registration` first
- Multi-prior-source synthesis → `meta-analysis`
- Ongoing topic → `living-review`
- Adversarial review → `red-team-only`
- Fresh, abstract → `fresh-question`

---

## Phase F7 — Corpus

**Goal:** identify what sources are available and authoritative.

**Questions:**
- "What sources should I read to investigate this?"
- "Who are the authorities in this domain?"
- "Are there any sources I should explicitly NOT read (e.g., to avoid bias)?"
- "Are sources frozen (papers, archived) or volatile (live data, ongoing)?"

**Why this matters:** corpus quality bounds investigation quality (per CORPUS-CURATION.md).

**Branch:**
- Stable corpus available → standard ingestion via `MO-corpus-curate.md`
- Volatile sources → activate VERIFICATION-FIRST.md protocol
- No prior corpus → `fresh-question` mode; corpus emerges from Phase 4
- User insists on excluding certain sources → respect with documented reason (anti-bias measure)

---

## Phase F8 — Constraints

**Goal:** surface time, budget, ethics, model-availability constraints.

**Questions:**
- "Wall-time budget?"
- "Are there model providers (cc/cod/gmi) we should prefer or avoid?"
- "Ethical considerations? (e.g., dual-use, privacy, regulated domain)"
- "Reviewers / sign-off requirements?"

**Why this matters:** constraints affect tier × roster × mode choices.

**Branch:**
- Tight time budget → tighten tier estimate; consider compressed mode
- Model exclusions → adjust roster
- Ethical considerations → activate `MO-dual-use-review.md` (Tier-4 MO)
- Sign-off required → ensure HANDBACK includes sign-off section

---

## Phase F9 — Tier

**Goal:** confirm tier (per TIER-TRIAGE.md).

Combines stakes (F2) × scope (F3) × constraints (F8) × reversibility.

**Output of F9:**
```
Tier: T<1-5>
Estimated wall time: <H>h
Default roster: <Solo/Pair/Squad/Swarm>
Default mode: <one of OPERATING-MODES.md>
Complexity overlays: <list>
```

If F9's tier estimate exceeds user's available budget: re-negotiate. Either accept lower-tier with caveats, OR escalate budget.

---

## Self-test gates

After F9, before exiting Phase 1, run the self-test (per QUESTION-OF-RECORD-TEMPLATE.md):

1. Could a hostile reader misread "Out of Scope"?
2. Is the falsifier observable in <1h by an investigator?
3. Could two reasonable people disagree on what "Scope" means?
4. Does the paradox actually motivate the question, or is it post-hoc?
5. What action changes if answer is X vs Y vs Z?

If any fails, return to the relevant F-phase. F1-F9 isn't strictly linear; iterate.

---

## Common framing failures (and the recovery path)

### "The question is too broad"

User: "What's the best architecture for our system?"

Recovery: probe scope (F3). Force workload class, goal metric, time horizon. Likely splits into multiple narrower questions.

### "The user can't articulate stakes"

User: "We just want to know."

Recovery: probe trigger (F1). What changed? If nothing changed AND no action depends, question is T1 curiosity at most.

### "The user proposes an unfalsifiable falsifier"

User: "We'll know we're right when we feel confident."

Recovery: probe falsifier (F5). Push for an observable: "If <specific observation> were found, would that change your view?" Iterate.

### "The user wants multiple questions answered"

User: "I have three questions: X, Y, and Z. Investigate all of them."

Recovery: split into separate sessions. Each gets its own framing. Cross-link if related.

### "The user has prior expectations"

User: "I think the answer is X; please confirm."

Recovery: this is anti-Brenner. The session can't be confirmation-only. Propose: "Let me investigate; my hypotheses will include X but also rivals. Are you OK with the possibility of refuting X?"

### "The user's question is ill-typed"

User: "Why is X bad?" (presupposes X is bad)

Recovery: reframe to neutral question: "Is X bad? Under what conditions?"

### "The user wants the answer 'fast'"

User: "I need this in an hour."

Recovery: T1 budget. Constrain scope drastically. Manage expectations: "Solo/Pair tier in 1h gets you a directional answer; for confidence you need T2-T3."

---

## Operator self-prompts

When stuck in framing:

```
Self-check at F-phase <N>:
- Have I extracted the user's actual driver, or just the surface question?
- Can I write the question of record in one sentence with all required fields filled?
- Could I run a useful Phase 4 round on this question? What would the first investigation step be?
- If I had to recommend abandoning this question (no session), what would be missing for me to do that confidently?
```

If stuck for >15 min on F1-F9, the question may not be brennerbot-shaped. Consider:

- Recommend a different skill (codebase-archaeology for "explore this repo", multi-pass-bug-hunting for "find bugs", etc.)
- Recommend the user think more before re-engaging
- Decline politely if the question is genuinely outside brennerbot's strength

---

## When framing fails

If after walking through F1-F9 the question still won't crystallize:

1. Document the attempted framing in `intake/framing-attempts.md` (preserve for future reference)
2. Tell the user what specifically didn't crystallize
3. Recommend: tighter constraints, different scope, different question
4. Don't proceed to Phase 2; framing must succeed first

A failed framing is better than a successful Phase 4 on a malformed question.

---

## Workbook for specific archetypes

Each archetype (per QUESTION-ARCHETYPES.md) has slightly different F1-F9 emphases:

- **A1 design-space**: F3 scope is critical (workload class)
- **A2 codebase**: F7 corpus is the codebase; F3 must scope subsystems
- **A4 incident**: F1 trigger and F8 time-budget are critical
- **A6 adversarial**: F4 paradox is special — falsifier is "no weaknesses found"
- **A7 decision**: F2 stakes + F5 decision-rule are most important
- **A10 first-principles**: F7 corpus is intentionally minimal

When the archetype is clear, weight the workbook phases accordingly.

---

## Phase 10 lesson loop

If a session's drift check reveals "Phase 1 framing was inadequate", the operator updates this workbook with the missing question. The workbook evolves as the operator's intuition for framing matures.

Sessions that consistently produce convergent verdicts often have well-framed questions; sessions that produce divergent-regression often have ill-framed questions. Track via OPERATOR-CALIBRATION-LOG.md.
