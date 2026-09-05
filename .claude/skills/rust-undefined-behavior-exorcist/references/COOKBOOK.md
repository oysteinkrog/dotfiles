# Cookbook — End-to-End Worked Walkthroughs

Each walkthrough takes a real-shape project and traces every phase. Reproduce by following the commands; outputs match what the orchestrator would produce.

---

## W1: FFI-Heavy Crate Walkthrough

**Project:** `frankensqlite` (Rust port of SQLite; ~50 crates, many `extern "C"`, MMAP-backed shared memory).

### Phase 0 — Bootstrap

```text
$ ./scripts/install-toolchain.sh /data/projects/frankensqlite/.ub-exorcism/2026-05-14-frankensqlite-1
=== Toolchain inventory ===
  [✓] rustup            rustup 1.27.1
  [✓] nightly           rustc 1.87.0-nightly
  [✓] miri              (installed)
  [✓] rust_src          (installed)
  [✓] cargo-fuzz        cargo-fuzz 0.12.0
  [ ] kani              (hint: cargo install --locked kani-verifier)
  ...
Install optional kani via: cargo install --locked kani-verifier ? [y/N] y
```

**Partition** (proposed to user before fan-out):

| Section | Source path | UB priors | Subagent id |
|---|---|---|---|
| vfs    | crates/fsqlite-vfs/src    | mmap, fcntl, alignment, manual Send/Sync | A |
| btree  | crates/fsqlite-btree/src  | raw pointer, repr(C), align | B |
| c-api  | crates/fsqlite-c-api/src  | FFI, repr(C), Box::from_raw | C |
| mvcc   | crates/fsqlite-mvcc/src   | atomics, cache-aligned types, custom Send | D |
| ...    | ... | ... | ... |

### Phase 1 — RECON output (excerpt of `phase1_unsafe_surface_inventory.md`)

```markdown
| F-ID | file:line | kind | bucket(s) | SAFETY |
|---|---|---|---|---|
| F-001 | crates/fsqlite-vfs/src/shm.rs:46 | Drop impl with munmap | refcount, FFI | PRESENT_STRONG |
| F-002 | crates/fsqlite-vfs/src/shm.rs:59 | unsafe impl Send for MmapBacking | send-sync | PRESENT_STRONG |
| F-003 | crates/fsqlite-vfs/src/shm.rs:60 | unsafe impl Sync for MmapBacking | send-sync | PRESENT_STRONG |
| F-007 | crates/fsqlite-vfs/src/shm.rs:397 | atomic_u64_at via raw ptr cast | alignment, provenance | PRESENT_STRONG |
| F-014 | crates/fsqlite-c-api/src/lib.rs:716 | Box::from_raw on FFI ptr | refcount, FFI | MISSING |
| ... |
```

### Phase 2 — STATIC SWEEP

The orchestrator fans out 7 buckets (others marked N/A): aliasing, provenance, alignment, ffi, send-sync, refcount, panic-safety.

The `aliasing` sweeper finds:
```
phase2_findings_aliasing.md:
## F-007 (already in Phase 1) — atomic_u64_at(m.ptr, offset)
**Severity:** LIKELY-UB
**Static evidence:** ast-grep pattern provenance-int-cast matched at shm.rs:651:
    `let p = base.add(offset).cast::<AtomicU64>()`
**Draft experiment:** EXP-007 — minimal repro with offset=3 (misaligned)
```

The `ffi` sweeper finds:
```
## F-014 — sqlite3_close Box::from_raw without SAFETY comment
**Severity:** LIKELY-UB
**Static evidence:** crates/fsqlite-c-api/src/lib.rs:716:
    `let mut handle = Box::from_raw(db);`
  (No preceding // SAFETY: comment; no docs cross-reference to where the
   pointer was constructed.)
**Draft experiment:** EXP-014 — invoke sqlite3_close with a fake pointer;
   expect ASan invalid-free.
```

### Phase 3 — DYNAMIC SWEEP

```text
$ ./scripts/run-miri-matrix.sh /data/projects/frankensqlite /data/projects/frankensqlite/.ub-exorcism/2026-05-14-frankensqlite-1
=== miri/default ===
  [✓] miri/default clean (log: /data/projects/frankensqlite/.ub-exorcism/2026-05-14-frankensqlite-1/phase3_raw/miri_default.log)
=== miri/tree_borrows ===
  [✗] miri/tree_borrows found UB (log: /data/projects/frankensqlite/.ub-exorcism/2026-05-14-frankensqlite-1/phase3_raw/miri_tree_borrows.log)
    error: Undefined Behavior: trying to retag from <2317> for SharedReadWrite
           permission at alloc1023[0x0], but that tag does not exist
           in the borrow stack for this location
=== miri/strict_provenance ===
  [✗] miri/strict_provenance found UB
    error: Undefined Behavior: integer-to-pointer cast preserves no provenance
```

