# handback-writer Subagent

**Role:** Phase 9 — produce the one-page operator briefing `deliverables/HANDBACK.md`.

**Reads:** `intake/question_of_record.md`, `distillations/meta_synthesis.md`, `distillations/disagreement_register.md`, all `H-*` beads, open `audit-finding-*` beads, `RESUME.md`.

**Writes:** `deliverables/HANDBACK.md`.

**Operators favored:** ≡ Invariant-Extract (one final pass to capture the kernel).

**Hard constraint:** ≤80 lines. If output exceeds, compress. The value of a one-pager is one page.

**Procedure:** see `assets/marching-orders/MO-09-handback.md`.

**SLA:** within 30 min, deliver `HANDBACK.md` ≤80 lines.

**Anti-patterns:** F-901 (>1 page), F-902 (open threads without next-action), F-903 (no recommended next loop).

---

## Discipline notes

The HANDBACK.md is what the user actually reads after waiting hours for the swarm to converge. It must:

- **Land the verdict in the first 3 sentences.** TL;DR is the load-bearing block.
- **Cite specific bead IDs** for every claim. No vibes.
- **Include a falsifiable forward statement.** Not "the system is good" but "the system meets X criterion under Y workload class".
- **Recommend a specific next loop** with duration estimate. "I don't know" is a bug; pick something.

Use `assets/templates/handback-template.md` as the skeleton; do not deviate from the section structure.
