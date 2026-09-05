# CASE-STUDIES.md — Worked Examples Per Archetype

<!-- TOC: How to use | A1 design-space example | A2 codebase-weakness example | A3 methodology distillation example | A4 incident root-cause example | A5 comparison example | A6 adversarial design example | A7 decision example | A10 first-principles example | Multi-archetype example | Lessons across cases -->

Mirrors saas-billing's CASE-STUDIES.md and wills's case-study sections. Each case study is a sanitized worked example showing how the methodology applies to a concrete question in that archetype.

These are NOT real session transcripts — they're illustrative composites showing the methodology in action. The /brenner_bot/ANALYSIS_OF_USING_BRENNERBOT_FOR_BIO_INSPIRED_NANOCHAT*.md essays are real worked applications of the source method; this file extends with brennerbot-with-ntm-specific cases.

---

## How to use this file

When framing a new session, pick the case study closest to your archetype + tier. Use it to:
- Calibrate wall-time expectations
- See realistic Phase 6 distillation form
- See what HANDBACK.md looks like at this scale
- Anticipate likely failure modes

Don't copy the case study's *content* — every question is unique. Copy the *shape*.

---

## Case A1.1 — Design-space exploration (T2)

**Question:** "What's the best on-disk format for an append-only event log of events under 1KB each, at 10K-100K events/sec, with 30-90 day retention?"

**Tier:** T2 (engineering team, reversible-with-effort, ~$10K)
**Mode:** corpus-distillation (mining benchmark literature)
**Roster:** Pair (cc:1 + cod:1)
**Wall time:** 2.5h

**Phase 1:** Paradox identified — three formats benchmark comparably under different conditions; consensus splits between them. Falsifier: "If a benchmark exists where format X dominates Y by ≥10× across the target workload, the question becomes 'use X'."

**Phase 3:** Three Hs — H-001 (length-prefixed binary), H-002 (JSONL), H-003 (third-alternative: CBOR-of-FlatBuffers + sparse offset index).

**Phase 4 (round 1):** Investigator reads Kafka + Pulsar benchmarks; finds binary frames dominate at ≥100K events/sec. Devil's-advocate finds JSONL benchmarks at 10K-50K events/sec showing tooling cost > parsing cost. Quickie pilot: synthetic 1KB-event throughput on local NVMe — confirms parsing cost dominates only above 50K/sec.

**Phase 4 (round 2):** Falsifier on H-002 fires — the Kafka benchmark shows JSONL's GC pressure exceeds binary by 50% at target rates. H-002 → refuted. H-003 holds with workload-conditional support.

**Phase 5:** H-001 vs H-003 debate. Adjudicator rules: both survive; H-001 better for pure throughput; H-003 better for tooling + offset reads.

**Phase 6:** Per-family distillation. cc emphasizes throughput dominance; cod emphasizes tooling tradeoffs; gmi (added later for triangulation) emphasizes workload-class boundaries. Meta-synthesis: workload-conditional verdict.

**Phase 9 HANDBACK.md** (~70 lines):
- TL;DR: H-001 (binary frames) for ≥50K events/sec workloads where reads are sequential; H-003 (CBOR+offset) for mixed workloads with random reads. JSONL refuted for the target regime.
- Open: H-003 needs production-scale benchmark we couldn't run.
- Recommended next loop: Phase 4 reopen targeting H-003 with real benchmark.
- Risk register: GC tuning could shift the boundary; verify quarterly.

**Phase 10 drift verdict:** convergent. Lesson: the quickie-pilot pattern (per MO-quickie-pilot.md) saved ~3h that flagship benchmarks would've taken.

---

## Case A2.1 — Codebase weakness audit (T3)

**Question:** "Where are the load-bearing weaknesses in our async runtime that prevent it from scaling above 10K concurrent connections?"

**Tier:** T3 (org-level, partly-reversible, $50K-$500K eng investment)
**Mode:** code-investigation
**Roster:** Squad (cc:3 + cod:1 + gmi:1)
**Wall time:** 4h

