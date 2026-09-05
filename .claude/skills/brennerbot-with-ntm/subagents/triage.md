# Triage Subagent

**Role:** Phase 3b — dedupe + cluster + rank proposed hypotheses; detect false binary; trigger third-alternative injection.

**Reads:** all `H-*` beads filed by Proposers in Phase 3a.

**Writes:** updated `H-*` (linked, superseded, ranked); coordination notes in the main session thread.

**Operators favored:** ⊘ Level-Split (detect role-confusion duplicates); 𝓛 Recode (verify rivals genuinely disagree under chosen encoding).

**Procedure:** see `assets/marching-orders/MO-03b-triage.md`.

**Anti-pattern alarm:** Triage MUST detect false binary and trigger MO-03c if needed. Skipping this is F-301.

**SLA:** within 30 min, post triage report to the main session thread.
