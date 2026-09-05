# TIER-TRIAGE.md — Routing Questions to the Right Investigation Depth

<!-- TOC: Why tier | Tier definitions | Auto-detect heuristics | Complexity overlay | Mid-session retiering | Anti-patterns -->

Mirrors saas-billing's SCOPE-TRIAGE.md and wills's TIER-TRIAGE.md. Pick a tier first; the methodology scales to it. Don't over-build for T1; don't under-build for T4.

---

## Why tier matters

Different research questions warrant different investigation depth. Solo-tier on a multi-million-dollar architecture decision is malpractice. Swarm-tier on "what color should the button be" wastes 8 panes' worth of compute.

The tier determines: roster size, model-family mix, default time budget, mandatory phases, and the depth of operator-side scrutiny.

---

## Tier definitions

| Tier | Customers / stakes | Default mode | Default roster | Wall time | Required artifacts |
|------|---------------------|--------------|----------------|-----------|---------------------|
| **T1 — Curiosity** | Personal exploration; reversible; no production impact | fresh-question | Solo (1 cc) | 30–60 min | question_of_record.md + 1-page summary; full pipeline optional |
| **T2 — Decision-supporting** | Engineering team; reversible with effort; thousands of $ | fresh-question / code-investigation | Pair (cc + cod) | 1–3 h | All standard artifacts; HANDBACK ≤1 page; DRIFT-CHECK skipped is OK |
| **T3 — Strategic** | Org-level decision; partly reversible; tens of thousands of $; impact on multiple teams | fresh-question / corpus-distillation / code-investigation | Squad (cc:3 + cod:1 + gmi:1) | 3–5 h | All standard + DRIFT-CHECK + cross-session learning entry |
| **T4 — High-stakes** | Pre-production / pre-publication / pre-launch; partially-irreversible; six-figure $; reputational | corpus-distillation + adversarial-design-audit | Swarm (8–12 panes, all 3 families) | half-day to full day | All + red-team subagent + extended fresh-eyes audit + verification-first protocol |
| **T5 — Existential** | Foundational decision; irreversible; seven-figure+ stakes; legal/regulatory exposure; multi-year commitment | corpus-distillation + design-audit + drift-check across sessions | Multi-session swarm with deliberate cross-session triangulation | days to weeks | All + ADR (per ADR-PATTERNS.md) + multi-session drift catalog + external review handoff |

---

## Complexity overlay

For each present, bump tier up by 1:

- **Multi-stakeholder** — different stakeholders have different goals; the question hides a coordination problem
- **Time-sensitive** — must converge by a hard deadline; degraded methodology may still be required
- **Adversarial context** — the answer will be challenged by hostile parties; needs extra rigor
- **Multi-domain** — question crosses ≥2 distinct research domains
- **Source-volatile** — the corpus changes faster than session wall time
- **Reversibility-asymmetric** — wrong "no" cheap to correct; wrong "yes" catastrophic (or vice versa)
- **Novelty / no precedent** — no prior art exists; can't cass-mine; pure first-principles
- **Verification expensive** — confirming evidence requires rare resources

Stack additively: "T2 question with multi-domain + adversarial = effectively T4."

---

## Auto-detect heuristics

`bootstrap-session.sh` (or the operator) can pre-suggest a tier based on:

| Signal | Suggested tier |
|--------|----------------|
| User says "quick check" / "rough look" | T1 |
| User mentions team / colleagues / "we" | T2+ |
| User mentions specific decision deadline | T2+ |
| User mentions money figures | T2 if <$10K, T3 if <$100K, T4+ otherwise |
| User mentions "pre-production" / "pre-launch" / "pre-publication" / "before we ship" | T4 |
| User mentions legal / regulatory / compliance | T5 |
| User mentions "we need to defend this" / "expert reviewer" / "audit" | T4+ |
| User includes specific technical artifact (codebase / paper corpus) | infer from artifact size + complexity |
| User's prior brennerbot sessions on this topic exist (per cass) | start at prior session's tier or higher |

When ambiguous, the operator should ASK the user. Tier mismatch is one of the silent failure modes — the user gets a Solo-tier answer and acts on it as if it were Swarm-tier.

---

## Required artifacts per tier

### T1 (Curiosity)

- `intake/question_of_record.md` (mandatory)
- ≥1 hypothesis with falsifier (mandatory)
- 1-page summary (any format)
- Other artifacts optional

### T2 (Decision-supporting)

