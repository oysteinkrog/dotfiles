# Phases 0–13 Playbook

The orchestrator drives the loop; subagents do the work in parallel. Every phase has an exit criterion that is *measurable*, not vibes-based.

Coverage in this file:
- **Phase 0** (Bootstrap & Partition) — always.
- **Phases 1–10** (RECON → fresh-eyes review) — Standard mode floor.
- **Phase 11** (Soak campaigns) — Exhaustive mode only.
- **Phase 12** (Final artifacts: report + runbook + handoff) — Standard and Exhaustive.
- **Phase 13** (Auto-remediation execution) — opt-in; appended after Phase 12.

---

## Phase 0: Bootstrap & Partition (5–15 min, main agent only)

Before any fan-out, the main agent:

1. **Confirm inputs** with the user — see SKILL.md "Up-Front User Confirmations".
2. **Clone if needed** to `/tmp/<repo>/` when given a URL; treat that as the source from now on.
3. **Initialize workspace + write the resume lifeline**:
   ```bash
   # The unquoted `<project>` / `<YYYY-MM-DD-...>` placeholder syntax used
   # elsewhere in this doc IS A BASH SYNTAX ERROR — bash treats `<` and `>` as
   # redirection operators even inside assignments. Use literal-looking values
   # like `foo` (intended-as-placeholder) so the snippet is copy-paste-safe.
   SOURCE=/data/projects/foo                  # ← replace `foo` with the project basename
   RUN_ID=2026-05-14-foo-1                    # ← today's UTC date + basename + sequence
   MODE=Standard                              # Quick | Standard | Exhaustive — from the user confirmations
   WORKSPACE="$SOURCE/.ub-exorcism/$RUN_ID"
   mkdir -p "$WORKSPACE"

   # phase0_run.json is the resume lifeline — every later step that needs to
   # detect "is there a resumable run in this project?" looks for THIS file.
   # Write it FIRST, before any phase that could fail mid-step.
   #
   # Using `jq -n --arg` so JSON escaping is correct even when a project path
   # or run-id contains quotes / backslashes (printf would produce invalid
   # JSON in those cases). jq is required elsewhere in Phase 0 anyway
   # (verify-phase-artifacts.sh, validate-phase.sh) so it's an acceptable dep.
   jq -n \
       --arg run_id "$RUN_ID" \
       --arg mode "$MODE" \
       --arg source "$SOURCE" \
       --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '{run_id: $run_id, mode: $mode, source_path: $source, started_at: $started_at, archetype_hint: null, skipped_tools: [], skipped_buckets: []}' \
       > "$WORKSPACE/phase0_run.json"
   ```
   Fields:
   - `mode` — `Quick` / `Standard` / `Exhaustive` from the user confirmations.
   - `archetype_hint` — fill in after step 5 (preflight) using `archetype_hints.forbid_unsafe` / `ffi_present` / `unsafe_blocks_count`. Update with `jq` (e.g. `jq '.archetype_hint = "ffi-heavy"' phase0_run.json | sponge phase0_run.json`) or by rewriting.
   - `skipped_tools` / `skipped_buckets` — appended throughout if the user chose the degraded-tooling path; same `jq` edit pattern.

4. **Toolchain inventory + install**:
   ```bash
   ./scripts/install-toolchain.sh "$WORKSPACE" --inventory-only   # writes phase0_toolchain_inventory.json
   ```
   **After running --inventory-only:** read `phase0_toolchain_inventory.json` and check each `status` + `smoke_test_passed` field. For any tool with `status != "ok"` or `smoke_test_passed != "yes"`, present the user with the THREE-CHOICE auto-install offer (see SKILL.md "Up-Front User Confirmations" §4):
   - **Auto-install everything missing** — run `./scripts/install-toolchain.sh "$WORKSPACE" --yes` if the user said "install whatever you need" or similar blanket approval.
   - **Interactive per-tool** — run `./scripts/install-toolchain.sh "$WORKSPACE"` and let the TTY prompt accept/decline each tool.
   - **Skip & degrade** — append the missing tool names to `phase0_run.json`'s `skipped_tools`, and mark the corresponding Phase 2/3 detector buckets as `SKIPPED` in the final report.

   Re-run inventory-only after installs to confirm `smoke_test_passed: yes` for every newly-installed tool. If any tool is `installed-but-broken-post-smoke`, surface that to the user — `cargo install` succeeding does not imply the tool works.

5. **Run preflight smoke test** before any subagent fan-out commits time:
   ```bash
   ./scripts/preflight-smoke-test.sh "$SOURCE" "$WORKSPACE"
   # Exit 0 = all clear; 1 = recoverable; 2 = fatal (abort the run)
   ```
   The smoke test confirms: rustup + nightly + miri available, cargo metadata + check succeed, archetype hints (forbid_unsafe / ffi_present / unsafe_blocks_count), disk space, fuzz target inventory. The output is `$WORKSPACE/preflight_smoke.json` (Phase 0 wants the report alongside `phase0_*.json`, so always pass `$WORKSPACE` here — the script accepts a 1-arg form for ad-hoc use but rejects an off-tree second arg rather than silently falling back to the source repo).

   Read `preflight_smoke.json`; the `archetype_hints` inform Phase 0 partition AND the convergence-floor selection. **Backfill `archetype_hint` into `phase0_run.json` now** so resumers see it.
