# Pattern Library — Index

The gauntlet's pattern library is the catalog of every reproducible discipline mined from the FrankenSQLite bibles, organized in step-of-5 numbering so future insertions don't churn IDs.

Each pattern file follows the same structure:
1. **What** — one-paragraph statement of the pattern.
2. **Why** — the failure mode the pattern prevents, with verbatim quote anchor.
3. **Where in FrankenSQLite** — the file(s) to read as authoritative source.
4. **Verbatim shape** — code/struct/contract lifted verbatim or near-verbatim.
5. **Per-class instantiation** — table or sub-sections per project class.
6. **Composition** — which other patterns this one chains with.
7. **Pitfalls** — common ways to think you've adopted it but actually haven't.

Numbered families (step-of-5 with room for future insertions):

## Kernel (00–095)

| ID | Pattern | Pillar |
|---|---|---|
| [00-KERNEL-AXIOMS](00-KERNEL-AXIOMS.md) | The 12 K-N axioms summary | all |
| [05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md) | The engine of every gate | conformance |
| [10-REFERENCE-PINNING](10-REFERENCE-PINNING.md) | `<reference>_version_contract.toml` | all |
| [15-ENGINE-IDENTITY](15-ENGINE-IDENTITY.md) | `Subject::<port>` vs `Oracle::<reference>` discriminator | conformance |
| [20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) | Green/yellow/red precondition before every certification lane | conformance |
| [25-FIXTURE-ROOT-CONTRACT](25-FIXTURE-ROOT-CONTRACT.md) | Manifest SHA-256 + cardinality floors | conformance |
| [30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) | Content-addressed `artifact_id = SHA-256(canonical JSON \ run_id)` | conformance |
| [35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md) | Render-to-canonical-string comparator | conformance |
| [40-METAMORPHIC-TRANSFORMS](40-METAMORPHIC-TRANSFORMS.md) | 4 TransformFamilies × EquivalenceExpectation | conformance |
| [45-MISMATCH-MINIMIZER](45-MISMATCH-MINIMIZER.md) | Delta-debug + schema-preservation guard + `MismatchSignature` | conformance |
| [50-THREE-TIER-EQUIVALENCE](50-THREE-TIER-EQUIVALENCE.md) | Tier1 raw / Tier2 canonical / Tier3 logical | conformance |
| [55-INSTA-GOLDEN-SNAPSHOTS](55-INSTA-GOLDEN-SNAPSHOTS.md) | Internal-layer regression pinning | conformance |
| [60-FAULT-VFS](60-FAULT-VFS.md) | Declarative `FaultSpec` with stable seeds | conformance |
| [65-CRASH-BOUNDARIES](65-CRASH-BOUNDARIES.md) | Named protocol boundaries (8 for SQL, 6+ for RESP, ...) | conformance |
| [70-E-PROCESSES](70-E-PROCESSES.md) | Ville-bounded anytime-valid invariant monitoring | conformance |
| [75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) | Beta posterior + distribution-free band; release uses LOWER bound | conformance |
| [80-BOCPD-REGIME-DETECTION](80-BOCPD-REGIME-DETECTION.md) | Stable / Improving / Regressing / ShiftDetected on parity stream | conformance |
| [85-ADVERSARIAL-SEARCH](85-ADVERSARIAL-SEARCH.md) | Active probing of every gate to find boundary flips | all |
| [90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) | `v1.0.0` with `/failure/first_divergence` jsonptr | conformance |
| [95-FIRST-FAILURE-EXPLAINER](95-FIRST-FAILURE-EXPLAINER.md) | Replay command + remediation playbook + artifact hashes | all |

## Surface (100–120)

| ID | Pattern | Pillar |
|---|---|---|
| [100-E2E-LOG-SCHEMA](100-E2E-LOG-SCHEMA.md) | Logs-as-API contract | all |
| [105-FEATURE-UNIVERSE](105-FEATURE-UNIVERSE.md) | `Feature { id, title, weight, status, exclusion_rationale }` | surface |
| [110-INVARIANT-CATALOG](110-INVARIANT-CATALOG.md) | `ParityInvariant + ProofObligation + ArtifactRef` | surface |
| [115-CLOSURE-WAVE](115-CLOSURE-WAVE.md) | Per-pipeline-stage gap closure (enumerate first, test after) | surface |
| [120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) | `pass | fail-missing-evidence | fail-invalid-references | fail-mixed` × base gate | surface |

