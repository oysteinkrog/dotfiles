# Tooling — Every Detector With Exact Invocations & Pitfalls

This is the arsenal. Each tool has a recommended invocation, gotchas, and notes on when *not* to use it.

---

## Miri (the workhorse)

Miri is an interpreter for Rust's mid-level IR that catches UB by simulating the abstract machine. Its detection power comes from its config flags (`MIRIFLAGS`) — running it once without flags is a triage, not an audit.

### Install
```bash
rustup toolchain install nightly
rustup component add miri rust-src --toolchain nightly
```

### The MIRIFLAGS matrix (run all four)
```bash
# 1) Default (stacked borrows) — baseline
cargo +nightly miri test 2>&1 | tee phase3_raw/miri_default.log

# 2) Tree borrows — stricter aliasing model (catches more than SB)
MIRIFLAGS="-Zmiri-tree-borrows" cargo +nightly miri test 2>&1 | tee phase3_raw/miri_tree.log

# 3) Strict provenance — catches int↔ptr casts that lose provenance
MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri test 2>&1 | tee phase3_raw/miri_provenance.log

# 4) Symbolic alignment — catches misaligned derefs
MIRIFLAGS="-Zmiri-symbolic-alignment-check" \
  cargo +nightly miri test 2>&1 | tee phase3_raw/miri_symbolic_alignment.log
```

Plain Miri checks invalid enum/scalar values by default on current nightlies.
Do not add `-Zmiri-check-number-validity`; current Miri rejects that obsolete
flag before the test suite runs.

### Stress modes (run on suspect tests)
```bash
# Maximum preemption — catches races that only manifest under specific schedules
MIRIFLAGS="-Zmiri-preemption-rate=0" cargo +nightly miri test test_suspect_race -- --nocapture

# Combined for paranoid runs
MIRIFLAGS="-Zmiri-tree-borrows -Zmiri-strict-provenance -Zmiri-symbolic-alignment-check -Zmiri-ignore-leaks" \
  cargo +nightly miri test
```

### Run individual binaries
```bash
cargo +nightly miri run --bin "<name>" -- "<args>"
```

### Pitfalls
- Miri **does not run FFI** by default. Code paths that call into C will hit an error: "unsupported operation: can't call foreign function". Stub the C call with a Rust shim for the Miri-only build (`#[cfg(miri)]`).
- Miri is slow — 5–100× native. Don't run it on the whole test suite for tight loops; pick targeted tests.
- Miri output is verbose. Filter with `rg 'Undefined Behavior|TB violation|SB violation|note:'` for the signal.

---

## Sanitizers (ASan, TSan, MSan, LSan)

LLVM sanitizers instrument the binary to catch UB at runtime. They complement Miri because they run native code at near-native speed and *do* execute FFI.

### Install / requirements
- nightly Rust (`rustup default nightly` or `+nightly`)
- Linux x86_64 (best support); other targets vary
- `rust-src` component: `rustup component add rust-src --toolchain nightly`

### ASan — heap/stack buffer overflows, use-after-free, double-free
```bash
RUSTFLAGS="-Zsanitizer=address -Z sanitizer-recover=address" \
  cargo +nightly test --target x86_64-unknown-linux-gnu 2>&1 | tee phase3_raw/asan.log
```

### TSan — data races, deadlocks
```bash
RUSTFLAGS="-Zsanitizer=thread" \
  cargo +nightly test --target x86_64-unknown-linux-gnu -- --test-threads=1 2>&1 | tee phase3_raw/tsan.log
```
**Critical:** `--test-threads=1` forces test ordering visibility. Without it, tests race with each other instead of with the code under test.

### MSan — uninitialized memory reads
```bash
RUSTFLAGS="-Zsanitizer=memory -C target-cpu=x86-64 -Z build-std" \
  cargo +nightly test --target x86_64-unknown-linux-gnu -- --test-threads=1
```
MSan requires the whole std rebuilt with the sanitizer; `-Z build-std` triggers that.

### LSan — memory leaks
```bash
RUSTFLAGS="-Zsanitizer=leak" \
  cargo +nightly test --target x86_64-unknown-linux-gnu
```

### Pitfalls
- Sanitizers fight each other — never combine ASan + TSan + MSan in one build. Run them in separate passes.
- ThreadSanitizer false-positives are rare but real (e.g., happen-before via signals can confuse it). Read the trace carefully.
- MSan's std rebuild can fail on first run; fix by retrying once cargo's std cache is warm.

---

## Loom

Loom is an exhaustive interleaving explorer for concurrent code. Wrap your sync primitives in `loom::sync::*` and write a model; loom runs every legal interleaving.