6. **Partition the source repo** into modules and concurrency hubs. Good partitions:
   - Top-level workspace members (`crates/*`)
   - `src/<subsystem>/` directories for single-crate projects
   - Concurrency hubs (each lock-free data structure / each FFI module / each custom `Send`+`Sync` type) get their own row even if small
7. **Emit a partition plan** to the user as a table *before* fanning out:
   ```markdown
   | Section | Source path | UB priors | Subagent id |
   |---------|-------------|-----------|-------------|
   | mvcc    | crates/fsqlite-mvcc/src | aliasing, atomics, custom Send | A |
   | btree   | crates/fsqlite-btree/src | raw pointer, repr(C), align | B |
   | c-api   | crates/fsqlite-c-api/src | FFI, repr(C), `Box::from_raw` | C |
   ```
8. **Bootstrap the workspace tree**:
   ```
   <workspace>/
     phase0_run.json                   # ← resume lifeline (written in step 3)
     phase0_toolchain_inventory.json
     phase0_partition.json
     preflight_smoke.json
     phase1_unsafe_surface_inventory.md
     phase1_notes/<module>.md
     phase2_findings_<bucket>.md       # one per UB-taxonomy bucket
     phase3_dynamic_findings.md
     phase3_raw/                       # raw tool output dumps
     phase4_unified_findings.md
     UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md
     phase5_experiment_results/<exp-id>.md
     phase6_idea_wizard.md
     phase7_convergence_round_<N>.json
     phase8_remediation_plan.md
     phase9_beads_log.md
     phase10_fresh_eyes_log.md
     phase11_soak_designs.md           # Exhaustive mode only
     FINAL_UB_REPORT.md
     UB_RUNBOOK.md
   ```

**Exit criterion:** partition table accepted by user; workspace exists under the source repo's `.ub-exorcism/<run-id>/`; `phase0_run.json` written; toolchain inventory clean; user gave green light.

---

## Phase 1: RECON — Unsafe Surface Inventory (parallel per section)

Each section owner spawns an `unsafe-surface-mapper` subagent (see `subagents/unsafe-surface-mapper.md`). It produces `phase1_notes/<section>.md` *and* contributes a row block to the shared `phase1_unsafe_surface_inventory.md`.

For every site, capture:
- `file:line`
- Site kind: `unsafe block`, `unsafe fn`, `unsafe impl Send`, `unsafe impl Sync`, `extern "C"` decl, `#[no_mangle]`, `#[repr(C|transparent|packed)]`, `static_assertions!`, atomic op, custom `Drop`, manual `MaybeUninit`, `transmute`, `from_raw`, `set_len`, `assume_init`, `get_unchecked`, `Pin::new_unchecked`, `UnsafeCell`, `core::intrinsics::*`, `core::hint::*_unchecked`, `mem::forget`, `mem::zeroed`, `mem::uninitialized`, raw `ptr::*`
- UB-taxonomy bucket(s) the site belongs to (multi-tag — see [UB-TAXONOMY.md](UB-TAXONOMY.md))
- SAFETY-comment status: PRESENT_STRONG (>40 char, names invariants), PRESENT_WEAK (<40 char or hand-wavy), MISSING
- Macro-expansion status: SOURCE_DIRECT (visible in source) or MACRO_GENERATED (only visible after `cargo expand`)

**Tool ritual (every section subagent must run):**
```bash
rg -n '(^|[^a-zA-Z])unsafe(\s+(fn|impl|trait|extern|\{))' --type rust SECTION/
rg -n '// *SAFETY:|// *Safety:' --type rust SECTION/
rg -n 'extern "C"|#\[no_mangle\]|#\[repr\((C|transparent|packed|align)' --type rust SECTION/
rg -n 'static_assertions!|const _: \(\) = assert!' --type rust SECTION/
rg -n 'transmute|from_raw|set_len|assume_init|get_unchecked|new_unchecked|UnsafeCell|::intrinsics::|::hint::.*_unchecked|mem::forget|mem::zeroed|mem::uninitialized' --type rust SECTION/
cargo +nightly expand --lib 2>/dev/null > /tmp/expand.rs && rg -n 'unsafe' /tmp/expand.rs | wc -l   # macro-generated unsafe count
```

**Exit criterion:** `phase1_unsafe_surface_inventory.md` has ≥1 row per discovered site; every section's `phase1_notes/<section>.md` has a paragraph-length module digest. Main agent posts a one-paragraph per-section summary to the user and *asks if any section needs re-research*.

