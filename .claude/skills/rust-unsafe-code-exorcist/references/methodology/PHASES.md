# PHASES.md — Per-Phase Playbook

Each phase has: **goal**, **inputs**, **outputs**, **exit criteria**, and **agent prompt** (cross-referenced to [AGENT-PROMPTS.md](AGENT-PROMPTS.md)). Phases that allow parallelism note the partition axis.

---

## Phase 0 — Intake & Scope Decision

**Goal:** Lock down what's in scope, what's not, and what tooling we'll use.

**Inputs:** user answers from `assets/intake-prompt.md`; project tree.

**Outputs:**
- `<audit-dir>/phase0_scope_decision.md`
- `<audit-dir>/phase0_toolchain.json`
- `<audit-dir>/phase0_skill_inventory.json`

**Exit criteria:**
- Mode chosen; toolchain profile chosen; perf budget chosen; execution authorization chosen.
- Crates in/out of scope enumerated.
- Dep crates whose unsafe is reachable through this project's public API explicitly listed.
- Missing tooling proposed with exact install one-liners; user approved or declined each.
- In-project audit dir created and `git init`-ed.
- The user is informed of the exact one-liner to add `/.unsafe-audit` to the project's top-level `.gitignore` (so the outer git tree doesn't flag the nested audit repo as an embedded repository or untracked clutter). The audit does NOT modify the project's `.gitignore` — that violates the audit-only "existing project files stay read-only" contract. The user runs the one-liner themselves when ready; the audit-dir README has the exact command.

**Run:**
```bash
./scripts/check-skills.sh <audit-dir>
./scripts/install-toolchain.sh --check <audit-dir>
./scripts/detect-mode.sh <project> >> <audit-dir>/phase0_scope_decision.md
```

---

## Phase 0.5 — CASS / Exemplar Mining (conditional)

**Goal:** Surface prior agent-session reasoning about unsafe refactors on similar codebases.

**When to skip:** brand-new domain with no prior sessions; `audit-only` runs where the user wants speed.

**Inputs:** `phase0_scope_decision.md`; the exemplar repo list.

**Outputs:**
- `<audit-dir>/phase0_cass_findings.md` — quotes from prior sessions tagged by unsafe-class.
- `<audit-dir>/phase0_exemplar_patterns.md` — per-repo canonical patterns we should consider applying.

**Run:**
```bash
./scripts/cass-mine.sh <audit-dir>             # local + remote hosts
Agent(subagents/exemplar-miner.md)             # reads /dp/<repo>/.beads/ + git log + src
```

**Exit:** the main agent has read both findings files and can name the top 5 patterns to look for during Phase 1.

---

## Phase 1 — Enumerate

**Goal:** Produce a single canonical `unsafe-inventory.jsonl` covering every `unsafe` site in scope, including macro-generated ones.

**Partition axis:** one agent per crate (or per top-level `src/<module>` for single-crate projects). Phase 1 + Phase 2 are owned by the same agent for that partition.

**Inputs:** `cargo metadata --format-version 1 | jq '.workspace_members'`; the scope decision.

**Outputs:**
- `<audit-dir>/unsafe-inventory.jsonl` — one row per site. The canonical artifact. Every downstream tool reads it. Schema (full per-field documentation in [INVENTORY-SCHEMA.md](INVENTORY-SCHEMA.md)):
  ```json
  {
    "id": "site-0001",
    "crate": "frankenlibc",
    "file": "src/syscall/mod.rs",
    "line_start": 142,
    "line_end": 167,
    "kind": "block|unsafe_fn|unsafe_impl|unsafe_trait|extern_block|asm|unsafe_cell_decl|intrinsic_call|intrinsic_ptr|raw_ptr_decl|raw_ptr_cast",
    "enclosing_fn": "open_o_direct",
    "enclosing_type": null,
    "public_api_exposed": true,
    "macro_origin": false,
    "macro_origin_path": null,
    "ffi": true,
    "intrinsic": false,
    "source_excerpt": "unsafe { libc::open(path.as_ptr(), libc::O_DIRECT | libc::O_RDWR) }",
    "rustdoc_anchor": "frankenlibc::syscall::open_o_direct",
    "geiger_count": 1,
    "ubs_findings": []
  }
  ```
- `<audit-dir>/phase1/<crate>__expand.rs` — `cargo expand` output per crate (so macro-generated unsafe is reviewable).
- `<audit-dir>/phase1/<crate>__rustdoc.json` — rustdoc JSON per crate.
- `<audit-dir>/phase1/cargo-tree.txt` — dep tree.
- `<audit-dir>/phase1/<crate>__geiger.json` — per-crate unsafe counts (baseline).

