# 35-ATOMICS-AND-ORDERINGS.md — Memory Ordering Audit

Atomic operations carry an `Ordering` argument that the language uses to decide what synchronizes with what. Wrong orderings produce bugs that are subtle, intermittent, and architecture-specific (x86_64 is forgiving; aarch64 / weak-memory architectures expose them ruthlessly).

The audit's job for any atomic-touching code:

1. Name the **happens-before relationships** the code requires.
2. Verify each Ordering choice is the WEAKEST that produces those relationships.
3. Cross-architecture verify under loom + x86_64 + aarch64.

---

## The 5 orderings, in audit terms

| Ordering | Read meaning | Write meaning | Audit position |
|----------|-------------|---------------|----------------|
| `Relaxed` | Atomic read; no sync with other locations | Atomic write; no sync | Acceptable for counters, flags that don't gate other state |
| `Acquire` | Read; previous ops before THE NEXT Release write are visible | invalid for stores | Use for read-of-flag-then-read-state |
| `Release` | invalid for loads | Write; subsequent ops AFTER the next Acquire read see prior writes | Use for write-state-then-write-flag |
| `AcqRel` | Both Acquire on read + Release on write (for RMW only) | (same) | Standard for CAS loops |
| `SeqCst` | Single global ordering across all SeqCst ops | (same) | Default IF you're not sure; weaken only with proof |

Weakening from `SeqCst` to `AcqRel` / `Acquire` / `Release` is a (B)-style optimization: profile + loom-model the alternative before committing.

---

## Per-pattern audit rules

### Pattern A — counter/flag (Relaxed)

```rust
// Counter that nothing else reads-then-acts-on:
COUNT.fetch_add(1, Ordering::Relaxed);  // OK — no synchronization needed
```

**Audit position.** (B) or (C) depending on whether `Relaxed` is correct. Most "just count requests" uses are correct under Relaxed.

**Watch for.** Code that reads the counter and ACTS on the value — like a watchdog that triggers when the count reaches a threshold. If acting on the value requires seeing OTHER state that was written before the increment, Relaxed is wrong; needs Acquire.

### Pattern B — once-init flag

```rust
// Writer
unsafe { STATIC.as_mut_ptr().write(value); }
INITIALIZED.store(true, Ordering::Release);

// Reader
if INITIALIZED.load(Ordering::Acquire) {
    let v = unsafe { STATIC.as_ptr().read() };  // OK; Acquire-Release sync
}
```

**Audit position.** (A) for the unsafe writes (the global is mutable static); the Acquire/Release pair is correct.

**Watch for.**
- Writer using `Relaxed` on the flag store → race; reader can see flag=true with stale state.
- Reader using `Relaxed` on the flag load → race; same.
- Using `SeqCst` everywhere → works but over-synchronizes; on aarch64, perf cliff.

### Pattern C — CAS loop (AcqRel)

```rust
loop {
    let cur = atomic.load(Ordering::Acquire);
    let new = compute(cur);
    match atomic.compare_exchange_weak(
        cur, new,
        Ordering::AcqRel,    // success ordering
        Ordering::Acquire,   // failure ordering
    ) {
        Ok(_) => break,
        Err(_) => continue,
    }
}
```

**Audit position.** (B) — performance-driven; the alternative is taking a mutex.

**Watch for.**
- Success ordering `Release` instead of `AcqRel` → write is visible to next Acquire, but the loaded `cur` value's history isn't synchronized. Subtle bug.
- Failure ordering stronger than success → unusual; usually wrong.
- ABA risk: the value loaded is the value stored, but the in-between history differs. Use `compare_exchange` with monotonic counter or tagged pointers.

### Pattern D — fence (Acquire / Release / SeqCst)

```rust
let v = unsafe { ptr.read() };
core::sync::atomic::fence(Ordering::Acquire);  // synchronize with a writer's Release
process(v);
```

**Audit position.** (A) — fences are language-level synchronization primitives.

