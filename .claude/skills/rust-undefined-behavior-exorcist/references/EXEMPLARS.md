# Exemplars — Mined Gold-Standard Patterns

Quote bank from `/dp/*` Rust projects where we've already done the work of eliminating UB at scale. Every pattern has an anchor (`<project> <file:line>`) and a short literal quote. This is Track A material from `/operationalizing-expertise`.

---

## Pattern E1 — Multi-Part SAFETY Contract (frankensqlite, asupersync, frankenlibc)

The SAFETY comment names *every* prerequisite of the unsafe op, in the order they were established in the surrounding code. Preconditions are validated *outside* the unsafe block; the unsafe block assumes them.

**Anchor:** `frankensqlite/fsqlite-vfs/src/shm.rs:397-430` (atomic ops at byte offset)
```rust
// SAFETY: `offset` bounds/alignment were validated above and
// the mapping stays alive for the duration of the guard.
let raw = unsafe { atomic_u64_at(m.ptr, offset) }.load(ordering);
```

**Anchor:** `asupersync/src/process.rs:1463` (libc waitpid)
```rust
// Safety: pid is the kernel-assigned PID for our owned child; `&mut status` is
// a valid out-pointer. `WNOHANG` makes this non-blocking — returns 0 if child
// is still running, pid if reaped, -1 on error.
let _ = unsafe { libc::waitpid(pid, &mut status, libc::WNOHANG) };
```

**Ritual derived:** every SAFETY comment is 2–4 lines, names the invariant, and points back at the enforcing code. Comments <40 char are weak — flag them in Phase 1.

---

## Pattern E2 — `unsafe impl Send`/`Sync` With External Synchronization

The SAFETY comment names: (a) the external sync mechanism, (b) the only public interface through which `&self` deref happens, (c) why that interface is sound.

**Anchor:** `frankensqlite/fsqlite-vfs/src/shm.rs:59-61`
```rust
// SAFETY: The mmap region is backed by a `MAP_SHARED` file mapping.
// Multiple processes/threads can safely access it via the POSIX shared memory
// contract (coordinated by fcntl locks and memory barriers). The raw pointer
// is only dereferenced through the `ShmRegionGuard` which holds a mutex lock.
unsafe impl Send for MmapBacking {}
unsafe impl Sync for MmapBacking {}
```

**Ritual:** every `unsafe impl Send`/`Sync` for a type holding raw state must cite (a)+(b)+(c). If any is missing, Phase 2 flags it as `LIKELY-UB`.

---

## Pattern E3 — Forbid Unsafe at Crate Boundaries (beads_rust, mcp_agent_mail_rust, pi_agent_rust, rich_rust)

The library forbids unsafe at the lib.rs level; the boundary crate exposes a safe public API; only specific boundary modules waive the forbid.

**Anchor:** `beads_rust/src/lib.rs:22`
```rust
#![forbid(unsafe_code)]
```

**Anchor:** `mcp_agent_mail_rust` — 6 of 11 crates forbid unsafe; the others use it only in test/conformance modules.

**Anchor:** `rich_rust/src/lib.rs:158`
```rust
#![forbid(unsafe_code)]
```

**Ritual:** start every new crate with `#![forbid(unsafe_code)]`. Only remove with a commit explicitly justifying the new unsafe surface. This is *architectural forbiddance*, not lint suppression.

---

## Pattern E4 — Refcount Choreography (asupersync RawWaker)

Every raw-pointer constructor is paired with a destructor in a documented dance:

- `clone` — `from_raw` + `clone` + `forget(old)` + `into_raw(new)`
- `wake` — `from_raw` (consumes)
- `wake_by_ref` — `from_raw` + `forget` (borrows)
- `drop` — `from_raw` (final)