**Run:**
```bash
./scripts/enumerate-unsafe.sh <project> <audit-dir>
./scripts/cargo-tree-soundness.sh <project> <audit-dir>
node scripts/generate-inventory.mjs <audit-dir>
```

**Exit criteria:**
- Every `unsafe` site that `ast-grep`, `cargo-geiger`, or `cargo expand` finds appears as an inventory row.
- Macro-origin rows have `macro_origin_path` pointing into `<audit-dir>/phase1/<crate>__expand.rs` with a line anchor.
- Public-API exposure flag is set from the call graph + rustdoc JSON (NOT guessed from source-text proximity).

---

## Phase 2 — Per-Site Write-Up

**Goal:** One Markdown file per inventory row. The agent that enumerated a partition writes the write-ups for that partition (continuity > parallelism gain).

**Outputs:**
- `<audit-dir>/audit/sites/<crate>/<file-slug>__<line_start>.md` — per `assets/site-writeup-template.md`. Each write-up answers:
  1. What does this `unsafe` block actually do?
  2. What invariants does it assume? (named, not paraphrased)
  3. Where does the data come from (caller / kernel / FFI peer)?
  4. Who else touches the same memory or atomic?
  5. What does the existing SAFETY comment claim, and — tracing the call graph today — is the claim still true?
  6. What breaks under panic-in-Drop? Under async cancellation? Under unwinding through FFI?

**Run:**
```bash
Agent(subagents/site-analyzer.md, partition=<crate>)
```

**Exit criteria:**
- Every inventory row has a corresponding `.md` file.
- Each write-up cites at least one specific code anchor for invariant enforcement (caller side).
- Sites with macro origin reference the expanded source, not the macro invocation.

---

## Phase 3 — Synthesize

**Goal:** What can only be seen globally: invariant clusters, soundness surface, cross-site `Send/Sync` dependencies.

**Inputs:** all Phase 2 write-ups.

**Outputs:**
- `<audit-dir>/audit/synthesis/invariants.md` — clusters sites by shared invariant. Each cluster has: name, sites, the safe wrapper that could subsume them. The cluster's safe wrapper is the **invariant chokepoint**: the single function (or trait, or type) that, once built, encapsulates the shared invariant so the surrounding unsafe sites collapse to safe calls.
- `<audit-dir>/audit/synthesis/soundness-surface.md` — every public API path that reaches `unsafe`. Schema:
  ```
  PUB API: frankenlibc::Connection::execute_o_direct
  REACHES: site-0142 (libc::open), site-0143 (libc::pwrite), site-0157 (mmap)
  INVARIANTS THE CALLER MUST UPHOLD: path is null-terminated; fd lifetime
  ```
- `<audit-dir>/audit/synthesis/refactor-clusters.md` — proposed refactor clusters with member sites and proposed safe wrapper.

**Run:**
```bash
Agent(subagents/synthesizer.md)
```

**Exit criteria:**
- Every `unsafe impl Send/Sync` has its field-level dependencies named.
- Every site reachable from `pub` is in the soundness-surface file.
- Refactor clusters have at least one shared invariant that would allow a single safe wrapper to subsume members.

---

## Phase 4 — Classify

**Goal:** Assign every site to (A) / (B) / (C) per [CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md). **Iterative.**

**Inputs:** the inventory + per-site write-ups + synthesis.

**Outputs:**
- `<audit-dir>/audit/classification/site-<id>.md` — per site: bucket + justification.
- `<audit-dir>/audit/classification/summary.jsonl` — `{id, bucket, confidence, prior_bucket}` per site per pass.
- `<audit-dir>/audit/classification/convergence-proof-pass-<N>.md` — per pass: total sites, flips this pass, flip ratio, count of (A)→(C) flips, count of upward flips (must be 0), exit decision. Schema:
  ```markdown
  # Convergence proof — Phase 4 pass <N>
  Date: <ISO-8601>
  Total sites: <T>
  Flips this pass: <F>
  Flip ratio: <F/T = X.XX%>
  (A)→(C) flips: <0 required for convergence>
  Upward flips ((B)→(A), (C)→(B), (C)→(A)): <0 required>
  Exit verdict: CONTINUE | EXIT-CONVERGED
  Convergence rule: flip_ratio < 5% AND (A)→(C) = 0 AND upward = 0 for TWO consecutive passes
  ```
