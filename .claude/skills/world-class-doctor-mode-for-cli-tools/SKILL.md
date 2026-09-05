---
name: world-class-doctor-mode-for-cli-tools
description: >-
  Add or upgrade a CLI tool's `doctor` subcommand — agent-ergonomic, idempotent,
  reversible, backup-aware, routed through a single `mutate()` chokepoint with
  capabilities reflection, robot-docs, fixtures, and per-run scoring artifact.
  Use when: "add doctor", "upgrade doctor", "make CLI agent-friendly", "absorb
  playbook into doctor", "self-healing CLI", or any broken CLI state needing
  safe auto-remediation. Language-agnostic; 24-axiom kernel; ≥700 on 10-dim
  rubric.
---

<!-- TOC: One Rule | What This Skill Produces | Inputs | Up-Front Confirmations | Skill Bootstrap | Mode Router | Phase Loop | Parallelism Model | The Ten Scoring Dimensions | Polish Bar | Cognitive Operators | Workspace + Run-Artifact Layout | IO Contracts | Doctor Surface (CLI Spec) | Safety Envelope | Cookbook (15 patterns) | Versioning | Anti-Patterns | Failure Modes | Pre-Flight + End Checklist | Reference Index | Scripts | Subagents | Assets | Self-Test -->

> **Quick start.** Coming in cold? Read in this order:
> 1. **[assets/skill-card.md](assets/skill-card.md)** — one page; decide if this is the right skill (~2 min)
> 2. **This SKILL.md** — the spine (~10–15 min). The Mode Router below routes you by situation.
> 3. **[KERNEL.md](references/methodology/KERNEL.md)** + **[COOKBOOK.md](references/methodology/COOKBOOK.md)** + **[WORKED-EXAMPLE.md](references/methodology/WORKED-EXAMPLE.md)** — the 24 axioms, the 15 project patterns, and one end-to-end example (~20 min skim)
>
> If you'd prefer a minute-by-minute runbook, follow **[FIRST-30-MINUTES.md](references/methodology/FIRST-30-MINUTES.md)** instead — it's the same content sequenced as a wall-clock walkthrough.
>
> Everything else under `references/` is pull-when-needed. The Reference Index near the bottom of this file is the lookup table.

# World-Class Doctor Mode for CLI Tools

> **The One Rule.** A `doctor` is a contract with a future agent who has no context, no human nearby, and one shot to make the tool work again. **Detect-then-fix, never fix-then-detect.** Every mutation is preceded by a verbatim backup, recorded in a single chokepoint, paired with an explicit inverse, and fingerprinted by content hash. If a fix can't be undone byte-for-byte from the artifact in `.doctor/runs/<run-id>/backups/`, it doesn't ship. If `doctor --fix` and `doctor undo <run-id>` aren't a true inverse pair, the doctor is broken regardless of what its scorecard says.

> **What this skill does.** Pointed at any CLI repo, this skill either **adds** a `doctor` subcommand if none exists, or **dramatically upgrades** an existing `doctor` / `health` / `verify` / `repair` / `check` / `diagnose` / `fix` until it is **maximally automated, safe-by-default, idempotent, reversible, backup-aware, and primarily designed for AN AI AGENT AS THE CALLER** (a non-interactive Claude/Codex/Gemini/Cursor in a sandbox with no TTY, no network, and no human to ask). Every run emits a durable scoring artifact so the next pass can measure uplift; every fixable failure mode in the project's bug tracker (`br ready`, GitHub issues), git history (`git log --grep=fix\|panic\|corrupt\|race`), and prior-incident memory (mined via `cass`) is converted into a (detector, fixer, fixture, regression-test) tuple wired through the `mutate()` chokepoint.

---

## What This Skill Is For

You point this skill at a CLI tool repo and ask one of these:

1. *"Add a `doctor` subcommand to this CLI."*
2. *"Upgrade `<tool> doctor` until it's world-class — agent-friendly, safe, reversible, scored."*
3. *"Take this manual repair playbook (`fixing-beads-problems`, `system-performance-remediation`, `dcg`'s help text…) and absorb it INTO the binary as `<tool> doctor --fix`."*
4. *"Add `<tool> doctor capabilities --json`, `<tool> doctor health`, `<tool> doctor robot-docs`, `<tool> doctor undo <run-id>`."*
5. *"Re-run the doctor build on `<tool>` and tell me what improved since pass-N."*
6. *"Build a fixture suite and a fresh-eyes review loop for the doctor of `<tool>`."*

Each request routes through the same kernel (the One Rule + Safety Envelope), the same operator library, the same **ten-dimension rubric** (with 0–1000 scoring per item), and the same **ten-phase loop** that you can re-enter idempotently across passes.

**Not in scope.** This skill does not redesign the CLI's *features*. It builds the *self-healing* surface — the contract that "if your install is broken, the binary itself can describe and (where safe) repair its own state, leaving an artifact a future agent can read." Feature work is filed as beads, never bundled into a doctor pass.

---

## Inputs

- **Target CLI repo path** (default: cwd) — absolute path, OR a git URL we should clone into `/tmp/<basename>`.
- **Doctor workspace path** (default: `<repo>__doctor_workspace/` as a sibling) — auto-detected if it already exists; resumes prior pass.
- **Pass number** (auto-detected from `<workspace>/manifest.json`; first run = `pass 1`).
- **Mode** — `add` (no existing doctor) | `upgrade` (existing doctor, score against baseline) | `audit-only` | `re-score-only` | `single-failure-mode-rescore`. Default: `auto-detect`.
- **Operating location** — `in-place` (work directly on the target repo) | `worktree` (create `<repo>__doctor_workspace/worktree/` linked git worktree on a feature branch). **Default: `worktree`** with branch `doctor-mode-pass-<N>`.
- **Tool language(s)** — auto-detected by `scripts/discover-cli.sh` (Rust / Go / Python / TS / Bun / Deno / Ruby / C / C++ / Zig / Elixir / Bash); the skill won't install a missing toolchain without explicit user approval.
- **Binary entry points** — auto-detected (Cargo bin, `package.json` bin, Go `cmd/*`, Python `entry_points`, Bash exec scripts). User can override.
- **Triangulation appetite** — `none` | `peer-claude` | `multi-model` (Claude + Codex + Gemini via `/multi-model-triangulation`). Default: `peer-claude` for `audit-only`, `multi-model` for `add`/`upgrade`.
- **CASS mining appetite** — `skip` | `quick` (10 canned queries) | `deep` (38+ queries against your prior agent sessions). Default: `quick` first pass, `skip` on resumed passes.
- **Online appetite** — `offline-only` (default; doctor works in a sandbox with no network) | `online-allowed` (probes opt-in via `--online`).

## Up-Front Confirmations (Ask Before Starting)

Use the intake template at `assets/intake-prompt.md` verbatim. The summary:

1. **Target repo path or URL?** Confirm absolute path. If GitHub URL, ask before cloning to `/tmp/<basename>`. **Never clone into a path the user didn't approve.**
2. **Binary name(s) the project produces?** Auto-detected; confirm. (e.g., `br`, `cass`, `am`, `dcg`, `caam`, `xf`, `ntm`.) Multiple binaries → each gets its own scorecard slice.
3. **Existing doctor surface?** `scripts/discover-cli.sh --probe-doctor` recursively walks `--help` looking for `doctor` / `health` / `verify` / `repair` / `check` / `diagnose` / `fix`. If one exists, we **snapshot its current behavior** into `<workspace>/baseline/` (its `--help`, `--json` output on a healthy and corrupted fixture, exit-code dictionary) so the upgrade can be scored against it.
4. **In-place or worktree?** Default: worktree at `<workspace>/worktree/` on branch `doctor-mode-pass-<N>` (created from `git worktree add`, NOT a fresh `git init`). The worktree shares the parent repo's `.git/`; doctor work belongs to the project it heals.
5. **Mode confirmation.** `add` (no existing doctor) | `upgrade` (existing doctor) | `audit-only` (no code changes — just score and recommend). Auto-detected; user can override.
6. **Toolchain consent.** Phase 5 needs to invoke the binary; if `cargo` / `go` / `uv` / `bun` / `npm` / `pnpm` / `mix` / `cmake` is missing for the target's language, ask before installing.
7. **Triangulation + CASS appetite** — confirm defaults above.
8. **Branch protection + safe push policy.** Confirm: feature branch only; we never push to `main`/`master`; merging is the user's call. We commit per phase so the diff is reviewable.
9. **Online probes consent.** Default is offline-only. If the user wants the doctor to probe DNS / TLS / a vendor API, that becomes opt-in via `--online`.
10. **`jsm` autoinstall consent for missing helper skills** — confirm we may run `jsm install <name>` for each missing skill from the inventory.

After the user answers, send the matching kickoff prompt from [references/methodology/KICKOFF-PROMPTS.md](references/methodology/KICKOFF-PROMPTS.md) verbatim.

### Autonomous defaults (when the user is unavailable)

If the agent is dispatched without the user present (e.g., via cron, `/loop`, or scheduled execution), use these safe defaults instead of blocking on the intake — every choice below is the LEAST-DESTRUCTIVE option:

| Question | Autonomous default | Rationale |
|----------|--------------------|-----------|
| 1. Target path | Use `pwd` if not specified; abort with run-id artifact if missing | Never invent a clone target |
| 4. In-place vs worktree | **worktree** (`--worktree --pass=1`) | Isolates pass output from user's working tree |
| 5. Mode | **`audit-only`** | No code changes without explicit approval |
| 6. Toolchain consent | **deny** (skip Phase 5 if toolchain missing) | Never install without consent |
| 7. Triangulation appetite | **peer-claude only** (no Codex/Gemini paid calls) | No surprise spend |
| 7. CASS appetite | **quick** (top-3 sessions only) | Fast, low-token |
| 8. Branch protection | **feature branch only**; never push | Always safe |
| 9. Online probes | **offline-only** (no `--online`) | No surprise network egress |
| 10. jsm autoinstall | **deny** | Skill missing = inline fallback per SKILL-FALLBACKS.md |

The `audit-only` autonomous mode produces `recommendations.jsonl` + `playbook.md` and stops; the user reviews and re-runs in `add`/`upgrade` mode when present.

If any helper skill referenced here is missing (`/operationalizing-expertise`, `/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools`, `/codebase-archaeology`, `/codebase-report`, `/multi-pass-bug-hunting`, `/multi-model-triangulation`, `/ubs`, `/dcg`, `/agent-mail`, `/beads-br`, `/beads-bv`, `/cass`, `/idea-wizard`, `/testing-fuzzing`, `/testing-metamorphic`, `/testing-conformance-harnesses`, `/testing-golden-artifacts`, `/testing-real-service-e2e-no-mocks`, `/cc-hooks`, `/gh-actions`, `/gh-cli`): if the user has `jsm` installed and authenticated, offer to `jsm install <name>` for each missing one. Don't block a phase if a polish skill is missing — note it and proceed with the inline fallback in [references/methodology/SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md).

