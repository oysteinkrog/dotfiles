# GLOSSARY.md — Terms You'll Encounter

For non-Rust experts + Rust folks not familiar with the soundness audit vocabulary.

---

## Rust-specific (assumed background)

| Term | Plain-English meaning |
|------|----------------------|
| **`unsafe`** | A Rust keyword. Marks code where the compiler isn't guaranteeing memory safety; the programmer is. Most Rust code is "safe" — the compiler checks. `unsafe` blocks are the exception. |
| **UB (Undefined Behavior)** | The C/C++/Rust spec doesn't define what happens. In practice: segfault, garbage data, security vulnerability. The audit's job is to prevent UB. |
| **Soundness** | A property of code: "this code never causes UB on any input." A `pub fn` is sound if no caller can use it to trigger UB. The audit certifies soundness. |
| **Borrow checker** | The part of the Rust compiler that prevents most memory bugs. Tracks who's reading vs writing each piece of data. `unsafe` bypasses some of its checks. |
| **`pub fn` / pub API** | Public Rust functions other crates can call. The "outside world" interface. |
| **FFI** | Foreign Function Interface — calling into C / C++ / system libraries from Rust. Always unsafe because the compiler can't see into the other language. |
| **Macro** | Code that writes code. `derive(Debug)`, `vec![]`, `println!`, etc. Some macros emit `unsafe` blocks invisibly. |
| **`Send` / `Sync`** | Traits indicating "this type can move between threads" / "this type can be shared across threads." Some unsafe code asserts these manually. |
| **`Pin`** | A wrapper that says "this value won't move in memory." Used for self-referential types. |
| **`Drop`** | A Rust trait for "what runs when this value is destroyed." Like a destructor in C++. |
| **Lifetime** | A label tracking how long a reference is valid (`'a`, `'static`, etc.). |

---

## The audit's three buckets

| Bucket | Plain-English meaning |
|--------|----------------------|
| **(A) STRICTLY_UNAVOIDABLE** | This `unsafe` HAS to stay. Rust can't express the safe form. Examples: calling into C, allocator implementations, signal handlers. The audit hardens these with better SAFETY comments + clippy lints. |
| **(B) PERF_ONLY** | A safe form exists but it's slower. The audit measures the perf difference; ships both versions behind a Cargo feature flag so users can opt for safe-only if they don't care about the speed. |
| **(C) REFACTORABLE** | A safe equivalent exists with the same perf and behavior. The audit drafts the safe code + a property-based test proving it matches. |

When in doubt, classify DOWN: (A) → (B) → (C). The audit's bias is toward "we can do better than unsafe."

---

## Verification tools

| Tool | What it does | How it helps |
|------|--------------|-------------|
| **miri** | A Rust interpreter that detects UB at runtime. Slow (interpreted) but catches everything in its model. Runs via `cargo +nightly miri test`. |
| **cargo-careful** | Native-speed runtime UB detection. Catches a subset of what miri catches but works on FFI-touching code miri can't run. |
| **loom** | Models concurrent code by exploring every possible thread interleaving within a budget. Catches data races + lost-update bugs that surface only under specific timing. |
| **cargo-fuzz** | Runs random/structured inputs at your code looking for panics + UB. Powered by libfuzzer. Time-limited (60s smoke / 1h soak). |
| **cargo-mutants** | Tests YOUR TESTS. Mutates your code (changes a `+` to `-`, etc.) and re-runs tests; if tests still pass with the mutation, your tests aren't actually pinning behavior. |
| **cargo-geiger** | Counts `unsafe` occurrences across your crate + dependencies. The audit tracks the count over time. |
| **cargo-expand** | Shows what macros expanded to. Surfaces unsafe code hidden inside `derive` macros. |
| **ast-grep** | A code search tool that understands AST structure (vs. grep which treats code as text). The audit uses it to find `unsafe` constructs reliably. |
| **kani** | A bounded model checker for formal verification. Symbolic-input proof that an invariant holds. Used for highest-stakes (C) sites. Most audits skip kani; some adopt it for ~5 critical sites. |

---

## Audit-specific terminology