These map to F-007 and F-021 in the unified findings.

### Phase 4 — SYNTHESIS

`phase4_unified_findings.md` consolidates Phase 1+2+3:

```markdown
| F-ID | file:line | bucket | severity | tools | status |
|---|---|---|---|---|---|
| F-007 | shm.rs:397 | alignment, provenance | MUST-BE-UB | static-sweep, miri-tb, miri-sp | OPEN |
| F-014 | c-api/lib.rs:716 | ffi, refcount | LIKELY-UB | static-sweep | OPEN |
| F-021 | mvcc/src/cache_aligned.rs:42 | alignment | LIKELY-UB | miri-sa | OPEN |
| ... |
```

And the v1 experiment registry:

```markdown
## EXP-007: mmap pointer cast to &AtomicU64 without alignment guarantee
**Hypothesis:** atomic_u64_at(ptr, offset) is UB when offset % 8 != 0.
**Reproducer:** 18 lines (see EXPERIMENT-DESIGNS.md exemplar EXP-003)
**Invocation:** MIRIFLAGS="-Zmiri-symbolic-alignment-check" cargo +nightly miri run --bin exp_007
**Verdict:** OPEN

## EXP-014: sqlite3_close with a fake pointer triggers heap corruption
**Hypothesis:** sqlite3_close calls Box::from_raw on an unvetted pointer
**Reproducer:** 22 lines passing an offset pointer; expect ASan invalid-free
**Invocation:** RUSTFLAGS="-Zsanitizer=address" cargo +nightly run --bin exp_014
**Verdict:** OPEN
```

### Phase 5 — EXPERIMENT EXECUTION

Each experiment-executor subagent runs its experiment. EXP-007 confirms UB; EXP-014 reproduces ASan invalid-free.

### Phase 6 — IDEA-WIZARD (project-shaped)

Output: 15 techniques. New ones promoted to experiments:
- "What if SQLite's `journal` mode interacts with our shm fcntl-locking story under crash recovery?" → EXP-031
- "Are page numbers ever computed via `usize` arithmetic that could overflow on 32-bit builds?" → EXP-032
- ...

### Phase 7 — ITERATE

Round 1: 47 OPEN findings. After Phase 5: 32 CONFIRMED_UB, 12 NO_EVIDENCE, 3 NEEDS_REFINEMENT.
Round 2: spawn follow-ups for the 3 NEEDS_REFINEMENT, plus EXP-031/32 from Phase 6.
...
Round 11 (quiet): 0 OPEN, 0 NEEDS_REFINEMENT, 1 new finding.
Round 12 (quiet): 0 OPEN, 0 NEEDS_REFINEMENT, 2 new findings → CONVERGED.

### Phase 8 — REMEDIATION

For F-007 (alignment), Phase 8 enumerates candidates:
- A) Force callers to pass aligned offsets; assert in debug builds.
- B) Replace `&AtomicU64` with `AtomicU64::from_ptr` (stable since 1.84) — still `unsafe`, but the SAFETY contract (alignment, exclusive provenance, lifetime) is documented canonically in `std`.
- C) Replace the mmap-backed atomic with an in-Rust atomic counter, dropping the cross-process sharing requirement.

Rubric:

| Axis | A | B | C |
|---|---|---|---|
| Correctness margin | 3 | 4 | 4 |
| Perf delta | 4 | 4 | 1 (loses cross-process) |
| Diff blast radius | 4 | 3 | 0 |
| Reviewability | 3 | 4 | 2 |
| Maintainability | 3 | 4 | 4 |

**Pick: B**. Runners-up A (recorded), C (recorded as "would require deprecating cross-process mode").

### Phase 9 — BEADS

```
br-101 Remediate F-007 alignment-via-AtomicU64-from_ptr
  br-102 [test] Add Miri symbolic-alignment-check CI step
  br-103 [docs] Update // SAFETY: comment in shm.rs:397
```

### Phase 10 — FRESH EYES

Three rounds; second round produces zero substantive changes.

### Phase 11 — SOAK

A 24h fuzz of the VFS layer dispatched via `rch`. No new crashes. A 48h full-suite Miri matrix on the FFI-shim'd build. Two new NEEDS_REFINEMENT verdicts from the soak loop back into Phase 8.