## Performance (125–175)

| ID | Pattern | Pillar |
|---|---|---|
| [125-COMPREHENSIVE-BENCH](125-COMPREHENSIVE-BENCH.md) | Six timing constants + JSON v3 + three orthogonal axes | perf |
| [130-FOCUSED-BENCHES](130-FOCUSED-BENCHES.md) | Narrow workload shape isolation (mt-mvcc, mt-oltp, perf-update-delete, swarm) | perf |
| [135-MEASURE-WITH-TEARDOWN](135-MEASURE-WITH-TEARDOWN.md) | Population/teardown OUTSIDE timed window | perf |
| [140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md) | Inherits release; never `--release` for perf claims | perf |
| [145-HOT-PATH-COUNTERS](145-HOT-PATH-COUNTERS.md) | `HotPathProfileSnapshot` per project class | perf |
| [150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md) | 19-field card + EV ≥ 2.0 + one-lever scope + proof pack | perf |
| [155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) | `.bench-history/*.latest.json` committed to git | perf |
| [160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) | Every kept win cites a frame ≥0.1% self-time | perf |
| [165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) | Focused + broad gate, same run window | perf |
| [170-ROBUST-REGRESSION-DETECTOR](170-ROBUST-REGRESSION-DETECTOR.md) | Median + MAD; warning/critical severities; structured dated waivers | perf |
| [175-CONCURRENT-MODE-GUARD](175-CONCURRENT-MODE-GUARD.md) | `concurrent_mode_default_guard.txt` in every artifact lane | perf |

## Negative-Evidence (180–195)

| ID | Pattern | Pillar |
|---|---|---|
| [180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) | Three ledgers + mandatory fields | all |
| [185-RETRY-CONDITION-PREDICATE](185-RETRY-CONDITION-PREDICATE.md) | 8 verbatim predicate forms; forbidden phrases | all |
| [190-CASS-MINING](190-CASS-MINING.md) | 60-day failure-term grep across local + css + csd + ts1 + ts2 | all |
| [195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md) | `run_id + trace_id + scenario_id + seed + commit_sha + ...` | all |

## The 10 Winning Optimizations (200–245)

These are the FrankenSQLite PART XIII patterns, lifted verbatim with per-class transferability notes.

| ID | Pattern | Speedup |
|---|---|---|
| [200-HOT-OPCODE-PROMOTION](200-HOT-OPCODE-PROMOTION.md) | `try_execute_hot_opcode` pre-match dispatch | up to +38.6% per opcode |
| [205-ATOMIC-BOOL-EMPTY-GATE](205-ATOMIC-BOOL-EMPTY-GATE.md) | O(N) sweep → O(1) on empty | 2.92µs → 1ns (~2922x) |
| [210-ALGEBRAIC-COUNTER-ELIMINATION](210-ALGEBRAIC-COUNTER-ELIMINATION.md) | `validations_total == commits + aborts` | 3.91 → 1.90 ns/call |
| [215-HASHSET-TO-SORTED-VEC](215-HASHSET-TO-SORTED-VEC.md) | Small-collection HashSet → sorted Vec + binary_search | 1674.8 → 970.8 ns (~1.7x) |
| [220-BOUNDS-ELIDE-AS-CHUNKS](220-BOUNDS-ELIDE-AS-CHUNKS.md) | `as_chunks::<N>()` not `chunks_exact()` | 10.7 → 3.7 ns (~2.9x) |
| [225-DEVIRTUALIZE-MATCH-ARM](225-DEVIRTUALIZE-MATCH-ARM.md) | `&dyn Trait` → match-arm dispatch (profile-driven) | closed 0.36% + 0.29% MT8 |
| [230-ENABLED-LEVEL-TRACING-GATE](230-ENABLED-LEVEL-TRACING-GATE.md) | `if tracing::enabled!()` around non-trivial args | 4-10x on oltp_cost |
| [235-MOVE-NOT-CLONE](235-MOVE-NOT-CLONE.md) | Refactor builders to take values | −21.9% MISS path |
| [240-ONCELOCK-DERIVATION-CACHE](240-ONCELOCK-DERIVATION-CACHE.md) | One-time-derivable state behind `OnceLock<T>` | part of 7.0x MT 8t cluster |
| [245-CACHE-KEY-EVICTION-AUDIT](245-CACHE-KEY-EVICTION-AUDIT.md) | "Which inputs does this cache actually depend on?" gap = bug | 778 → 5458 fs_wps (~7x) |

