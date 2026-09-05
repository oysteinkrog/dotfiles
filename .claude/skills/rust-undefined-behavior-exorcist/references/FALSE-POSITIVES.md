# False Positives — Tool-Specific Gotchas

Every UB-detection tool produces false positives. Knowing the patterns saves hours of dead-end investigation. This file is the catalog.

For correct positives + the "is this real?" diagnostic flow, see operator [⊙ DEBOUNCE-FALSE-POSITIVE](OPERATOR-LIBRARY.md). For the general anti-patterns see [ANTI-PATTERNS.md](ANTI-PATTERNS.md).

---

## Miri false positives

### M-FP1 — "unsupported operation: can't call foreign function" is not UB

This is Miri saying it can't continue, not that your code is UB. The test is *unverified*, not failed.

**Resolution:** Author a `#[cfg(miri)]` shim (see [MIRI-SHIMS.md](MIRI-SHIMS.md)) or annotate `#[cfg(not(miri))]` on the test if shimming is impractical. Do NOT close as NO_EVIDENCE.

### M-FP2 — Stacked borrows vs Tree borrows disagreement

Stacked borrows and tree borrows are different models. Code that's TB-clean may be SB-violating because SB is an outdated model. Code that's SB-clean may be TB-violating because TB is stricter.

**Resolution:** Trust TB. SB is being deprecated. If only SB flags a finding (clean under TB + strict-provenance + symbolic-alignment), it's likely a false positive — record with rationale and move on.

### M-FP3 — Reborrow chains via `&mut self.field` are TB-strict

Tree borrows can flag a `&mut self.field` reborrow that's standard Rust idiomatic code. Often the actual bug is the type design, not the reborrow.

**Resolution:** Use `addr_of_mut!(self.field)` if the reborrow is causing TB issues but the operation is genuinely sound. Document the SAFETY note.

### M-FP4 — Allocator alignment slacker than declared

Miri's allocator returns max-aligned memory. Your real allocator (especially `mimalloc`, `jemalloc`) may return smaller alignments. A Miri-clean alignment check doesn't prove the real allocator returns aligned memory; you may still need ASan to confirm.

**Resolution:** Layer Miri + ASan; don't rely on Miri alone for alignment audits.

### M-FP5 — Miri's view of `Vec::reserve_exact` overhead

Miri's allocator doesn't compress small allocations; Vec growth strategies sometimes flag as "leak" because Miri reports the over-allocated capacity. Verify by running native + LSan — if LSan is clean, the Miri "leak" is just over-reservation.

**Resolution:** Use `MIRIFLAGS="-Zmiri-ignore-leaks"` for tests that legitimately leak Vec capacity by design.

### M-FP6 — `OnceCell` / `LazyLock` first-init paths

Some sync types use unsafe internally that Miri's tree-borrows flags under specific schedules. The std library hardens these against this; flags here are typically std-internal, not your code.

**Resolution:** Filter via `rg 'Undefined Behavior' | rg -v 'std::|alloc::'` to focus on user code.

### M-FP7 — `mem::take` on a Pin field

`mem::take` on `Pin<&mut T>::get_unchecked_mut().field` may flag under TB even when the field is structurally pinned. The fix is to use `pin_project_lite` properly.

**Resolution:** Use pin_project, not raw `Pin::get_unchecked_mut`.

---

## ThreadSanitizer (TSan) false positives

### T-FP1 — std::sync internal traces

TSan sometimes flags `std::sync::Mutex` or `std::sync::Once` internals as racing. These are sound (libstd is audited); TSan's happens-before tracking is imperfect.

**Resolution:** Add to `tsan.supp`:
```
race:std::sync::Once::call_once
race:std::sync::Mutex
race:std::sync::OnceLock
```

### T-FP2 — Signal-handler happens-before

TSan doesn't model signal-handler happens-before precisely. If a signal handler writes a flag and the main thread reads it via `Ordering::SeqCst`, TSan may flag it.

**Resolution:** Wrap signal-handler-touched state in `core::sync::atomic::AtomicBool` and only access via atomics. If still flagged, suppress.

### T-FP3 — fork() child-process traces

A child process inherits the parent's memory; TSan in the child reports races on memory the parent wrote pre-fork. This is *not* a race — fork synchronizes.

**Resolution:** Don't TSan child processes. Add `__tsan_disable()` in the child immediately after fork.

### T-FP4 — Concurrent reads of constants

Some compilers + tsan combinations flag concurrent reads of `static` data. Constants are read-only; this is a false positive.

**Resolution:** `__attribute__((no_sanitize("thread")))` on the access function (Rust: `#[no_sanitize(thread)]`).

---

## AddressSanitizer (ASan) false positives

### A-FP1 — `mimalloc` / `jemalloc` interactions

ASan instruments std's allocator. If you `#[global_allocator]` to `mimalloc`/`jemalloc`, ASan may report inconsistencies in the early-startup path.

**Resolution:** Use std allocator under ASan: `#[cfg(not(sanitize = "address"))] #[global_allocator] static GLOBAL: MiMalloc = MiMalloc;`

### A-FP2 — Stack-use-after-return on async futures

ASan may flag stack-use-after-return on tokio runtime stacks because tokio reuses thread stacks. The data is logically dead by the time it's "used"; ASan sees the address pattern only.

**Resolution:** `ASAN_OPTIONS="detect_stack_use_after_return=0"` for async-runtime tests.

---

## MemorySanitizer (MSan) false positives

### MS-FP1 — std rebuilt with sanitizer is std

MSan requires `-Z build-std`. The rebuilt std may differ subtly from the prebuilt; some MSan flags are about std's uninit handling, not your code.

