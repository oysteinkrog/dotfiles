# Harmonization — Best-of-All-Worlds Synthesis Across Branch Variants

> **The conceptual centerpiece of this skill.** A stash is one diff: pick or drop. A pile of branches is N diffs that overlap on the same files in incompatible ways. The job is **not** to choose the right branch; it is to **recover the strongest current implementation of every contested file** by inspecting every variant, naming each piece's intent, and synthesizing the result on top of canonical's architecture.

This file is the methodology behind the `◇ HARMONIZE` operator and the Phase 7 `harmonization_plan.md` artifact. If a reader skips this file and tries to run the skill, they will reduce it to "stash-janitor for branches" and lose the entire point. See [SKILL.md](../SKILL.md), the third `>` block at the top ("The conceptual leap from git-stash-janitor"), and Axiom 1.

---

## 1. Why Harmonization, Not Picking

**Picking is the wrong primitive.** When five `agent-cleanup-pass-*` branches all touch `src/util/logger.rs` because five parallel agents tried to harden the same module, every branch usually has *something worth keeping*: one branch added a null-arg guard, a second tightened the length cap, a third introduced a redaction pattern, a fourth fixed a thread-safety bug, the fifth has stale work that's now dead. If the skill picks one branch and drops the rest, four pieces of real defensive work are lost.

**Why:** Axiom 1 in [SKILL.md](../SKILL.md):

> **Axiom 1 — Harmonize, don't pick.** For any file touched by more than one non-protected branch, the job is NOT to choose between competing variants. The job is to inspect every variant (canonical's, each branch's, each dirty worktree's), reason about each part's intent, and synthesize the strongest current implementation on top of canonical's architecture.

**Why:** the [stash-janitor sibling skill](../../git-stash-janitor/SKILL.md) doesn't have to make this move because a stash is a single diff against a known parent. There is no "synthesize across stashes" because stashes don't normally collide on the same file in interleaved-intent ways — and when they do, pick-or-drop is usually fine because there are typically two or three. With branches, collisions of 5+ variants on the same hot file are routine in agent-swarm aftermath. Pick-or-drop fails by orders of magnitude.

**Symptom that you skipped harmonization:** the user opens the rationalization branch's diff against canonical, sees `src/util/logger.rs`, recognizes one branch's hardening, and asks "where's the redaction pattern from `feature/redact-secrets`?" If you can't answer "it was harmonized into the same file at hunk N", you needed Phase 7 and didn't run it.

**The cognitive move from stash-janitor to here:**

| stash-janitor | branch-rationalization |
|---------------|------------------------|
| One diff per stash | N diffs per branch + dirty-worktree variants |
| Apply or drop | Inspect every variant, identify intent, synthesize |
| Conflicts handled by 3-way merge | Conflicts are the *expected* shape of every contested file |
| Pick-best-stash for duplicates | Combine non-overlapping intents from multiple branches into one synthesis |
| Phase 6 = apply | Phase 7 = harmonize, Phase 8 = apply harmonized result |

---

## 2. The Variant Matrix Structure

The variant matrix is the deliverable of Phase 7's `◇ HARMONIZE` operator: one matrix per contested file (any file touched by ≥2 non-protected branches OR by ≥1 non-protected branch + ≥1 dirty worktree). The matrix is what the user reviews before any synthesis lands.

### Columns

For one file `<path>`:

| Column | Content | Source |
|--------|---------|--------|
| **variant** | `canonical` / `<branch-slug>` / `worktree:<sanitized-path>` | Inventory |
| **head sha** | Full commit SHA at the variant's tip; `WT-DIRTY-<timestamp>` for dirty worktrees | `branches.tsv` / `worktrees.tsv` |
| **signatures** | Function signatures, type signatures, public-API names introduced or changed in `<path>` for this variant | Fingerprint extraction (see [OPERATOR-LIBRARY.md `✦ FINGERPRINT`](OPERATOR-LIBRARY.md)) |
| **hunk summary** | Bullet list of hunks at coarse granularity ("added null-arg guard", "tightened length cap to 4 KiB", "added redaction regex"), one bullet per logical change | Manual reading of `git diff <merge-base>..<branch> -- <path>` |
| **tests/fixtures** | Test files and fixture files that this variant adds or modifies AND that exercise the changed code in `<path>` | `branches.tsv:touched_files` cross-referenced with the project's test layout |
| **identified intent** | One or more of: `defensive` / `refactor` / `test` / `fixture` / `type-narrowing` / `error-handling` / `performance` / `naming` (see Section 3) | The harmonization-planner subagent |
| **proposed synthesis** | Either "preserve verbatim", "compose with <other-variant-slug>'s <intent>", "supersede <other-variant-slug> (newer + strictly stronger)", or "skip (stale / divergent-refactor)" | Subagent reasoning, user-reviewable |
| **confidence** | 0.0–1.0; <0.7 forces user decision in Phase 7 review | Subagent self-assessment |
| **risks** | Free-text: "depends on `Logger::new` taking 2 args; canonical has 3" / "fixture file name collides with canonical's naming convention" | Subagent reasoning |

