# OPERATOR-PROMPT-LIBRARY.md — Reusable Prompts for Operator-User Conversations

<!-- TOC: Why a prompt library | Phase 1 framing prompts | Mid-session check-in prompts | Stuck-pane prompts | Convergence prompts | Phase 9 handback prompts | Phase 10 drift prompts | Cross-cutting prompts | Composition with cards -->

Companion to PROMPTS.md (which covers operator-side prompts to swarm panes). This file covers operator-side prompts to the *user* — the back-and-forth that turns vague asks into sound questions of record, communicates progress, and surfaces decisions.

Each prompt is field-tested phrasing that operators can copy verbatim. Customize the bracketed placeholders.

---

## Why a prompt library

The user is part of the methodology. Phase 1 framing requires structured probing; mid-session check-ins prevent expectation drift; Phase 9 handback delivers value clearly. Without practiced phrasing:

- Operators ask vague questions ("can you tell me more?") and get vague answers
- Operators dump the framing too early and lose the user's attention
- Operators surface technical complexity that the user can't act on

This library provides phrasing that's tight, specific, and respectful of user attention.

---

## Phase 1 framing prompts

### P1.1 Trigger probe (F1)

> Before we frame the question: what triggered you to ask this NOW? Was it an incident, an upcoming decision, a customer request, or just curiosity?

**Why:** trigger reveals the underlying need. "What changed" filters out artificially-distanced framings (per AE-1.3).

### P1.2 Stakes probe (F2)

> What action do you take if the answer is X? Y? Z? And who's affected by acting on it?

**Why:** "what action" forces the user to articulate decision impact. Without this, the question may be T1 curiosity at most.

### P1.3 Reversibility probe (F2)

> If we act on this answer and it turns out wrong, how hard is it to reverse? Hours, days, weeks, or years?

**Why:** reversibility is a major tier multiplier. Irreversible decisions need T4+.

### P1.4 Scope probe (F3)

> What's clearly IN scope? List 3-5 specifics. And what's clearly OUT of scope? List 3-5 things you don't want changed or investigated.

**Why:** out-of-scope is harder than in-scope; pushing for specifics catches scope balloon (AE-1.7).

### P1.5 Paradox probe (F4)

> What's the tension that makes this question hard? If the obvious answer were correct, why hasn't it already been adopted?

**Why:** without genuine paradox, the question may not need a brennerbot session. A T1 curiosity can be answered with a quick lookup.

### P1.6 Falsifier probe (F5)

> What evidence, if found in the next few hours of investigation, would prove the question malformed or already answered? What concrete observable would distinguish "we know" from "we don't"?

**Why:** falsifier discipline is load-bearing. "We'll know it when we see it" is rejected.

### P1.7 Falsifier iteration (when first answer is vague)

> "We'll know" isn't specific enough — what specific data point or experiment outcome would settle it? For example: "if benchmark X under conditions Y produces metric Z below threshold T, the conclusion is wrong."

**Why:** iterates until a SPECIFIC observable falsifier emerges (per AE-1.2).

### P1.8 Confirmation-seeking surface

> I notice you have a prior conclusion ("[user's prior]"). The brennerbot session can either: (a) test the conclusion against alternatives — with risk of refuting your prior — or (b) we skip the session and just plan the implementation. Which do you want?

**Why:** addresses AE-1.5 head-on. Confirmation-only sessions are anti-Brenner; the user must accept the possibility of being wrong.

### P1.9 Multi-question split

> These are [N] separate questions. Each needs its own session, OR we pick one as the anchor. Which is most urgent? If you ran ONE question now and the others later, which would unblock the most?

**Why:** addresses AE-1.4. Pacing decisions help users prioritize.

### P1.10 Recipe match

> Your question shape matches recipe R[N] in DOMAIN-RECIPE-LIBRARY.md ([R-name]). I'll use the recipe's roster + tier (T[N]) and pre-bootstrap actions [list]. Does this match what you actually want?

**Why:** confirms recipe match before bootstrap. User can redirect if recipe is wrong fit.

---

## Mid-session check-in prompts

### P2.1 End-of-phase brief (per PROMPTS.md F1 cadence)

> [Brief update on Phase X completion]
>
> Phase X: [one-line outcome — e.g., "3 hypotheses survived triage"]
> Beads: H-001 / H-003 / H-005 active; H-002 refuted.
> Next phase: [N+1] starting now ([estimated wall-time]).
> Reply only if you want to redirect; otherwise I'll continue.