---

## Skill Bootstrap (Phase 0 — right after inputs, before Phase 1; matches [PHASES.md § Phase 0](references/methodology/PHASES.md))

**Step 0 (recommended once per skill checkout):** run [SELF-TEST.md](SELF-TEST.md) end-to-end against a throwaway tinycli. It takes ~30 seconds and validates that the harness scripts work on this machine before you apply them to a real project. Skip if you've run SELF-TEST in the last 30 days against the current skill version.

```bash
./scripts/preflight-check.sh <workspace>
# Verifies required external tools (jq, git, python3, awk, sed) plus optional
# jsm/cass/br/bv/agent-mail adapters. Writes <workspace>/preflight.json and
# fails early if a required tool is missing.

./scripts/check-skills.sh <workspace>
# Inventories helper skills + jsm state; writes phase0_skill_inventory.json

./scripts/discover-cli.sh <target> --probe-doctor > <workspace>/phase0_cli.json
# Detects language, build system, binary entry points, completion-script paths,
# config-file schemas, env-var prefix conventions, embedded man pages.
# `--probe-doctor` ALSO walks the discovered binary's --help and reports any
# existing doctor / health / verify / repair / check / diagnose / fix surfaces;
# omit it if you only need language/build/binary detection.

./scripts/scaffold-workspace.sh <workspace> <target>
# Creates analysis/, fixtures/, baseline/, runs/ index dirs and (if requested)
# a worktree at <workspace>/worktree/ on branch doctor-mode-pass-<N>.
# DOES NOT init a new git repo — the worktree shares the target's .git.

./scripts/mine-changelog.py <target> --workspace <workspace>
# Mines the target's CHANGELOG.md for past bug-fix entries. Each entry becomes
# a candidate failure mode the doctor should detect. Output:
# <workspace>/changelog_findings.jsonl (consumed by Phase 1 archaeologist).

./scripts/cass-mine.sh <target> <workspace>
# Runs the 13 canonical CASS queries from CASS-PLAYBOOK.md and emits
# <workspace>/cass_findings.jsonl. If cass is not installed, it records the
# absence explicitly so Phase 1 can rely on bug tracker + git-log evidence.

./scripts/query-corpus.py --language "$(jq -r .language <workspace>/phase0_cli.json)" \
    > <workspace>/known_fms_for_language.jsonl
# Pre-suggested FMs from the cross-project corpus
# (references/corpus/known-fms.jsonl), filtered to this target's language.
# Phase 1 archaeologist uses these as a seed list.
```

If skills are missing and `jsm` is installed + authenticated:

```bash
./scripts/install-referenced-skills.sh <workspace>
```

If `jsm` isn't installed, offer the official installer (Linux/macOS):

```bash
curl -fsSL https://jeffreys-skills.md/install.sh | bash
```

