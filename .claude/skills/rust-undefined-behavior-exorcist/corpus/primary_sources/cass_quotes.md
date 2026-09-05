# Cass Quote Bank — UB-Hunting Sessions (Verbatim)

Mined from cass (~3,324 conversations, 137k messages) across local + css + csd + ts1 indexes. Each quote has a stable anchor `Q-NNN`. Honest gap analysis at the end.

The mining preserves the user's *actual* working methodology, including its gaps — the skill teaches miri/loom/shuttle/Kani as the **upgrade path** layered onto the user's existing suspect-list + safety-notes-first ritual, not as a tradition we pretend already exists.

---

## Q-001: Beads-rust focused security & reliability audit

**Source:** `/home/ubuntu/.claude/projects/-data-projects/1bd88a79-…/subagents/agent-afc8c41.jsonl:1`, 2026-02-01
**Project:** beads_rust

**User prompt (verbatim):**
> Conduct a focused security and reliability audit of the beads_rust Rust codebase at /data/projects/beads_rust. Focus on:
>
> 1. SQL injection - check if all database queries use parameterized statements
> 2. Path traversal - check file operations for proper validation
> 3. Panic/unwrap misuse - check for unwrap() in non-test code
> 4. Resource handling - check for file/DB leaks
>
> For each issue found, provide:
> - File path and line numbers
> - Root cause
> - Severity (CRITICAL, HIGH, MEDIUM, LOW)
> - Fix suggestion
>
> Only report real issues that could cause problems, not theoretical concerns that are properly mitigated.

**Maps to:** ★ SUSPECT (the canonical suspect-list audit template).

---

## Q-002: Toon_rust 5-category audit including memory + concurrency

**Source:** `…/subagents/agent-ab025d0.jsonl:1`
**Project:** toon_rust

**User prompt (verbatim):**
> Conduct a thorough security and reliability audit of the toon_rust codebase at /data/projects/toon_rust. Focus on:
>
> 1. Input parsing vulnerabilities - command line parsing, file parsing
> 2. File I/O safety - path traversal, race conditions
> 3. Error handling - unwrap/expect misuse, silent failures
> 4. Memory safety - any unsafe blocks, buffer handling
> 5. Concurrency issues - race conditions, deadlocks
>
> For each issue found, provide:
> - File path and line numbers
> - Root cause explanation
> - Severity (CRITICAL, HIGH, MEDIUM, LOW)
> - Suggested fix
>
> Only report real issues, not theoretical concerns that are properly handled.

**Maps to:** ★ SUSPECT (5-category variant; "Memory safety" + "Concurrency issues" added).

---

## Q-003: Xf "look at recent commits especially"

**Source:** `…/subagents/agent-aa0e177.jsonl:1`
**Project:** xf

**User prompt (verbatim):**
> Deep code review of /data/projects/xf focusing on:
> 1. Error handling - unchecked errors, panics, silent failures
> 2. Race conditions - concurrent access, shared state
> 3. Resource leaks - file handles, DB connections, sockets
> 4. Security issues - SQL injection, command injection, path traversal
> 5. Logic bugs - off-by-one, wrong comparisons, edge cases
>
> Look especially at recent commits (embedding worker, daemon features). Report findings with file:line and severity. Skip test files.

**Maps to:** ✦ ISOLATE (audit-the-delta).

---

## Q-004: Frankensqlite mmap-SHM implementation with explicit SAFETY notes (the single best UB exemplar in the corpus)

**Source:** `…/subagents/agent-a1cb425ac8f627afa.jsonl:1` (file pruned; quote from indexed snippet)
**Project:** frankensqlite

