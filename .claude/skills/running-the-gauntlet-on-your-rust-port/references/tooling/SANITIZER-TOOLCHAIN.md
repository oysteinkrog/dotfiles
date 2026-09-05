# SANITIZER-TOOLCHAIN.md — ASan / TSan / MSan / LSan / Miri / Polonius

How to run the Rust port under each sanitizer; the nightly-only flags; the per-sanitizer env-var matrix; why a sanitizer finding is a conformance failure (not "just a debug-build warning"); and when to escalate to Miri for UB-class divergences. Cross-links: [FUZZ-TOOLCHAIN.md](FUZZ-TOOLCHAIN.md) for fuzz-under-sanitizer (the highest-yield combination); [CONCURRENCY-TOOLCHAIN.md](CONCURRENCY-TOOLCHAIN.md) for TSan as the dynamic complement to loom/shuttle.

## 0. Core Discipline

> **A port that segfaults on a workload doesn't have parity with a reference that doesn't. Sanitizer findings are conformance failures.** A "100% pass rate" claim with an unreported ASan use-after-free is dishonest.

The 5 sanitizers + Miri + Polonius cover orthogonal failure classes:

| Tool | What it catches |
|---|---|
| **ASan** (address) | Use-after-free, heap-buffer-overflow, stack-buffer-overflow, double-free, invalid `free()`. |
| **TSan** (thread) | Data races (unsynchronized access from multiple threads). |
| **MSan** (memory) | Reads of uninitialized memory. |
| **LSan** (leak) | Memory leaks at exit. |
| **UBSan** (undefined behavior) | Integer overflow, signed-integer wraparound, alignment violations, null deref. |
| **Miri** | Pointer provenance, aliasing violations (Stacked Borrows / Tree Borrows), uninit reads, dangling references, type-level UB. |
| **Polonius** | Borrow-checker variant — catches some cases the current `rustc` borrow checker rejects falsely (and vice versa). |

---

## 1. Building with Sanitizers

All require **nightly** Rust + an explicit target (sanitizers are linked into the target-specific runtime).

```bash
rustup toolchain install nightly
rustup component add rust-src --toolchain nightly
```

### 1.1 The Four Sanitizers + UBSan

```bash
# ASan (default; ~2x runtime cost)
RUSTFLAGS="-Zsanitizer=address" \
    cargo +nightly build --target x86_64-unknown-linux-gnu -Z build-std

# TSan (data races; ~5-15x runtime cost)
RUSTFLAGS="-Zsanitizer=thread" \
    cargo +nightly build --target x86_64-unknown-linux-gnu -Z build-std

# MSan (uninit reads; ~3x runtime cost)
RUSTFLAGS="-Zsanitizer=memory -Zsanitizer-memory-track-origins" \
    cargo +nightly build --target x86_64-unknown-linux-gnu -Z build-std

# LSan (leaks; ~0 runtime cost; runs at exit only)
RUSTFLAGS="-Zsanitizer=leak" \
    cargo +nightly build --target x86_64-unknown-linux-gnu

# UBSan
RUSTFLAGS="-Zsanitizer=undefined" \
    cargo +nightly build --target x86_64-unknown-linux-gnu
```

### 1.2 Why the `--target` Flag

Sanitizer runtimes are compiled per-target. Without `--target x86_64-unknown-linux-gnu` (or your local triple), Cargo builds the workspace and its `build-dependencies` with the same RUSTFLAGS, and the sanitizer crashes on its own build-script binaries. Always pass an explicit target.

### 1.3 Why `-Z build-std`

The standard library ships **without** sanitizer instrumentation by default. `-Z build-std` rebuilds `std` + `core` with the same RUSTFLAGS, so the sanitizer sees instrumented allocations / sync primitives / etc.

For ASan / LSan, `-Z build-std` is optional but recommended.
For TSan / MSan, `-Z build-std` is **mandatory** — without it, std types' internal synchronization confuses TSan, and MSan reports millions of false positives from std-internal allocations.

---

## 2. Sanitizer-Specific Environment Variables

