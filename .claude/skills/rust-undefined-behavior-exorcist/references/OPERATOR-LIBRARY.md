# Operator Library — Cognitive Moves For UB Hunting

Polish-by-vibes doesn't work for UB. Each finding is driven through a fixed sequence of *operators* — small, named cognitive moves with explicit triggers, prompt modules, exit criteria, and failure modes. Adapted from `/operationalizing-expertise` Track A.

Use the operator name in workspace artifacts (e.g., "★ SUSPECT for F-007 at src/btree.rs:412") so reviewers can trace the cognitive path.

---

## ★ SUSPECT — flag a candidate UB site

**Trigger:** something feels off. The SAFETY comment is missing/weak; the `unsafe impl Send` has no visible synchronization; the FFI call takes a pointer of unclear provenance.

**Prompt module:**
> Read `<file:line>` and the 20 lines on each side. Is the unsafe operation actually sound? Specifically: (1) what invariant does it depend on; (2) where is that invariant enforced; (3) what happens if the invariant breaks. If you can't answer all three confidently in two sentences each, mark this site as `★ SUSPECT` and add a row to `phase2_findings_<bucket>.md`.

**Exit:** row added to `phase2_findings_<bucket>.md` with severity (`MUST-BE-UB` / `LIKELY-UB` / `SUSPICIOUS` / `CONTRACTUAL-BUT-DEFENSIBLE`).

**Failure mode:** marking everything `SUSPICIOUS` — defeats the purpose. Reserve `SUSPICIOUS` for sites where you have a specific reason but can't yet articulate it.

---

## ✦ ISOLATE — reduce to a minimal reproducer

**Trigger:** a `★ SUSPECT` site has graduated past triage and you want to prove the hypothesis.

**Prompt module:**
> Build the smallest standalone Rust program that exercises only the suspect operation. Strip every dependency. Strip every unrelated field. Strip every loop. The reducer is done when removing any further line either breaks the build or removes the suspect operation. Save it to `experiments/<exp-id>/repro.rs`.

**Exit:** `experiments/<exp-id>/repro.rs` exists and is ≤30 lines.

**Failure mode:** "minimal" reproducers that import the whole crate. Properly minimal means *no `Cargo.toml` deps that aren't strictly necessary*.

---

## ◐ REPRO — wrap as a runnable test

**Trigger:** `✦ ISOLATE` produced a repro; now make it executable under a chosen tool.

**Prompt module:**
> Wrap the reducer as either: (a) a `#[test]` runnable under `cargo +nightly miri test`, or (b) a `#[cfg(loom)] #[test]` runnable under loom, or (c) a `fuzz_target!` runnable under `cargo fuzz run`. Add the test to a Cargo manifest at `experiments/<exp-id>/Cargo.toml` if it's not already part of the source repo.

**Exit:** a single shell command runs the reproducer and produces a verdict.

---

## ⬡ INSTRUMENT — add flags / tracing to surface the failure

**Trigger:** `◐ REPRO` runs clean. The failure is real but hidden.

**Prompt module:**
> Add `MIRIFLAGS` / `RUSTFLAGS` / `tracing` / `eprintln!`s that maximize visibility into the suspect operation. Specifically: (a) for aliasing — add `-Zmiri-tree-borrows`; (b) for provenance — add `-Zmiri-strict-provenance`; (c) for alignment — add `-Zmiri-symbolic-alignment-check`; (d) for data races — switch to TSan with `--test-threads=1`. Re-run.

**Exit:** the failure manifests with a useful diagnostic, OR the finding is downgraded to `NO_EVIDENCE` after instrumenting every relevant tool.

---

## ⚠ ESCALATE — recruit a second opinion

**Trigger:** `⬡ INSTRUMENT` can't decide; conflicting signals; or the finding is high-stakes (custom allocator, custom lock-free data structure, public-API unsafe).

