# CASS-MINING-DEEP.md — Per-Failure-Class CASS Recipes

Companion to [CASS-MINING.md](CASS-MINING.md) and [CASS-QUERY-PACK.md](../source/CASS-QUERY-PACK.md). This file is the EXTENDED query pack: per failure class, multi-pass queries that surface the deepest precedents.

Use when the audit needs more than the canonical query pack — typically for incidents, dep-soundness deep dives, or pre-release-gate audits.

---

## Recipe 1 — FFI unwinding incident

A user reports a SEGV when a callback panics. The CASS deep mine:

```bash
# Local first
cass search "extern C panic unwind UB"           --robot --limit 30
cass search "catch_unwind FFI boundary"          --robot --limit 30
cass search "panic abort profile cargo"          --robot --limit 20
cass search "Rust panic across C ABI"            --robot --limit 20
cass search "C++ exception Rust interop"         --robot --limit 20

# Remote hosts — different workloads
for h in css csd ts1 ts2; do
  cass search "extern C panic unwind UB" --robot --limit 20 --host "$h"
  cass search "panic abort vs unwind audit" --robot --limit 20 --host "$h"
done

# Specific exemplar repos
cass search "frankenlibc panic abort"            --robot --limit 30
cass search "frankensqlite catch_unwind"         --robot --limit 30
```

Expected findings: the `panic = "abort"` decision documented in `frankenlibc`; the `catch_unwind` pattern used in `frankensqlite`'s sqlite-callback handlers.

---

## Recipe 2 — Send/Sync newtype migration

Refactoring a hand-rolled `unsafe impl Send`:

```bash
cass search "SendPtr newtype audited Send Sync"  --robot --limit 30
cass search "unsafe impl Send for raw pointer"   --robot --limit 30
cass search "auto-derive Send Sync after refactor" --robot --limit 30
cass search "static_assertions assert_impl_all"  --robot --limit 20
cass search "PhantomData<*mut T> trick"          --robot --limit 20

# Exemplar-specific
cass search "franken_engine worker handle Send"  --robot --limit 30
cass search "mcp_agent_mail SocketFd Send"       --robot --limit 30
```

Expected findings: the newtype-with-audited-Send pattern from `franken_engine` (bead `br-fengine-1788` analog); the `SocketFd` newtype from `mcp_agent_mail_rust`.

---

## Recipe 3 — Pin self-referential refactor

Trying to move a manual `Pin::new_unchecked` to `pin-project-lite`:

```bash
cass search "Pin::new_unchecked refactor pin-project" --robot --limit 30
cass search "pin-project-lite self-referential"      --robot --limit 30
cass search "PhantomPinned !Unpin"                   --robot --limit 20
cass search "Box::pin returns Pin<Box>"              --robot --limit 20
cass search "async self-ref state machine"           --robot --limit 30

# Failures
cass search "pin-project can't project lifetime"     --robot --limit 20
cass search "self-referential async cancellation"    --robot --limit 20
```

Expected findings: the pin-project-lite adoption in `mcp_agent_mail_rust`; the cases where pin-project couldn't express the projection (those that stayed (A)).

---

## Recipe 4 — SIMD safe-only feature flag

Adding `safe-only` to a SIMD crate:

```bash
cass search "safe-only feature flag SIMD migration" --robot --limit 30
cass search "std::simd portable migration bench"   --robot --limit 30
cass search "wide crate stable fallback"           --robot --limit 30
cass search "autovectorization friendly safe loop" --robot --limit 30
cass search "per-target benchmark x86_64 aarch64"  --robot --limit 30
cass search "AVX-512 thermal throttling"           --robot --limit 20

# rich_rust is the canonical example
cass search "rich_rust safe-only feature"          --robot --limit 30
cass search "rich_rust portable_simd benchmark"    --robot --limit 30
cass search "rich_rust per-target matrix"          --robot --limit 30
```

Expected findings: the rich_rust safe-only feature shape; the per-target bench discipline; the AVX-512 opt-in decision.

---

## Recipe 5 — Allocator refactor

In-crate callers of a custom allocator move to safe arena types:

```bash
cass search "allocator identity refactor bumpalo"  --robot --limit 30
cass search "slab::Slab replace raw pointer"       --robot --limit 30
cass search "generational_arena vs slab"           --robot --limit 30
cass search "GlobalAlloc impl miri stacked"        --robot --limit 30
cass search "arena bump alloc cache locality"      --robot --limit 30

# frankenfs is the exemplar
cass search "frankenfs slab in-crate callers"      --robot --limit 30
cass search "frankenfs bumpalo migration"          --robot --limit 30
```

Expected findings: the frankenfs in-crate slab→bumpalo refactor (`br-ffs-148` analog); the cases where the slab stayed.

---

## Recipe 6 — io_uring / async I/O refactor

Refactoring io_uring usage:

```bash
cass search "io_uring SQE CQE safe wrapper"        --robot --limit 30
cass search "io_uring submission ring shared"      --robot --limit 30
cass search "epoll replace io_uring perf cliff"    --robot --limit 20
cass search "tokio-uring vs glommio vs monoio"     --robot --limit 30
cass search "completion ring kernel write race"    --robot --limit 30

# asupersync is the exemplar
cass search "asupersync io_uring kernel race"      --robot --limit 30
cass search "asupersync mmap shared MmapHandle"    --robot --limit 30
```

Expected findings: the asupersync `Ring::submit` pattern; the mmap-handle-with-Drop discipline; the reason `epoll` was rejected.

---

## Recipe 7 — Macro-generated unsafe audit

Auditing derive-heavy crate:

```bash
cass search "cargo expand unsafe macro output"     --robot --limit 30
cass search "zerocopy-derive FromBytes audit"      --robot --limit 30
cass search "bytemuck-derive Pod"                  --robot --limit 30
cass search "pin-project-lite expansion"           --robot --limit 30
cass search "custom proc-macro emits unsafe"       --robot --limit 30
cass search "bindgen output cluster audit"         --robot --limit 30

# beads_rust had a serializer macro
cass search "beads_rust transmute serialization derive" --robot --limit 30
```

Expected findings: the cluster-by-macro-source pattern; the swap from custom derive to zerocopy-derive in beads_rust.

---

## Recipe 8 — Lock-free / atomic refactor

Replacing hand-rolled CAS loops:

```bash
cass search "arc-swap atomic config replace"       --robot --limit 30
cass search "crossbeam SegQueue replace lockfree"  --robot --limit 30
cass search "dashmap replace Mutex HashMap"        --robot --limit 30
cass search "atomic Ordering Acquire Release SeqCst" --robot --limit 30
cass search "loom model lock-free verify"          --robot --limit 30

# franken_engine
cass search "franken_engine arc-swap config"       --robot --limit 30
cass search "franken_engine inbox shard SegQueue"  --robot --limit 30
cass search "franken_engine worker_park atomic"    --robot --limit 30
```

Expected findings: the franken_engine arc-swap migration; the SegQueue inbox; the (A) decision on `worker_park` intrinsics.

---

## Recipe 9 — Embedded / volatile MMIO

For embedded crates:

```bash
cass search "volatile-register crate MMIO"         --robot --limit 30
cass search "embedded-hal PAC type safety"         --robot --limit 30
cass search "vcell volatile cell"                  --robot --limit 30
cass search "memory-mapped IO safe abstraction"    --robot --limit 30

# pi_agent_rust
cass search "pi_agent_rust volatile-register"      --robot --limit 30
cass search "pi_agent_rust GPIO UART"              --robot --limit 30
```

Expected findings: the pi_agent_rust per-peripheral ownership; the volatile-register adoption.

---

## Recipe 10 — Pre-existing UB discovery

When the audit's harness finds unrelated UB:

```bash
cass search "pre-existing UB outside refactor scope" --robot --limit 30
cass search "miri stacked borrows old bug"           --robot --limit 30
cass search "incident response 5 whys"               --robot --limit 30
cass search "bisect commit introduced UB"            --robot --limit 30

# Look for prior incidents
cass search "CVE Rust crate soundness advisory"      --robot --limit 30
cass search "yank cargo version security"            --robot --limit 30
```

Expected findings: prior incident response sessions, how the team triaged, the pre-existing-UB protocol's evolution.

---

## How to combine recipes

For an audit with multiple unsafe classes (most audits), run multiple recipes:

```bash
# Multi-recipe driver
RECIPES="ffi-unwinding send-sync pin-self-ref simd-safe-only allocator"
for r in $RECIPES; do
  bash "$(dirname "$0")/cass-recipe-${r}.sh" "$AUDIT_DIR" || true
done

# Aggregate by host + class
jq -s 'sort_by(._host, ._class)' "$AUDIT_DIR"/phase0_cass_*.jsonl \
  | jq 'group_by(._class) | map({class: .[0]._class, hits: . | length})' \
  > "$AUDIT_DIR/phase0_cass_class_summary.json"
```

This produces a class-by-class summary the orchestrator uses to weight Phase 4 classification.

---

## Output: enriched findings file

`<audit-dir>/phase0_cass_findings_deep.md` is the enriched output. Per the recipe:

```markdown
# CASS Deep Findings

Generated: <date>
Recipes run: <list>
Hosts queried: localhost, css, csd, ts1, ts2
Total unique hits: <N>

## By recipe

### Recipe 1 — FFI unwinding (<count> hits)
- ...
- ...

### Recipe 2 — Send/Sync newtype (<count> hits)
- ...

## Cross-recipe patterns

Sessions that mention patterns from multiple recipes:
- Session <ts> on <host>: <pattern intersection>
```

The orchestrator reads this in Phase 4 and weights classifications accordingly.