Then `jsm login`. Requires a paid [jeffreys-skills.md](https://jeffreys-skills.md) subscription to install premium skills. The pipeline degrades gracefully — every helper skill has an inline fallback.

Full bootstrap detail (subscription checks, headless OAuth, offline fallback): **[references/methodology/SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md)**.

---

## Mode Router

Pick the primary mode first. The phase loop is the same; the **stop conditions and required artifacts** differ.

| Mode | Use when | Must finish with |
|------|----------|------------------|
| `add` | No `doctor` (or `health`/`verify`/`repair`/`check`/`diagnose`/`fix`) subcommand exists | full ten-phase loop; new `doctor` subcommand on feature branch; ≥ 1 fixture per failure mode; ≥ 2 clean fresh-eyes passes; scorecard at run-1 establishes baseline |
| `upgrade` | An existing diagnostic surface exists | snapshot baseline; full ten-phase loop; uplift_diff.md vs. baseline; no surface regressed > 50 pts; existing flags preserved or deprecated through warning, never silently broken |
| `audit-only` | User wants the rubric scored against the current binary, no code changes | scorecard.json + scorecard.md + heatmap.svg + recommendations.jsonl + playbook.md; no feature branch, no commits |
| `re-score-only` | Resumed run; user wants Phase 6 re-run against current target HEAD | scorecard_pass_<N+1>.md + uplift_diff.md + regression_alerts.md |
| `single-failure-mode-rescore` | Targeted; user added one detector/fixer and wants its score | one row appended to `failure_mode_scores.jsonl`; rest unchanged |
| `absorb-playbook` | Convert an existing manual repair skill (e.g. `fixing-beads-problems`) into automated `doctor` repairs | each playbook section → (detector, fixer, fixture, regression-test) tuple; original playbook updated to demote to fallback ("run `<tool> doctor --fix` first") |

Auto-detect heuristics: `scripts/discover-cli.sh` checks for an existing `doctor`/`health` subcommand and the presence of a `<workspace>/manifest.json`. Picks a default; user overrides.

Full mode definitions, exit criteria, and required artifacts: **[references/methodology/OPERATING-MODES.md](references/methodology/OPERATING-MODES.md)**.

---

## The Phase Loop (Mandatory)

```
Phase 1   PROJECT ARCHAEOLOGY + FAILURE-MODE INVENTORY (parallel by subsystem)
Phase 2   REPAIR SPECIFICATION                          (parallel, same agent per subsystem)
Phase 2.5 SPEC REVIEW                                   (single reviewer; gates Phase 3) [Pair+ tier]
Phase 3   SYNTHESIS + HARMONIZATION                     (single agent: taxonomy, dep graph, conflicts, safety envelope)
Phase 4   IMPLEMENTATION                                (parallel by subsystem, gated on Phase 3)
Phase 5   SAFETY HARNESS                                (reversibility, idempotence, crash-recovery, concurrency, detector metamorphic)
Phase 6   AGENT-ERGONOMIC SURFACE + SCORECARD           (capabilities, robot-docs, --robot-*, scorecard generator)
Phase 7   MULTI-PASS FRESH-EYES REVIEW                  (three calibrated prompts; until two clean passes)
Phase 8   INTEGRATION + DOGFOODING                      (pre-commit, CI, related-skill demotion)
Phase 9   REAL-WORLD FIXTURE SUITE                      (one fixture per failure mode + worst-pair combos)
Phase 10  FINAL AGENT-UX PASS                           (fresh agent invokes cold; feedback → one polish pass)
```

Phase 2.5 (spec-review) is added at Pair+ tier; Solo tier omits it. Phase 5's built-in metamorphic verifier checks detector repeatability; optional extensions (`/testing-fuzzing`, `/testing-metamorphic` for deeper property tests, `/testing-conformance-harnesses`, `/testing-golden-artifacts`, `/testing-real-service-e2e-no-mocks`) are wired in [TESTING-INTEGRATION.md](references/methodology/TESTING-INTEGRATION.md).

**Phases 4, 5, 7** are *reapply-until-quiet* — keep spawning passes until an entire pass produces only trivial edits. Phase 7's two clean rounds are the explicit termination gate before Phase 8.

**Phase 7 fresh-eyes prompts** (use verbatim — they're calibrated):

1. *"Reread the new doctor code with fresh eyes. Look for obvious bugs, races, partial-write windows, unsafe `unwrap`/`expect`/panics on user paths, missing backups, broken idempotence, or any place where exit codes lie about reality. Carefully fix anything you uncover."*
2. *"Randomly pick three detectors and three fixers; trace their full execution including the `mutate()` chokepoint, backup write, and undo path. Construct a scenario that would corrupt user data and prove the code prevents it — or fix it."*
3. *"Review your fellow agents' code without restricting to recent commits. Find root causes via first-principles analysis. Pay special attention to: TOCTOU between detect and fix, signal handling, FS atomicity (rename vs write), interaction with the project's existing locks, and any path that bypasses `mutate()`."*

Repeat until two consecutive rounds come up clean except for trivial changes. Then run `ubs` (if available), the project's typecheck/lint/test suite, the project's existing build, and the doctor's own scorecard threshold gate. Fix everything.

### Termination thresholds (Phase 4/5/6/7 loop exit criteria)

The loop terminates when ALL of:

- Median per-failure-mode score uplift in the last pass is **< 25 points**.
- **No failure mode regressed** by more than 50 points (a regression > 50 is a **hard stop** — investigate before continuing).
- Phase 4 produced no new top-N detector/fixer that wasn't a near-duplicate of one already applied.
- Phase 7 fresh-eyes ran clean two times in a row (only trivial edits).
- The fixture suite from Phase 9 round-trips: corrupt → `doctor --fix` → assert healthy → `doctor undo <run-id>` → byte-identical to the corrupted state, for every failure mode.

Full per-phase playbook with exit criteria + exact prompts: **[references/methodology/PHASES.md](references/methodology/PHASES.md)** and **[references/methodology/AGENT-PROMPTS.md](references/methodology/AGENT-PROMPTS.md)**.

---

## Parallelism Model

The doctor's failure-mode partition mirrors the project's own subsystem boundaries. Phase 1 produces that partition; Phases 2 and 4 fan out across it; Phase 3 collapses to a single synthesizer.

```
┌────────────────────────────────────────────────────────────────────────┐
│  PARTITION (Phase 1, by main agent)                                    │
│  ─> recursive --help walk + git-grepped panics + bug-tracker scrape    │
│  ─> assign one archaeologist subagent per subsystem subtree            │
└────────────────┬───────────────────────────────────────────────────────┘
                 │
   ┌─────────────┼──────────────┬──────────────┬────────────────────────┐
   ▼             ▼              ▼              ▼                        ▼
┌────────┐  ┌────────────┐  ┌──────────┐  ┌──────────┐           ┌──────────────┐
│ state- │  │ config-    │  │ schema-  │  │ sockets/ │   ...     │ hook-installs│
│ files  │  │ files      │  │ migration│  │ pidfiles │           │ /plugin-dirs │
└───┬────┘  └─────┬──────┘  └────┬─────┘  └────┬─────┘           └──────┬───────┘
    │             │               │             │                       │
    └─────────────┴───────────────┴─────────────┴───────────────────────┘
                                  │
                                  ▼
                  ┌──────────────────────────┐
                  │ Phase 3 SYNTHESIS        │  single agent: taxonomy,
                  │ (taxonomy + dep graph +  │  dependency graph (which
                  │  conflicts + envelope)   │  repairs precede which),
                  └──────────────┬───────────┘  conflict matrix, safety
                                 ▼              envelope, narrative chapters
                Phase 4 IMPLEMENTATION (parallel by subsystem,
                                       all routes go through mutate())
                                 ▼
                Phase 5 SAFETY HARNESS (reversibility / idempotence /
                                       crash-recovery / concurrency /
                                       detector metamorphic)
                                 ▼
                Phase 6 SURFACE + SCORECARD (single agent)
                                 ▼
                Phase 7 FRESH-EYES SWARM (multi-model if available)
                                 ▼
                Phase 9 FIXTURE SUITE (one corrupter per failure mode)
                                 ▼
                Phase 10 FRESH AGENT cold UX run → one polish pass
```

**Coordination.** Use [MCP Agent Mail](../agent-mail/SKILL.md) file reservations whenever a Phase 4 implementer touches a file another implementer is also editing (especially the `mutate()` chokepoint, the run-artifact emitter, the `--help` output strings, and the capabilities schema). Thread id: `doctor-<pass>-<phase>-<subsystem>`.

**Orchestration tier** — pick based on tool size:

| Tier | Shape | When |
|------|-------|------|
| Solo | 1 worker, serial phases | Tiny tool, ≤ 3 subsystems, ≤ 10 failure modes |
| Pair | 2 workers, fan-out only on Phase 1/2/4 | Typical CLI, 3–6 subsystems, 10–30 failure modes |
| Squad | 4–6 workers, parallel by subsystem | Full CLI suite, 6–12 subsystems, 30–60 failure modes |
| Swarm | 8–12 workers, beads-driven + multi-model in Phase 4/7 | Multi-binary toolkit (e.g. `br` + `bv`); rewriting an entire diagnostic surface |

Triangulation is reserved for Phase 4 (implementation review of the `mutate()` chokepoint and irreversible paths) and Phase 7 (fresh-eyes), where independent reads produce the highest signal. See **[references/methodology/ORCHESTRATION.md](references/methodology/ORCHESTRATION.md)**.

---

## The Ten Scoring Dimensions

Every scored item — each detector, each fixer, each verb, each flag, each emitted artifact field — gets 0–1000 across these ten dimensions. Rubric anchors at 0/250/500/750/1000 are in **[references/rubric/SCORING-RUBRIC.md](references/rubric/SCORING-RUBRIC.md)**. The aggregate score per failure mode is the median of its detector + fixer + fixture + test scores; the aggregate per-tool score is the per-FM median weighted by frequency × blast_radius.

| # | Dimension | The question it answers |
|---|-----------|-------------------------|
| 1 | **agent_intuitiveness** | Can an agent guess the right invocation from `--help` alone? Does the first command an agent tries succeed (or get redirected with a useful hint)? |
| 2 | **agent_ergonomics** | Stable JSON schema, exit codes, stderr/stdout discipline, no TTY assumptions, no interactive prompts in `--robot` mode, every read-side path has `--json`. |
| 3 | **automation_degree** | What percentage of detected issues can be fixed without a human? Of those fixed, what percentage need follow-up? |
| 4 | **data_safety** | Does every mutation back up first? Are backups verbatim (byte-identical), per-file, and stored alongside their before/after hashes? |
| 5 | **idempotence** | Run twice → same as run once. Run mid-fix → next run completes or aborts cleanly. No torn writes. No orphaned backups. |
| 6 | **reversibility** | Every fix has a recorded inverse. `doctor undo <run-id>` restores byte-for-byte. The undo script is itself idempotent. |
| 7 | **diagnostic_specificity** | Each finding cites `file:line` / `key=…` / table.row / json-pointer / blob hash, not generic prose. Every error message names the *exact* flag that fixes it. |
| 8 | **blast_radius_containment** | Worst-case scope is bounded and disclosed in `--dry-run`. Doctor never touches anything outside paths it documented in `capabilities --json`. |
| 9 | **observability** | Structured logs, run-id, `--explain <finding-id>`, machine-parseable artifacts, stable schema_version. |
| 10 | **test_coverage_of_repair** | A fixture reproduces the broken state and an automated test asserts repair from that state to a known-good state. Fixture lives in-repo. |

**Threshold rule.** Any score >= 700 requires concrete evidence cited in the per-item record (file:line for source-defined behavior, fixture path + test name for runtime-verified behavior). Scoring without evidence is rejected by `scripts/scorecard.py validate <workspace>`.

**Priority** is computed per failure mode as: `priority = frequency × score_gap × blast_radius` where `frequency` is "how often this failure mode is seen" (estimated from CASS mining + bug tracker counts + git-log mentions), `score_gap = 1000 − weighted_avg(dimension_scores)`, and `blast_radius` is "how badly does it stay-bad if unfixed" (rubric in [references/rubric/PRIORITY-FORMULA.md](references/rubric/PRIORITY-FORMULA.md)).

---

## The Polish Bar (Non-Negotiable)

Every shipped doctor must satisfy these. If any item fails, that's a Phase 4/5/6/7 rework target — not a "ship it and watch."

| Dimension | Test |
|-----------|------|
| **Detect-then-fix** | Detectors are pure functions (no side effects, no `mutate()` calls). They return a finding list; the runtime decides whether `--fix` was passed. |
| **Single-chokepoint mutation** | Every disk write goes through `mutate(path, op)`. `mutate()` writes the backup, computes before/after hashes, appends `actions.jsonl`, holds the file lock, and is the **only** code allowed to touch the disk under `doctor --fix`. Verified by a code search test. |
| **Backups before any mutation** | `mutate()` first copies the target file verbatim into `.doctor/runs/<run-id>/backups/<path-relative-to-repo-root>` (preserving directory layout, mtime, permissions). For DB rows, the backup is a `pg_dump`/`sqlite3 .dump` of the affected rows. For config keys, the backup is the full original file. |
| **Reversible** | `doctor undo <run-id>` reads `actions.jsonl` in reverse, restores from `backups/`, and verifies post-restore hash matches the recorded `before_hash`. Fails closed if any backup is missing. |
| **Idempotent** | `doctor --fix` then `doctor --fix` → second run reports "no actions taken" with exit 0. Verified per-failure-mode by Phase 5 test. |
| **Crash-recoverable** | `SIGKILL doctor` mid-fix → next run either completes the partial fix or aborts cleanly. No torn writes; no orphaned `.tmp.<pid>` files; no stale lock. Verified by Phase 5 fault-injection test. |
| **Concurrency-safe** | Two `doctor --fix` invocations on the same workspace → one wins via the project's existing lock primitive (or one we add); the other refuses with exit 5 (`concurrency_lost`). |
| **Read-only by default** | `doctor` (no flags) **never mutates**. `--fix` is opt-in. `--dry-run --fix` prints the plan without executing. |
| **Stable JSON schema** | `--json` and `--robot` outputs include `schema_version` and a stable field set. Schema export available via `doctor capabilities --json`. |
| **Exit-code contract** | `0` healthy, `1` findings present (no `--fix`), `2` fix attempted and partial, `3` fix failed and rolled back, `4` refused unsafe, `5` concurrency lost (lock held), `6` online required, `64` usage error, `66` no input, `73` cannot create output, `74` I/O error. Documented in `capabilities --json` (canonical schema in [CLI-SURFACE.md § exit_codes](references/methodology/CLI-SURFACE.md)). |
| **Stdout = data, stderr = progress** | All ANSI / spinners / progress bars go to stderr; stdout is data. Auto-disable on non-TTY, `NO_COLOR=1`, `--robot`, or `--json`. |
| **Capabilities + robot-docs** | `<tool> doctor capabilities --json` returns version, contract version, detector list, fixer list, exit codes, env vars, run-artifact schema. `<tool> doctor robot-docs` prints a paste-ready agent handbook in-tool. |
| **Mega-command** | `<tool> doctor --robot-triage` returns `{summary, findings, actions_planned, recommended_command, capabilities_url}` in a single call. |
| **Each fixer has a fixture** | `tests/doctor_fixtures/<failure-mode>/` reproduces the broken state. A test asserts: corrupt → `doctor --fix` → `doctor` (no flags) returns exit 0 → `doctor undo <run-id>` → byte-identical to corrupted state. |
| **Offline by default** | All detectors and fixers run with no network. Network probes (DNS, TLS, vendor APIs) are opt-in via `--online`. |
| **No destructive shell** | Doctor never invokes `rm -rf`, `git reset --hard`, `git clean -fd`, or any AGENTS.md-forbidden command. Equivalent semantics are implemented in code, scoped to documented paths, and recorded in `actions.jsonl`. |

If a surface can't satisfy these, it fails the bar. Full per-dimension verification queries: **[references/methodology/POLISH-BAR.md](references/methodology/POLISH-BAR.md)**.

---

## Cognitive Operators (Doctor-Mode Thinking Moves)

Composable moves. Apply to any failure mode, any error message, any flag-design decision. See **[references/methodology/OPERATORS.md](references/methodology/OPERATORS.md)** for the full card library with triggers, failure modes, and prompt modules.

| Glyph | Name | Question | Fix-pointer |
|-------|------|----------|-------------|
| `🩺` | **Detect-Then-Fix** | "Is the detector pure, or does it mutate?" | Polish Bar §detect-then-fix |
| `🚪` | **Single-Chokepoint** | "Does every mutation flow through `mutate()`?" | Polish Bar §single-chokepoint |
| `💾` | **Backup-Before-Mutate** | "Is the verbatim backup written and verified before the mutation begins?" | Polish Bar §backups-before-mutation |
| `↩` | **Inverse-Pair** | "Does this fix have a recorded inverse that's been tested?" | Polish Bar §reversible |
| `🔁` | **Idempotent-Twice** | "If I run this fix twice, does the second run report `no_actions_taken`?" | Polish Bar §idempotent |
| `⚡` | **Crash-Mid-Fix** | "If the process dies mid-fix, can the next run finish or cleanly abort?" | Polish Bar §crash-recoverable |
| `🔒` | **Lock-Or-Refuse** | "If two doctors run at once, does one refuse with exit 5 (concurrency_lost)?" | Polish Bar §concurrency-safe |
| `🧪` | **Fixture-Pinned** | "Is there a fixture that reproduces the broken state, and a test that asserts repair?" | Polish Bar §each-fixer-has-fixture |
| `🛡` | **Refuse-On-Unsafe** | "If the state is genuinely unsafe (out-of-scope write, schema unknown, network required but offline), does doctor exit 4 (`refused_unsafe`) with a precise reason and a safe alternative? (Lock-held is exit 5 — see Lock-Or-Refuse.)" | Polish Bar §exit-code-contract |
| `🪧` | **Stdout-Data-Stderr-Diag** | "Does `<tool> doctor --json | jq …` work without grep-filtering log lines?" | Polish Bar §stdout-data-stderr-progress |
| `📜` | **Self-Describing** | "Does `<tool> doctor capabilities --json` exist and pin the contract?" | Polish Bar §capabilities-and-robot-docs |
| `📖` | **In-Tool-Docs** | "Does `<tool> doctor robot-docs` make external lookup unnecessary?" | Polish Bar §capabilities-and-robot-docs |
| `🚦` | **Exit-Code-Dictionary** | "Are non-zero exits a documented dictionary, not ad-hoc?" | Polish Bar §exit-code-contract |
| `🩹` | **Error-Names-The-Fix** | "Does this finding name the exact flag/command that resolves it?" | Polish Bar §diagnostic-specificity |
| `🆔` | **Stable-Run-Id** | "Does every run get a stable, content-addressed handle (`<ISO8601>__<run-id>`)?" | Polish Bar §observability |
| `📦` | **Verbatim-Backup** | "Is the backup the file as-was, byte-identical, with permissions and mtime preserved?" | Polish Bar §backups-before-mutation |
| `🔢` | **Hash-Witnessed** | "Are before/after hashes recorded in `actions.jsonl` for every mutation?" | Polish Bar §observability |
| `🌐` | **Offline-By-Default** | "Does this detector / fixer require network? If yes, is it gated on `--online`?" | Polish Bar §offline-by-default |
| `🪞` | **Mega-Command** | "Can three round-trips collapse into one `--robot-triage` call?" | Polish Bar §mega-command |
| `🗺` | **Bounded-Blast-Radius** | "Does `--dry-run` print the worst-case write set, and is that set a strict subset of the documented capability paths?" | Polish Bar §blast-radius |

The operators deliberately overlap — a single fixer typically deserves four or five. Composition pipelines per failing dimension: [references/methodology/OPERATORS.md § Composition](references/methodology/OPERATORS.md).

---

## Workspace + Run-Artifact Layout (the IO Contract)

There are **two** filesystem layouts to keep straight:

### 1. The skill's measurement workspace (sibling of the target repo)

```
<repo>__doctor_workspace/
├── manifest.json                              ← entry point: tool, target_sha, pass, paths
├── phase0_scope_decision.md                   ← user's "must not touch" + branch name
├── phase0_skill_inventory.json                ← which helper skills are installed
├── phase0_cli.json                            ← language, build system, binaries detected
├── cass_findings.jsonl                        ← Phase 0: CASS mining results (one finding per line)
├── cass_findings.md                           ← Phase 0: human-readable companion to cass_findings.jsonl (one section per kind)
├── triangulation_<phase>_<round>.md           ← Phase 4 / Phase 7 (multi-model tier only): per-question multi-model verdict from triangulator
├── baseline/                                  ← snapshot of pre-existing doctor (upgrade mode)
│   ├── help_output.txt
│   ├── json_output_healthy.json
│   ├── json_output_corrupted.json
│   ├── exit_code_dictionary.txt
│   ├── version.txt                            ← `<tool> --version` capture
│   ├── hash_before_audit.json                 ← SHA-256 of every target file (proves baseline-snapshotter didn't mutate)
│   └── auto_mutation_violations.md            ← (only if Phase 0 detected an existing doctor that auto-mutated without --fix)
├── analysis/
│   ├── failure_modes/<subsystem>.md          ← Phase 1: enumerate every realistic failure mode
│   ├── inventory_summary.md                  ← Phase 1: one-line summary per FM (table form)
│   ├── repair_specs/<id>.md                  ← Phase 2: detector + fixer + fixture spec per FM
│   ├── spec_review.md                        ← Phase 2.5 (Pair+ tier only): per-spec review classifications
│   ├── taxonomy.md                           ← Phase 3: canonical naming, severity buckets
│   ├── dependency_graph.md                   ← Phase 3: which repairs precede which (Mermaid + prose)
│   ├── dependency_graph.json                 ← Phase 3: machine-readable DAG (validated by `scripts/validate-dag.py`)
│   ├── conflict_matrix.md                    ← Phase 3: repairs that must NEVER co-run
│   └── safety_envelope.md                    ← Phase 3: invariants doctor must never violate
├── audit_log.md                               ← Phase 4 / 7: mutate-auditor's findings (`scripts/validate-doctor.sh` violations + dispositions)
├── safety_harness.jsonl                       ← Phase 5: per-fixer reversibility/idempotence/crash/concurrency results (one row per (fm, test))
├── safety_harness_report.md                   ← Phase 5: human-readable companion summarizing pass/fail per FM
├── fresh_eyes_round_<N>.md                    ← Phase 7: per-round findings from each fresh-eyes review (round 1, 2, 3...)
├── fresh_eyes_summary.md                      ← Phase 7: aggregate of all rounds; cited by HANDOFF.md
├── failure_mode_scores.jsonl                  ← Phase 6: per-FM × per-dimension scores (+ frequency, blast_radius weights)
├── scorecard.md                               ← Phase 6: human-readable summary
├── scorecard_pass_<N>.md                      ← Phase 6: per-pass historical scorecards
├── heatmap.svg                                ← Phase 6: failure-modes × dimensions, hot=low
├── uplift_diff.md                             ← Phase 6: pass-N vs pass-N-1 deltas
├── regression_alerts.md                       ← Phase 6: FMs that dropped > 50 pts
├── agent_ergo_grade.md                        ← Phase 6: doctor surface graded against the agent-ergonomics rubric
├── agent_ergo_recommendations.jsonl           ← Phase 6: ranked recs from agent-ergo-grader
├── recommendations.jsonl                      ← Phase 4 input: ranked recs from Phase 1+2
├── applied_changes.jsonl                      ← Phase 4 output: one line per applied repair spec, before/after evidence
├── playbook.md                                ← Phase 3 narrative chapters (what doctor will and will not do, what you should back up first, how to recover if doctor itself goes wrong)
├── canonical_tasks.md                         ← Phase 10 input: ~10 representative tasks an agent should be able to do via `<tool> doctor` alone (authored from `assets/canonical-tasks-template.md` by the orchestrator before dispatching `subagents/cold-agent-prober.md`)
├── agent_simulations/
│   ├── pre_pass_<N>/                          ← baseline transcripts for `add` mode
│   └── post_pass_<N>/                         ← Phase 10 fresh-agent transcripts
│       ├── <task>.transcript.jsonl            ← Phase 10: per-task command-and-output trace from cold-agent-prober
│       └── notes.md                           ← Phase 10: cold-prober's "confusing surfaces / wished-this-existed" summary
├── ideas_pass_<N>.md                          ← Phase 10: idea-generator's surfaced improvements (filed as priority-3 beads)
├── worktree/                                  ← (optional) git worktree on doctor-mode-pass-<N>
└── HANDOFF.md                                 ← Phase 10: queued for next pass
```

### 2. The per-run artifact directory (lives INSIDE the target repo, gitignored)

Every invocation of `<tool> doctor` (no flags or with `--fix`) writes a fresh run directory:

```
<target>/.doctor/
├── runs/
│   ├── 2026-05-06T14-23-07Z__a3f9b2/
│   │   ├── report.json                        ← findings, exit code, schema_version
│   │   ├── report.md                          ← human-readable narrative
│   │   ├── scorecard.json                     ← per-detector × per-dimension this run
│   │   ├── actions.jsonl                      ← one line per mutate() call (before/after hashes)
│   │   ├── backups/                           ← verbatim per-file backups, dirs preserved
│   │   │   ├── .beads/beads.db
│   │   │   ├── .beads/issues.jsonl
│   │   │   └── …
│   │   ├── stderr.log                         ← captured stderr (rotated per run)
│   │   ├── stdout.json                        ← copy of report.json (or fix output) for replay
│   │   └── undo.sh                            ← idempotent rollback (calls `<tool> doctor undo <run-id>`)
│   ├── 2026-05-06T15-44-19Z__b771ac/
│   │   └── …
│   └── 2026-05-06T19-02-31Z__c88de4/
│       └── …
├── latest -> runs/2026-05-06T19-02-31Z__c88de4/   ← symlink; updated atomically
└── scorecard_history.jsonl                    ← one line per run; trend analysis input
```

**`.doctor/` belongs in `.gitignore` of the target repo** (the doctor adds it on first run if missing). Never check run artifacts into the repo — they describe a single machine's recovery, not the project's state.

Full per-artifact schema, including JSONL line shapes for `failure_mode_scores.jsonl`, `actions.jsonl`, `report.json`, `scorecard.json`, `recommendations.jsonl`, and the manifest: **[references/methodology/IO-CONTRACTS.md](references/methodology/IO-CONTRACTS.md)** + **[references/methodology/OUTPUT-SCHEMA.md](references/methodology/OUTPUT-SCHEMA.md)**.

---

## Doctor Surface (CLI Spec)

The doctor we build (or upgrade) exposes this surface, in this exact spelling. Every implementation in the project's native language must wire these flags. Verbatim help text and JSON schemas in **[references/methodology/CLI-SURFACE.md](references/methodology/CLI-SURFACE.md)**.

```text
<tool> doctor                              # read-only diagnose; exit 0 healthy, 1 findings, 4 unsafe-refused
<tool> doctor --fix                        # repair with backups; exit 0/2/3/4
<tool> doctor --dry-run --fix              # print the plan, do NOT execute; exit 0
<tool> doctor --explain <finding-id>       # expand one finding with full evidence (cited file:line, query, hash)
<tool> doctor undo <run-id>                # restore from .doctor/runs/<run-id>/backups/
<tool> doctor undo latest                  # convenience for the most recent run
<tool> doctor capabilities --json          # version, contract, detectors, fixers, exit codes, env vars, schema_version
<tool> doctor health                       # cheap liveness summary (one line + exit code); for CI scheduling
<tool> doctor robot-docs                   # paste-ready agent handbook printed to stdout
<tool> doctor ls                           # list runs in .doctor/runs/ with {run_id, started_at, exit_code, action_count}
<tool> doctor diff [<ref>]                 # show what --fix would change; read-only; optional ref compares prior run
<tool> doctor gc --before <date> --yes     # prune old runs (destructive — requires both flags; AGENTS.md-safe inside the doctor)
<tool> doctor --robot-triage               # mega-command: {summary, findings, actions_planned, recommended_command, capabilities_url}
<tool> doctor --quick                      # pre-commit / hook fast path; cheap detectors only
<tool> doctor --json | --robot             # stable schema, schema_version, stdout-data-only
<tool> doctor --online                     # opt-in: enable network probes (DNS, TLS, vendor APIs)
<tool> doctor --only=<subsystem,...>       # scope to a subset of detectors/fixers
<tool> doctor --since=<run-id>             # diff against an earlier run's findings
```

**Every flag respects the Polish Bar.** No flag silently mutates. No flag implies `--fix`. No flag turns off backups. No flag bypasses `mutate()`.

---

## Safety Envelope (Invariants the Doctor Must Never Violate)

Phase 3 produces `analysis/safety_envelope.md` for the specific project. These are the **universal** invariants every doctor must obey, regardless of project. Verified by `scripts/validate-doctor.sh`.

1. **No file deletion during diagnose/fix/undo.** Per AGENTS.md RULE NUMBER 1. `doctor undo` restores from backup rather than erasing. (Restoring `backups/foo` over `foo` is a write, not a delete.) Retention cleanup is a separate `doctor gc --before <date> --yes` command, never part of `--fix`, and requires explicit user intent for the cutoff.
2. **No destructive shell commands.** Never `rm -rf`, `git reset --hard`, `git clean -fd`, `DROP TABLE`, `kubectl delete`, or any equivalent. If equivalent semantics are needed, implement them in code, scoped to documented paths, and recorded.
3. **Writes are scoped.** Doctor only writes inside paths the project's `capabilities --json` documents (typically: `.<tool>/`, `~/.config/<tool>/`, `<workspace>/.doctor/`, and any `data_paths` it owns). Writes outside this scope require an explicit allow-list and refuse with exit 4 by default.
4. **Writes are atomic.** Every disk write uses `write-tmp-then-rename` (or filesystem equivalent). No in-place truncation. No half-written files visible to readers.
5. **Backups are verbatim.** No transcoding, no normalization, no "I'll just clean up the trailing newline." Backup is the file as-was; `cmp` between backup and original at the moment of backup must succeed.
6. **Hashes witness everything.** Every `mutate()` call records `{path, before_hash, after_hash, op, timestamp}` in `actions.jsonl`. SHA-256 minimum.
7. **Locks are explicit.** Doctor takes the project's existing lock (or a doctor-specific one) before mutating. If the lock is held, refuse with exit 5 (`concurrency_lost`) and name the holder if discoverable.
8. **Network only on opt-in.** Default is offline. `--online` is required for any network call. Network failures never wedge a fixer — they downgrade it to `findings_only_offline` and proceed.
9. **No mutation in detect mode.** Calling `<tool> doctor` with no `--fix` flag never writes anywhere except (a) append-only `.doctor/runs/<run-id>/report.{json,md}` artifacts and (b) an atomic update of the symlink at `.doctor/latest`. These writes don't touch the project's state.
10. **No mutation if any precondition fails.** Each fixer has explicit preconditions (e.g., "lock available", "schema_version matches", "backup directory writable"). If any fails, refuse with exit 4 (`refused_unsafe`) and a finding pointing at the unmet precondition — except lock-related preconditions, which use exit 5 (`concurrency_lost`) so an agent knows to retry-after-wait rather than escalate.

Full project-specific envelope template: **[references/methodology/SAFETY-ENVELOPE-TEMPLATE.md](references/methodology/SAFETY-ENVELOPE-TEMPLATE.md)**.

---

## Cookbook — Fifteen Doctor Patterns

The 10-phase loop is universal but the *shape* of the doctor differs by project archetype. The cookbook in **[references/methodology/COOKBOOK.md](references/methodology/COOKBOOK.md)** names fifteen patterns; most real projects match 1–3 simultaneously.

| # | Pattern | Examples | Per-pattern recipe |
|---|---------|----------|---------------------|
| 1 | Single-binary state-owning CLI | `xf`, `cm` | (baseline) |
| 2 | Multi-binary toolkit (single shared state) | `br + bv`, `cargo + cargo-deny + cargo-audit` | [recipes/multi-binary-toolkit.md](references/recipes/multi-binary-toolkit.md) |
| 3 | Single-binary stateless / config-only | `dcg`, `de-slopify` | (Pattern 1 with no state_files subsystem) |
| 4 | Daemon / long-running process | `wrangler dev`, `ntm`, `mcp-agent-mail`, `wezterm mux` | [recipes/daemon-cli.md](references/recipes/daemon-cli.md) |
| 5 | Installer / provisioner | `acfs`, `dsr`, `installer-workmanship` outputs | [recipes/installer.md](references/recipes/installer.md) |
| 6 | TUI-first with non-interactive subset | `bv`, `frankentui` apps | (Pattern 1 + never-launch-TUI rule) |
| 7 | AI-coding-agent CLI | `caam`, `ntm`, `cass`, `cm` | (Pattern 1 + agent-session subsystem) |
| 8 | Doctor for a tool you don't own | proposed `cargo doctor`, `kubectl doctor` | (wrapper CLI; no upstream changes) |
| 9 | Distributed CLI (vendor-API client) | `wrangler`, `vercel`, `gh`, `gcloud` | [recipes/distributed-cli.md](references/recipes/distributed-cli.md) |
| 10 | Absorb-playbook | `fixing-beads-problems → br doctor` | [methodology/ABSORB-PLAYBOOK.md](references/methodology/ABSORB-PLAYBOOK.md) |
| 11 | Doctor for an installer-bootstrap chain | `dsr`, `ggshield install` | [recipes/installer.md](references/recipes/installer.md) §11 |
| 12 | Doctor for a skill itself (meta-doctor) | this skill's own validator (proposed) | [methodology/META-DOCTOR.md](references/methodology/META-DOCTOR.md) |
| 13 | Read-only / forensic doctor (post-mortem mode) | compliance-bound projects; `--fix` refused | [methodology/COOKBOOK.md § Pattern 13](references/methodology/COOKBOOK.md) |
| 14 | Build-system doctor | `cargo doctor`, `npm doctor`, `gradle doctor` | [methodology/COOKBOOK.md § Pattern 14](references/methodology/COOKBOOK.md) |
| 15 | Compliance / audit doctor | SOC 2 / HIPAA / PCI / GDPR doctors | [methodology/COOKBOOK.md § Pattern 15](references/methodology/COOKBOOK.md) |

Phase 1's archaeologist classifies the target against these patterns first; per-pattern adjustments stack additively.

---

## Versioning

The doctor publishes three orthogonal version numbers:

| Version | Purpose | Bump rules |
|---------|---------|------------|
| `tool_version` | the project's own version (not the doctor's concern) | per project's existing semver |
| `doctor_version` | implementation version | minor for new fixers; major for incompatible refactors |
| `doctor_contract_version` | agent-facing contract: schemas, exit codes, flag set, `--robot` envelope | major-bump only on breaking changes; backward-compat additions are minor |

Every JSON artifact carries `schema_version` (usually = `doctor_contract_version` but can bump independently). The agent-facing surface is stable across `doctor_version` minor bumps; agents only care about `doctor_contract_version`.

Full versioning policy, breaking-vs-additive matrix, run-artifact compatibility across versions, and `--contract-version` pinning: **[references/methodology/VERSIONING.md](references/methodology/VERSIONING.md)**.

---

## Anti-Patterns (Never Do)

| ✗ | Why | Fix |
|---|-----|-----|
| Apply a fix that bypasses `mutate()` "for performance" | Breaks the backup + hash + actions.jsonl invariants | Every disk write goes through `mutate()`. Add a code-search test that fails CI if any other path writes. |
| Score a detector >= 700 without evidence | Rubric is meaningless if anchored to vibes | `scripts/scorecard.py validate <workspace>` rejects unsourced high scores |
| Write a fixer without a fixture | Pass-N+1 can't tell "fixed" from "regressed" | Phase 9 is mandatory; run the fixture suite plus `scripts/verify-undo.sh`, `scripts/verify-idempotence.sh`, `scripts/verify-crash-recovery.sh`, `scripts/verify-concurrency.sh`, and `scripts/verify-metamorphic.sh` for the fixer |
| Delete a file inside `doctor --fix` "to clean up" | Violates AGENTS.md RULE NUMBER 1 | Move to `.doctor/runs/<run-id>/quarantine/` via `Op::Rename`; real retention cleanup is the separately gated `doctor gc --before <date> --yes` command after explicit consent. |
| `rm -rf` inside any fixer to start clean | Destructive shell in doctor is forbidden | Implement equivalent in code: enumerate, back up each, then write the new state via `mutate()`. |
| Apply a fix even though the lock is held | Concurrency-corrupts user state | Refuse with exit 5 (`concurrency_lost`) and a finding identifying the holder if possible. |
| Print color/progress to stdout | Breaks `--json | jq` | All ANSI / spinners go to stderr. Auto-disable when stdout is non-TTY. |
| `panic!` / `unwrap()` on user-supplied paths | Crashes doctor in the worst possible moment | Convert to a `safety_block` finding with exit 4 and a precise reason. |
| Add a backwards-compat shim for an existing flag | Project is pre-1.0; AGENTS.md forbids shims | Just change the code. Update the related skill (e.g., `fixing-beads-problems`) and demote its manual playbook to "fallback if `<tool> doctor --fix` doesn't help." |
| Mix data and progress on stdout | Breaks composability | Stdout = data, stderr = progress. No exceptions. |
| Network probes in detect mode by default | Doctor must work in a sandbox | Network is opt-in via `--online`. |
| Score the same failure mode under two different IDs | Cumulative scoring breaks across passes | `failure_mode_id` is content-derived (subsystem + symptom + root_cause); use `scripts/compute-fm-id.py` |
| Land changes on `main` of the target | Per AGENTS.md and basic git hygiene | Always feature branch `doctor-mode-pass-<N>`; merge only with explicit user approval |
| Modify the workspace as part of Phase 4 (in-tree code changes) | Workspace is the *measurement*; should be untouched by code changes | Code changes go on the worktree's feature branch; workspace tracks measurements only |
| Treat "no `capabilities` endpoint" as a feature gap | The methodology IS to find these gaps | If `capabilities` is missing, that's a P0 finding scored under diagnostic_specificity + observability |
| Ship a fixer that prints "fixed" but didn't write actions.jsonl | Future undo cannot find the action | `mutate()` is the only writer; if it didn't run, the fix didn't happen — emit a different finding instead. |
| Use random / wall-clock IDs for run-id | Breaks determinism + reproducibility | Run-id is derived from `sha256(target_sha + iso8601_utc_seconds)[..6]`; deterministic up to the second |

Full anti-pattern catalog: **[references/methodology/ANTI-PATTERNS.md](references/methodology/ANTI-PATTERNS.md)**.

---

## Failure Modes (and Recovery)

| Symptom | Root cause | Recovery |
|---------|------------|----------|
| Phase 1 inventory has < 5 failure modes for a non-trivial CLI | Subsystem partition too coarse; bug-tracker scrape skipped | Re-run `subagents/archaeologist.md` with broader subsystem list; add `git log --grep` mining and `br ready --json`/`gh issue list --json` mining |
| Phase 4 implementer wrote a fixer that bypasses `mutate()` | Implementer didn't read [references/methodology/MUTATE-CHOKEPOINT.md](references/methodology/MUTATE-CHOKEPOINT.md) | Hard reject. Add to phase 7 fresh-eyes prompt 3. Add a code-search test gate. |
| Phase 5 reversibility test fails on one fixer | Fixer is not byte-identical reversible (e.g., reformats JSON it touches) | The fixer must NOT touch unrelated bytes. Restrict the diff to the minimal byte range. |
| Phase 5 idempotence test fails | Fixer's detector is dirty (mutates a side-channel that the next detect doesn't see) | Detector must be pure. Move the side-channel write into `mutate()`. |
| Phase 5 crash-recovery test leaves orphan `.tmp.<pid>` | Atomic rename not implemented | Use `tempfile::NamedTempFile` (Rust), `os.replace` (Python), `os.Rename` (Go), `fs.renameSync` (Node) — never separate `write` + `rename` for same data. |
| Phase 6 `capabilities --json` exists but lies | Schema drifts from reality | `scripts/verify-capabilities.sh` round-trips capabilities → invokes each declared detector → asserts they exist. |
| Phase 6 score regression > 50 on a single fixer between passes | Side-effect of unrelated change in target repo | **Hard stop**. Diagnose root cause. Cited file:line in `regression_alerts.md`. |
| Phase 7 fresh-eyes never goes quiet | Loop is touching cosmetic surfaces | Tighten "trivial change" definition: only typo/whitespace counts. Rephrasing IS a change. |
| Phase 9 fixture suite has a fixture with no test | Fixture-author wrote the corrupter but didn't pair the assertion | Phase 9 isn't done until every fixture has a test asserting the round-trip. |
| Phase 10 cold agent gets stuck on canonical task | Real intent-inference gap | File as P0 bead for next pass; do not mark Phase 10 complete |
| `<tool> doctor --json` mixes log lines and JSON | stdout/stderr split violation | Score 0 on agent_ergonomics; flag as Polish Bar fail; rework the logger |
| Doctor needs network but project doesn't expose `--online` | Default-online violation | Add `--online`. Default `false`. Network detectors downgrade to `findings_only_offline` when unset. |