**Watch for.** Fences without a matching Release on the writer side → no sync; ineffective.

### Pattern E — SeqCst as default

```rust
COUNTER.fetch_add(1, Ordering::SeqCst);
```

**Audit position.** (B) — perf-only weakening to Relaxed if no sync needed, or Acquire/Release pair if specific sync is needed.

**Watch for.** Code that defaults to `SeqCst` because the author wasn't sure. Document the actual sync requirements and weaken if appropriate.

---

## loom model templates

For every atomic-touching (C) rewrite, a loom model:

```rust
#[cfg(loom)]
#[test]
fn loom_acquire_release_pair() {
    loom::model(|| {
        use loom::sync::Arc;
        use loom::sync::atomic::{AtomicBool, Ordering};
        let init = Arc::new(AtomicBool::new(false));
        let state = Arc::new(loom::cell::UnsafeCell::new(0u32));

        let init2 = init.clone();
        let state2 = state.clone();
        let writer = loom::thread::spawn(move || {
            unsafe { *state2.with_mut(|p| &mut *p) = 42; }
            init2.store(true, Ordering::Release);
        });

        if init.load(Ordering::Acquire) {
            let v = unsafe { *state.with(|p| &*p) };
            assert_eq!(v, 42);
        }
        writer.join().unwrap();
    });
}
```

Run with `RUSTFLAGS="--cfg loom" cargo test --features loom_concurrency_tests --release`.

---

## Cross-architecture verification

Some ordering bugs are invisible on x86_64 (which has Strong Memory Model — most ops are de facto Acquire-Release). To catch them:

- Run tests on aarch64 (qemu, GitHub Actions `ubuntu-latest-arm64`, or `macos-14` for Apple silicon).
- Use ThreadSanitizer (tsan) on debug builds: `RUSTFLAGS="-Z sanitizer=thread" cargo test`.
- Use loom — its model is architecture-agnostic and catches race bugs x86_64 hides.

---

## Common bugs

- **Releasing a flag without Releasing the state it gates.** `state = X; flag.store(true, Release)` — only the flag is Release; the state write was Relaxed. Reader sees `flag=true` with stale state.
- **AcqRel CAS where Release suffices.** `compare_exchange` with success=AcqRel when no read-of-state happens after — Acquire is wasted; weaken to Release.
- **SeqCst on a flag that doesn't need it.** Reasonable default but over-synchronizes; profile to determine.
- **Mixing orderings across writes to the same atomic.** `x.store(1, Relaxed); ... x.store(2, Release)` — the Release ordering only synchronizes with the SECOND write, not the first. Almost always a bug.
- **Using `compare_exchange` (strong) in a tight loop.** `compare_exchange_weak` is intended for retry loops; it's allowed to spuriously fail but has better perf. The non-weak version is a typo waiting to happen.

---

## Exemplar precedents

- `/dp/franken_engine/src/sched/worker_park.rs` — uses `core::intrinsics::atomic_load_unsynchronized` for the lock-free worker-parking protocol. (A); loom model proves the protocol; SAFETY comment names the unsync invariant.
- `/dp/franken_engine/src/config.rs` — `arc-swap::ArcSwap<Config>` for hot-reload. (C); previous hand-rolled `AtomicPtr<Config>` + `Arc::into_raw` round-trip eliminated.
- `/dp/asupersync/src/io/ring.rs` — io_uring SQE/CQE pointer updates synchronized via `core::sync::atomic::fence` with kernel-side updates. (A); the fence + the kernel ABI is the soundness contract.

---

## Acceptance signal

An atomic site passes when:

1. **Happens-before relationships are named** in the SAFETY comment.
2. **Each Ordering is justified** — either "weakest correct" (with proof) or "SeqCst conservative default" (with acknowledgement).
3. **A loom model exists** for the protocol.
4. **Tests run on at least one weak-memory architecture** (aarch64) — or the limitation is documented.
5. **No "let me use SeqCst because I'm not sure"** without a follow-up bead to refine.
