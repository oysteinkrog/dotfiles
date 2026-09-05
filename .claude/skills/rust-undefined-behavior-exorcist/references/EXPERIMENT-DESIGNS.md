# Experiment Designs — Template + Per-Bucket Exemplars

`UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` is the registry. Every hypothesis lives there until it has a verdict. This file is the template + worked examples per UB-taxonomy bucket.

---

## Standalone-Cargo-Project Harness (RECOMMENDED DEFAULT)

The recommended way to execute a Phase-5 experiment is to author a **dedicated cargo project** under `<workspace>/exp-harness-<EXP_ID>/` that path-depends on the audit target, contains the reproducer as `src/main.rs` (or as inline tests in `src/lib.rs`), and is `cargo run --release`'d. This pattern:

- **Avoids the `cargo test --test <name>` gotcha.** Cargo's auto-discovery picks up `tests/*.rs` for unqualified `cargo test`, but **NOT** for `cargo test --test <name>` unless the test is explicitly declared in `[[test]]`. Many projects don't bother with explicit `[[test]]` entries, so any experiment invocation that uses `cargo test --test <name>` against the target project fails with `error: no test target named <X>`.
- **Avoids touching the project's `tests/` tree.** No new files in the source repo (which AGENTS.md rule #1 in many projects strictly polices) and no need to ask the user before adding a temp test file.
- **Compiles cleanly against the target's `default-features = false`.** Test-only deps (chrono, serde_json, etc.) live in the harness Cargo.toml, not in the target's.
- **Re-runnable after a fix lands.** Once the audit completes, the harness can be left in place (or under `<workspace>/exp-harness/` if multi-EXP) so future maintainers can re-execute the reproducer to confirm the fix holds. This is what `regression-harness-author` formalizes for the long-lived CI regression test, but the standalone harness is the bootstrap.

### Worked example

For an EXP that depends on the audit target's `model::Status` type:

```
<workspace>/
├── exp-harness-EXP-001/
│   ├── Cargo.toml
│   └── src/
│       └── main.rs
```

`Cargo.toml`:

```toml
[package]
name = "ub-exp-EXP-001"
version = "0.0.0"
edition = "2024"
publish = false

[dependencies]
# Path-depend on the audit target. default-features = false avoids pulling in
# heavy features (e.g., a network client) that aren't needed for the reproducer.
<crate-name> = { path = "../..", default-features = false }
# Test-only dependencies live here, NOT in the target's Cargo.toml.
serde_json = "1.0"
# chrono is optional — add only if the reproducer touches timestamps.

[[bin]]
name = "ub-exp-EXP-001"
path = "src/main.rs"
```

`src/main.rs`:

```rust
//! Reproducer for EXP-001 (see ../UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md).
//!
//! Prints the observed values and exits non-zero (panic) when the hypothesis
//! is CONFIRMED. The Phase-5 experiment-executor captures the exit code and
//! transcribes the verdict back into the registry.

use <crate>::model::Status;

fn main() {
    let upper: Status = serde_json::from_str(r#""SOME_INPUT""#).unwrap();
    let lower: Status = serde_json::from_str(r#""some_input""#).unwrap();
    println!("upper = {:?}", upper);
    println!("lower = {:?}", lower);
    if upper != lower {
        panic!("EXP-001 CONFIRMED: case-different inputs not Eq");
    }
    println!("EXP-001 NO_EVIDENCE: case-different inputs are Eq (hypothesis refuted)");
}
```

Invocation:

```bash
cd <workspace>/exp-harness-EXP-001
RCH_DISABLED=1 cargo +nightly run --release 2>&1 \
  | tee <workspace>/phase5_experiment_results/EXP-001.log
```

Verdict capture (the experiment-executor reads exit code AND `EXP-001 (CONFIRMED|NO_EVIDENCE)` line from the log; edit in place in EXPERIMENT-DESIGNS).

### When to use a different pattern

| Scenario | Pattern |
|----------|---------|
| Reproducer needs MIRIFLAGS to trip Miri | Inline `#[test]` inside the harness (Miri still works against `cargo test`) |
| Reproducer needs cargo-fuzz | Author a `fuzz/fuzz_targets/<EXP_ID>.rs` in the AUDIT TARGET (with user permission), not in the harness — fuzz harnesses need to be near the corpus |
| Reproducer needs `cargo bench` | Author under `<workspace>/exp-bench-<EXP_ID>/` with `[dev-dependencies] criterion = ...` |
| Multi-EXP harness | One project at `<workspace>/exp-harness/` with separate `[[bin]]` per EXP — keeps compile times down |