### Rows

One row per variant. Always include `canonical` first. Then one row per non-protected branch that touched `<path>`. Then one row per dirty worktree that has uncommitted changes to `<path>`. Order: canonical → branches by chronological tip date (oldest first) → worktrees alphabetical by sanitized path.

### Example (sketch — see Section 7 for a full worked example)

```
file: src/util/logger.rs

variant                          | head sha | signatures                | hunk summary                                                | tests/fixtures              | intent              | proposed synthesis                                                                | conf | risks
---------------------------------|----------|---------------------------|-------------------------------------------------------------|-----------------------------|---------------------|-----------------------------------------------------------------------------------|------|-------
canonical                         | a1b2c3d  | log(level, msg)           | (no change; baseline)                                       | tests/log_basic.rs          | (baseline)          | base of synthesis                                                                 | —    | —
agent-cleanup-pass-3              | b3c4d5e  | log(level, msg)           | + null-arg guard at top                                     | tests/log_null.rs (new)     | defensive           | adopt the null-arg guard; lift the new test                                       | 0.92 | none
feature/length-cap                | c5d6e7f  | log(level, msg)           | + length cap → 4 KiB on msg                                 | tests/log_length.rs (new)   | defensive           | compose with the null-arg guard; lift the new test                                | 0.94 | none
feature/redact-secrets            | d7e8f90  | log(level, msg)           | + redact_secrets(msg) before write                          | tests/log_redact.rs (new)   | defensive           | compose with the null-arg + length guards; lift the new test                      | 0.91 | regex perf — micro-bench OK
worktree:data-projects-foo--wt-3 | WT-DIRTY-... | log(level, msg, ctx)  | function-signature change: msg → (msg, ctx)                  | none yet                    | refactor            | DO NOT compose — divergent-refactor; surface to user                              | 0.45 | major API change; revert tests
```

That table is the user-reviewable artifact in `harmonization_plan.md`.

---

## 3. Intent Taxonomy

Every hunk in a variant is classified as one of eight intents. The intent determines composition rules (Section 4).

| Intent | What it looks like in a diff | How it composes |
|--------|------------------------------|-----------------|
| **defensive** | Added input validation, null-checks, bounds-checks, length-caps, redaction, escape-on-input, sanity-asserts | **Composes additively** with other defensive checks. Three branches each adding a different defensive check on the same function compose into one function with all three checks layered in entry order (most-restrictive last) |
| **refactor** | Function-extraction, file-split, rename, type-renaming, replacing `if-else` with `match`, switching from `Vec<u8>` to `Bytes` | **Does NOT compose.** Pick the strongest single refactor; rebase other branches' content into its shape. If two branches do incompatible refactors of the same code, that is a `divergent-refactor` and Phase 7 surfaces it instead of synthesizing |
| **test** | New test files; new test functions in existing test files | **Always additive.** Lift every novel test from every variant. Conflicts only on file-name collisions; resolve by giving each test a distinct name in the synthesis |
| **fixture** | New fixture files (golden output, sample input, snapshot data); modifications to existing fixtures | **Additive for new fixture files.** For modifications to the *same* fixture file, examine carefully — fixture diffs are usually evidence of a real semantic change in the code, and the harmonization plan must explain which variant's modification is correct |
| **type-narrowing** | Changing `&str` → `&NonEmptyStr`, `i64` → `NonZeroI64`, introducing newtype wrappers, replacing `Option<T>` with `T` after a guard | **Composes with everything.** Type-narrowings strictly increase guarantees. The strongest set of narrowings from across variants is the synthesis. Watch for narrowings whose construction site is on a different branch from the call site |
| **error-handling** | Changing `unwrap()` → `?`, introducing custom error types, error-context wrapping, wrapping in `anyhow::Context` | **Composes if error types are compatible.** If branch A introduces `enum LoggerError { ... }` and branch B introduces `anyhow::Error`, pick the typed enum (stronger guarantees) and rebase B's call sites onto it. If both branches introduce different bespoke error enums, that's a `divergent-refactor` |
| **performance** | Inline-cache, batch-buffer, lock-free swap, replacing `Vec` with `SmallVec`, threading-model change | **Composes if independent.** Two branches optimizing different code paths compose. Two branches optimizing the *same* code path with incompatible strategies do not — pick the one with measured benchmarks (or surface to user if neither has them) |
| **naming** | Rename of internal symbols (function names, variable names, module names) | **Picks one.** When both branches rename the same symbol to different names, surface to user; this is usually orthogonal to the real harmonization but matters for downstream import compatibility |