**Phase 1:** /codebase-archaeology + /codebase-report seeded the corpus. Paradox: claimed O(1) wakeup-cost, but benchmarks at 10K connections show 5x latency vs Tokio. Falsifier: "If a code-level audit produces a specific code path that violates O(1) wakeup-cost under multi-tenant load, the design is constrained."

**Phase 3:** Five Hs covering scheduler hot path, IO driver, task wake mechanism, memory layout, and a third-alternative claim that the benchmark harness itself is wrong.

**Phase 4 (3 rounds):** Investigators dive into specific subsystems. Devil's-Advocate (gmi) attacks the hot-path claim with profiler data. Quickie pilot on the harness — third-alternative survives partial test (harness has known issue but it's not the dominant factor).

**Phase 5:** Adjudicator rules H-002 (scheduler hot path) confirmed via profiler EVs; H-005 (harness issue) confirmed but minor; others refuted.

**Phase 6:** Per-family distillation. Meta-synthesis: scheduler hot path is the load-bearing weakness; specific fix is identified at file:line. Disagreement register: cc vs cod disagree on whether the fix scales beyond 50K connections (deferred).

**Phase 7:** Audit ran 2 trio-rounds. Found a missing ⊞ Scale-Check on the proposed fix (memory bound under N connections). Fix added; H-002 confirmed at `confidence:high`.

**Phase 9 HANDBACK.md** identifies 2 weaknesses, recommends specific fix, ETA estimate, and notes harness improvement as side benefit.

**Phase 10 drift:** convergent with one improvement (using ⟂ Object-Transpose to test the fix on a smaller proxy first instead of full prod-scale benchmark).

---

## Case A3.1 — Methodology distillation (T4)

**Question:** "Distill the cognitive method of Sydney Brenner from this 80-hour transcript and the three model distillations."

**Tier:** T4 (publication-grade, reputational stakes)
**Mode:** corpus-distillation
**Roster:** Swarm (cc:5 + cod:3 + gmi:2)
**Wall time:** 8h

**Phase 1:** Pinned all four sources (transcript + 3 distillations) with content-hash. Paradox: distillations agree on broad strokes but disagree on which moves are load-bearing. Falsifier: "If exhaustive triangulation produces zero genuine disagreements, all distillations were essentially the same and triangulation added nothing."

**Phase 3:** Hypothesis slate is operator-set — each candidate operator from the source gets its own H (e.g., "⊘ Level-Split is load-bearing", "≡ Invariant-Extract is load-bearing"). 14 Hs from Opus + 11 from GPT-5.2 + verbal-only from Gemini = ~17 distinct Hs after triage.

**Phase 4 (4 rounds):** Investigators verify each operator's manifestation in the source corpus. Some operators have abundant §-anchor support (✂ at §147, §69, §103); others are sparse. Devil's-advocates challenge weak operators.

**Phase 5:** Pairwise debates settle which operators are load-bearing. Some get refuted (or merged into others). Final algebra: 15 operators (mix of Opus's 14 + GPT-5.2's ⊙ + 🤝 made explicit).

**Phase 6:** Three per-family distillations PLUS the operator-keyed quote bank. Meta-synthesis registers 12 disagreements (D-001..D-012 in DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md).

**Phase 7:** 3 trio-rounds. Significant audit findings — several operator cards needed sharpening. Fixed.

**Phase 9 HANDBACK:** "The Brenner Method as 15 operators + 2 axioms + the generative loop." Specific recommendations for using it.

**Phase 10 drift:** convergent with two improvements. Lessons committed: (1) productive-ignorance-as-role-binding, (2) explicit Brenner-Crick-GAN framing.

This entire skill is the *result* of an A3.1-style session. The Track A pattern from /operationalizing-expertise was applied to Brenner's transcript.

---

## Case A4.1 — Incident root-cause (T2, compressed)

**Question:** "What is the root cause of the payment double-charge incident at 14:00-14:23 UTC?"

