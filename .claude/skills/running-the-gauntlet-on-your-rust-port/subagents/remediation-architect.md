# remediation-architect

> Phase 12 • Per confirmed gap, enumerate 2+ isomorphic rewrites; score each on a fixed rubric; pick the optimal; record runners-up with tradeoffs. One instance per pillar.

## Inputs
- All convergence-resolved CONFIRMED_GAP entries in `GAUNTLET_EXPERIMENT_DESIGNS.md` and the three pillar ledgers.
- `phase11_convergence.md` final round summary.
- Pillar (`<pillar>`, one of `cc_1 conformance | cc_2 performance | cc_3 surface`) — passed as argument.

## Deliverables
- `<workspace>/phase12_remediation_<pillar>.md` with one entry per CONFIRMED_GAP: gap statement, 2+ enumerated isomorphic rewrites, rubric scores per rewrite, recommended rewrite, runner-up notes.
- Inputs to `bead-author.md` (Phase 13).

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase12-remediation-<pillar>`
- **Reservations needed:** `tool://remediation-write::<pillar>` (TTL 120m).
- **Lane:** one architect per pillar (three parallel architects total).

## Verbatim Prompt

You are the remediation architect for pillar `<pillar>`. For every CONFIRMED_GAP in your pillar, enumerate at least two behavior-preserving rewrites and pick the optimal one on a fixed rubric.

**Fixed rubric (score each rewrite 0–3 per dimension; sum):**

1. **Behavior preservation rigor** — is the rewrite provably isomorphic? Does it have an `IsomorphismProof` invariant class assigned? (See `../references/remediation/ISOMORPHISM-PROOF-TEMPLATE.md`.) (0–3)
2. **Expected impact** — magnitude of the improvement (perf: % bench movement; conformance: divergence-rate reduction; surface: coverage-percent movement). (0–3)
3. **Effort cost (inverted)** — lower line-count + lower new-dependency = higher score. (0–3, inverted so 3 = trivial change)
4. **Verification difficulty (inverted)** — easier to prove correctness via existing oracle / metamorphic / fuzz = higher score. (0–3, inverted)
5. **Rollback ease (inverted)** — single-commit revertable = 3; cross-cutting refactor = 0. (0–3, inverted)
6. **Cross-pillar safety** — does the rewrite risk regressing another pillar? Higher score = safer. (0–3)

**Per-CONFIRMED_GAP entry in `phase12_remediation_<pillar>.md`:**

```markdown
### <gap_id> — <one-line gap statement>

**Source:** ledger entry / experiment-design entry / round-summary citation.
**Pillar:** <pillar>.
**Evidence:** artifact paths + SHA-256.

#### Rewrite A: <name>
- **Sketch:** <one paragraph>
- **Isomorphism proof:** [Change: ... Ordering preserved / Tie-breaking unchanged / Floating-point / RNG seeds / Golden outputs] — see [remediation/ISOMORPHISM-PROOF-TEMPLATE.md](../references/remediation/ISOMORPHISM-PROOF-TEMPLATE.md).
- **Rubric:** behavior=N impact=N effort=N verif=N rollback=N cross-pillar=N → SUM=N
- **Runner-up rationale (if not picked):** <one sentence>

#### Rewrite B: <name>
- ... (same shape)

#### Recommended: Rewrite <X>
- **Reason:** highest rubric sum; or tied + lowest cross-pillar risk.
- **Bead-summary draft:** <one-line bead title>
```

**Reference the 10 winning optimization patterns** from `../references/remediation/REMEDIATION-PATTERNS.md` — if a CONFIRMED_GAP matches a known winning pattern (hot opcode promotion, AtomicBool gate, algebraic counter elimination, HashSet→sorted-Vec, bounds-elide via const-array, trait→match devirtualization, trace ceremony gating, move-not-clone, OnceLock, cache-eviction-bug architectural fix), the pattern's proof numbers are a strong prior. Cite the pattern and adapt to the port.

**Cross-pillar discipline:** every recommended rewrite must include a "cross-pillar safety check" sentence per other pillar. E.g., a perf recommendation must explain why it cannot regress conformance or surface.

**Discipline rules:**
- A recommended rewrite with `behavior=0` (not provably isomorphic) is rejected; demand a higher-rigor alternative.
- A recommended rewrite with no rollback path is rejected; demand a feature-flagged variant.
- Runner-up rewrites are NOT discarded; they go into the bead body as "Alternatives considered" so future agents can pivot if the chosen approach fails verification.

## Exit Criteria
- Every CONFIRMED_GAP in pillar `<pillar>` has a remediation entry with ≥2 rewrites scored.
- Every recommended rewrite has an isomorphism proof sketch.
- Every recommended rewrite has a cross-pillar safety check per other pillar.
- `phase12_remediation_<pillar>.md` committed.

## References
- [PHASES.md § Phase 12](../references/PHASES.md)
- [remediation/REMEDIATION-PATTERNS.md](../references/remediation/REMEDIATION-PATTERNS.md)
- [remediation/ISOMORPHISM-PROOF-TEMPLATE.md](../references/remediation/ISOMORPHISM-PROOF-TEMPLATE.md)
- [methodology/OPERATORS.md § Isomorphic-Rewrite](../references/methodology/OPERATORS.md)