### Setup
Add to `Cargo.toml`:
```toml
[target.'cfg(loom)'.dependencies]
loom = "0.7"
```
Add the model as a `#[cfg(loom)] #[test]`:
```rust
#[cfg(loom)]
mod loom_tests {
    use loom::sync::{Arc, atomic::{AtomicUsize, Ordering}};
    use loom::thread;

    #[test]
    fn ordering_holds() {
        loom::model(|| {
            let n = Arc::new(AtomicUsize::new(0));
            let h = {
                let n = n.clone();
                thread::spawn(move || n.store(1, Ordering::Release))
            };
            let v = n.load(Ordering::Acquire);
            h.join().unwrap();
            assert!(v == 0 || v == 1);
        });
    }
}
```

### Run
```bash
RUSTFLAGS="--cfg loom" cargo +nightly test --release loom_tests 2>&1 | tee phase3_raw/loom.log
```

### Pitfalls
- Loom blows up combinatorially past **3 threads** or **~1000 iterations**. Keep models tiny.
- Tests must be deterministic given the loom-scheduled interleaving; don't pull from system time / RNG.
- Loom is *not* for testing tokio runtimes wholesale — only for your custom sync primitives.

---

## Shuttle

Shuttle is loom's probabilistic cousin — random-walks the schedule space instead of exhaustively exploring it. Use when loom times out.

```toml
[dev-dependencies]
shuttle = "0.7"
```

```rust
#[test]
fn shuttle_check_random() {
    shuttle::check_random(my_model, 1000);
}
```

Use when the model is too large for loom but a 1000-iteration random walk gives enough confidence.

---

## cargo-fuzz (libFuzzer)

Coverage-guided fuzzing for parsers, codecs, and bounds-checking unsafe blocks.

### Setup
```bash
cargo install cargo-fuzz
cargo +nightly fuzz init
```

### Author a target
```rust
// fuzz/fuzz_targets/parse.rs
#![no_main]
use libfuzzer_sys::fuzz_target;
fuzz_target!(|data: &[u8]| {
    let _ = my_crate::parse(data);
});
```

### Run
```bash
cargo +nightly fuzz run parse -- -max_total_time=600 -timeout=5 \
  -artifact_prefix=phase3_raw/fuzz_artifacts/
```

### Structure-aware fuzzing (preferred for non-byte inputs)
```rust
use arbitrary::{Arbitrary, Unstructured};
use libfuzzer_sys::fuzz_target;
fuzz_target!(|input: MyStructInput| { ... });
```
With `MyStructInput: Arbitrary`, libfuzzer generates valid-shape inputs instead of random bytes.

### Pitfalls
- Run with a corpus directory to amortize work across runs.
- Don't run fuzz campaigns under Miri — way too slow. Run fuzz first, then run *the crashes* under Miri to triage.

---

## cargo-afl (AFL++)

AFL++ is an alternative fuzzer with a different scheduling heuristic. Useful when libFuzzer gets stuck.

```bash
cargo install cargo-afl
cargo afl build
cargo afl fuzz -i in/ -o out/ "./target/debug/<target>"
```

---

## cargo-geiger

Counts unsafe blocks per crate, including transitive deps. Useful for tracking unsafe surface over time; **not** a soundness oracle.

```bash
cargo install cargo-geiger
cargo geiger --output-format Json > phase2_geiger.json
```

Pitfalls: counts benign unsafe (e.g., `core::hint::unreachable_unchecked` in an `unwrap_unchecked`) the same as soundness-critical unsafe. Use as a trend signal, not as a verdict.

---

## cargo-audit / cargo-deny

Scan Cargo.lock for known-vulnerable dependencies. UB in a dep is your UB.

```bash
cargo install cargo-audit cargo-deny
cargo audit
cargo deny check advisories
```

---

## Clippy — the safety-lint groups

```bash
cargo clippy --all-targets -- \
  -W clippy::pedantic \
  -W clippy::nursery \
  -W clippy::cargo \
  -W clippy::undocumented_unsafe_blocks \
  -W clippy::multiple_unsafe_ops_per_block \
  -W clippy::cast_ptr_alignment \
  -W clippy::cast_ref_to_mut \
  -W clippy::ptr_as_ptr \
  -W clippy::transmute_undefined_repr \
  -W clippy::transmute_int_to_bool \
  -W clippy::transmute_int_to_char \
  -W clippy::uninit_assumed_init \
  -W clippy::derive_ord_xor_partial_ord \
  -W clippy::derive_hash_xor_eq \
  2>&1 | tee phase2_clippy.log
```

