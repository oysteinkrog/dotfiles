# CASS-MINING.md — Mining Prior Agent Sessions

The exemplar repos accumulated their refactor reasoning over many agent sessions. CASS indexes those sessions across machines. Mine them for patterns the audit should consider.

Hosts to query: `localhost` plus `css`, `csd`, `ts1`, `ts2` (via `cass --host`).

---

## The query pack (run all per host)

The pack is the same on every host. The orchestrator aggregates results.

```bash
# Core unsafe-refactor queries
cass search "unsafe to safe"                        --robot --limit 30
cass search "remove unsafe"                          --robot --limit 30
cass search "isomorphic safe rewrite"                --robot --limit 30
cass search "miri stacked borrows fix"               --robot --limit 30
cass search "miri provenance violation"              --robot --limit 20
cass search "Tree Borrows accept"                    --robot --limit 20

# Per pattern bundle
cass search "Pin::new_unchecked refactor"            --robot --limit 20
cass search "pin-project migration"                  --robot --limit 20
cass search "transmute to zerocopy"                  --robot --limit 20
cass search "transmute bytemuck"                     --robot --limit 20
cass search "MaybeUninit::assume_init refactor"      --robot --limit 20
cass search "uninit array safe init"                 --robot --limit 20
cass search "unsafe impl Send Sync removal"          --robot --limit 20
cass search "SendPtr newtype wrapper"                --robot --limit 20
cass search "raw pointer to NonNull migration"       --robot --limit 20
cass search "get_unchecked bounds-check"             --robot --limit 20
cass search "std::simd portable migration"           --robot --limit 20
cass search "wide crate SIMD"                        --robot --limit 20
cass search "safe-only feature flag"                 --robot --limit 30
cass search "FFI shim safe wrapper"                  --robot --limit 20
cass search "extern C panic boundary"                --robot --limit 20

# Per tool
cass search "cargo expand macro unsafe"              --robot --limit 20
cass search "cargo-geiger delta"                     --robot --limit 20
cass search "cargo-careful UB"                       --robot --limit 20
cass search "loom test interleaving"                 --robot --limit 20
cass search "loom preemption_bound"                  --robot --limit 10
cass search "cargo fuzz target unsafe"               --robot --limit 20
cass search "cargo mutants behavior pin"             --robot --limit 10

# Per failure class
cass search "double drop panic in drop"              --robot --limit 20
cass search "async cancellation UB"                  --robot --limit 20
cass search "panic unwind through FFI"               --robot --limit 20
cass search "Drop glue lost resource"                --robot --limit 20
cass search "allocator identity refactor"            --robot --limit 20

# Per exemplar repo (heuristic — find sessions about that repo)
for repo in asupersync beads_rust mcp_agent_mail_rust pi_agent_rust rich_rust \
            frankensqlite frankentui franken_engine frankenlibc frankenfs; do
    cass search "$repo unsafe" --robot --limit 30
    cass search "$repo refactor safety" --robot --limit 20
done
```

Run per host via `scripts/cass-mine.sh <audit-dir>`. The script wraps each query with the host loop and tags hits by host.

---

## Output schema

`<audit-dir>/phase0_cass_findings.md` is grouped by unsafe-class:

```markdown
# CASS Findings — Phase 0 mining

## FFI / extern "C"

### Hit 1 — host: ts1; session: 2026-03-14T15:42; project: /dp/frankenlibc
**User prompt:** "We have 200+ unsafe { libc::open } calls; can we refactor to a single safe wrapper?"
**Agent action:** Built `frankenlibc::sys::syscall` module with one safe wrapper per syscall, each
establishing the boundary contract (path null-termination, fd lifetime, errno conversion).
Result: cargo-geiger count fell from 213 to 12; the 12 are the wrappers themselves.
**Applicability to current audit:** HIGH — current project has similar surface.
**Quote excerpt:** "...The trick is to make the wrapper itself the single unsafe boundary, then
everything above can be safe. The 213 calls were all isomorphic — just `open(path, flags)` with
slightly different flags. One generic wrapper covered them all."

### Hit 2 — ...
```

The `Applicability` field is a heuristic flag the cass-miner agent sets by matching the hit's
project's signature (FFI count, target arch, dep tree) against the current audit target.

---

## Per-exemplar-repo mining

Each exemplar repo has its own `cass`-discoverable history. Run these focused queries to surface the canonical patterns we shipped:

### `/dp/frankenlibc`

```bash
cass search "frankenlibc FFI boundary contract"      --robot --limit 30
cass search "frankenlibc safe wrapper" --robot --limit 20
cass search "frankenlibc panic_unwind extern C" --robot --limit 10
```

Expected findings: the single-safe-wrapper pattern, the panic-converter pattern, the boundary contract template.

### `/dp/rich_rust`

```bash
cass search "rich_rust SIMD safe-only"               --robot --limit 30
cass search "rich_rust portable_simd" --robot --limit 20
cass search "rich_rust autovectorization" --robot --limit 20
```

Expected findings: the per-target benchmark protocol, the `safe-only` feature flag pattern, the cases where SIMD was kept (perf cliff > 5%) vs graduated to (C).

