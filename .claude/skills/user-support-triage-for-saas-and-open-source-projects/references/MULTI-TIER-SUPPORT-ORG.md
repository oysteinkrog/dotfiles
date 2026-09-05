# Multi-Tier Support Org — L1/L2/L3, Swarming, Follow-The-Sun

The triage skill defaults to a single-owner shape: founder + agent. That's the right default for solo-and-early projects. Mature operations layer specialists, escalate by complexity, and operate continuously across timezones. This file describes the patterns so the skill stays useful as the project's support function grows.

> **Core insight:** the right org shape is not "more people doing the same thing." It is *differentiated* people: specialists, escalation paths, swarming for complex cases, and continuity across timezones. Each shape has its own pitfalls; picking the wrong one costs more than no specialisation.

This file complements `SUPPORT-FORECASTING.md` (capacity planning math) and `PARETO-AND-LONG-TAIL.md` (head-vs-tail strategy). Both assume a capacity number; this file describes how that capacity is structured.

---

## The Three Org Models

| Model | When | Cost shape | Customer experience |
|---|---|---|---|
| **Tiered (L1/L2/L3)** | Volume requires specialisation | Linear in volume | Slow on first response; specialised on re-routed |
| **Swarming** | Complex cases dominate; junior+senior pairs | Higher per-case but fewer cases | Fast resolution; one continuous owner |
| **Follow-the-sun** | Global customer base; need 24/7 coverage | Continuous coverage | Always-on response; risk of context-loss handoffs |

Most projects benefit from a *hybrid* — tiered for routine, swarming for tail, follow-the-sun for after-hours coverage of high-tier customers only. The triage skill adapts by directing the right operators to the right structure.

---

## The Tiered Model

Classic L1/L2/L3:

| Tier | Skill | Owns |
|---|---|---|
| **L1** | Trained on FAQ + common runbooks | Volume routine; deflection; escalation routing |
| **L2** | Domain expertise (billing, integrations, etc.) | Investigation; non-routine cases; reproduction |
| **L3** | Engineering / specialist / founder | Bugs, security, edge cases, escalations |

### How the skill maps

- **L1** runs Pipeline A (routine bugs), Pipeline B (small refunds), Pipeline H (feature request), Pipeline I (pre-sales). Most ✓ CONFIRM goes through L1's batched bundle.
- **L2** picks up when L1 ★ ORIENT detects out-of-scope or when L1's batched investigation fails. Pipelines C, J, K, Q.
- **L3** handles Pipelines D, E, F, G, T, U, W, X. The crisis / outage / regulatory / fraud bucket.

Routing rules in `03-decision-matrix.md` should be tier-aware: routine → L1, investigation needed → L2, runbook-bound severity → L3.

### The L1-routing trap

L1 is graded on volume; L2/L3 graded on complexity. The mis-routing failure mode: L1 doesn't escalate cases they could handle "if they just tried harder," because it costs them throughput. The customer waits while L1 thrashes. Fix by:

- Set per-case L1 budget (15-20 min before mandatory escalation review)
- Reward L1 for **escalating well**, not just for closing
- Reward L2/L3 for **mentoring** L1 to absorb the next instance of a class
- Track time-to-resolution including escalation chain, not by tier

The triage skill captures this in `📈 OUTCOME` records: every escalation is a learning opportunity. After 3 of the same escalation pattern, the L1 runbook is updated.

---

## The Swarming Model

Less common in tech; common in elite consulting and incident response. The structure:

- A complex case opens; the most-senior available person *takes ownership* and pulls in 1-3 specialists for short bursts (15-30 min)
- The senior is the customer-facing voice throughout
- Specialists contribute internally without rotating customer-facing context

Why it works: customer experiences one voice; complex cases get expert attention without specialists carrying the customer-comms burden full-time.

### How the skill maps to swarming

- The senior runs ★ ORIENT, ⚖ DECIDE, ✉ DRAFT
- Specialists provide investigation contributions (🔍 REPRO from engineer; ⊕ CORRELATE from data; 🪞 SECOND-OPINION from other senior)
- The owner (senior) consolidates, voice-matches, and confirms

This is the natural shape for Pipelines C (large refund), D (security), E (outage), G (hostile L3+), Q (churn-risk-tail). Each requires multi-specialist input but should not look fragmented to the customer.

### The swarming trap

Swarming becomes broken-telephone if specialists don't have full context. Discipline:

- Senior writes a 3-line case-frame at swarm start, shared across all specialists
- Specialist contributions go to the shared case file, not back to the senior verbally
- One ✓ CONFIRM at the end; never partial-send during the swarm

For an agentic system: the agent itself can play the "junior who synthesises specialist contributions for the senior". The case file is the agent's working context; specialists drop into it; the senior sees the synthesis.

---

## Follow-The-Sun

Three (or more) regional teams: Asia/Pacific, EMEA, Americas. Each team is "on" during their region's business day, "warm-handing-off" to the next region at end-of-day.

Why teams adopt it: enterprise customers expect <1h response 24/7. A US-only team can't deliver that without on-call burnout.

### Handoff discipline

The most common failure: customer hits region 1 at end-of-day, region 2 picks up at start-of-day, region 2 has no context, asks the customer to repeat themselves. Customer experience: I told someone yesterday and now you don't know.

Patterns that fix:

- **Structured handoff at end-of-region-day**: every active ticket gets a 3-line summary in the agent's standardised format (current state, blockers, next-action, ETA)
- **Single ticket-thread**: never branch per-region; region 2 replies in the same thread
- **Pre-acknowledgement**: when the customer's original message arrives in region 1's evening, an internal note is added saying "EMEA team will pick this up at 09:00 their time = 04:00 your time"
- **Continuity tag**: tickets with active follow-the-sun handoff tagged with `fts-handoff` so neither region accidentally closes