Triage the firehose — most pedantic lints are noise, the listed groups are the soundness ones.

---

## rustc `-W` safety lints

Beyond clippy, rustc has its own safety lints worth enabling project-wide:

```bash
RUSTFLAGS="-W unsafe_op_in_unsafe_fn \
          -W unused_unsafe \
          -W invalid_reference_casting \
          -W dangling_pointers_from_temporaries \
          -W unaligned_references \
          -W improper_ctypes \
          -W improper_ctypes_definitions" \
  cargo +nightly check --all-targets
```

`unsafe_op_in_unsafe_fn` is especially valuable — by default, inside an `unsafe fn`, every unsafe op is implicitly allowed without a block. This lint forces explicit `unsafe { … }` blocks even inside `unsafe fn`, which means SAFETY comments are forced on each op.

---

## ast-grep — structural patterns

ast-grep parses Rust to ASTs, so it doesn't match `unsafe` inside comments or string literals. The bundled pattern set is in `scripts/patterns/`.

```bash
ast-grep scan --rule scripts/patterns/aliasing-deref-while-borrowed.yml SOURCE/
ast-grep scan -r scripts/patterns/                 # apply every pattern
```

Add patterns as you discover new UB shapes specific to the project.

---

## semgrep — semantic regex patterns

Slower than ast-grep but supports dataflow. Use for patterns that involve cross-function flow (e.g., "a pointer escapes from constructor and is used in another function after the original is dropped").

```bash
semgrep --config=auto SOURCE/
semgrep --config=scripts/semgrep-rules/ SOURCE/
```

---

## syn-based walkers

When ast-grep can't express the predicate (e.g., "every `unsafe fn` that has no `# Safety` doc comment", "every raw pointer that ever escapes its construction scope"), use a `syn` walker.

The bundled walkers live under `scripts/syn-walkers/src/bin/` (each is a cargo
binary; build & run via `cargo run --manifest-path scripts/syn-walkers/Cargo.toml --bin <name> -- <src>`):
- `aliasing.rs` — flags `*mut T` deref within scope of a live `&T`
- `validity.rs` — flags `mem::zeroed::<T>()` for T with non-zero-valid fields
- `transmute_pairs.rs` — extracts source/target types of every `transmute`
- `data_races.rs` — flags `&Cell` / `&UnsafeCell` shared cross-thread
- `pin_walker` (`src/bin/pin.rs`) — flags `Pin::new_unchecked` calls and nearby move hazards
- `escape.rs` — flags raw pointers escaping their borrow scope
- `safety_doc_coverage.rs` — flags `unsafe fn` without `# Safety` doc + `unsafe { }` blocks without preceding `// SAFETY:` comment

Build:
```bash
cd scripts/syn-walkers
cargo run --release --bin "<walker>" -- "$SOURCE"
```

---

## cargo-expand — macro expansion audit

Macros can generate unsafe blocks that hand-reading misses. Run `cargo expand` and grep:
```bash
cargo expand --lib > /tmp/expand.rs
rg -n 'unsafe' /tmp/expand.rs
diff <(rg -n 'unsafe' --type rust src/) <(rg -n 'unsafe' /tmp/expand.rs)
```

---

## cargo doc --document-private-items — SAFETY-doc coverage

```bash
cargo doc --document-private-items --no-deps 2>&1 | tee phase2_doc.log
```

Then run the `safety_doc_coverage.rs` walker. Every `unsafe fn` without a `# Safety` section is a docs bug *and* a likely UB bug (no documented contract ⇒ no audit trail).

---

## valgrind / memcheck

Useful only for Rust binaries that ship C dependencies and where the Rust std lib's allocator interactions are well-understood. Otherwise too many false positives.

```bash
valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=1 \
  "target/debug/<binary>"
```

---

## Polonius (next-gen borrow checker)

```bash
RUSTFLAGS="-Z polonius" cargo +nightly check
```

Polonius is more permissive than the default NLL borrow checker; running with polonius enabled occasionally surfaces patterns the current checker accepts that aren't really sound. Treat any new diagnostic as a hint, not a verdict.

---

## MIR dumps

```bash
cargo +nightly rustc --lib -- -Z dump-mir=all
```

The dumps land in `target/.../mir_dump/`. Use for hot functions where you want to see exactly what the borrow checker sees.

---

## KaniRust, Prusti, Creusot, Aeneas — formal verification

Reserved for hot kernels (custom allocator, custom lock-free queue) where formal proofs justify the engineering cost. Don't use these as a default — they require translation effort that doesn't pay off for ordinary code.