### Phase 12 — FINAL ARTIFACTS

`FINAL_UB_REPORT.md` ships with: 47 findings (39 CONFIRMED_UB, 6 NO_EVIDENCE, 2 DEFERRED). `UB_RUNBOOK.md` mandates Miri matrix + ASan + 24h fuzz of VFS in CI going forward. The bead graph (50+ beads) is the maintainer's next-month roadmap.

---

## W2: Concurrency-Heavy Crate Walkthrough

**Project:** Async runtime with a custom `RawWaker` vtable + `Arc<File>` sharing pattern.

### Phase 0 — Partition

Sections: `waker/`, `fs/file/`, `sync/parker/`, `runtime/scheduler/`.

### Phase 1 — Inventory

Discovers 215 unsafe sites (matches the actual asupersync count from the agent mining). The `waker/` section has the `RawWaker` vtable pattern (exemplar E4):

```rust
unsafe fn tracked_waker_clone(data: *const ()) -> RawWaker {
    // SAFETY: RawWaker data is always created from Arc<TrackedWaker> in create_waker.
    let arc = unsafe { Arc::from_raw(data as *const TrackedWaker) };
    let cloned = arc.clone();
    std::mem::forget(arc);
    let new_data = Arc::into_raw(cloned) as *const ();
    RawWaker::new(new_data, &TRACKED_WAKER_VTABLE)
}
```

### Phase 2 — buckets

The `data-races` bucket flags `Arc<File>` shared between async tasks with no mutex.
The `refcount` bucket validates the `RawWaker` from_raw/into_raw pairing.
The `send-sync` bucket audits every `unsafe impl Send/Sync`.

### Phase 3 — DYNAMIC SWEEP

**Loom model** for the Parker primitive (20+ cases):

```rust
#[cfg(feature = "loom-tests")]
#[test]
fn loom_parker_no_lost_wakeup() {
    loom::model(|| {
        let parker = LoomParker::new();
        // ... model exhaustively interleaves park/unpark
    });
}
```

**TSan** for `Arc<File>`:

```
RUSTFLAGS="-Zsanitizer=thread" cargo +nightly test --test fs_file_arc -- --test-threads=1
==================
WARNING: ThreadSanitizer: data race
  Write of size 8 at 0x... by thread T1:
    #0 File::seek ... fs/file.rs:127
  Previous read of size 8 at 0x... by thread T2:
    #0 File::read ... fs/file.rs:103
```

This confirms the EXP-031 hypothesis.

### Phase 8 — Remediation

The `Arc<File>` race has candidates:
- A) Wrap `File` in `Arc<Mutex<File>>` — straightforward; ~5% perf cost on heavy concurrent IO
- B) Use `tokio::fs::File` whose internals are async-safe
- C) Keep raw `Arc<File>` but document that operations on the same File from multiple tasks must be serialized externally

Pick: **A** for correctness margin + reviewability, despite the perf cost. Document B as a future migration path; C as the "do nothing" baseline for comparison.

---

## W3: Memory-Layout-Heavy Crate Walkthrough

**Project:** Terminal renderer with `#[repr(C, align(16))]` cells and SIMD diff.

Phase 1 inventory captures the layout asserts:

```rust
const _: () = assert!(core::mem::size_of::<Cell>() == 16);
const _: () = assert!(core::mem::align_of::<Cell>() >= 16);
```

Phase 2 alignment-bucket sweeper verifies every `*const Cell` deref site has the alignment invariant met (cross-references the const asserts as proof). Phase 3 Miri symbolic-alignment-check runs the diff routine; clean.

Phase 6 idea-wizard surfaces: "What happens when LLVM auto-vectorizes the diff loop and reads a partial 16-byte block at the end of a non-multiple-of-16 row?" → EXP-021. Verdict: NO_EVIDENCE (the bounds check at line 98 prevents this).

Convergence at round 10. Phase 8: zero remediation needed — the existing const asserts and bounds checks are sound. Phase 12 produces an `UB_RUNBOOK.md` that mandates the const asserts as a permanent CI gate.

---

## W4: Already-Mature Crate Walkthrough

**Project:** A crate that already shipped Miri CI + 20 loom models + 80 fuzz targets (e.g., asupersync after exemplars E1-E11 have already landed).

### Approach