### Why NOT `cargo test --test <name>` against the audit target

If you try the natural-reading invocation:

```bash
cd "$SOURCE"
cargo test --test exp_001_status_custom_case
```

You typically get:

```
error: no test target named `exp_001_status_custom_case` in default-run packages
```

Cargo only sees test targets declared in `[[test]]` blocks for `--test <name>`. The `tests/*.rs` files an `cargo test` (without filter) picks up via auto-discovery are NOT addressable by `--test <name>`. Working around this requires either (a) editing the audit target's `Cargo.toml` to add `[[test]]` entries (not appropriate for a non-invasive audit), or (b) using a function-name filter `cargo test --release <substring>` (which filters within already-discovered binaries — confusing and fragile). The standalone-harness pattern sidesteps both issues.

---

## Is This Finding Worth A Real Experiment?

When the synthesizer rolls Phase 1/2/3 findings into the experiment registry, every finding needs a decision: **does this warrant an EXP-NNN block, or does it live in the "documented safe-by-construction" appendix instead?** The checklist:

| Finding's shape | Allocate EXP-NNN? |
|-----------------|--------------------|
| HIGH severity with a concrete counter-example already in the Phase 2 evidence (e.g., "Custom('FOO') != Custom('foo') under derived PartialEq") | **YES.** The reproducer is almost free — translate the counter-example into a self-contained binary. |
| HIGH severity but flagged "safe by construction" with explicit rationale (e.g., `process::exit` calls with no RAII guards in scope; `DirGuard` impls in test-only code) | **NO.** Document in `phase4_unified_findings.md` under a "Safe-by-construction" subsection so future audits don't re-investigate. |
| MED severity with a multi-step precondition that Phase 2 verification did NOT satisfy | **YES.** The verification gap is precisely what an experiment closes. |
| MED severity with a multi-step precondition that Phase 2 verification DID satisfy ("we read the code; the invariant holds") | **MAYBE.** Allocate an EXP-NNN only if reproducible (i.e., the experiment would convert a code-reading argument into a tool-arbitrated one). Otherwise note the verification step in `phase4_unified_findings.md`. |
| LOW or INFO severity | **NO** unless it cross-cuts another finding (i.e., the LOW finding is part of a cluster with one HIGH; the cluster gets a shared EXP). |
| NEW_EXP_PROMOTED from Phase 6 idea-wizard | **YES** by definition — that's the verdict's contract. The new EXP gets `EXP-{ROUND}NN` numbering. |
| NEEDS_REFINEMENT verdict on an existing EXP | The follow-up gets `EXP-NNN-a` (then `-b`, ...) with `Follow-up of: EXP-NNN`. |
| Same-shape sibling of an existing EXP (caught by `shape-sweeper`) | `EXP-NNN-a` (etc.) — the sibling reuses the parent's reproducer skeleton with a different file:line input. |
| Architectural acknowledgement ("the design chose tradeoff X; doc-only") | **NO EXP**, but file a doc-only remediation bead in Phase 9 to record the tradeoff explicitly. |

**Heuristic:** if you cannot articulate an Expected Signal field (concrete tool diagnostic), the finding is not yet experiment-ready. Either tighten the hypothesis or recategorize as documented.

---

## Format

```markdown
## EXP-NNN: <descriptive title>

**Finding ref:** F-007 in phase4_unified_findings.md
**Bucket:** Aliasing
**Severity (Phase 2):** MUST-BE-UB
**Hypothesis:** <one sentence; the falsifiable claim>

**Minimal reproducer:** <inline Rust code, ≤30 lines, self-contained>
```rust
// experiments/EXP-NNN/repro.rs
fn main() { … }
```

**Expected signal:**
- Miri: "attempting reborrow from disabled location"
- TSan: "data race on … "
- ASan: "heap-buffer-overflow"
- Loom: assertion failure under schedule …

**Falsifiability:** what evidence would refute the hypothesis. The experiment must be capable of producing both outcomes.

**Invocation (single command):**
```
MIRIFLAGS="-Zmiri-tree-borrows" cargo +nightly miri test --test ub_exp_NNN exp_NNN 2>&1 | tee phase5_experiment_results/EXP-NNN.log
```

**Verdict:** OPEN | CONFIRMED_UB | NO_EVIDENCE | NEEDS_REFINEMENT | DEFERRED

**Notes:**
- (filled by experiment-executor in Phase 5)
- (any newly-spawned hypothesis IDs: EXP-NNN-a, EXP-NNN-b, …)
```