Full failure-mode catalog with recovery scripts: **[references/methodology/TROUBLESHOOTING.md](references/methodology/TROUBLESHOOTING.md)**.

---

## Pre-Flight & End Checklist

- [ ] Target CLI path confirmed; sibling workspace named & scaffolded; worktree (if chosen) created on `doctor-mode-pass-<N>` from the target's `main`/default branch (NOT a fresh `git init`)
- [ ] Mode confirmed (`add` | `upgrade` | `audit-only` | `re-score-only` | `single-failure-mode-rescore` | `absorb-playbook`)
- [ ] Pass number determined (auto-incremented from manifest if resuming)
- [ ] Helper skills inventoried; missing ones offered via `jsm install` (non-blocking)
- [ ] CLI language + binaries discovered and recorded in `phase0_cli.json`
- [ ] (Upgrade mode only) Existing doctor's behavior snapshotted into `baseline/`
- [ ] Phase 1 produced `analysis/failure_modes/<subsystem>.md` for every detected subsystem; spot-check against runtime panics + bug tracker
- [ ] Phase 2 produced `analysis/repair_specs/<id>.md` for every failure mode (detector pseudocode, fixer pseudocode, preconditions, invariants, backup spec, inverse, idempotence proof sketch, fixture spec)
- [ ] Phase 3 produced `taxonomy.md`, `dependency_graph.md` + `dependency_graph.json` (DAG validated by `scripts/validate-dag.py`), `conflict_matrix.md`, `safety_envelope.md`, and the user-facing narrative chapters in `playbook.md`
- [ ] Phase 4 — `mutate()` chokepoint exists, every detector is pure, every fixer routes through `mutate()`, `--dry-run`/`--fix`/`--explain` wired, JSON/robot output stable, exit-code dictionary in `capabilities`
- [ ] Phase 5 — reversibility test green for every fixer; idempotence test green; crash-recovery test green; concurrency test green
- [ ] Phase 6 — `<tool> doctor capabilities --json`, `health`, `robot-docs`, `--robot-triage` all exist; scorecard generator produces `scorecard.json` per run + `scorecard_history.jsonl` aggregate
- [ ] Phase 7 fresh-eyes ran ≥ 2 times clean; `ubs` clean (if available); typecheck/lint/tests green; project's existing tests still green
- [ ] Phase 8 — pre-commit / CI wired (doctor runs on schedule, fails CI if score drops > 50 from baseline); related-skill demoted (e.g., `fixing-beads-problems` updated to recommend `<tool> doctor --fix` first)
- [ ] Phase 9 — `tests/doctor_fixtures/` has one entry per failure mode; round-trip test passes for every fixture
- [ ] Phase 10 — `agent_simulations/post_pass_<N>/` populated with cold-agent transcripts; one polish pass run; HANDOFF.md written; beads filed for queued work
- [ ] `<workspace>/manifest.json` updated with new `pass`, `target_sha`, summary stats, artifact list

