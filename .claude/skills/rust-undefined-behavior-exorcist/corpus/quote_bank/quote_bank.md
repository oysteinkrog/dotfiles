# Quote Bank — Stable-Anchored Primary Sources

Each quote has a stable anchor `Q-NNN`. The kernel and operator library cite these anchors. To extract a single quote programmatically:

```bash
awk '/<!-- Q id=NNN/,/<!-- \/Q id=NNN/' quote_bank.md
```

Quotes are grouped by source. Some are populated; others are placeholders waiting for the cass-mining agent to finish (see `corpus/primary_sources/cass_quotes.md` for the live mine).

---

## From `/dp/*` exemplar mining (anchors verified against source)

<!-- Q id=Q-201 source=exemplar project=frankensqlite tag=mmap+SAFETY -->
> ```rust
> // SAFETY: The mmap region is backed by a `MAP_SHARED` file mapping.
> // Multiple processes/threads can safely access it via the POSIX shared memory
> // contract (coordinated by fcntl locks and memory barriers). The raw pointer
> // is only dereferenced through the `ShmRegionGuard` which holds a mutex lock.
> unsafe impl Send for MmapBacking {}
> unsafe impl Sync for MmapBacking {}
> ```

**Source:** `/data/projects/frankensqlite/crates/fsqlite-vfs/src/shm.rs:59-61` (approximate, verify on access)
**Maps to operator:** ★ SUSPECT (positive exemplar — what a strong SAFETY comment looks like)
**Maps to kernel invariant:** I9 (multi-part SAFETY contract), I10 (manual Send/Sync needs synchronization story)
<!-- /Q id=Q-201 -->

<!-- Q id=Q-202 source=exemplar project=asupersync tag=RawWaker+choreography -->
> ```rust
> unsafe fn tracked_waker_clone(data: *const ()) -> RawWaker {
>     // SAFETY: RawWaker data is always created from Arc<TrackedWaker> in create_waker.
>     let arc = unsafe { Arc::from_raw(data as *const TrackedWaker) };
>     let cloned = arc.clone();
>     std::mem::forget(arc);  // Balance the from_raw
>     let new_data = Arc::into_raw(cloned) as *const ();
>     RawWaker::new(new_data, &TRACKED_WAKER_VTABLE)
> }
> ```

**Source:** `/data/projects/asupersync/fuzz/fuzz_targets/mutex_lock_owned_cancel.rs:131+` (approximate)
**Maps to operator:** ⊕ REWRITE (exemplar: how `Arc::from_raw` is paired with `into_raw`/`forget`)
**Maps to kernel invariant:** I11 (refcount lifecycle pairing)
<!-- /Q id=Q-202 -->

<!-- Q id=Q-203 source=exemplar project=frankentui tag=compile-time-asserts -->
> ```rust
> const _: () = assert!(core::mem::size_of::<Cell>() == 16);
> const _: () = assert!(
>     core::mem::size_of::<Cell>() * BLOCK_SIZE == 64,
>     "BLOCK_SIZE * Cell must equal 64-byte cache line"
> );
> const _: () = assert!(
>     core::mem::align_of::<Cell>() >= 16,
>     "Cell alignment must be >= 16 for SIMD access"
> );
> ```

**Source:** `/data/projects/frankentui/ftui-render/src/cell.rs:338` + `diff.rs:98-109`
**Maps to operator:** ⊕ REWRITE (exemplar: compile-time layout verification)
**Maps to kernel invariant:** I12 (layout assumptions need compile-time asserts)
<!-- /Q id=Q-203 -->

<!-- Q id=Q-204 source=exemplar project=frankenfs tag=Arc-count-drop-guard -->
> ```rust
> impl Drop for FuseInodeGuard {
>     fn drop(&mut self) {
>         if Arc::strong_count(&self.lock) == 2
>             && let Some(existing) = table.get(&self.ino)
>             && Arc::ptr_eq(existing, &self.lock)
>         {
>             table.remove(&self.ino);
>         }
>     }
> }
> ```

**Source:** `/data/projects/frankenfs/ffs-fuse/src/lib.rs:1217-1254` (approximate)
**Maps to operator:** ⊕ REWRITE (exemplar: Arc strong_count as a drop guard)
**Maps to kernel invariant:** I11 (refcount lifecycle)
<!-- /Q id=Q-204 -->

<!-- Q id=Q-205 source=exemplar project=mcp_agent_mail_rust tag=UTF-8-safe-replacement -->
> Before:
> ```rust
> line.as_bytes()[col1_start]
> sanitized.as_bytes()[0].is_ascii_alphanumeric()
> ```
>
> After:
> ```rust
> line.bytes().nth(col1_start).unwrap()
> sanitized.chars().next().is_some_and(|c| c.is_ascii_alphanumeric())
> ```

