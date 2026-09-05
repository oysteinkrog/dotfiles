---
name: rust-undefined-behavior-exorcist
description: >-
  Hunt every flavor of Rust UB (aliasing, races, FFI, Send/Sync, Pin, library
  invariants) via Miri/sanitizers/loom/fuzz; prove, fix, hand off as beads.
  Use when "rust UB audit", "miri sweep", "rustonomicon audit", or "race hunt".
---

<!-- TOC: One Rule | Boundaries | Quick-Start | IO Contracts | Inputs | Bootstrap | Phases | Parallelism | Convergence | Operator Library | Taxonomy | Remediation | Beads | Anti-Patterns | Checklist | References -->

# Rust Undefined Behavior Exorcist

> **The One Rule:** UB is whatever the Rustonomicon says it is — not just the `unsafe { … }` blocks. Hunt the full taxonomy (aliasing, provenance, alignment, validity, FFI contract, `Send`/`Sync`, `Pin`, `MaybeUninit`, panic-safety, unsafe library contracts, and invariant drift that can feed unsafe boundaries), prove each suspect empirically with Miri / sanitizers / loom / shuttle / fuzz, then design the *optimal* fix (not just the first that compiles).

> **Hard workflow invariant: no git worktrees.** This skill must not create, recommend, or clean up git worktrees. Remediation and validation happen in the active checkout or, when historical release tags must be tested, in non-git archive snapshots stored under the audit workspace. Use ordinary branches in the active checkout for PR-shaped work.

> Change history lives in [CHANGELOG.md](CHANGELOG.md). Check it when comparing audit artifacts produced by different skill versions.

---

## First-30-Seconds (read this before anything else)

**Smell test — is this even the right skill?**

| User said... | Use this skill? |
|---|---|
| "Audit Rust project for UB" / "Miri sweep" / "soundness review" | **YES** |
| "Find every UB in `<repo>`" / "use-after-free hunt" / "race-condition hunt" | **YES** |
| "Audit every `unsafe` block" / "remove unsafe / safe-only feature flag" | NO — use `/rust-unsafe-code-exorcist` |
| "Find a deadlock" / "tests hang" | NO — use `/deadlock-finder-and-fixer` |
| "Find any bug, not specifically UB" | NO — use `/multi-pass-bug-hunting` |
| "Review this PR" | NO — use `/review` or `/code-review-gemini-swarm-with-ntm` |

Full differentiation: [references/BOUNDARIES.md](references/BOUNDARIES.md).

**Recipe selector — pick the right path within the skill:**

