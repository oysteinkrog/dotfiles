# TOOLCHAIN-RUNBOOK.md — Tool-by-Tool Runbook

The verification harness (Phase 7 + Phase 9) chains seven tools. Each has known-issue traps. Run them in the order below; tee output to `<audit-dir>/audit/phase7/verification-log.md` so every finding is reviewable.

The exit-status contract for `verify.sh` is: any tool's non-zero exit → harness fails, even if subsequent tools would have passed. Don't suppress.

---

## Installation

The skill's bootstrap script (`scripts/install-toolchain.sh`) proposes these one-liners; the user must approve before any install runs.

```bash
# Nightly toolchain (required by miri, careful, geiger, unstable rustdoc JSON)
rustup toolchain install nightly

# Miri component on nightly
rustup +nightly component add miri rust-src

# cargo-careful: runtime UB detection
cargo +nightly install cargo-careful

# ast-grep: structural code search
cargo install ast-grep --locked

# cargo-geiger: unsafe-count metric
cargo +nightly install --locked cargo-geiger

# cargo-expand: macro expansion view
cargo install cargo-expand --locked

# cargo-fuzz: libfuzzer integration
cargo install cargo-fuzz --locked

# cargo-mutants: mutation testing (verifies tests pin behavior, not vibes)
cargo install --locked cargo-mutants

# cargo-flamegraph: profile-driven perf measurement
cargo install flamegraph --locked

# hyperfine: end-to-end command timing
cargo install --locked hyperfine
# or: brew install hyperfine

# loom: dev-dependency, not a binary; added per-crate to Cargo.toml
# [target.'cfg(loom)'.dev-dependencies] loom = "0.7"
```

Run `cargo +nightly miri setup` once per machine to pre-build the miri sysroot. This caches under `~/.cache/miri/`.

---

## miri

### What it catches

- Out-of-bounds memory access
- Use-after-free
- Dangling references
- Misaligned pointers
- Uninitialized memory reads
- Data races (under `-Zmiri-track-pointer-tag`)
- Provenance violations (under `-Zmiri-strict-provenance`)
- Stacked Borrows violations (default)
- Tree Borrows violations (under `-Zmiri-tree-borrows`)

### Standard invocation

```bash
cargo +nightly miri test --workspace --all-features
```

### Strict mode (run after standard)

```bash
MIRIFLAGS="-Zmiri-strict-provenance -Zmiri-symbolic-alignment-check" \
  cargo +nightly miri test --workspace --all-features
```

### Filesystem / network tests

Miri isolates by default. For tests that legitimately need filesystem:

```bash
MIRIFLAGS="-Zmiri-disable-isolation" \
  cargo +nightly miri test --workspace --test fs_tests
```

Document in `verify.sh` which test targets need `-Zmiri-disable-isolation` and why.

### Stacked vs Tree Borrows

Run both. Stacked Borrows is stricter (the historical default); Tree Borrows is the newer model with more accepted patterns. A rewrite that fails Stacked but passes Tree is acceptable IF the failure is documented as a known Stacked Borrows false-positive (rare and worth interrogating).

```bash
# Stacked Borrows (default)
cargo +nightly miri test
# Tree Borrows
MIRIFLAGS="-Zmiri-tree-borrows" cargo +nightly miri test
```

### Known traps

- **Crates that link to native libraries** — miri can't execute the native code. Mark FFI tests as `#[cfg(not(miri))]` and rely on careful + fuzz for those paths.
- **Stack overflow under miri** — miri's stack is small. Use `RUST_MIN_STACK=8388608` (8MB) for deep-recursion tests.
- **Long miri runtimes** — miri is ~100× slower than native. Use `--release` is ineffective (miri ignores opt-level for soundness reasons). Scope miri tests to the rewritten module.

---

## cargo-careful

### What it catches

Miri-style UB detection at native execution speed, by inserting runtime checks. Catches a subset of what miri catches but runs on real binaries, including those that link native code.