**Source:** `/data/projects/mcp_agent_mail_rust` commit `02a01ce7` ("fix: replace unsafe byte-index string access with boundary-checked alternatives across 6 crates")
**Maps to anti-pattern:** A14 (transmute as a quick fix — by analogy, byte-indexing as a quick fix)
**Maps to ast-grep:** `scripts/patterns/utf8-as-bytes-index.yml`
<!-- /Q id=Q-205 -->

<!-- Q id=Q-206 source=exemplar project=pi_agent_rust tag=shell-trampoline-over-FFI -->
> Instead of `Command::pre_exec(|| { signal::signal(SIGPIPE, SIG_DFL) })`
> (which requires unsafe FFI in a `forbid(unsafe_code)` crate):
>
> ```rust
> let mut command = Command::new("/bin/sh");
> command.arg("-c").arg("trap - PIPE\nexec \"$@\"\n...");
> ```

**Source:** `/data/projects/pi_agent_rust/src/tools.rs:550+` (approximate)
**Maps to operator:** ⊕ REWRITE (exemplar: boundary safety without unsafe FFI)
**Maps to kernel invariant:** I9 (SAFETY contract minimization)
<!-- /Q id=Q-206 -->

---

## From cass session mining

Live cass quotes will land in `corpus/primary_sources/cass_quotes.md` once the
background mining agent finishes. The placeholder anchors below will be filled
when that's done.

<!-- Q id=Q-001 source=cass tag=user-statement-UB-is-Rustonomicon -->
> Placeholder — to be filled by cass mining. Expected: user's first-message
> assertion that UB encompasses the full Rustonomicon, not just `unsafe` blocks.
<!-- /Q id=Q-001 -->

<!-- Q id=Q-002 source=cass tag=SAFETY-comment-discipline -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-002 -->

<!-- Q id=Q-003 source=cass tag=miri-tree-borrows -->
> Placeholder — to be filled by cass mining. Expected: "Miri tree-borrows is gold".
<!-- /Q id=Q-003 -->

<!-- Q id=Q-005 source=cass tag=stress-rare-schedules -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-005 -->

<!-- Q id=Q-006 source=cass tag=wrap-as-runnable-test -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-006 -->

<!-- Q id=Q-007 source=cass tag=TSan-test-threads-1 -->
> Placeholder — to be filled by cass mining. Expected: "TSan + --test-threads=1
> is the only reliable race oracle".
<!-- /Q id=Q-007 -->

<!-- Q id=Q-008 source=cass tag=SUSPECT-triage -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-008 -->

<!-- Q id=Q-009 source=cass tag=minimization-discipline -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-009 -->

<!-- Q id=Q-010 source=cass tag=MIRIFLAGS-matrix -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-010 -->

<!-- Q id=Q-014 source=cass tag=frankensqlite-WAL-corruption -->
> Placeholder — to be filled by cass mining. Expected: an actual frankensqlite
> session where multi-process WAL corruption was diagnosed.
<!-- /Q id=Q-014 -->

<!-- Q id=Q-015 source=cass tag=instrument-with-flags -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-015 -->

<!-- Q id=Q-016 source=cass tag=triage-fast -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-016 -->

<!-- Q id=Q-018 source=cass tag=convergence-10-rounds -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-018 -->

<!-- Q id=Q-021 source=cass tag=document-rejected-alternatives -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-021 -->

<!-- Q id=Q-022 source=cass tag=escalate-to-triangulation -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-022 -->

<!-- Q id=Q-024 source=cass tag=soak-rch-offload -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-024 -->

<!-- Q id=Q-025 source=cass tag=polish-prompt-DO-NOT-OVERSIMPLIFY -->
> Placeholder — to be filled by cass mining. Expected: user's polish prompt
> with "DO NOT OVERSIMPLIFY; DO NOT LOSE FEATURES".
<!-- /Q id=Q-025 -->

<!-- Q id=Q-027 source=cass tag=decompose-multi-bucket-finding -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-027 -->

<!-- Q id=Q-029 source=cass tag=falsifiability-discipline -->
> Placeholder — to be filled by cass mining.
<!-- /Q id=Q-029 -->

---

## Validation

`scripts/validate-corpus.py` checks:
- Every quote has source + tag + project (if applicable) attributes
- Every kernel invariant cites ≥2 distillation sources
- No anchor IDs are duplicated
- Marker start/end pairs match
