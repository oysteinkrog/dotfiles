# ARCHETYPE-START-PACKS.md — Question Archetypes + Pre-Flight Configurations

<!-- TOC: A1 Design-space exploration | A2 Codebase weakness audit | A3 Methodology distillation | A4 Production incident investigation | A5 Comparison/benchmarking | A6 Adversarial design audit | A7 Decision under uncertainty | A8 Resume / second-pass | A9 Methodology drift check | A10 First principles synthesis | How to use these archetypes | Extending the catalog -->

Every research question maps roughly to an archetype. The archetype determines: roster default, mode default, common operators applied early, common failure modes to anticipate, common evidence-pack methodology, common audit findings.

This file mirrors wills-and-estate-planning's ARCHETYPE-START-PACKS — the archetype is a fast-start preset; the operator can override.

---

## Archetype A1 — Design-space exploration

**Trigger phrasings:**
- "What's the best way to <do X>?"
- "What's the design space for <Y>?"
- "What architecture should we pick for <Z>?"

**Default mode:** `fresh-question` or `corpus-distillation` (if relevant literature exists).

**Default roster:** Squad. Mix: `cc:3,cod:1,gmi:1`. Productive-ignorance pane on cc.

**Phase 1 emphasis:** ◊ Paradox-Hunt is critical. Most "design space" questions hide a tacit consensus. The paradox is usually: "Industry says X dominates, but Y benchmarks comparably, and a third class Z exists. Why hasn't Z taken over?"

**Default scope discipline:** Force out-of-scope to specify *workload class* / *constraint regime*. "Best on-disk format" without workload constraints is malformed.

**Common operators in Phase 4:**
- ⟂ Object-Transpose — pick a small benchmark proxy, not the full real workload
- ↑ Amplify — find the regime where the design choices have ≥10× difference
- ⊞ Scale-Check — verify the math/physics actually permits each candidate

**Common failure modes:**
- F-101 (too broad) — VERY common; most users start with no scope
- F-301 (false binary) — typical "X vs Y" framings need explicit third alternative
- F-403 (confirmation only) — investigators tend to confirm consensus

**Default Phase 6 distillation form:** "Best for workload class W₁ is <X>; best for W₂ is <Y>; best for W₃ is <Z>; the three boundaries are at <thresholds>." Workload-conditional answers are the typical convergence.

---

## Archetype A2 — Codebase weakness audit

**Trigger phrasings:**
- "Where are the load-bearing weaknesses in <codebase>?"
- "What would prevent <codebase> from scaling to <regime>?"
- "Find the design weaknesses in <repo>."

**Default mode:** `code-investigation`.

**Default roster:** Squad. Mix: `cc:3,cod:1,gmi:1`. Productive-ignorance pane on gmi (different framing for the contrarian).

**Phase 1 emphasis:** Run `/codebase-archaeology` first; pin codebase at `git rev-parse HEAD`; record dirty status. The paradox is usually: "Claimed feature X is documented; but benchmark Y suggests X breaks at scale Z."

**Common operators in Phase 4:**
- ⌂ Materialize — investigators must produce a verbatim file:line citation, not "I looked"
- 🔧 DIY — investigators allowed (encouraged) to write quick benchmarks in `deliverables/scripts/`
- ⊞ Scale-Check — every load-bearing claim needs the math

**Common failure modes:**
- F-303 (unfalsifiable hypothesis) — "this is bad code" is not a hypothesis; "function F at file:line will fail under condition C" is
- F-401 (evidence inflation) — investigators read code without probing falsifiers
- F-503 (rhetoric debate) — "I prefer X over Y" is rhetoric

**Default Phase 6 distillation form:** "Top-N weaknesses ranked by exploit-likelihood × blast-radius, each with a falsifier-grade EV citing file:line, each with a recommended remediation." Don't ship "vague design concerns."

---

## Archetype A3 — Methodology distillation

**Trigger phrasings:**
- "Distill the methodology of <expert/domain> from these sources."
- "Operationalize <approach> as a reusable framework."
- "Extract the operator algebra of <expert>."

**Default mode:** `corpus-distillation`.

**Default roster:** Swarm (8–12 panes). Multi-model triangulation is the *point* of methodology distillation.

**Phase 1 emphasis:** Pin the corpus content-hashes meticulously. The paradox is usually: "Multiple writeups of the methodology agree on broad strokes but disagree on which moves are load-bearing."