Every field is mandatory. `Verdict` starts at `OPEN`; transitioning out of OPEN requires a corresponding `phase5_experiment_results/EXP-NNN.log` with the raw tool output.

---

## Exemplar 1 — Aliasing (bucket 1)

```markdown
## EXP-001: `*mut Page` deref while a `&Page` to the same slot is live

**Finding ref:** F-001 (src/btree.rs:412)
**Bucket:** Aliasing
**Severity (Phase 2):** LIKELY-UB
**Hypothesis:** `BTreeCursor::split_node` returns a `&Page` that the caller then mutates through `Page::as_mut_ptr()` while the `&Page` is still live; this violates the unique-mutation aliasing model.

**Minimal reproducer:**
```rust
// experiments/EXP-001/repro.rs
//
// Take &Page, cast to *mut, write through it while &Page is still live.
// Reproduces the BTreeCursor::split_node aliasing shape: callers hold a
// shared borrow into the page table; split_node grabs a mutable raw ptr
// and writes; the shared borrow is read again after the write.

struct Page { data: [u8; 4096] }

fn split_node(p: &Page) -> *mut u8 {
    // Derived from a shared reference; writing through this raw pointer
    // while `p` is still live is UB under both stacked and tree borrows.
    p as *const Page as *mut Page as *mut u8
}

fn main() {
    let page = Page { data: [0; 4096] };
    let r: &Page = &page;            // shared borrow remains live below
    let m: *mut u8 = split_node(r);
    unsafe { *m = 1; }               // ← UB: write via *mut while &page live
    let _ = r.data[0];               // observe r AFTER the write → SB/TB error
}
```

**Expected signal:**
- Miri SB: "attempting a write through pointer N0 which is not exposed to this borrow"
- Miri TB: "attempting reborrow from disabled location"

**Falsifiability:** if both SB and TB report clean, the hypothesis is wrong; downgrade and re-check the original code path.

**Invocation:**
```
MIRIFLAGS="-Zmiri-tree-borrows" cargo +nightly miri run --bin exp_001 2>&1 | tee phase5_experiment_results/EXP-001.log
```

**Verdict:** OPEN
```

---

## Exemplar 2 — Provenance (bucket 2)

```markdown
## EXP-002: `(ptr as usize + offset) as *const Header` loses provenance

**Finding ref:** F-014 (src/shm.rs:483)
**Bucket:** Provenance
**Severity (Phase 2):** MUST-BE-UB
**Hypothesis:** The mmap base pointer is converted to `usize` for arithmetic; the resulting pointer has no provenance for the original allocation.

**Minimal reproducer:**
```rust
fn main() {
    let buf: Vec<u8> = vec![0; 64];
    let base = buf.as_ptr() as usize;
    let p = (base + 8) as *const u64;
    let v = unsafe { p.read() };
    println!("{}", v);
}
```

**Expected signal:** `MIRIFLAGS="-Zmiri-strict-provenance"` reports a provenance violation.

**Falsifiability:** If `-Zmiri-strict-provenance` runs clean (no provenance-violation error), the hypothesis is wrong; provenance was preserved by some upstream `ptr.add` or `ptr.with_addr` we missed.

**Invocation:**
```
MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri run --bin exp_002 2>&1 | tee phase5_experiment_results/EXP-002.log
```

**Verdict:** OPEN

**Notes:** if confirmed, the remediation is `ptr.add(offset)` (which preserves provenance) or the `ptr.with_addr(addr)` / `ptr.map_addr(|a| ...)` methods on `*const T` / `*mut T` (stable in 1.84) for explicit operations. See REMEDIATION-PATTERNS.md.
```

---

## Exemplar 3 — Alignment (bucket 3)