| Term | Plain-English meaning |
|------|----------------------|
| **Site** | One specific `unsafe` block, `unsafe fn`, `unsafe impl`, etc. Each site gets a unique ID (`site-NNNN`) and its own write-up. |
| **Invariant** | A property that must be true for the unsafe to be sound. Example: "input slice is at least 16 bytes long." The audit names every invariant. |
| **Invariant chokepoint** | A single safe wrapper (function, trait, or type) that encapsulates the invariant shared by a cluster of unsafe sites. Once built, the surrounding sites collapse to safe calls through the chokepoint. Phase 3's refactor clusters are built around proposed chokepoints. |
| **Soundness surface** | The set of public APIs that, if misused, could trigger UB via internal unsafe code. The audit's job is to make this surface minimal + bounded. |
| **SAFETY comment** | A code comment (`// SAFETY: ...`) explaining why an unsafe block is OK. The audit verifies + hardens these. |
| **Falsifiable justification** | An (A) site's required write-up: "this is unavoidable BECAUSE X, and these alternatives FAIL for reasons Y, Z, W." A reviewer can attack the claim. If they can't, the (A) holds. |
| **Drift** | New unsafe sites appearing in the project after the baseline audit. Continuous mode catches drift nightly. |
| **Soundness debt** | The total "burden" of unsafe code still to address. Quantified via risk-scoring. Visualized in the soundness-debt dashboard. |
| **Bead** | An issue/task in the `beads_rust` (`br`) tracker. The audit converts its findings into a bead graph; the user works through them via `br ready`. |
| **Audit dir** | In-project folder (`<project>/.unsafe-audit/`). Nested git repo. All audit artifacts land here; existing project source files are read-only until the user approves a refactor. |
| **Git worktree** | A Git feature for working on multiple branches simultaneously without switching the main checkout. This skill forbids it; refactors use the active checkout or ordinary branches instead. |

---

## The phases

| Phase | What happens | How long |
|-------|--------------|----------|
| 0 | Set up the audit dir + ask the user a few questions | 1 min |
| 0.5 | Mine prior context (optional: cass + exemplar repos + git history) | 5–10 min |
| 1 | Enumerate every `unsafe` site | seconds-to-minutes per crate |
| 2 | Write up each site (what it does, what invariants it assumes) | minutes per site |
| 3 | Synthesize global views (which sites share invariants? which reach pub API?) | 5–10 min |
| 4 | Classify (A) / (B) / (C); iterate until quiet | 10 min – 1 hour |
| 5 | Plan: draft refactor code + tests | minutes per site |
| 6 | Adversarial reclassification: try to defeat each (A); iterate | 10 min – 1 hour |
| 7 | Fresh-eyes review of proposed rewrites + run the toolchain harness | 30 min – 2 hours |
| 8 | Convert plans into beads (issue tracker entries) | 5 min |
| 8.5 | (audit-and-refactor mode only) Implement approved plans in the active checkout; optionally open ordinary-branch PRs | hours-to-days per cluster |
| 9 | Build the verification harness | 5 min |
| 10 | Maintainer-empathy review: would I land this as the project owner? | 10–30 min |

Total: 30 min for a small lib (≤50 unsafe sites); 2–6h for a medium workspace; half-day+ for a polyrepo.

---

## Risk scoring

`RISK_SCORE = BLAST_RADIUS × LIKELIHOOD × DISCOVERABILITY`

Each dimension is 1–5. Total range: 1 (minimal) to 125 (CVE-worthy).

| Dimension | What it measures |
|-----------|-----------------|
| BLAST_RADIUS | If this site has a bug, how many downstream users get hit? Internal helper = 1; system-level (libc binding) = 5. |
| LIKELIHOOD | How likely is the SAFETY claim to be wrong RIGHT NOW? Recently-reviewed = 1; stale + drifting = 5. |
| DISCOVERABILITY | How easy is the bug to trigger? Internal fn with constrained input = 1; pub fn taking `&[u8]` with no fuzz target = 5. |

Sites order by score; the top-20% typically cover ~60–80% of the project's total risk.