**Common operators in Phase 6:**
- ≡ Invariant-Extract — what holds across all source distillations? That's the kernel
- ⊘ Level-Split — disagreements often about what *level* the methodology operates at
- 🤝 GAN — Phase 5 debates between distillation-perspectives is high-signal

**Common failure modes:**
- F-601 (silently averaged) — distillations agree by softening; the disagreement register is empty → reject
- F-602 (single family dominance) — the dominant model's framing wins by default → re-dispatch with different family meta-synthesizer
- F-603 (no register) — hard invariant; cannot exit Phase 6

**Default Phase 6 distillation form:** Mirrors this skill's own structure: corpus → quote bank → triangulated kernel → operator library → validators. The artifact is a Track A operationalization of the methodology.

---

## Archetype A4 — Production incident investigation

**Trigger phrasings:**
- "What's the root cause of <incident>?"
- "Why did <component> fail?"
- "Post-mortem for <event>."

**Default mode:** `incident-investigation` (compressed).

**Default roster:** Pair. Mix: `cc:1,cod:1`.

**Phase 1 emphasis:** Skip exhaustive corpus assembly. Use whatever logs/dashboards/metrics are immediately accessible. Falsifier must be falsifiable in <30 min by an investigator.

**Common operators:**
- ⌂ Materialize (tight) — every hypothesis names a specific log line / metric / event
- ✂ Exclusion-Test (tight) — what observation, if seen in the next 15 min of log scanning, would kill this hypothesis?
- 🤝 GAN compressed — investigator + devil's-advocate run as paired panes; debate is fast

**Common failure modes:**
- "Multiple causes" temptation — incident investigations should converge on ≤2 root causes
- Premature closure — "we found A; ship the fix" without falsifier on B/C alternatives
- Adjudication on rhetoric — "this looks like the cause" is not enough; cite the log line

**Default Phase 9 form:** `INCIDENT-VERDICT.md` (not HANDBACK.md):
- Root cause (with EV-NNN log/metric citations)
- Killed alternatives (with falsifier-fired EV)
- Recommended remediation
- Open questions deferred to a proper post-mortem

---

## Archetype A5 — Comparison/benchmarking

**Trigger phrasings:**
- "Compare <X> and <Y> on <criteria>."
- "Which is better — <X> or <Y>?"
- "Benchmark <X> against <Y>."

**Default mode:** `fresh-question` (with corpus-distillation if benchmark literature is available).

**Default roster:** Pair to Squad. Productive-ignorance role is critical here: a pane that doesn't read the existing benchmark literature can spot misframings.

**Phase 1 emphasis:** Force a precise comparison schema. "Better" without metric is malformed. The falsifier is usually: "If metric M shows X dominates Y by ≥<threshold> across workload classes W₁..W_n, the comparison is decisive."

**Critical guard:** false-binary check. The third alternative is often "neither — under workload Z, option <Z> is better than both." Always inject (per Brenner §103).

**Common operators in Phase 4:**
- ⟂ Object-Transpose — pick the right benchmark proxy
- ↑ Amplify — find the regime where differences are large
- ⊞ Scale-Check — verify the benchmark conditions are physically realistic

**Default Phase 6 distillation form:** "Comparison matrix with per-workload-class verdicts; under <W₁>, X dominates by N×; under <W₂>, Y dominates by M×; under <W₃>, Z (the third alternative) emerges."

---

## Archetype A6 — Adversarial design audit

**Trigger phrasings:**
- "Find every way <design> could fail."
- "Adversarial review of <proposal>."
- "Where would an attacker break <system>?"

**Default mode:** `fresh-question` or `code-investigation`.

**Default roster:** Squad with **TWO** Devil's-Advocate panes (rather than one).

**Phase 1 emphasis:** The question of record is unusual: the falsifier is "the design has zero load-bearing weaknesses" — i.e., we expect to find weaknesses; failing to find any is the falsifier-firing condition.

**Common operators:**
- ✂ Exclusion-Test — exhaustive forbidden-pattern enumeration
- ⊞ Scale-Check — adversaries exploit scale asymmetries
- ΔE Exception-Quarantine — anomalies in design behavior are starting points for attack hypotheses
- ⊕ Cross-Domain (sub of ⊙) — apply known attack patterns from adjacent domains

**Common failure modes:**
- Excessive devil's-advocacy — F-501 (kills everything) — distinguish "found a weakness" from "claimed a weakness rhetorically"
- Surface-only critique — Phase 7 audit must check that critiques cite specific code paths/protocol steps, not abstract concerns

**Default Phase 6 distillation form:** Threat catalog: each threat with `attack:`, `precondition:`, `evidence_to_confirm:`, `severity:`, `recommended_remediation:`.

