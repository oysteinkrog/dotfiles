# CASS-QUERY-PACK.md — Pre-Composed Search Queries

Companion to [CASS-MINING.md](../methodology/CASS-MINING.md). This file is the exhaustive query pack the cass-miner subagent runs against `localhost`, `css`, `csd`, `ts1`, `ts2`.

Pack is organized by unsafe class + per-repo. Run via `scripts/cass-mine.sh`.

---

## Core unsafe-refactor queries

```bash
cass search "unsafe to safe"                                     --robot --limit 30
cass search "remove unsafe block"                                --robot --limit 30
cass search "isomorphic safe rewrite"                            --robot --limit 30
cass search "rewrite unsafe equivalent"                          --robot --limit 30
cass search "audit unsafe code"                                  --robot --limit 30
cass search "soundness invariant"                                --robot --limit 20
cass search "SAFETY comment hardening"                           --robot --limit 20
cass search "cargo-geiger count reduction"                       --robot --limit 20
cass search "first-principles unsafe classification"             --robot --limit 20
```

## Per-pattern bundle

```bash
# Pointer migration
cass search "raw pointer to NonNull migration"                   --robot --limit 20
cass search "NonNull to reference"                               --robot --limit 20
cass search "Box::from_raw refactor"                             --robot --limit 20
cass search "ptr arithmetic to slice methods"                    --robot --limit 20

# SIMD & perf
cass search "std::simd portable migration"                       --robot --limit 20
cass search "wide crate SIMD"                                    --robot --limit 20
cass search "core::arch::x86_64 to portable simd"                --robot --limit 20
cass search "autovectorization safe loop"                        --robot --limit 20
cass search "safe-only feature flag SIMD"                        --robot --limit 30
cass search "get_unchecked bounds-check elision"                 --robot --limit 20
cass search "criterion bench unsafe vs safe"                     --robot --limit 20
cass search "hyperfine end-to-end SIMD"                          --robot --limit 20
cass search "perf budget safe-only"                              --robot --limit 20

# Concurrency
cass search "arc-swap atomic config"                             --robot --limit 20
cass search "crossbeam queue replace mpsc"                       --robot --limit 20
cass search "dashmap replace sharded HashMap"                    --robot --limit 20
cass search "indexmap replace HashMap Vec"                       --robot --limit 20
cass search "loom test interleaving"                             --robot --limit 20
cass search "loom preemption_bound"                              --robot --limit 10
cass search "hand-rolled CAS loop replace"                       --robot --limit 20

# Macro-generated unsafe
cass search "cargo expand unsafe macro"                          --robot --limit 20
cass search "zerocopy-derive migration"                          --robot --limit 20
cass search "bytemuck-derive Pod"                                --robot --limit 20
cass search "pin-project-lite adoption"                          --robot --limit 20
cass search "custom proc-macro unsafe emission"                  --robot --limit 20

# Send/Sync impls
cass search "unsafe impl Send Sync removal"                      --robot --limit 20
cass search "SendPtr newtype audited"                            --robot --limit 20
cass search "auto-derive Send Sync after refactor"               --robot --limit 20
cass search "static_assertions::assert_impl_all"                 --robot --limit 10

# FFI
cass search "FFI shim safe wrapper"                              --robot --limit 20
cass search "extern C panic boundary catch_unwind"               --robot --limit 20
cass search "libc syscall wrapper safe"                          --robot --limit 20
cass search "bindgen output cluster"                             --robot --limit 20
cass search "longjmp Rust UB"                                    --robot --limit 10
cass search "callback into Rust panic"                           --robot --limit 10

# Uninit & transmute
cass search "MaybeUninit::assume_init refactor"                  --robot --limit 20
cass search "array::from_fn replace MaybeUninit"                 --robot --limit 20
cass search "transmute to zerocopy"                              --robot --limit 20
cass search "transmute bytemuck"                                 --robot --limit 20
cass search "transmute from_be_bytes from_le_bytes"              --robot --limit 20

# Pin / async
cass search "Pin::new_unchecked refactor"                        --robot --limit 20
cass search "pin-project migration"                              --robot --limit 20
cass search "self-referential async state machine"               --robot --limit 20
cass search "tokio::pin macro"                                   --robot --limit 10
cass search "async cancellation drop UB"                         --robot --limit 20
```

## Per tool

```bash
cass search "miri stacked borrows fix"                           --robot --limit 30
cass search "miri tree borrows"                                  --robot --limit 20
cass search "miri provenance violation"                          --robot --limit 20
cass search "miri disable isolation filesystem"                  --robot --limit 10
cass search "miri sysroot setup"                                 --robot --limit 10
cass search "cargo-careful UB native"                            --robot --limit 20
cass search "cargo fuzz target unsafe"                           --robot --limit 20
cass search "cargo mutants behavior pin"                         --robot --limit 10
cass search "cargo-geiger delta vs baseline"                     --robot --limit 20
cass search "cargo expand macro output"                          --robot --limit 20
cass search "cargo flamegraph SIMD"                              --robot --limit 10
```

## Per failure class

```bash
cass search "double drop panic in drop"                          --robot --limit 20
cass search "async cancellation UB leak"                         --robot --limit 20
cass search "panic unwind through FFI extern C"                  --robot --limit 20
cass search "Drop glue lost resource"                            --robot --limit 20
cass search "allocator identity refactor"                        --robot --limit 20
cass search "use-after-free arena pointer"                       --robot --limit 20
cass search "data race lock-free"                                --robot --limit 20
cass search "alignment misaligned access"                        --robot --limit 20
cass search "stacked borrows uniqueness"                         --robot --limit 20
```