```markdown
## EXP-003: `mmap` pointer cast to `&AtomicU64` without alignment guarantee

**Finding ref:** F-021 (src/shm.rs:651)
**Bucket:** Alignment
**Severity (Phase 2):** LIKELY-UB
**Hypothesis:** `atomic_u64_at(ptr, offset)` casts `ptr.add(offset)` to `&AtomicU64`; if `offset % 8 != 0` the deref is UB.

**Minimal reproducer:**
```rust
use std::sync::atomic::{AtomicU64, Ordering};
fn main() {
    let buf: Vec<u8> = vec![0; 64];
    let base = buf.as_ptr();
    let p = unsafe { base.add(3).cast::<AtomicU64>() }; // offset 3 — misaligned
    let _ = unsafe { (*p).load(Ordering::SeqCst) };
}
```

**Expected signal:** `MIRIFLAGS="-Zmiri-symbolic-alignment-check"` reports a misaligned access.

**Falsifiability:** If symbolic-alignment-check runs clean, the hypothesis is wrong; either the offset is always 8-aligned in the call sites we test, or `AtomicU64::from_ptr` catches the alignment violation upstream.

**Invocation:**
```
MIRIFLAGS="-Zmiri-symbolic-alignment-check" cargo +nightly miri run --bin exp_003 2>&1 | tee phase5_experiment_results/EXP-003.log
```

**Verdict:** OPEN
```

---

## Exemplar 4 — Data Race (bucket 7)

```markdown
## EXP-004: `Arc<File>` concurrent read/write race

**Finding ref:** F-031 (src/fs/file.rs:127)
**Bucket:** Data Race
**Severity (Phase 2):** MUST-BE-UB
**Hypothesis:** `Arc<File>` is shared across async tasks; `File::seek` mutates internal state without synchronization; two tasks calling `read` interleave the seek with the read.

**Minimal reproducer:** stateful fuzz target with `Arbitrary` sequence of `{Read(off, len), Write(off, buf), Seek(off)}` operations dispatched across N tasks.

**Expected signal:**
- TSan: "data race on …"
- Loom: assertion failure on read-after-write expected content

**Falsifiability:** If TSan AND loom both report clean across 1000+ stateful-fuzz iterations, the hypothesis is wrong; either `File`'s internal state isn't actually shared-mutable, or the seek/read calls already serialize through a kernel-level lock we missed.

**Invocation:**
```
# TSan (real implementation)
RUSTFLAGS="-Zsanitizer=thread" cargo +nightly test --target x86_64-unknown-linux-gnu \
  --test exp_004_tsan -- --test-threads=1 2>&1 | tee phase5_experiment_results/EXP-004-tsan.log

# Loom (model)
RUSTFLAGS="--cfg loom" cargo +nightly test --release exp_004_loom_model 2>&1 | tee phase5_experiment_results/EXP-004-loom.log
```

**Verdict:** OPEN
```

---

## Exemplar 5 — Send/Sync (bucket 8)

```markdown
## EXP-005: `unsafe impl Sync for MmapBacking` without sufficient synchronization

**Finding ref:** F-040 (src/shm.rs:59)
**Bucket:** Send/Sync invariants
**Severity (Phase 2):** CONTRACTUAL-BUT-DEFENSIBLE
**Hypothesis:** The SAFETY comment claims `MAP_SHARED + fcntl + memory barriers` synchronize. Test whether the *only* public deref path actually holds the mutex.

**Minimal reproducer:** a binary that spins up two threads, each accessing the mmap region through a `&MmapBacking` (not through `ShmRegionGuard`); fuzz with arbitrary access patterns.

**Expected signal:**
- If the SAFETY claim is correct, every deref must go through `ShmRegionGuard` ⇒ direct `&MmapBacking` access shouldn't be reachable from outside the module. Audit the module's public surface for any leak.
- TSan if the test exercises the unsafe path.

**Falsifiability:** If a code-search shows zero `&MmapBacking` derefs outside the `shm` module AND TSan + 10⁴ loom iters both run clean across the multi-thread test, the SAFETY claim holds; close as NO_EVIDENCE.

**Invocation:**
```
# Static audit: every public deref path must go through ShmRegionGuard
ast-grep run -l Rust -p '&$X.ptr' --include 'crates/fsqlite-vfs/**/*.rs' \
  | tee phase5_experiment_results/EXP-005-audit.log
# Dynamic gate
RUSTFLAGS="-Zsanitizer=thread" cargo +nightly test --target x86_64-unknown-linux-gnu \
  --test exp_005_concurrent -- --test-threads=1 2>&1 | tee phase5_experiment_results/EXP-005-tsan.log