### `/dp/mcp_agent_mail_rust`

```bash
cass search "mcp_agent_mail_rust Pin::new_unchecked" --robot --limit 20
cass search "mcp_agent_mail_rust self-ref future" --robot --limit 20
cass search "mcp_agent_mail_rust WebSocket stream" --robot --limit 20
```

Expected findings: self-referential async state machines that are (A); the field-level Pin contract.

### `/dp/asupersync`

```bash
cass search "asupersync io_uring unsafe"             --robot --limit 30
cass search "asupersync mmap shared"                 --robot --limit 20
cass search "asupersync soundness surface"           --robot --limit 20
```

Expected findings: `io_uring` setup unsafe (A); `mmap` shared-memory pointers (A) wrapped in safe API.

### `/dp/franken_engine`

```bash
cass search "franken_engine worker park"             --robot --limit 20
cass search "franken_engine atomic intrinsic"        --robot --limit 20
```

Expected findings: scheduler atomics (A); worker-thread parking (A).

### `/dp/frankensqlite`

```bash
cass search "frankensqlite C binding safe"           --robot --limit 30
cass search "frankensqlite prepared statement lifetime" --robot --limit 20
```

Expected findings: FFI binding patterns; statement-lifetime tracking in safe wrappers.

### `/dp/frankenfs`

```bash
cass search "frankenfs allocator slab"               --robot --limit 20
cass search "frankenfs GlobalAlloc"                  --robot --limit 20
```

Expected findings: allocator (A); slab patterns; the (C) graduation where in-crate callers swapped to `bumpalo`.

### `/dp/frankentui`

```bash
cass search "frankentui terminal mode"               --robot --limit 20
cass search "frankentui signal handler"              --robot --limit 20
```

Expected findings: signal-handler (A); termios setting (A); rendering hot path (B-or-graduated).

### `/dp/beads_rust`

```bash
cass search "beads_rust sqlite binding"              --robot --limit 20
cass search "beads_rust transmute"                   --robot --limit 20
```

Expected findings: rusqlite FFI (A); endian-aware (de)serialization (C, migrated to zerocopy).

### `/dp/pi_agent_rust`

```bash
cass search "pi_agent_rust embedded UART"            --robot --limit 20
cass search "pi_agent_rust volatile register"        --robot --limit 20
```

Expected findings: embedded patterns (A); volatile MMIO (A).

---

## Synthesizing findings into the audit

After mining, the orchestrator agent reads `phase0_cass_findings.md` AND `phase0_exemplar_patterns.md` (from the exemplar-miner agent), and writes:

`<audit-dir>/phase0_cass_findings_summary.md`:

```markdown
# Top 5 patterns to look for in this audit

Based on the cass mining and the exemplar-repo patterns, the audit should specifically look for:

1. **<Pattern>** — appears in <which exemplar repos>; signal in target: <which inventory rows likely match>; refactor sketch: <link to pattern bundle>
2. ...

# Top 3 patterns the exemplar repos REJECTED

These look tempting but exemplar history rejected them. Don't propose them in plans without explicit user override.

1. **<Anti-pattern>** — rejected in <repo> by bead <id>; reason: <perf cliff, complexity, lost invariant>
2. ...

# Cross-host signal

CASS findings on `ts1` and `ts2` (which run different workloads than the audit machine) show: <observations relevant to target arch / target workload>.
```

This summary is loaded into context for Phase 4 classifier so classifications align with the exemplar-repo precedents.

---

## When CASS is not available

Skip Phase 0.5 mining; rely on the exemplar-miner agent reading source/git/beads directly from `/dp/*` on the local machine.

If even local exemplar repos aren't present, fall back to the pattern bundles in `references/patterns/` (which themselves were distilled from the exemplar-repo history). The bundles are the explicit Track A artifact for this skill.

---

## Mining hygiene

- **Don't mine for code, mine for reasoning.** Past code is in the exemplar repos. CASS adds the reasoning: why X, why not Y, what was tried first.
- **Tag every quote by host + session timestamp + project**, so a reviewer can re-find it.
- **Don't cargo-cult patterns.** A pattern that worked in `/dp/rich_rust` (SIMD) may be wrong for the current target's workload. Mining surfaces candidates; the audit's own measurement decides.
- **Refresh per audit.** CASS is appended to over time; mining from 6 months ago misses recent learning.

---

## Bandwidth-conscious option

For an `audit-only` quick run, the full per-host query pack is overkill. Trim to:

```bash
cass search "unsafe to safe"                         --robot --limit 30   # localhost only
cass search "miri stacked borrows fix"               --robot --limit 20   # localhost only
cass search "$primary_pattern_for_this_project"      --robot --limit 30   # per-shape
```

Where `$primary_pattern_for_this_project` is picked by Phase 0 detection:
- FFI-heavy → `"FFI shim safe wrapper"`
- SIMD-heavy → `"std::simd portable migration"`
- async-runtime → `"Pin::new_unchecked refactor"`
- general → `"isomorphic safe rewrite"`

The trimmed pack costs ~30 cass calls instead of ~150. Use when the user wants speed over depth.
