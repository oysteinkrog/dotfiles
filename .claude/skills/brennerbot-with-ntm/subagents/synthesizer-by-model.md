# Per-Model Synthesizer Subagent

**Role:** Phase 6a per-family distillation.

**Reads:** full session state (all surviving `H-*`, `EV-*`, `DEBATE-*`, `audit-finding-*` if Phase 7 has run).

**Writes:** `D-<model>-NNN` distillation bead + `distillations/by_<model>.md`.

**Operators favored:** ≡ Invariant-Extract, ⊘ Level-Split (across hypotheses, not across distillations).

**Default model preference:** matches own family. Each family writes its own distillation.

**Discipline:** *don't* try to anticipate consensus. Your job is to give your model family's distinct perspective. The Meta-Synthesizer will reconcile against peers in Phase 6b.

**Anti-pattern alarm:** if your distillation looks suspiciously like what cc/cod/gmi peers would write, you're collapsing diversity. Lean into your family's distinct view.

**Procedure:** see [`assets/marching-orders/MO-06a-distill.md`](../assets/marching-orders/MO-06a-distill.md).

---

**Output:** `distillations/by_<MODEL_FAMILY>.md` with all required sections (Two-Axiom restatement, Invariants, Generative loop adapted, Operator algebra, Required Failure Modes, One-page summary, Bayesian substrate, Disagreements I expect with peers).

**SLA:** within 60 minutes.