---

## Reference Index

### Foundational (operationalizing-expertise artifacts)
| Need | File |
|------|------|
| The skill's universal axioms (the lens) | [methodology/KERNEL.md](references/methodology/KERNEL.md) |
| Source corpus (named, citable layers) | [methodology/CORPUS.md](references/methodology/CORPUS.md) |
| Stable-ID quotes from the corpus | [methodology/QUOTE-BANK.md](references/methodology/QUOTE-BANK.md) |
| Fifteen doctor patterns by project shape | [methodology/COOKBOOK.md](references/methodology/COOKBOOK.md) |
| End-to-end worked example (br doctor pass-1) | [methodology/WORKED-EXAMPLE.md](references/methodology/WORKED-EXAMPLE.md) |
| Vocabulary | [methodology/GLOSSARY.md](references/methodology/GLOSSARY.md) |
| Common questions | [methodology/FAQ.md](references/methodology/FAQ.md) |
| Skill-card / elevator pitch | [assets/skill-card.md](assets/skill-card.md) |

### Methodology (the canonical loop)
| Need | File |
|------|------|
| Mode definitions + exit criteria | [methodology/OPERATING-MODES.md](references/methodology/OPERATING-MODES.md) |
| Per-phase playbook with exit criteria | [methodology/PHASES.md](references/methodology/PHASES.md) |
| **Prompts (orchestrator → archaeologist/synthesizer/etc subagent)** — verbatim, calibrated | [methodology/AGENT-PROMPTS.md](references/methodology/AGENT-PROMPTS.md) |
| **Prompts (after intake → kicks off Phase 0)** — by mode (`add`/`upgrade`/`audit-only`/...) | [methodology/KICKOFF-PROMPTS.md](references/methodology/KICKOFF-PROMPTS.md) |
| Operator cards + composition cheat-sheet | [methodology/OPERATORS.md](references/methodology/OPERATORS.md) |
| Polish Bar verification queries | [methodology/POLISH-BAR.md](references/methodology/POLISH-BAR.md) |
| Multi-agent orchestration tiers | [methodology/ORCHESTRATION.md](references/methodology/ORCHESTRATION.md) |
| Inline fallbacks for missing helper skills | [methodology/SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md) |
| IO contracts for every JSONL artifact | [methodology/IO-CONTRACTS.md](references/methodology/IO-CONTRACTS.md) |
| Run-artifact + capabilities JSON schema | [methodology/OUTPUT-SCHEMA.md](references/methodology/OUTPUT-SCHEMA.md) |
| `mutate()` chokepoint design | [methodology/MUTATE-CHOKEPOINT.md](references/methodology/MUTATE-CHOKEPOINT.md) |
| CLI surface spec (verbatim help text + JSON shapes) | [methodology/CLI-SURFACE.md](references/methodology/CLI-SURFACE.md) |
| Universal safety envelope template | [methodology/SAFETY-ENVELOPE-TEMPLATE.md](references/methodology/SAFETY-ENVELOPE-TEMPLATE.md) |
| Anti-pattern catalog | [methodology/ANTI-PATTERNS.md](references/methodology/ANTI-PATTERNS.md) |
| Failure-mode + recovery catalog | [methodology/TROUBLESHOOTING.md](references/methodology/TROUBLESHOOTING.md) |
| Multi-model triangulation harness | [methodology/TRIANGULATION.md](references/methodology/TRIANGULATION.md) |
| Absorbing manual repair skills (e.g., `fixing-beads-problems`) | [methodology/ABSORB-PLAYBOOK.md](references/methodology/ABSORB-PLAYBOOK.md) |