| User said... | Mode | Workflow | What to do differently |
|---|---|---|---|
| "Miri error in fn X" / specific bug reported | Quick (scoped) | [W6 incident](references/WORKFLOWS.md#w6--incident-response) | Treat reported symptom as `F-001`; scope Phase 0 partition + Phase 1 inventory + Phase 2 sweep to the affected module/buckets; write `EXP-001` from the reported reproducer in Phase 4 and run it FIRST in Phase 5 |
| "Pre-release UB audit / before crates.io" | Exhaustive | [W7 pre-release](references/WORKFLOWS.md#w7--pre-release-gate-cratesio) | All 12 phases + Phase 11 soak; `UB_RUNBOOK.md` is the shipping artifact |
| "Audit this whole project for UB" (generic) | Standard | by archetype — see [PROJECT-TYPES.md](references/PROJECT-TYPES.md) | Full Phase 0; auto-detect archetype |
| "Tests flake under load / TSan reports race" | Quick (concurrency-scoped) | W6-ish (incident-shaped) | If reproducible → treat like W6 incident with the flake as `F-001`. If only flaky → first check [FALSE-POSITIVES.md §T-FP1](references/FALSE-POSITIVES.md) for known TSan false-positive shapes |
| "Set up Miri CI" (no audit yet) | (skill doesn't apply directly) | — | Use [MIRI-CI-TEMPLATE.md](references/MIRI-CI-TEMPLATE.md) directly; offer full audit as next step |
| "Spot-audit just this new feature / module" | Quick (scoped) | W6-ish | Same shape as W6 incident but the trigger is a diff rather than a reported UB; Phase 1 scoped to the diff |
| "Already audited X months ago; refresh" | Quick | [W4 already-mature](references/WORKFLOWS.md#w4--already-mature-crate) | Phase 1 diff against committed baseline |

If none match cleanly, default to **Standard mode + full Phase 0** and let the user clarify during confirmations.

**First actions, in order (for a fresh run):**

> Placeholders below resolve progressively: `<project>` is known after step 1;
> `<run-id>` and `<workspace>` are constructed in step 4. Don't substitute a
> placeholder into a command until the step that resolves it has run.

1. **Read [the "Up-Front User Confirmations" section](#up-front-user-confirmations-ask-before-starting)** and ask the user the 6 questions there *before* doing anything else. This resolves `<project>`, run mode, default workspace location, and toolchain-install permission.
2. **If user gave a git URL** instead of a path in step 1: `git clone <url> /tmp/<basename>` and treat `/tmp/<basename>` as `<project>` from here on.
3. **Check for an existing in-project workspace** — `find <project>/.ub-exorcism -maxdepth 2 -name phase0_run.json -print -quit 2>/dev/null`. If this prints a path, STOP and follow "Resuming an existing run" below before proceeding to steps 4-7.
4. **Create the per-run workspace** at `<workspace> = <project>/.ub-exorcism/<run-id>/` (concrete example for a project at `/data/projects/foo` started today: `/data/projects/foo/.ub-exorcism/2026-05-14-foo-1/`) and write `<workspace>/phase0_run.json` with `{run_id, mode, source_path, started_at, archetype_hint, skipped_tools, skipped_buckets}` — see [references/PHASES.md §Phase 0 step 3](references/PHASES.md#phase-0-bootstrap--partition-515-min-main-agent-only) for the exact `jq -n --arg` invocation (uses jq for JSON-safe escaping; heredocs are avoided because markdown list-item indentation breaks heredoc terminators). This file is the resume lifeline — every later step assumes it exists.
5. **Run `scripts/install-toolchain.sh <workspace> --inventory-only`** to see what's installed without auto-installing. Show the user the inventory; ask which missing tools to install (per [references/FLYWHEEL-TOOLS-INSTALL.md](references/FLYWHEEL-TOOLS-INSTALL.md)).
6. **Run `scripts/preflight-smoke-test.sh <project> <workspace>`** (~30s) — validates the project is auditable BEFORE any fan-out commits. Catches: missing nightly, miri build break, fsqlite-style giant compile, no fuzz targets, broken `cargo check`. Writes the report to `<workspace>/preflight_smoke.json`. Failures here let you abort cheaply. The second arg is optional, but Phase 0 wants the report alongside `phase0_*.json` so always pass it.
7. **Partition the source** per [references/PHASES.md §Phase 0](references/PHASES.md#phase-0-bootstrap--partition-515-min-main-agent-only). Post the partition table to the user before fan-out. Then **fan out Phase-1 subagents** with `subagent_type=general-purpose` per the [Subagent type matrix](references/AGENT-PROMPTS.md#subagent-type-matrix-read-first). **NEVER use `subagent_type=Explore` for any subagent that writes a file** — Explore is read-only and will silently drop output.

**Resuming an existing run** (if `phase0_run.json` already exists):

1. `cat <workspace>/phase0_run.json` to get `run_id`, `mode`, `started_at`, and any `skipped_tools` / `skipped_buckets` recorded so far.
2. Use the compaction-survival protocol in [references/ORCHESTRATION.md §Compaction Survival](references/ORCHESTRATION.md#compaction-survival) — walk the phase artifacts in order; resume from the first incomplete phase.
3. Ask the user: "Resume run `<run-id>` (started `<started_at>`, currently at phase N) — OR start a fresh run?". Do not silently resume; the human needs to know.

**ABORT IF** (common ways to fail; the orchestrator should pre-check):

- ⚠ **The user gave you a project but you skipped the confirmations.** Mode, offload, and toolchain-install permission are not defaultable. Ask first.
- ⚠ **You started Phase 1 without showing the partition table.** Phase 0 has an explicit exit criterion: "Partition plan accepted by user." Don't skip.
- ⚠ **You're about to install via `curl | bash` without explicit user `y`.** Install-toolchain.sh has `--inventory-only` for exactly this reason. Use it.
- ⚠ **You're about to invoke any subagent with `subagent_type=Explore`.** Explore is read-only — it cannot Write/Edit, so any per-phase output file the subagent is supposed to produce gets silently dropped. Use `subagent_type=general-purpose` for every phase-output subagent. See [Subagent type matrix](references/AGENT-PROMPTS.md#subagent-type-matrix-read-first).
- ⚠ **You're about to commit to `.beads/` without explicit user permission.** Phase 9 always asks before pushing.
- ⚠ **You think you can skip the convergence floor.** You can't. The floor depends on the project archetype: ≥10 rounds for unsafe-heavy crates; ≥3 rounds for `#![forbid(unsafe_code)]` pure-safe projects; ≥10 always in Exhaustive mode. See [references/CONVERGENCE.md](references/CONVERGENCE.md) — and don't conflate "fewer rounds" with "skip the gates"; the gates are non-negotiable.
- ⚠ **You're about to delete a file to "clean up".** AGENTS.md Rule #1 — never. Ask first.

**If you only have time to read 4 files**, read these (in order):

1. **This file** (SKILL.md) — the orchestrator playbook
2. **[references/PHASES.md](references/PHASES.md)** — exact per-phase exit criteria
3. **[references/AGENT-PROMPTS.md](references/AGENT-PROMPTS.md)** — verbatim kickoff prompts for every subagent
4. **[references/UB-TAXONOMY.md](references/UB-TAXONOMY.md)** — the 25 buckets you'll be hunting in

The other 44 references are loaded on demand — see [Reference Index](#reference-index) at the bottom.

**What you're about to produce** (the `<source>/.ub-exorcism/<run-id>/` tree):

```
<workspace>/
├── phase0_run.json                                # run metadata, mode, archetype hint
├── phase0_partition.json                          # the per-section partition (modules / FFI / concurrency hubs)
├── phase0_toolchain_inventory.json                # what's installed (status + smoke_test_passed per tool)
├── preflight_smoke.json                           # output of preflight-smoke-test.sh (rustup / nightly / disk / archetype hints)
├── phase1_unsafe_surface_inventory.md             # every unsafe site tagged with bucket(s)
├── phase1_notes/<module>.md                       # per-module digest
├── phase2_findings_<bucket>.md                    # per-bucket findings (sweepers fan out)
├── phase3_dynamic_findings.md                     # miri/sanitizer/loom/fuzz crashes
├── phase3_raw/{miri,asan,tsan,...}_<cfg>.log      # raw tool output
├── phase4_unified_findings.md                     # deduped, severity-ranked table
├── UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md       # ← the registry every hypothesis lives in
├── experiments/<EXP-NNN>/repro.rs                 # per-experiment reproducer
├── phase5_experiment_results/<EXP-NNN>.log        # per-experiment verdict log
├── phase6_idea_wizard.md                          # project-shaped UB techniques
├── phase7_convergence_round_<N>.json              # round-by-round counts
├── phase8_remediation_plan.md                     # rubric-scored rewrite candidates
├── phase9_beads_log.md                            # beads landed in source's .beads/
├── phase10_fresh_eyes_log.md                      # the three verbatim review prompts, round-by-round
├── phase11_soak_designs.md                        # 24h fuzz / multi-day miri (Exhaustive)
├── phase11_artifacts/<campaign>/                  # soak campaign outputs
├── FINAL_UB_REPORT.md                             # executive summary + full findings table
├── UB_RUNBOOK.md                                  # the project's permanent CI gates
├── phase13_remediation_log.md                     # Phase 13 only: per-bead remediation outcomes
└── corpus/                                        # Track-A artifacts (operationalizing-expertise)
```

Beads land in the *source repo*'s `.beads/`, not the workspace.

---

## Boundaries — Don't Confuse With `rust-unsafe-code-exorcist`

| | `rust-unsafe-code-exorcist` | **this skill** |
|---|---|---|
| **Asks** | "Is this `unsafe` block necessary?" | "Is there UB anywhere in this codebase?" |
| **Scope** | Every `unsafe` site — classify (A) unavoidable / (B) perf-only / (C) refactorable | Every UB-taxonomy bucket, *whether or not* the site is inside `unsafe` |
| **Catches** | Macro-generated unsafe, FFI hardening, safe-rewrite candidates | Data races (no `unsafe` needed), unsafe-trait contract violations, FFI contract violations, Miri TB violations, broken `Send`/`Sync`, plus safe-code invariant bugs (`Hash`/`Eq`, `size_hint`) when they can feed unsafe boundaries |
| **Output** | per-site write-ups + `safe-only` feature + refactored code | experiment registry + final UB report + UB runbook + remediation beads |
| **Method** | Classify-then-refactor | Detect-then-prove-then-fix |
| **Compose** | Often runs first to clean up `unsafe`; this skill then verifies the result is *also* UB-free | Often the audit gate before a public crates.io release |

They are **complementary**. Run unsafe-exorcist for `unsafe`-block hygiene; run UB-exorcist to prove the codebase is free of Rustonomicon UB and the soundness-adjacent invariant drift that can feed it. Full breakdown: **[references/BOUNDARIES.md](references/BOUNDARIES.md)**.

---

## Methodology Lineage — What This Skill Inherits vs. Adds

The skill is grounded in the user's actual UB-hunting methodology (mined from 365 days of cass sessions across `/dp/asupersync`, `/dp/frankensqlite`, `/dp/frankenlibc`, `/dp/frankenfs`, `/dp/beads_rust`, `/dp/mcp_agent_mail_rust`, `/dp/pi_agent_rust`, `/dp/rich_rust`, `/dp/frankentui`). See [corpus/primary_sources/cass_quotes.md](corpus/primary_sources/cass_quotes.md) for the ~42 mined quotes spanning Q-001..Q-802 (Q-001..Q-029 = cass ritual quotes; Q-201..Q-206 = exemplar-project quotes; Q-301..Q-802 = release / CI / shape-sweep / bead-ladder quotes).

**What the user already does well** (and the skill preserves verbatim):

- **Ritual 1 — Suspect-list audits** (Q-001, Q-002, Q-033): numbered category audits with "file:line + severity + fix" output + "only report real issues" disclaimer.
- **Ritual 2 — Named-failure-mode questions** (Q-006, Q-007, Q-010, Q-020): "Could there be a race condition between X and Y?" rather than "is this correct?".
- **Ritual 3 — Local-invariant counter-examples** (Q-008): find the property that holds N-1 times, point at the N-th violator.
- **Ritual 4 — Safety-Notes-First** (Q-004): write the unsafe invariants in the prompt *before* any code is generated. The frankensqlite mmap-SHM exemplar.
- **Ritual 5 — Read-only delta frame** (Q-013, Q-014, Q-017, Q-024, Q-025): `git diff --stat` + `git diff` + "do NOT edit any files" before any fix pass.
- **Ritual 8 — Per-project CARGO_TARGET_DIR isolation** (Q-019): isolation-by-env-var, extends to `MIRI_SYSROOT` and fuzz corpus dirs.
- **Ritual 9 — Default-forbid stance** (Q-028): per-crate `#![forbid(unsafe_code)]` is the default; per-crate opt-out only when physically required.

**What the skill adds as an upgrade path** (techniques that don't yet appear in the captured corpus but are central to UB exorcism):

- `cargo +nightly miri test` with the **MIRIFLAGS matrix** (default / tree-borrows / strict-provenance / symbolic-alignment) — zero captured hits in 365 days. The skill teaches this layered onto Ritual 5 ("after every read-only delta frame on TLS/arena/mmap/fcntl, propose a miri pass").
- **Loom + Shuttle models** — layered onto Ritual 4 ("Safety-Notes-First + Loom-Model-First": a 30-line loom model on `Drop` ordering for `MmapBacking`-shape types).
- **TSan / ASan / MSan / LSan matrix** — layered onto Ritual 1's concurrency category (Q-002), in particular `--test-threads=1` for TSan.
- **Kani / Prusti / Creusot** — for the highest-stakes findings (custom allocator, lock-free DS, FFI public API), via operator ⊢ PROVE — invoke the verifier directly (the chosen tool depends on the obligation shape; see [⊢ PROVE in operator_library.md](corpus/specs/operator_library.md)).
- **`cargo fuzz` + structured `Arbitrary` inputs** — layered onto Ritual 4's release-gate (Q-018 currently runs `cargo audit + cargo test`; the skill adds a fuzz step).
- **`cargo-geiger`** — surface-trending lint, layered onto every release pass.

The skill does NOT pretend miri/loom/etc are already in the user's workflow. It positions them as the **natural extension** of what the user is already doing well. Phase 0 user-confirmations include "are you currently running Miri / TSan / loom on this crate?" and the run plan adjusts accordingly.

Full operator library with the 12 mined rituals as operator cards (★ SUSPECT, ♦ COUNTER, ☣ SAFETY-NOTES-FIRST, ⊳ READ-ONLY-DELTA, ☣ FIX-PREP, plus the miri/sanitizer/loom upgrades): **[corpus/specs/operator_library.md](corpus/specs/operator_library.md)**.

---

## Quick-Start (Agent-Ergonomic TL;DR)

```
INPUT  → Rust project path (or git URL)
SKILL  → Bootstrap toolchain → 12-phase loop → polished beads
OUTPUT → <source>/.ub-exorcism/<run-id>/ artifacts + bead graph in source

Run mode (pick at Phase 0):
  Quick      = phases 1–4, 1–2h, surface triage
  Standard   = phases 1–10, ½ day, full audit (DEFAULT)
  Exhaustive = phases 1–12, multi-day, soak campaigns

Convergence = 2 consecutive rounds with <3 new findings AND zero OPEN/NEEDS_REFINEMENT
              AND ≥10 total rounds. Non-negotiable.

Coordination = MCP Agent Mail file reservations (tool://miri/<config>, tool://loom,
               tool://fuzz-corpus/<target>); thread id
               ub-exorcism-<run-id>-phase<N>-<bucket-or-tool>
```

| Stage | Subagent | Reservation | Output file |
|---|---|---|---|
| 1 RECON | unsafe-surface-mapper × N modules | none | `phase1_unsafe_surface_inventory.md` + `phase1_notes/<module>.md` |
| 2 STATIC | static-bucket-sweeper × \|taxonomy\| | none | `phase2_findings_<bucket>.md` |
| 3 DYNAMIC | miri-runner × {tb,sb,sp,sa}, sanitizer × {asan,tsan,msan,lsan}, fuzz, loom, shuttle | `tool://miri/<cfg>`, `tool://sanitizer-build`, `tool://fuzz-corpus/<t>`, `tool://loom` | `phase3_dynamic_findings.md` + `phase3_raw/*.log` |
| 4 SYNTHESIS | synthesizer (1) | none | `phase4_unified_findings.md` + `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` (v1) |
| 5 EXP EXEC | experiment-executor × \|EXP-OPEN\| | `path://<workspace>/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` exclusive ttl 5min | in-place edits + `phase5_experiment_results/<id>.log` |
| 6 IDEAS | idea-wizard-orchestrator | none | `phase6_idea_wizard.md` + appended EXP entries |
| 7 ITERATE | (re-fan-out 2–6) | as above | `phase7_convergence_round_<N>.json` |
| 8 REMEDIATE | remediation-architect (1) | none | `phase8_remediation_plan.md` |
| 9 BEADS | bead-author (1) | `path://<src>/.beads/` exclusive ttl 3600s | beads in source repo + `phase9_beads_log.md` |
| 10 REVIEW | fresh-eyes-reviewer (1) | `path://<src>/.beads/` exclusive ttl 3600s (only while editing beads) | `phase10_fresh_eyes_log.md` |
| 11 SOAK | soak-runner × campaigns (Exhaustive only) | none (dispatched to `rch`; per-campaign thread, no shared file/tool lock) | `phase11_soak_designs.md` + artifacts |
| 12 FINAL | final-artifact-author (1) | none | `FINAL_UB_REPORT.md`, `UB_RUNBOOK.md` |
| 13 EXECUTE (opt-in) | remediation-executor × ready beads (parallel per non-overlapping file scope) | `path://<src>/<bead-files>` exclusive ttl 3600s per bead | source-repo diffs + commits + `phase13_remediation_log.md` |

---

## What This Skill Produces

An in-project audit workspace at `<source>/.ub-exorcism/<run-id>/` containing every artifact of the audit, plus a polished beads graph in the source project's `.beads/`, plus a final report. Drafted by parallel subagents across **12 phases**, repeated until convergence (≥10 rounds; <3 new genuine findings in two consecutive rounds AND every open hypothesis resolved).

**Inputs**
- Rust project path (e.g. `/data/projects/frankensqlite`), or
- Git URL (clone into `/tmp/<repo>/` first, then treat as path), or
- Current working directory if nothing specified.

**Outputs**
- `<source>/.ub-exorcism/<run-id>/` — in-project artifact tree with all phase notes, experiment designs, repros, raw tool output
- `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` — the experiment registry (one entry per hypothesis, with verdict)
- `FINAL_UB_REPORT.md` — executive summary, severity-ranked findings, remediation plan, convergence evidence
- `UB_RUNBOOK.md` — how to stay UB-free going forward (CI Miri flags, loom models, fuzz corpora, SAFETY-comment template, minimum Clippy lint group)
- A polished bead graph in the source project's `.beads/` — every remediation has a test-bead dep AND a docs-bead dep; `br dep cycles` empty

---

## Up-Front User Confirmations (Ask Before Starting)

1. **Target project path?** Confirm absolute path or clone URL. If a GitHub URL, clone to `/tmp/<repo>/` first.
2. **Workspace directory?** Default: `<source>/.ub-exorcism/<run-id>/` inside the project being audited. Confirm OK to create — or confirm resuming if an existing `phase0_run.json` is found there. Do not use a sibling directory.
3. **Run mode?** **Quick** (Phases 1–4 only, 1–2h, surface-level), **Standard** (1–10, ~half-day, full audit), **Exhaustive** (1–12 with Phase 11 soak campaigns, multi-day). Default: Standard.
4. **Toolchain install OK?** The skill needs nightly + miri + rust-src, plus optional cargo-fuzz, cargo-afl, cargo-geiger, cargo-audit, cargo-deny, ast-grep, semgrep, cargo-expand. Run `scripts/install-toolchain.sh <workspace> --inventory-only` first; then OFFER the user three explicit choices:
   - **(a) Auto-install everything missing** — `./scripts/install-toolchain.sh <workspace> --yes`. Use when the user has already said "install whatever you need" or has otherwise pre-approved.
   - **(b) Interactive per-tool** — `./scripts/install-toolchain.sh <workspace>` (needs TTY). The user accepts/declines each tool.
   - **(c) Skip installs and degrade** — proceed without missing tools; affected phase steps will be marked SKIPPED and reported as gaps in the final report.
   Default offer: (a) if the user has expressed urgency/blanket approval, else (b). NEVER install without an explicit approval signal from the user.
5. **Local or `rch` offload?** Recommend `rch exec --` for anything >5 minutes wall time (Miri-on-test-suite, fuzz campaigns, sanitizer builds, soak runs). Local only is fine for small projects.
6. **Missing helper skills?** If `jsm` is installed + authenticated, offer `jsm install` for `/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/beads-workflow`, `/idea-wizard`, `/cass`, `/deadlock-finder-and-fixer`. Non-blocking — inline fallbacks below if missing.

---

## Skill Bootstrap

```bash
# Set WORKSPACE once (per First Actions step 4 — bash treats unquoted
# <source>/<run-id> as redirection operators, so use a real path here).
WORKSPACE="$SOURCE/.ub-exorcism/$RUN_ID"   # SOURCE + RUN_ID from First Actions step 4

# Agent-friendly: probe what's installed without committing to install anything.
# Writes $WORKSPACE/phase0_toolchain_inventory.json with status per tool.
# Workspace must be inside the audited source, e.g. $SOURCE/.ub-exorcism/<run-id>.
./scripts/install-toolchain.sh "$WORKSPACE" --inventory-only

# After showing the user the inventory and getting their per-tool approval
# (via AskUserQuestion or similar), invoke installation interactively:
./scripts/install-toolchain.sh "$WORKSPACE"           # asks per-tool (needs TTY)
# OR, if the user gave blanket approval for everything missing:
./scripts/install-toolchain.sh "$WORKSPACE" --yes     # installs every missing tool
```

Full flywheel-tools install catalog + non-auto-detected tools: **[references/FLYWHEEL-TOOLS-INSTALL.md](references/FLYWHEEL-TOOLS-INSTALL.md)**.

If `jsm` is installed and the user agreed to bootstrap missing skills:

```bash
# Per-skill, after confirming:
jsm install operationalizing-expertise codebase-archaeology codebase-report \
            beads-workflow idea-wizard cass deadlock-finder-and-fixer
```

Inline fallbacks are described in [references/TOOLING.md](references/TOOLING.md) under "Operating without helper skills".

---

## The Phase Loop (Mandatory)

```
Phase 1  RECON                unsafe-surface inventory; per-module parallel
Phase 2  STATIC SWEEP         per-taxonomy-bucket subagent; ast-grep + syn + clippy + geiger
Phase 3  DYNAMIC SWEEP        miri matrix + sanitizer matrix + loom + shuttle + fuzz
Phase 4  SYNTHESIS            single agent; dedupe; first EXPERIMENT-DESIGNS.md
Phase 5  EXPERIMENT EXECUTION fan-out per experiment; verdicts inline
Phase 6  IDEA-WIZARD          30 ideas/round × {2 Std, 3 Exh} rounds; investigate ALL 30 per round
Phase 7  ITERATE 2–6          ≥10 rounds; convergence-tracker.sh gates
Phase 8  REMEDIATION DESIGN   enumerate isomorphic rewrites; rubric-score; pick
Phase 9  BEADS HANDOFF        beads-workflow convert + polish 4–5x; deps validated
Phase 10 FRESH EYES           three review prompts verbatim; twice clean
Phase 11 SOAK (Exhaustive)    24h fuzz / multi-day miri / 1000s of loom iters
Phase 12 FINAL ARTIFACTS      FINAL_UB_REPORT.md + UB_RUNBOOK.md + handoff
Phase 13 AUTO-REMEDIATION     OPT-IN; remediation-executor walks `br ready`; gates per bead
```

**Phases 5–7 are reapply-until-quiet.** A round is "quiet" when *every* open hypothesis is resolved (CONFIRMED / NO_EVIDENCE / DEFERRED-with-rationale) AND the new-findings count is <3. Two consecutive quiet rounds = convergence. Below ten rounds total is non-negotiable for Standard or Exhaustive mode — see [references/CONVERGENCE.md](references/CONVERGENCE.md).

**Phase 13 is opt-in.** At the close of Phase 12, ask the user explicitly whether to execute the remediation plan automatically (the skill mutates source code) or hand off to humans. Default is hand-off. See [references/PHASES.md §Phase 13](references/PHASES.md#phase-13-optional-auto-remediation--execute-the-plan).

Full per-phase playbook with exact prompts: **[references/PHASES.md](references/PHASES.md)** and **[references/AGENT-PROMPTS.md](references/AGENT-PROMPTS.md)**.

### Mode variants

| Mode | Phases | Wall time | When |
|---|---|---|---|
| **Quick** | 1–4 | 1–2 h | Triage; project-shaped sniff; early scoping |
| **Standard** | 1–10 | half-day | Most projects with non-trivial `unsafe` surface |
| **Exhaustive** | 1–12 | multi-day | Custom allocators, lock-free data structures, FFI-heavy crates, anything publishable to crates.io |
| **+ Phase 13** | append after Quick / Standard / Exhaustive | 30 min – 4 h | OPT-IN auto-remediation: skill executes the plan instead of just designing it |

---

## Parallelism Model

```
┌─────────────────────────────────────────────────────────────┐
│  PARTITION (once, main agent)                                │
│  → list top-level modules / FFI surfaces / concurrency hubs  │
└────────────────┬─────────────────────────────────────────────┘
                 ▼
    ┌────────────────────────────────────────────┐
    │ Phase 1 RECON (parallel per module)        │
    │   unsafe-surface-mapper × N                 │
    └────────────────┬───────────────────────────┘
                     ▼
    ┌────────────────────────────────────────────┐
    │ Phase 2 STATIC (parallel per UB bucket)    │
    │   static-bucket-sweeper × |taxonomy|        │
    └────────────────┬───────────────────────────┘
                     ▼
    ┌────────────────────────────────────────────┐
    │ Phase 3 DYNAMIC (parallel per tool)        │
    │   miri-runner × {SB, TB, prov, align}       │
    │   sanitizer-runner × {ASan, TSan, MSan, L}  │
    │   loom-modeler / shuttle-runner / fuzz × M  │
    └────────────────┬───────────────────────────┘
                     ▼
    ┌────────────────────────────────────────────┐
    │ Phase 4 SYNTHESIS (single agent)           │
    │   synthesizer — writes EXPERIMENT-DESIGNS   │
    └────────────────┬───────────────────────────┘
                     ▼
    ┌────────────────────────────────────────────┐
    │ Phase 5 EXPERIMENTS (parallel per hypoth.) │
    │   experiment-executor × |open hypotheses|   │
    └────────────────┬───────────────────────────┘
                     │
            ◄── loop 2–7 until convergence ──►
```

**Coordination:** MCP Agent Mail file reservations on shared tools:
- `tool://miri/<config>` — one Miri run *per config* at a time; different MIRIFLAGS configs build to distinct target dirs and run in parallel
- `tool://loom` — exclusive (loom is single-threaded by design)
- `tool://fuzz-corpus/<target>` — exclusive while writing to a fuzz corpus
- `tool://sanitizer-build/<sanitizer>` — exclusive *per sanitizer family*; ASan + TSan can coexist in separate builds
- `resource://gpu-0` — for fuzz targets that exercise GPU code

Thread IDs: `ub-exorcism-<run-id>-<phase>-<bucket>` (e.g., `ub-exorcism-2026-05-14-phase2-aliasing`).

Full orchestration playbook: [references/ORCHESTRATION.md](references/ORCHESTRATION.md).

---

## Convergence Criteria (Non-Negotiable)

A round closes only when **all** of the following hold:

1. Every open hypothesis in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` has a verdict: `CONFIRMED_UB`, `NO_EVIDENCE`, `NEEDS_REFINEMENT`, or `DEFERRED` (with rationale).
2. Round's new-findings count is recorded by `convergence-tracker.sh` and dumped to `phaseN_convergence.json`.
3. Two consecutive rounds satisfy: new-findings <3 AND zero `NEEDS_REFINEMENT`.

Compaction-survival: every workspace file is the source of truth. An agent dropped mid-run reads `phase*.md` + `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` and resumes from there — no in-memory state.

Details + jq queries to measure progress: [references/CONVERGENCE.md](references/CONVERGENCE.md).

---

## Operator Library (the cognitive moves)

Polish-by-vibes doesn't work for UB. Each finding gets driven through a fixed sequence of *operators* — small cognitive moves with explicit triggers, prompt modules, and exit criteria:

| Operator | What it does |
|---|---|
| `★ SUSPECT` | Something is off — flag a candidate UB site with file:line and rationale |
| `✦ ISOLATE` | Reduce the suspect to the smallest reproducer that still UB-s |
| `◐ REPRO` | Wrap the reducer in a runnable Miri / sanitizer / loom test |
| `⬡ INSTRUMENT` | Add MIRIFLAGS / RUSTFLAGS / tracing to surface the failure mode |
| `⚠ ESCALATE` | When INSTRUMENT can't decide, recruit `/multi-model-triangulation` |
| `⊕ REWRITE` | Enumerate ≥2 isomorphic rewrites; rubric-score; pick |
| `⊙ DEBOUNCE-FALSE-POSITIVE` | Confirm a NO_EVIDENCE finding stays NO_EVIDENCE across a fresh round |
| `⊞ SOAK` | Long-running campaign (24h fuzz / multi-day miri / 10k loom iters) |
| `⌘ REDUCE` | When a remediation passes locally but slows the hot path — shrink the safe shell |

Per-operator triggers, prompt modules, and exit criteria: **[references/OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md)**.

---

## UB Taxonomy

The skill operates over the full Rustonomicon UB surface plus soundness-adjacent invariant buckets, not just visible `unsafe` blocks. Every `unsafe` block is fingerprinted into one or more of these 25 buckets, and each bucket has a dedicated Phase-2 subagent:

| # | Bucket | Examples |
|---|---|---|
| 1 | Aliasing | `&T`/`&mut T` violations via raw pointer; `UnsafeCell` misuse |
| 2 | Provenance | int-to-pointer that loses provenance; pointer arithmetic OOB |
| 3 | Alignment | dereference of misaligned `*const T`; `#[repr(packed)]` field address |
| 4 | Validity invariants | invalid `bool`/`char`/`enum`/`NonNull`/`NonZero*`/`&T`/`&mut T` |
| 5 | Uninitialized memory | `mem::zeroed::<T>()` for non-zero-valid T; `MaybeUninit::assume_init` too early |
| 6 | Type punning | `transmute` between non-layout-compatible types |
| 7 | Data races | non-atomic shared mutation; manual `Send`/`Sync` for non-Sync state |
| 8 | `Send`/`Sync` invariants | thread-unsafe state behind manual `unsafe impl Sync` |
| 9 | `Pin` invariants | moving a `!Unpin` value out of `Pin` |
| 10 | FFI contracts | extern "C" preconditions; `repr(C)`/`repr(transparent)` ABI breakage |
| 11 | Panic safety | dropping half-initialized state; `mem::forget`/`ManuallyDrop` misuse |
| 12 | Library trait invariants | safe trait drift (`Hash`+`Eq`, `Ord`, `size_hint`) plus unsafe allocator contracts |
| 13 | Reference-count lifecycle | dangling `Arc::from_raw` after the original was dropped |
| 14 | Mutation through `*const T` | the namesake violation |
| 15 | Lifetimes & escape | raw pointer outliving its construction scope |
| 16 | Volatile contracts | `read_volatile` on misaligned MMIO; mixed volatile/non-volatile access |
| 17 | Async drop | `block_on` inside `Drop` while a tokio runtime is on the stack |
| 18 | Inline asm | `asm!` clobber list missing a register actually clobbered |
| 19 | Target-feature mismatch | `#[target_feature]` callee invoked without runtime feature detection |
| 20 | Dangling `Box` / allocator pairing | `Box::from_raw` paired with wrong allocator |
| 21 | FFI callback aliasing | C library re-enters Rust while a `&mut` is live |
| 22 | `repr(packed)` field addr | `&packed.field` on a non-aligned field |
| 23 | Observed type changes | `&T as *const T as *mut T` write-through (invalid reference casting) |
| 24 | Coherence violations | `feature(specialization)` lifetime-dependent dispatch |
| 25 | Hash / Eq / Borrow consistency | correctness bug by itself; UB only if unsafe code depends on it |

Per-bucket detection arsenal, common shapes, and reference exemplars: **[references/UB-TAXONOMY.md](references/UB-TAXONOMY.md)**.

---

## Remediation Patterns

When `⊕ REWRITE` fires, the architect enumerates candidate rewrites for the UB shape and scores each on a five-axis rubric (correctness margin / perf delta / diff blast radius / reviewability / maintainability). Common shapes have a playbook:

| Shape | Candidate rewrites |
|---|---|
| Self-referential struct | `Pin<Box<_>>` · arena + index · `Rc<RefCell<_>>` graph · ouroboros / yoke |
| Intrusive linked list | safe doubly-linked `Vec`-backed · arena + `Option<usize>` next · third-party `intrusive-collections` |
| Lock-free queue | `crossbeam::ArrayQueue` · `flume` · `tokio::sync::mpsc` · keep custom + Loom |
| Custom `Send`/`Sync` | external mutex wrapper · `Arc<Mutex<>>` · interior `RwLock` · keep + Loom proof |
| Raw FFI handle | `OwnedFd` / `OwnedHandle` · typed wrapper newtype · `Pin<Box<RawHandle>>` |
| Self-pun via `transmute` | `bytemuck` · `zerocopy` · explicit byte copy · `repr(C)` + named-field access |

Each candidate is recorded with tradeoffs, even the runners-up — so a future maintainer can revisit. Full playbook: **[references/REMEDIATION-PATTERNS.md](references/REMEDIATION-PATTERNS.md)**.

---

## Beads Handoff (Phase 9)

Phase 8 produces `phase8_remediation_plan.md`. Phase 9 converts it to beads using **[beads-workflow](../beads-workflow/SKILL.md)**'s "EXACT PROMPT — Plan to Beads Conversion", then polishes 4–5 rounds with the standard polish prompt (DO NOT OVERSIMPLIFY; DO NOT LOSE FEATURES). Validation gates:

- `br dep cycles` must be empty
- `bv --robot-insights | jq '.Cycles'` must be empty
- Every remediation bead has at least one test-bead dependency (Miri / loom / sanitizer / fuzz / property)
- Every remediation bead has at least one documentation-bead dependency (update `// SAFETY:` comments and `# Safety` doc sections)

---

## Anti-Patterns (Never Do)

| ✗ | Why |
|---|---|
| Grep for `unsafe` and call it an audit | Misses macro-expanded unsafe, FFI contract violations, library-trait invariants |
| Run Miri once with default flags and ship | Tree-borrows + strict-provenance + symbolic-alignment catch different things; run the matrix |
| Mock the database / mock the FFI in concurrency tests | Hides the very race you're hunting — see AGENTS.md feedback |
| "It compiles, so it's sound" | Soundness is empirical until proven; the borrow checker doesn't see raw-pointer aliasing |
| Skip the rewrite-runners-up record | Future maintainers will revisit the choice; lock the alternatives in once |
| Run a soak campaign locally without `rch` | Burns your machine; offload anything >5 min wall time |
| Close a bead without its test- and docs-bead deps | Defeats the point — the next regression has no canary |
| Delete a file to "clean up" the workspace | See AGENTS.md Rule #1; ask first, always |

---

## Pre-Flight & End Checklist

- [ ] Target project + in-project workspace dir confirmed (`<source>/.ub-exorcism/<run-id>/`)
- [ ] `phase0_toolchain_inventory.json` filled; missing tools installed with permission
- [ ] Phase 0: `phase0_toolchain_inventory.json` exists, every required tool is `status:ok` AND `smoke_test_passed:yes` (or the user has explicitly accepted the degraded-tooling path)
- [ ] Phase 0: `preflight_smoke.json` exists with `failed_count:0` (fatal failures abort the run; non-fatal acceptable with user awareness)
- [ ] Phase 0: partition table confirmed by the user and persisted to `phase0_partition.json` BEFORE Phase 1 fan-out
- [ ] Partition posted to user before Phase 1 fan-out
- [ ] Phase 1: per-module unsafe-surface inventory (`phase1_unsafe_surface_inventory.md`)
- [ ] Phase 2: per-bucket findings (`phase2_findings_<bucket>.md`) with severity and draft experiment
- [ ] Phase 3: dynamic findings (`phase3_dynamic_findings.md`) with crash reports / Miri tracebacks
- [ ] Phase 4: unified findings (`phase4_unified_findings.md`) + first `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`
- [ ] Phase 5: every experiment has a verdict
- [ ] Phase 6: idea-wizard produced ≥5 new techniques; ≥1 net-new experiment
- [ ] Phase 7: convergence-tracker reports two consecutive quiet rounds (`phase7_convergence.json`)
- [ ] Phase 8: remediation plan with rewrite candidates + runners-up
- [ ] Phase 9: beads polished 4–5x; `br dep cycles` empty; every remediation has test+doc deps
- [ ] Phase 10: three fresh-eyes prompts ran ≥2x clean each; `ubs` clean (if installed); `cargo +nightly miri test` green on any scratch-implemented remediations
- [ ] Phase 11 (Exhaustive): soak runs dispatched to `rch`; findings looped back
- [ ] Phase 12: `FINAL_UB_REPORT.md`, `UB_RUNBOOK.md`, polished bead graph all in place
- [ ] Phase 12: explicit auto-remediation offer made to user (Phase 13 opt-in prompt fired with `AskUserQuestion` or equivalent)
- [ ] Phase 13 (if user accepted): every CLOSED bead has a regression test that was confirmed FAILING pre-change and PASSING post-change; every DEFERRED bead carries `phase13-needs-human-review`; `phase13_remediation_log.md` complete
- [ ] Workspace `git commit`'d; source repo's `.beads/` synced and committed per AGENTS.md "Landing the Plane"

---

## Reference Index

### Core playbooks
| Need | File |
|------|------|
| Phase-by-phase playbook with exit criteria | [PHASES.md](references/PHASES.md) |
| Exact prompts for every parallel subagent | [AGENT-PROMPTS.md](references/AGENT-PROMPTS.md) |
| Cognitive moves: operator cards + prompt modules | [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md) |

### Methodology
| Need | File |
|------|------|
| The full Rustonomicon + soundness-adjacent catalog | [UB-TAXONOMY.md](references/UB-TAXONOMY.md) |
| **Ten advanced detectors the standard sweep misses** (cross-axis verdict diff, cross-target Miri, build.rs / proc-macro audit, cfg-divergence, differential fuzz, TLS-Drop, panic-across-FFI, `unreachable_unchecked` reachability, custom-allocator audit, niche round-trip) | [UB-ADVANCED-DETECTORS.md](references/UB-ADVANCED-DETECTORS.md) |
| Every tool with exact invocations + pitfalls | [TOOLING.md](references/TOOLING.md) |
| Experiment template + per-bucket exemplar designs | [EXPERIMENT-DESIGNS.md](references/EXPERIMENT-DESIGNS.md) |
| Isomorphic-rewrite playbook per UB shape | [REMEDIATION-PATTERNS.md](references/REMEDIATION-PATTERNS.md) |
| Convergence criteria + measurement queries | [CONVERGENCE.md](references/CONVERGENCE.md) |

### Process
| Need | File |
|------|------|
| Subagent fan-out, mail thread/reservation conventions, beads handoff | [ORCHESTRATION.md](references/ORCHESTRATION.md) |
| Mined gold-standard patterns from exemplar projects with quote-bank anchors | [EXEMPLARS.md](references/EXEMPLARS.md) |
| Common failures + diagnostic recipes | [TROUBLESHOOTING.md](references/TROUBLESHOOTING.md) |
| Per-archetype audit flows (FFI-heavy / concurrency-heavy / layout-heavy / pure-safe / incident / pre-release) | [WORKFLOWS.md](references/WORKFLOWS.md) |
| How this skill composes with neighbors (multi-pass-bug-hunting, idea-wizard, /multi-model-triangulation, etc.) | [INTEGRATIONS.md](references/INTEGRATIONS.md) |
| Authoritative differentiation vs. /rust-unsafe-code-exorcist + other neighbors | [BOUNDARIES.md](references/BOUNDARIES.md) |
| End-to-end worked walkthroughs for every archetype | [COOKBOOK.md](references/COOKBOOK.md) |
| Verbatim kickoff prompts the orchestrator sends per phase + per subagent | [KICKOFF.md](references/KICKOFF.md) |
| Workspace artifact shapes + parsing contracts + merge rules + marker-bounded sections | [ARTIFACTS.md](references/ARTIFACTS.md) |
| Catalogued audit failure modes with corrections | [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md) |
| Mandatory validation gates per phase | [VALIDATION.md](references/VALIDATION.md) |
| Project-specific terminology | [JARGON.md](references/JARGON.md) |
| Per-archetype priors (which UB shapes recur per project type) | [PROJECT-TYPES.md](references/PROJECT-TYPES.md) |
| `#[cfg(miri)]` shim recipes for FFI / syscalls / asm! | [MIRI-SHIMS.md](references/MIRI-SHIMS.md) |
| Sixty-plus SAFETY-invariant patterns with comment templates | [INVARIANT-CATALOG.md](references/INVARIANT-CATALOG.md) |
| Per-tool false-positive catalog with diagnostic recipes | [FALSE-POSITIVES.md](references/FALSE-POSITIVES.md) |
| Frequently asked questions | [FAQ.md](references/FAQ.md) |
| Flywheel-tool detection + curl-bash install one-liners (br, bv, cass, ubs, rch, jsm, ntm, dcg, sbh, dsr, slb) | [FLYWHEEL-TOOLS-INSTALL.md](references/FLYWHEEL-TOOLS-INSTALL.md) |
| `git bisect` adapted for UB (catching UB that wasn't there in `v1.2.0`) | [BISECTION.md](references/BISECTION.md) |
| Prove a remediation is behaviorally equivalent to the original | [COMPARATIVE-TESTING.md](references/COMPARATIVE-TESTING.md) |
| Coordinated security disclosure when the UB is in a shipped crate | [DISCLOSURE.md](references/DISCLOSURE.md) |
| Backport the fix to older supported versions | [BACKPORTING.md](references/BACKPORTING.md) |
| UB at the Rust ↔ C / C++ / Python / JS boundary | [POLYGLOT.md](references/POLYGLOT.md) |
| Post-audit life: maintenance, refresh cadence, runbook care | [LIFECYCLE.md](references/LIFECYCLE.md) |

### Cass-mined depth references (corpus round 2)
| Need | File |
|------|------|
| Verbatim fresh-eyes prompts + the ↻A AGENTS.md prefix ritual (Q-201..206) | [FRESH-EYES-OPERATORS.md](references/FRESH-EYES-OPERATORS.md) |
| Same-shape multi-site sweep methodology (Q-801) | [SHAPE-SWEEP.md](references/SHAPE-SWEEP.md) |
| Adversarial pointer fault injection matrix template (Q-101) | [UB-TEST-MATRIX.md](references/UB-TEST-MATRIX.md) |
| Unsafe mmap/SHM introduction checklist (Q-102) | [SHM-AND-FENCES.md](references/SHM-AND-FENCES.md) |
| "Looked benign, was UB" pattern catalog | [HIDDEN-BARRIERS.md](references/HIDDEN-BARRIERS.md) |
| Concurrency soundness as a peer UB lane to memory UB (Q-103) | [CANCEL-CORRECTNESS.md](references/CANCEL-CORRECTNESS.md) |
| The 5-step bead ladder execution pattern (Q-802) | [UB-BEAD-LADDER.md](references/UB-BEAD-LADDER.md) |
| Exact frankensearch Miri CI YAML (Q-701) | [MIRI-CI-TEMPLATE.md](references/MIRI-CI-TEMPLATE.md) |
| Modern `cargo-deny` `db-urls` form (Q-601) | [CARGO-DENY-TEMPLATE.md](references/CARGO-DENY-TEMPLATE.md) |
| CVE arena per-bead artifact layout (Q-602, Q-101) | [CVE-ARENA-LAYOUT.md](references/CVE-ARENA-LAYOUT.md) |
| Active-checkout conventions replacing the retired worktree flow (Q-301 superseded) | [WORKTREE-PATTERNS.md](references/WORKTREE-PATTERNS.md) |
| Forward-only topological re-publish (Q-501) | [RELEASE-FORWARD-ONLY.md](references/RELEASE-FORWARD-ONLY.md) |
| User's encoded remediation preferences | [REMEDIATION-PRINCIPLES.md](references/REMEDIATION-PRINCIPLES.md) |
| Detailed worked audits from /dp/* exemplars | [CASE-STUDIES.md](references/CASE-STUDIES.md) |

### Track-A Corpus (operationalizing-expertise format)
| Need | File |
|------|------|
| Stable-anchored quotes from primary sources (cass + exemplars) | [corpus/quote_bank/quote_bank.md](corpus/quote_bank/quote_bank.md) |
| Verbatim user cass-session quotes (~42 quotes spanning Q-001..Q-802: cass ritual quotes + exemplar quotes + release/CI/shape-sweep quotes) | [corpus/primary_sources/cass_quotes.md](corpus/primary_sources/cass_quotes.md) |
| Triangulated kernel (marker-bounded invariants I1..I15) | [corpus/specs/triangulated_kernel.md](corpus/specs/triangulated_kernel.md) |
| Operator cards in extractable marker-bounded form | [corpus/specs/operator_library.md](corpus/specs/operator_library.md) |
| Session kickoff identity templates | [corpus/specs/session_kickoff.md](corpus/specs/session_kickoff.md) |

### Scripts
| Script | Purpose |
|---|---|
| `scripts/preflight-smoke-test.sh` | Phase 0 pre-fan-out validation — confirms nightly + miri + cargo metadata + disk space + archetype hints before any subagent is spawned (~30s) |
| `scripts/install-toolchain.sh` | Detect + install nightly, miri, sanitizers, fuzz crates, ast-grep, etc. (with per-tool smoke-test post-install) |
| `scripts/run-miri-matrix.sh` | Run Miri across the MIRIFLAGS matrix (SB, TB, strict provenance, symbolic alignment) |
| `scripts/miri-axis-differ.sh` | Diff verdicts across the MIRIFLAGS axes after run-miri-matrix.sh — surfaces tests one axis accepts and another rejects (free signal; ~10s) |
| `scripts/run-sanitizer-matrix.sh` | Run ASan, TSan, MSan, LSan against the test suite + fuzz harnesses |
| `scripts/run-loom-matrix.sh` | Drive every `#[cfg(loom)]` test under loom |
| `scripts/run-fuzz-campaign.sh` | Launch fuzz targets with bounded wall time, collect corpora + crashes |
| `scripts/run-kani.sh` | Bounded model check via Kani for high-stakes findings (custom allocator, lock-free DS, FFI public API) |
| `scripts/ast-grep-ub-patterns.sh` | Run the bundled pattern set (see `scripts/patterns/`) |
| `scripts/syn-walkers/` | syn-based walkers for predicates ast-grep can't express |
| `scripts/convergence-tracker.sh` | Compute round-over-round new-finding counts; exit non-zero until convergence |
| `scripts/generate-ub-runbook.sh` | Phase 12: emit a starter `UB_RUNBOOK.md` from workspace artifacts |
| `scripts/lint-experiment-designs.py` | Validate every `## EXP-NNN` block has the mandatory fields and a valid verdict |
| `scripts/validate-corpus.py` | Check corpus markers (KERNEL-START/END, OPERATOR-START/END) are balanced and well-formed |
| `scripts/validate-skill.py` | Wrapper that delegates to writing-skills' validator |
| `scripts/validate-phase.sh` | Run the per-phase gates from [VALIDATION.md](references/VALIDATION.md) for a given workspace + phase number (or `all`). Mechanizes file-existence, grep, and jq checks; surfaces qualitative gates as `[?] MANUAL`. |
| `scripts/verify-phase-artifacts.sh` | After a parallel fan-out, verify every declared output file exists and is non-empty. Catches the "subagent reported done but file isn't on disk" failure mode. |
| `scripts/shape-sweep.sh` | Given a confirmed UB at one site, sweep the source for every other site with the same lexical/syntactic/semantic shape. Dispatches to `rg`/`ast-grep`/`semgrep`. |
| `scripts/bisect-ub.sh` | `git bisect` wrapper that uses a per-experiment Miri reproducer as the bisect test. Two modes: per-commit test (invoked by `git bisect run`) and full-drive (`--drive`). Handles flaky tests, toolchain pinning, merge-commit reporting. |
| `scripts/cancel-correctness-audit.sh` | ast-grep audit for `pub fn`s that perform blocking syscalls without a cancellation handle (`cx: &Cx` by default; configurable). Covers ~20 blocking primitives. |
| `scripts/miri-unsupported-extract.sh` | Extract + group + frequency-sort "unsupported operation" errors from Miri output. Stdin filter or `<workspace>` mode. Routes each op to its [MIRI-SHIMS.md](references/MIRI-SHIMS.md) recipe. |
| `scripts/disclosure-template-author.sh` | From a CONFIRMED_UB EXP-NNN block, draft a RustSec advisory TOML + companion advisory.md. Every reviewable field marked `NEEDS-REVIEW:`. |
| `scripts/backport-runner.sh` | Re-test a per-experiment UB reproducer against multiple release tags using non-git archive snapshots under the audit workspace; produces a backport-candidate matrix. |
| `scripts/release-forward-only.sh` | Topological re-publish of every crate in a workspace; verifies clean tree + version match, publishes in dependency order with crates.io-index sleep, creates annotated tag, prints (does NOT execute) the push commands per AGENTS.md. |
| `scripts/drift-monitor.sh` | Between full audits, detect drift signals warranting a spot-audit (new unsafe blocks, dep bumps, toolchain bumps, new `extern "C"`, new `loom::` use, fresh RustSec advisories). |
| `scripts/install.sh` | Top-level installer for the skill's flywheel tools (br, bv, cass, ubs, rch, jsm, ntm, dcg, sbh, dsr, slb) plus delegation to `install-toolchain.sh` for Rust-side tools. Inventory-only / interactive / `--yes` modes. |
| `scripts/rustonomicon-antipatterns.sh` | Run a 24-rule ast-grep ruleset derived directly from the Rustonomicon's "Don't do this" examples (D-11 in UB-ADVANCED-DETECTORS.md). Each hit cites the Rustonomicon URL that documents WHY it's UB, so a finding is self-documenting. ~30 seconds; Quick mode runs it. |

### Subagents
| Subagent | Purpose |
|---|---|
| `subagents/unsafe-surface-mapper.md` | Phase 1: enumerate unsafe surface for one module |
| `subagents/static-bucket-sweeper.md` | Phase 2: own one UB-taxonomy bucket end-to-end |
| `subagents/miri-runner.md` | Phase 3: drive Miri across the MIRIFLAGS matrix |
| `subagents/sanitizer-runner.md` | Phase 3: drive ASan/TSan/MSan/LSan builds |
| `subagents/fuzz-author-and-runner.md` | Phase 3: author missing fuzz targets and run campaigns |
| `subagents/loom-modeler.md` | Phase 3: build loom models for concurrency primitives |
| `subagents/shuttle-runner.md` | Phase 3: complement loom with shuttle's probabilistic search |
| `subagents/synthesizer.md` | Phase 4: dedupe + cross-link + write EXPERIMENT-DESIGNS |
| `subagents/experiment-designer.md` | Phase 4 / Phase 6: design new experiments |
| `subagents/experiment-executor.md` | Phase 5: run one experiment, record verdict |
| `subagents/idea-wizard-orchestrator.md` | Phase 6: drive `/idea-wizard` Phase 2 prompt for project-shaped UB |
| `subagents/remediation-architect.md` | Phase 8: enumerate rewrites + score + pick |
| `subagents/bead-author.md` | Phase 9: convert + polish beads |
| `subagents/fresh-eyes-reviewer.md` | Phase 10: the three fresh-eyes prompts, verbatim |
| `subagents/soak-runner.md` | Phase 11: long campaigns via `rch` |
| `subagents/soak-designer.md` | Phase 11: design the campaigns soak-runner executes |
| `subagents/bisection-runner.md` | Phase 8 helper: `git bisect run` to find UB-introducing commit |
| `subagents/miri-shim-author.md` | Phase 3 helper: author `#[cfg(miri)]` shims for FFI Miri can't run |
| `subagents/regression-harness-author.md` | Phase 8/9: author the test that guards the fix |
| `subagents/polyglot-boundary-auditor.md` | Phase 2: Rust↔C/C++/Python/JS boundary specialist |
| `subagents/shape-sweeper.md` | Phase 8: find all same-shape sites before remediation |
| `subagents/disclosure-author.md` | Phase 12 helper: RUSTSEC advisory drafting |
| `subagents/triangulation-coordinator.md` | Helper: invoke /multi-model-triangulation for high-stakes findings |
| `subagents/ub-runbook-author.md` | Phase 12: writes the project's permanent UB_RUNBOOK.md |
| `subagents/ci-integration-author.md` | Phase 12: converts UB_RUNBOOK CI section into a workflow file |
| `subagents/kani-prover.md` | Phase 8: Kani bounded model checking for highest-stakes findings |
| `subagents/semgrep-author.md` | Phase 2: custom semgrep rules for dataflow-shaped UB |
| `subagents/kernel-keeper.md` | Maintains Track-A corpus + kernel + operator library |

---

## Self-Test

Trigger phrases that should activate this skill:

- "Audit `<rust-project>` for undefined behavior"
- "Run a Miri sweep on this Rust repo"
- "Find every UB site in `<repo>`"
- "Soundness review of this `unsafe` module"
- "Hunt use-after-free in `<repo>`"
- "Rustonomicon audit on this codebase"
- "Exorcise unsafe from `<crate>`"
- "Run miri + loom + fuzz on this Rust project and tell me everything that's wrong"

Full trigger list + end-to-end smoke test on a tiny repo: [SELF-TEST.md](SELF-TEST.md).