For an agentic system: the agent maintains the working state continuously; "regions" are owner-availability windows. The agent's audit trail and state become the lossless handoff.

---

## The Swarm + Tier Hybrid

Most mature operations:

- **Routine** (head per `PARETO-AND-LONG-TAIL.md`): tiered L1 → L2 escalation
- **Complex** (tail): swarmed; senior + specialists
- **24/7 coverage**: follow-the-sun for enterprise tier, on-call escalation for everyone else

`05-policies.md` records the project's specific structure.

### The escalation matrix

A useful one-page:

```
                      L1 covers   L2 covers   L3 / swarm covers
                      ─────────   ─────────   ─────────────────
Routine bug              ✓
Refund < $X              ✓
Refund > $X                                       ✓
Security disclosure                              ✓
GDPR DSAR                            ✓
Outage                                           ✓ (swarm)
Hostile user (L0-L2)                ✓
Hostile user (L3+)                               ✓
Press inquiry                                    ✓ (swarm)
Regulator inquiry                                ✓ (swarm)
Crisis / safety                                  ✓ (swarm)
Fraud-flagged                       ✓
Plan transition                     ✓
```

The matrix should be derivable from `03-decision-matrix.md`; documenting it explicitly catches gaps.

---

## On-Call Discipline

For projects with after-hours severity:

| Severity | After-hours response | Examples |
|---|---|---|
| **Sev 1** | Page immediately | Outage; data loss; security disclosure |
| **Sev 2** | Notify within 1h | Tier-1 customer blocked; broken integration affecting many |
| **Sev 3** | Next business day | Routine non-blocking; cosmetic |
| **Sev 4** | Whenever | Feature requests; documentation |

On-call rotations don't belong solely to engineering. Support should have an analogous rotation for severities 1-2 above.

Patterns that protect on-call humans:
- Rotating, predictable
- Defined response SLA, not "always reachable"
- Named hand-off at end-of-shift, even if nothing's active
- Compensated (extra pay or equivalent time off)
- Capped (no on-call for >X consecutive days)

---

## QA / Shadow Review (Cross-Tier)

Quality flow across tiers:

- Senior periodically reviews random samples of L1 sends
- Sample size: 5% of L1 sends, weekly
- Review rubric: factual accuracy, voice match, customer-effort minimisation, compliance with runbooks
- Findings feed back into L1 training and `08-voice.md` calibration

The same applies to AI-agent-drafted-then-owner-approved content: random sampling of approvals to catch slow-drift in agent quality. See `QA-SHADOW-REVIEW.md` for the detailed rubric.

---

## Career Paths And Burnout

Tiered systems become career ladders or dead ends. The difference:

- **Career ladder**: L1 → L2 → L3 → engineering / product manager / customer success leader
- **Dead end**: L1 forever, with attrition

Patterns that build the ladder:
- Document an L1 → L2 promotion criteria explicitly (cases owned, retention metrics, mentor-junior, etc.)
- Time-bounded L1 (most stay 12-24 months max)
- Cross-functional rotations (L1 spends a week shadowing engineering)
- L2/L3 takes on mentoring as part of role

Burnout prevention is structural: limit concurrent crisis cases per agent (no more than 1 active Pipeline W or T at once); enforced PTO; backups for on-call; weekly retros that surface friction.

---

## Hand-Off Protocols

Specific tactical hand-offs the skill supports:

| Hand-off | Format | Skill artefact |
|---|---|---|
| L1 → L2 escalation | Case summary + reason for escalation + L1's read | Internal note in ticket; bead if substantive |
| L2 → L3 escalation | Same + reproduction notes + 🪞 SECOND-OPINION proposal | Bead + draft for review |
| Swarm initiation | 3-line case frame; @mentions of specialists | Slack thread; ticket internal note |
| Region 1 → Region 2 (FTS) | Standardised state-of-ticket | Internal note format |
| Support → CS (retention handoff) | Customer profile + relationship history + concern | Distinct artefact, not just ticket |
| Support → Engineering (bug) | Reproduction + impact + 🐞 BEAD | Bead linking ticket |
| Support → Sales (pre-sales escalation) | Lead summary + technical question | Pipeline I/S handoff |

Each hand-off is a *trust transfer*. The handoff document either preserves the trust the customer had or breaks it. Document templates for each.

---

## How This File Plugs In

| Used by | How |
|---|---|
| ⚡ SWARM operator | Initiate multi-specialist swarm |
| 📞 FOLLOW-SUN operator | Cross-region handoff |
| 🛡 ESCALATE operator | Tier escalation routing |
| 03-decision-matrix.md | Tier routing per category |
| 05-policies.md | Project's specific org structure |
| QA-SHADOW-REVIEW.md | Cross-tier quality review |
| ANTI-PATTERNS.md | Adds tier-mis-routing, broken-telephone-handoff failure modes |

---

## Cross-References

- [SUPPORT-FORECASTING.md](SUPPORT-FORECASTING.md) — capacity math
- [PARETO-AND-LONG-TAIL.md](PARETO-AND-LONG-TAIL.md) — head/tail allocation
- [QA-SHADOW-REVIEW.md](QA-SHADOW-REVIEW.md) — quality discipline
- [POST-INCIDENT-RETRO.md](POST-INCIDENT-RETRO.md) — multi-tier retro patterns
- [BEADS-INTEGRATION.md](BEADS-INTEGRATION.md) — handoff via beads