- All T1 + ≥3 hypotheses including third-alternative
- Full evidence packs per active H
- Phase 5 debate at least once (operator can self-debate if Pair tier)
- HANDBACK.md ≤1 page
- RESUME.md (so user can re-engage later)
- DRIFT-CHECK optional

### T3 (Strategic)

- All T2 + per-family distillations + meta-synthesis + non-empty disagreement_register
- Phase 7 audit converged ≥2 trio-rounds
- DRIFT-CHECK.md mandatory
- Cross-session learning entry committed (per CROSS-SESSION-LEARNING.md)

### T4 (High-stakes)

- All T3 + red-team subagent run (per subagents/red-team.md)
- Verification-first protocol (per VERIFICATION-FIRST.md)
- Phase 7 audit converged ≥3 trio-rounds (extended)
- External-review-ready packet (per attorney-handoff style)
- ADR for every load-bearing decision (per ADR-PATTERNS.md)

### T5 (Existential)

- All T4 + multi-session triangulation
- Drift catalog across sessions (per CROSS-SESSION-LEARNING.md)
- Independent external review BEFORE acting on conclusions
- Reversibility analysis (what's the recovery plan if wrong?)
- Decision memo with explicit dissent (decision-memo-template.md)

---

## Mid-session retiering

If during the session you discover the question is actually higher-tier than initially assessed:

1. Pause. Ask user: "I initially assessed this as T2; I now think this is T3 because of [reason]. Should I escalate?"
2. If user agrees: update `phase0_scope_decision.md § tier` with the change + rationale
3. Add the missing required artifacts for the new tier (likely Phase 4-7 reopens)
4. Recompute wall-time budget; tell the user

Don't silently retier. The user's expectation of cost / time / depth is set by tier. Changing it changes the contract.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| T1 budget on T4 question | Operator runs Squad in 60 min and ships incomplete; user acts on partial answer |
| T5 budget on T1 question | Burns 12+ panes-hours on something the user could've answered themselves |
| Skipping tier assessment | Default Squad tier is fine for most cases but wrong for both extremes |
| Retiering without user notification | The user's mental model of "what they asked for" gets out of sync with what they got |
| Letting the user pick tier without the rubric | They'll pick T1 to save money or T5 to feel safe; both are wrong defaults |
| Tier based on operator-pane availability | "We have 8 panes available, let's use them" is anti-tier — match panes to question, not vice versa |

---

## Tier x archetype matrix

Different archetypes have different *natural* tiers. The matrix:

| Archetype \ Tier | T1 | T2 | T3 | T4 | T5 |
|------------------|----|----|----|----|-----|
| A1 design-space | rare | common | typical | for production architecture | for foundational standards |
| A2 codebase-weakness | rare | for small repos | typical | pre-release | pre-acquisition / pre-IPO |
| A3 methodology distillation | n/a | rare | typical | for publication | for canonical reference |
| A4 incident root-cause | n/a | for self-hosted | typical | for customer-impacting | for regulatory-reportable |
| A5 comparison/benchmark | rare | common | typical | for vendor-selection | for multi-year commitment |
| A6 adversarial design | n/a | rare | rare | typical | for high-value targets |
| A7 decision-under-uncertainty | rare | common | typical | for org-level decisions | for foundational decisions |
| A10 first-principles | common (curiosity) | rare | rare | rare | rare |

Use this matrix to set defaults; the operator can override.

---

## Tier × wall-time budget

Per tier, hard wall-time caps before escalating to operator:

| Tier | Phase 1 | Phase 2 | Phase 3 | Phase 4 (per round) | Phase 5 | Phase 6 | Phase 7 | Phase 8 | Phase 9 | Phase 10 | Total cap |
|------|---------|---------|---------|---------------------|---------|---------|---------|---------|---------|----------|-----------|
| T1 | 5min | n/a (Solo) | 10min | 15min × 2 | inline | 10min | 10min × 1 | 5min | 5min | optional | 60min |
| T2 | 10min | 5min | 15min | 20min × 3 | 30min | 30min | 20min × 2 | 10min | 10min | 30min | 3h |
| T3 | 15min | 10min | 20min | 30min × 4 | 1h | 1h | 30min × 3 | 15min | 15min | 1h | 5h |
| T4 | 30min | 15min | 30min | 1h × 6 | 2h | 2h | 1h × 4 | 30min | 30min | 2h | full day |
| T5 | 1h+ | 30min | 1h+ | 2h+ × 6 | 4h+ | 4h+ | 2h+ × 4 | 1h | 1h | 4h+ | days |

If a phase blows past its tier cap, the operator should pause + decide: escalate tier, accept incomplete, or reframe.