### Standard invocation

```bash
cargo +nightly careful test --workspace --all-features
```

### Difference from miri

- Native speed (no interpretation).
- Works on FFI-heavy crates miri can't run.
- Catches FEWER classes (no Stacked Borrows; no Tree Borrows; no provenance).
- Use cargo-careful for paths miri rejects; use miri for paths cargo-careful can't model.

### Known traps

- Slower than vanilla cargo test (~2–5×).
- Some `unsafe` patterns that pass careful still fail miri — careful is necessary but not sufficient.

---

## loom

### What it catches

All possible interleavings of concurrent operations on a model (atomics + threads + cells), within the configured budget. Catches use-after-free across threads, lost updates, ABA, deadlock under specific interleavings.

### Standard usage

```toml
# Cargo.toml
[target.'cfg(loom)'.dev-dependencies]
loom = "0.7"

[features]
loom_concurrency_tests = []
```

```rust
// src/foo.rs
#[cfg(loom)]
use loom::sync::Arc;
#[cfg(not(loom))]
use std::sync::Arc;
// ... atomics, threads similarly aliased ...

#[cfg(loom)]
#[test]
fn loom_no_data_race() {
    loom::model(|| {
        // your concurrent code here
    });
}
```

### Invocation

```bash
RUSTFLAGS="--cfg loom" cargo test --features loom_concurrency_tests --release
```

`--release` is recommended because loom models are CPU-intensive.

### Budget tuning

Default budget is fine for 2 threads and ~10 atomic operations. For larger models:

```rust
loom::model::Builder::new()
    .preemption_bound(3)
    .max_branches(10_000)
    .check(|| { /* ... */ });
```

### Known traps

- Models do NOT exercise `unsafe { /* raw pointer */ }` — loom only instruments `loom::cell::UnsafeCell`. If the rewrite still has raw pointers, they're invisible to the model.
- The 2-thread model assumes both threads start; real-world startup races (e.g., `pthread_create` failure) aren't modeled.
- Loom builds slower (instrumentation overhead). Keep loom tests under `cfg(loom)` so they don't bloat normal builds.

---

## cargo-fuzz

### What it catches

UB and panics on arbitrary inputs. Use for any (C) rewrite that widens or modifies a public surface that takes external input.

### Setup

```bash
cd <crate>
cargo fuzz init
cargo fuzz add my_target
```

`fuzz/fuzz_targets/my_target.rs`:

```rust
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let _ = mycrate::parse(data);  // must not UB, must not panic on arbitrary input
});
```

### Invocation

```bash
cargo +nightly fuzz run my_target -- -max_total_time=60
```

For sustained fuzzing (CI nightly): `-max_total_time=3600` (1 hour).

### Known traps

- Targets that allocate unboundedly will OOM-kill the fuzzer (not a UB finding).
- libfuzzer can't model network or filesystem; use `arbitrary` crate for structured inputs.
- A panic-free run isn't proof — coverage matters. Use `cargo fuzz coverage my_target` to see what's exercised.

---

## cargo-mutants

### What it catches

Tests that pass even when the code under test is broken. A mutation is a small code change (replace `+` with `-`, change `<` to `<=`, etc.); if the test suite still passes, the test was not pinning the behavior the mutation broke.

### Invocation

```bash
cargo mutants --in-place=false --jobs 4
```

`--in-place=false` runs mutations in a copy (slower, safer).

### Interpretation

- A "missed" mutation means the test suite is loose. Mutations on production code paths must be CAUGHT by the test suite or the test suite is folklore.
- For an unsafe-audit context: every (C) rewrite's equivalence property test should catch mutations on BOTH the old unsafe and the new safe versions.

### Known traps

- Slow (combinatorial in mutations × tests).
- Some mutations are equivalent (semantically identical to the original); not a bug.
- Configure with `.cargo/mutants.toml` to skip uninteresting mutations (e.g., trace-string changes).