### Identifying Intent in Practice

For each hunk in each variant, ask:

1. **Does the hunk add a check that prevents bad input from being processed?** → defensive
2. **Does the hunk reorganize existing code without adding new behavior?** → refactor
3. **Is the hunk in `tests/`, `test/`, `_test.rs`, `*.test.ts`?** → test
4. **Is the hunk in `fixtures/`, `testdata/`, `golden/`, a `.snap` file?** → fixture
5. **Does the hunk change a type signature to express tighter invariants?** → type-narrowing
6. **Does the hunk change `Result`/`Option` flow or introduce/refine error types?** → error-handling
7. **Does the hunk change algorithmic complexity, memory layout, or concurrency primitives?** → performance
8. **Does the hunk only change identifier names without semantic change?** → naming

A hunk can have multiple intents (e.g., a refactor that also introduces type-narrowing); the matrix records all of them and synthesis follows the strictest composition rule (refactor wins over narrowing — narrowing rebases onto the chosen refactor).

### Intent Hierarchy When Variants Disagree

When a single hunk has variant A claiming `defensive` and variant B claiming `refactor` for the same code, the resolution priority is:

1. `defensive` and `type-narrowing` always survive — they're additive guarantees
2. `test` and `fixture` always survive
3. `error-handling` survives if compatible; otherwise the stronger error model wins (typed enum > anyhow > unwrap)
4. `refactor` and `performance` are the only intents that can fully replace each other; pick the strongest
5. `naming` is the most negotiable — adopt the canonical-aligned name when in doubt

---

## 4. Synthesis Principles

The principles below are how the harmonization-planner subagent decides what the "best-of-all-worlds" actually is. They are derived from Axioms 1, 4, 6 and from the operator card `◇ HARMONIZE` ([OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md)).

### 4.1 Preserve the strongest example of each intent

For each intent category present in the variants, identify the strongest single instance and preserve it verbatim where possible. The "strongest" criteria, in order:

1. **Tightest guarantee.** A length-cap of 4 KiB is stronger than a length-cap of 64 KiB. A `NonZeroU32` is stronger than `u32`.
2. **Most-recently-authored.** Among equally-strong checks, prefer the most recent — the agent that wrote it had the latest knowledge of the codebase.
3. **Tested.** A check with a regression test in its variant is stronger than the same check without one (the test proves intent).
4. **No regressions on canonical.** If the strongest check breaks an existing canonical test, it's not the strongest; the synthesis must adapt it.

**Why:** Axiom 4 — "Beneficiary-style coherence: all five layers tell the same story." A synthesis that drops a defensive check the user expected, or that picks a weaker variant when a stronger one was available, breaks the recovery story.

### 4.2 Defensive checks compose

Given three branches each adding one defensive check (null-arg, length-cap, redaction-pattern), the synthesis adds **all three** at the function entry, in increasing order of restrictiveness — null first (cheapest, eliminates the largest input class), then length, then redaction.

```
fn log(level: Level, msg: &str) -> Result<()> {
    if msg.is_empty() {                                    // ← from agent-cleanup-pass-3
        return Err(LoggerError::EmptyMessage);
    }
    if msg.len() > MAX_LOG_MSG_BYTES {                     // ← from feature/length-cap
        return Err(LoggerError::MessageTooLong(msg.len()));
    }
    let msg = redact_secrets(msg);                         // ← from feature/redact-secrets
    write_log_entry(level, &msg)
}
```

Each check survives because each one rejects a *different* class of bad input.

### 4.3 Refactors don't compose — pick the strongest, rebase the rest