### Cross-cutting concerns
| Need | File |
|------|------|
| `/testing-*` skills wired to Phase 5 | [methodology/TESTING-INTEGRATION.md](references/methodology/TESTING-INTEGRATION.md) |
| Credential redaction; symlink escape; backup safety | [methodology/SECURITY.md](references/methodology/SECURITY.md) |
| Detector budgets and hot-path discipline | [methodology/PERFORMANCE.md](references/methodology/PERFORMANCE.md) |
| Schema/contract/run-artifact versioning policy | [methodology/VERSIONING.md](references/methodology/VERSIONING.md) |
| Doctor for the skill itself (Pattern 12) | [methodology/META-DOCTOR.md](references/methodology/META-DOCTOR.md) |
| Agent Mail file reservations + threading | [methodology/AGENT-MAIL-INTEGRATION.md](references/methodology/AGENT-MAIL-INTEGRATION.md) |
| Beads-driven Phase 4 task assignment | [methodology/BEADS-INTEGRATION.md](references/methodology/BEADS-INTEGRATION.md) |
| Formal doctor lifecycle FSM (states + invariants per state) | [methodology/STATE-MACHINE.md](references/methodology/STATE-MACHINE.md) |
| Specific Phase-7 attack scenarios beyond calibrated prompts | [methodology/ADVERSARIAL-REVIEW.md](references/methodology/ADVERSARIAL-REVIEW.md) |
| Stage 0 → 10 maturity ladder (Stage 0 = no doctor; Stage 10 = world-class) | [methodology/GROWTH-LADDER.md](references/methodology/GROWTH-LADDER.md) |
| Day-2 observability beyond the scorecard | [methodology/METRICS.md](references/methodology/METRICS.md) |
| Narrative postmortems doctor saved (or could have) | [methodology/CASE-STUDIES.md](references/methodology/CASE-STUDIES.md) |
| Daily/weekly/monthly/quarterly ops cadence | [methodology/OPS-RUNBOOK.md](references/methodology/OPS-RUNBOOK.md) |
| Multi-agent runtime etiquette beyond Agent Mail | [methodology/ETIQUETTE.md](references/methodology/ETIQUETTE.md) |
| What the doctor looks like from the agent's side | [methodology/AGENT-PERSPECTIVE.md](references/methodology/AGENT-PERSPECTIVE.md) |
| Worked example for distributed CLI (wrangler-style) | [methodology/WORKED-EXAMPLE-WRANGLER.md](references/methodology/WORKED-EXAMPLE-WRANGLER.md) |
| Worked example for installer pattern (acfs-style) | [methodology/WORKED-EXAMPLE-INSTALLER.md](references/methodology/WORKED-EXAMPLE-INSTALLER.md) |