---

## cargo-geiger

### What it catches

Per-crate `unsafe` counts. The metric: `unsafe { }` + `unsafe fn` + `unsafe impl` + `unsafe trait` declarations.

### Invocation

```bash
cargo +nightly geiger --output-format Json > <audit-dir>/geiger-after.json
```

### Use in the audit

Phase 1 captures `geiger-before.json`. Phase 9 captures `geiger-after.json`. The delta MUST match the planned (C) refactor count.

A geiger delta of zero with substantial refactor work means we moved unsafe around without removing any — investigate.

A geiger delta worse than planned means we added unsafe we didn't intend — investigate.

### Known traps

- Counts the lexical `unsafe`, not the semantic unsafe surface. A single `unsafe fn` with 10 callers counts once.
- Doesn't follow macro expansion; `cargo expand` first if macros are heavy.
- Some forbid-unsafe-via-`#![forbid(unsafe_code)]` crates still show 0; that's correct.

---

## hyperfine (perf measurement)

For every (B) classification:

```bash
# warmup, then 10 runs
hyperfine --warmup 3 --runs 10 \
  './target/release/myapp --workload canonical' \
  './target/release/myapp-safe --workload canonical' \
  --export-json <audit-dir>/audit/plans/bench-site-NNNN.json
```

The harness `scripts/bench-before-after.sh` runs this AND `cargo bench` AND `cargo flamegraph` per (B) site.

---

## Composing into verify.sh

The composite harness lives at `<audit-dir>/verify.sh` and executes the tools in this order. Each step tees to a per-step log AND to the combined `verify.log`.

```bash
#!/usr/bin/env bash
set -euo pipefail

AUDIT_DIR="${1:-.}"
LOG="$AUDIT_DIR/audit/phase9/verify.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

echo "[1/7] cargo +nightly miri test"
cargo +nightly miri test --workspace --all-features

echo "[2/7] cargo +nightly miri test (strict provenance)"
MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri test --workspace --all-features

echo "[3/7] cargo +nightly careful test"
cargo +nightly careful test --workspace --all-features

echo "[4/7] loom"
RUSTFLAGS="--cfg loom" cargo test --features loom_concurrency_tests --release

echo "[5/7] cargo fuzz (60s per target)"
for target in $(cargo fuzz list); do
  cargo +nightly fuzz run "$target" -- -max_total_time=60
done

echo "[6/7] cargo mutants"
cargo mutants --in-place=false --jobs 4 --output "$AUDIT_DIR/audit/phase9/mutants/"

echo "[7/7] cargo +nightly geiger (delta check)"
cargo +nightly geiger --output-format Json > "$AUDIT_DIR/geiger-after.json"
# Compare by count against the Phase 1 baseline. New audits store
# per-crate `phase1/*__geiger.json`; older audits may have one
# `phase1/cargo-geiger.json`.

echo "[default features] cargo test"
cargo test --workspace --all-features

echo "[safe-only features] cargo test"
cargo test --workspace --features safe-only --no-default-features

echo "verify.sh OK"
```

`scripts/verify.sh` is the canonical template; `assets/verify.sh.template` is the user-installable copy.

---

## Tool-output triage

When a tool fails:

1. **Classify per operator ⚑ Pre-Existing-UB-Isolator.** Is the finding in code the refactor touched (IN-SCOPE) or in code the refactor didn't touch (OUT-OF-SCOPE)?
2. **IN-SCOPE:** open the relevant `audit/plans/site-<id>.md`, refine the rewrite, re-test. Land via the bead's normal flow.
3. **OUT-OF-SCOPE:** file `pre-existing-ub-N` bead with full reproduction. Do NOT widen the current refactor. Note in `audit/synthesis/pre-existing-ub.md`.

A harness that fails clean (every finding either resolved in-scope or filed out-of-scope) is acceptable. A harness that fails with un-triaged findings is not.
