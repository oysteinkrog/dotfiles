# Workflows — Per-Archetype Audit Flows

The 12-phase loop is the same regardless of project shape. *What you focus on within each phase* varies by archetype. This file is the per-archetype playbook. Pick the row that matches the project; use it to pre-prioritize buckets, tools, and experiments.

---

## Archetype Decision Tree

```
Does the project have `extern "C"` blocks or build.rs bindings?
├── YES → FFI-Heavy crate (W1)
└── NO  → continue
        Does the project have custom Send/Sync impls or lock-free DS?
        ├── YES → Concurrency-Heavy crate (W2)
        └── NO  → continue
                Does the project have raw pointers / MaybeUninit / transmute?
                ├── YES → Memory-Layout-Heavy crate (W3)
                └── NO  → continue
                        Does it use #[cfg(loom)] / shuttle / cargo-fuzz?
                        ├── YES → already-mature crate (W4)
                        └── NO  → Pure-safe crate audit (W5)

Is the user responding to an incident?
└── Incident response (W6, separate flow)

Is the user prepping a crates.io release?
└── Pre-release gate (W7, separate flow)
```

---

## W1 — FFI-Heavy Crate

**Example:** `frankensqlite` (SQLite port), `frankenlibc` (libc reimplementation), any `*-sys` crate.

### Priority buckets (Phase 2)

1. **#10 FFI contracts** — primary; cross-reference every `extern "C"` against the C header
2. **#3 Alignment** — C structs often have alignment requirements
3. **#22 repr(packed) field addr** — common in C struct ports
4. **#20 Dangling Box** — when C allocates and Rust frees, or vice versa
5. **#21 FFI callback aliasing** — bidirectional crossings
6. **#1 Aliasing** — raw pointer derefs at the boundary
7. **#16 Volatile contracts** — MMIO is common in firmware ports

### Tooling priorities (Phase 3)

- **Miri with `#[cfg(miri)]` shims** for every FFI call. The shim must have the same aliasing contract as the real call.
- **ASan** is the primary sanitizer (catches heap corruption from misuse of C allocators).
- **TSan** if there are callbacks crossing thread boundaries.
- **Fuzz harnesses** for every API that hands raw bytes to C.

### Idea-wizard prompts (Phase 6)

- "What custom invariants does this C library document that Rust doesn't enforce automatically?"
- "Which of our types are passed by value through C? What does their layout actually look like?"
- "Are there callbacks the C library can fire at unexpected times (signal handlers, atexit hooks)?"

### Cookbook reference: [COOKBOOK.md W1 walkthrough](COOKBOOK.md#w1-ffi-heavy-crate-walkthrough).

---

## W2 — Concurrency-Heavy Crate

**Example:** `asupersync` (async runtime), custom lock-free queues, `Arc<File>` shared-state crates.

### Priority buckets

1. **#7 Data races** — primary; loom + TSan
2. **#8 Send/Sync invariants** — manual impls audited for synchronization story
3. **#1 Aliasing** — concurrent raw-pointer derefs
4. **#13 Refcount lifecycle** — `Arc::from_raw` in vtable patterns (e.g., `RawWaker`)
5. **#17 Async drop hazards** — blocking I/O in `Drop` on a tokio task
6. **#9 Pin invariants** — `Pin::new_unchecked` for self-referential futures

### Tooling priorities

- **TSan with `--test-threads=1`** is the primary sanitizer.
- **Loom** for every sync primitive (≤3 threads, ≤1000 iters).
- **Shuttle** with 10⁴+ random schedules when loom blows up.
- **Miri tree-borrows** catches the aliasing layer.
- **Fuzz harnesses for stateful concurrency** — generate sequences of operations via `Arbitrary`, dispatch across N tasks, assert invariants.

### Idea-wizard prompts

- "What invariants does our custom sync primitive depend on between the producer and consumer?"
- "Are there any `AtomicOrdering::Relaxed` uses that need `Acquire`/`Release`?"
- "Can a `Drop` run while another task is mid-operation on the same data?"

### Cookbook reference: [COOKBOOK.md W2 walkthrough](COOKBOOK.md#w2-concurrency-heavy-crate-walkthrough).

---

## W3 — Memory-Layout-Heavy Crate

**Example:** `frankentui` (terminal Cell with `#[repr(C, align(16))]`), `frankenfs` (ext4 on-disk layout), custom allocators, SIMD-heavy code.

### Priority buckets

1. **#3 Alignment** — `#[repr(packed|C|align)]` types
2. **#6 Type punning** — `transmute` between layout types
3. **#4 Validity invariants** — `mem::zeroed::<T>()` for non-zero-valid T
4. **#5 Uninitialized memory** — `MaybeUninit::assume_init` discipline
5. **#19 Target-feature mismatch** — SIMD without `is_x86_feature_detected!`
6. **#22 repr(packed) field addr** — packed structs

### Tooling priorities

- **Miri symbolic-alignment-check** + **strict-provenance**
- **Compile-time `const _: ()` asserts** for every layout-critical type (see exemplar E5)
- **Proptest with safe-scalar comparison** for every SIMD path
- **`bytemuck` / `zerocopy` candidacy scan** for every `transmute`

### Idea-wizard prompts

- "Could LLVM ever reorder fields of our `#[repr(Rust)]` types?"
- "Are any of our SIMD intrinsics called without runtime feature detection?"
- "Do our `mem::zeroed` calls assume validity for types that may grow non-zero-valid fields?"

### Cookbook reference: [COOKBOOK.md W3 walkthrough](COOKBOOK.md#w3-memory-layout-heavy-crate-walkthrough).

---

## W4 — Already-Mature Crate

