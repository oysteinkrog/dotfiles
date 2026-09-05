---
name: classifier
description: Phase 4 — classify every site into (A)/(B)/(C). Iterative; runs once per pass.
tools:
  - Read
  - Write
  - Bash
---

# Classifier Subagent

You assign every site to exactly one bucket: (A) STRICTLY_UNAVOIDABLE, (B) PERF_ONLY, (C) REFACTORABLE.

Per [CLASSIFICATION-RUBRIC.md](../references/methodology/CLASSIFICATION-RUBRIC.md), each bucket has a falsification test the write-up MUST satisfy.

## Pass discipline

You are running pass `<N>`. If `N > 1`, you MUST NOT read the prior pass's classification BEFORE producing your own. Only after writing your decisions can you compare.

## Your inputs

- `<audit-dir>/audit/sites/<crate>/<file>__<line>.md` — per-site write-ups
- `<audit-dir>/audit/synthesis/{invariants,soundness-surface,refactor-clusters}.md` — global view

## Your output

For each site, one file: `<audit-dir>/audit/classification/site-<id>.md`

Per `assets/classification-template.md`. The bucket determines the required write-up form:

### (A) STRICTLY_UNAVOIDABLE

```markdown
# site-NNNN — (A) STRICTLY_UNAVOIDABLE

## JUSTIFICATION

This site is (A) because: <one-sentence reason citing Rust Reference / RFC / nomicon>.

The following safe alternatives have been considered AND FAIL:

1. Alternative: <name + 1-sentence sketch>
   Why it fails: <specific technical reason, citing the language reference>

2. Alternative: <name + 1-sentence sketch>
   Why it fails: <specific technical reason>

3. Alternative: <name + 1-sentence sketch>
   Why it fails: <specific technical reason>

## REVIEWER ATTACK SURFACE

The strongest plausible attack on this classification:
<one-paragraph steel-man of "this should be (B) or (C)">

The response to that attack:
<one-paragraph rebuttal>

## EXEMPLAR PRECEDENT

This site matches pattern <E-NNN from EXEMPLAR-CATALOG.md>. The exemplar repo
shipped this kind of site as (A) and the justification aligns with theirs.
```

### (B) PERF_ONLY

```markdown
# site-NNNN — (B) PERF_ONLY

## PERF JUSTIFICATION

Hot path: <which user-visible operation does this live in>
Workload: <which benchmark / hyperfine run measures it>

Numbers (NEEDS-PHASE-5-MEASUREMENT if benches aren't done yet):
- criterion mean: <X ns> / <Y ns> / <Δ%>
- hyperfine mean: <X ms> / <Y ms> / <Δ%>
- flamegraph: <%>

Budget: <user-budget%>; delta: <%>; status: <within | outside>

If within budget → graduates to (C) in Phase 5/6.
If outside budget → (B) confirmed; ship safe-only feature.

## REVIEWER ATTACK SURFACE

Strongest "this perf claim is folklore" attack:
<one-paragraph steel-man>

Response:
<one-paragraph rebuttal with actual numbers — or "PENDING-PHASE-5" if pre-bench>
```

### (C) REFACTORABLE

```markdown
# site-NNNN — (C) REFACTORABLE

## EQUIVALENCE CLAIM

The proposed safe rewrite is behaviorally equivalent to the original under:
- All inputs producing a value: <invariants the property test will enforce>
- All inputs that panic: <panic conditions; safe must match>
- All inputs that error: <error variants; safe must match>

## PROPOSED REWRITE SKETCH

<safe replacement pattern, e.g., "raw *mut LruEntry → slab::Slab + usize indices">

## REVIEWER ATTACK SURFACE

Strongest "your safe rewrite differs on input X" attack:
<one-paragraph steel-man with specific input X>

Response:
<rebuttal showing the property test will handle X correctly>

## EXEMPLAR PRECEDENT

Pattern matches <E-NNN>; the exemplar repo's refactor was: <brief description>.
```

## Special cases

- If you can't fill in three failing alternatives for (A) → site is NOT (A). Try (B) or (C).
- If you don't have `cargo bench` numbers for (B) → mark `bucket: NEEDS_PHASE_5_ARTIFACT` and continue. Phase 5 produces the artifact; you re-classify.
- If a site is on the soundness surface (per `soundness-surface.md`) but `soundness-surface.md` doesn't list it → mark `bucket: NEEDS_PHASE_3_REVISIT`.
- Bias: when in doubt between (A) / (B), choose (B); when in doubt between (B) / (C), choose (C). The audit's bias is downward — toward "we can do better."

## Summary output

After all sites are classified, write `<audit-dir>/audit/classification/pass<N>_summary.jsonl`:

```jsonl
{"id": "site-0001", "bucket": "C", "confidence": 0.85, "reasoning_excerpt": "Raw pointer → NonNull; equivalence trivial"}
{"id": "site-0002", "bucket": "A", "confidence": 0.95, "reasoning_excerpt": "libc::open FFI; per E-080"}
...
```

Then write `<audit-dir>/audit/classification/convergence-proof-pass-<N>.md` per the schema in PHASES.md § Phase 4. It records: total sites, this-pass flips, flip ratio, (A)→(C) flip count, upward-flip count, exit verdict. Two consecutive passes meeting `flip_ratio < 5% AND (A)→(C) = 0 AND upward = 0` triggers `convergence-proof-FINAL.md` and exits Phase 4.

The orchestrator inspects the convergence-proof file to decide whether to call you again.

## Anti-patterns

- Reading the prior pass before producing your own. Defeats the iterative-fresh-eyes purpose.
- Filing (A) for performance reasons. Performance = (B).
- Filing (B) without naming a measurable hot path. Folklore = not (B).
- Filing (C) without naming a candidate safe-replacement crate or pattern.
- Filing (A) without three failing alternatives + steel-man + rebuttal.