---

## Phase 2: STATIC SWEEP — Per-Bucket Subagent Fan-Out (parallel per bucket)

For each UB-taxonomy bucket (see [UB-TAXONOMY.md](UB-TAXONOMY.md)), fan out a `static-bucket-sweeper` subagent. Each owns its bucket's findings markdown (`phase2_findings_<bucket>.md`) with file:line refs, hypothesis severity, and a draft experiment design.

Severity scale (used in every Phase-2 finding):
- **MUST-BE-UB** — sound analysis says this *is* UB; experiment will confirm shape
- **LIKELY-UB** — strong static signal, but the dynamic check is the arbiter
- **SUSPICIOUS** — pattern-match flag, may be false positive
- **CONTRACTUAL-BUT-DEFENSIBLE** — relies on caller's contract; check the contract is documented and enforced at the boundary

**Bucket → tooling map** (full detail in [TOOLING.md](TOOLING.md)):

| Bucket | Tools |
|---|---|
| Aliasing | ast-grep patterns, `cargo +nightly miri` (SB+TB), syn-walker `aliasing.rs` |
| Provenance | ast-grep, `MIRIFLAGS=-Zmiri-strict-provenance` |
| Alignment | ast-grep on `*const T`/`*mut T` casts, `MIRIFLAGS=-Zmiri-symbolic-alignment-check`, `#[repr(packed)]` field-address audit |
| Validity invariants | syn-walker `validity.rs`; flags `mem::zeroed::<T>()` for non-zero-valid T |
| Uninit memory | ast-grep on `MaybeUninit::uninit().assume_init()`; clippy `uninit_assumed_init` |
| Type punning | ast-grep on `transmute(...)`; `bytemuck` candidacy scan |
| Data races | syn-walker `data_races.rs` — looks for `&Cell` / `&UnsafeCell` shared cross-thread |
| Send/Sync | every `unsafe impl (Send|Sync) for ...` cross-referenced against fields |
| Pin | ast-grep on `Pin::new_unchecked`, manual `Pin` impl |
| FFI | every `extern "C"` cross-referenced against headers if available; `improper_ctypes` lint |
| Panic safety | drop-impl audit; `mem::forget`/`ManuallyDrop` usage |
| Std-library trait invariants | clippy `derive_ord_xor_partial_ord`, `eq_op`, custom `Hasher` audit |
| Refcount lifecycle | `Arc::from_raw` / `Box::from_raw` / `Rc::from_raw` usage audit |
| `*const T` mutation | ast-grep on `*(p as *mut _)`, casts that strip const |
| Lifetimes & escape | syn-walker `escape.rs` — raw pointer outliving its scope |

Each finding gets a **draft experiment** at this phase — see [EXPERIMENT-DESIGNS.md](EXPERIMENT-DESIGNS.md) for the template.

**Exit criterion:** every bucket subagent has produced `phase2_findings_<bucket>.md` with at least the row block from Phase 1 acknowledged, even if "no findings in this bucket". `phase2_summary.md` rolls them up.

---

## Phase 3: DYNAMIC SWEEP — Tool Matrix (parallel per tool)

Five subagent families run in parallel:

1. **miri-runner × N** — one per `MIRIFLAGS` configuration. See [TOOLING.md §Miri matrix](TOOLING.md).
2. **sanitizer-runner × 4** — ASan, TSan, MSan, LSan (subset where the target is supported).
3. **fuzz-author-and-runner × M** — one per existing fuzz target + one per *missing* fuzz target identified in Phase 2 for unsafe APIs.
4. **loom-modeler × P** — one per concurrency primitive identified in Phase 1.
5. **shuttle-runner × Q** — complement to loom for primitives where loom's exhaustive search blows up.

All raw output lands in `phase3_raw/<tool>_<config>.log`. The subagents extract crash traces, Miri tracebacks, race transcripts and post structured findings to `phase3_dynamic_findings.md`.

**After the Miri matrix completes, ALWAYS run the axis differ** — it's a free signal the per-axis logs leave on the table:
```bash
./scripts/miri-axis-differ.sh "$WORKSPACE"
# Writes phase3_raw/miri_axis_diff.md.
# Exit 1 = at least one test diverged across axes; each is a Phase 5 experiment candidate.
```
A test that one axis (e.g., tree-borrows) rejects while another (default/stacked-borrows) accepts is a soundness gradient: the program is UB under one borrow model, accidentally accepted by the other. Open a Phase 5 entry for each divergence, citing the divergent axes.

The Phase 3 step list also incorporates [UB-ADVANCED-DETECTORS.md](UB-ADVANCED-DETECTORS.md) when the project's archetype indicates additional surfaces are worth checking:
- **D-2 cross-target Miri** (run when the project ships non-x86_64 targets)
- **D-5 differential fuzz vs published version** (W7 pre-release mode only)
- **D-9 custom-allocator audit** (run when Phase 1 found `#[global_allocator]`)