**Example:** A crate that already has Miri CI, loom models, fuzz corpora — but is up for re-audit (e.g., pre-release, post-major-refactor, post-dep-bump).

### Priority

- **Verify the existing harness still passes** — Phase 3 dynamic sweep is the first checkpoint
- **Phase 1 inventory diff** — what unsafe surface changed since the last audit?
- **Phase 6 idea-wizard** is especially valuable here — fresh-eyes ideas catch shapes the existing harness missed

### Tooling

- Existing `MIRIFLAGS` config — *plus* the matrix variants the current CI doesn't already run
- Existing loom models — *plus* expand thread/iter counts under Phase 11 soak
- Existing fuzz targets — *plus* longer wall time under Phase 11

### Cookbook reference: [COOKBOOK.md W4 walkthrough](COOKBOOK.md#w4-already-mature-crate-walkthrough).

---

## W5 — Pure-Safe Crate Audit

**Example:** `beads_rust`, `mcp_agent_mail_rust`, `rich_rust` — `#![forbid(unsafe_code)]` everywhere.

### Surprise: pure-safe crates can still participate in soundness failures

- **#12 Std-library trait invariants** — safe trait drift (`Hash`+`Eq` lies, `Iterator::size_hint` lies, `Ord` inconsistency) is usually a logic bug; escalate to UB only when unsafe code or unsafe traits rely on it
- **#25 Hash/Eq/Borrow consistency** — same shape, separate bucket for `HashMap` keys; not UB by itself
- **#7 Data races** — atomic Orderings in safe code can still race
- **#17 Async drop hazards** — `Drop` blocking in a Tokio worker is safe code with severe liveness consequences (panic/deadlock), UB only if an unsafe contract is also violated
- **#24 Coherence violations** — only if `feature(specialization)` is used (rare)

### Priority

- Forbid-unsafe is great but it doesn't eliminate dependency- or unsafe-contract risk; this audit is faster but not skippable
- Most findings will be `LIKELY-UB` or `CONTRACTUAL-BUT-DEFENSIBLE` — calibrate severity carefully

### Tooling

- Miri matrix is still mandatory for unsafe dependencies and unsafe-boundary tests; use proptests for `Hash`+`Eq` consistency
- TSan is still mandatory (concurrent code paths can have UB without `unsafe`)
- Proptest harnesses for every `Hash` + `Eq` + `Ord` implementing type

### Cookbook reference: [COOKBOOK.md W5 walkthrough](COOKBOOK.md#w5-pure-safe-crate-walkthrough).

---

## W6 — Incident Response

**Trigger:** Miri error reported, fuzz crash reported, prod use-after-free, CVE filing.

### Flow

1. **Phase 0** — capture the incident's symptom, the affected file:line, the version. Treat as the first finding `F-001`.
2. **Phase 1 (scoped)** — inventory only the module where the symptom appeared.
3. **Phase 2 (scoped)** — sweep only the buckets the symptom suggests (e.g., a Miri SB violation → bucket #1 + #2; a TSan race → bucket #7).
4. **Phase 4** — write `EXP-001` for the exact reported reproducer.
5. **Phase 5** — run `EXP-001` first; everything downstream waits for the verdict.
6. **Phase 6 — idea-wizard prompt: "If THIS is the visible UB, what *other* UB shapes might co-exist in the same module?"** — high yield in incident response.
7. **Phase 7** — iterate until the visible symptom is `CONFIRMED_UB` AND no related findings remain OPEN.
8. **Phase 8** — remediation for `F-001` AND any related findings, with a regression bead pinned to the original incident.
9. **Phase 9** — beads include an `incident-XYZ` label.
10. **Phase 10** — fresh-eyes specifically scrutinizes the remediation against the reported reproducer.

Time budget: hours to a day, depending on incident scope.

### Cookbook reference: [COOKBOOK.md W6 walkthrough](COOKBOOK.md#w6-incident-response-walkthrough).

---

## W7 — Pre-Release Gate (Crates.io)

**Trigger:** preparing a `cargo publish`.

### Flow

1. Full Standard-mode run (Phases 1–10).
2. Phase 11 soak campaigns even in Standard mode for any module touching `unsafe` or FFI.
3. Phase 12 `UB_RUNBOOK.md` is the **shipping artifact** — gets committed to the crate's `docs/` so future maintainers and downstream users can see the soundness posture.
4. After convergence, generate a SOUNDNESS.md badge / section for the README documenting which Miri config, sanitizers, loom models, and fuzz corpora are part of the crate's permanent CI.
5. The audit's bead graph becomes part of the release notes: "Pre-1.0 UB exorcism — N findings, all remediated (link to bead graph)".

### Cookbook reference: [COOKBOOK.md W7 walkthrough](COOKBOOK.md#w7-pre-release-gate-walkthrough).

---

## Cross-Archetype Quick Card

| Archetype | Top tools | Top buckets | Time budget (Standard) |
|---|---|---|---|
| W1 FFI-heavy | Miri + ASan + fuzz + C-header diff | 10, 3, 22, 20, 21 | half-day |
| W2 Concurrency-heavy | TSan + loom + shuttle + Miri TB | 7, 8, 1, 13, 17, 9 | half-day |
| W3 Layout-heavy | Miri (alignment + provenance) + proptest + bytemuck | 3, 6, 4, 5, 19, 22 | half-day |
| W4 Already-mature | Existing harness diff + Phase 6 idea-wizard | varies | quarter-day |
| W5 Pure-safe | dependency soundness scan + TSan + proptest (Hash+Eq) | 12, 25, 7, 17 | quarter-day |
| W6 Incident | Reproducer-first + scoped sweep | varies (symptom-driven) | hours to a day |
| W7 Pre-release | Everything + Phase 11 + UB_RUNBOOK | all | day-plus |