```

**Verdict:** OPEN
```

---

## Exemplar 6 — FFI Contract (bucket 10)

```markdown
## EXP-006: `sqlite3_open` Box::from_raw mismatch

**Finding ref:** F-053 (crates/fsqlite-c-api/src/lib.rs:716)
**Bucket:** FFI Contracts + Refcount lifecycle
**Severity (Phase 2):** LIKELY-UB
**Hypothesis:** `sqlite3_close` calls `Box::from_raw(db)` where `db: *mut sqlite3` was previously returned by `sqlite3_open` via `Box::into_raw`. If callers pass anything other than the exact pointer returned by `sqlite3_open`, the `from_raw` is UB.

**Minimal reproducer:**
```rust
extern "C" { fn sqlite3_open(filename: *const i8, ppDb: *mut *mut Db) -> i32;
             fn sqlite3_close(db: *mut Db) -> i32; }
fn main() {
    let mut p: *mut Db = std::ptr::null_mut();
    let _ = unsafe { sqlite3_open(c"x".as_ptr(), &mut p) };
    // pass a fake pointer to sqlite3_close — double-free if the API doesn't guard
    let _ = unsafe { sqlite3_close((p as usize + 8) as *mut Db) };
}
```

**Expected signal:** ASan reports a heap-buffer-overflow or invalid-free.

**Falsifiability:** If ASan runs clean (the C library validates the handle internally before deref), the hypothesis is wrong; document the C library's guard and downgrade severity.

**Invocation:**
```
RUSTFLAGS="-Zsanitizer=address" cargo +nightly run --target x86_64-unknown-linux-gnu --bin exp_006
```

**Verdict:** OPEN
```

---

## Verdict Recording Discipline

`experiment-executor` subagents must record verdicts directly into `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` by *editing the existing block in place* — never appending a duplicate. Use the exact strings:

- `CONFIRMED_UB`
- `NO_EVIDENCE`
- `NEEDS_REFINEMENT`
- `DEFERRED`

`convergence-tracker.sh` greps for these strings to compute round-over-round statistics.

When a `NEEDS_REFINEMENT` verdict spawns a follow-up experiment, the new experiment gets ID `EXP-NNN-a` (then `-b`, `-c`, …) and a `Follow-up of:` field pointing to the parent.

---

---

## Exemplar 7 — Async Drop Hazard (bucket 17)

```markdown
## EXP-007: Drop calls block_on inside tokio runtime

**Finding ref:** F-070 (src/runtime/file_handle.rs:412)
**Bucket:** Async drop hazards
**Severity (Phase 2):** MUST-BE-UB (deadlock-grade)
**Hypothesis:** `FileHandle::drop` calls `tokio::runtime::Handle::current().block_on(self.flush())`; when dropped from within a tokio task, this deadlocks the worker.

**Minimal reproducer:**
```rust
use tokio::runtime::Runtime;
struct Handle;
impl Drop for Handle {
    fn drop(&mut self) {
        let _ = tokio::runtime::Handle::try_current()
            .map(|h| h.block_on(async {}));
    }
}
fn main() {
    Runtime::new().unwrap().block_on(async {
        let _ = Handle;
    });
}
```

**Expected signal:** test times out / deadlocks; tokio worker block detection fires.

**Invocation:**
```
timeout 10 cargo run --release --bin exp_007 2>&1 | tee phase5_experiment_results/EXP-007.log
# Exit code 124 = timeout = deadlock confirmed
```

**Falsifiability:** If the test completes within 5s, the hypothesis is wrong; the runtime handles this case.

**Verdict:** OPEN
```

---

## Exemplar 8 — Hash/Eq Inconsistency (bucket 25)