### Deep methodology + maintainer references
| Need | File |
|------|------|
| Specific cass query recipes per situation (14 recipes + per-pattern phrases) | [methodology/CASS-PLAYBOOK.md](references/methodology/CASS-PLAYBOOK.md) |
| The WHY behind each axiom (failure that motivated, alternative considered) | [methodology/FIRST-PRINCIPLES.md](references/methodology/FIRST-PRINCIPLES.md) |
| Matrix of which adjacent skill informs which methodology piece (50+ skills) | [methodology/SKILLS-CROSS-REF.md](references/methodology/SKILLS-CROSS-REF.md) |
| STRIDE-style threat catalog (Spoofing/Tampering/Repudiation/InfoDisclosure/DoS/Elevation) | [methodology/THREAT-MODEL.md](references/methodology/THREAT-MODEL.md) |
| 10 Hypothesis/proptest/fast-check property specifications | [methodology/PROPERTY-TESTS.md](references/methodology/PROPERTY-TESTS.md) |
| Orthogonal FM taxonomy: 7 kinds × 13 subsystems matrix | [methodology/FAILURE-ONTOLOGY.md](references/methodology/FAILURE-ONTOLOGY.md) |
| Minute-by-minute onboarding runbook | [methodology/FIRST-30-MINUTES.md](references/methodology/FIRST-30-MINUTES.md) |
| Design decision log (D-001…D-017 with alternatives-considered) | [methodology/DECISION-LOG.md](references/methodology/DECISION-LOG.md) |
| Per-audience reading: user / agent / operator / maintainer | [methodology/MENTAL-MODELS.md](references/methodology/MENTAL-MODELS.md) |
| Monorepo-specific recipe (turborepo / nx / rush / bazel) | [methodology/MONOREPO.md](references/methodology/MONOREPO.md) |
| The doctor contract written as RFC (testable conformance checklist) | [methodology/RFC.md](references/methodology/RFC.md) |
| Skill-level changelog (semver, round history) | [CHANGELOG.md](CHANGELOG.md) |
| Meta-doctor (Pattern 12 implementation) | [scripts/validate-skill.sh](scripts/validate-skill.sh) |

### Library + recipes
| Need | File |
|------|------|
| **Prompts (user → orchestrator)** — paste these into a Claude Code session to start work; organized by user intent | [methodology/PROMPT-LIBRARY.md](references/methodology/PROMPT-LIBRARY.md) |
| **Prompts (orchestrator → sub-agent that USES the built doctor)** — for after-the-fact use of the doctor; not for building | [methodology/AGENT-PROMPT-RECIPES.md](references/methodology/AGENT-PROMPT-RECIPES.md) |
| Active-incident playbook (tier 1-6 response runbooks) | [methodology/INCIDENT-RESPONSE.md](references/methodology/INCIDENT-RESPONSE.md) |
| Migrating an existing doctor to this methodology | [methodology/MIGRATION-GUIDE.md](references/methodology/MIGRATION-GUIDE.md) |
| 15 reusable detector predicates in 5 languages | [methodology/PREDICATE-LIBRARY.md](references/methodology/PREDICATE-LIBRARY.md) |
| Industry doctor comparison (cargo / npm / brew / rustup / git fsck / etc.) | [methodology/COMPARATIVE-ANALYSIS.md](references/methodology/COMPARATIVE-ANALYSIS.md) |
| 18 higher-order behavioral patterns (Probe-then-Commit, Saga, Bulkhead, etc.) | [methodology/DESIGN-PATTERNS.md](references/methodology/DESIGN-PATTERNS.md) |
| Scale adaptations (tiny → very large) | [methodology/SCALE.md](references/methodology/SCALE.md) |
| Standing roadmap + retrospective | [methodology/ROADMAP.md](references/methodology/ROADMAP.md) |

### Rubric
| Need | File |
|------|------|
| Ten-dimension rubric with 0/250/500/750/1000 anchors | [rubric/SCORING-RUBRIC.md](references/rubric/SCORING-RUBRIC.md) |
| Priority formula (frequency × score_gap × blast_radius) | [rubric/PRIORITY-FORMULA.md](references/rubric/PRIORITY-FORMULA.md) |
| Per-class scoring guidance (detector / fixer / verb / flag / artifact / capability / fixture) | [rubric/SURFACE-CLASSES.md](references/rubric/SURFACE-CLASSES.md) |
| Regression-test patterns per dimension | [rubric/REGRESSION-TEST-PATTERNS.md](references/rubric/REGRESSION-TEST-PATTERNS.md) |

### Exemplars (the source of truth for "what good looks like")
| Need | File |
|------|------|
| Canonical doctor exemplars distilled from `/dp` (`xf doctor`, `br doctor`, `caam doctor`, `caam robot`, `cm doctor`, `cass health`, `dcg explain`, `am health_check`) | [exemplars/exemplars.md](references/exemplars/exemplars.md) |
| Extended exemplars from `/dp/` (`dsr`, `ntm`, `wezterm`, `installer-workmanship`, `acfs`, `frankensearch`, `pi_agent_rust`, `flywheel_private`, …) | [exemplars/DP-EXEMPLARS-EXTENDED.md](references/exemplars/DP-EXEMPLARS-EXTENDED.md) |
| Counter-examples (real CLIs that fail one or more Polish Bar items) | [exemplars/COUNTER-EXAMPLES.md](references/exemplars/COUNTER-EXAMPLES.md) |
| CASS findings — strongest, durable patterns | [exemplars/CASS-FINDINGS.md](references/exemplars/CASS-FINDINGS.md) |
| CASS evidence index — comprehensive theme-organized cross-reference | [exemplars/CASS-EVIDENCE-INDEX.md](references/exemplars/CASS-EVIDENCE-INDEX.md) |

### Per-language recipes
| Need | File |
|------|------|
| Cross-language failure-mode catalog (state files, configs, schemas, sockets, hooks, plugins, …) | [recipes/failure_mode_catalog.md](references/recipes/failure_mode_catalog.md) |
| Rust recipe (clap, serde, sqlx, atomic-write, lockfile patterns) | [recipes/rust.md](references/recipes/rust.md) |
| Go recipe (cobra, encoding/json, atomic.os.Rename, syscall lock) | [recipes/go.md](references/recipes/go.md) |
| Python recipe (typer/click, pydantic, atomic write, fcntl/portalocker) | [recipes/python.md](references/recipes/python.md) |
| TS/Node + Bun + Deno recipe (commander/yargs, zod, fs-atomic, proper-lockfile) | [recipes/typescript.md](references/recipes/typescript.md) |
| Ruby / C/C++ / Zig / Elixir / Bash recipes | [recipes/other-languages.md](references/recipes/other-languages.md) |
| Multi-binary toolkit (`br + bv`-style projects) | [recipes/multi-binary-toolkit.md](references/recipes/multi-binary-toolkit.md) |
| Distributed CLI (vendor-API client; `wrangler`, `vercel`, `gh`, …) | [recipes/distributed-cli.md](references/recipes/distributed-cli.md) |
| Daemon CLI (`wrangler dev`, `ntm`, `mcp-agent-mail`, …) | [recipes/daemon-cli.md](references/recipes/daemon-cli.md) |
| Installer / provisioner CLI (`acfs`, `dsr`, …) | [recipes/installer.md](references/recipes/installer.md) |
| JVM family (Java / Kotlin / Scala / Clojure) + Swift | [recipes/jvm.md](references/recipes/jvm.md) |

---

## Scripts

These are the skill's own helpers, executable across passes. They all read `<workspace>/manifest.json` to know which pass + target they're operating on. All scripts honor `NO_COLOR`, exit 0 on success, ≥ 1 on failure with a stderr message naming the next remediation step.