## Per exemplar repo

```bash
for repo in asupersync beads_rust mcp_agent_mail_rust pi_agent_rust rich_rust \
            frankensqlite frankentui franken_engine frankenlibc frankenfs; do

  echo "=== $repo ==="
  cass search "$repo unsafe"                                     --robot --limit 30
  cass search "$repo refactor safety"                            --robot --limit 20
  cass search "$repo miri"                                       --robot --limit 20
  cass search "$repo loom"                                       --robot --limit 20
  cass search "$repo SAFETY comment"                             --robot --limit 20

done

# Repo-specific deep queries (drawn from EXEMPLAR-CATALOG.md)

cass search "asupersync io_uring SQE CQE"                        --robot --limit 30
cass search "asupersync mmap shared task"                        --robot --limit 20
cass search "asupersync MmapHandle Drop"                         --robot --limit 20

cass search "beads_rust rusqlite cluster"                        --robot --limit 20
cass search "beads_rust transmute serialization"                 --robot --limit 20

cass search "mcp_agent_mail_rust WebSocket Pin self-ref"         --robot --limit 30
cass search "mcp_agent_mail_rust SocketFd newtype Send"          --robot --limit 20
cass search "mcp_agent_mail_rust pin-project Future"             --robot --limit 20

cass search "pi_agent_rust volatile MMIO"                        --robot --limit 30
cass search "pi_agent_rust volatile-register crate"              --robot --limit 20
cass search "pi_agent_rust asm interrupt"                        --robot --limit 10

cass search "rich_rust SIMD safe-only feature"                   --robot --limit 30
cass search "rich_rust portable_simd benchmark"                  --robot --limit 20
cass search "rich_rust wide crate fallback"                      --robot --limit 20
cass search "rich_rust AVX-512 throttling"                       --robot --limit 10

cass search "frankensqlite Statement lifetime"                   --robot --limit 30
cass search "frankensqlite longjmp boundary"                     --robot --limit 20
cass search "frankensqlite zerocopy column"                      --robot --limit 20

cass search "frankentui termios single-ownership"                --robot --limit 20
cass search "frankentui SIGWINCH signalfd"                       --robot --limit 20
cass search "frankentui render get_unchecked autovec"            --robot --limit 20

cass search "franken_engine worker_park intrinsic"               --robot --limit 30
cass search "franken_engine ArcSwap config hot-reload"           --robot --limit 20
cass search "franken_engine inbox shard SegQueue"                --robot --limit 20

cass search "frankenlibc syscall cluster wrapper"                --robot --limit 30
cass search "frankenlibc panic abort profile"                    --robot --limit 10
cass search "frankenlibc SAFETY docstring template"              --robot --limit 20

cass search "frankenfs SlabAllocator GlobalAlloc"                --robot --limit 30
cass search "frankenfs miri stacked-borrows allocator"           --robot --limit 20
cass search "frankenfs bumpalo migration in-crate"               --robot --limit 20
cass search "frankenfs inode zerocopy FromBytes"                 --robot --limit 20
```

---

## Reasoning queries (cross-cutting)

These find sessions where reasoning was articulated — the most valuable mining channel.

```bash
cass search "why keep unsafe perf cliff"                         --robot --limit 20
cass search "why reject safe alternative"                        --robot --limit 20
cass search "decided not to refactor unsafe"                     --robot --limit 20
cass search "perf folklore measured"                             --robot --limit 20
cass search "first-principles unsafe is necessary"               --robot --limit 20
cass search "exemplar repo precedent"                            --robot --limit 20
```

---

## Trimmed pack (for quick runs)

For `audit-only` quick runs where the user wants speed, trim to:

```bash
# localhost only
cass search "unsafe to safe"                                     --robot --limit 30
cass search "miri stacked borrows fix"                           --robot --limit 20
# plus one query targeted at the project's primary unsafe class:
case "$PROJECT_KIND" in
  ffi-heavy)   cass search "FFI shim safe wrapper"               --robot --limit 30 ;;
  simd-heavy)  cass search "std::simd portable migration"        --robot --limit 30 ;;
  async-rt)    cass search "Pin::new_unchecked refactor"         --robot --limit 30 ;;
  allocator)   cass search "GlobalAlloc impl miri"               --robot --limit 30 ;;
  *)           cass search "isomorphic safe rewrite"             --robot --limit 30 ;;
esac
```

~30 cass calls vs ~200 for the full pack. Use when the user wants speed > depth.

---

## Per-host strategy

Each user host runs a different workload mix:

- `localhost` (audit-running machine): primary corpus.
- `css` / `csd`: usually heavier system-level Rust work; FFI-heavy bias.
- `ts1` / `ts2`: usually testing / staging workloads; signal-handler + concurrency bias.

The cass-miner subagent runs the same query pack against each host BUT tags the results by host so the orchestrator can weight findings (e.g., concurrency findings from `ts1` are more relevant if the current project is concurrency-heavy).

---

## Output post-processing

Run results through a deduplication pass — the same prompt may appear on multiple hosts:

```bash
jq -s 'unique_by(.prompt_hash)' <(cass search ... --json) ...
```

Tag each unique hit with: hosts where it appeared, applicability flag (per CASS-MINING.md), unsafe class.

Save to `<audit-dir>/phase0_cass_findings.md`.
