# PROJECT-TYPES.md — Per-Shape Defaults

The skill is designed for Rust projects of any shape. Phase 0 detects the shape and picks a template that adjusts partition, tier, and emphasized pattern bundles.

---

## Single binary crate

**Detection.** `Cargo.toml` has `[[bin]]` or top-level `src/main.rs`; no `[lib]`; not a workspace.

**Default partition.** One agent per top-level `src/<module>` directory or per significant module file. For small crates (<5 modules), a single agent does Phase 1+2 for the whole project.

**Default tier.** Solo or Pair.

**Emphasis bundles.**
- [40-MACRO-GENERATED-UNSAFE.md](../patterns/40-MACRO-GENERATED-UNSAFE.md) — binaries often pull in `clap`-derive, `serde`-derive, `tokio`-macros which can expand to unsafe.
- [70-UNINIT-AND-TRANSMUTE.md](../patterns/70-UNINIT-AND-TRANSMUTE.md) — common in parsers and config loaders.
- [00-CANONICAL-UNAVOIDABLE.md](../patterns/00-CANONICAL-UNAVOIDABLE.md) — terminal control, signal handlers, process-level FFI.

**Typical (A) sites.** Signal handlers (`libc::signal`), terminal-mode setters (`libc::tcsetattr`), the program-entry rust-specific stuff.

**Typical (C) opportunities.** Hand-rolled string parsers using raw pointers (swap for `&[u8]` + `std::str::from_utf8_unchecked` → `from_utf8` with proper UTF-8 validation).

---

## Single library crate

**Detection.** `Cargo.toml` has `[lib]` or default `src/lib.rs`; no `[[bin]]` for the public API; usually has rustdoc + `#![deny(unsafe_code)]` aspirations.

**Default partition.** One agent per top-level `src/<module>`.

**Default tier.** Pair.

**Emphasis bundles.**
- [10-POINTER-MIGRATIONS.md](../patterns/10-POINTER-MIGRATIONS.md) — libs use generic + lifetime trickery; raw pointers often live here.
- [50-SEND-SYNC-IMPLS.md](../patterns/50-SEND-SYNC-IMPLS.md) — every `unsafe impl Send/Sync` on a `pub` type is on the soundness surface.
- [40-MACRO-GENERATED-UNSAFE.md](../patterns/40-MACRO-GENERATED-UNSAFE.md) — derive macros for type-level zero-copy patterns.
- [60-FFI-PATTERNS.md](../patterns/60-FFI-PATTERNS.md) — if the lib has any C-binding aspirations.

**Soundness-surface emphasis.** Every `pub fn`, `pub struct`, `pub trait`, AND every `pub use` re-export. Library crates are about contract; the soundness surface IS the API.

**Typical (A) sites.** `Pin::new_unchecked` for self-referential types exposed via `pub`; `core::hint::unreachable_unchecked` for proven-exhaustive matches in hot paths.

**Typical (C) opportunities.** `unsafe impl Send for FooHandle` where `FooHandle` has been refactored to not own a raw pointer anymore — the impl is dead code.

---

## Workspace (≤10 members)

**Detection.** Top-level `Cargo.toml` has `[workspace]` with up to ~10 members.

**Default partition.** One agent per crate. Phase 1+2 owned by the per-crate agent; Phase 3 synthesis is the single global view.

**Default tier.** Squad.

**Emphasis bundles.** All bundles activate; emphasis on cross-crate soundness surface (which pub APIs in crate A reach unsafe in crate B?).

**Workspace-specific in Phase 3.** Build `audit/synthesis/cross-crate-soundness.md` showing:
```
PUB API: crate_a::Handle::frob
REACHES (in crate_a): site-0142 (block in src/internal.rs)
REACHES (in crate_b via dep): site-1031 (in crate_b::sys::raw_call)
INVARIANT FROM crate_b: ptr is non-null and valid for 'a
ENFORCED BY: crate_a constructs via crate_b::Sys::register; lifetime tied to 'a
```

**Coordination.** Use [MCP Agent Mail](../../../agent-mail/SKILL.md) file reservations per crate to prevent two agents from clobbering each other when refactor clusters span crates.

---

## Workspace (>10 members)

**Detection.** Top-level `Cargo.toml` has `[workspace]` with >10 members, OR explicit `members = [...]` listing many directories.