| Sanitizer | Env var | Default | Why override |
|---|---|---|---|
| ASan | `ASAN_OPTIONS=detect_leaks=1:abort_on_error=1:strict_string_checks=1:detect_stack_use_after_return=1` | partial | Catch leaks too; abort on first error for cleaner stack trace; check stack-after-return (off by default for perf). |
| ASan | `ASAN_SYMBOLIZER_PATH=/usr/bin/llvm-symbolizer` | path | Need this if reports show numeric addresses instead of symbols. |
| TSan | `TSAN_OPTIONS=halt_on_error=1:second_deadlock_stack=1:history_size=7` | partial | Halt on first; show both stacks on deadlock; max history. |
| MSan | `MSAN_OPTIONS=poison_in_dtor=1:halt_on_error=1` | partial | Poison destructed memory; halt for stack-trace coherence. |
| LSan | `LSAN_OPTIONS=suppressions=lsan-suppressions.txt:print_suppressions=1` | none | Suppress known leaks (e.g., from C deps); print which suppressions matched (catches stale suppressions). |
| UBSan | `UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1` | partial | Full stack; halt for clarity. |

### LSan Suppression File Example

```
# lsan-suppressions.txt
leak:libsqlite3      # known C SQLite alloc-once globals; intentional
leak:dlopen          # dlopen-cached strings; intentional
leak:python3         # PyO3 sub-interpreter cached globals
```

---

## 3. Running the Test Suite Under Sanitizers

### 3.1 Full Workspace Test Suite

```bash
# TSan (most common for a port with concurrency)
RUSTFLAGS="-Zsanitizer=thread" \
TSAN_OPTIONS="halt_on_error=1:second_deadlock_stack=1" \
cargo +nightly test --target x86_64-unknown-linux-gnu -Z build-std --release
```

The `--release` is important: TSan in `debug` is so slow (10-15x baseline) that a 10-minute test suite balloons to 2 hours.

### 3.2 Per-Crate (for quick iteration)

```bash
cargo +nightly test --target x86_64-unknown-linux-gnu -Z build-std \
    -p fsqlite-mvcc --release \
    -- --test-threads=1
```

`--test-threads=1` keeps the sanitizer report bounded; multiple threads producing concurrent reports interleave into garbage.

### 3.3 Specific Test

```bash
cargo +nightly test --target x86_64-unknown-linux-gnu -Z build-std \
    -p fsqlite-mvcc --release \
    -- --exact test_concurrent_commit_no_data_race
```

---

## 4. Running Fuzz Harnesses Under Sanitizers

The highest-yield combination: a fuzz target + a sanitizer + 24 hours.

```bash
# Default: cargo-fuzz uses ASan
cargo +nightly fuzz run fuzz_sql_parser

# Switch to thread sanitizer
cargo +nightly fuzz run fuzz_sql_parser --sanitizer thread

# Switch to memory sanitizer
cargo +nightly fuzz run fuzz_sql_parser --sanitizer memory

# Switch to leak sanitizer
cargo +nightly fuzz run fuzz_sql_parser --sanitizer leak
```

`cargo-fuzz` handles all the `-Z build-std`, `--target`, RUSTFLAGS wiring automatically. The `--sanitizer` flag is the only knob you touch.

### Per-Class Recommendations

| Fuzz target type | Sanitizer of choice |
|---|---|
| Parser / lexer | ASan (catches buffer overruns in parsing). |
| Concurrent dispatcher | TSan (data races dominate). |
| Codec / serializer / deserializer | ASan + MSan (uninit reads in unsafe deserialization paths). |
| Long-running / leaky-suspect | LSan. |
| Anything in `unsafe { }` | All four, separately. |

---

## 5. Why Sanitizer Findings Count as Conformance Failures

> A port that segfaults on a workload doesn't have parity with a reference that doesn't.

The C reference doesn't have data races (it's single-threaded, or it has correct mutexes). The Rust port has TSan reports on `mvcc.rs`. The port is non-conformant. Period.

The trap to avoid: "but the test still passes, the sanitizer warning is just a warning." If TSan reports a data race, the program has undefined behavior — it just happened not to crash on this test machine, this time. UB is a parity violation.

CI rule: any sanitizer warning fails the lane. Treat sanitizer output with the same severity as a `TrueDivergence` from [ORACLE-TOOLCHAIN.md § MismatchClassification](ORACLE-TOOLCHAIN.md).

---

## 6. Miri — UB-Class Divergences