```markdown
## EXP-008: HashMap logic break from Hash/Eq mismatch

**Finding ref:** F-080 (src/lookup.rs:48)
**Bucket:** Std-library trait invariants + Hash/Eq consistency
**Severity (Phase 2):** CONTRACTUAL-BUT-DEFENSIBLE (logic bug; UB only if unsafe code depends on this invariant)
**Hypothesis:** `MyKey` compares equality by `id` but manually hashes both `id` and `name`; two keys with the same `id` and different `name` are equal but hash differently, breaking HashMap's lookup contract.

**Minimal reproducer:**
```rust
use std::collections::HashMap;
struct MyKey { id: u32, name: String }
impl PartialEq for MyKey {
    fn eq(&self, other: &Self) -> bool { self.id == other.id }
}
impl Eq for MyKey {}
impl std::hash::Hash for MyKey {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        std::hash::Hash::hash(&self.id, state);
        std::hash::Hash::hash(&self.name, state); // BUG: Eq ignores `name`
    }
}
fn main() {
    let mut map = HashMap::new();
    map.insert(MyKey { id: 1, name: "a".into() }, "alpha");
    let lookup = MyKey { id: 1, name: "b".into() };
    // a == lookup is TRUE by Eq, but their hashes differ.
    // HashMap::get can miss a logically equal key; this is not UB by itself.
    println!("{:?}", map.get(&lookup));
}
```

**Expected signal:** proptest fails for `a == b ⟹ hash(a) == hash(b)`; clippy `derive_hash_xor_eq` warning.

**Falsifiability:** If the proptest finds no counterexample after 10⁴+ cases AND clippy is clean, the impls are consistent; close as NO_EVIDENCE.

**Invocation:**
```
cargo clippy -- -W clippy::derive_hash_xor_eq 2>&1 | tee phase5_experiment_results/EXP-008-clippy.log
cargo test --test exp_008_proptest 2>&1 | tee phase5_experiment_results/EXP-008-proptest.log
```

**Verdict:** OPEN
```

---

## Exemplar 9 — Iterator::size_hint Lie (bucket 12)

```markdown
## EXP-009: Manual Iterator::size_hint lower bound trusted by unsafe code

**Finding ref:** F-090 (src/iter.rs:103)
**Bucket:** Std-library trait invariants
**Severity (Phase 2):** LIKELY-UB only for the unsafe collector; ordinary safe `Vec::extend` is not the UB source
**Hypothesis:** `MyIter` returns `size_hint() = (100, None)` but actually yields only 10 items, and project-local unsafe collection code trusts the lower bound as initialized length.

**Minimal reproducer:**
```rust
struct LiarIter { remaining: usize }
impl Iterator for LiarIter {
    type Item = u32;
    fn next(&mut self) -> Option<u32> {
        if self.remaining == 0 { None } else {
            self.remaining -= 1; Some(self.remaining as u32)
        }
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        (100, None) // LIE: actual remaining is `self.remaining`
    }
}
fn main() {
    let v = collect_trusting_hint(LiarIter { remaining: 10 });
    println!("{:?}", &v[..]); // reads 90 uninitialized u32 slots
}
fn collect_trusting_hint<I: Iterator<Item = u32>>(mut it: I) -> Vec<u32> {
    let (low, _) = it.size_hint();
    let mut v = Vec::with_capacity(low);
    let ptr = v.as_mut_ptr();
    let mut written = 0;
    while let Some(x) = it.next() {
        unsafe { ptr.add(written).write(x); }
        written += 1;
    }
    unsafe { v.set_len(low); } // BUG: assumes the lower bound was exact
    v
}
```

**Expected signal:** Miri reports "reading uninitialized memory" when the vector is printed.

**Falsifiability:** If Miri runs clean, either the unsafe collector does not actually trust the lower bound, or the reproducer failed to read the uninitialized tail.

**Invocation:**
```
MIRIFLAGS="" cargo +nightly miri run --bin exp_009 2>&1 | tee phase5_experiment_results/EXP-009.log
```

**Verdict:** OPEN
```

---

## Exemplar 10 — Manual Allocator Mismatched Layout (bucket 20)

```markdown
## EXP-010: Box::from_raw with wrong allocator

**Finding ref:** F-100 (src/ffi.rs:67)
**Bucket:** Dangling Box / allocator pairing
**Severity (Phase 2):** MUST-BE-UB
**Hypothesis:** `Box::from_raw` is called on a pointer obtained from `libc::malloc`; Rust's `Box` allocator (System / GlobalAlloc) doesn't match libc's, so the eventual drop calls the wrong free.

**Minimal reproducer:**
```rust
fn main() {
    unsafe {
        let p = libc::malloc(8) as *mut u64;
        *p = 42;
        let _b: Box<u64> = Box::from_raw(p);
        // _b's Drop calls the global allocator's dealloc; ptr came from libc::malloc
        // → heap corruption.
    }
}
```

**Expected signal:** ASan reports "free called on memory not allocated by this allocator" or heap-buffer-overflow.

**Falsifiability:** If ASan runs clean, the hypothesis is wrong; the global allocator happens to forward to `libc::malloc`/`free` on this platform (e.g., glibc + `#[global_allocator] = System`).

