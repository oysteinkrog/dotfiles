# Greenfield Adaptation

How the gauntlet applies to a novel, non-port Rust project — one that doesn't have an external reference implementation to compare against. The Subject/Oracle/Comparator kernel (K-1) still holds; the Oracle just gets *constructed* rather than *adopted from upstream*.

Trigger: any time `scripts/detect-project-class.sh` returns `UNKNOWN` (no SQLite/Redis/numpy/torch/HTTP shape) — OR the user explicitly invokes `gauntlet.sh --mode gauntlet-greenfield`.

Cross-link: [`methodology/MODE-ROUTER.md § gauntlet-greenfield`](MODE-ROUTER.md), [`taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class`](../taxonomy/PROJECT-CLASSES.md), [`case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md).

---

## 1. The Greenfield-Rust-class

A new sixth project class on top of the original 5 (SQL / RESP / Numerical-Python / ML-System / HTTP-Protocol). Defining traits:

- No upstream reference to diff against.
- The Subject is the current code at HEAD.
- The Oracle is one or more of:
  1. **Specification-as-Oracle** — a formal or semi-formal spec (e.g., `docs/spec/v1/<feature>.md`) the Subject must implement faithfully.
  2. **Property-Oracle** — invariants stated as `proptest` / `quickcheck` properties; the Oracle is "every property holds".
  3. **Self-Oracle (prior-commit)** — the Subject's own behavior at a frozen baseline commit; regression = any departure not explicitly authored.
  4. **Round-trip-Oracle** — encode→decode (or sign→verify, or pack→unpack) round-trips; the Oracle is identity.
  5. **External-tool-Oracle** — a trusted external check (e.g., `cargo +nightly miri test` is an Oracle for UB; `cargo clippy -D warnings` is an Oracle for code-quality invariants).
- The Comparator is one of:
  1. **Spec-conformance check** — Subject behavior matches spec assertion.
  2. **Property assertion** — `proptest!` runs to completion without shrinking.
  3. **Insta snapshot comparison** — the current output equals the last-blessed.
  4. **Round-trip equality** — bytewise equality after the round-trip.
  5. **External tool exit code** — Miri/Clippy/Cargo-deny exits 0.

The five oracle modes can be MIXED in one project — most projects use 3-4 of them.

## 2. Per-pillar adaptation

### Performance (pillar (a))

UNCHANGED. Greenfield perf benchmarks compare AGAINST PRIOR COMMITS (the self-oracle). The keep-gate rules ([`KEEP-GATE-RULES.md`](KEEP-GATE-RULES.md)), MT8 attribution ([`pattern:160-MT8-ATTRIBUTION`](../patterns/160-MT8-ATTRIBUTION.md)), `.bench-history` ratchet ([`pattern:155-BENCH-HISTORY-RATCHET`](../patterns/155-BENCH-HISTORY-RATCHET.md)), profile-first card ([`pattern:150-PROFILE-FIRST-CARD`](../patterns/150-PROFILE-FIRST-CARD.md)), proof-pack rubric ([`PROOF-PACK-RUBRIC.md`](PROOF-PACK-RUBRIC.md)) all apply unchanged — they were designed against the project's own historical baseline, not against an external reference.

The only adaptation: there's no "reference engine" to symmetrically wrap in retry shells. The bench harness runs only the subject. The "both gates must move in the same run window" rule still applies (focused bench + broad bench, same git state, same `target/`, same machine, same minute), with the prior commit acting as the implicit second engine.

### Conformance (pillar (b))

ADAPTED. The Differential V2 envelope ([`pattern:30-DIFFERENTIAL-V2-ENVELOPE`](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md)) still applies, but `EngineVersions.reference_identity` becomes one of: `"spec-vN"`, `"property-suite-vN"`, `"prior-commit-<sha>"`, `"round-trip"`, `"miri"`. The EngineIdentity ([`pattern:15-ENGINE-IDENTITY`](../patterns/15-ENGINE-IDENTITY.md)) discriminator still asserts distinct (Subject ≠ Oracle).

The 30-line `scenario()` template ([`pattern:05-SUBJECT-ORACLE-COMPARATOR`](../patterns/05-SUBJECT-ORACLE-COMPARATOR.md)) becomes:

```rust
fn scenario(setup: impl FnOnce() -> State, action: impl FnOnce(State) -> Result<Output>,
            spec_check: impl FnOnce(&Output) -> Result<()>) {
    let state = setup();
    let out = action(state);
    match (out, spec_check(...)) {
        (Ok(o), Ok(())) => assert_spec_holds(&o),
        (Err(e), Err(spec_e)) => assert_error_class_matches(&e, &spec_e),
        _ => panic!("subject/spec divergence"),
    }
}
```

Both-error = agreement and one-error-one-OK = hard failure ([K-8](KERNEL.md)) still apply.

Metamorphic transforms ([`pattern:40-METAMORPHIC-TRANSFORMS`](../patterns/40-METAMORPHIC-TRANSFORMS.md)) are *especially* powerful in greenfield: with no external reference, metamorphic relations (e.g., `f(f^{-1}(x)) == x`, `f(a) + f(b) == f(a + b)` for linear ops) are how you reach high coverage from a single oracle. The 4 TransformFamilies remain valid; the per-family `soundness_proof_sketch` is mandatory.

Fault VFS + crash boundaries ([`pattern:60-FAULT-VFS`](../patterns/60-FAULT-VFS.md), [`pattern:65-CRASH-BOUNDARIES`](../patterns/65-CRASH-BOUNDARIES.md)) adapt per project's actual fault surface — see eidetic case study for the durability boundaries of a SQLite-backed local-first agent-memory CLI.

E-processes ([`pattern:70-E-PROCESSES`](../patterns/70-E-PROCESSES.md)) apply to project-defining invariants verbatim. For eidetic the invariants are things like "every `remember` produces a content-addressable identifier with collision-rate < 1e-15"; "every `recall` returns the same context-pack for the same query+state hash"; "every `pack` respects the configured token budget within ±1%".

### Surface parity (pillar (c))

ADAPTED. There's no upstream `__all__` to enumerate. Instead the FeatureUniverse ([`pattern:105-FEATURE-UNIVERSE`](../patterns/105-FEATURE-UNIVERSE.md)) is built from:

1. **The project's CLI surface** — every subcommand, every flag, every output format. Use `clap`'s help output as the source of truth; `pub` items in `src/cli/` define the surface.
2. **The project's library surface** — every `pub` item in `src/lib.rs` (if the project has a library API).
3. **The project's spec** — every promise in `docs/spec/v1/`, `README.md § Hard Requirements`, `AGENTS.md § Hard Requirements`.
4. **The project's user-facing behaviors** — every documented invariant ("ee never loses data", "ee respects the token budget", "ee is hermetic").

Each becomes a `Feature { id: F-{CAT}-{SEQ}, ... }` row with weight summing to 1.0 per category. The InvariantCatalog ([`pattern:110-INVARIANT-CATALOG`](../patterns/110-INVARIANT-CATALOG.md)) is even more critical: with no external reference, the catalog IS the contract. The release ships the catalog → the release ships the proof-of-work.

The Closure-Wave pattern ([`pattern:115-CLOSURE-WAVE`](../patterns/115-CLOSURE-WAVE.md)) is the gold-standard discipline for greenfield: enumerate every expected behavior FIRST (from spec + CLI + AGENTS.md), THEN test each. Stage-by-stage coverage deltas; never accumulate blind spots.

## 3. Mode and tier router additions

### `gauntlet-greenfield` mode (new entry in [`MODE-ROUTER.md`](MODE-ROUTER.md))

| Mode | Use when | Phases run |
|---|---|---|
| `gauntlet-greenfield` | Novel non-port Rust project; spec or property suite is the Oracle | 0-16 (same as gauntlet-full, but with Oracle construction in Phase 3) |

Phase 2 (REFERENCE PINNING) becomes SPEC PINNING — the `<reference>_version_contract.toml` is replaced by `spec_version_contract.toml` pinning the spec version + the property-suite version + the round-trip-test version + the external-tool versions (Miri, Clippy lints).

### Tier

Greenfield projects are typically T2-T3 (smaller surface than mature ports). The eidetic_engine_cli case study runs at T3 (multi-crate workspace, ~50k LOC, requires rch for full bench matrix).

## 4. New project-class row for `taxonomy/PROJECT-CLASSES.md`

Append:

```markdown
## Greenfield-Rust-class
**Members:** novel Rust projects with no external reference (e.g., eidetic_engine_cli).

**Oracle wiring:** one or more of {Spec-as-Oracle, Property-Oracle, Self-Oracle, Round-trip-Oracle, External-tool-Oracle}.

**NormalizedValue:** project-specific; defined alongside the spec at Phase 2.

**Retry predicate:** project-specific; typically wraps storage-backend transient errors (e.g., SQLite `SQLITE_BUSY`) symmetrically across both subject and prior-commit baseline.

**Headline matrix axes:** CLI subcommand × scale (small/medium/large) × concurrency (1/N writers).

**Keep-gate score:** per-CLI-subcommand weighted; weights derived from usage telemetry if available, else equal-weight over the canonical subcommand set.

**Hot-path counters:** project-specific; for eidetic: `remember_latency_ns`, `recall_latency_ns`, `pack_assembly_time_ns`, `embed_dedup_ratio`, `sqlite_busy_retries`, `index_rebuild_progress_pct`, `arena_alloc_bytes`.

**Negative-ledger failure terms:** project-specific; for eidetic: `embed-cache-stale, ulid-tiebreak-loss, ppr-divergent, pack-overspill, why-stale-evidence, asupersync-cancel-leak`.

**Crash boundaries:** project-specific; for eidetic (storage class): 5 SQLite-backed boundaries (`BeforeBeginImmediate, BeforeCommit, BetweenCommitAndFsync, BeforeWalCheckpoint, AfterCheckpoint`) + 2 long-running-procedure boundaries (`MidIndexRebuild, MidContextStreamSpill`).

**Bit-exact vs ULP boundary:** typically bit-exact (greenfield rarely needs ULP tolerance unless it's also Numerical-class adjacent).

**Seed contract:** `derive_entry_seed(corpus_entry_id)`; never `rand::random()`.

**Behavior-preserving verifier:** insta-snapshot equality on every emitted format; `selections=` byte-identical analog.

**Concurrency-honesty rule:** project-specific; for eidetic: "every WriteApi call uses BEGIN IMMEDIATE on the writer connection; reader connections may not call BEGIN IMMEDIATE; concurrent_mode_default_guard.txt analog is `single_writer_invariant_guard.txt`".

**Certification-bundle shape:** same as other classes per [`CERTIFICATION.md`](CERTIFICATION.md); the strict-conformant-release.v1 constants apply.
```

## 5. Spec-as-Oracle authoring (Phase 3 adaptation)

When the Oracle is the project's own spec, Phase 3 produces:

1. **`docs/spec/v1/<feature>.md`** — every assertion in the spec gets a tagged identifier `[SPEC-<feature>-NNN]`.
2. **`crates/<port>-harness/src/spec_oracle.rs`** — one verifier per `[SPEC-NNN]` tag; each verifier asserts the spec holds given a subject's output.
3. **`tests/spec_<feature>_oracle_e2e.rs`** — drives subject + spec-verifier per the 30-line `scenario()` template.
4. **`crates/<port>-harness/src/oracle_preflight_doctor.rs`** — for spec-Oracle, the preflight verifies: spec file SHA-256 matches contract; every `[SPEC-NNN]` tag has a corresponding verifier; verifier-set is non-empty.

The spec_oracle is a "contract test" generator: each assertion in the spec → one verifier → one E2E test. Updates to the spec propagate via the schema-version-bumper subagent ([`subagents/schema-version-bumper.md`](../../subagents/schema-version-bumper.md)).

## 6. Property-Oracle authoring (Phase 6 adaptation)

For property-suite Oracles, Phase 6 produces:

1. **`tests/properties/<area>_proptest.rs`** — one file per behavior class; each contains 5-20 `proptest!` properties.
2. **Checked-in `proptest-regressions/<test>.txt`** — every shrunk counterexample committed to git.
3. **`crates/<port>-harness/src/property_oracle.rs`** — bridges property results into the MismatchSignature / FailureBundle pipeline (per [`pattern:45-MISMATCH-MINIMIZER`](../patterns/45-MISMATCH-MINIMIZER.md), [`pattern:90-FAILURE-BUNDLE`](../patterns/90-FAILURE-BUNDLE.md)).

Use [`assets/property-test-templates/sql_proptest.rs`](../../assets/property-test-templates/sql_proptest.rs) as the structural template; replace the SQL-specific properties with project-specific ones.

## 7. Self-Oracle authoring (Phase 4 adaptation)

For self-oracle (prior-commit baseline), Phase 4 produces:

1. **`tests/golden/<feature>_v<N>.golden`** — captured-at-blessed-commit canonical outputs.
2. **`crates/<port>-harness/src/self_oracle.rs`** — compares current output against `<feature>_v<N>.golden`; passes if bytewise equal; fails with `TrueDivergence` if not.
3. **`scripts/bless-golden.sh`** — operator-run when an intentional behavior change lands; updates the golden + bumps the version + writes a `golden_bump_<N>.md` rationale.

Insta is the canonical implementation; per [`pattern:55-INSTA-GOLDEN-SNAPSHOTS`](../patterns/55-INSTA-GOLDEN-SNAPSHOTS.md).

## 8. Round-trip-Oracle authoring

For round-trip oracles (encode→decode, pack→unpack, store→retrieve), Phase 6 produces:

```rust
fn roundtrip_scenario(input: impl Arbitrary, label: &str) {
    let encoded = subject::encode(&input);
    let decoded = subject::decode(&encoded);
    assert_eq!(input, decoded, "{label}: round-trip identity violation");
}
```

This is the cheapest form of Oracle and should be exhaustively differential-fuzzed (per [`pattern:40-METAMORPHIC-TRANSFORMS § Literal`](../patterns/40-METAMORPHIC-TRANSFORMS.md)).

## 9. External-tool-Oracle authoring

Wire each external tool as a CI gate AND as a per-round soak check:

- **Miri** — `cargo +nightly miri test` as a Phase 15 soak runner per [`subagents/soak-runner-miri.md`](../../subagents/soak-runner-miri.md). Any UB report is a `TrueDivergence`-equivalent.
- **Clippy with `-D warnings`** — Phase 14 static gate. Any warning is a `TrueDivergence`-equivalent.
- **cargo-deny** — Phase 0 toolchain check + per-round if dependencies changed. Any advisory hit is a release blocker.
- **cargo-geiger** — Phase 1 RECON output (unsafe-surface metric); informs which areas warrant extra fuzz coverage.

## 10. What the gauntlet GIVES UP in greenfield mode

Honest accounting of what's WEAKER without an external reference:

- **No oracle differential** for SUBJECT vs OTHER-PROGRAM. The Oracle is internal (spec/property/self/round-trip/external-tool). This is fine for novelty but means the parity claim is "internal-consistency" not "matches-an-industry-standard".
- **No `cass`-mined sibling-adoption matrix** unless siblings exist in the user's own ecosystem.
- **No "did we re-discover SQLite's PRAGMA semantics correctly" benchmark** — instead the question is "did we honor every documented promise in our own spec".
- **No `__all__`-style 100%-reachable structural gate** — replaced by "every `clap` subcommand and every `pub fn` is in FeatureUniverse".

What the gauntlet GAINS in greenfield:

- The Oracle is *fully owned* by the project; no upstream version drift.
- Metamorphic relations + properties + round-trip + spec all compose; the combined Oracle is often stronger than any single external reference.
- The negative-ledger discipline applies unchanged (failed greenfield experiments are still failed experiments worth banking).
- The certification bundle still proves "this release was tested under the strict-conformant-release.v1 constants".

## 11. Worked recipe for greenfield bootstrap

```bash
# Phase 0
SKILL_DIR="/path/to/running-the-gauntlet-on-your-rust-port"
"$SKILL_DIR/scripts/install-toolchain.sh" --workspace <workspace>
"$SKILL_DIR/scripts/init-workspace.sh" <target> <workspace>
"$SKILL_DIR/scripts/detect-project-class.sh" <target> --workspace <workspace>
# → stdout includes "Detected: UNKNOWN"; JSON writes <workspace>/phase0_project_class.json.detected_class.
# The orchestrator falls through to the greenfield prompt when detected_class == UNKNOWN.

# Confirm greenfield mode with the user (intake-prompt asks).
# Set mode = gauntlet-greenfield in <workspace>/phase0_intake.json.

# Phase 2 — author the four contract files but use the greenfield templates:
#   spec_version_contract.toml (instead of <reference>_version_contract.toml)
#   supported_surface_matrix.toml (CLI subcommands + pub fns + spec assertions)
#   canonical_parity_contract.md (the project's own definition of "what does done mean")
#   parity_score_contract.toml (per-CLI-subcommand category weights)

# Phase 3 — wire ALL FIVE oracle modes:
./scripts/spawn-greenfield-oracles.sh <target> <workspace>
# Produces: spec_oracle.rs, property_oracle.rs, self_oracle.rs, roundtrip_oracle.rs,
#   external_tool_oracle.rs, oracle_preflight_doctor.rs (greenfield variant).

# Phases 4-16 proceed normally per the standard 16-phase loop.
```

## 12. Cross-references

- [`methodology/MODE-ROUTER.md`](MODE-ROUTER.md) — `gauntlet-greenfield` mode addition.
- [`taxonomy/PROJECT-CLASSES.md`](../taxonomy/PROJECT-CLASSES.md) — Greenfield-Rust-class row addition.
- [`case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md) — concrete worked example.
- [`pattern:05-SUBJECT-ORACLE-COMPARATOR`](../patterns/05-SUBJECT-ORACLE-COMPARATOR.md) — kernel pattern (unchanged).
- [`pattern:30-DIFFERENTIAL-V2-ENVELOPE`](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) — envelope adaptation.
- [`pattern:55-INSTA-GOLDEN-SNAPSHOTS`](../patterns/55-INSTA-GOLDEN-SNAPSHOTS.md) — Self-Oracle implementation.
- [`pattern:40-METAMORPHIC-TRANSFORMS`](../patterns/40-METAMORPHIC-TRANSFORMS.md) — Round-trip + Property oracles.
- [`pattern:115-CLOSURE-WAVE`](../patterns/115-CLOSURE-WAVE.md) — surface enumeration discipline.
- [`tooling/SANITIZER-TOOLCHAIN.md`](../tooling/SANITIZER-TOOLCHAIN.md) — External-tool-Oracle wiring.