**Default partition.** One agent per `[workspace.members]` group — groups defined by directory naming convention or by `Cargo.toml`'s `workspace.metadata`.

**Default tier.** Swarm.

**Emphasis.** Same as smaller workspace plus:
- `dependency-soundness` mode often runs concurrently with the workspace audit.
- Cross-crate refactor clusters become MORE important; one safe wrapper might subsume sites across 6 member crates.
- Use beads with `--depends-on` to model cross-crate refactor ordering.

**Operational note.** Run the orchestrator under [NTM](../../../ntm/SKILL.md) when the swarm exceeds 6 concurrent agents. The orchestrator monitors via [vibing-with-ntm](../../../vibing-with-ntm/SKILL.md).

---

## Polyrepo

**Detection.** Multiple separate git repos that depend on each other; not a single Cargo workspace.

**Two strategies:**

### Strategy 1 — clone + treat as workspace.

Clone every repo into a temp directory; write a `Cargo.toml` workspace that includes them via `path = "../repo-X"`; run a single audit.

Advantages: cross-repo soundness surface is captured.
Disadvantages: cargo-geiger may double-count; cross-repo refactor PRs are coordinated by the user.

### Strategy 2 — per-repo audits + meta-synthesis.

Run one `audit-only` per repo. Then a meta-synthesis agent reads every repo's `audit/synthesis/soundness-surface.md` AND `audit/synthesis/refactor-clusters.md` and produces a single `meta-soundness-surface.md` highlighting cross-repo invariants.

Advantages: each repo's audit is independently committable; user can land them at their own pace.
Disadvantages: cross-repo refactor clusters are harder to coordinate; some unsafe at the seam may go uncaught.

**Default.** Strategy 2 unless the user has explicit cross-repo refactor authority.

---

## FFI-heavy crate

**Detection.** `Cargo.toml` dep on `libc`, `windows-sys`, `nix`, `core-foundation`, `bindgen`-output, or `extern "C"` blocks in `src/`.

**Default partition.** One agent per `extern` block OR per FFI-bound module.

**Default tier.** Pair / Squad.

**Emphasis.** [60-FFI-PATTERNS.md](../patterns/60-FFI-PATTERNS.md) dominates. The (A) bucket will be large — that's expected. The work is HARDENING, not removal:

- Every FFI surface gets a written boundary contract.
- Every `extern "C" fn` callable FROM C has `#[no_mangle]` AND a panic-handler wrapper to convert Rust panics into C-side error codes (Rust unwinding through `extern "C"` is UB).
- Every `extern "C" { fn foo(...) }` call gets a thin safe wrapper named `foo_safe` (or similar) that establishes the boundary invariants.

**Refactor opportunity.** Group the FFI calls under a single `mod sys` whose API is the thin safe wrapper; the rest of the crate sees only the safe API. Sometimes a `cargo-geiger` count of 200 becomes 12 after this kind of factoring, even though no `unsafe` was removed — it's been clustered.

**Exemplar.** `/dp/frankenlibc/src/sys/` — every FFI surface is in one place with a single safe-wrapper per call.

---

## SIMD-heavy crate

**Detection.** `Cargo.toml` dep on `std::simd` (unstable), `wide`, or `Cargo.toml` uses `target_feature` aggressively; or `src/` has `use core::arch::x86_64::*` etc.

**Default partition.** One agent per target architecture (`x86_64`, `aarch64`, `wasm32`, …).

**Default tier.** Pair / Squad.

**Emphasis.** [20-SIMD-AND-PERF.md](../patterns/20-SIMD-AND-PERF.md) dominates. The (B) bucket will be large; the `safe-only` feature is the main deliverable.

**Standard refactor sequence per SIMD site.**

1. Try `std::simd` (portable, requires nightly).
2. Try `wide` (stable, more limited operations).
3. Try autovectorization-friendly safe loop (LLVM may vectorize without intrinsics).
4. Measure all three against `std::arch` baseline on every target the crate ships.
5. Pick the safest that meets the perf budget.
6. The `std::arch` version stays behind `#[cfg(not(feature = "safe-only"))]`.

**Exemplar.** `/dp/rich_rust` had hand-written `_mm_loadu_si128` loops; refactored to `std::simd::u8x16` with a `wide` fallback; safe-only feature ships the autovec safe loop at 0.9× the perf of the SIMD path on canonical workloads.

