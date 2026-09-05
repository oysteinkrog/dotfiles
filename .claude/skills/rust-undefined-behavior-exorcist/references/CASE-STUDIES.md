# Case Studies — Detailed Worked Audits

These are written-up audits from the `/dp/*` exemplar projects. Each case study walks through what the skill *would* find on this project, with real anchors. They're longer than [COOKBOOK.md](COOKBOOK.md)'s walkthroughs — meant for studying the methodology in depth, not for first-time invocation.

---

## Case Study 1: frankensqlite mmap-SHM (UB-grade)

**Project:** frankensqlite — Rust port of SQLite, ~50 crates, FFI-heavy + storage engine
**Archetype:** P3 workspace + P7 FFI + P10 storage
**Mode:** Standard with selective Phase 11 soak
**Total wall time:** ~14 hours

### The starting situation

The project ships `crates/fsqlite-vfs/src/shm.rs` which implements SQLite's shared-memory layer. The SHM layer:
- Mmap-maps a `*.shm` file
- Implements POSIX fcntl locking on the mmap pointer
- Performs atomic load/store via raw `*mut u64` casts at offsets
- Has `unsafe impl Send`/`Sync` on `MmapBacking`

The previous version used in-process locks (just `Mutex<HashMap<...>>`); the rewrite is the actual SQLite multi-process model.

### What Phase 1 surfaced

`phase1_unsafe_surface_inventory.md` for the vfs section:

```markdown
| F-ID | file:line | kind | bucket(s) | SAFETY status |
|---|---|---|---|---|
| F-001 | shm.rs:46  | Drop impl with libc::munmap     | refcount, FFI       | PRESENT_STRONG |
| F-002 | shm.rs:59  | unsafe impl Send for MmapBacking | send-sync          | PRESENT_STRONG |
| F-003 | shm.rs:60  | unsafe impl Sync for MmapBacking | send-sync          | PRESENT_STRONG |
| F-007 | shm.rs:397 | atomic_u64_at(m.ptr, offset)    | alignment, FFI      | PRESENT_STRONG |
| F-008 | shm.rs:430 | similar pattern, .load(Acquire) | alignment           | PRESENT_STRONG |
| F-009 | shm.rs:475 | similar, .store(Release)        | alignment           | PRESENT_STRONG |
| F-010 | shm.rs:540 | similar, .swap                  | alignment           | PRESENT_STRONG |
| F-011 | shm.rs:651 | atomic_u64_at helper definition | alignment, FFI      | PRESENT_STRONG |
```

The Q-201 SAFETY comment is high quality — 4-line multi-part contract citing MAP_SHARED + fcntl + memory barriers + the only public deref path.

### What Phase 2 surfaced

The alignment bucket sweeper looked at every `atomic_u64_at` call and asked: where is the alignment enforced?

The caller checks `offset % 8 == 0` and `ptr.addr() % PAGE_SIZE == 0` (page-aligned mmap). The math says page-aligned + offset%8 = aligned for u64. So *if* the caller's checks hold, the unsafe block is sound.

But the sweeper found one call site (in `wal_index.rs`) that computed `offset = base_offset + dynamic_index * 8` where `dynamic_index` came from user-input. If `dynamic_index` is `usize::MAX / 8`, the multiplication overflows, and `offset` wraps to a small value — still divisible by 8, but the pointer arithmetic `ptr.add(offset)` then escapes the mapped region.

Bucket: aliasing/provenance + alignment. Severity: LIKELY-UB.

### What Phase 3 surfaced

```text
$ MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri test wal_index_overflow
error: Undefined Behavior: trying to retag from <2317> ... outside the allocation
```

Confirmed UB. The dynamic_index overflow lets the offset escape the mapped region, then `ptr.add` constructs an out-of-bounds pointer.

### Phase 4 + 5 EXP design

`EXP-007` reproducer (verbatim from the audit):

```rust
// experiments/EXP-007/repro.rs
use std::sync::atomic::{AtomicU64, Ordering};

fn main() {
    let buf = vec![0u8; 4096];  // 1 page
    let base = buf.as_ptr();
    let dynamic_index: usize = usize::MAX / 8;
    let offset = dynamic_index.wrapping_mul(8);  // wraps to small
    // This is the original code (lightly simplified):
    let p = unsafe { base.add(offset).cast::<AtomicU64>() };
    let _ = unsafe { (*p).load(Ordering::SeqCst) };  // ← UB
}
```

Verdict: **CONFIRMED_UB**.

### Phase 6 idea-wizard

Project-narrowed wizard surfaced: "What if `wal_index_capacity()` underestimates the mapped region's size, and a valid-looking offset escapes the mmap?". This became EXP-008 — confirmed via Miri.

### Phase 8 remediation

Three candidates:

**A. Defensive `wal_index_check_offset(offset, len)`** — return `Err(Corrupt)` if offset > len.
- Correctness: 4
- Perf delta: 4 (one branch)
- Diff radius: 2 (touches every call site)
- Reviewability: 4 (mechanical)
- Maintainability: 3 (have to remember to call)