**User prompt (verbatim, abridged):**
> Implement the mmap-based SHM layer for frankensqlite to fix multi-process WAL corruption (issue #19). This is the most critical correctness issue in the project.
>
> Based on the investigation, the key gaps are:
> 1. SHM regions backed by heap Vec instead of mmap
> 2. Locks simulated in-process instead of fcntl
> 3. shm_barrier is a noop instead of atomic fence
> 4. No SHM file created/opened
> ...
> ### CRITICAL SAFETY NOTES:
> - The mmap ShmRegion must use `unsafe` carefully — bound check every access
> - Send and Sync must be carefully considered for mmap pointers
> - Drop ordering matters: munmap before close(fd)
> - On macOS, MAP_SHARED + fcntl works differently than Linux for some edge cases — use POSIX-portable subset only
> - The existing MemoryVfs (in-memory backend) should NOT be affected — keep it using heap-backed ShmRegions

**Tool sequence (verbatim):**
```rust
fn shm_barrier(&self) {
    std::sync::atomic::fence(std::sync::atomic::Ordering::SeqCst);
}
```
```rust
let ret = unsafe { libc::fcntl(shm_fd, libc::F_SETLK, &flock) };
if ret < 0 { /* EAGAIN|EACCES -> ShmLockBusy */ }
```

**Outcome:** Committed as `b810842`. Agent summary noted: "Added `unsafe impl Send + Sync for MmapBacking`", "Drop ordering matters: munmap before close(fd)", "`std::sync::atomic::fence(SeqCst)` matching C SQLite's `__sync_synchronize()`".

**Maps to:** ☣ SAFETY-NOTES-FIRST (write the unsafe invariants in the prompt before any code is generated).

---

## Q-005: Frankensqlite WAL multi-process corruption exploration

**Source:** `…/subagents/agent-ad2d941cce90bed5f.jsonl:1` (pruned; indexed snippet)
**Project:** frankensqlite

**User prompt (verbatim, abridged):**
> Thoroughly explore /data/projects/frankensqlite to understand the WAL multi-process corruption issue (#19). Focus on:
>
> 1. **VFS SHM layer** — Find the VFS [SHM region code, lock implementation, barrier]
> ...

**Agent response excerpt (L75):**
> causes of WAL multi-process corruption:
> 1. **Missing WAL-index hash table updates in mmap region** - Processes map the SHM but don't coordinate hash table [updates]

**Maps to:** explore → spec → implement (three passes).

---

## Q-006: Pi_agent_rust three-fix specific-fix review

**Source:** `…/subagents/agent-a1c680bf023a8a965.jsonl:1`
**Project:** pi_agent_rust

**User prompt (verbatim):**
> Thoroughly review the three recent fixes in pi_agent_rust for bugs, errors, or issues.
>
> Fix 1: Read /data/projects/pi_agent_rust/src/interactive.rs and search for "downcast" to find the replacement for try_downcast. Check:
> - Is `is::<PiMsg>()` + `downcast::<PiMsg>().unwrap()` safe? Could it panic?
> - Is the pattern semantically equivalent to the original try_downcast?
> - Read the surrounding match/if block to ensure the logic flow is correct.
>
> Fix 2: ... [PROXY_ARGS bash 3.2 unbound-array idiom]
> Fix 3: ... [GitHub Actions submodule stub + macOS cross-compile]
>
> Report any bugs, issues, or concerns found.

**Maps to:** ★ SUSPECT (pre-stated panic hypothesis).

---

## Q-007: Asupersync Cx/cancellation correctness — named-failure-mode questions

**Source:** `…/subagents/agent-a535f204c5a354a71.jsonl:1` (pruned; cass view capture)
**Project:** asupersync

**User prompt (verbatim, excerpt):**
> Review all three asupersync changes with fresh eyes in /data/projects/asupersync/:
>
> **1. try_spawn_with_cx (#23)**
> Read `src/runtime/builder.rs`:
> - Find the new `spawn_with_cx` and `try_spawn_with_cx` methods
> - Does `try_spawn_with_cx` correctly create a child Cx in the root region?
> - Is the Cx properly linked to the runtime's task infrastructure?
> - **Could there be a race condition between Cx creation and task scheduling?**
> - Does the spawned task's Cx get cancelled when the runtime shuts down?
> ...
> **3. HttpClient cx parameter (#26)**
> - Is `cx: &Cx` added to ALL public methods? (count them)
> - Does `check_cx()` correctly check cancellation?
> - Are cancellation checks at EVERY I/O boundary?
> - **Could a cancelled Cx cause a resource leak (e.g., half-open connection)?**
>
> Report any bugs, race conditions, resource leaks, or API inconsistencies.

**Maps to:** ★ SUSPECT (Named-Failure-Mode variant — *don't* ask "is this correct?", name the failure mode).

---

## Q-008: Frankensqlite codegen.rs — local-invariant counter-example

**Source:** `…/subagents/agent-aa3dfa3019d2c30a6.jsonl:96` (live transcript)
**Project:** frankensqlite

**Agent's methodology (excerpt):**
> Every single `IfNot` call in the file uses `p3=1` EXCEPT the UPSERT WHERE clause at line 4612-4618 which uses `p3=0`. This is clearly a bug.

**Maps to:** ♦ COUNTER — find the property that holds N-1 times, point at the N-th violator.

---

## Q-009: Frankensqlite serial-type proptest scoping

**Source:** `…/subagents/agent-a9203fb.jsonl:1`
**Project:** frankensqlite

**User prompt (verbatim, excerpt):**
> Explore the frankensqlite project at /data/projects/frankensqlite to understand the serial type system and what property tests are needed.
>
> DO NOT modify any files. This is research only.
>
> Investigate:
> 1. Read crates/fsqlite-types/src/serial_type.rs ...
> 2. Check existing tests for serial types — what's already tested?
> 4. Check if proptest or quickcheck is already a dependency in Cargo.toml
> 5. Look at any existing property tests in the project for patterns to follow
> ...
> Return a concise report with:
> - SerialType enum definition and key methods
> - What's already tested
> - What testing framework is available (proptest/quickcheck)
> - Recommended property tests to add

**Maps to:** ✦ ISOLATE — when the user reaches for property testing it's `proptest`/`quickcheck`, NOT `miri`/`Kani`. The skill should respect this preference but offer the upgrade path.

---

## Q-010: Cass own BM25-fix review — edge-case-first

**Source:** `…/subagents/agent-ae1a5622654d7b99b.jsonl:1`
**Project:** coding_agent_session_search (cass itself)

**User prompt (verbatim, excerpt):**
> Fix 1 (issue #79 - BM25): ... check:
> - Is the SQL query correct? Are the JOINs right?
> - Is parameter binding safe (no SQL injection)?
> - Does the ORDER BY handle NULL created_at correctly?
> - Is the stable_hit_hash call using the right arguments?
> ...
> - Does the empty query detection work correctly in TantivySearchService::execute()?
> - **Is the per-agent quota logic in regroup_panes() correct? Could it panic on edge cases (0 groups, empty results)?**
> - **Does the startup SearchRequested trigger create any race conditions?**

**Maps to:** ★ SUSPECT (Edge-Case-First variant).

---

## Q-011..Q-012: Frankensqlite Deep-Audit prefix (recurring)

**Sources:** Multiple subagent files, indexed titles only (files pruned).
**Project:** frankensqlite

**User prompt (verbatim title, recurring across many sessions):**
> Deep audit of ALL extension crates in `/data/projects/frankensqlite/crates/`
> Deep audit of the SQL parser in FrankenSQLite. Read these files thoroughly and look for bugs

**Maps to:** ★ SUSPECT — the literal "Deep audit of <crate-path>" prefix is a corpus signature.

---

## Q-013: Frankenlibc TLS+arena unsafe-block change inspection (read-only delta)

**Source:** `…/subagents/agent-a702377.jsonl:1`
**Project:** frankenlibc

**User prompt (verbatim):**
> Examine the NEW uncommitted changes in /data/projects/frankenlibc. Do NOT edit any files.
>
> 1. Run `git -C /data/projects/frankenlibc diff --stat` to see scope
> 2. Run `git -C /data/projects/frankenlibc diff` to see the full diff
> 3. Run `git -C /data/projects/frankenlibc log --oneline -3`
>
> Modified files: crates/frankenlibc-core/src/pthread/tls.rs, crates/frankenlibc-membrane/src/arena.rs, …

**Maps to:** ✦ ISOLATE — **GAP exemplar**: high-UB-risk surface (TLS + arena) inspected without a miri pass. The skill should propose adding `cargo +nightly miri test` after this kind of inspection.

---

## Q-014..Q-017: Read-Only Delta Frame ritual (recurring across projects)

The literal phrase "do NOT edit any files" preceded by `git diff --stat` + `git diff` + `git log --oneline -5` appears in 5+ sessions. Acts as the **scope-fence** before any fix pass.

**Maps to:** ✦ ISOLATE (Read-Only Delta Frame).

---

## Q-018: Asupersync release-gate (cargo audit only, no miri)

**Source:** `…/subagents/agent-acbd33a28fb8d407f.jsonl:1`
**Project:** asupersync

**User prompt (verbatim, excerpt):**
> 2. Run `cargo audit` to check for vulnerabilities. If any are found, fix them (update the vulnerable dep, possibly bump MSRV in Cargo.toml if needed)
> 3. Run `cargo test` to verify everything passes. If tests fail, fix the issues.

**Maps to:** ✦ ISOLATE — **GAP exemplar**: release ritual is `cargo audit + cargo test`, not `miri + loom + cargo geiger`.

---

## Q-019: Per-project CARGO_TARGET_DIR isolation

**Source:** `…/subagents/agent-ab8a5da9e44016572.jsonl:1`
**Project:** asupersync

**User prompt (verbatim, excerpt):**
> CRITICAL: The environment has CARGO_TARGET_DIR=/data/tmp/cargo-target which is SHARED across projects. You MUST override it for every cargo command:
>   CARGO_TARGET_DIR=/tmp/cargo-target-asupersync cargo ...

**Maps to:** ☣ FIX-PREP — isolation harness, extends to MIRI_SYSROOT and fuzz corpus dirs.

---

## Q-020: Beads-rust two-fix review — "match the patterns used elsewhere"

**Source:** `…/subagents/agent-a8d6a8e8e65663e2f.jsonl:1`
**Project:** beads_rust

**User prompt (verbatim, excerpt):**
> Fix 1 (issue #74): … check:
> - Is the SQL query correct? Does it properly join tables?
> - Is the error handling correct?
> - Does it match the patterns used elsewhere in rebuild_blocked_cache_impl()?
> - **Could it produce duplicate inserts?**
> - **Is the blocker reference format consistent?**

**Maps to:** ♦ COUNTER (local-invariant question: "does it match the patterns used elsewhere?").

---

## Q-021: Pi_agent_rust prescriptive-fix prompt

**Source:** `…/subagents/agent-a5be8646b67b671ca.jsonl:1`
**Project:** pi_agent_rust

**User prompt (verbatim, excerpt):**
> 3. Installer has `PROXY_ARGS[@]` unbound variable with `set -u`
> …
> 2. Read /data/projects/pi_agent_rust/install.sh — find the PROXY_ARGS variable and initialize it as empty array before first use (add `PROXY_ARGS=()` near the top after set -u or before first use)

**Maps to:** ☣ FIX (prescriptive — describe the concrete edit in the prompt).

---

## Q-022: Mcp_agent_mail diff harvest (race-sensitive surface)

**Source:** `…/subagents/agent-a83fdc2e1ce0f514a.jsonl:1`
**Project:** mcp_agent_mail_rust

**User prompt (verbatim):**
> Get the full git diffs for all modified tracked files in /data/projects/mcp_agent_mail_rust. Run `git diff` to see all changes. Return a structured summary of what changed in each file, grouped logically.

**Maps to:** ✦ ISOLATE.

---

## Q-023: Mcp_agent_mail spoofing + lifecycle issue bug-claim verification

**Source:** `…/subagents/agent-a2f7dd3.jsonl:1`
**Project:** mcp_agent_mail

**User prompt (verbatim, excerpt):**
> Investigate four open issues on Dicklesworthstone/mcp_agent_mail. DO NOT make any code changes - just research and report back.
>
> ISSUE #99: "send_message allows sender_name spoofing -- no validation against registered identity" …
> For each issue:
> 1. Read the full issue body: `gh api repos/Dicklesworthstone/mcp_agent_mail/issues/NUMBER`
> 2. Look at the relevant source code in /data/projects/mcp_agent_mail/ or /data/projects/mcp_agent_mail_rust/
> 3. **Verify if the claimed bugs are real and still present**
> 4. **Check git log --since="2026-02-01" for recent fixes**

**Maps to:** ♦ COUNTER — bug-claim verification before acting on a reporter's claim.

---

## Q-024..Q-025: Read-only commit-message ritual (frankenlibc, frankensqlite)

**Source:** Multiple subagent files.

**User prompt (verbatim, excerpt):**
> I need to understand the changes in /data/projects/X to write a detailed commit message. This is a read-only investigation - do NOT edit any files.
>
> 1. `git -C /data/projects/X diff --stat`
> 2. `git -C /data/projects/X diff`
> 3. `git -C /data/projects/X log --oneline -5`

**Maps to:** ✦ ISOLATE — frames a change-set without committing to action; UB-relevant when applied to TLS/arena/mmap surfaces (which are the highest-UB-risk surfaces in frankenlibc + frankensqlite).

---

## Q-026: Frankensqlite diff-to-file handoff for oversized diff

**Source:** `…/subagents/agent-a203242.jsonl:1`
**Project:** frankensqlite

**User prompt (verbatim, excerpt):**
> Read the file at /home/ubuntu/.claude/projects/-data-projects/3c6e0f37-…/tool-results/toolu_01SkBRqPm2eDcBjT32hzhbCP.txt
>
> This is the full `git diff` + `git status` output for the `frankensqlite` repo. Analyze the changes and produce:
> 1. A list of logical commit groupings (which files go together and why)
> 2. For each group, a detailed commit message

**Maps to:** ✦ ISOLATE — diff-to-file indirection for oversized payloads.

---

## Q-027: Ultimate-bug-scanner exploration (skill author's own tool)

**Source:** `…/subagents/agent-a57bcc0.jsonl:1`
**Project:** ultimate_bug_scanner

**User prompt (verbatim, excerpt):**
> Explore the /data/projects/ultimate_bug_scanner project. I need to understand:
> 1. The project structure
> 2. How it currently handles output formatting (JSON, text, etc.)
> 3. What serialization patterns it uses (serde, custom formatters)
> 4. The main CLI interface and commands
> 5. What the scan output looks like
> 6. Test infrastructure

**Maps to:** the user has a "bug scanner" project but has not yet connected it to UB-specific tooling. **Gap exemplar.**

---

## Q-028: Frankenfs forbid-unsafe stance

**Source:** ts1 corpus, `cass search 'frankenlibc unsafe' --workspace ts1` L530 indexed snippet
**Project:** frankenfs

**Indexed snippet (verbatim):**
> impulse/step_response now propagate lfilter errors, `#![forbid(unsafe_code)]` on sparse crate

**Maps to:** ☣ FIX-PREP — per-crate `#![forbid(unsafe_code)]` is the user's default; per-crate opt-out only when physically required.

---

## Q-029: The Recurring Closing Phrase

**Source:** ts1 corpus, `cass search 'frankenlibc unsafe'` — `786fee45-…jsonl` repeated at L56, L65, L73, L80, L85, L91, L97.

**Indexed snippet (verbatim):**
> regressions, unsafe assumptions, missing tests, sloppy edge cases. Fix what you find before picking new work.

**Maps to:** ★ SUSPECT — the user's ritual closing scope phrase. Quote verbatim in operator-library templates.

---

## Q-030: Frankenfs cargo fuzz target convention

**Source:** ts1 corpus, `cass search 'cargo fuzz target'` — L10 indexed snippet
**Project:** frankenfs

**Indexed snippet (verbatim):**
> **Commit 3: feat(fuzz): add btrfs chunk mapping and ext4 checksum fuzz targets**
> - `fuzz/fuzz_targets/fuzz_btrfs_chunk_mapping.rs`
> - `fuzz/fuzz_targets/...`

**Maps to:** ☣ FIX — per-format `fuzz_<format>_<aspect>.rs` naming.

---

## Q-031..Q-033: Asupersync state-machine race audit (ts1 corpus)

**Source:** ts1, `cass search 'race condition rust'` — top hits

**Indexed snippets (verbatim):**
> 1. State machine correctness in distributed protocol
> 2. Race conditions in concurrent state

> | Generation race window | Notify | MEDIUM | Race Condition | 212-216 |
> | Cancellation race | Barrier | MEDIUM | Race Condition | 92-108

> 12. Race conditions
> For each finding:
> - State the exact line number(s)
> - Classify severity: CRITICAL / HIGH / MEDIUM / LOW

**Maps to:** ★ SUSPECT (12-category maximal variant); ✦ ISOLATE (race-window inventory table format).

---

## Q-034: Frankensqlite gemini-tier exploration of InodeTable

**Source:** `~/.gemini/tmp/frankensqlite/chats/session-2026-03-08T22-16-466c7bcd.json:129` (pruned; indexed snippet)
**Project:** frankensqlite

**Indexed snippet (verbatim):**
> InodeTable::get to reuse a canonical file descriptor. This is correct for POSIX fcntl locks, but it creates a leaking lock if a file is opened, locked …
> The "Process-Global Inode Table" Inefficiency: FrankenSQLite implements a `global_inode_table` to coalesce POSIX `fcntl` locks …

**Maps to:** ♦ COUNTER (gemini tier explores; Claude tier fixes — two-tier triangulation).

---

## Q-035: Sbh blocking-flock named-failure

**Source:** `~/.gemini/tmp/.../sbh-session.json:86` (pruned)
**Project:** storage_ballast_helper (sbh)

**Indexed snippet (verbatim):**
> `#[allow(deprecated)]
>          nix::fcntl::Flock::lock(file, nix::fcntl::FlockArg::LockExclusive).map_err(...)`
>
> It uses blocking lock.
>
> If `sbh ballast release` …

**Maps to:** ★ SUSPECT (named-failure: blocking-flock-deadlock).

---

## Q-036: Asupersync UnixVfs architecture statement

**Source:** `~/.gemini/tmp/.../session-2026-02-08.json:79` (pruned)
**Project:** asupersync

**Indexed snippet (verbatim):**
> Vfs/VfsFile), memory.rs (MemoryVfs with HashMap<PathBuf, Arc<Mutex<Vec<u8>>>>), unix.rs (UnixVfs via asupersync blocking I/O, fcntl F_SETLK, 5 lock levels …

**Maps to:** architectural fact for the skill's exemplar library.

---

# 12 Rituals That Recurred (Distilled)

| # | Ritual | Operator | Anchors |
|---|---|---|---|
| 1 | **Suspect-List Audit** — N numbered categories + "file:line + severity + fix" output + "only report real issues" disclaimer | ★ SUSPECT | Q-001, Q-002, Q-031, Q-033 |
| 2 | **Named-Failure-Mode Question** — "Could there be a race condition between X and Y?" rather than "is this correct?" | ★ SUSPECT (variant) | Q-006, Q-007, Q-010, Q-020 |
| 3 | **Local-Invariant Counter-Example** — find the property holding N-1 times, point at the N-th violator | ♦ COUNTER | Q-008, Q-020, Q-023 |
| 4 | **Safety-Notes-First** — write the unsafe invariants in the prompt before any code is generated | ☣ SAFETY-NOTES-FIRST | Q-004 |
| 5 | **Read-Only Delta Frame** — `git diff --stat` + `git diff` + "do NOT edit any files" before any fix pass | ✦ ISOLATE (Read-Only) | Q-013, Q-014, Q-017, Q-024, Q-025 |
| 6 | **Inline-Loop Sweep** — `for repo in X Y Z; do cd /data/projects/$repo; git diff ...; done` | ✦ ISOLATE (Fleet) | Q-016 (not shown but indexed) |
| 7 | **Diff-To-File Handoff** — write oversized diff to a file, then ask the next agent to read it | ✦ ISOLATE (Indirection) | Q-026 |
| 8 | **Per-Project CARGO_TARGET_DIR Isolation** — `CARGO_TARGET_DIR=/tmp/cargo-target-<proj>` for every command | ☣ FIX-PREP | Q-019 |
| 9 | **Default-Forbid Stance** — per-crate `#![forbid(unsafe_code)]` until physically required | ☣ FIX-PREP | Q-028 |
| 10 | **Bug-Claim Verification** — "Verify if the claimed bugs are real and still present" before acting on a report | ♦ COUNTER | Q-023 |
| 11 | **Two-Tier Triangulation** — gemini explores; Claude fixes | ☣ FIX (Two-Tier) | Q-004, Q-034 |
| 12 | **Ritual Closing Phrase** — "regressions, unsafe assumptions, missing tests, sloppy edge cases. Fix what you find before picking new work." | scope_phrase template | Q-029 |

---

# Documented Gaps (What the Skill Adds)

The user's captured cass corpus does NOT show any usage of:
- `cargo +nightly miri test` (zero verbatim invocations in 365 days)
- `MIRIFLAGS=...` (any setting)
- `loom::model!` / `shuttle::check_random!`
- `Kani` / `Prusti` / `Creusot` / `Aeneas`
- `TSan` / `ASan` / `MSan` / `LSan`
- `cargo-geiger` (mentioned zero times)
- `transmute MaybeUninit assume_init` (one hit, in a documentation reading)

The skill teaches these as the **upgrade path** layered onto the user's existing strong methodology. Each ritual above gets a paired miri/loom/sanitizer/kani "upgrade" recommendation in [OPERATOR-LIBRARY.md](../../references/OPERATOR-LIBRARY.md) and [TOOLING.md](../../references/TOOLING.md). The skill does NOT pretend these tools are already in use; it positions them as the natural extension of what the user is already doing well.

**Especially high-leverage entry points** (gaps the skill should aggressively close):

1. **After every Ritual 5 (Read-Only Delta Frame) on TLS/arena/mmap/fcntl code**, propose a miri pass. Specifically the frankenlibc `pthread/tls.rs` + `membrane/arena.rs` surface (Q-013).
2. **Convert Ritual 4 (Safety-Notes-First) to Safety-Notes-First + Loom-Model-First** for MmapBacking-shape types (Q-004). A 30-line loom model on `Drop` ordering would have caught the original bug class faster than the inspection prompt.
3. **Add `cargo +nightly miri test` to Ritual 8 (release-gate)** alongside `cargo audit` and `cargo test`.
4. **Wire `cargo-geiger` into Ritual 8** as a one-liner for surface trending.
5. **For every Ritual 4 SAFETY-NOTES-FIRST prompt, also require a regression test** — a property test or fuzz target that proves the invariant.

---

# Round-2 Anchors (Q-101..Q-802) — Depth-Mined From Ts1 / Exemplar Sessions

A second mining pass surfaced specific, narrower episodes that the round-1 anchors (Q-001..Q-036) glossed. These get their own `Q-NNN` IDs so the new round-2 reference files can cite them stably. Each entry below is a short paraphrase + the citing file(s) where the verbatim/derived prompt lives.

## Q-101 — Adversarial pointer fault-injection matrix
**Project:** frankenlibc. **Episode:** `adversarial_pointer_fault_injection_matrix_has_zero_false_negatives` — 100K probes across 4×4×4×3×2 axes, gated on zero false negatives. **Cited in:** [UB-TEST-MATRIX.md](../../references/UB-TEST-MATRIX.md), [CVE-ARENA-LAYOUT.md](../../references/CVE-ARENA-LAYOUT.md), [REMEDIATION-PRINCIPLES.md](../../references/REMEDIATION-PRINCIPLES.md), [UB-BEAD-LADDER.md](../../references/UB-BEAD-LADDER.md).

## Q-102 — SHM noop-barrier as soundness bug
**Project:** frankensqlite. **Episode:** *"Replaced noop `shm_barrier()` with `std::sync::atomic::fence(SeqCst)`"* plus 8 new tests across mmap / cross-handle / multi-region / cleanup / cross-process visibility. **Cited in:** [SHM-AND-FENCES.md](../../references/SHM-AND-FENCES.md), [HIDDEN-BARRIERS.md](../../references/HIDDEN-BARRIERS.md).

## Q-103 — Cancel-correctness as a peer UB lane
**Project:** asupersync. **Episode:** SOCKS5 connector lacked `cx: &Cx`, was uncancellable. Fixed by threading `cx` through 12 public `HttpClient` methods + 5 `check_cx(cx)?` boundaries (DNS / connect / TLS / redirect / proxy). **Cited in:** [CANCEL-CORRECTNESS.md](../../references/CANCEL-CORRECTNESS.md), [HIDDEN-BARRIERS.md](../../references/HIDDEN-BARRIERS.md), [RELEASE-FORWARD-ONLY.md](../../references/RELEASE-FORWARD-ONLY.md), [REMEDIATION-PRINCIPLES.md](../../references/REMEDIATION-PRINCIPLES.md).

## Q-201..Q-206 — Exemplar quotes (already in quote_bank.md)
See [`../quote_bank/quote_bank.md`](../quote_bank/quote_bank.md) for the full verbatim text. Summary:
- **Q-201** frankensqlite mmap+SAFETY contract; **Q-202** asupersync `RawWaker` choreography; **Q-203** frankentui compile-time-asserts; **Q-204** frankenfs Arc-count drop guard; **Q-205** mcp_agent_mail_rust UTF-8-safe replacement; **Q-206** pi_agent_rust shell trampoline replacing FFI.

## Q-301 — Origin/github worktree-remote convention
**Project:** frankensqlite. **Episode:** *"The frankensqlite 'ahead' is just because its `origin` is a local worktree; we already pushed to its `github` remote."* Named verification worktrees like `frankensqlite-bd-2yqp6-3-1-verify`. **Cited in:** [WORKTREE-PATTERNS.md](../../references/WORKTREE-PATTERNS.md).

## Q-401 — Fix-the-chokepoint
**Episode:** AWK END block kept, gated by `found` accumulator — the user's preference for fixing the single chokepoint rather than scattering checks at every caller. **Cited in:** [REMEDIATION-PRINCIPLES.md](../../references/REMEDIATION-PRINCIPLES.md), [HIDDEN-BARRIERS.md](../../references/HIDDEN-BARRIERS.md).

## Q-402 — Shape-sweep + checked operators
**Episode:** When a single arithmetic UB site is found, sweep the codebase for the same shape and replace with checked operators (`checked_add`, `wrapping_mul`, etc.) project-wide in the same pass. **Cited in:** [REMEDIATION-PRINCIPLES.md](../../references/REMEDIATION-PRINCIPLES.md), [HIDDEN-BARRIERS.md](../../references/HIDDEN-BARRIERS.md).

## Q-501 — Forward-only topological re-publish
**Episode:** When a transitive dep is yanked, re-publish dependents forward (new minor versions, bottom-up dep order) rather than back-porting to a `0.x.y` series. **Cited in:** [RELEASE-FORWARD-ONLY.md](../../references/RELEASE-FORWARD-ONLY.md), [REMEDIATION-PRINCIPLES.md](../../references/REMEDIATION-PRINCIPLES.md), [UB-BEAD-LADDER.md](../../references/UB-BEAD-LADDER.md).

## Q-601 — Modern `cargo-deny` form
**Episode:** `deny.toml` migration from deprecated `url = "https://..."` to modern `db-urls = ["https://..."]` plus `db-path` settings. **Cited in:** [CARGO-DENY-TEMPLATE.md](../../references/CARGO-DENY-TEMPLATE.md).

## Q-602 — Per-bead CVE artifact arena
**Project:** frankenlibc. **Episode:** `tests/cve_arena/results/bd-18qq.4/uaf_adversarial_detection.v1.json` — one results directory per bead, versioned JSON artifacts. **Cited in:** [CVE-ARENA-LAYOUT.md](../../references/CVE-ARENA-LAYOUT.md), [REMEDIATION-PRINCIPLES.md](../../references/REMEDIATION-PRINCIPLES.md).

## Q-701 — Frankensearch Miri-CI YAML
**Project:** frankensearch. **Episode:** GitHub Actions workflow with `continue-on-error: true`, `-Zmiri-disable-isolation`, `cargo miri test --lib`. Non-blocking signal job. **Cited in:** [MIRI-CI-TEMPLATE.md](../../references/MIRI-CI-TEMPLATE.md).

## Q-801 — Same-shape multi-site sweep
**Project:** frankensqlite. **Episode:** Float-modulo UB appeared in **two** code paths (VDBE `engine.rs::sql_rem` and MVCC `index_regen.rs::numeric_rem`); user fixed both in the same fresh-eyes pass. **Cited in:** [SHAPE-SWEEP.md](../../references/SHAPE-SWEEP.md), [REMEDIATION-PRINCIPLES.md](../../references/REMEDIATION-PRINCIPLES.md), and `subagents/shape-sweeper.md`.

## Q-802 — 5-step bead-ladder execution
**Episode:** The user's recurring shape for shipping a UB fix as a bead: (1) write the failing test, (2) write the fix, (3) cross-link to the same-shape sites, (4) update SAFETY comments + runbook, (5) gate convergence on the cross-linked sweep. **Cited in:** [UB-BEAD-LADDER.md](../../references/UB-BEAD-LADDER.md), [SHAPE-SWEEP.md](../../references/SHAPE-SWEEP.md), [REMEDIATION-PRINCIPLES.md](../../references/REMEDIATION-PRINCIPLES.md), and `subagents/shape-sweeper.md`.

**Audit note:** Q-101..Q-802 are derivative anchors — paraphrased from the verbatim cass episodes for re-citation. The verbatim text lives in the citing files. If you need the literal user message, run a fresh cass query on the project + tag combo above.