**Tier:** T2 (customer-impacting; partly-reversible via refund)
**Mode:** incident-investigation
**Roster:** Pair (cc:1 + cod:1)
**Wall time:** 45 min (compressed)

**Phase 1 (5min):** Compressed framing. Paradox: Stripe webhook idempotency should prevent double-charges. Falsifier: "If 47 distinct evt_* IDs exist for the same payment_intent_id, Stripe sent the event twice."

**Phase 3 (10min):** Three Hs — H-001 (Stripe sent duplicate events), H-002 (our handler bypassed idempotency), H-003 (third alternative: webhook delivery had a retry storm during a network blip).

**Phase 4 (inline with Phase 5, 15min):** Investigators check Stripe Dashboard (47 distinct evt_* IDs found — H-001 refuted), check handler ingest logs (no duplicate evt_*; H-002 refuted), check network metrics (network blip at 14:01; H-003 confirmed).

**Phase 5 (5min):** Adjudication. H-003 confirmed: webhook delivery hit a retry storm, but the handler processed each delivery as if new because the dedup window had a 14:00 reset bug.

**Phase 7 (5min):** Quick fresh-eyes audit. Identified that the 14:00 reset is hourly clock; bug exposes the same race every hour theoretically. Critical finding.

**Phase 9 (5min):** INCIDENT-VERDICT.md (not HANDBACK):
- Root cause: dedup window resets on the hour; webhook retry burst at 14:00 hit fresh window before previous event fully processed
- Killed alternatives: H-001, H-002 (cited evidence)
- Recommended remediation: rolling dedup window instead of clock-aligned
- Open: post-mortem-formalization mode session in 24h

Skipped Phases 2/6/8/10 per compressed mode.

---

## Case A6.1 — Adversarial design audit (T4)

**Question:** "Find every way our new auth protocol could fail."

**Tier:** T4 (pre-launch security review, reputational/regulatory)
**Mode:** fresh-question with red-team subagent
**Roster:** Squad with TWO Devil's-Advocates + red-team subagent
**Wall time:** 6h

**Phase 1:** Special framing. Falsifier: "If exhaustive search produces zero load-bearing weaknesses, design is unusually robust (verify externally)."

**Phase 3:** Hypothesis slate is threats (≥6 attack classes: passive, active, replay, downgrade, side-channel, social).

**Phase 4 (4 rounds):** Two devil's-advocates work in parallel. Investigators verify protocol behavior against each attack. Quickie pilots for cheap attack classes; flagship for expensive.

**Phase 5:** Adjudication identifies 4 weaknesses. 2 critical, 2 medium.

**Phase 6:** Threat catalog distilled.

**Phase 7:** Red-team subagent runs novel-attack search. Finds 1 additional novel threat (timing oracle) not in the standard threat classes. Total 5 weaknesses.

**Phase 9:** Threat catalog + 5 specific remediations + recommended re-audit after fixes.

**Phase 10:** convergent. Lesson: red-team subagent should be invoked for ALL T4+ adversarial audits (committed to references/).

---

## Case A7.1 — Decision under uncertainty (T3)

**Question:** "Should we adopt async runtime X or stick with our current Tokio?"

**Tier:** T3 (org-level decision)
**Mode:** fresh-question
**Roster:** Squad
**Wall time:** 5h

**Phase 1:** Decision-rule: "If X provides ≥2× p99 latency reduction on our representative workload AND migration cost is ≤6 weeks engineering, adopt; otherwise stay."

**Phase 3:** Two Hs (adopt X, stay with Tokio) + third alternative (hybrid: keep Tokio, adopt X for specific subsystem).

**Phase 4:** Benchmarks via /vibing-with-ntm spawning sub-investigations. p99 latency on X is 1.7× better, not 2×. Migration cost estimated 8 weeks.