**B. `AtomicU64::from_ptr` (Rust 1.84+)** — moves alignment + dereferenceability check into std.
- Correctness: 4
- Perf delta: 4 (one zero-cost wrap)
- Diff radius: 3 (just the helper)
- Reviewability: 4 (std-validated)
- Maintainability: 4 (no project-specific code)

**C. Replace mmap-backed atomics with in-Rust `Arc<[AtomicU64; N]>`** — abandons multi-process.
- Correctness: 4
- Perf delta: 0 (loses cross-process; SQLite WAL requires this)
- Diff radius: 0 (whole-module rewrite)
- Reviewability: 2 (semantic change)
- Maintainability: 4 (no unsafe)

**Pick: B.** Runners-up A (recorded as the immediate band-aid), C (recorded as "would require deprecating cross-process WAL").

### Phase 9 beads

```
br-101 [remediation] Switch atomic_u64_at to AtomicU64::from_ptr
  br-102 [test] EXP-007 regression test under Miri strict-provenance
  br-103 [docs] Update SAFETY comment to reference Rust 1.84 stdlib check
  br-104 [docs] Bump MSRV to 1.84
  br-105 [bench] Verify no perf regression on the WAL hot path
```

### Phase 11 soak

24-hour fuzz of the WAL multi-process scenario via `rch` → zero new crashes. Multi-day Miri of the full test suite under tree-borrows + strict-provenance → clean.

### Phase 12 final