**Anchor:** `asupersync/fuzz/fuzz_targets/mutex_lock_owned_cancel.rs:131-189`
```rust
unsafe fn tracked_waker_clone(data: *const ()) -> RawWaker {
    // SAFETY: RawWaker data is always created from Arc<TrackedWaker> in create_waker.
    let arc = unsafe { Arc::from_raw(data as *const TrackedWaker) };
    let cloned = arc.clone();
    std::mem::forget(arc);  // Balance the from_raw
    let new_data = Arc::into_raw(cloned) as *const ();
    RawWaker::new(new_data, &TRACKED_WAKER_VTABLE)
}
```

**Ritual:** every `Arc::from_raw` is paired with `Arc::into_raw` or `std::mem::forget`. Auditors trace the pairing across the vtable; missing pairs are double-free or leak hazards.

---

## Pattern E5 — Compile-Time Layout Assertions (frankentui, frankensqlite)

Every SIMD-or-memory-critical type ships a `const _: ()` assert proving size and alignment.

**Anchor:** `frankentui/ftui-render/src/cell.rs:338`
```rust
const _: () = assert!(core::mem::size_of::<Cell>() == 16);
```

**Anchor:** `frankentui/ftui-render/src/diff.rs:98-109`
```rust
const _: () = assert!(
    core::mem::size_of::<Cell>() * BLOCK_SIZE == 64,
    "BLOCK_SIZE * Cell must equal 64-byte cache line"
);
const _: () = assert!(
    core::mem::align_of::<Cell>() >= 16,
    "Cell alignment must be >= 16 for SIMD access"
);
```

**Ritual:** for every `#[repr(C|transparent|packed|align)]` type, ship a const assert for size and alignment. Catches silent layout regressions when refactoring.

---

## Pattern E6 — SAFE-by-Default for Bytewise Operations

When tempted to byte-index `&str`, use UTF-8-aware alternatives.

**Anchor:** `mcp_agent_mail_rust` commit `02a01ce7` ("fix: replace unsafe byte-index string access with boundary-checked alternatives across 6 crates")

Before:
```rust
line.as_bytes()[col1_start]
sanitized.as_bytes()[0].is_ascii_alphanumeric()
```

After:
```rust
line.bytes().nth(col1_start).unwrap()
sanitized.chars().next().is_some_and(|c| c.is_ascii_alphanumeric())
```

**Ritual:** Phase 2 flags every `as_bytes()[i]` as `SUSPICIOUS`; if the string is UTF-8 and the index isn't on a char boundary, it's UB-adjacent (mis-renders or crashes on non-ASCII).

---

## Pattern E7 — Arc-Count As Drop Guard (frankenfs)

Resource cleanup is guarded by counting Arc references — only remove from the table when `strong_count == 2` (table + this guard).

**Anchor:** `frankenfs/ffs-fuse/src/lib.rs:1217-1254`
```rust
impl Drop for FuseInodeGuard {
    fn drop(&mut self) {
        // ... acquire table mutex, release held flag ...
        if Arc::strong_count(&self.lock) == 2
            && let Some(existing) = table.get(&self.ino)
            && Arc::ptr_eq(existing, &self.lock)
        {
            table.remove(&self.ino);
        }
    }
}
```

**Ritual:** when entries in a table own resources and must be removed when the last user goes away, check `strong_count == 2 + Arc::ptr_eq` (table + self). Prevents concurrent revival of the resource.

---

## Pattern E8 — Property Tests as Soundness Oracle (frankensqlite, asupersync)

When introducing SIMD / transmute / from_raw, ship a 10⁴-case proptest verifying the unsafe path matches the safe scalar path.

**Anchor:** `frankensqlite` commit `1c58156e` (SIMD integer serialization)
- Removed raw AVX2 intrinsics in favor of `std::simd`
- Added 10,000-case proptest verifying SIMD output matches scalar byte-for-byte

**Ritual:** every new unsafe block in a hot path must be proven correct via a 10⁴+ proptest against the safe reference implementation. The proptest stays in CI permanently as a regression guard.

---

## Pattern E9 — Defensive `.expect()` With Invariant Name

When unwrapping inside unsafe code, use `.expect("Invariant X violated: <name>")` not `.unwrap()`. The expect message names the invariant and aids panic debugging.