- `<audit-dir>/audit/classification/convergence-proof-FINAL.md` — written when Phase 4 exits. Summarizes the convergence trajectory across all passes.
- `<audit-dir>/audit/synthesis/graduation-history.md` — bucket changes vs the prior audit run (if any). Append-only across runs; see [GRADUATION-HISTORY.md](GRADUATION-HISTORY.md) for the cross-audit schema.

**Iteration discipline:**
- Pass 1 — initial classification with the original analyzing agent.
- Pass 2..N — a fresh classifier agent re-classifies without seeing the prior decision.
- Convergence — two consecutive passes where <5% of sites flip bucket AND zero (A)→(C) flips.

**Run:**
```bash
for i in 1 2 3 ...; do
  Agent(subagents/classifier.md, pass=$i)
  diff prior_summary.jsonl summary.jsonl | tee phase4_pass${i}_diff.txt
done
```

**Exit:** convergence as defined; no (A) lacking a falsifiable justification.

---

## Phase 5 — Plan-Draft

**Goal:** For every site, produce the actionable plan.

**(C) sites:** full safe replacement code (not pseudocode); property-based + metamorphic equivalence tests; loom model if concurrency-touching; miri invocation that exercises the rewrite.

**(B) sites:** `safe-only` Cargo feature implementation; criterion bench + hyperfine end-to-end timing + flamegraph diff; CI matrix entry building `--features safe-only`.

**(A) sites:** hardened SAFETY comment + proof obligation that callers MUST uphold; a clippy-or-lint rule (if expressible) that catches caller-side violations.

**Outputs:**
- `<audit-dir>/audit/plans/site-<id>.md` per site (per `assets/refactor-plan-template.md`).
- `<audit-dir>/audit/plans/INDEX.md` — global plan index ordered by cluster.

**Final harmonization pass:** look for contradictions across plans (e.g., two clusters proposing incompatible safe wrappers for the same invariant), missing sites, double-counted sites.

**Run:**
```bash
Agent(subagents/refactor-planner.md)        # parallel per cluster
Agent(subagents/equivalence-prover.md)      # parallel per (C) site
Agent(subagents/synthesizer.md, pass=2)     # harmonization
```

**Exit:** every site has a plan; every (C) has a property test draft + miri command; every (B) has perf numbers; every (A) has a hardened SAFETY block.

---

## Phase 6 — Adversarial Reclassification

**Goal:** A fresh agent that hasn't seen prior classification tries to break it.

**For each (A):** propose a safe alternative and argue it works. If the argument holds, reclassify to (B) or (C).

**For each (B):** hunt for a missed perf-equivalent safe pattern. If found, reclassify to (C).

**For each (C):** construct inputs the proposed safe rewrite would handle differently from the unsafe original. If found, the equivalence claim is broken — refine the rewrite OR reclassify.

**Iteration discipline:** same as Phase 4 (reapply until two consecutive passes are marginal).

**Run:**
```bash
for i in 1 2 3 ...; do
  Agent(subagents/adversarial-reclassifier.md, pass=$i)
  diff classification/summary.jsonl phase6_pass${i}_summary.jsonl
done
```

**Exit:** two consecutive adversarial passes produce only marginal reclassifications.

---

## Phase 7 — Fresh-Eyes Code Review

**Goal:** Find bugs in the proposed safe rewrites themselves.

**Step 1.** Run the three verbatim prompts ([SKILL.md § Phase 7 fresh-eyes prompts](../../SKILL.md)) against the rewrites. Repeat until two consecutive rounds come up clean except for trivial changes.

**Step 2.** Run the toolchain harness in this order:

```bash
cargo +nightly miri test                                   # UB detection
cargo +nightly miri run --bin <each>                       # if miri can execute the binary
cargo +nightly careful test                                # additional UB detection
RUSTFLAGS="--cfg loom" cargo test --features loom_concurrency_tests
cargo fuzz run <target> -- -max_total_time=60              # for any new/widened public surface
cargo mutants --in-place=false                             # tests must pin behavior
cargo +nightly geiger                                      # delta vs phase1 baseline
```

**Step 3.** Fix every finding meticulously, preserving behavior, perf, and public API where possible.

**Outputs:**
- `<audit-dir>/audit/phase7/review-pass-<N>.md` — round-by-round findings + fixes.
- `<audit-dir>/audit/phase7/verification-log.md` — verbatim tool output, tee'd.