The `FINAL_UB_REPORT.md` documents 47 findings (39 CONFIRMED_UB, 6 NO_EVIDENCE, 2 DEFERRED — the deferred are around `MAP_FIXED` semantics that we couldn't fully reproduce). `UB_RUNBOOK.md` mandates the MIRIFLAGS matrix in CI + a 24-hour fuzz of the VFS layer monthly.

### Lessons

- **Multi-part SAFETY contracts (Q-201) catch real bugs.** The original contract said "offset bounds/alignment were validated above". Phase 2 just had to ask: are they? The answer was "not for all call sites".
- **Project-shaped wizard (Phase 6) was high-leverage.** EXP-008 wouldn't have surfaced from off-the-shelf checklists.
- **`AtomicU64::from_ptr` is a Rust 1.84+ stdlib bonus** — Rust evolving made the remediation cleaner than it would have been at audit start.

---

## Case Study 2: asupersync Arc<File> Race (TSan-grade)

**Project:** asupersync — async runtime + filesystem I/O
**Archetype:** P6 async runtime + P12 net service
**Mode:** Standard
**Total wall time:** ~6 hours

### The starting situation

`src/fs/file.rs` exposed `Arc<File>` for cheap sharing. `File::read(&self, ...)`, `File::write(&self, ...)`, `File::seek(&self, ...)` all took `&self`. The implementation reached into a `seek_pos` field via `Arc::as_ptr().cast_mut()` to mutate.

### What Phase 1 surfaced

Phase 1 RECON tagged this as `★ SUSPECT`. The SAFETY comment was empty; F-ID assigned.

### What Phase 2 surfaced

The data-races bucket sweeper flagged it immediately: "`unsafe impl Send + Sync` on a struct that has interior mutability without synchronization is always UB if any access is concurrent".

### What Phase 3 surfaced

TSan with `--test-threads=1` reported the race:

```
WARNING: ThreadSanitizer: data race
  Write of size 8 at 0x... by thread T1:
    #0 File::seek ... src/fs/file.rs:127
  Previous read of size 8 at 0x... by thread T2:
    #0 File::read ... src/fs/file.rs:103
```

Loom modeling confirmed: any interleaving where two tasks concurrently call `seek` and `read` on the same `Arc<File>` violates the seek-then-read invariant.

### Phase 8 remediation

Candidates:
- A. Wrap `File` in `Arc<Mutex<File>>` — straightforward, ~5% perf cost
- B. Use per-task local `seek` state (no shared seek_pos) — requires API redesign
- C. Use `pread`/`pwrite` system calls (no seek state at all) — file-system-level fix

**Pick: A.** B and C documented as future improvements requiring API redesign.

### Phase 11 soak

10-hour stateful fuzz of `Arc<Mutex<File>>` operations → clean.

### Lessons

- **TSan + `--test-threads=1`** is the only reliable concurrent-UB oracle for async runtimes
- **Race conditions can be in 100% safe-looking Rust** — `Arc<File>` looks innocuous; the race lives in the manual `cast_mut`
- The Phase 8 rubric correctly prioritized correctness over the perf delta — the perf cost is real but the soundness is non-negotiable

---

## Case Study 3: beads_rust Hash+Eq Inconsistency (correctness invariant)

**Project:** beads_rust — `#![forbid(unsafe_code)]` across all crates
**Archetype:** P1 library, pure-safe
**Mode:** Quick (Phases 1-4 only initially, then escalated to Standard when the finding surfaced)
**Total wall time:** ~3 hours

### The starting situation

The project derived `Hash` on a `BeadId` struct but had a manual `PartialEq` impl that compared only `bead_id.id`, not `bead_id.prefix`. Two `BeadId`s with same id but different prefix were equal-but-not-equally-hashed.

### What surfaced

Phase 2 library-trait bucket sweeper flagged immediately: "Manual `Hash` without `derive(Hash)` is an audit target".

Property test:
```rust
proptest! {
    #[test]
    fn hash_eq_consistency(a: BeadId, b: BeadId) {
        if a == b {
            let mut h_a = DefaultHasher::new(); a.hash(&mut h_a);
            let mut h_b = DefaultHasher::new(); b.hash(&mut h_b);
            prop_assert_eq!(h_a.finish(), h_b.finish());
        }
    }
}
```

Failed in <100 cases.

### Phase 3 dynamic

No Miri UB signal is expected from this safe-code invariant by itself. The confirmed signal is the property-test counterexample; any UB escalation requires a separate unsafe-boundary finding that depends on the broken lookup semantics.

### Phase 8 remediation

Trivial: switch to `derive(Hash, Eq, PartialEq)`. Phase 9 bead included the proptest as a regression test.

### Lessons

- **Pure-safe crates can still hide serious invariant bugs.** The `#![forbid(unsafe_code)]` was true; this finding was correctness-grade unless an unsafe boundary depended on the map invariant.
- **Bucket #12 (library-trait invariants) deserves a dedicated sweeper** even on safe codebases.

---

## Case Study 4: frankenlibc TLS Storage (Aliasing-grade)

**Project:** frankenlibc — libc reimplementation in Rust
**Archetype:** P4 embedded no_std + P7 FFI heavy
**Mode:** Exhaustive
**Total wall time:** ~3 days (Phase 11 soak is the bulk)

### The starting situation

`crates/frankenlibc-core/src/pthread/tls.rs` implements pthread thread-local storage. `pthread_setspecific` writes a `*mut c_void` to TLS; `pthread_getspecific` reads it. The implementation:
- Has a global `Arc<Mutex<Vec<*mut c_void>>>` for the TLS table
- `unsafe impl Send + Sync` on the table (because raw pointers don't auto-impl)
- Each entry's pointer can be touched from any thread (via `pthread_setspecific` from outside)

### What Phase 2 surfaced

Multiple findings:
- F-101: `unsafe impl Send + Sync` on `Vec<*mut c_void>` with no synchronization story beyond the Mutex
- F-102: The C destructor callbacks (registered via `pthread_key_create`) can fire from any thread; if Rust holds `&mut entry` while another thread fires the destructor → race
- F-103: Allocator pairing — entries are allocated via Rust's allocator but the C caller may free them with `libc::free`

### Phase 3 dynamic

TSan (with the test suite hitting pthread_setspecific from multiple threads) reported the race in <60s.

### Phase 8 remediation

This was the toughest. Candidates:
- A. Wrap each entry in `Arc<AtomicPtr<c_void>>` — atomic load/store, no mutex
- B. Per-thread TLS table (thread_local!) — no sharing, no race
- C. Keep the design + add fine-grained per-entry locks

**Pick: B**, with A as fallback for the case where the C caller's expected API demands cross-thread access (some pthread APIs do).

### Phase 11 soak (multi-day)

24h fuzz of pthread_setspecific/getspecific/destruction cycles. Then 48h Miri tree-borrows on the full pthread test suite. Both clean after the remediation.

### Lessons

- **frankenlibc is the worst-case archetype** for UB exorcism — every function is an `unsafe extern "C"` and the contracts are tight against the C standard.
- **`thread_local!`** moves UB into the type system and the stdlib — almost always the right answer for TLS-shaped data.
- **Exhaustive mode is justified** for libc reimplementations because they're the foundation everything else stands on.

---

## Common cross-case patterns

Across all four case studies:

1. **Phase 1 SAFETY-comment quality predicts findings.** The frankensqlite case had strong comments and surface-level audit was fast; beads_rust had no unsafe at all but had a Hash+Eq lie; frankenlibc had hundreds of unsafe sites and dozens of findings.
2. **Phase 6 idea-wizard pays off when the codebase is project-shaped.** frankensqlite's EXP-008 (the wal_index overflow) came from the wizard; off-the-shelf checklists would have missed it.
3. **TSan + loom + Miri-matrix together** catch what no single tool catches. The asupersync race was TSan-detected; the frankenlibc race was loom-confirmed; the frankensqlite alignment issue was Miri-detected.
4. **Phase 11 soak is non-negotiable for OSS releases.** All four projects have Phase 11 runs gated before releases.
5. **Remediation runners-up matter.** In all four cases, the runners-up provided context for future maintainers — the asupersync `pread`/`pwrite` candidate is a 1-2 year future improvement; the frankensqlite "deprecate cross-process WAL" candidate is the eventual major-version cleanup.