**Anchor:** `frankentui/ftui-core/src/s3_fifo.rs:131-135`
```rust
// SAFETY: indices in `index` are guaranteed to be valid and occupied.
let entry = self.entries[idx]
    .as_mut()
    .expect("S3Fifo invariant violated: valid index required");
```

**Ritual:** every `.unwrap()` inside `unsafe { … }` becomes `.expect("<invariant name>")`. Phase 2 flags bare `.unwrap()` inside unsafe blocks.

---

## Pattern E10 — Boundary Safety Without FFI Hacks (pi_agent_rust SIGPIPE)

When a problem seems to require unsafe FFI (e.g., resetting SIGPIPE before exec), check whether a safe shell trampoline can achieve the same effect.

**Anchor:** `pi_agent_rust/src/tools.rs:550+` — wraps every child process in `/bin/sh -c 'trap - PIPE\nexec "$@"\n...'` to reset SIGPIPE without `Command::pre_exec` (which requires unsafe FFI).

**Ritual:** before adding new unsafe FFI to solve a process / signal / fd problem, check whether a `/bin/sh` trampoline can do the job. Often yes.

---

## Anti-Pattern E11 — Truncating Casts Without Bounds Check (frankenfs, fixed in commit `35610ffd`)

```
Remove the clippy::cast_possible_truncation suppression and replace
bare `as u16` / `as u32` casts with new clamp_to_u16 and clamp_to_u32
helper functions that use saturating conversion. This prevents silent
wrap-around corruption when ext4 extent lengths or logical block
numbers exceed their target type's range.
```

**Ritual:** Phase 2 flags every `as u16` / `as u32` / `as i32` cast that narrows. Either: (a) prove the value is in range via a preceding check; or (b) use saturating/checked casts; or (c) keep the wider type.

---

## Cross-Cutting Rituals (the operator-library back-feed)

These mined patterns feed back into the operator library:

| Pattern | Operator triggered |
|---|---|
| E1 (multi-part SAFETY) | `★ SUSPECT` flags missing/weak SAFETY |
| E2 (unsafe impl) | `★ SUSPECT` + Phase 2 Send/Sync bucket sweeper |
| E3 (forbid unsafe) | Phase 1 inventory + Phase 8 remediation candidate "extract to forbid-unsafe sub-crate" |
| E4 (refcount choreography) | Phase 2 refcount-lifecycle bucket |
| E5 (compile-time asserts) | Phase 1 inventory captures every `const _: ()` and `static_assertions!` |
| E6 (UTF-8 safe) | Phase 2 ast-grep pattern flags `as_bytes()[i]` |
| E7 (Arc-count drop guard) | Phase 2 panic-safety + drop-impl audit |
| E8 (proptest oracle) | Every Phase 8 remediation ships a proptest |
| E9 (.expect with invariant) | Phase 2 flags bare `.unwrap()` inside `unsafe` |
| E10 (boundary without FFI) | Phase 8 remediation candidate "shell trampoline instead of unsafe" |
| E11 (saturating casts) | Phase 2 narrowing-cast audit |

---

## Project-Specific UB Shapes Worth Remembering

| Project | UB shape | Where it surfaced |
|---|---|---|
| frankensqlite | mmap atomic ops at byte offset | `fsqlite-vfs/src/shm.rs:397+` |
| frankensqlite | `Box::from_raw` on FFI-supplied pointer | `fsqlite-c-api/src/lib.rs:716` |
| asupersync | `Arc<File>` concurrent access race | `src/fs/file.rs` — required TSan oracle |
| frankenlibc | transmute of host symbol addr | `dlfcn_abi.rs:152` — gated by `host_resolve` step |
| frankenfs | truncating `as u16` cast | commit `35610ffd` — silent wrap-around |
| mcp_agent_mail | byte-indexing into `&str` | commit `02a01ce7` — 9 fixes across 6 crates |
| pi_agent | SIGPIPE inheritance through `exec` | `src/tools.rs:550+` — solved via shell trampoline |

Use these as templates: when auditing a *new* project, check whether each shape has an analog there.