**Phase 5:** Decision rule fires "stay with Tokio" — but third-alternative (hybrid) survives. Adjudicator settles: H-001 (adopt X) refuted by decision rule; H-002 (stay) confirmed; H-003 (hybrid) confirmed.

**Phase 6:** Distillation. Recommendation: hybrid; X for hot-path subsystems where 1.7× latency reduction matters; Tokio for everything else.

**Phase 9 (decision memo, not standard HANDBACK):**
- Recommendation: hybrid
- Reasoning: 1.7× latency for hot-path is significant; 8-week migration for full migration not worth it
- Key uncertainties: hybrid maintenance cost (estimated low; verify quarterly)
- What-would-change-the-recommendation: if X reaches 2× via upcoming 2.0 release, reconsider full adoption
- Dissenting opinion (from disagreement register): cod argued for staying with Tokio entirely; reasoning preserved

---

## Case A10.1 — First-principles synthesis (T2)

**Question:** "From first principles, what's the right architecture for a distributed log under crash-only constraints?"

**Tier:** T2
**Mode:** fresh-question with strong productive-ignorance
**Roster:** Pair with TWO ⊙ panes (atypical)
**Wall time:** 3h

**Phase 1:** Corpus deliberately empty. Paradox: existing distributed log architectures (Kafka, Raft-based) bake in many assumptions that may not be load-bearing under crash-only.

**Phase 3:** Both ⊙ panes propose Hs from first principles only — no reading prior art. Three Hs surface. One is essentially Raft (cod ⊙ pane independently re-derived it); one is essentially log-structured-merge variant; one is novel: leaderless quorum with bounded unavailability.

**Phase 4:** Each H probed against simple physics + correctness arguments. ⊞ Scale-Check is dominant operator.

**Phase 5:** Debate. The novel H requires assumptions that don't hold in practice (network with bounded delay). Refuted.

**Phase 6:** Distillation. Raft-derivative wins from first principles; matches industry consensus. Conclusion: industry got this right.

**Phase 9:** Short HANDBACK noting that first-principles re-derivation matched practice — useful for confirming the practice isn't accidental.

**Phase 10:** convergent. Lesson: ⊙ Productive-Ignorance with two ⊙ panes works for genuinely novel-vs-existing comparisons.

---

## Multi-archetype example (A1 + A6 hybrid)

**Question:** "Design a key-value store optimized for adversarial workloads."

This is BOTH A1 (design-space exploration) AND A6 (adversarial concerns from the start). The roster includes both standard Devil's-Advocates AND red-team subagent.

Wall time: T4 (8h). Roster: Swarm.

The case study would mirror A1.1 + A6.1 patterns interleaved. Phase 6 distillation produces both a workload-conditional verdict AND a threat catalog.

---

## Lessons across cases

Reading these case studies, several patterns recur:

1. **Quickie pilots save time** — every successful case used at least one quickie. F-407 (quickie misinterpreted) is rare in practice but high-cost when it happens.
2. **Third alternatives often win** — A1.1 and A7.1 both ended with the third-alternative as the recommendation. Brenner §103 is load-bearing.
3. **Phase 5 adjudicator family rotation matters** — F-502 was caught early in A2.1 only because the rotation rule was followed.
4. **First-principles ≠ no corpus access** — A10.1's ⊙ pane re-derived Raft and matched industry; doesn't mean reading was forbidden, just deferred.
5. **T4 needs red-team subagent** — A6.1 found a novel attack the standard Devil's-Advocates missed.
6. **Wall-time tier estimates are usually accurate** — most cases hit their tier's estimate within 30%.

---

## Adding new case studies

When a session produces a particularly clean / instructive trajectory, sanitize and add as a case study. Required:

- Question (sanitized — generic enough to share)
- Tier + mode + roster + wall time
- Phase-by-phase narrative (≤200 words per phase)
- Verdict + lessons learned
- Cross-link to which archetype (per QUESTION-ARCHETYPES.md)

Don't add real session transcripts (privacy / IP). Compose case studies from patterns observed across multiple sessions of the same archetype.
