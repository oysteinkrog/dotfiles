# First-Bug-Hunt Recipe: Greenfield-Rust-Class

Empirically, these 10 bug classes surface in the first day of running the gauntlet on a greenfield (non-port) Rust project — projects without an external reference implementation, where the Oracle is constructed from the project's own spec + property suite + prior-commit baseline + round-trip tests + external tools. The canonical case study is `eidetic_engine_cli`.

**Prerequisites:** `mode == "gauntlet-greenfield"` per `<workspace>/phase0_intake.json`; the 5 oracle modes wired per [`subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md); `spec_version_contract.toml` pinned with every spec source SHA-256'd per [`methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md); `OracleMode` enum dispatched per the 30-line greenfield `scenario()` template; `EngineIdentity` constants (`SUBJECT_IDENTITY_LABEL = "<project>"`, `REFERENCE_IDENTITY_LABEL ∈ {"spec-vN", "property-suite-vN", "prior-commit-<sha>", "round-trip", "miri", "clippy"}`).

Per item: **symptom** → **paste-ready repro** → **MismatchClassification expected** → **severity** → **fix pattern**.

Cross-link: [`methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md), [`case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md), [`taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class`](../taxonomy/PROJECT-CLASSES.md).

---

## 1. Spec-source contradiction not caught

**Symptom.** Two spec sources (e.g., `AGENTS.md § Hard Requirements` and `docs/spec/v1/specification.md § Token Budget`) make contradictory assertions about the same behavior — typically one says "MUST never exceed N" while the other says "SHOULD respect within ±1%". Phase 3 wires verifiers from BOTH sources; the verifiers themselves disagree at runtime; a passing test under one verifier is a failing test under the other; the silent regression looks like "the test is flaky" but is actually a contract conflict.

**Repro:**
```bash
cd "$WORKSPACE"
./scripts/extract-spec-tags.sh "$PORT" > docs/spec/SPEC-TAGS.md
./scripts/check-spec-coherence.sh docs/spec/SPEC-TAGS.md
# Expect: per-tag pairwise consistency check; any conflicting pair is reported.

# Or, after Phase 3 oracle-wiring, run the dispatcher with --all-modes:
cargo test --test spec_oracle_smoke -- --nocapture
# Both verifiers run on the same input; divergence between them surfaces.
```

