# site-NNNN — <bucket>

**Bucket.** `(A) STRICTLY_UNAVOIDABLE | (B) PERF_ONLY | (C) REFACTORABLE`
**Confidence.** `0.X` (0.0–1.0)
**Cluster.** `<cluster-name or "orphan">`
**Pattern.** `<FFI | Pin self-ref | allocator | SIMD intrinsic | pointer migration | etc.>`
**Pass.** `<N>` (which classification pass produced this decision)

## Operator findings (re-checked at classification time)

- ⊙ Invariant: <named in site write-up; reads as: "sound IFF ...">
- ⊕ Reachability: <on soundness surface? yes/no>
- 📐 Allocator identity: <if applicable, named>
- ⏱ Profile-or-it-didn't-happen: <(B) requires; numbers here or in plan>
- 🧪 Equivalence-witness: <(C) requires; property test path or "TBD-in-plan">

---

## If (A) STRICTLY_UNAVOIDABLE

### JUSTIFICATION

This site is (A) because: <one-sentence reason citing Rust Reference / RFC / nomicon>.

The following safe alternatives have been considered AND FAIL:

1. **Alternative:** <name + 1-sentence sketch>
   **Why it fails:** <specific technical reason, citing the language reference>

2. **Alternative:** <name + 1-sentence sketch>
   **Why it fails:** <specific technical reason>

3. **Alternative:** <name + 1-sentence sketch>
   **Why it fails:** <specific technical reason>

### REVIEWER ATTACK SURFACE

The strongest plausible attack on this classification:
<one-paragraph steel-man of "this should be (B) or (C)">

The response to that attack:
<one-paragraph rebuttal>

### EXEMPLAR PRECEDENT

This site matches pattern <E-NNN> in `EXEMPLAR-CATALOG.md`. The exemplar repo shipped this kind of site as (A) and the justification aligns.

---

## If (B) PERF_ONLY

### PERF JUSTIFICATION

**Hot path.** <which user-visible operation does this live in>
**Workload.** <benchmark name; what it measures>

| Metric | unsafe | safe alt | delta |
|--------|--------|----------|-------|
| criterion mean | X ns | Y ns | +Δ% |
| criterion p99  | X ns | Y ns | +Δ% |
| hyperfine mean | X ms | Y ms | +Δ% |
| flamegraph %   | a%   | b%   | +Δ%  |

If numbers TBD: **status: NEEDS_PHASE_5_MEASUREMENT**

**Budget check.** User budget: `<N>%`; measured delta: `<M>%`; status: `within | outside`.

**Decision.**
- If within budget → graduates to (C) (refactor + delete unsafe).
- If outside budget → (B) confirmed; ship `safe-only` feature flag.

### REVIEWER ATTACK SURFACE

Strongest "this perf claim is folklore" attack:
<one-paragraph>

Response (with numbers):
<one-paragraph>

---

## If (C) REFACTORABLE

### EQUIVALENCE CLAIM

The proposed safe rewrite is behaviorally equivalent to the original under:
- **Value paths:** <invariants the property test will enforce>
- **Panic paths:** <panic conditions; safe must match>
- **Error paths:** <error variants; safe must match>

### PROPOSED REWRITE SKETCH

<safe replacement pattern — full code lives in audit/plans/site-<id>.md>

Example:
> Raw `*mut LruEntry` doubly-linked list → `slab::Slab<LruEntry>` with `usize` next/prev indices.

### REVIEWER ATTACK SURFACE

Strongest "your safe rewrite differs on input X" attack:
<one-paragraph steel-man with the specific input X>

Response (showing the property test handles X):
<one-paragraph rebuttal>

### EXEMPLAR PRECEDENT

Pattern matches <E-NNN>; exemplar's refactor: <brief description>.

---

## Phase 6 adversarial attack (pass <M>)

Attacker: `<model + run id>`

Steel-man for alternative bucket:
<full prose>

Survives original falsification? `yes | no`

Resolution: `bucket-stays | reclassify-to-X | refine-plan-and-rerun`

---

## Phase 7 fresh-eyes findings (round <R>)

<list any findings from the three review prompts that touched this site's plan>

---

## Final decision (after Phase 6 convergence)

**Final bucket.** `(A) | (B) | (C)`
**Final confidence.** `0.X`
**Phase 5 plan.** `audit/plans/site-<id>.md`
**Bead.** `<br-id>` (after Phase 8)