| Script | Purpose |
|--------|---------|
| `scripts/check-skills.sh` | Detect referenced helper skills + jsm state; write `phase0_skill_inventory.json` |
| `scripts/install-referenced-skills.sh` | Bulk-install missing skills via jsm |
| `scripts/discover-cli.sh` | Detect language, build system, binary entry points, completion scripts, embedded man pages, **existing doctor surfaces** |
| `scripts/scaffold-workspace.sh` | Create workspace dirs + (optionally) `git worktree add` for `doctor-mode-pass-<N>` |
| `scripts/scorecard.py` | Multi-subcommand scorecard utility — reads `.doctor/runs/<id>/scorecard.json` + per-FM × per-dimension scores. Subcommands: `render <workspace>` (aggregate scorecard + heatmap.svg), `validate <workspace>` (rejects >=700 scores lacking evidence; rejects unacked regression blocks emitted by `diff-scorecards.py`), `compare-against-baseline <new> <baseline>`, `append-history <run_dir> <history_jsonl>` |
| `scripts/diff-scorecards.py` | Compare two passes by parsing `scorecard_pass_<A>.md` + `scorecard_pass_<B>.md`; emit `uplift_diff.md` + `regression_alerts.md`; hard-stops on unacked >50pt regressions |
| `scripts/compute-fm-id.py` | Compute the canonical content-derived `fm-<slug>` ID for a failure mode (so the same FM gets the same ID across passes) |
| `scripts/verify-undo.sh` | Phase 5 helper: corrupt fixture → `<tool> doctor --fix` → assert healthy → `<tool> doctor undo <run-id>` → byte-identical to corrupted |
| `scripts/verify-idempotence.sh` | Phase 5 helper: `<tool> doctor --fix; <tool> doctor --fix`; assert second run reports no actions |
| `scripts/verify-crash-recovery.sh` | Phase 5 helper: SIGKILL doctor mid-fix; next run finishes or aborts cleanly |
| `scripts/verify-concurrency.sh` | Phase 5 helper: launch two `doctor --fix` simultaneously; assert one wins (exit 0/2), other refuses with exit 5 (`concurrency_lost`) |
| `scripts/verify-capabilities.sh` | Phase 6 helper: round-trip `<tool> doctor capabilities --json` against the binary; assert every declared detector/fixer exists |
| `scripts/validate-doctor.sh` | Phase 7 helper: enforce the universal safety envelope (no destructive shell, no `rm -rf`, every write through `mutate()`, atomic writes only) |
| `scripts/validate-fm.py` | Lint a single `analysis/failure_modes/<subsystem>.md` row for required fields (id, severity, subsystem, auto_detected, auto_fixed) |
| `scripts/validate-spec.py` | Lint a `analysis/repair_specs/<id>.md` for required sections (detector, fixer, preconditions, invariants, backup spec, inverse, fixture) |
| `scripts/validate-dag.py` | Verify `analysis/dependency_graph.json` is acyclic. Schema: `{"nodes": ["fm-...", ...], "edges": [{"from": "fm-...", "to": "fm-..."}, ...]}` |
| `scripts/validate-skill.sh` | **Meta-doctor (Pattern 12).** Validates this skill's own internal consistency: frontmatter length, Q-NNN citation integrity, cross-reference targets, no destructive shell in scripts, orphan detection |
| `scripts/manifest-update.sh` | Atomically update `<workspace>/manifest.json` with new artifacts/scores/pass |
| `scripts/preflight-check.sh` | Phase 0.0 helper: verify required external tools (jq, git, python3, awk, sed) + report optional ones (jsm, cass, br, bv, am). Emits `<workspace>/preflight.json`. **Run before any other Phase 0 script.** |
| `scripts/mine-changelog.py` | Phase 0 helper: extract bug-fix lines from target's CHANGELOG.md; pre-classify by subsystem; write `<workspace>/changelog_findings.jsonl`. Phase 1 archaeologist consumes this. |
| `scripts/cass-mine.sh` | Phase 0 helper: run the 13 canonical CASS queries from CASS-PLAYBOOK.md; deduplicate; write `<workspace>/cass_findings.jsonl`. Skipped if cass not installed. |
| `scripts/query-corpus.py` | Phase 0 helper: filter `references/corpus/known-fms.jsonl` by `--language` / `--subsystem` / `--severity`. Phase 1 archaeologist uses this for seed FMs. |
| `scripts/build-corpus.py` | Maintainer-only: aggregate per-project mine-changelog outputs into a candidate `known-fms.jsonl`. Output is noisy; the canonical corpus is hand-curated. |
| `scripts/scaffold-doctor.sh` | Phase 4 helper: emit a stub doctor module (Rust / Go / Python / TypeScript) with the canonical 10 subcommands stubbed, `mutate()` chokepoint declared, exit-code dictionary defined, JSON shape pre-wired. Phase 4 implementer fills in detector/fixer bodies. |
| `scripts/run-safety-harness.sh` | Phase 5 helper: orchestrate all `verify-*.sh` scripts in sequence; emit consolidated `safety_harness.jsonl` per FM; PASS/FAIL summary. |
| `scripts/conformance-harness.sh` | Phase 5/Phase 6 (upgrade mode): compare two doctor implementations against the same fixtures; emit `conformance_report.{md,jsonl}`. Used to detect silent regressions during upgrade. |
| `scripts/beads-from-fms.sh` | Phase 1→Phase 4 helper: file `br create` beads for each P0/P1 FM emitted in Phase 1; add `br dep add` edges from `dependency_graph.json`. Idempotent. |
| `scripts/bv-prioritize.py` | Phase 6 helper: rank FMs by graph centrality (PageRank + in/out-degree + topological order) over `dependency_graph.json`. Complements static `frequency × blast_radius` priority. |
| `scripts/emit-agents-md-section.sh` | Phase 8 helper: read `<tool> doctor capabilities --json` and emit a markdown `AGENTS.md § <tool> doctor` section the integration-wirer appends to the target's AGENTS.md. |
| `scripts/coverage-gap.py` | Maintainer: cross-correlate corpus FMs with cumulative `scorecard_history.jsonl` files; report (a) corpus FMs no project detects + (b) frequently-detected FMs not in corpus. |
| `scripts/dashboard.py` | Operator: one-screen ASCII summary of an in-flight pass (phase status, FM counts, scorecard delta, ETA). `--watch SEC` for refresh. |
| `scripts/single-fm-rescore.sh` | Tight inner loop: re-score ONE FM (run safety harness for that FM, update `failure_mode_scores.jsonl`, regenerate scorecard) without a full Phase-6 rerun. |
| `scripts/corpus-grow-suggest.py` | Maintainer: propose corpus additions/demotions based on a single project's Phase-1 outputs. Companion to `coverage-gap.py`. |
| `scripts/verify-metamorphic.sh` | Phase 5 helper: assert detector idempotence (`detect(state) == detect(state)`). 5th test in `run-safety-harness.sh`. |
| `scripts/snapshot-capabilities.sh` | Golden-artifact regression: capture `capabilities --json` to a snapshot; subsequent runs diff against it. Drift fails CI. |
| `scripts/migrate-contract.sh` | Apply mechanical changes documented in `CONTRACT-MIGRATIONS.md` for a `doctor_contract_version` bump. |
| `scripts/verify-cross-fm.sh` | Phase 5.5 helper: test ordered FM-A, FM-B pair for cross-FM interactions. Ensures fix-A-then-fix-B doesn't leave residual findings. |
| `scripts/log-phase-timing.sh` | Subagent helper: append phase start/finish events to `phases_timing.jsonl`. Feeds `dashboard.py`. |
| `scripts/self-apply.sh` | Pattern 12 (meta-doctor) gate: run all meta-validators against the skill itself. CI-grade self-check. |

For Phase 9 fixture authoring (the per-FM corrupter scripts), copy `assets/fixture-template.sh` into `tests/doctor_fixtures/<fm-id>/corrupt.sh` and customize per-FM. The `subagents/baseline-snapshotter.md` subagent (not a separate script) snapshots the existing doctor's behavior into `baseline/` for upgrade mode.

For monorepo projects with multiple CLIs, see [`references/recipes/monorepo-multi-cli.md`](references/recipes/monorepo-multi-cli.md). Build-system-specific recipes: [`references/recipes/bazel-monorepo.md`](references/recipes/bazel-monorepo.md), [`references/recipes/nix-flake.md`](references/recipes/nix-flake.md), [`references/recipes/jvm-multi-module.md`](references/recipes/jvm-multi-module.md), [`references/recipes/cargo-npm-hybrid.md`](references/recipes/cargo-npm-hybrid.md).
For the cross-project FM corpus, see [`references/corpus/README.md`](references/corpus/README.md).
For contract-version migrations (when `doctor_contract_version` bumps), see [`references/methodology/CONTRACT-MIGRATIONS.md`](references/methodology/CONTRACT-MIGRATIONS.md).

Per-script docs and exit-code contracts: [methodology/IO-CONTRACTS.md § Script contracts](references/methodology/IO-CONTRACTS.md).

---

## Subagents

| Subagent | Phase | Purpose |
|----------|-------|---------|
| `subagents/cass-miner.md` | 0 | Mine prior agent sessions for tool-specific failure modes, post-mortems, "I had to manually fix X" moments |
| `subagents/baseline-snapshotter.md` | 0 | (upgrade mode) Snapshot existing doctor's `--help`, `--json`, exit-code dict into `baseline/` |
| `subagents/archaeologist.md` | 1 | Enumerate failure modes for one subsystem; cross-reference bug tracker + git log + cass + AGENTS.md |
| `subagents/repair-spec-author.md` | 2 | Same agent that did the archaeology writes the repair spec — context wins |
| `subagents/spec-reviewer.md` | 2.5 | Reviews every spec against the kernel + chokepoint contract before Phase 3 accepts; files P1 beads for rework |
| `subagents/synthesizer.md` | 3 | Single agent: produce taxonomy, dependency graph, conflict matrix, safety envelope, narrative chapters |
| `subagents/implementer.md` | 4 | Implement detectors/fixers for one subsystem on the feature branch; route every write through `mutate()`; emit per-run artifact |
| `subagents/mutate-auditor.md` | 4 / 7 | Code-search: assert no other code path writes to disk under `--fix`; flag every violation |
| `subagents/safety-harness-runner.md` | 5 | Run reversibility / idempotence / crash-recovery / concurrency / detector-metamorphic tests for every fixer |
| `subagents/agent-ergo-grader.md` | 6 | Apply [agent-ergonomics-and-intuitiveness-maximization-for-cli-tools](../agent-ergonomics-and-intuitiveness-maximization-for-cli-tools/SKILL.md) as a reference rubric to grade the new doctor surface |
| `subagents/scorecard-generator.md` | 6 | Compute per-FM × per-dimension scores; emit `failure_mode_scores.jsonl` + `scorecard.md` + heatmap |
| `subagents/fresh-eyes.md` | 7 | Run the three calibrated review prompts; until two clean passes |
| `subagents/triangulator.md` | 4 / 7 | Multi-model verification (Claude + Codex + Gemini) for top recommendations and irreversible paths |
| `subagents/integration-wirer.md` | 8 | Wire `doctor --json` into pre-commit / CI; demote related manual playbook skill to fallback |
| `subagents/fixture-author.md` | 9 | Build `tests/doctor_fixtures/<failure-mode>/` reproducibly broken states + paired tests |
| `subagents/cold-agent-prober.md` | 10 | Fresh-context agent invokes the doctor cold; reports confusing `--help`, ambiguous JSON, escalation needs |
| `subagents/handoff-writer.md` | 10 | Write `HANDOFF.md` for the next pass; file beads for queued work |
| `subagents/idea-generator.md` | 10 | Surface second-order ergonomic improvements via `/idea-wizard` |

---

## Assets

| Asset | Purpose |
|-------|---------|
| `assets/skill-card.md` | One-page elevator pitch; read first if deciding whether to invoke |
| `assets/intake-prompt.md` | Verbatim up-front confirmations to gather inputs |
| `assets/intake-worksheet.md` | Structured pre-intake form for the user to fill in |
| `assets/manifest-template.json` | Initial `<workspace>/manifest.json` structure |
| `assets/repair-spec-template.md` | Template for `analysis/repair_specs/<id>.md` |
| `assets/failure-mode-template.md` | Template for `analysis/failure_modes/<subsystem>.md` |
| `assets/scorecard-template.md` | Markdown template for human-readable scorecard |
| `assets/scorecard-example.md` | Worked example scorecard for `br doctor` after pass-1 |
| `assets/handoff-template.md` | Template for `HANDOFF.md` |
| `assets/canonical-tasks-template.md` | Phase 10 cold-prober's canonical 10 tasks |
| `assets/dispatch-prompts.md` | Quick-reference shorthand prompts (user-facing, parameter-pre-filled). Full per-phase prompts live in `methodology/AGENT-PROMPTS.md` |
| `assets/fixture-template.sh` | Template for `tests/doctor_fixtures/<failure-mode>/corrupt.sh` |
| `assets/regression-test-template.sh` | Template for the round-trip test asserting repair |
| `assets/capabilities-template.json` | Template for `<tool> doctor capabilities --json` output |
| `assets/report-template.json` | Template for `<run-id>/report.json` |
| `assets/actions-jsonl-line-template.json` | Template for one line of `actions.jsonl` |

---

## Self-Test

Trigger phrases that should activate this skill:

- "Add a `doctor` subcommand to this CLI"
- "Upgrade `<tool>`'s doctor command — make it world-class"
- "Build a doctor mode for this Rust/Go/Python/TS CLI"
- "Make `<tool> doctor --fix` actually fix things automatically and reversibly"
- "Convert this manual repair playbook into a `doctor` subcommand"
- "Absorb `fixing-beads-problems` into `br doctor --fix`"
- "Score this CLI's doctor against the world-class rubric"
- "Re-run the doctor build on `<tool>` and tell me what improved since pass-N"
- "Add `<tool> doctor capabilities --json` and `<tool> doctor robot-docs`"
- "Build a fixture suite for `<tool> doctor` so every fixer has a regression test"
- "Make sure `<tool> doctor --fix` is idempotent and reversible — and prove it"

Trigger-phrase probe + smoke test against a tiny throwaway CLI in `/tmp/`: [SELF-TEST.md](SELF-TEST.md).