If branch A refactors `log` from a free function to a method on `Logger`, and branch B refactors `log` from synchronous to async, the synthesis cannot do both arbitrarily — they may interact. Pick one (whichever has stronger evidence of correctness — tests, benchmarks, downstream call sites that already adopted it), then rebase the *content* of the other branch (its defensive checks, its tests, its fixtures) into the chosen refactor's shape.

If both refactors are independently strong and orthogonal (rare), compose them. If they conflict (the more common case), flag as `divergent-refactor` (Section 5).

**Why:** A refactor changes the *shape* of the code; layering two incompatible shapes produces nonsense. The skill's job is to surface this and let the user pick. Per AGENTS.md "No Script-Based Changes", the synthesis is authored by the Edit tool, not generated.

### 4.4 Tests are additive

Lift every novel test from every variant onto the synthesis. Test files that don't exist on canonical land directly. Test files that already exist on canonical receive the variant's new test functions appended (resolve any function-name collisions by giving each variant's test a distinct name — `test_log_null_arg`, `test_log_length_cap`, `test_log_redacts_secrets` — even if the original variants all called theirs `test_log_input_validation`).

**Why:** Tests are encoded *intent*. Throwing one away because another variant already has "a test on this code" loses coverage on a specific failure mode.

### 4.5 Fixtures are additive

New fixture files land. Modifications to *existing* fixture files require careful inspection: the modification is usually evidence of a real semantic change, and the matrix must record which variant's modification is correct (or whether a synthesis of the modifications is correct — e.g., a snapshot whose top half came from one branch's change and bottom half from another's).

If two variants modified the same fixture in mutually-exclusive ways and neither change is clearly correct, surface to user.

### 4.6 Type-narrowing usually composes with everything

Type-narrowings strictly increase guarantees. If branch A narrowed `arg: &str` to `arg: &NonEmptyStr` and branch B narrowed `count: i64` to `count: NonZeroI64`, the synthesis takes both narrowings. Construction sites get adapted to produce the narrowed types.

The one exception: a narrowing on branch A that conflicts with a refactor on branch B (e.g., A narrows the type of a parameter that B removed in its refactor). In that case, the narrowing is rebased onto whatever the refactor produced — typically as a narrowing on the new parameter, or as a check inside the new code path.

### 4.7 Error-handling composes if the error types are compatible

If both variants use `anyhow::Error`, their error-handling improvements compose. If both use `Result<T, std::io::Error>`, they compose. If one uses a typed enum and another uses `anyhow`, prefer the typed enum (stronger guarantees) and rebase the `anyhow` variant's call sites onto the enum.

If both variants introduce different *bespoke* error enums (`LoggerError` on one branch, `LogError` on another), that is a `divergent-refactor` — surface to user.

### 4.8 Performance composes only when independent

Two performance optimizations on **different** code paths compose freely. Two performance optimizations on the **same** code path with incompatible strategies (lock-free vs. fine-grained mutex; SmallVec vs. arena) do **not** compose; pick the one with measured benchmark evidence in its variant. If neither variant has benchmarks, surface to user.

### 4.9 Naming picks one

When two variants rename the same symbol to different names (`format_log` vs. `render_log`), the synthesis picks one — preferring the name that's already used elsewhere on canonical, or the more conventional name in the project's idiom. Naming is the most negotiable intent and rarely causes harmonization failures by itself.

---

## 5. When NOT to Harmonize

Some collisions are *not* harmonization material. They are flagged `divergent-refactor` in `triage.tsv` and surfaced to the user verbatim. Harmonization is **never** auto-attempted across architectural disagreement.

### Symptoms that say "do not harmonize"

| Symptom | Why harmonization fails | What to do |
|---------|-------------------------|------------|
| Two branches implement the same feature with **fundamentally different state machines** (one event-driven, one polling-loop) | The shape of the code is the disagreement, not the surface | Surface both designs to the user; ask which they want to keep; the loser's tests/fixtures may still be lifted onto the winner's design |
| Two branches use **different storage layouts** for the same data (one column-oriented, one row-oriented) | The data layout *is* the design; you can't synthesize a hybrid without inventing a third architecture | Surface to user; the rationalization branch lands the chosen design; the loser's content lives only in the bundle |
| Two branches use **incompatible concurrency primitives** for the same shared resource (mutex vs. channel; threadpool vs. async) | The choice ripples through the entire call graph; layering produces deadlocks or races | Surface to user; pick one wholesale |
| Two branches introduce **different external dependencies** for the same purpose (`tokio` vs. `async-std`, `serde_json` vs. `simd-json`) | Adding both is a tech-debt accumulation; picking neither loses both branches' work | Surface to user; whichever the user picks gets the synthesis; the loser's call sites get rebased onto the winner |
| Branch A **deletes a module** that branch B **extends**; both have ≥3 commits of meaningful work | Reverting one is reverting at least three commits' worth of intent | Surface to user as `divergent-direction`; do not auto-resolve |
| The collision is on **generated code or auto-formatted regions** | Synthesis would mean re-running the generator; the diff is meaningless | Treat the variant whose generator-input changed as canonical; regenerate; lift only manual edits to non-generated regions |

### The synthesis discipline

When in doubt, **flag rather than synthesize**. The harmonization plan's confidence column for any synthesis row must be ≥0.7 to land without explicit user OK. Anything below 0.7 forces a Phase 7 user review before Phase 8 may run.

**Why:** Axiom 4 — "If a Phase 3 byte-equality check disagrees on even one entry, the run is unsafe — halt." The same coherence principle applies to harmonization: if the planner isn't confident about a synthesis, the synthesis is unsafe and Phase 7 halts on it.

---

## 6. The Synthesis Discipline (How Synthesis Actually Lands)

Synthesis is *not* a `git merge` and is *not* a `git cherry-pick` and is **never** a `sed`/`awk` script. It is the Edit tool, applied by an agent, on the rationalization branch, with a commit message that cites every source.

### 6.1 Synthesis commits land via the Edit tool, NEVER sed/awk

Per AGENTS.md "No Script-Based Changes":

> NEVER run a script that processes/changes code files in this repo. Brittle regex-based transformations create far more problems than they solve.

The synthesis is read by a human or an agent, the Edit tool is invoked, the resulting file is verified to compile, the project's test/typecheck/lint suite is run, and only then does the commit land. Cross-link to [ANTI-PATTERNS.md A14 / W11](ANTI-PATTERNS.md#w11-script-based-source-mutation-sedawk-for-conflict-resolution).

### 6.2 Commit messages cite source branches and explain why each hunk came from where

A synthesis commit's message is *not* "harmonize logger.rs". It explicitly names every source and every intent. Template:

```
recover defensive logger hardening from 3 branches; harmonized

src/util/logger.rs:
  + null-arg guard from agent-cleanup-pass-3 (b3c4d5e)
    intent: defensive — rejects empty messages (was a real prod bug)
  + length-cap guard from feature/length-cap (c5d6e7f)
    intent: defensive — caps messages at MAX_LOG_MSG_BYTES (4 KiB)
  + redact_secrets() call from feature/redact-secrets (d7e8f90)
    intent: defensive — strips API keys / passwords before write
  + tests/log_null.rs from agent-cleanup-pass-3
  + tests/log_length.rs from feature/length-cap
  + tests/log_redact.rs from feature/redact-secrets

Composed in order most-permissive → most-restrictive (null → length → redact)
so cheap rejections happen first. All three checks survive because each rejects
a different class of bad input.

Source-branch backups:
  refs/branch-rationalization-backup/agent-cleanup-pass-3
  refs/branch-rationalization-backup/feature-length-cap
  refs/branch-rationalization-backup/feature-redact-secrets
```

The user reading `git log` on the rationalization branch can answer "where did this hunk come from?" without leaving the commit message.

### 6.3 The harmonization plan is a user-reviewable artifact BEFORE any synthesis commit lands

Phase 7 produces `harmonization_plan.md` containing every variant matrix. Phase 7's exit gate is the user reviewing this file and explicitly OK'ing it (per the `⚠ CONFIRM` operator). Only then does Phase 8 invoke the synthesis path of `apply-keeper.sh` to produce the actual commits.

If the plan changes (user overrides a synthesis row, or the planner re-runs after Phase 8 `⊞ RE-FINGERPRINT` flips a verdict), Phase 7 re-emits the plan and re-asks for sign-off on the changed rows.

**Why:** Axiom 14 — "Authorization is per-plan, verbatim, recorded." A synthesis that lands without the user seeing the plan first is an unauthorized change to contested files, no matter how good the synthesis is.

### 6.4 Synthesis runs the project's quality gates per-keeper

After the Edit-tool synthesis is in place, but before the commit, the project's `cargo test` / `bun tsc --noEmit` / `pytest` etc. runs (per [SKILL.md](../SKILL.md) Polish Bar dimension "Per-apply gates" and Axiom 13). If gates fail, the synthesis is broken and the commit does not land; surface to user. Cross-link to [FAILURE-MODES.md F22](FAILURE-MODES.md#f22-phase-8-commit-fails-because-of-a-pre-commit-hook).

---

## 7. Worked Example — Logger Harmonization Across Three Branches

**Scenario:** five `agent-*` branches and two non-agent branches. Three of the five touch `src/util/logger.rs` with the following intents:

- `agent-cleanup-pass-3` — added null-arg guard (defensive); added `tests/log_null.rs`
- `feature/length-cap` — added length-cap guard at 4 KiB (defensive); added `tests/log_length.rs`
- `feature/redact-secrets` — added `redact_secrets(msg)` call (defensive); added `tests/log_redact.rs`

Canonical's `src/util/logger.rs::log` is:

```rust
pub fn log(level: Level, msg: &str) -> Result<()> {
    write_log_entry(level, msg)
}
```

### 7.1 The variant matrix (Phase 7 output)

```
file: src/util/logger.rs
columns: variant | head sha | signatures | hunk summary | tests/fixtures | intent | proposed synthesis | conf | risks

canonical              | a1b2c3d | log(level, msg) -> Result<()>     | (baseline)                                      | tests/log_basic.rs       | (baseline)  | base of synthesis                                                     | —    | —
agent-cleanup-pass-3   | b3c4d5e | log(level, msg) -> Result<()>     | + null-arg guard at function entry              | + tests/log_null.rs      | defensive   | adopt the null-arg guard verbatim; lift the new test                  | 0.92 | none
feature/length-cap     | c5d6e7f | log(level, msg) -> Result<()>     | + length-cap MAX_LOG_MSG_BYTES = 4096          | + tests/log_length.rs    | defensive   | compose with null-arg guard; lift the new test                        | 0.94 | const should live next to log()
feature/redact-secrets | d7e8f90 | log(level, msg) -> Result<()>     | + redact_secrets() call before write            | + tests/log_redact.rs    | defensive   | compose with null-arg + length guards; lift the new test              | 0.91 | regex perf — micro-bench OK
```

All three intents are `defensive` and all three apply at the function entry. They compose (Section 4.2). All three signatures match canonical. Confidence is high across the board. Synthesis is straightforward.

### 7.2 The synthesis diff

```diff
--- a/src/util/logger.rs
+++ b/src/util/logger.rs
@@ -1,5 +1,18 @@
+const MAX_LOG_MSG_BYTES: usize = 4096;
+
 pub fn log(level: Level, msg: &str) -> Result<()> {
+    if msg.is_empty() {
+        return Err(LoggerError::EmptyMessage);
+    }
+    if msg.len() > MAX_LOG_MSG_BYTES {
+        return Err(LoggerError::MessageTooLong(msg.len()));
+    }
+    let msg = redact_secrets(msg);
-    write_log_entry(level, msg)
+    write_log_entry(level, &msg)
 }
```

Plus three new test files lifted verbatim from their source branches.

### 7.3 The commit message

```
recover defensive logger hardening from 3 branches; harmonized

src/util/logger.rs:
  + null-arg guard from agent-cleanup-pass-3 (b3c4d5e)
    intent: defensive — rejects empty messages
  + length-cap (4 KiB) from feature/length-cap (c5d6e7f)
    intent: defensive — caps messages at MAX_LOG_MSG_BYTES
  + redact_secrets() call from feature/redact-secrets (d7e8f90)
    intent: defensive — strips API keys / passwords before write

Composition order (most-permissive → most-restrictive): null → length → redact.

tests added:
  tests/log_null.rs       (from agent-cleanup-pass-3)
  tests/log_length.rs     (from feature/length-cap)
  tests/log_redact.rs     (from feature/redact-secrets)

All three checks survive because each rejects a different class of bad input.

Source-branch backups:
  refs/branch-rationalization-backup/agent-cleanup-pass-3
  refs/branch-rationalization-backup/feature-length-cap
  refs/branch-rationalization-backup/feature-redact-secrets
```

### 7.4 What happened to the source branches

After the synthesis lands on `branch-rationalization-2026-05-07`:

- The three source branches' content for `src/util/logger.rs` is now reachable via the rationalization branch.
- Their backup refs remain (Phase 3 created them; Phase 10 doesn't touch them).
- Phase 8's `⊞ RE-FINGERPRINT` re-runs across all remaining triage candidates; if any other branch was relying on `agent-cleanup-pass-3`'s null-arg pattern as a fingerprint, that fingerprint now resolves on the rationalization branch and the dependent row gets the `superseded-during-apply` apply-log status (the canonical marker for "another keeper covered this content mid-Phase-8"; see `apply_log.tsv` schema in [PHASES.md § Phase 8](PHASES.md#phase-8-rationalization--apply-sequential-60240-min)).
- The branches themselves (the refs `refs/heads/agent-cleanup-pass-3` etc.) are deleted in Phase 10's gated cleanup, but only after fresh-eyes verification (Phase 9) and verbatim user authorization. Cross-link to [RECOVERY-RECIPES.md R1](RECOVERY-RECIPES.md#r1-i-regret-deleting-a-branch).

---

## 8. Edge Cases

### 8.1 One branch reverts a portion that another branch extends

**Symptom:** branch A reverts a function `parse_v1_protocol` (deletes it). Branch B extends `parse_v1_protocol` (adds a v1.1 case).

**Resolution:** look at the *intent* of the revert. If branch A's revert is part of a larger refactor that replaces v1 with v2 (`parse_v2_protocol`), and branch B's extension is on v1, then the resolution is `divergent-direction` — surface to user. If branch A's revert was a mistake (no replacement, no other commits), then branch B's extension wins and the synthesis re-introduces `parse_v1_protocol` with B's changes.

### 8.2 A fixture file appears in both with different contents

**Symptom:** `tests/fixtures/parse_input.json` exists on canonical at version V0; branch A modified it to V1; branch B modified it to V2.

**Resolution:** read both modifications. If V1 and V2 modify *different* sections of the JSON (V1 added a top-level `version: 2` key, V2 added a new test case at the end), synthesize a V3 that includes both modifications. If V1 and V2 modify the *same* section in incompatible ways (V1 changed `expected_output` to one value, V2 changed it to a different value), surface to user — the underlying code change is the disagreement.

### 8.3 One branch deletes a file that another branch modifies

**Symptom:** branch A deletes `src/legacy.rs`. Branch B modifies `src/legacy.rs` (adds a deprecation warning).

**Resolution:** branch A's deletion is the stronger signal *if* its commit message and accompanying changes show the file is genuinely obsolete (the call sites have moved elsewhere). Branch B's deprecation warning is a softer version of the same intent. Synthesis: take A's deletion. If A's deletion is a mistake (no migration, call sites still use `legacy.rs`), surface to user as `divergent-direction`.

### 8.4 Binary blobs collide

**Symptom:** branch A and branch B both modified `assets/logo.png`.

**Resolution:** binary blobs cannot be harmonized at the byte level. Surface to user with both versions accessible (each variant's blob is in `<bundle>/branches/<slug>/diff-vs-merge-base.diff` with `--binary`). User picks one or supplies a third blob. The synthesis row records "binary collision; user-resolved" with the chosen blob's source.

### 8.5 The same fingerprint appears on two branches but with different signatures

**Symptom:** branch A introduces `redact_secrets(msg: &str) -> String`. Branch B introduces `redact_secrets(msg: &str, patterns: &[Regex]) -> String`.

**Resolution:** B's signature is strictly more general. Adopt B's signature in the synthesis; the call sites that came from A get adapted to pass a default patterns list (which is whatever A's hard-coded version was using internally).

### 8.6 A branch's content already landed on canonical via a squash-merge

**Symptom:** `git cherry -v <canonical> <branch>` shows all `-` lines for the relevant commits. The branch's intent is on canonical even though `git log` doesn't show ancestry. (Per [SKILL.md](../SKILL.md) Axiom 17.)

**Resolution:** the branch is `superseded` (or `already-merged`); it is **not** harmonization material. The intent is already on canonical. If a later branch extends that intent, the extension goes through harmonization but the `superseded` branch does not.

### 8.7 The harmonization-planner subagent's confidence is below 0.7

**Resolution:** the row is flagged in `harmonization_plan.md` with confidence shown. Phase 7 surfaces this to the user verbatim and asks for a decision. Options: (a) accept the planner's proposal as-is, (b) override with a different synthesis the user describes, (c) flag the file for `divergent-refactor` and skip it. The user's choice is recorded in `user_overrides.tsv`.

### 8.8 A dirty worktree variant has the strongest defensive check

**Symptom:** the user's currently-dirty worktree at `/data/projects/foo--wt-3` has uncommitted changes to `src/util/logger.rs` that include the strongest length-cap (a 1 KiB cap, even tighter than `feature/length-cap`'s 4 KiB cap).

**Resolution:** the dirty-worktree variant is treated as a first-class row in the variant matrix. Its `head sha` is `WT-DIRTY-<timestamp>`. Per [SKILL.md](../SKILL.md) Axiom 12, the skill never disturbs a dirty worktree, but it can *read* from it and lift the content. The synthesis cites the worktree by its sanitized path; the dirty state is preserved in `<bundle>/worktrees/<sanitized>/unstaged.diff` so the user can recover it independently. The user reviews the harmonization plan and decides whether the dirty-worktree variant lands.

---

## 9. Phase 7 Invocation — How the Harmonization-Planner Subagent Runs

Phase 7 is invoked after Phase 6 freezes the triage. The harmonization-planner subagent (`subagents/harmonization-planner.md`) does the following:

1. **Read** `triage.tsv`. Identify every file that appears in the `touched-files` column for ≥2 non-protected branches OR for ≥1 non-protected branch + ≥1 dirty worktree. These are the contested files.
2. **For each contested file**, build the variant matrix (Section 2). Pull `git diff <merge-base>..<branch> -- <path>` for each variant, extract signatures, summarize hunks, identify intent (Section 3), assess confidence.
3. **Apply synthesis principles** (Section 4) to propose a synthesis. If any variant's intent is `refactor` or `performance` and not all variants agree, evaluate Section 5 to determine if the file is `divergent-refactor`.
4. **Write** `harmonization_plan.md` with one section per contested file. Include the variant matrix, the proposed synthesis, the proposed commit message, and the per-row confidence.
5. **Block** until the user reviews the plan and either OKs it as-is, overrides specific rows (recorded in `user_overrides.tsv`), or flags rows as `divergent-refactor` (skipped from auto-synthesis; surfaced to user in Phase 8 conflict context).
6. **Hand off to Phase 8** with the approved plan. Phase 8 calls `scripts/apply-keeper.sh` with `--strategy harmonized-synthesis` for each approved row; the script invokes the Edit tool on the synthesis content; the per-apply gates run; the commit lands on the rationalization branch.

### Parallelism

For Comprehensive and Council modes (≥20 contested files), Phase 7 fans out to per-file harmonization-planner workers in parallel. The merge step is single-threaded (one author of `harmonization_plan.md`) but the per-file matrix builds run in parallel.

### Council-mode triangulation

For Council mode, the per-file matrix is evaluated by Codex / Gemini in addition to Claude. The three models' proposed syntheses are compared; agreement raises the row's confidence; disagreement forces a user decision regardless of confidence. Cross-link to the SKILL.md "Mode Variants" table.

---

## 10. Cross-References

- [SKILL.md](../SKILL.md) — Axiom 1, Axiom 4, Axiom 6, Axiom 14; the Polish Bar's "Harmonization fidelity" dimension; the `◇ HARMONIZE` operator
- [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) — full operator card for `◇ HARMONIZE` with prompt module
- [ANTI-PATTERNS.md](ANTI-PATTERNS.md#w4-skipping-the-harmonization-plan-when-2-branches-collide) — what NOT to do when files collide
- [FAILURE-MODES.md](FAILURE-MODES.md#f14-two-branches-collide-on-the-same-file-with-incompatible-defensive-checks) — the failure-mode entry that points back here
- [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) — how files end up tagged for harmonization (the `divergent-refactor` verdict, the `partially-novel` verdict)
- [WORKED-EXAMPLES.md](WORKED-EXAMPLES.md) — full annotated end-to-end example including a multi-file harmonization
- [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) — where each variant's source diff lives in the bundle, so the harmonization plan can cite it
- [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md#r1-i-regret-deleting-a-branch) — how a harmonized branch's source content is recovered if the user wants the original variant back

---

## 11. The Mantra

> **Inspect every variant. Identify each intent. Synthesize the strongest combination. Author via Edit. Cite every source. Run the gates per-commit. Land on the rationalization branch. Let the user merge at their pace.**

If a step in that mantra is skipped, the run is not a harmonization; it's a pick-or-drop with extra steps, and the user is paying the cost of a Phase 7 they didn't actually get.