`miri` is a Rust MIR interpreter that detects undefined behavior the compiled binaries can't catch: pointer provenance violations, dangling references through transmuted pointers, Stacked Borrows / Tree Borrows aliasing violations, uninit-read through `MaybeUninit::assume_init`, etc.

### 6.1 Setup

```bash
rustup +nightly component add miri rust-src
cargo +nightly miri setup       # first-time only; pre-builds miri-instrumented std
```

### 6.2 Run

```bash
# Per-crate (recommended for iteration)
cargo +nightly miri test -p fsqlite-mvcc

# Workspace (slow; for nightly soak)
cargo +nightly miri test
```

### 6.3 Configuration

```bash
MIRIFLAGS="-Zmiri-strict-provenance \
           -Zmiri-symbolic-alignment-check \
           -Zmiri-tree-borrows" \
cargo +nightly miri test -p fsqlite-mvcc
```

| Flag | Effect |
|---|---|
| `-Zmiri-strict-provenance` | Enforces strict provenance rules (planned future Rust default). Catches pointer-as-integer round-trips that work today but won't tomorrow. |
| `-Zmiri-symbolic-alignment-check` | Catches alignment violations missed by ordinary numeric alignment checks. |
| `-Zmiri-tree-borrows` | Use Tree Borrows aliasing model (more permissive than Stacked Borrows). |
| `-Zmiri-disable-isolation` | Allow filesystem / network / clock; needed for integration tests, weakens determinism. |

### 6.4 The Slow-But-Thorough Option

Miri runs ~50-100x slower than native execution. A test that runs in 1s natively takes 1-2 minutes under Miri. A workspace test suite of 10 minutes natively takes 8-16 hours under Miri.

**Strategy:** Phase 15 multi-day soak. Run Miri across the harness internals nightly via `rch`. Findings are bead-quality bugs.

### 6.5 Miri vs Sanitizers Decision