---

## Async-runtime crate

**Detection.** Crate is `tokio` / `async-std` / `glommio` / `monoio` / `embassy` itself, OR a custom async runtime; OR a crate that exposes `Pin`-projected types in `pub` API.

**Default partition.** One agent per `Pin`-projection cluster.

**Default tier.** Squad.

**Emphasis.** [80-PIN-PROJECTIONS.md](../patterns/80-PIN-PROJECTIONS.md) dominates. The (A) bucket will include the runtime's core; (C) opportunities cluster around external-facing Pin types where `pin-project` / `pin-project-lite` could replace hand-written `unsafe impl Unpin` patterns.

**Loom suite mandatory.** Every concurrency-touching site has a loom model.

**Exemplar.** `/dp/mcp_agent_mail_rust/src/ws/stream.rs` has `Pin::new_unchecked` for a self-referential WebSocket reader; the (A) classification documents why `pin-project` doesn't cover the self-reference; the SAFETY comment names the field-level invariants.

---

## Allocator / arena crate

**Detection.** Crate impls `GlobalAlloc`, `Allocator` (unstable), or provides `Bump`-style arena types; or pulls in `bumpalo`, `slab`, `typed-arena`, `mimalloc-rs`.

**Default partition.** One agent per allocation strategy (e.g., per `mod`).

**Default tier.** Squad.