### Kani — bounded model checker (most accessible)

```bash
cargo install --locked kani-verifier
cargo kani setup   # one-time, downloads kani's CBMC backend
```

Author a proof:
```rust
#[cfg(kani)]
mod proofs {
    #[kani::proof]
    fn check_invariant() {
        let x: u32 = kani::any();
        kani::assume(x < 100);
        let result = my_fn(x);
        assert!(result < 1000);
    }
}
```

Run:
```bash
cargo kani --harness check_invariant
# Or via the script:
./scripts/run-kani.sh "$SOURCE" "$WORKSPACE" check_invariant
```

Pitfalls: Kani's default unwind budget is small; for loops with unknown bounds you'll need `--unwind N`. Symbolic inputs combine multiplicatively — keep the harness tiny.

### Prusti — Viper-backed verifier

```bash
# Install via prusti-cli (see prusti.github.io for current instructions)
```

Annotate functions with `#[requires(...)]`, `#[ensures(...)]`, loop invariants:
```rust
#[requires(x >= 0)]
#[ensures(result == x * x)]
fn square(x: i32) -> i32 { x * x }
```

Best for functional correctness on individual functions, less suited to whole-program UB checks.

### Creusot — translates Rust to Why3

Heavier setup; produces proof obligations discharged by SMT solvers (Z3, CVC4) or interactive provers. Reserved for cryptographic primitives and similar high-stakes algorithmic code.

### Aeneas — translates Rust to F*/Coq

Produces a pure-functional model of the Rust program for theorem proving in F* or Coq. Used for soundness proofs of cryptographic libraries.