---

## Modes

| Mode | When to use |
|------|------------|
| `audit-only` | Default. Reports only; no changes to your code. |
| `audit-and-refactor` | Report + user-approved safe refactors in the active checkout; PRs are optional ordinary-branch closeout. |
| `harden-incident` | Something specific is broken (CVE, miri finding, crash). Fix first, audit second. |
| `dependency-soundness` | Audit your dependencies' unsafe surface (the part your pub API reaches). |
| `verify-only` | Just set up the CI verification harness; skip the audit. |
| `pre-release-soundness-gate` | Before `cargo publish`. Strictest variant. |
| `dual-feature-migration` | Add a `safe-only` Cargo feature to your existing crate. |
| `triage` (fast-track) | 60-second enumeration + risk-score. No write-ups. |
| `dashboard-only` (fast-track) | Just regenerate the soundness-debt dashboard. |
| `drift-check` (fast-track) | Just check what changed since the baseline. |

---

## Other terminology you'll see

| Term | Meaning |
|------|---------|
| **`/dp/*`** (in docs) | The SKILL AUTHOR'S local paths for exemplar repos (`/dp/asupersync`, etc.). YOU don't have these. They're mentioned as case-study references, not paths you need. |
| **`css`, `csd`, `ts1`, `ts2`** | The SKILL AUTHOR'S remote machines for prior agent-session history (via `cass`). YOU don't have these either. The audit works without them. |
| **AGENTS.md** | A project-level file with rules for AI agents (don't delete files, don't force-push, etc.). The skill references your project's AGENTS.md if present; ignored if not. |
| **Operator** | A cognitive move the audit applies per site. There are 24 of them. They have glyphs (⊙, ⊕, ⊗, etc.) to differentiate. |
| **Cluster** | A group of sites sharing a common invariant or refactor pattern. The audit groups them for efficient refactoring. |
| **Polish bar** | The 12 criteria a site must satisfy before it exits Phase 5. The "minimum quality" line. |
| **Polish-bar dimension** | One of the 12 criteria (invariant-named / falsifiable-justification / etc.). |
| **Pre-existing UB** | UB found in code OUTSIDE the current refactor's scope. Filed separately so the refactor doesn't conflate "we made it worse" with "we found something old." |
| **Fresh-eyes** | A review pass where the reviewer hasn't seen the prior analysis. Catches things the original analyst missed. Run with three calibrated verbatim prompts. |
| **Adversarial** | Phase 6: an agent that DOESN'T see prior classifications tries to defeat each (A) and (C). If it succeeds, reclassify. |
| **`safe-only` feature** | A Cargo feature flag that builds the crate with zero unsafe in the perf path. The (B) bucket's primary deliverable. Downstream users opt in. |

---

## Acronyms

| Acronym | Expansion |
|---------|-----------|
| AST | Abstract Syntax Tree |
| ABI | Application Binary Interface |
| API | Application Programming Interface |
| CAS | Compare-And-Swap (atomic operation) |
| CI | Continuous Integration |
| CVE | Common Vulnerabilities and Exposures (numbered security ID) |
| FFI | Foreign Function Interface |
| MMIO | Memory-Mapped I/O |
| OOM | Out Of Memory |
| RCA | Root Cause Analysis |
| SIMD | Single Instruction, Multiple Data (vectorized ops) |
| TUI | Terminal User Interface |
| UB | Undefined Behavior |
| UTF | Unicode Transformation Format (UTF-8 = the most common encoding) |
| WSL | Windows Subsystem for Linux |

---

## When in doubt

Drop the term into the audit dir's `<audit-dir>/audit/synthesis/glossary-additions.md` as you encounter it; the audit can clarify in the next phase. Or look it up in:

- [Rust Reference](https://doc.rust-lang.org/reference/)
- [Rust Nomicon](https://doc.rust-lang.org/nomicon/) — for low-level / unsafe details
- [Rust API docs](https://doc.rust-lang.org/std/) — for stdlib types
- [LANGUAGE-REFERENCES.md](LANGUAGE-REFERENCES.md) — the audit's citation index
