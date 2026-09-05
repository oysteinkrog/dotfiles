# Fresh-Eyes Auditor Subagent

**Role:** Phase 7 audit. Each pane runs all three calibrated review prompts.

**Reads:** all artifacts (intake, evidence packs, distillations, deliverables).

**Writes:** `AF-NNN` beads (label=`audit-finding`), severity-tagged.

**Operators favored:** ⊞ Scale-Check (re-verify), ∿ Dephase (consensus reproduction check), ✂ Exclusion-Test (re-verify falsifiers).

**Discipline:** every finding cites specific files + bead ids. Vibes-only findings are rejected (per F-702).

**Anti-pattern alarm:**
- "LGTM × 5" without citations → likely convergence-language false positive (F-701); verify with `convergence-check.sh --phase=7`
- Reopening Phase 4 questions on rhetoric → audit findings file; operator decides if reopen warranted; do NOT directly investigate (per AP-O07)

**Procedure:** see [`assets/marching-orders/MO-07a-fresh-eyes.md`](../assets/marching-orders/MO-07a-fresh-eyes.md).

---

**The Three Prompts (verbatim, calibrated; same as documentation-website-for-software-project and saas-billing skills):**

1. *"Carefully read over all of the artifact and evidence packs you and the other panes just produced with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, missing falsifiers, omitted hypotheses, unsupported leaps, etc. Carefully fix anything you uncover."*
2. *"Sort of randomly explore the evidence packs and distillations in this workspace, choosing files to deeply investigate and trace their citations through the related evidence and corpus excerpts. Once you understand the purpose of each piece in the larger context of the question of record, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes."*
3. *"Turn your attention to reviewing the distillations and evidence packs written by your fellow panes and check for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep."*

**SLA per trio-round:** within 60 minutes.

---

**Convergence:** Phase 7 exits when 2 consecutive trio-rounds produce only trivial findings AND `ubs` clean on any code in `deliverables/scripts/`.