| Property | Sanitizers | Miri |
|---|---|---|
| Detects spatial memory errors (overruns, UAF) | Yes (ASan) | Limited |
| Detects data races | Yes (TSan) | Yes |
| Detects uninit reads | Yes (MSan) | Yes |
| Detects pointer provenance violations | No | Yes |
| Detects Stacked / Tree Borrows violations | No | Yes |
| Catches bugs in unsafe code that "happen to work" | Sometimes | Yes |
| Production-grade C interop (libsqlite3, BLAS) | Yes | No (Miri can't run most FFI) |
| Speed | 2-15x | 50-100x |

For a Rust port wrapping a C library, **sanitizers are the production tool**; Miri is for the pure-Rust internals.

---

## 7. Polonius — Next-Gen Borrow Checker

```bash
RUSTFLAGS="-Zpolonius" cargo +nightly build
```

Polonius is the next-generation Rust borrow checker, more precise than the current NLL implementation. Catches some real bugs missed by NLL (rare); accepts some valid programs NLL rejects (more common).

### When to Run Polonius

- Pre-release: confirm the port compiles under both checkers. If Polonius rejects code NLL accepted, that's a future-Rust regression to fix now.
- Rare: as a debugging tool when NLL emits a confusing error and you want a second opinion.

### Polonius Reports

```
error[E0502]: cannot borrow `self.cache` as mutable because it is also borrowed as immutable
  --> crates/fsqlite-core/src/connection.rs:1234:9
```

Same format as NLL errors, but the *set* of errors differs slightly. Sometimes Polonius accepts code NLL rejects (great, you can simplify lifetime annotations); sometimes Polonius rejects code NLL accepts (bug-fix needed before Rust default flips).

---

## 8. Per-Project-Class Sanitizer Matrix

Default lanes in Phase 15 (see [../methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md)):

| Class | Sanitizers run | Miri | Notes |
|---|---|---|---|
| **SQL** (FrankenSQLite) | ASan, TSan, LSan | yes (harness only; not the C-linked path) | LSan suppress libsqlite3 leaks. |
| **RESP** (FrankenRedis) | ASan, TSan, LSan | yes (parser only) | Vendored redis-server runs outside sanitizer. |
| **NumPy** (franken_numpy) | ASan, MSan, LSan | yes (Rust core) | LSan suppress Python + numpy globals. |
| **ML-System** (FrankenTorch) | ASan, TSan, LSan | rare | CUDA paths can't be sanitized; CPU paths can. |
| **HTTP** (FastAPI) | ASan, TSan, LSan | yes | Standard async stack. |

---

## 9. Pitfalls

| Pitfall | Why it bites | Fix |
|---|---|---|
| Stable Rust + sanitizer | Sanitizer flags are nightly-only | `rustup default nightly` for the sanitizer lane; or `rustup run nightly cargo ...`. |
| Missing `-Z build-std` for TSan | TSan sees std-internal mutexes as races | Always `-Z build-std` for TSan/MSan; install `rust-src` component. |
| Missing `--target` | Sanitizer-instrumented build-scripts crash | `--target x86_64-unknown-linux-gnu` (or your local triple). |
| MSan + std without build-std | Millions of false positives | `-Z build-std` rebuilds std with MSan instrumentation. |
| LSan against PyO3 / libsqlite3 | C deps allocate-once globals look like leaks | `LSAN_OPTIONS=suppressions=lsan-suppressions.txt`; entry per C dep. |
| TSan against single-thread async runtime | Tokio current-thread runtime has internal "races" by design | Use `tokio::runtime::Builder::new_multi_thread()` for TSan lane. |
| Sanitizer-incompatible deps | Some `-sys` crates link without sanitizer support | Identify via `cargo tree`; either rebuild with sanitizer-aware features or exclude from the sanitizer build. |
| FFI symbol clashes | Sanitizer's `malloc` interceptor clashes with C deps' custom allocator | Use `ASAN_OPTIONS=verify_asan_link_order=0` (last-resort); or rebuild the C dep without its custom allocator. |
| Sanitizer-only flakes | Test passes natively, fails under TSan on one in 10 runs | The flake is the bug. TSan is detecting a race that happens to commit harmlessly in native runs. Investigate as a real race. |
| Miri on FFI-heavy code | Miri can't run most extern calls | Run Miri on pure-Rust crates only; gate FFI tests behind `#[cfg(not(miri))]`. |
| Sanitizer reports in CI without symbolizer | Reports show 0x7f0a... numbers instead of symbols | `ASAN_SYMBOLIZER_PATH=/usr/bin/llvm-symbolizer` in CI env. |
| Stale `target/` after switching sanitizers | Old artifacts mix with new instrumentation; segfault at runtime | `cargo clean` between sanitizer-flag changes; or use separate `--target-dir`. |
| `LSAN_OPTIONS` ignored on macOS | LSan support on macOS is partial | LSan lane runs Linux-only; macOS uses ASan + leak-detection via macOS heap tools. |

---

## 10. Wiring into CI

```yaml
# .github/workflows/sanitizers.yml
name: Sanitizers
on:
  schedule:
    - cron: '0 6 * * *'       # daily 06:00 UTC
  workflow_dispatch:

jobs:
  asan:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@nightly
        with: { components: rust-src }
      - run: |
          RUSTFLAGS="-Zsanitizer=address" \
          ASAN_OPTIONS="detect_leaks=1:abort_on_error=1" \
          cargo +nightly test --target x86_64-unknown-linux-gnu -Z build-std --release

  tsan:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@nightly
        with: { components: rust-src }
      - run: |
          RUSTFLAGS="-Zsanitizer=thread" \
          TSAN_OPTIONS="halt_on_error=1" \
          cargo +nightly test --target x86_64-unknown-linux-gnu -Z build-std --release

  miri:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@nightly
        with: { components: miri, rust-src }
      - run: cargo +nightly miri setup
      - run: cargo +nightly miri test -p fsqlite-harness   # pure-Rust only
```

---

## See Also

- [FUZZ-TOOLCHAIN.md](FUZZ-TOOLCHAIN.md) — `cargo fuzz run --sanitizer thread` is the highest-yield bug-finding combo.
- [CONCURRENCY-TOOLCHAIN.md](CONCURRENCY-TOOLCHAIN.md) — TSan as dynamic complement to loom (static-state) and shuttle (random-state).
- [BENCH-TOOLCHAIN.md](BENCH-TOOLCHAIN.md) — sanitizer-built benches reveal hidden UB that perf wins quietly depend on.
- [ORACLE-TOOLCHAIN.md](ORACLE-TOOLCHAIN.md) — sanitizer findings are `TrueDivergence` class; not "warnings".
- [../methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md) — multi-day Miri + sanitizer campaigns in Phase 15.