**Emphasis.** [00-CANONICAL-UNAVOIDABLE.md § allocator-identity](../patterns/00-CANONICAL-UNAVOIDABLE.md#allocator-identity) dominates. Miri stacked-borrows mode is mandatory.

**Specific concerns.**
- `Layout`-related transmutes are usually (A): `Layout::from_size_align_unchecked` is unsafe-by-construction.
- Arena pointers are usually (A) inside the arena impl AND (C) in callers that should switch to safe `bumpalo::Vec` etc.
- A `GlobalAlloc` impl has unique stacked-borrows interactions — miri's `-Zmiri-tree-borrows` may accept patterns stacked rejects.

**Exemplar.** `/dp/frankenfs/src/alloc/slab.rs` — `GlobalAlloc::alloc` is (A); the public `Slab::new` is safe; the in-crate users of `Slab` had a (C) cluster swapped to safe arena ownership.

---

## Forbid-soundness

**Project signals.** `#![forbid(unsafe_code)]` at the crate root (`src/lib.rs` / `src/main.rs`) AND/OR `[lints.rust] unsafe_code = "forbid"` in `Cargo.toml`. The phase loop collapses dramatically because in-tree unsafe is structurally absent.

**Recommended posture.**

- **Partition.** Single-agent (or pair for big workspaces). There are no in-tree sites to enumerate per-site; the work is all global synthesis.
- **Tier.** Solo. Adding more agents doesn't help when there's nothing to fan out across.
- **Phases.** 1 → 3 → skip 4–6 → 7 (tailored harness) → 8 (file dep-hygiene + harness-wiring beads) → 9 → 10. See SKILL.md § Mode variants row for `forbid-soundness`.
- **Main bundles.** `00-CANONICAL-UNAVOIDABLE` (for the dep-side allocator + signal-hook + FFI patterns) + `40-MACRO-GENERATED-UNSAFE` (for the compiler-emitted derive output that `cargo expand` surfaces — see § Compiler-emitted derive output (rustc 1.97-nightly+)) + the soundness-protocol references.

**What the audit produces.**

1. **In-tree forbid-airtightness proof.** Four checks:
   - `src/lib.rs` (or `src/main.rs`) has `#![forbid(unsafe_code)]`.
   - `Cargo.toml` has `[lints.rust] unsafe_code = "forbid"`.
   - Zero `#[allow(unsafe_code)]` overrides anywhere in `src/`, `tests/`, `benches/`, `build.rs`.
   - Zero source-level `unsafe (fn|impl|trait|extern|{)` declarations.

2. **Macro-expanded accounting.** `cargo expand --lib` is grepped for `\bunsafe[[:space:]]+(fn|impl|trait|extern|\{)`. Matches are categorized: `unsafe impl ::core::clone::TrivialClone for T {}` (built-in derive perf opt-in), `unsafe { ::core::intrinsics::unreachable() }` (built-in match-arm unreachability proof), or `other`. `other` should be small (typically just string-literal / comment matches); a growing `other` signals a new derive macro emitting unsafe and needs investigation.

3. **Dep-side soundness surface.** Direct dependencies characterized for their unsafe usage class (heavy / moderate / minimal / none) AND reachability through the project's public API. `cargo geiger` baselines are the canonical numerical artifact; install it for full fidelity.

4. **Tailored verification harness.** Drop `assets/verify-forbid-soundness.sh.template` into `<audit-dir>/verify.sh`, customize the four env vars at the top (`CRATE_ROOT_FILE`, `GEIGER_BASELINE_FILE`, `EXPAND_OTHER_BUDGET`, `RUN_TESTS`), and wire into CI or run on a cadence.

5. **Bead candidates** (typical low-priority follow-ups):
   - Install `cargo-geiger`; freeze a baseline.
   - Replace `once_cell::sync::Lazy` → `std::sync::LazyLock` (if MSRV ≥ 1.80).
   - Confirm forbid status of sibling/transitive deps (`rich_rust`, `toon_rust`, etc.).
   - Investigate replacing async HTTP/TLS deps with simpler blocking alternatives (`reqwest` → `ureq` etc.) if usage is occasional.

**Anti-patterns to avoid in this mode.**

- Don't run miri / loom / fuzz / mutants against the in-tree code — there's no unsafe to verify, so they're noise. Save them for the rare regression where new unsafe sneaks in.
- Don't propose `safe-only` feature flags — there are no (B) sites to gate.
- Don't propose `unsafe impl Send/Sync` audits — there are no manual impls.
- Don't expand `cargo expand` output into the inventory as classifiable sites — they're (A) by definition (built-in derives) and bulk-listing them muddies the report.

**Exemplar.** This skill's first invocation, on `beads_rust` v0.2.10 (2026-05-14). The full audit ran in ~20 minutes, produced `<audit-dir>/AUDIT_SUMMARY.md` + 8 candidate beads + a runnable `verify.sh` that passes today, and discovered four scriptable improvements upstream (now landed in this release). See `/data/projects/beads_rust/.unsafe-audit/` for the worked example.

---

## Special-case detections

| Project signal | Adjustment |
|----------------|------------|
| `forbid(unsafe_code)` already declared, but build fails when unsafe is added | Crate is in good shape; usually a `verify-only` mode |
| `unsafe_code = "deny"` lint config; many `#[allow(unsafe_code)]` opt-outs | `audit-only` with attention to opt-outs |
| `bindgen` build script | FFI-heavy + macro-generated-unsafe overlay (bindgen output is full of unsafe) |
| `wasm-bindgen` crate | FFI-heavy + the JS-side ABI is a special invariant (see 60-FFI-PATTERNS.md §wasm) |
| `embedded`-targeted (no_std) | Smaller `std::*` surface; emphasis on volatile + interrupt-handler patterns |
| `proc-macro` crate | macro-generated-unsafe overlay; the proc-macro itself may have unsafe |
| `build.rs`-heavy | Phase 1 must `cargo expand` BOTH pre-build-script and post-build-script outputs |

---

## Adjustment matrix at a glance

| Shape | Partition | Tier | Main bundle | Soundness-surface care |
|-------|-----------|------|-------------|------------------------|
| bin | per-mod | Solo/Pair | 40-MACRO + 00-CANONICAL | Low (no library API) |
| lib | per-mod | Pair | 10-POINTER + 50-SEND-SYNC | High (every pub item) |
| ws ≤10 | per-crate | Squad | All | High + cross-crate |
| ws >10 | per-group | Swarm | All | High + cross-crate, NTM |
| polyrepo | per-repo | Swarm | All | Meta-synthesis |
| FFI-heavy | per-extern-block | Pair/Squad | 60-FFI | Medium (FFI invariants) |
| SIMD-heavy | per-target | Pair/Squad | 20-SIMD | Low (perf-bucket) |
| async-rt | per-pin-cluster | Squad | 80-PIN | High (Pin contract) |
| allocator | per-strategy | Squad | 00-CANONICAL §allocator | High (UB blast radius) |
| forbid | single-agent | Solo | 40-MACRO + 00-CANONICAL §allocator+FFI | Dep-side only (in-tree is empty) |