The static detectors (D-3, D-4, D-6, D-7, D-10) are Phase 2 buckets — see the composition table in [UB-ADVANCED-DETECTORS.md §Composition with existing phases](UB-ADVANCED-DETECTORS.md#composition-with-existing-phases).

**Reservation contracts:**
- `tool://miri/<config>` — exclusive *per config*; different MIRIFLAGS configs build to distinct target dirs, so they run in parallel (see [ORCHESTRATION.md §Standard reservations](ORCHESTRATION.md#standard-reservations-tools-and-shared-resources))
- `tool://loom` — exclusive
- `tool://fuzz-corpus/<target>` — exclusive while writing the corpus
- `tool://sanitizer-build/<sanitizer>` — exclusive *per family*; ASan + TSan can run concurrently in separate builds
- `resource://gpu-0` — for GPU fuzz targets

Coordination is via Agent Mail — see [ORCHESTRATION.md](ORCHESTRATION.md).

**Exit criterion:** every scheduled tool/config has either a green/red line in `phase3_dynamic_findings.md` or an explicit `SKIPPED-with-rationale` (e.g., "ASan not supported on aarch64 + this OS").

**Hand-off opportunity — `/testing-fuzzing`.** Phase 3's fuzz step is targeted-and-shallow (5–15 min per target). When Phase 4 synthesis flags a fuzz target as "high-value but the short pass didn't crash", hand the target to `/testing-fuzzing` for a 24-hour-class campaign. The harness layout is identical (both write under `fuzz/fuzz_targets/`), so the hand-off is a direct file copy + invocation. See [INTEGRATIONS.md §With /testing-fuzzing](INTEGRATIONS.md#with-testing-fuzzing) for the artifact-flow diagram.

---

## Phase 4: SYNTHESIS — Unified Findings + Experiment Designs (single agent)

A single `synthesizer` agent reads:
- `phase1_unsafe_surface_inventory.md`
- every `phase2_findings_<bucket>.md`
- `phase3_dynamic_findings.md`

…and writes:
- `phase4_unified_findings.md` — deduped, cross-linked, severity-ranked. Each row has: ID, file:line, bucket, severity, dynamic-tool signals, hypothesis, status (`OPEN` / `EXPERIMENT_DRAFTED`).
- `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` (v1) — one experiment per OPEN hypothesis. The format is strict:

```markdown
## EXP-001: <descriptive title>

**Finding ref:** F-007 in phase4_unified_findings.md
**Bucket:** Aliasing / Provenance / ...
**Hypothesis:** <one sentence; the falsifiable claim>
**Minimal reproducer:** <inline Rust code, ≤30 lines, self-contained>
**Expected signal:** <e.g., "Miri TB reports 'attempting reborrow from disabled location'">
**Falsifiability:** <what evidence would refute>
**Invocation:**
```
MIRIFLAGS="-Zmiri-tree-borrows" cargo +nightly miri test --test ub_exp_001 exp_001 2>&1 | tee phase5_experiment_results/EXP-001.log
```
**Verdict:** OPEN
**Notes:** <empty until results>
```

Ambiguous findings get **multiple experiments**, each isolating a different assumption.

**Exit criterion:** every OPEN hypothesis from Phase 4 has ≥1 experiment in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`. Main agent shares the unified-findings table with the user.

---

## Phase 5: EXPERIMENT EXECUTION (parallel per experiment)

Fan out an `experiment-executor` subagent per OPEN experiment. Each subagent:
1. Reads the experiment block.
2. Writes the reproducer file under `<workspace>/experiments/<exp-id>/`.
3. Runs the invocation; captures output to `phase5_experiment_results/<exp-id>.log`.
4. Records verdict back into `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`:
   - `CONFIRMED_UB` — expected signal observed; finding stays at MUST-BE-UB
   - `NO_EVIDENCE` — clean run; demote finding to SUSPICIOUS or close it
   - `NEEDS_REFINEMENT` — partial signal / new variable surfaced; spawn a follow-up experiment
   - `DEFERRED` — out of scope for this run; record rationale and re-check criteria
5. **Any new hypothesis spawned** during execution gets appended as a new EXP-N entry.

**Exit criterion:** every Phase-5 experiment has a verdict. Zero `OPEN`. `phase5_round_summary.md` lists the verdict counts.

**Hand-off opportunity — `/testing-metamorphic`.** The MIRIFLAGS matrix and sanitizer matrix are *already a source of metamorphic relations* the skill doesn't formally exploit. For every CONFIRMED_UB experiment, consider authoring an MR via `/testing-metamorphic`:
- "output under MIRIFLAGS=default ≡ output under MIRIFLAGS=-Zmiri-tree-borrows for the safe-input class"
- "output under ASan ≡ output under MSan"

When the MR fires on a fuzz-generated input, you have a *property-grounded* UB confirmation rather than a single-axis verdict. Plug `/testing-metamorphic` into Phase 5 alongside the experiment-executor. See [INTEGRATIONS.md §With /testing-metamorphic](INTEGRATIONS.md#with-testing-metamorphic).

**Hand-off opportunity — `/testing-golden-artifacts` (freeze the reproducer).** Each CONFIRMED_UB reproducer's tool output (Miri traceback, ASan crash report) becomes a golden snapshot. Future runs of `experiments/<exp-id>/repro.rs` that produce a different output indicate either a Rust upgrade-induced behavior change or a silent re-introduction. The freeze is a 30-second add-on per CONFIRMED experiment.

---

## Phase 6: IDEA-WIZARD ROUNDS — Project-Shaped UB Techniques (multi-round, investigate-all)

**Run 2 rounds in Standard mode, 3 rounds in Exhaustive.** Each round uses a different lens; each round investigates ALL 30 ideas (not just top-5). The lens-rotation schedule:

| Round | Lens | What it surfaces |
|-------|------|------------------|
| R1 | **STRUCTURAL** | Data-shape invariants: content-hash determinism, serialization round-trip, sort stability, trait-derive consistency, Hash/Eq agreement, atomic-ordering pairings |
| R2 | **ADVERSARIAL** | Crafted-input attacks: separator-byte injection, alias collisions, schema-version mismatches, timing-dependent state transitions, malicious JSONL |
| R3 (Exhaustive only) | **CROSS-SYSTEM** | Multi-process/machine/thread interactions: concurrent writers, file-lock fallback, timezone-dependent canonicalization, fs::rename cross-FS fallback, kernel vs user-space contract drift |

**Why multi-round + investigate-all (calibration anchor):** in a field trial, a CONFIRMED SHA-256 collision (NUL-injection in `HashFieldWriter`) was the highest-severity finding of the whole audit. It came from an idea-wizard round whose top-5 by score did NOT contain it; the killer finding was at sum-score-rank #30. Post-Phase-1/2 static buckets had NOT caught it. Top-5-only would have missed the only HIGH-severity UB-adjacent bug in a pure-safe-Rust codebase. The cost of investigating 30 instead of 5 is ~3× tokens but the expected hit-rate gain is the difference between "found the actual bug" and "filed a no-op convergence round."

Per round, invoke `/idea-wizard`'s Phase 2 prompt narrowed for the round's lens:

> Come up with your very best ideas for clever, non-obvious UB-detection techniques that are specifically suited to THIS codebase, viewed through the {LENS} lens. Consider its specific architecture (content-hash dedup, custom allocators, self-referential structs, intrusive lists, lock-free data structures, MMIO surfaces, FFI surfaces, scoped threads, serde Deserialize impls, etc.). **Generate 30 ideas. Score each on three axes: PROVABILITY (1–5), CRATE-LEVEL IMPACT (1–5), NOVELTY VS EXISTING FINDINGS (1–5). Do NOT cut to a top-5; we investigate every single idea.**

The `idea-wizard-orchestrator` subagent owns this phase (see `subagents/idea-wizard-orchestrator.md`). Output per round: `phase6_idea_wizard_round_{N}.md`. After the final round: `phase6_idea_wizard_rollup.md` consolidating all rounds.

Per-idea verdict classification (one of these on every idea):

- **ALREADY_COVERED** — overlaps existing F-NNN or EXP-NNN
- **NEW_EXP_PROMOTED** — promoted to EXP-{ROUND}NN with verdict OPEN
- **NEEDS_DEEPER_INVESTIGATION** — credible but requires more data; recorded as deferred
- **NO_EVIDENCE** — code doesn't have the shape; document why
- **INAPPLICABLE** — wrong architecture / wrong language feature

**Exit criterion:** for each round, 30 ideas with three-axis scores AND a per-idea verdict; net-new EXP-{ROUND}NN blocks filed in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` for every NEW_EXP_PROMOTED. On the final round, the rollup file exists. **Across all rounds combined:** ≥1 net-new EXP filed (or, on a fully-mined-out project, a documented convergence-evidence note explaining why no rounds produced new EXPs).

---

## Phase 7: ITERATE PHASES 2–6 — Until Convergence

Repeat Phase 2 → 6, with these adjustments per round:
- Phase 2 sweepers may add new ast-grep patterns / syn walkers as they learn.
- Phase 3 may add new MIRIFLAGS combinations, new sanitizer configs, new fuzz targets.
- Phase 4 dedupes against the *previous* round.
- Phase 5 executes any new experiments.
- Phase 6 runs again only if Phase 5 surfaced enough novelty to be worth fresh idea-wizard work.

After each round, run:
```bash
# $WORKSPACE set per Phase 0 step 3 — bash treats unquoted <workspace> as a
# redirection operator, so always use the variable (or a real path).
./scripts/convergence-tracker.sh "$WORKSPACE"
# Writes phase7_convergence_round_N.json
# Exit 0 if this round is "quiet" (see CONVERGENCE.md); exit >0 otherwise.
```

**Exit criterion:** two consecutive rounds with exit 0 AND the archetype-aware round floor met AND every `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` entry has a non-OPEN verdict. The floor is 10 for unsafe-touching crates, 3 (Standard) or 5 (Exhaustive) for `#![forbid(unsafe_code)]` pure-safe projects — see [CONVERGENCE.md §Archetype-aware round floor](CONVERGENCE.md#archetype-aware-round-floor).

Compaction-survival: every phase artifact is the source of truth. If an agent gets dropped, it reads the most recent round's files and resumes. Never store reasoning only in memory.

---

## Phase 8: REMEDIATION DESIGN (single agent, with optional triangulation)

The `remediation-architect` subagent reads `phase4_unified_findings.md` (final) and `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` (final). For each `CONFIRMED_UB` finding:

1. **Enumerate isomorphic rewrites** — at least 2 where applicable. Use [REMEDIATION-PATTERNS.md](REMEDIATION-PATTERNS.md) playbook.
2. **Score each on the fixed rubric** (0–4 per axis):
   - Correctness margin (does this remove the UB or just hide it?)
   - Performance delta (vs. current implementation; benchmark if available)
   - Diff blast radius (LOC / files touched)
   - Reviewability (how easy is the diff to peer-review?)
   - Maintainability (how easy is it to keep correct as the codebase evolves?)
3. **Pick the optimal one**, document rationale.
4. **Record runners-up** with their tradeoffs (preserved for future maintainers).
5. **Cross-reference each remediation** to:
   - The experiment that proves the original is UB
   - The experiment that will prove the remediation is sound

For high-stakes UB sites (e.g., custom allocator, custom lock-free data structure), invoke `/multi-model-triangulation` for a second opinion.

Output: `phase8_remediation_plan.md`.

**Exit criterion:** every `CONFIRMED_UB` finding has a chosen remediation + ≥1 runner-up (where applicable) + cross-references.

---

## Phase 9: BEADS HANDOFF (parallel write phase)

The `bead-author` subagent invokes `/beads-workflow` "EXACT PROMPT — Plan to Beads Conversion" against `phase8_remediation_plan.md`. Then runs the standard polish prompt **4–5 times** (DO NOT OVERSIMPLIFY; DO NOT LOSE FEATURES).

Validation gates (run after every polish round):
```bash
br dep cycles                                  # must be empty
bv --robot-insights | jq '.Cycles'             # must be empty
br list --json | jq '
  .issues[] | select(.title | test("[Rr]emediat")) |
  select((.dependencies // []) | length == 0)
'                                              # must be empty: every remediation has deps
```

Every remediation bead must have:
- At least one **test bead** dependency (Miri / loom / sanitizer / fuzz / property)
- At least one **docs bead** dependency (update `// SAFETY:` comments and `# Safety` doc sections)

After polish steady-state:
```bash
br sync --flush-only
git -C <source-repo> add .beads/
git -C <source-repo> commit -m "Land UB-exorcism beads (run <run-id>)"
```

**Exit criterion:** polish rounds converged; gates green; commit made (with explicit user permission per AGENTS.md).

**Hand-off opportunity — `/testing-golden-artifacts`** for every regression test bead. The Phase 9 `regression-harness-author` subagent should pair every test bead with a frozen golden snapshot of the post-remediation tool output (e.g., `tests/regression/snapshots/<bead-id>_miri.snap` capturing the CLEAN Miri trace). Then CI compares both — a code-level regression breaks the `#[test]`, a tool-output drift breaks the golden. See [INTEGRATIONS.md §With /testing-golden-artifacts](INTEGRATIONS.md#with-testing-golden-artifacts) for the canonicalization recipe (scrub addresses / timestamps / line numbers).

---

## Phase 10: FRESH-EYES REVIEW

Apply the three fresh-eyes prompts (verbatim, in order) against the remediation plan AND the beads AND the experiment designs. Keep iterating until two consecutive passes come up clean except for trivial changes.

**Prompt A** — "great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover."

**Prompt B** — "I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file."

**Prompt C** — "Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!"

Then run static + dynamic gates:
```bash
ubs $(git diff --name-only --cached)            # if ubs is installed
cargo check --all-targets
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo +nightly miri test                        # against any remediations implemented in a scratch branch
```

**Exit criterion:** two consecutive Phase-10 passes produce only trivial changes; all gates green. Log to `phase10_fresh_eyes_log.md`.

---

## Phase 11 (Exhaustive only): SOAK / DEEP-VALIDATION

Long-running campaigns dispatched to `rch` workers:

- **24h fuzz** on every previously-UB-bearing API
- **Multi-day Miri** across the whole test suite under every MIRIFLAGS combination
- **10⁴+ loom iterations** against previously-racy concurrency code
- **Shuttle** with random schedules for code where loom timed out

Designs in `phase11_soak_designs.md`. The `soak-runner` subagent dispatches jobs and polls progress via `rch status`.

Any late-breaking findings get appended to `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`. If they're genuine new UB, loop back to Phase 8.

**Exit criterion:** every campaign finished or timed out with a recorded outcome; no `CONFIRMED_UB` finding without a remediation bead.

---

## Phase 12: FINAL ARTIFACTS

Produce:

### `FINAL_UB_REPORT.md`
- Executive summary (1 paragraph + counts: confirmed, deferred, refuted)
- Full findings table (severity-ranked, with experiment IDs and remediation IDs)
- Convergence-evidence appendix (round-by-round new-finding counts from `phase7_convergence_round_*.json`)
- Open questions (any `DEFERRED` items, with re-check criteria)

### `UB_RUNBOOK.md`
For future maintainers:
- Minimum Clippy lint group to enforce (`-W clippy::pedantic -W clippy::nursery -W clippy::cargo` + the project-specific additions discovered during this audit)
- MIRIFLAGS combinations to wire into CI
- Loom models that must stay green
- Fuzz corpora that must be preserved
- `// SAFETY:` comment template (3 lines minimum; cite invariants by name; reference the enforcing code)
- The `rustc -W` flags worth enabling project-wide
- "If you change X, re-run experiment EXP-Y" recipes

### Polished bead graph
Already in `.beads/` of the source repo. Hand off `br ready` as the user's next-step starting point.

**Exit criterion:** all three artifacts exist; user has been pinged with a summary + a recommendation to either run Phase 13 (auto-remediation) or hand off to humans via `br ready`; workspace is committed.

---

## Phase 13 (OPTIONAL): AUTO-REMEDIATION — Execute the Plan

**The skill is not just a diagnostic tool — it can also execute the remediation plan it just produced.** Phase 13 is OPT-IN: it never runs without an explicit user request, since it mutates the audited source code.

### When Phase 13 is appropriate

- The user has time + context to review the resulting code changes (this phase writes real diffs to the source repo).
- `phase8_remediation_plan.md` has a non-empty list of CONFIRMED_UB or RUNBOOK-grade findings, each with a chosen remediation candidate and a rubric-scored runner-up.
- The bead graph from Phase 9 exists and is consistent (`br dep cycles` empty).
- Either git working tree is clean OR the user has explicitly OK'd mixing remediation diffs with in-flight work.

### When Phase 13 should be DECLINED (the agent says "not now")

- Working tree is dirty AND user has not approved interleaving.
- `phase8_remediation_plan.md` contains a `chosen` candidate the user has not accepted yet (let them edit it first).
- The remediation requires breaking API changes and the user has not confirmed they're OK with that.
- The user is in degraded coordination (Agent Mail down) AND other agents are visibly active on the same files.

### The user-prompt at end of Phase 12

At the close of Phase 12, the main agent MUST ask the user explicitly:

> "All audit artifacts are written. Do you want me to (a) execute the remediation plan I just designed — I'll work through `br ready`, implement each bead, run the regression harness, and close beads as they go — or (b) hand off and let your team take it from here? Phase 13 will modify source files; reply (a) only if you want that. Default = (b)."

Use `AskUserQuestion` (or equivalent). Do NOT proceed to Phase 13 without an explicit affirmative answer.

### Procedure (parallel per independent track; sequential within a track)

For each ready bead chain in `br ready --json`:

1. **Claim and reserve** the edit surface per [ORCHESTRATION.md §Standard reservations](ORCHESTRATION.md#standard-reservations-tools-and-shared-resources):
   ```bash
   br update <id> --claim --json
   # file_reservation_paths(project_key, agent, [paths from bead], ttl=3600, reason="<id>")
   ```
2. **Spawn `remediation-executor` subagent** (see `subagents/remediation-executor.md`). The subagent receives:
   - The bead ID and the chosen remediation candidate from `phase8_remediation_plan.md`
   - The bead's regression test bead (test must FAIL pre-change, PASS post-change)
   - The runner-up candidate as fallback if the chosen approach fails
3. **The subagent executes**:
   - Reads the SAFETY-comment template from [INVARIANT-CATALOG.md](INVARIANT-CATALOG.md) before writing any new `unsafe` block
   - Implements the change in the smallest possible diff
   - Runs the regression test bead — must transition pre-FAIL → post-PASS
   - Runs `cargo check --all-targets`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`, and the project's Miri config from `UB_RUNBOOK.md`
   - If ANY gate fails, the subagent does NOT close the bead — it leaves an audit comment with the failure trace and returns control
4. **Close on success**:
   ```bash
   br close <id> --reason "Phase 13 auto-remediation: <one-line summary>" --json
   br close <regression-test-bead-id> --reason "Phase 13: regression test enforces fix; passes after remediation" --json
   br sync --flush-only
   ```
5. **Hand off on failure**: revert the source to the pre-bead `HEAD` (scope to the bead's declared files via `git restore --source=<PRE_HEAD>`), leave the bead in `in_progress`, add a `phase13-needs-human-review` label, post a comment with both failure traces. The regression-test bead also stays open. Move on to the next ready bead.

The "bead obsolete" sub-case — regression test passes pre-change — closes both beads with reason `"Phase 13: regression test already green; bead obsolete"` without making a commit. The orchestrator's commit-existence gate is conditional on `Pre-change verdict: FAIL` in the log entry.

### Hard rules for the executor subagent

- **NEVER deletes a file** without explicit re-confirmation from the user (per project AGENTS.md).
- **NEVER runs destructive git** (`git reset --hard`, `rm -rf`, `git clean -fd`) under any circumstance.
- **Never bypasses pre-commit hooks** with `--no-verify`. If a hook fails, fix the underlying issue or escalate.
- **Never commits with `Forced close due to cycle`** or equivalent hedge text — resolve cycles via `br dep remove` first.
- The executor is `general-purpose` subagent type (write access required). Spawning it with `Explore` will silently no-op the edits — see [AGENT-PROMPTS.md §Subagent type matrix](AGENT-PROMPTS.md#subagent-type-matrix-read-first).

### The Phase 13 log

```
<workspace>/phase13_remediation_log.md
```

Append-only entry per bead processed:
```markdown
## <bead-id> — <one-line summary>
- Approach: <chosen | runner-up | escalated-to-human>
- Pre-change HEAD: <sha at executor entry>
- Post-change HEAD: <sha after step 7 commit, or same as Pre-change HEAD if obsolete/deferred>
- Files declared: <comma-separated list from the bead's `files` field>
- Files changed: <list>  (or "none — reverted" or "none — bead obsolete")
- Pre-change test verdict: FAIL (expected) | already-PASS (bead obsolete) | NO-TEST-FILE (infrastructure missing)
- Post-change test verdict: PASS | FAIL | NOT_RUN
- Gates: cargo-check=✓ clippy=✓ fmt=✓ miri-default=✓ ...
- Commit SHA: <sha>  (or "—" if obsolete/deferred — equals Post-change HEAD)
- Outcome: CLOSED-WITH-FIX | CLOSED-OBSOLETE | DEFERRED-NEEDS-HUMAN
- Notes: ...
```

### Convergence and exit criterion

Phase 13 ends when one of:
- All Phase 9 beads with `priority <= 2` are CLOSED or labeled `phase13-needs-human-review`.
- The user calls a stop.
- The remediation-executor has consumed its budget (configurable; default: 4 hours wall time, or 12 beads, whichever first).

**Exit criterion:** `phase13_remediation_log.md` exists, summarizing the disposition of every bead the executor attempted. The FINAL_UB_REPORT.md gets a "Phase 13 Execution Log" appendix with bead counts. Commit the workspace + remediation diffs together (separate commits per remediation when practical).

### Optional golden-artifact gate (recommended)

If `/testing-golden-artifacts` was wired in at Phase 9, the executor's step 6 gate suite should include a golden comparison:

```bash
# After cargo +nightly miri test passes, compare its stdout/stderr against the
# pre-recorded "clean Miri" golden for this bead.
cargo +nightly miri test "$TEST_FN" -- --exact 2>&1 \
    | scrub_miri_addresses \
    | diff -u tests/regression/snapshots/{BEAD_ID}_miri.snap - \
    || GOLDEN_FAILED=yes
```

The golden gate catches remediations that change *which* UB Miri sees rather than eliminating UB. Without it, the executor would close the bead on "Miri now passes for the regression test" even if Miri now reports a *different* UB elsewhere in the same run. See [INTEGRATIONS.md §With /testing-golden-artifacts §(d)](INTEGRATIONS.md#with-testing-golden-artifacts) for the rationale.

### What Phase 13 deliberately DOES NOT do

- It does not auto-merge any PR.
- It does not push to a remote (`git push`).
- It does not run `cargo publish`.
- It does not bypass the project's CI — local gates are the floor, not the ceiling.
- It does not synthesize remediations not in `phase8_remediation_plan.md`. If the plan didn't cover a finding, the executor surfaces that gap to the user; it does not improvise.

---

## Per-Phase Time Budgets (Standard mode)

| Phase | Wall-time budget |
|---|---|
| 0 | 5–15 min |
| 1 | 15–30 min |
| 2 | 30–60 min |
| 3 | 30–120 min (parallel) |
| 4 | 20–40 min |
| 5 | 20–90 min (parallel) |
| 6 | 15–30 min |
| 7 | × N rounds; each ~45 min |
| 8 | 30–60 min |
| 9 | 60–120 min (polish-heavy) |
| 10 | 30–90 min |
| 11 | hours to days (offloaded) |
| 12 | 15–30 min |
| 13 | OPTIONAL; 30 min – 4 h depending on bead count |