**Why:** maintains user awareness without forcing approval at every step. The "reply only if redirect" footer is critical — it makes the user feel in control while not blocking on every micro-decision.

### P2.2 Mid-Phase-4 progress

> Phase 4 round [N] complete: kill_rate=[K], add_rate=[A]. [If K ≥ A:] convergence approaching, expect [M-N] more rounds. [If K < A:] applying ⊘ Level-Split / mode-flip rotation; if not converging, may need to escalate tier.

**Why:** specific metric communication respects user's analytical mindset; no fluff.

### P2.3 Cost / wall-time alert

> [Estimated burn]: [%] of [tier's] wall-time budget consumed. [If >150%:] hard breach — should we (a) escalate tier and budget, (b) accept incomplete with caveats, (c) reframe?

**Why:** per WALL-TIME-BUDGET.md hard-breach protocol. User makes the call.

### P2.4 Pivot detection

> Phase [N]: anomaly cluster suggests the question may be different from what we framed. Specific anomaly: [description]. Options: (a) absorb anomaly into current question (T1 path), (b) reframe question (back to Phase 1, +30-60 min), (c) note as out-of-scope (continue current). Which do you prefer?

**Why:** anomalies often signal misframing. Surfacing this is honest about where we stand.

### P2.5 User-reply window

> [Optional after P2.1-P2.4]: Going dark for [estimated time] until Phase [N+1] checkpoint. If you don't hear back by [time], assume the swarm is healthy. If urgent, ping with "/status" and I'll surface the latest tick.

**Why:** sets expectation explicitly; the user is freed from passive watching.

---

## Stuck-pane and recovery prompts

### P3.1 Stuck-pane briefing

> Pane [N] has been [stuck/rate-limited/saturated] for [duration]. Applying [specific OC card from /vibing-with-ntm — e.g., OC-002 rotate, OC-009 context-reset]. Estimated recovery: [M-N] minutes. If recovery fails, will [escalate / kill+respawn / reroute].

**Why:** specific operator action communication; user knows what's happening.

### P3.2 External event (provider down, network)

> [Provider] reports [outage/degraded service]. Affecting [N] panes. Options: (a) wait for recovery (estimated [time]), (b) hot-rotate via /caam to alternative account, (c) emergency-stop and resume later. Recommendation: [specific].

**Why:** transparent about external constraints.

---

## Convergence prompts

### P4.1 Phase 4 convergence

> Phase 4 converged: kill_rate ≥ add_rate for [N] rounds. Active hypotheses: H-[list]. Killed: H-[list]. Proceeding to Phase 5 adversarial debate.

### P4.2 Phase 6 convergence

> Phase 6 distillations complete: [N] per-family distillations submitted; meta-synthesis emitted. Disagreement register: [N] entries (1 per pair as required). Next: Phase 7 audit.

### P4.3 Phase 7 convergence

> Phase 7 audit converged after [N] trio-rounds. Findings: [N] critical, [N] high, [N] medium, [N] low. All critical/high addressed. Proceeding to Phase 8 freeze.

### P4.4 Whole-session convergence

> All convergence criteria met. About to freeze (Phase 8) and produce HANDBACK.md (Phase 9). [Estimated wall-time]: [N] more minutes. Optional: Phase 10 drift check (+15 min). Want both?

**Why:** explicit decision point: do they want the methodology lesson loop or just the verdict?

---

## Phase 9 handback prompts

### P5.1 Handback presentation

> [Direct delivery — no preamble:]
>
> **Verdict:** [one-line]
> **Confidence:** [low/medium/high] per CONFIDENCE-SCORING.md
> **Cited evidence:** [top 3 EVs with W ≥ 0.7]
> **Open uncertainties:** [list with next-action tags]
> **Recommended action:** [specific]
> **Risks if you act on this:** [≤3 with mitigations]
>
> Full HANDBACK.md at [path]. Want me to walk through any section in more detail?

**Why:** front-loads the verdict. User reads ≤80 lines and acts.

### P5.2 Caveat emphasis

> One specific caveat: [load-bearing assumption that, if wrong, flips the verdict]. If you observe [specific signal] in production, the verdict would need re-evaluation.

**Why:** brief callout of the most important risk; reduces confidence-illusion.

### P5.3 Cross-session note

> This session reconciled with prior session [RS-...] per RECONCILIATION-MEMO.md. [Type 1-4 outcome]. [Action implication]: [specific].

---

## Phase 10 drift prompts

### P6.1 Drift dispatch

> Dispatching Phase 10 drift check via fresh general-purpose Agent (NOT a swarm pane). Focus areas: [methodology compliance / cross-session patterns / lesson commitment]. Output expected in [N] minutes.

### P6.2 Drift verdict

> Drift verdict: [convergent / divergent-recoverable / divergent-regression]. Lessons: [N] entries to commit. [Recommendation]: [accept / extend / reopen].

### P6.3 Lesson commitment offer

> Phase 10 surfaced [N] lessons. Options: (a) commit them to references/ now (+5 min), (b) leave for next session, (c) accept verdict and skip lesson commitment.

**Why:** lesson commitment is a real action; user opts in.

---

## Cross-cutting prompts

### P7.1 Composition consideration

> This question matches recipe R[N] AND involves [adjacent skill or domain]. Should I compose with /[skill]? It would add [benefit] but cost [overhead].

### P7.2 Tier escalation

> Current tier T[N] has wall-time budget [Hh]. [Reason for escalation: e.g., scope grew, complexity discovered]. Recommend escalating to T[N+1] (+budget [delta]). Approve?

### P7.3 Tier de-escalation

> Current tier T[N] is overkill for the actual question shape. Recommend de-escalating to T[N-1] (-budget [delta]). [Specific reason]. Approve?

### P7.4 Resume from prior session

> Found prior session [RS-...] on related question (per /flywheel + /cass). Options: (a) resume that session in targeted-investigation mode, (b) start fresh (independent verdict), (c) reconcile both. Recommendation: [specific].

### P7.5 Methodology emergency

> Drift auditor flags [serious methodology violation: e.g., unfalsifiable H confirmed, falsifier softened, audit rubber-stamp]. Recommend [pause / re-run affected phases / accept with caveat]. Decision needed before Phase 8 freeze.

**Why:** transparent about methodology integrity; user makes the call to accept or re-run.

---

## Composition with /vibing-with-ntm operator cards

These prompts complement the operator's actions on the swarm. Combined flow:

```
User → P1.1-P1.10 (Phase 1 framing)
↓
Operator → bootstrap-session.sh (Phase 0.5)
↓
Operator → ntm pipeline run (Phase 2-7)
↓ (during)
Operator → P2.1, P2.2, P3.1, P3.2 as needed
↓
Operator → P4.1-P4.4 at convergence
↓
Operator → P5.1-P5.3 (Phase 9 handback)
↓ (optional)
Operator → P6.1-P6.3 (Phase 10 drift)
```

Throughout, the operator runs the /vibing-with-ntm operator loop in the background. The user-facing prompts above are *events*; the operator loop is *continuous*.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip Phase 1 probes "user knows what they want" | Most users don't articulate sound framing on first ask |
| Dump all 9 framing probes at once | Overwhelms; users disengage |
| Mid-session updates that lack metrics | "We're working on it" doesn't help; specific numbers do |
| Hide hard-breach decisions from user | Wall-time decisions are user's call |
| Phase 9 handback that buries the verdict in prose | Front-load verdict; details follow |
| Drift findings that demand user action | Drift is methodology lesson; user accepts or rejects |
| Long preambles ("I'm running brennerbot, which is a...") | User doesn't care about framework; they care about the answer |

---

## Operator self-test before each prompt

Before sending a prompt, ask yourself:
1. Is this the smallest message that conveys the actual decision the user needs to make?
2. Does it include specific numbers, dates, or files (not vague generalities)?
3. Does it offer a clear next step or decision point?
4. Will the user know what to do (or not do) after reading?

If any answer is "no", refine the prompt before sending.

---

## Cross-references

- PROMPTS.md (operator-to-swarm prompts)
- FRAMING-WORKBOOK.md (F1-F9 phases that P1.* probes correspond to)
- PHASE-1-ANTI-EXAMPLES.md (when to invoke specific recovery prompts)
- WALL-TIME-BUDGET.md (when to invoke P2.3 + P7.2/P7.3)
- /vibing-with-ntm operator cards (in-swarm actions complement these user-facing prompts)