**Prompt module:**
> Invoke `/multi-model-triangulation` with the finding row, the reproducer, the instrumented run outputs, and the question: "Is this UB? If yes, which Rustonomicon bucket? If no, what additional experiment would refute the hypothesis?" Cross-reference responses; record consensus + dissent in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`.

**Exit:** triangulation verdict recorded.

---

## ⊕ REWRITE — enumerate isomorphic rewrites + pick

**Trigger:** finding is `CONFIRMED_UB`. Phase 8.

**Prompt module:**
> For this `CONFIRMED_UB` site, enumerate at least two isomorphic rewrites that eliminate the UB while preserving behavior. Consult [REMEDIATION-PATTERNS.md](REMEDIATION-PATTERNS.md). Score each candidate 0–4 on: correctness margin / performance delta / diff blast radius / reviewability / maintainability. Pick the winner. Record runners-up with their tradeoffs.

**Exit:** `phase8_remediation_plan.md` entry with chosen rewrite + runners-up + rubric scores + cross-reference to the proving experiment and the future regression experiment.

**Failure mode:** picking the first rewrite that compiles. The rubric exists to force a tradeoff conversation.

---

## ⊙ DEBOUNCE-FALSE-POSITIVE — confirm NO_EVIDENCE stays NO_EVIDENCE

**Trigger:** a finding came back `NO_EVIDENCE`. Verify the negative.

**Prompt module:**
> Re-run the experiment in a fresh workspace (no cached corpora, no warm fuzz coverage map). Re-run with the *complete* MIRIFLAGS matrix, not just the one used in Phase 3. Re-run with an inverted assertion (assert the UB *did* happen — does it fail clean?) to make sure the test would actually catch the bug.

**Exit:** finding closes as `NO_EVIDENCE` only after two fresh-eyes runs confirm absence; otherwise upgrade to `NEEDS_REFINEMENT`.

**Failure mode:** trusting a single Miri-clean run. Miri's coverage isn't exhaustive; rare schedules can hide races.

---

## ⊞ SOAK — long-running campaign

**Trigger:** Phase 11. The remediation candidate or the original UB needs proof at scale.

**Prompt module:**
> Design a 24-hour fuzz campaign / multi-day Miri run / 10⁴-iteration loom model for this finding. Specify: (a) corpus seed; (b) wall-time budget; (c) success criterion (e.g., "zero crashes in 24h" or "zero Miri errors across the full test suite under every MIRIFLAGS combination"); (d) checkpoint cadence (where intermediate state lands). Dispatch via `rch exec --`.

**Exit:** `phase11_soak_designs.md` entry exists; `rch` job dispatched and tracked.

---

## ⌘ REDUCE — shrink the safe shell when the remediation is too costly

**Trigger:** a `⊕ REWRITE` remediation passes correctness but the perf delta is unacceptable.

**Prompt module:**
> The chosen rewrite is correct but slower. Identify the *smallest* unsafe core that captures the perf-critical path, then wrap it in the safest possible API. The unsafe core must: (a) have a 3+ line SAFETY comment naming every invariant; (b) be unit-tested under the full MIRIFLAGS matrix; (c) be loom-modeled if concurrent; (d) be fuzzed if it parses bytes. Document the runtime cost of each safety layer you added vs. removed.

**Exit:** revised `phase8_remediation_plan.md` entry; rubric scores updated.

---

## Cass-Mined Operators (the user's existing rituals)

These operators are mined from the user's actual cass sessions (see [corpus/primary_sources/cass_quotes.md](../corpus/primary_sources/cass_quotes.md), anchors Q-001..Q-036). They are the user's existing UB-hunting methodology, preserved verbatim where possible.

---

## ♦ COUNTER — local-invariant counter-example

**Trigger:** A function or module has many sites following the same pattern; suspicion centers on the one site that's different.

**Prompt module:**
> Read `<file>`. Identify the invariant that holds at every call site EXCEPT one or a few. State the invariant explicitly. Then point at the violator(s) and explain why their divergence is a bug, not an intentional design choice.
>
> Examples:
> - Every `IfNot` call uses `p3=1` (except UPSERT at L4612 which uses `p3=0` — Q-008)
> - Every `Arc::from_raw` is paired with `into_raw`/`forget` (except site X)
> - Every `&str` access uses `chars().nth()` (except site Y using `as_bytes()[n]`)

**Exit:** Violator confirmed (file a finding) OR divergence justified (record rationale).

**Anchors:** Q-008, Q-020, Q-023, Q-034.

---

## ☣ SAFETY-NOTES-FIRST — write invariants before any code

**Trigger:** A remediation requires `unsafe { ... }`. Writing the SAFETY contract *before* the implementation is far cheaper than retrofitting it after.

**Prompt module:**
> Before writing any code, write the SAFETY contract:
>
> ```
> ### CRITICAL SAFETY NOTES:
> - <invariant 1: bounds, alignment, validity, lifetimes>
> - <invariant 2>
> - <invariant 3>
> - <platform-specific notes>
> - <what must NOT be affected by this change>
> ```
>
> Then design the implementation. Every unsafe block in the implementation cites one or more of the SAFETY notes above by reference.

**Exit:** SAFETY notes are written *and* every unsafe block references them.

**Anchors:** Q-004 (the frankensqlite mmap-SHM exemplar — single best UB exemplar in the corpus).

**Composes with:** ⊢ PROVE, ⊞ SOAK, the loom-model-first variant.

---

## ⊳ READ-ONLY-DELTA — frame a change-set before acting

**Trigger:** Any UB-adjacent task that begins with "what changed?". Acts as the scope-fence before any fix pass.

**Prompt module:**
> This is a READ-ONLY investigation. Do NOT edit any files.
>
> Run:
> 1. `git -C <repo> diff --stat`
> 2. `git -C <repo> diff` (full)
> 3. `git -C <repo> log --oneline -5`
>
> Identify: what functional surface changed; whether the change introduces new unsafe / FFI / SAFETY-contract sites; whether high-UB-risk surface is in the diff.
>
> **If high-UB-risk surface is touched, propose follow-up:** run `cargo +nightly miri test` on the affected modules; loom-model any new concurrency primitive.

**Exit:** Summary of change-set + recommendation for next UB action.

**Anchors:** Q-013, Q-014, Q-017, Q-024, Q-025.

**Upgrade path the skill adds:** After READ-ONLY-DELTA on TLS/arena/mmap/fcntl code, always propose the miri pass — the corpus shows the user has not historically done this.

---

## ♢ INLINE-LOOP-SWEEP — fleet inspection via shell for-loop

**Trigger:** Several /dp/* repos may be in dirty state simultaneously; need a fast fleet-wide view.

**Prompt module:**
> ```bash
> for repo in asupersync coding_agent_session_search frankenlibc franken_networkx \
>             frankensqlite mcp_agent_mail_rust storage_ballast_helper xf; do
>     echo "==== DIFF: $repo ===="
>     cd /data/projects/$repo
>     git diff HEAD 2>/dev/null | head -150
> done
> ```

**Exit:** Per-repo digest in one read pass.

**Anchors:** Q-016.

---

## ✕ BUG-CLAIM-VERIFY — verify before acting on a report

**Trigger:** External bug report (GitHub issue, CVE filing, user report) claims UB at a specific site.

**Prompt module:**
> Investigate the claim. DO NOT make code changes — research only.
>
> 1. Read the full issue body via `gh api repos/<owner>/<repo>/issues/<num>`.
> 2. Read the relevant source at the cited file:line.
> 3. **Verify if the claimed bug is real and still present** — does the claimed invariant actually hold?
> 4. **Check git log --since="<date>" for recent fixes** that may have already addressed it.
>
> Report: real-and-present | real-but-fixed-in-<commit> | not-a-bug-because-<reason>.

**Exit:** Verdict on the claim recorded.

**Anchors:** Q-023.

---

## ⟀ TWO-TIER-TRIANGULATION — gemini explores, claude fixes

**Trigger:** A complex architectural finding (frankensqlite WAL corruption, fcntl coalescing) where exploration is best done by one model and surgical implementation by another.

**Prompt module:**
> Phase A (exploration): use `/multi-model-triangulation` or invoke a gemini session via `~/.gemini/tmp/`. Ask for the architectural analysis without code changes.
>
> Phase B (implementation): take the gemini output as a spec; invoke a Claude subagent with the spec + ☣ SAFETY-NOTES-FIRST applied. Claude writes the SAFETY notes from the spec + the code.

**Exit:** Two-tier handoff complete; the architectural finding from A landed via B.

**Anchors:** Q-004 + Q-034 (the frankensqlite InodeTable + mmap-SHM exemplar pair).

---

## Operator Composition — Per-Severity Pipelines

| Severity | Operator pipeline |
|---|---|
| `MUST-BE-UB` | `★ SUSPECT` → `✦ ISOLATE` → `◐ REPRO` → (verdict `CONFIRMED_UB`) → `⊕ REWRITE` |
| `LIKELY-UB` | `★ SUSPECT` → `✦ ISOLATE` → `◐ REPRO` → `⬡ INSTRUMENT` → verdict |
| `SUSPICIOUS` | `★ SUSPECT` → `⬡ INSTRUMENT` (lightweight) → either `✦ ISOLATE` (graduate) or `⊙ DEBOUNCE-FALSE-POSITIVE` (close) |
| `CONTRACTUAL-BUT-DEFENSIBLE` | `★ SUSPECT` → check the contract docs, check the enforcement code → close as `NO_EVIDENCE` with rationale OR upgrade to `LIKELY-UB` |

For Phase 11 (Exhaustive mode), every `⊕ REWRITE` is followed by `⊞ SOAK` before being declared sound.

---

## Anti-Patterns

| ✗ | Why |
|---|---|
| Skipping `★ SUSPECT` and going straight to `⊕ REWRITE` | You'll rewrite code that isn't actually UB |
| `⬡ INSTRUMENT` without first running the baseline | You can't tell what changed |
| Picking the first rewrite without runners-up | Future maintainers lose the choice rationale |
| `⊙ DEBOUNCE` on a single clean run | One Miri-clean run isn't proof; need fresh-eyes confirm |
| `⊞ SOAK` locally instead of via `rch` | Burns your machine; pollutes the audit |