---

## Archetype A7 — Decision under uncertainty

**Trigger phrasings:**
- "Should we do <X> or <Y>?"
- "Is <approach> the right choice given <constraints>?"
- "Make a decision on <topic> by <date>."

**Default mode:** `fresh-question`.

**Default roster:** Squad with one pane explicitly assigned as "decision-recorder" (synthesizer variant).

**Phase 1 emphasis:** The falsifier here is the *decision rule* — what observation would change the recommended choice? Force the user to articulate this explicitly.

**Common operators:**
- ⊘ Level-Split — "should we do X" is often two questions (technical: can we? values: should we?)
- ◊ Paradox-Hunt — the decision is hard precisely because there's a tension; surface it
- ↑ Amplify — find the regime where the choice clearly matters (small differences = analysis paralysis)

**Default Phase 9 form:** Decision memo: recommendation, reasoning, key uncertainties, what-would-change-the-recommendation, dissenting opinions surfaced from disagreement_register.md.

---

## Archetype A8 — Resume / second-pass

**Trigger phrasings:**
- "Resume the <session>"
- "Run another pass on <workspace>"
- "Re-investigate <question> with fresh eyes"

**Default mode:** `resume-session`.

**Default roster:** Inherit from prior session (per RESUME.md.roster), but rotate model families if possible (different families bring fresh perspective).

**Phase 1 emphasis:** Skip Phase 1 framing. The question of record is fixed (per RESUME.md hash verification).

**Common operators:**
- ∿ Dephase — second-pass perspective; was the first pass in-phase with a consensus that didn't deserve it?
- ΔE Exception-Quarantine — anomalies that were quarantined in pass 1 may now cluster

**Default Phase 9 form:** Updated HANDBACK.md noting *what changed* between passes.

---

## Archetype A9 — Methodology drift check

**Trigger phrasings:**
- "How did our last session diverge from canonical Brenner?"
- "Audit our methodology against the source."
- "Drift check on <session>."

**Default mode:** `methodology-drift-check`.

**Default roster:** Solo (one fresh general-purpose Agent — NOT a swarm pane).

**Phase 1 emphasis:** Skip framing entirely. The "question" is structural: did the session apply canonical Brenner operators in canonical order with canonical exit criteria?

**Common operators:**
- ∿ Dephase — was the session in-phase with prior session's framings? (drift accumulates)
- ◊ Paradox-Hunt — between intended trajectory and actual trajectory

**Default Phase 9 form:** DRIFT-CHECK.md only (no HANDBACK.md needed — the drift report IS the handback).

---

## Archetype A10 — First principles synthesis

**Trigger phrasings:**
- "What does first principles say about <X>?"
- "Reason from scratch about <Y>."
- "Strip away assumptions and rebuild <Z>."

**Default mode:** `fresh-question`.

**Default roster:** Pair to Squad with strong productive-ignorance — designate ≥2 panes as ⊙ panes.

**Phase 1 emphasis:** The corpus is *deliberately minimal* — only the question of record. The hypothesis space comes from the panes' first-principles reasoning, not from prior literature.

**Common operators:**
- ⊙ Productive-Ignorance — the load-bearing operator
- ⊞ Scale-Check — first-principles claims must hold up to scale checks
- 𝓛 Recode — finding the right encoding is the move

**Default Phase 6 distillation form:** "From <small set of axioms>, the following claims follow: <list>. The argument structure is: <chain>."

---

## How to use these archetypes

At Phase 0 confirmation, the operator suggests an archetype based on the user's raw ask. The user can:

- Accept the archetype's defaults → fast-start
- Override defaults → custom configuration
- Reject the archetype → declare a new one (and feed back into ARCHETYPE-START-PACKS.md as a Phase 10 lesson)

Archetypes are *defaults*, not destiny. Mid-session, if the question turns out to be a different archetype, the operator may rebind defaults — record the rebinding in `phase0_scope_decision.md § archetype_changes`.

---

## Extending the catalog

If a session reveals a new archetype not represented above, Phase 10 drift-check should propose a new entry. Required fields:

- Trigger phrasings (≥3)
- Default mode + roster + model mix
- Phase 1 emphasis (paradox shape, scope discipline)
- Common operators per phase
- Common failure modes (with F-### codes)
- Default Phase 6/9 distillation form

The skill grows by accumulating archetypes the way a doctor's office accumulates case notes. Each archetype represents a stable pattern of *question shape* that warrants a calibrated start.