**Run:**
```bash
Agent(subagents/fresh-eyes-reviewer.md, pass=N)
./scripts/run-miri.sh <audit-dir>
./scripts/run-careful.sh <audit-dir>
./scripts/run-loom.sh <audit-dir>
./scripts/run-fuzz.sh <audit-dir>
./scripts/run-mutants.sh <audit-dir>
./scripts/run-geiger.sh <audit-dir>
```

**Exit:** two consecutive review rounds clean + all tools green (or every finding explained in `verification-log.md` and the plan revised).

---

## Phase 8 — Bead Conversion + Commit

**Goal:** Convert plans into a `br` bead graph the user can feed to their existing swarm workflow.

**Bead shape (per `/beads-workflow`):**
- One parent epic per refactor cluster from Phase 3.
- One implementation bead per (C) site; the parent epic depends on child site beads, while site beads depend only on true technical prerequisites.
- One feature-flag-+-CI-matrix bead per (B), with acceptance criteria = `--features safe-only` build green + perf delta within budget.
- One "harden SAFETY comment + add proof-obligation lint" bead per (A).
- One `pre-existing-ub-N` bead per UB found in code outside scope.

Each bead carries: acceptance criteria as exact `cargo` invocations, expected diff size, back-reference to `audit/plans/site-<id>.md`.

**Run:**
```bash
node scripts/generate-bead-graph.mjs <audit-dir>           # emits br create + br dep commands
bash <audit-dir>/phase8_bead_commands.sh                    # executes them in the audit repo
br sync --flush-only
git -C <audit-dir> add .beads/ audit/ phase*.{md,json,jsonl}
git -C <audit-dir> commit -m "rust-unsafe-code-exorcist: audit complete"
```

**Exit:** bead graph committed; `br ready` shows the first wave of unblocked beads.

---

## Phase 9 — Verification Harness

**Goal:** A `verify.sh` for the target project that runs the full safety suite and emits a single pass/fail.

**Outputs:**
- `<audit-dir>/verify.sh` (per `assets/verify.sh.template`) — runs miri + careful + loom + fuzz + mutants + geiger + the project's test suite, under default AND `safe-only` features.
- `<audit-dir>/ci-matrix.yml` (per `assets/ci-matrix.yml.template`) — GitHub Actions matrix entry.
- `<audit-dir>/audit/synthesis/pre-existing-ub.md` — anything the harness uncovered that was NOT in the refactor scope. **Filed as separate `pre-existing-ub-N` beads, never folded into the refactor plan.**

**Run:**
```bash
Agent(subagents/harness-builder.md)
bash <audit-dir>/verify.sh   # final dry-run in audit dir
```

**Exit:** harness exits 0 on a clean run; pre-existing UB filed as separate beads with explicit `[NOT IN REFACTOR SCOPE]` label.

---

## Phase 10 — Maintainer-Empathy Review

**Goal:** A fresh agent with no prior context reads the entire audit and answers: "If I were the project's maintainer, would I land these? Where am I unconvinced? What evidence am I missing? What would I want before clicking merge?"

**Companion agents (if available):**
- `/idea-wizard` — generate alternative refactor strategies the original audit missed.
- `/multi-model-triangulation` — second-opinion (Codex + Gemini + Grok) on the highest-risk (C) sites.

**Outputs:**
- `<audit-dir>/REVIEWER_RESPONSES.md` per `assets/reviewer-responses-template.md`.
- Revisions to plans landed as follow-up commits on the audit repo.

**Run:**
```bash
Agent(subagents/maintainer-empathy-reviewer.md)
Agent(subagents/idea-generator.md)
Agent(subagents/multi-model-triangulator.md, sites=<top-N-risky-C>)
```

**Exit:** `REVIEWER_RESPONSES.md` exists; every reviewer concern is either addressed in revised plans or filed as a follow-up bead with explicit "deferred — see REVIEWER_RESPONSES.md §N" annotation.

---

## Cross-phase invariants

- **Audit dir is the only write target until Phase 8.** The project repo stays untouched.
- **No destructive rewrites.** Every Edit is incremental. (Per AGENTS.md.)
- **No silent allocator changes.** Phase 5 plans must preserve allocator identity unless explicitly approved.
- **No file deletion without permission.** Per AGENTS.md, even in the audit dir.
- **Pre-existing UB is filed separately.** Never folded into the refactor scope.
- **Every classification has a falsifiable justification.** No vibes.