**Resolution:** Whitelist `std::` traces; focus on your crate's reports.

### MS-FP2 — `MaybeUninit::uninit().assume_init_ref()` shadows

`assume_init_ref` on a partially-init MaybeUninit may flag — but if only the relevant fields are read, the partial init is OK in Rust's model.

**Resolution:** Use `MaybeUninit::write` per-element + `Vec::spare_capacity_mut` + `set_len` (stable) instead of `assume_init_ref` on the whole slice. `MaybeUninit::slice_assume_init_ref` is also available under nightly `feature(maybe_uninit_slice)`. The MSan flag often points at a real refactor opportunity.

---

## Loom false positives

### L-FP1 — Test depends on system time

Loom is deterministic; system-time-dependent tests are non-deterministic *to loom*.

**Resolution:** Don't use system time in loom tests. Use `loom::lazy_static!` for any "first run" state.

### L-FP2 — Loom assertion fires only on rare schedule

Not a false positive — that's the point of loom. The "rare schedule" is the actual bug. Read the schedule trace.

---

## Shuttle false positives

### SH-FP1 — Replay seed doesn't reproduce

If shuttle finds a failure but the replay seed doesn't reproduce, the model is non-deterministic.

**Resolution:** Audit the model for system time / system RNG / external state. Fix; re-run.

---

## Clippy false positives (UB-related lints)

### C-FP1 — `clippy::cast_ptr_alignment` on `bytemuck::cast`

`bytemuck` macros compile-time-verify alignment via `Pod` traits. Clippy doesn't see the proof.

**Resolution:** `#[allow(clippy::cast_ptr_alignment)]` on the bytemuck call site with a comment citing the Pod derive.

### C-FP2 — `clippy::undocumented_unsafe_blocks` inside macros

Macro-generated unsafe doesn't have a // SAFETY: comment because the user doesn't write the unsafe; the macro does. Clippy flags this anyway.

**Resolution:** Document SAFETY *on the macro definition*. Annotate the macro's unsafe block with `// SAFETY: see <macro_name>! docs in src/macros.rs`.

### C-FP3 — `clippy::transmute_int_to_char` on a value that *is* a valid char

Clippy doesn't know whether your u32 is a valid Unicode scalar. If you've already validated, suppress with rationale:

```rust
debug_assert!(char::from_u32(n).is_some());
// SAFETY: validated by debug_assert above; n came from VALID_CHARS
let c = unsafe { std::mem::transmute::<u32, char>(n) };
```

(Better: just use `char::from_u32(n).unwrap_unchecked()` after `assume(char::from_u32(n).is_some())`.)

---

## Fuzz harness false positives

### F-FP1 — Crash file isn't reproducible

libfuzzer's crash files capture the byte stream that crashed *under that fuzzer version*. Newer/older fuzz versions may not reproduce.

**Resolution:** Pin the fuzz tool version; export the crash to a `#[test]` reproducer so it lives independently of fuzz infra.

### F-FP2 — Timeout warning isn't a UB finding

`WARNING: timeout` from libfuzzer means the target took too long on that input; not UB.

**Resolution:** Cap input size in the target; investigate only if "timeout" correlates with a known infinite-loop pattern.

---

## ast-grep / syn-walker false positives

### AS-FP1 — Pattern matches in test code

Tests intentionally exercise unsafe patterns. ast-grep can't distinguish "test code" from "production code" by pattern alone.

**Resolution:** Filter via `rg -v '^[A-Z]:.*tests?/'` or run ast-grep against `src/` only.

### AS-FP2 — Pattern matches generated code

`build.rs` outputs may contain patterns ast-grep flags. Don't run ast-grep against `target/` or `OUT_DIR`.

**Resolution:** Limit ast-grep scope to `src/` and `crates/*/src/`.

---

## semgrep false positives

### SG-FP1 — Cross-function pattern requires --jobs=1

Multi-file dataflow rules in semgrep can race if `--jobs > 1`. Findings may appear or disappear non-deterministically.

**Resolution:** Use `--jobs=1` for soundness audits; the rules run serially.

---

## Common patterns across all tools

### General — "Found 1 issue" with no diagnostic line

The tool ran, exited non-zero, but the output is empty. This means the tool itself crashed.

**Resolution:** Run with `RUST_BACKTRACE=1` and a `--verbose` flag. If the tool segfaults, file a bug upstream; treat the run as `NEEDS_REFINEMENT`.

### General — Tool version drift

A finding produced by one version of Miri/TSan/etc. may not reproduce under another version. The catalog values can change between releases.

**Resolution:** Pin tool versions in the audit's `phase0_toolchain_inventory.json`. Re-pin only when the diff is well-understood.

---

## How to triage a suspected false positive

Apply operator `⊙ DEBOUNCE-FALSE-POSITIVE` (see [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md#-debounce-false-positive--confirm-no_evidence-stays-no_evidence) — the slug starts with a leading `-` because GitHub strips the `⊙` symbol from anchors):

1. Re-run in a fresh workspace.
2. Re-run with the *complete* matrix (all four MIRIFLAGS, every applicable sanitizer).
3. Add an *inverted assertion*: assert the UB *did* happen — does the test fail clean? If yes, the test is sensitive enough; the original NO_EVIDENCE is robust.
4. Cross-check against the catalog above: does this match a known false-positive pattern?
5. If still uncertain, escalate via operator `⚠ ESCALATE` to `/multi-model-triangulation`.

If the finding clearly matches a known false-positive pattern, close as NO_EVIDENCE with the rationale citing the FP-XX ID. Record in `phase5_experiment_results/EXP-NNN.log` so future maintainers see the precedent.