**Invocation:**
```
RUSTFLAGS="-Zsanitizer=address" cargo +nightly run --target x86_64-unknown-linux-gnu --bin exp_010 2>&1 | tee phase5_experiment_results/EXP-010.log
```

**Verdict:** OPEN

**Notes:** Common in FFI bindings — verify every `Box::from_raw` site against the allocator that produced the pointer.
```

---

## Exemplar 11 — Target-Feature Mismatch (bucket 19)

```markdown
## EXP-011: AVX2 intrinsic called on a non-AVX2 CPU path

**Finding ref:** F-110 (src/simd.rs:42)
**Bucket:** Target-feature mismatch
**Severity (Phase 2):** MUST-BE-UB (SIGILL or silent corruption)
**Hypothesis:** `fast_path` is `#[target_feature(enable = "avx2")]` but is called from a `dispatch` fn that doesn't check `is_x86_feature_detected!("avx2")`.

**Minimal reproducer:**
```rust
#[target_feature(enable = "avx2")]
unsafe fn fast(x: &[i32]) -> i32 { x.iter().sum() }
fn dispatch(x: &[i32]) -> i32 {
    // BUG: no runtime detection
    unsafe { fast(x) }
}
fn main() { println!("{}", dispatch(&[1, 2, 3])); }
```

**Expected signal:** clippy flags `target_feature_caller_not_target_feature_callee` (if enabled). At runtime on a non-AVX2 CPU: SIGILL.

**Falsifiability:** If clippy is clean AND running on a non-AVX2 CPU under qemu produces correct output, the hypothesis is wrong; either runtime detection exists upstream of `dispatch`, or the LLVM lowering of `fast` happens to avoid AVX2 for this input shape.

**Invocation:**
```
cargo clippy -- -W clippy::target_feature_caller_not_target_feature_callee 2>&1 | tee phase5_experiment_results/EXP-011.log
```

**Verdict:** OPEN
```

---

## Exemplar 12 — Volatile Misalignment (bucket 16)

```markdown
## EXP-012: read_volatile on misaligned MMIO pointer

**Finding ref:** F-120 (src/mmio.rs:88)
**Bucket:** Volatile contracts + alignment
**Severity (Phase 2):** MUST-BE-UB
**Hypothesis:** `device.read_register::<u32>(offset=3)` calls `read_volatile::<u32>` on a misaligned pointer.

**Minimal reproducer:**
```rust
fn main() {
    let buf = [0u8; 16];
    let base = buf.as_ptr();
    let p = unsafe { base.add(3) as *const u32 }; // offset 3 → misaligned
    let _ = unsafe { p.read_volatile() };          // UB
}
```

**Expected signal:** Miri symbolic-alignment-check reports "misaligned read".

**Falsifiability:** If symbolic-alignment-check is clean, the hypothesis is wrong; the call site always passes a 4-aligned offset (the audit must trace the caller and confirm).

**Invocation:**
```
MIRIFLAGS="-Zmiri-symbolic-alignment-check" cargo +nightly miri run --bin exp_012 2>&1 | tee phase5_experiment_results/EXP-012.log
```

**Verdict:** OPEN
```

---

## Exemplar 13 — `repr(packed)` Field Reference (bucket 22)

```markdown
## EXP-013: Taking &packed.field on non-aligned field

**Finding ref:** F-130 (src/disk_format.rs:201)
**Bucket:** repr(packed) field addr + alignment
**Severity (Phase 2):** MUST-BE-UB
**Hypothesis:** `Header { magic: u32, version: u32, count: u64 }` is `#[repr(packed)]`; `&header.count` creates a misaligned reference (count starts at byte 8 but packed = no padding insertion, so its alignment is 1).

**Minimal reproducer:**
```rust
#[repr(packed)]
struct Header { magic: u32, version: u32, count: u64 }
fn main() {
    let h = Header { magic: 0, version: 0, count: 1 };
    let r: &u64 = &h.count; // ERROR or UB depending on toolchain
    println!("{}", r);
}
```

