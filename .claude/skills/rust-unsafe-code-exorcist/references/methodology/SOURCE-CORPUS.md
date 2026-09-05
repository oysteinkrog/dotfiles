# SOURCE-CORPUS.md — Track A Artifact Structure

This skill is a Track A artifact of `/operationalizing-expertise`. It distills a tacit method (the user's lived experience auditing & refactoring unsafe across 10 exemplar Rust projects) into executable, auditable artifacts.

---

## Track A pieces

| Piece | This skill's instance |
|-------|----------------------|
| **Corpus** (primary sources) | The 10 exemplar repos: `/dp/asupersync`, `/dp/beads_rust`, `/dp/mcp_agent_mail_rust`, `/dp/pi_agent_rust`, `/dp/rich_rust`, `/dp/frankensqlite`, `/dp/frankentui`, `/dp/franken_engine`, `/dp/frankenlibc`, `/dp/frankenfs` — present-day source AND git history AND beads. |
| **Quote bank** | `references/source/EXEMPLAR-CATALOG.md` indexes canonical patterns per repo with `[E-NNN]` anchors. CASS query packs that surface each pattern: `references/source/CASS-QUERY-PACK.md`. |
| **Triangulated kernel** | The classification rubric in [CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md) — the (A)/(B)/(C) buckets with falsification tests, distilled from cross-repo consensus. |
| **Operator library** | The 17 operators in [OPERATORS.md](OPERATORS.md). |
| **Validators** | The audit scripts in `../../scripts/` plus the `verify.sh` template in `../patterns/90-OPERATIONS.md`. |
| **Session kickoff prompts** | [KICKOFF-PROMPTS.md](KICKOFF-PROMPTS.md) (per-mode) + [AGENT-PROMPTS.md](AGENT-PROMPTS.md) (per-subagent). |

---

## Evidence chain

Every rule in this skill has an evidence chain back to a specific source pattern.

### Kernel claim

> "Misclassification of (B) as (A) freezes the project at a worse Pareto frontier than necessary."

**Evidence:**
- `/dp/rich_rust` git history: commit `<hash>` removed an `unsafe { _mm_loadu_si128 }` that was originally classified "needs SIMD" by the maintainer; bench showed `std::simd::u8x16` was 1.02× the speed on AVX2 and the unsafe was unnecessary.
- `/dp/frankenlibc` bead `br-237` documents the audit that reclassified 18 unsafe sites from "FFI-required" to "could be safely wrapped by a single thin shim" — saved cargo-geiger count of 213 down to 12.
- CASS hit on `ts1` 2026-03-14: "the 213 calls were all isomorphic; one safe wrapper covered them all."

The kernel claim is now in [CLASSIFICATION-RUBRIC.md § (A) STRICTLY_UNAVOIDABLE](CLASSIFICATION-RUBRIC.md#a-strictly_unavoidable) as a falsification rule.

### Operator claim

> "Operator ⌖ Macro-X-Ray catches unsafe that source-text grep cannot."

**Evidence:**
- `/dp/beads_rust` had 12 unsafe sites visible in source AND 47 unsafe sites visible only after `cargo expand`. The 35 macro-origin sites all came from `zerocopy-derive`, `serde-derive`, and a custom-derived `Repr` macro.
- `/dp/mcp_agent_mail_rust` had `pin-project-lite` expansions that contain `unsafe impl Unpin` per generated type; the operator surfaces every one and lets the audit confirm the macro author's invariants.

This is now in [OPERATORS.md § ⌖ Macro-X-Ray](OPERATORS.md#-macro-x-ray) and [40-MACRO-GENERATED-UNSAFE.md](../patterns/40-MACRO-GENERATED-UNSAFE.md).

### Polish bar claim

> "Every (C) rewrite must have a property-based equivalence test exercising the failure modes of the old unsafe."

**Evidence:**
- `/dp/frankensqlite` PR `#142` shipped a (C) refactor (replaced `mem::transmute<&[u8], &[u32]>` with `zerocopy::FromBytes`) without an equivalence test. A subsequent fuzz finding (`bead br-1842`) revealed the safe version handled trailing-non-aligned-bytes DIFFERENTLY — silent truncation instead of an error. Test would have caught it.
- `/dp/rich_rust` PR `#88` shipped a (C) refactor (replaced hand-rolled SIMD with `std::simd`) WITH equivalence test; the test caught a `NaN` handling discrepancy before merge.

The rule is now in [POLISH-BAR.md § 4. Equivalence witness](POLISH-BAR.md#4-equivalence-witness-c-only).

---

## Per-exemplar-repo summary (compact)

This is the at-a-glance version. The detailed catalog with `[E-NNN]` quote anchors is in `references/source/EXEMPLAR-CATALOG.md`.

| Repo | Primary unsafe class | (A) count | (B) count | (C) refactor wins | Rejected refactors |
|------|---------------------|-----------|-----------|-------------------|-------------------|
| asupersync | io_uring / mmap FFI | high | low | factored to a single safe shim per syscall | replacing io_uring with epoll (lost perf) |
| beads_rust | rusqlite FFI; macro-generated transmute | medium | low | zerocopy migration | none significant |
| mcp_agent_mail_rust | Pin self-ref, ws stream | low (Pin) | low | pin-project where applicable | hand-rolled BufReader (perf loss) |
| pi_agent_rust | embedded volatile MMIO | high | low | safer volatile abstraction crate | replacing core::arch::asm (no safe equiv) |
| rich_rust | SIMD | low | high (B → safe-only feature) | autovec + `wide` where it ties | std::simd for AVX-512 sometimes |
| frankensqlite | C binding | high | low | safer prepared-statement lifetime | abandoning rusqlite (too much work) |
| frankentui | termios / signals | high | medium | safer signal handling via tokio | replacing termios (no portable safe API) |
| franken_engine | scheduler atomics | high | low | arc-swap where contention pattern fits | replacing scheduler core (rejected) |
| frankenlibc | syscall layer | very high | low | single-safe-wrapper-per-syscall pattern | replacing syscall (purpose of the crate) |
| frankenfs | allocator | high | low | bumpalo for in-crate callers | replacing core allocator (purpose) |

---

## How to extend the corpus

When the audit surfaces a NEW canonical pattern (one the exemplar repos don't yet exhibit):

1. **Capture in EXEMPLAR-CATALOG.md.** Add a new `[E-NNN]` entry with the source (commit / bead / file) and a 1-paragraph description.
2. **Cross-reference in the relevant pattern bundle.** If the new pattern is in [40-MACRO-GENERATED-UNSAFE.md], add it there too.
3. **If it changes the kernel** (rare — would be a new bucket or a new falsification rule), open a discussion before editing [CLASSIFICATION-RUBRIC.md]. The kernel is supposed to be stable.
4. **If it's a new operator** (also rare), draft a new card in [OPERATORS.md] with: trigger, failure modes, prompt module, fix section.
5. **Run validators.** `scripts/validate-corpus.py` (if available) checks that new entries have stable IDs, source citations, and aren't duplicates.

---

## How to use the corpus during an audit

The corpus is read in Phase 0.5 (`phase0_exemplar_patterns.md`) and consulted by every subsequent phase:

- **Phase 1 (enumerate).** When ast-grep finds a new `unsafe`, check if the kind matches an `[E-NNN]` pattern; if so, the per-site write-up cites the exemplar precedent.
- **Phase 4 (classify).** When (A) is on the table, check if the exemplar repos shipped this kind of site as (A) — does the falsification justification align with theirs?
- **Phase 5 (plan).** When a (C) rewrite is being drafted, check if an exemplar repo has shipped an equivalent rewrite — copy the structure (not the literal code).
- **Phase 6 (adversarial).** When attacking a classification, the strongest attack often cites an exemplar precedent: "Repo X classified this as (B); why are we calling it (A)?"
- **Phase 10 (reviewer-empathy).** A confident "would I land this" comes from the maintainer recognizing the pattern from their own past work, which is what the exemplar catalog encodes.

---

## Corpus integrity rules

- **Source of truth is the exemplar repo.** If `/dp/rich_rust`'s code disagrees with the catalog entry, the code wins; update the entry.
- **Beads are second-source.** `br show <id>` records the reasoning behind a refactor decision. Cite the bead in the catalog entry.
- **CASS quotes are third-source.** A CASS hit can document reasoning, but it's only as good as the session. Prefer beads when both exist.
- **No catalog entry without a source.** "I think this is how we do it" doesn't get an `[E-NNN]`. Find the commit / bead / session, or don't add it.

---

## Validators

`scripts/validate-corpus.py` (lives in `../../scripts/`):

```bash
# Walk EXEMPLAR-CATALOG.md
# For each [E-NNN] entry:
#   - Confirm source path exists (exemplar repo / commit / bead).
#   - Confirm no duplicate ID.
#   - Confirm the entry's "applies to" tag matches at least one pattern bundle.
# Walk CLASSIFICATION-RUBRIC.md:
#   - Confirm no rule cites a missing [E-NNN].
# Exit non-zero if any of the above fails.
```

This validator is itself in the corpus — it's how we know the corpus is healthy.

---

## Anti-patterns (corpus-specific)

- **"This is how we do it" without a citation.** Find the commit / bead. Catalog entries without sources are folklore.
- **Treating the catalog as exhaustive.** The exemplars cover what we've shipped; new audits will turn up patterns the exemplars don't have. Extend the catalog when that happens.
- **Cargo-culting an exemplar pattern.** A pattern that worked in `/dp/rich_rust` (SIMD) is wrong for a non-SIMD project. The catalog surfaces candidates; the audit's own classification decides.
- **Mining without applicability gating.** The Phase 0.5 cass-miner agent's "Applicability" tag is required. A hit that's not applicable to the current project is noise.