**Expected MismatchClassification:** `SpecConflict { source_a: <path>, source_b: <path>, tag: [SPEC-NNN] }` — a greenfield-specific extension to the standard `MismatchClassification` enum. Treat as a hard Phase 2 BLOCKER, NOT a TrueDivergence (the engine is correct relative to one source and wrong relative to the other — there's no single right answer until the user canonicalizes).
**Severity:** **critical** — blocks all downstream Phase 3+ work until resolved.
**Fix pattern:** [`cookbook/spec-conflict-detected.md`](../cookbook/spec-conflict-detected.md) — escalate to user; canonicalize one source-of-truth per [`methodology/SPEC-PINNING-FOR-GREENFIELD.md § 4`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md); update `spec_version_contract.toml#/meta.revision`; re-run the Phase 2 scope-decider.

---

## 2. `[SPEC-NNN]` tag without verifier

**Symptom.** The spec source contains an assertion tagged `[SPEC-EE-042]` (e.g., "every `pack` respects the configured token budget within ±1%") but `crates/<port>-harness/src/spec_oracle.rs` has no `verify_spec_ee_042` function. The verification-contract loader silently treats the tag as `Unverified` rather than failing; release certification ships with the tag's promise unbacked by evidence.

**Repro:**
```bash
cd "$PORT"
./scripts/check-spec-tag-orphans.sh
# Lists tags in SPEC-TAGS.md without a matching verifier symbol.

# Or grep manually:
grep -hoP '\[SPEC-[A-Z0-9_-]+\]' docs/spec/SPEC-TAGS.md | sort -u > /tmp/declared_tags.txt
rg -oP 'verify_spec_[a-z0-9_]+' src/harness/spec_oracle.rs | sort -u > /tmp/implemented_verifiers.txt
# diff the two; orphans are tags-without-verifiers.
```

**Expected MismatchClassification:** `UnverifiedSpecTag { tag: [SPEC-EE-042], source: <path> }` — release-blocker under the strict-conformant-release.v1 `MIN_VERIFICATION_PCT=100` constant.
**Severity:** **high** — release certification falsely claims coverage.
**Fix pattern:** [`cookbook/spec-tag-orphan-cleanup.md`](../cookbook/spec-tag-orphan-cleanup.md) — retire-or-implement decision tree; either author the verifier, demote the tag to `docs/CHARTER.md` (non-binding), or refine the assertion to be falsifiable per [`methodology/SPEC-PINNING-FOR-GREENFIELD.md § 5`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md).

---

## 3. Round-trip not actually identity

**Symptom.** `subject::encode(input) → bytes → subject::decode(bytes) → output`; the round-trip oracle asserts `assert_eq!(input, output)` and passes 999 / 1000 cases. The shrunken counterexample reveals that floating-point precision (or string-normalization, or timestamp truncation, or whitespace collapse) silently loses information on a specific input shape. Most commonly: `f64` → JSON → `f64` loses the low bits; or `&str` containing combining-Unicode is NFC-normalized one direction and not the other.

**Repro:**
```bash
cd "$PORT"
cargo +nightly fuzz run fuzz_<feature>_roundtrip -- -max_total_time=60
# Counterexample lands in fuzz/artifacts/fuzz_<feature>_roundtrip/crash-<sha>.

# Replay via the proptest harness:
PROPTEST_CASES=8192 cargo test --test <feature>_roundtrip_proptest -- --nocapture
```

For eidetic: `embedding_v1` encode→decode of an `f32`-vector with subnormal values; `context_pack_v1` encode→decode with a UTF-8 string containing combining marks; `ulid` serialize→parse with the high-bit-set timestamp edge.

**Expected MismatchClassification:** `TrueDivergence { description: "round-trip identity violation", first_divergence_jsonptr: <jsonptr-to-differing-field> }`.
**Severity:** **critical** — silent data loss; any downstream consumer reading the decoded form sees corrupt state.
**Fix pattern:** [pattern:40-METAMORPHIC-TRANSFORMS § Literal](../patterns/40-METAMORPHIC-TRANSFORMS.md) — the encoder must preserve enough bits; the decoder must reconstruct exactly. Either fix the codec OR weaken the round-trip oracle's `EquivalenceExpectation` to `NormalizedEquivalence` with the normalization documented in the spec contract (and add a new `[SPEC-NNN]` tag for the normalization rule).

---

## 4. Insta-snapshot drift on cosmetic CLI change

**Symptom.** A developer changes a `clap` help message (e.g., adds a sentence), reformats a JSON output field-order, or upgrades a dependency that changes its `Display` impl. Insta-snapshot tests in `tests/snapshots/` go red. The first-bug-hunt agent reads the diff and files a `TrueDivergence`. But the diff is **cosmetic** — the CLI behavior is identical; only the output formatting moved.

**Repro:**
```bash
cd "$PORT"
cargo insta test --review
# Inspect every diff: is it a behavior change or a cosmetic change?
# If the bytes differ but the semantics don't, the snapshot WAS the test's
# specification — and the test is over-specifying.
```

**Expected MismatchClassification:** `FalsePositive { reason: "cosmetic format change; behavior identical", remediation: "bless snapshot OR loosen normalizer" }` IF the change is genuinely cosmetic. Otherwise `TrueDivergence`.
**Severity:** **medium** — wastes triage time; trains agents to bless-without-thinking; eventually a real divergence gets blessed away.
**Fix pattern:** [pattern:55-INSTA-GOLDEN-SNAPSHOTS § Tier 2 Normalization](../patterns/55-INSTA-GOLDEN-SNAPSHOTS.md) — insert a canonical normalizer (sort JSON keys; collapse whitespace; strip help-text version suffix) BEFORE `assert_snapshot!`. Snapshot the normalized form, not the raw form. The bless-policy in `spec_version_contract.toml#/golden_snapshots.bless_policy = "manual"` means every bless gets a bead with rationale per [`methodology/SPEC-PINNING-FOR-GREENFIELD.md § 6`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md).

---

## 5. Property test passes locally but fails in CI with checked-in regression

**Symptom.** Developer runs `cargo test --test <feature>_proptest` locally; passes. Pushes. CI fails on `proptest-regressions/<feature>_proptest.txt` line 17. The committed regression seed reproduces the bug, but the developer never saw it because their proptest invocation generated different inputs.

This is a SEED-CONTRACT VIOLATION: the proptest config either (a) lacks `FileFailurePersistence::WithSource("regressions")`; (b) the developer ran with `PROPTEST_CASES=10` locally and CI runs `PROPTEST_CASES=256`; (c) the regressions file is in `.gitignore`; or (d) the test was rewritten and the old regression seed no longer matches the new strategy.

**Repro:**
```bash
cd "$PORT"
# Confirm regressions file exists and is committed:
git ls-files proptest-regressions/
# Confirm the proptest_config() uses WithSource:
rg "FileFailurePersistence::WithSource" tests/

# Replay the exact CI failure:
PROPTEST_CASES=1024 PROPTEST_MAX_SHRINK_ITERS=8192 \
  cargo test --test <feature>_proptest -- --nocapture
```

**Expected MismatchClassification:** `SeedContractViolation { regression_file: <path>, line: 17, replay_status: "missed" }` — a greenfield-specific extension. NOT a TrueDivergence in the engine itself; it's a HARNESS bug.
**Severity:** **high** — every future regression silently slips through local dev.
**Fix pattern:** [`assets/property-test-templates/greenfield_proptest.rs`](../../assets/property-test-templates/greenfield_proptest.rs) §"Seed contract" — bake `FileFailurePersistence::WithSource("regressions")` into the shared `proptest_config()`; commit `proptest-regressions/` (NOT gitignore); pin `PROPTEST_CASES` in `Cargo.toml`'s `[env]` block AND in CI workflow; assert in CI: "regression file SHA-256 matched the run-id-stamped expected value".

---

## 6. Miri finds UB in custom runtime adapter

**Symptom.** The project uses a custom async runtime (e.g., `asupersync` rather than `tokio`); `cargo +nightly miri test --lib` reports undefined behavior in the runtime's task-queue or its custom `Waker` impl. Common patterns: aliasing `&mut` through raw pointers; missing `Acquire`/`Release` ordering on a futures wake counter; `Send`/`Sync` impls on a type containing `*mut`; uninitialized memory in a slab allocator.

This is empirically a HIGH-FREQUENCY greenfield bug because custom runtimes are a common architectural choice in greenfield projects (avoiding the heavy tokio ecosystem), and runtime authors often lean on `unsafe` for perf without the discipline of a multi-year-mature codebase like tokio.

**Repro:**
```bash
cd "$PORT"
rustup toolchain install nightly --component miri
cargo +nightly miri setup
MIRIFLAGS="-Zmiri-strict-provenance -Zmiri-symbolic-alignment-check" \
  cargo +nightly miri test --lib -- runtime::
# Miri reports the exact line + the violated rule; capture stderr fully.
```

For eidetic: `asupersync::Executor::spawn` + the cancellation-token interaction; the slab-allocated future storage; the cross-pane channel reader/writer pair.

**Expected MismatchClassification:** `TrueDivergence { description: "miri UB detected", external_tool: "miri", evidence: <stderr-capture> }` — per [`methodology/GREENFIELD-ADAPTATION.md § 9`](../methodology/GREENFIELD-ADAPTATION.md), Miri findings are TrueDivergence-equivalent.
**Severity:** **critical** — UB is undefined; "it works on my machine" is not evidence of correctness.
**Fix pattern:** [`tooling/SANITIZER-TOOLCHAIN.md`](../tooling/SANITIZER-TOOLCHAIN.md) Miri section + [`patterns/65-CRASH-BOUNDARIES.md`](../patterns/65-CRASH-BOUNDARIES.md). Cross-link to the `rust-undefined-behavior-exorcist` skill if the project has many findings. Pin the nightly toolchain in `spec_version_contract.toml#/external_tools.miri.toolchain` so Miri's output is reproducible.

---

## 7. cargo-deny advisory hit on a dev-dep

**Symptom.** A release-blocking `cargo deny check advisories` hit lands the day of a release. Investigation reveals the affected crate is a transitive of a `[dev-dependencies]` entry — it never ships with the binary, and the advisory is irrelevant to production. But cargo-deny is configured to fail on ANY advisory and the release is blocked for hours while someone figures out it was a false alarm.

**Repro:**
```bash
cd "$PORT"
cargo deny check advisories
# If hit, inspect:
cargo tree --invert <affected-crate>
# Is the chain a [dev-dependencies] / build-dependencies path? Then it doesn't
# ship; the advisory is a release-non-blocker for a *binary* release but
# possibly still relevant for a *crate publish*.
```

**Expected MismatchClassification:** `FalsePositive { reason: "advisory on dev-dep transitive; not shipped", remediation: "add deny.toml ignore + bead with retry condition" }` IF the chain is genuinely dev-only. Otherwise `TrueDivergence` and ship-blocker.
**Severity:** **medium-high** — false alarms train teams to ignore real advisories.
**Fix pattern:** Configure `deny.toml`'s `[advisories.ignore]` with a bead-tagged comment per advisory; the bead names the retry condition predicate (one of the 8 forms per [`assets/negative-ledger-seed.md § Retry-Condition Predicate Vocabulary`](../../assets/negative-ledger-seed.md)) — typically form 8: `"Blocked until <upstream-fix-published>; track as bd-<id>"`. Re-evaluate on every `cargo deny update`.

---

## 8. Hot-path counter incrementing concurrently without atomics

**Symptom.** `hot_path_counters.sqlite_busy_retries` increments on every retry; under MT8 concurrent load, the final reported count is consistently LOWER than the sum of per-thread increments. The counter is declared `static mut COUNTER: u64 = 0;` and `unsafe { COUNTER += 1; }` — a textbook data race; the lost-update visible in the bench output but the test passes because no oracle checks the counter's actual value.

This is a frequent greenfield miss because the discipline of using `AtomicU64` for every shared counter doesn't get formalized until the gauntlet's pillar (a) HotPathProfileSnapshot work surfaces "wait, the numbers don't add up".

**Repro:**
```bash
cd "$PORT"
# Run the MT8 bench with deterministic load:
cargo bench --bench mt8_<feature>_bench -- --measurement-time 10
# Inspect the emitted HotPathProfileSnapshot:
jq '.hot_path_counters' .bench-history/mt8_<feature>_bench.latest.json
# Sum the per-thread emissions independently and compare to the reported global.

# Direct race detection:
RUSTFLAGS="-Z sanitizer=thread" cargo +nightly test --target x86_64-unknown-linux-gnu
# ThreadSanitizer flags the unsynchronized access.
```

**Expected MismatchClassification:** `TrueDivergence { description: "lost-update on shared counter", concurrency_witness: "MT8" }`.
**Severity:** **high** — perf attribution is wrong; the `negative-ledger` entries citing the counter are based on bad data.
**Fix pattern:** [pattern:145-HOT-PATH-COUNTERS § AtomicU64 mandate](../patterns/145-HOT-PATH-COUNTERS.md); convert every shared counter to `AtomicU64` with `Ordering::Relaxed` for monotonic counters and `Acquire`/`Release` where ordering matters; add an MT8 invariant: `sum_per_thread(counter) == global(counter)` as an e-process.

---

## 9. Storage backend `BUSY` retries hidden

**Symptom.** The project uses SQLite (or any concurrent-access storage); under MT8 load, the writer hits `SQLITE_BUSY` and silently retries N times before succeeding. The bench's wall-time is dominated by retry-wait, but no counter exposes this; the agent sees "slow bench, why?" and spends a day profiling CPU when the answer was visible in the storage backend's busy-handler.

The retry is hidden because:
- The storage adapter swallows `SQLITE_BUSY` errors and retries internally.
- No counter surfaces the retry count.
- The bench's `concurrent_mode_default_guard.txt` analog doesn't declare which lock mode is in effect.

**Repro:**
```bash
cd "$PORT"
# Confirm the bench's HotPathProfileSnapshot exposes a sqlite_busy_retries field:
jq '.hot_path_counters | keys' .bench-history/mt8_<feature>_bench.latest.json
# If the field is missing, the bug is hidden.

# Force the retry to surface via deterministic contention:
SQLITE_BUSY_HANDLER_DELAY_MS=100 cargo bench --bench mt8_<feature>_bench
# A long tail in the latency distribution is the busy-retry; compare to baseline.
```

**Expected MismatchClassification:** `PerfCliff { hidden_cost: "sqlite_busy_retries", attribution_pct_unaccounted: <pct> }` — a greenfield-specific perf classification. NOT a TrueDivergence (the engine is correct; the perf surface is just opaque).
**Severity:** **high** — perf gauntlet rounds make wrong decisions on hidden cost.
**Fix pattern:** [pattern:145-HOT-PATH-COUNTERS](../patterns/145-HOT-PATH-COUNTERS.md) — surface `sqlite_busy_retries`, `sqlite_busy_wait_total_ns`, `single_writer_invariant_guard` as named counters per [`taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class`](../taxonomy/PROJECT-CLASSES.md); drop `single_writer_invariant_guard.txt` into every artifact lane stating which (writer | reader) connection mode was in effect.

---

## 10. CLI subcommand surface drifts between `clap` definition and spec

**Symptom.** Developer adds a `clap` subcommand `ee analyze` in `src/cli.rs`; doesn't update `docs/spec/v1/specification.md` to declare it. FeatureUniverse (built per [`pattern:105-FEATURE-UNIVERSE`](../patterns/105-FEATURE-UNIVERSE.md) from the union of clap surface + spec promises) flags `analyze` as `present-in-cli-absent-from-spec`. Or, conversely: spec promises `ee migrate` but no clap subcommand exists — `present-in-spec-absent-from-cli`.

Either direction is a Surface-pillar bug; both directions silently accumulate until Phase 7 surface inventory.

**Repro:**
```bash
cd "$PORT"
# Generate the CLI surface enumeration:
./target/release/<binary> --help-all-json > /tmp/cli_surface.json
# (Or use clap's `clap_complete` to dump every subcommand + flag.)

# Generate the spec surface enumeration:
./scripts/extract-spec-tags.sh "$PORT" --filter-by-kind=subcommand > /tmp/spec_surface.txt

# Compare:
./scripts/compare-cli-vs-spec.sh /tmp/cli_surface.json /tmp/spec_surface.txt
# Reports: cli_only=[analyze]; spec_only=[migrate]; both=[remember, recall, ...].
```

**Expected MismatchClassification:** `SurfaceDrift { direction: "cli-only" | "spec-only", item: <subcommand-name> }`. NOT TrueDivergence (the engine works; the contract is incomplete).
**Severity:** **medium-high** — silent surface drift compounds; by month 3 the spec is fiction.
**Fix pattern:** [pattern:105-FEATURE-UNIVERSE](../patterns/105-FEATURE-UNIVERSE.md) + [pattern:115-CLOSURE-WAVE](../patterns/115-CLOSURE-WAVE.md) — for every `cli-only` item: either add a `[SPEC-NNN]` tag declaring it OR mark the clap subcommand as `#[command(hide = true)]` and add a `negative-ledger` entry. For every `spec-only` item: either implement OR demote the spec line to `docs/CHARTER.md`. Wire `compare-cli-vs-spec.sh` as a CI gate so future drift is caught at PR-time.

---

## Empirical first-day stats (calibration)

Running this recipe on a *new* Greenfield-Rust-class project typically surfaces:

- **2–3 of the above 10 in the first hour** (high-frequency authoring-discipline misses: spec-tag orphans, surface drift between clap and spec, missing seed contract on proptest).
- **5–7 in the first day** (after the 5-mode oracle is wired and a first MT8 bench runs).
- **All 10 within first 3 rounds** of the gauntlet.

Items 1 (spec-source contradiction), 6 (Miri UB in custom runtime), and 8 (hot-path counter race) are the deepest — they require multi-source spec analysis, nightly Miri infrastructure, and concurrent-load benches respectively. Greenfield projects with strong informal floors (like eidetic per [`case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md)) tend to surface fewer items in items 5/8/10 because the project already has insta + property-test + counter discipline, but ALL of them still surface item 1 if multiple spec sources exist.

---

## Cross-references

- [PROJECT-CLASSES.md § Greenfield-Rust-class](../taxonomy/PROJECT-CLASSES.md)
- [methodology/GREENFIELD-ADAPTATION.md](../methodology/GREENFIELD-ADAPTATION.md)
- [methodology/SPEC-PINNING-FOR-GREENFIELD.md](../methodology/SPEC-PINNING-FOR-GREENFIELD.md)
- [case-studies/eidetic_engine_cli.md](../case-studies/eidetic_engine_cli.md)
- [cookbook/spec-conflict-detected.md](../cookbook/spec-conflict-detected.md)
- [cookbook/spec-tag-orphan-cleanup.md](../cookbook/spec-tag-orphan-cleanup.md)
- [cookbook/single-crate-vs-workspace-decision.md](../cookbook/single-crate-vs-workspace-decision.md)
- [subagents/greenfield-oracle-wirer.md](../../subagents/greenfield-oracle-wirer.md)
- [assets/per-class-checklists/greenfield.md](../../assets/per-class-checklists/greenfield.md)
- [assets/integration-test-templates/greenfield_oracle_e2e.rs](../../assets/integration-test-templates/greenfield_oracle_e2e.rs)
- [assets/property-test-templates/greenfield_proptest.rs](../../assets/property-test-templates/greenfield_proptest.rs)
- [assets/fuzz-target-templates/greenfield_fuzz.rs](../../assets/fuzz-target-templates/greenfield_fuzz.rs)
- [patterns/40-METAMORPHIC-TRANSFORMS.md](../patterns/40-METAMORPHIC-TRANSFORMS.md)
- [patterns/55-INSTA-GOLDEN-SNAPSHOTS.md](../patterns/55-INSTA-GOLDEN-SNAPSHOTS.md)
- [patterns/105-FEATURE-UNIVERSE.md](../patterns/105-FEATURE-UNIVERSE.md)
- [patterns/115-CLOSURE-WAVE.md](../patterns/115-CLOSURE-WAVE.md)
- [patterns/145-HOT-PATH-COUNTERS.md](../patterns/145-HOT-PATH-COUNTERS.md)
- [tooling/SANITIZER-TOOLCHAIN.md](../tooling/SANITIZER-TOOLCHAIN.md)