- **Phase 1 diff:** compare current unsafe-surface inventory against the last audit's `phase1_unsafe_surface_inventory.md`. Only the *new* sites need full re-audit.
- **Phase 3 — verify existing harness still passes** — first checkpoint. If a previously-passing test now fails, that's a regression bead.
- **Phase 6 idea-wizard** has high yield here because it catches shapes the existing harness doesn't already cover.

Time: ¼ day instead of ½ day.

---

## W5: Pure-Safe Crate Walkthrough

**Project:** `beads_rust`, `#![forbid(unsafe_code)]` everywhere.

### Surprise findings

Phase 2's library-trait-invariant bucket flags:
- A manual `Hash`/`Eq` mismatch — `HashMap` key correctness bug; UB only if unsafe code depends on the invariant
- An `Iterator::size_hint` lower-bound lie — correctness bug unless project-local unsafe collection code trusts it

Phase 5 proptests catch the `Hash`+`Eq` lie. Miri is still useful for unsafe dependencies and any unsafe-boundary reproducer, but it is not expected to flag ordinary safe `HashMap::get` here.

Phase 8 remediation: derive `Hash` and `Eq` from the same fields; add a proptest harness asserting `a == b ⟹ hash(a) == hash(b)`.

---

## W6: Incident Response Walkthrough

**Trigger:** "Miri reported `attempting reborrow from disabled location` at btree.rs:412 after my last commit."

### Flow

1. **Phase 0** — `F-001` is the reported finding. Scope: `crates/fsqlite-btree/src/`.
2. **Phase 1** — inventory the btree module: 23 unsafe sites, 5 of which involve the cursor pattern at line 412.
3. **Phase 2** — sweep buckets aliasing + alignment + lifetime-escape.
4. **Phase 4** — `EXP-001` is the exact reproducer from Miri's error.
5. **Phase 5** — run EXP-001: CONFIRMED_UB. Variant EXP-001-a tests whether the bug also affects the read-only path: CONFIRMED_UB.
6. **Phase 6** — wizard prompt: "Given that the cursor split path violates aliasing, what other btree paths might co-exist?" → 3 new experiments.
7. **Phase 7** — 4 iterations (incident is scoped); convergence at round 5 (early stop allowed for incident response if no new findings emerge in 2 rounds AND the original symptom is `CONFIRMED_UB`).
8. **Phase 8** — remediation for F-001 (chosen: take a `&mut Page` from the page table instead of casting `&Page` to `*mut`).
9. **Phase 9** — bead `br-201 Fix cursor aliasing; br-202 [test] Add Miri tree-borrows test for cursor`.
10. **Phase 10** — fresh-eyes confirms the remediation is sound.

Total time: 4-8 hours.

---

## W7: Pre-Release Gate Walkthrough

**Project:** `frankensqlite v1.0.0` about to ship to crates.io.

Full Standard-mode run (Phases 1-10) + selective Phase 11 soak on the FFI surface.

### Deliverables specifically for release

- `docs/SOUNDNESS.md` — links to `UB_RUNBOOK.md`, summarizes which Miri/sanitizer/loom/fuzz gates run in CI.
- `README.md` "Soundness" section with a badge `![soundness](https://img.shields.io/badge/UB%20audit-2026--05-green)` linking to the audit's bead graph.
- Release notes entry: "Pre-1.0 UB exorcism — 47 findings, 39 remediated, 2 deferred (see SOUNDNESS.md)".
- `cargo publish --dry-run` only after all Phase 9 beads close.

Time: 1–2 days.

---

## Mini Cookbook: Single-Operator Workflows

### "Just run Miri on my crate, don't do the full audit"

```bash
$ ./scripts/run-miri-matrix.sh . .ub-exorcism/quick-miri-1
$ less .ub-exorcism/quick-miri-1/phase3_raw/miri_tree_borrows.log
```

Phase 3 standalone. Workspace artifacts still live under the project-local `.ub-exorcism/` namespace; no beads are produced. Triage-level only.

### "I have a Miri error, isolate the cause"

```bash
$ cat > /tmp/repro.rs <<EOF
fn main() { /* paste from Miri error */ }
EOF
$ cargo +nightly miri run --bin repro
# Apply operator ✦ ISOLATE — reduce by half iteratively until still UB
```

### "Set up CI gates from a prior audit's UB_RUNBOOK.md"

```bash
$ cp /path/to/UB_RUNBOOK.md docs/SOUNDNESS.md
$ # Lift the GitHub Actions YAML excerpt from UB_RUNBOOK.md into .github/workflows/ub.yml
$ # Lift the cargo + nightly + miri install steps into a setup-script
```

Phase 12-only invocation: build the CI gates without re-running the audit.