## Cross-Cutting (250–280)

| ID | Pattern |
|---|---|
| [250-ISOMORPHISM-PROOF](250-ISOMORPHISM-PROOF.md) | The 5-line proof template every behavior-preserving change must include |
| [255-RCH-OFFLOAD-DISCIPLINE](255-RCH-OFFLOAD-DISCIPLINE.md) | >5min wall-time → `rch exec --` |
| [260-AGENT-MAIL-RESERVATIONS](260-AGENT-MAIL-RESERVATIONS.md) | `tool://...` / `resource://...` lease conventions |
| [265-DEEP-HYPOTHESIS-ESCALATION-TRIGGER](265-DEEP-HYPOTHESIS-ESCALATION-TRIGGER.md) | 4 trigger conditions for escalating to a deep-review session |
| [270-PRODUCTIVE-IGNORANCE-INJECTION](270-PRODUCTIVE-IGNORANCE-INJECTION.md) | `⊚` operator — deliberately under-onboard one pane to deliver disagreement signal |
| [275-THEORY-KILL-IMMEDIATE-CLOSE](275-THEORY-KILL-IMMEDIATE-CLOSE.md) | `†` operator — every `NO_EVIDENCE` outcome closes immediately with a retry predicate |
| [280-SCRATCH-WORKTREE-CONVENTION](280-SCRATCH-WORKTREE-CONVENTION.md) | `/data/tmp/<project>-<feature>-<timestamp>/` for rejected-but-preserved code |

## Round-5 step-of-1 inserts into earlier families

These patterns are conceptually-adjacent to existing ones but the step-of-5 slot was taken; they were inserted at step-of-1 with explicit documentation here so reviewers know the placement is intentional.

| ID | Pattern | Inserted between |
|---|---|---|
| [06-5-MODE-ORACLE-DISPATCH](06-5-MODE-ORACLE-DISPATCH.md) | Greenfield composite Oracle: OracleMode enum dispatching Spec/Property/Self/Round-trip/External-tool | 05 ↔ 10 |
| [11-SPEC-TAG-EXTRACTION](11-SPEC-TAG-EXTRACTION.md) | Phase 2 mechanism for extracting `[SPEC-NNN]` from spec sources | 10 ↔ 15 |
| [12-SPEC-CONFLICT-DETECTION](12-SPEC-CONFLICT-DETECTION.md) | Phase 2 BLOCKER pattern for contradictory spec sources | 10 ↔ 15 |
| [13-SINGLE-CRATE-VS-WORKSPACE-DECISION](13-SINGLE-CRATE-VS-WORKSPACE-DECISION.md) | Phase 3 layout decision for greenfield projects | 10 ↔ 15 |
| [31-SCHEMA-VERSION-MIGRATION-DUAL-READER](31-SCHEMA-VERSION-MIGRATION-DUAL-READER.md) | vN → vN+1 schema bumps with dual-reader window | 30 ↔ 35 |
| [56-PROPTEST-REGRESSION-DISCIPLINE](56-PROPTEST-REGRESSION-DISCIPLINE.md) | Checked-in `proptest-regressions/*.txt` as seed-contract artifact | 55 ↔ 60 |

---

## How to read

- **Authoring a new pattern**: pick the next free slot in the relevant family (e.g., `42-…` between 40 and 45). Don't renumber siblings.
- **Step-of-1 inserts** are valid when the step-of-5 slot is taken; document in the round-5-inserts table above so reviewers see the intent.
- **Citing in a bead**: use `pattern:NN-NAME` as the bead title prefix so the bead graph stays grep-able.
- **Adding a new family**: round to the next 300-block (so 300+ is reserved for project-specific extension patterns).
- **Authoring rule**: every pattern MUST cite at least one FrankenSQLite source file path and one verbatim quote. No "best practice" without evidence.

## Cross-references

- The full conceptual decomposition: [../THREE-PILLARS.md](../THREE-PILLARS.md).
- The axiomatic kernel: [../methodology/KERNEL.md](../methodology/KERNEL.md).
- The operator glyph library that drives application: [../methodology/OPERATORS.md](../methodology/OPERATORS.md).
- The 16-phase pipeline: [../PHASES.md](../PHASES.md).
- Per-class transferability tables: [../taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md).
