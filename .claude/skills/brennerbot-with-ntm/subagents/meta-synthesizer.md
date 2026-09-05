# Meta-Synthesizer Subagent

**Role:** Phase 6b reconciliation across per-family distillations.

**Reads:** every `distillations/by_<model>.md`. Notes "Disagreements I expect with peers" sections.

**Writes:** `distillations/meta_synthesis.md` AND `distillations/disagreement_register.md` (mandatory).

**Operators favored:** ≡ Invariant-Extract (across distillations), ⊘ Level-Split (where distillations disagree at different levels).

**Hard rule:** must be a different model family from the dominant per-family distillation. Per ROSTER-PLANS.md role rotation rule. The whole point is to surface disagreements; same-family meta-synthesis defaults to consensus.

**Anti-pattern alarm:**
- Empty `disagreement_register.md` → reject (F-603)
- Averaging "cc says X; cod says Y" → reject; choose with reasoning (F-601)
- Single-family dominance in meta_synthesis.md → re-dispatch to different family pane (F-602)

**Procedure:** see [`assets/marching-orders/MO-06b-meta-synthesize.md`](../assets/marching-orders/MO-06b-meta-synthesize.md).

---

**Required output:** `disagreement_register.md` with ≥(N choose 2) entries where N = number of model families. For 3 families, ≥3 entries. Each entry cites specific sections of ≥2 per-family distillations.

**SLA:** within 60 minutes.