**Expected signal:** rustc `unaligned_references` warns (now hard-error in stable). Use `addr_of!(h.count)` instead.

**Falsifiability:** If the build succeeds (no `unaligned_references` error), the hypothesis is wrong; either the `repr(packed)` annotation is missing/inherited, or the field happens to fall on a naturally-aligned offset (e.g., `u8` field after a `u32`).

**Invocation:**
```
cargo build 2>&1 | tee phase5_experiment_results/EXP-013.log
# expect: error[E0793]: reference to packed field is unaligned
```

**Verdict:** OPEN
```

---

## Exemplar 14 — Manual Send Lies (bucket 8)

```markdown
## EXP-014: unsafe impl Send for a type containing Rc

**Finding ref:** F-140 (src/shared.rs:55)
**Bucket:** Send/Sync invariants
**Severity (Phase 2):** MUST-BE-UB
**Hypothesis:** `Shared` contains an `Rc<Inner>` but has `unsafe impl Send for Shared`. Moving `Shared` to another thread breaks Rc's non-atomic refcount.

**Minimal reproducer:**
```rust
use std::rc::Rc;
struct Shared { inner: Rc<u32> }
unsafe impl Send for Shared {}  // LIE
fn main() {
    let s = Shared { inner: Rc::new(42) };
    let h = std::thread::spawn(move || println!("{}", s.inner));
    h.join().unwrap();
}
```

**Expected signal:** TSan races on Rc's refcount; Miri reports the unsynchronized access.

**Falsifiability:** If TSan and Miri are both clean across N runs, the hypothesis is wrong; either the Rc is never actually cloned/dropped in the spawned thread, or the test path serializes on a kernel-level synchronization we missed.

**Invocation:**
```
RUSTFLAGS="-Zsanitizer=thread" cargo +nightly run --target x86_64-unknown-linux-gnu --bin exp_014 2>&1 | tee phase5_experiment_results/EXP-014.log
```

**Verdict:** OPEN
```

---

## Exemplar 15 — `Pin::new_unchecked` + `mem::replace` (bucket 9)

```markdown
## EXP-015: mem::replace through a Pin

**Finding ref:** F-150 (src/state_machine.rs:240)
**Bucket:** Pin invariants
**Severity (Phase 2):** MUST-BE-UB
**Hypothesis:** `Pin::new_unchecked(&mut self.state)` is taken, then `mem::replace(&mut self.state, new_state)` moves the value, violating pin.

**Minimal reproducer:**
```rust
use std::pin::Pin;
struct State { addr_dep: *const u8 }
impl Unpin for State {}  // mistakenly marks !Unpin types Unpin (or vice versa)
fn main() {
    let mut s = State { addr_dep: std::ptr::null() };
    let _p: Pin<&mut State> = unsafe { Pin::new_unchecked(&mut s) };
    let _old = std::mem::replace(&mut s, State { addr_dep: std::ptr::null() });
    // _p is now pointing to memory holding `_old`, but we believed it was pinned.
}
```

**Expected signal:** Miri tree-borrows reports the violated reborrow; if `State: !Unpin`, the move triggers UB.

**Falsifiability:** If Miri TB is clean, the hypothesis is wrong; either `State: Unpin` (in which case `mem::replace` after `Pin::new_unchecked` is OK), or the reborrow chain was actually maintained correctly.

**Note:** The reproducer is *illustrative* — the borrow checker will reject having `&mut s` live both through `_p` and the `mem::replace` argument. A live reducer needs `NonNull::from(&mut s).as_mut()` or raw-pointer plumbing; see [BISECTION.md §G2](BISECTION.md) for the harness-authoring approach.

**Invocation:**
```
MIRIFLAGS="-Zmiri-tree-borrows" cargo +nightly miri run --bin exp_015 2>&1 | tee phase5_experiment_results/EXP-015.log
```

**Verdict:** OPEN
```

---

## Anti-Patterns in Experiment Design

| ✗ | Why |
|---|---|
| Reproducer that pulls in the whole crate | Defeats minimization; can't bisect |
| Falsifiability field missing | The "experiment" can only confirm — that's a demo, not a test |
| No tool-output file referenced | The verdict can't be audited |
| Vague "expected signal" | Tomorrow you won't recognize the diagnostic when you see it |
| Combined MIRIFLAGS in a single invocation | Cleaner to run each axis separately so the failing axis is obvious |