See [REMEDIATION-PATTERNS.md §When Formal Verification Is Worth The Cost](REMEDIATION-PATTERNS.md#when-formal-verification-is-worth-the-cost).

---

## Tool decision tree

```
What kind of UB are you hunting?

Aliasing / borrow violations
├── First: Miri tree-borrows (-Zmiri-tree-borrows)
├── If clean: switch to stacked borrows (default) and compare
└── For raw-pointer-heavy code: also run the syn-walker `aliasing.rs`

Provenance / int↔ptr casts
├── First: Miri strict-provenance (-Zmiri-strict-provenance)
└── ast-grep `provenance-int-cast.yml`

Alignment violations
├── First: Miri symbolic-alignment-check
├── For #[repr(packed)]: clippy unaligned_references (now hard-error)
└── For mmap-backed atomics: audit the offset arithmetic manually

Validity invariants (bool, char, NonZero*, refs)
├── First: plain Miri (invalid enum/scalar values are checked by default)
├── For mem::zeroed: syn-walker `validity.rs`
└── For transmute: syn-walker `transmute_pairs.rs`

Uninitialized memory
├── First: Miri (default catches many)
├── Then: MSan with -Z build-std
└── For MaybeUninit: ast-grep `uninit-maybeuninit-assume-init.yml`

Type punning via transmute
├── First: syn-walker `transmute_pairs.rs` (extracts source/target)
├── Then: judge each pair for layout compatibility
└── Candidate rewrite: bytemuck/zerocopy

Data races
├── First: TSan with --test-threads=1
├── For sync primitives: loom (≤3 threads, ≤1k iters)
├── If loom times out: shuttle (10⁵+ random schedules)
└── For Miri-runnable races: -Zmiri-preemption-rate=0

Send/Sync invariants
├── First: syn-walker `data_races.rs` (flags every manual impl)
├── For each manual impl: audit SAFETY comment
└── Cross-check: TSan + loom

Pin invariants
├── First: ast-grep `pin-new-unchecked.yml`
├── Then: syn-walker `pin.rs` (also flags mem::replace near Pin)
└── For self-referential futures: Miri tree-borrows

FFI contracts
├── First: rustc -W improper_ctypes
├── Then: ASan against the test suite
├── Cross-reference each extern "C" against the C header (when available)
└── Author Miri shims for any FFI Miri can't run

Panic safety
├── First: drop-impl audit
├── For mem::forget / ManuallyDrop: ast-grep
└── Property test: panic at every unsafe op; assert no torn state remains

Std-library trait invariants
├── First: clippy derive_ord_xor_partial_ord, derive_hash_xor_eq
├── For HashMap keys: proptest a == b ⟹ hash(a) == hash(b)
└── For manual Iterator size_hint: ast-grep `manual-Iterator-size-hint.yml`

Refcount lifecycle
├── First: ast-grep `refcount-from-raw.yml`
├── For each from_raw: trace to into_raw / forget pairing
└── For multi-threaded: ASan + TSan

Lifetime escape
├── First: syn-walker `escape.rs`
├── Then: Miri tree-borrows
└── For closure captures: cargo expand to see hidden moves

Volatile contracts (MMIO)
├── First: ast-grep for read_volatile / write_volatile
└── Manual audit of producing pointer's alignment + validity

Async drop hazards
├── First: ast-grep `async-drop-block-on.yml`
├── tokio runtime metrics (worker-block detection)
└── Audit every Drop on async-context types

Inline asm UB
├── Manual audit + architecture manual
├── Miri: #[cfg(not(miri))] guard since asm! is unsupported
└── Cross-check clobber list against architecture spec
```

---

## Tool composability matrix

| Tool combo | Use case |
|---|---|
| ast-grep + syn-walker | Static sweep across Phase 2; ast-grep first (fast triage), syn-walker for predicates ast-grep can't express |
| Miri TB + Miri SB | Run both — they're separate aliasing models with different sensitivities |
| Miri + sanitizer | Miri for the abstract machine; sanitizer for native + FFI. They catch overlapping but non-identical sets |
| loom + shuttle | loom first (exhaustive for tiny models); shuttle when loom blows up |
| TSan + loom | TSan native at scale; loom for the model. Combine to catch the rare race-only-under-specific-schedule |
| fuzz + Miri | Fuzz to find inputs that crash; triage crashes under Miri to confirm UB |
| Kani + property tests | Kani for the bounded proof; property tests for the unbounded test suite. They reinforce each other |

---

## Tools the user does NOT historically use (upgrade path)

Per the cass mining (see [corpus/primary_sources/cass_quotes.md](../corpus/primary_sources/cass_quotes.md)), the user has not historically run these in captured sessions. The skill teaches them as the upgrade path:

| Tool | Closest user ritual to upgrade | Skill's entry point |
|---|---|---|
| `cargo +nightly miri test` (any flags) | Ritual 5 (Read-Only Delta Frame) on TLS/arena/mmap/fcntl code | After every ⊳ READ-ONLY-DELTA, propose a miri pass on the affected modules |
| Loom | Ritual 4 (Safety-Notes-First) for MmapBacking-shape types | "Safety-Notes-First + Loom-Model-First" — 30-line loom model on Drop ordering |
| Shuttle | Loom timeouts on >3 threads | Switch to shuttle 10⁵ when loom takes >30s |
| TSan / ASan / MSan / LSan | Ritual 2 (Named-Failure-Mode) when failure is "race" or "leak" | Run `scripts/run-sanitizer-matrix.sh` whenever a finding's bucket is data-races / refcount / FFI |
| Kani | Ritual 4 (Safety-Notes-First) for custom allocator / lock-free DS / FFI public API | After ☣ SAFETY-NOTES-FIRST, author a `#[kani::proof]` harness for the unsafe core |
| cargo-geiger | Ritual 9 (Default-Forbid Stance) | One-liner CI: `cargo geiger --output-format Json` to track unsafe-surface trend |
| cargo fuzz with Arbitrary | Ritual 8 (release-gate runs cargo audit + cargo test) | Add `cargo +nightly fuzz run <target>` for every unsafe API |

The skill positions these as **upgrades, not replacements**. The user's existing methodology (suspect-list audits, named-failure-mode questions, local-invariant counter-examples, Safety-Notes-First, Read-Only Delta Frame) is preserved verbatim — these tools layer on top to convert *insight* into *empirical proof*.

---

## Operating without helper skills

If `/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/beads-workflow`, `/idea-wizard`, `/cass`, or `/deadlock-finder-and-fixer` aren't available, fallbacks:

- `/codebase-archaeology` → use the exact prompt in [AGENT-PROMPTS.md §Phase 1](AGENT-PROMPTS.md). It works without the skill installed.
- `/codebase-report` → produce a markdown summary from the exact template in [AGENT-PROMPTS.md §Phase 1 output template](AGENT-PROMPTS.md).
- `/beads-workflow` → invoke `br` directly; the "Plan to Beads Conversion" prompt is reproduced in [AGENT-PROMPTS.md §Phase 9](AGENT-PROMPTS.md).
- `/idea-wizard` → reproduce the Phase 2 prompt verbatim — see [AGENT-PROMPTS.md §Phase 6](AGENT-PROMPTS.md).
- `/cass` → skip Cross-Machine Search; rely on local exemplar reads.
- `/deadlock-finder-and-fixer` → use the loom + shuttle + TSan stack directly.

The pipeline does not block on a missing helper skill.
