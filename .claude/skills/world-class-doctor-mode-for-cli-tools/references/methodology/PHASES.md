# Phase Playbook

Each phase below has: **goal**, **inputs**, **outputs**, **subagent(s) to dispatch**, **exit criteria**, **failure modes**, **verbatim prompt** to send. Phases 1–4 fan out across subsystems; Phases 3, 5, 6, 8, 10 collapse to a single agent; Phase 7 swarms.

Phases 4, 5, 7 are *reapply-until-quiet*: keep spawning passes until termination thresholds are met (median uplift < 25 points, no regression > 50 points, two consecutive clean fresh-eyes rounds).

---

## Phase 0 — Bootstrap

**Goal.** Confirm inputs, scaffold workspace, snapshot baseline (upgrade mode), inventory helper skills.

**Inputs.** target repo path, mode, triangulation appetite, online appetite.

**Outputs.**
- `<workspace>/manifest.json` (use `assets/manifest-template.json`)
- `<workspace>/phase0_scope_decision.md`
- `<workspace>/phase0_skill_inventory.json`
- `<workspace>/phase0_cli.json`
- `<workspace>/baseline/` (upgrade mode only): `help_output.txt`, `json_output_healthy.json`, `json_output_corrupted.json`, `exit_code_dictionary.txt`
- `<workspace>/worktree/` (if requested) — `git worktree add` from target's default branch

**Subagents.** `subagents/cass-miner.md`, `subagents/baseline-snapshotter.md` (upgrade mode only).

**Exit criteria.**
- `manifest.json` references a valid `target_sha` and binary list.
- (Upgrade mode) `baseline/help_output.txt` is non-empty and reflects the current binary.
- `phase0_skill_inventory.json` lists every helper skill referenced in this skill with `installed: bool`.

**Verbatim prompt** (to dispatch the cass-miner):

```
You are mining the user's prior agent sessions for evidence about how the
target CLI {{tool}} fails in real life — not how its docs say it fails.

Run these 13 canonical queries and capture the strongest 5–15 quotes per query into
`<workspace>/cass_findings.md` with full citations (source_path, agent,
created_at, line_number):

1. cass search "\"{{tool}} stale lock\"" --json --limit 20 --fields minimal
2. cass search "\"{{tool}} corruption\" OR \"{{tool}} corrupt\"" --json --limit 20 --fields minimal
3. cass search "\"{{tool}} migration\" failure" --json --limit 20 --fields minimal
4. cass search "\"{{tool}} race\" OR TOCTOU" --json --limit 20 --fields minimal
5. cass search "\"{{tool}} deadlock\"" --json --limit 20 --fields minimal
6. cass search "\"{{tool}} sqlite\" corruption" --json --limit 20 --fields minimal
7. cass search "\"{{tool}} jsonl\" tombstone OR drift" --json --limit 20 --fields minimal
8. cass search "\"{{tool}} undo\" OR \"{{tool}} restore\"" --json --limit 20 --fields minimal
9. cass search "\"{{tool}} crash\" recovery" --json --limit 20 --fields minimal
10. cass search "\"{{tool}} symlink\" TOCTOU OR traversal" --json --limit 20 --fields minimal
11. cass search "\"{{tool}} schema\" version mismatch" --json --limit 20 --fields minimal
12. cass search "\"{{tool}} cache\" stale" --json --limit 20 --fields minimal
13. cass search "\"{{tool}} had to manually\"" --json --limit 20 --fields minimal

For each quote, classify into: SYMPTOM, ROOT_CAUSE, MANUAL_FIX, INCIDENT,
WISH_THIS_EXISTED. The MANUAL_FIX entries are gold — they are the exact
playbook the doctor must absorb in Phase 4.

Save the structured findings as `<workspace>/cass_findings.md` AND as
`<workspace>/cass_findings.jsonl` (one entry per line).
```

---

## Phase 1 — Project Archaeology + Failure-Mode Inventory (parallel by subsystem)

**Goal.** For each subsystem of the target project, enumerate every realistic failure mode: symptoms, root causes, observable signals, severity, prior incidents, and whether currently auto-detected/auto-fixed.

**Inputs.** `phase0_cli.json`, `cass_findings.md`, project's bug tracker (`br ready --json`, `br list --status=open --json`, `gh issue list --json`), `git log --grep='fix\|panic\|corrupt\|race\|deadlock\|leak' --oneline -200`.

**Outputs.** `<workspace>/analysis/failure_modes/<subsystem>.md` per subsystem. Use `assets/failure-mode-template.md`.

**Subsystem catalog** (default; refine per project):

- `state_files` — embedded DB, JSONL, lock files, pid files
- `configs` — TOML/YAML/JSON config, env files, MCP configs
- `schemas` — DB migrations, schema drift, version mismatches
- `caches` — disk caches, memo files, derived indexes
- `sockets` — Unix sockets, named pipes, TCP listeners
- `hooks` — git hooks, pre-commit, IDE hooks
- `plugins` — plugin dirs, extension manifests
- `secrets` — keychain entries, env vars, credential files
- `permissions` — file modes, ACLs, ownership
- `external_artifacts` — built binaries, completion scripts, man pages
- `concurrency_primitives` — flock files, advisory locks, mutexes
- `network` (if project does any) — DNS, TLS, vendor APIs
- `userland_state` — `~/.config/<tool>/`, `~/.local/share/<tool>/`, XDG dirs

**Subagent.** `subagents/archaeologist.md` (one per subsystem).

**Exit criteria.**
- Every subsystem has a `<subsystem>.md` with ≥ 3 failure modes (or an explicit `n/a` block explaining why none).
- Each failure mode lists: id (content-derived via `scripts/compute-fm-id.py`), title, severity (P0/P1/P2/P3), symptoms, root cause, observable signals (file:line, query, log pattern), prior incidents (git SHAs, bead IDs, cass quotes), currently auto-detected (yes/no), currently auto-fixed (yes/no).
- Aggregate count posted to `<workspace>/analysis/inventory_summary.md`.

**Verbatim prompt** in [AGENT-PROMPTS.md § archaeologist](AGENT-PROMPTS.md#archaeologist).

---

## Phase 2 — Repair Specification (parallel, same agent per subsystem)

**Goal.** For each failure mode, write a Repair Spec: detector pseudocode, fix pseudocode, preconditions, invariants, backup spec, inverse, idempotence proof sketch, fixture spec.

**Critical rule.** The agent that did the archaeology for a subsystem in Phase 1 writes the repair specs for that subsystem in Phase 2. Context wins. Don't shuffle ownership.

**Outputs.** `<workspace>/analysis/repair_specs/<id>.md` per failure mode. Use `assets/repair-spec-template.md`.

**Each spec contains.**

```markdown
# RS-<id> — <title>

**Failure mode:** fm-<id>
**Subsystem:** <subsystem>
**Severity:** P0 | P1 | P2 | P3
**Currently auto-detected:** yes | no
**Currently auto-fixed:** yes | no

## Detector (pure)

Returns `Finding | None`. NEVER mutates. Pseudocode:

```
fn detect_<id>(repo) -> Option<Finding> {
    // ...
}
```

## Fixer (mutates via mutate())

Returns `FixResult { actions_planned, actions_taken }`. Routes EVERY write
through `mutate()`. Pseudocode:

```
fn fix_<id>(repo) -> FixResult {
    // 1. Read current state.
    // 2. Compute desired state.
    // 3. For each (path, op) in plan:
    //      mutate(path, op)  // does backup + hash + actions.jsonl
    // 4. Verify post-state via the detector.
}
```

## Preconditions

- ...

## Invariants preserved

- ...

## Backup spec

Files backed up by this fixer (verbatim, byte-identical, via `mutate()`):
- ...

## Inverse

Restore from `<run-id>/backups/` per the standard `doctor undo <run-id>` path.

Special-case inverse logic, if any:
- ...

## Idempotence proof sketch

After `fix_<id>` runs once, calling `detect_<id>` returns `None`. Therefore
the next `fix_<id>` invocation is a no-op (it never enters the mutation
loop). Verified by `verify-idempotence.sh fm-<id>`.

## Fixture spec

`tests/doctor_fixtures/<id>/`:
- `corrupt.sh` — reproducibly creates the broken state
- `assert.sh` — asserts post-fix state is healthy
- `README.md` — what the fixture represents

## Open questions

- ...
```

**Subagent.** `subagents/repair-spec-author.md` (one per subsystem; same agent that did Phase 1 for that subsystem).

**Skeleton fixture contract (round-53).** In addition to writing the spec, Phase 2 emits a SKELETON pair `tests/doctor_fixtures/<fm_id>/{corrupt.sh, assert.sh}` per FM:
- `corrupt.sh <sandbox>` — produces the corrupted state described in the spec's `triggered_by_findings`.
- `assert.sh <sandbox>` — asserts the post-fix expected state matches.
- Both must be `chmod +x`.

Why Phase 2 (not Phase 9): Phase 5's safety harness (`run-safety-harness.sh`) cannot run without these. The fixtures are formally "built in Phase 9" by `subagents/fixture-author.md`, but Phase 5 hard-fails (verify-undo.sh exit 1) if `corrupt.sh` is missing. Splitting the work — Phase 2 emits the skeleton, Phase 9 expands with edge cases and golden artifacts — closes the ordering gap. Phase 9's fixture-author MUST extend, not overwrite, the skeleton.

**Exit criteria.**
- Every failure mode from Phase 1 has a corresponding `analysis/repair_specs/<id>.md`.
- Every failure mode has skeleton `tests/doctor_fixtures/<fm_id>/{corrupt.sh, assert.sh}` (executable, minimal but functional).
- Spec passes `scripts/validate-spec.py` (checks: detector signature is pure; fixer goes through `mutate()`; backup spec is non-empty; inverse is named; idempotence sketch is present; fixture spec is present).
- Spec includes a "Metamorphic relations" section listing relations the detector preserves (round-56). Minimum: `detect(state) == detect(state)` (idempotence under repeated detection). Verified by `scripts/verify-metamorphic.sh` in Phase 5.

---

## Phase 2.5 — Spec Review (single reviewer; Pair+ tier only)

**Goal.** Catch spec-level violations of the kernel and the `mutate()` chokepoint contract before Phase 3's synthesizer accepts the specs.

**Inputs.** All `<workspace>/analysis/repair_specs/*.md` from Phase 2.

**Subagent.** [`subagents/spec-reviewer.md`](../../subagents/spec-reviewer.md). One reviewer for the whole spec set.

**Process.**

1. Run `python3 scripts/validate-spec.py <workspace>/analysis/repair_specs/<id>.md` against each spec (the script takes one path arg; loop over the directory).
2. For each spec, verify axiom compliance: detector is pure (no `mutate()` calls), fixer goes through `mutate()`, backups are listed, inverse is named, idempotence sketch present, fixture spec deterministic.
3. Cross-reference each spec against its FM file (severity, subsystem, prior_incidents alignment).
4. Classify each as PASS, REWORK (file P1 bead, blocks Phase 3 for that FM), or QUESTION (note in spec_review.md, doesn't block).

**Outputs.**
- `<workspace>/analysis/spec_review.md` — per-spec classification.
- P1 beads for every REWORK.

**Exit criteria.**
- Every spec is PASS, REWORK, or QUESTION.
- No spec is in REWORK without a corresponding bead.

**When to skip.** Solo tier (the same agent that wrote the spec usually catches its own bugs in Phase 4 implementation). Always run at Pair+ tier. Always run in `upgrade` mode.

---

## Phase 3 — Synthesis + Harmonization (single agent)

**Goal.** Read all repair specs and produce taxonomy, dependency graph, conflict matrix, safety envelope, and the user-facing narrative chapters.

**Outputs.**
- `<workspace>/analysis/taxonomy.md` — canonical naming and severity buckets
- `<workspace>/analysis/dependency_graph.md` — which repairs must precede which (e.g., schema fix before index rebuild) — both ASCII diagram + machine-readable JSON in `<workspace>/analysis/dependency_graph.json`
- `<workspace>/analysis/conflict_matrix.md` — repairs that must NEVER run in the same pass + the reason
- `<workspace>/analysis/safety_envelope.md` — project-specific invariants on top of the universal envelope
- `<workspace>/playbook.md` — narrative chapters: "What doctor will and will not do", "What you should back up first" (even though doctor backs up too), "How to recover if doctor itself goes wrong"

**Subagent.** `subagents/synthesizer.md`.

**Exit criteria.**
- `dependency_graph.json` is a DAG (verified by `scripts/validate-dag.py`).
- `conflict_matrix.md` cites every blacklisted pair with a one-line "why".
- `safety_envelope.md` extends the universal envelope (does not contradict it).
- `playbook.md` contains all three required chapters.

---

## Phase 4 — Implementation (parallel by subsystem, gated on Phase 3)

**Goal.** Implement detectors, fixers, the `mutate()` chokepoint, backup/restore primitives, per-run artifact emission, and the `<tool> doctor` surface in the project's native language.

**Strict rules** (re-read [MUTATE-CHOKEPOINT.md](MUTATE-CHOKEPOINT.md) before writing any code):

- Detect-then-fix; detectors are pure, never mutate.
- Every fix path goes through `mutate(path, op)`. `mutate()` writes the backup, computes before/after hashes, appends to `actions.jsonl`, holds the file lock, and is the **only** code allowed to touch the disk under `--fix`.
- `<tool> doctor` (no flags) = read-only diagnose.
- `<tool> doctor --fix` = repair with backups.
- `<tool> doctor --dry-run --fix` = print the plan without executing.
- `<tool> doctor --explain <finding-id>` = expand a single finding with full evidence.
- `<tool> doctor undo <run-id>` and `undo latest` work.
- `--json` and `--robot` produce stable, versioned schemas (include `schema_version`).
- Exit codes: 0 healthy, 1 findings present (no `--fix`), 2 fix attempted and partial, 3 fix failed and rolled back, 4 unsafe state/refused, 5 concurrency lost, 6 online required, 64 usage error, 66 no input, 73 cannot create output, 74 I/O error.
- stdout = data, stderr = human progress; never mix.
- All TTY-only output (colors, spinners) auto-disables when stdout isn't a TTY or when `--robot`/`--json`/`NO_COLOR` is set.

**Outputs.**
- Code on the feature branch `doctor-mode-pass-<N>` in the target repo.
- One bead per applied recommendation (`br create --type=task --priority=...`).
- Per-pass commit per subsystem so the diff is reviewable.
- `<workspace>/applied_changes.jsonl` — one line per applied repair spec with before/after evidence.

**Subagent.** `subagents/implementer.md` (one per subsystem) + `subagents/mutate-auditor.md` (one for the whole pass).

**Exit criteria.**
- `cargo build` / `go build` / `bun run typecheck` / `pytest --collect-only` (or language equivalent) green.
- `scripts/validate-doctor.sh <target>` green: `mutate()` is the only writer; no destructive shell; atomic writes only.
- `<tool> doctor --help`, `<tool> doctor --json`, `<tool> doctor capabilities --json`, `<tool> doctor robot-docs`, `<tool> doctor health` all exist and respond.
- `<tool> doctor` on a healthy fixture exits 0; on each broken fixture exits 1.
- `<tool> doctor --fix` on each broken fixture exits 0 and produces a `.doctor/runs/<run-id>/` directory with `report.json`, `actions.jsonl`, `backups/`, `undo.sh`.

**Verbatim prompts** in [AGENT-PROMPTS.md § implementer](AGENT-PROMPTS.md#implementer) and § mutate-auditor.

---

## Phase 5 — Safety Harness

**Goal.** Prove reversibility, idempotence, crash-recovery, concurrency safety, and detector metamorphic repeatability for every fixer. Failures here are blocking.

**The five tests** (run for every failure mode that has a fixer):

### 5.1 Reversibility
```
corrupt fixture → <tool> doctor --fix → assert healthy → <tool> doctor undo <run-id> → assert byte-identical to corrupted state
```

If `cmp -s <corrupted-baseline> <restored>` fails, the fixer is broken. The fix must NOT touch unrelated bytes.

> **Helper invocation** for all five verify-*.sh scripts: each takes `<fm_id> [<tool>] [<fixture_root>]`. The `<tool>` arg is required as arg 2 OR via the `TOOL` env var (else the script exits 64 with usage). Recommended: `export TOOL=<tool>` once at the top of the harness loop, then call each helper with just the fm_id.

Helper: `scripts/verify-undo.sh fm-<id>`.

### 5.2 Idempotence
```
<tool> doctor --fix; <tool> doctor --fix
```

Second run must report `actions_taken: 0` and exit 0. If not, the detector is dirty (mutating a side channel) or the fixer is non-idempotent.

Helper: `scripts/verify-idempotence.sh fm-<id>`.

### 5.3 Crash-recovery
```
<tool> doctor --fix &; pid=$!; sleep <K>ms; kill -9 $pid; wait
<tool> doctor    # Next invocation
```

Next invocation must complete cleanly or refuse with exit 4 and a precise reason. No torn writes; no orphaned `.tmp.<pid>` files; no stale lock.

Tested at K = {1, 5, 25, 125} ms (varies by language) or via fault-injection points.

Helper: `scripts/verify-crash-recovery.sh fm-<id>`.

### 5.4 Concurrency
```
<tool> doctor --fix & <tool> doctor --fix
```

Exactly one wins; the other refuses with exit 5 (`concurrency_lost`) and a "lock held by pid X" finding.

Helper: `scripts/verify-concurrency.sh fm-<id>`.

### 5.5 Detector metamorphic repeatability
```
<tool> doctor diagnose --json --only=<fm_id>
<tool> doctor diagnose --json --only=<fm_id>
```

Both runs against the same corrupted fixture must produce equivalent `.findings` arrays after canonicalization. If not, the detector is non-deterministic or stateful.

Helper: `scripts/verify-metamorphic.sh fm-<id>`.

**Use these skills if available** to extend the harness:

- [testing-fuzzing](../../testing-fuzzing/SKILL.md) — fault-inject into `mutate()` chokepoint
- [testing-metamorphic](../../testing-metamorphic/SKILL.md) — assert "fix(corrupt(x)) = x" for properties that should be invariant
- [testing-conformance-harnesses](../../testing-conformance-harnesses/SKILL.md) — round-trip backup/restore against a golden corpus

**Outputs.** `<workspace>/safety_harness_report.md` + per-FM result rows in `<workspace>/safety_harness.jsonl`.

**Subagent.** `subagents/safety-harness-runner.md`.

**Exit criteria.** Every fixer passes all five tests. Failures regenerate the corresponding repair spec and re-enter Phase 4.

---

## Phase 6 — Agent-Ergonomic Surface + Scorecard

**Goal.** Polish the agent-facing surface (`capabilities`, `robot-docs`, `health`, `--robot-triage`) and produce the per-run scorecard generator.

**Inputs.** [agent-ergonomics-and-intuitiveness-maximization-for-cli-tools](../../agent-ergonomics-and-intuitiveness-maximization-for-cli-tools/SKILL.md) as the grader's reference rubric. **Cite it in `<workspace>/agent_ergo_grade.md`.**

**Outputs.**

- `<tool> doctor capabilities --json` — version, contract version, detectors, fixers, exit codes, env vars, run-artifact schema. Schema in [OUTPUT-SCHEMA.md § capabilities](OUTPUT-SCHEMA.md#capabilities).
- `<tool> doctor robot-docs` — paste-ready agent handbook printed to stdout.
- `<tool> doctor health` — cheap liveness summary; one line + exit code; for CI scheduling.
- `<tool> doctor --robot-triage` — mega-command returning summary, findings, actions_planned, recommended_command, capabilities_url. Full canonical schema (includes `schema_version`, `quick_ref`, `robot_docs_command`) in [CLI-SURFACE.md § --robot-triage](CLI-SURFACE.md).
- Scorecard generator (`scripts/scorecard.py`) — language-agnostic; reads `.doctor/runs/<id>/scorecard.json` from the latest run plus per-FM × per-dimension scores; emits aggregate `<workspace>/scorecard.md`, `heatmap.svg`, `scorecard_history.jsonl`.
- `<workspace>/scorecard_pass_<N>.md` — historical record.
- `<workspace>/agent_ergo_grade.md` — score the new doctor against the agent-ergonomics rubric.

**Subagents.** `subagents/agent-ergo-grader.md`, `subagents/scorecard-generator.md`.

**Exit criteria.**
- `scripts/verify-capabilities.sh` round-trips: every detector + fixer in `capabilities --json` is callable and produces consistent output.
- `<tool> doctor robot-docs` is non-empty and includes: command list, exit-code dictionary, schema_version, every flag, examples for the canonical happy path, examples for the canonical broken path.
- `<tool> doctor health` returns in < 200ms on a healthy workspace.
- `--robot-triage` returns valid JSON matching the schema.
- Scorecard is computed for every failure mode × every dimension; aggregate score is recorded in `manifest.json`.

---

## Phase 7 — Multi-Pass Fresh-Eyes Review (until two clean passes)

**Goal.** Three calibrated review prompts, dispatched to fresh subagents, then linter/typechecker/build/UBS/scorecard threshold gate.

**The three prompts** (verbatim — they're calibrated):

1. *"Reread the new doctor code with fresh eyes. Look for obvious bugs, races, partial-write windows, unsafe `unwrap`/`expect`/panics on user paths, missing backups, broken idempotence, or any place where exit codes lie about reality. Carefully fix anything you uncover."*
2. *"Randomly pick three detectors and three fixers; trace their full execution including the `mutate()` chokepoint, backup write, and undo path. Construct a scenario that would corrupt user data and prove the code prevents it — or fix it."*
3. *"Review your fellow agents' code without restricting to recent commits. Find root causes via first-principles analysis. Pay special attention to: TOCTOU between detect and fix, signal handling, FS atomicity (rename vs write), interaction with the project's existing locks, and any path that bypasses `mutate()`."*

After each round, run:

```bash
ubs $(git diff --name-only HEAD~1 HEAD)        # If available
cargo clippy -- -D warnings                    # Or language equivalent
cargo test                                     # Or language equivalent
scripts/validate-doctor.sh <target>            # Universal envelope
scripts/diff-scorecards.py <workspace> <N-1> <N> # Threshold gate
```

**Termination.** Two consecutive rounds where the only changes are typo/whitespace. Rephrasing IS a change.

**Subagent.** `subagents/fresh-eyes.md` (dispatched fresh each round, no prior context). Use `subagents/triangulator.md` if multi-model is available.

**Exit criteria.** Two clean passes. UBS clean. Lint/typecheck/test clean. `scripts/validate-doctor.sh` exits 0. `diff-scorecards.py` reports no regression > 50 points.

---

## Phase 8 — Integration + Dogfooding

**Goal.** Wire `<tool> doctor` into pre-commit hooks, CI, and project entry points; demote any related manual playbook to a fallback.

**Outputs (high level).**

1. **Pre-commit hook.** Either an entry in `.pre-commit-config.yaml` (if the project uses pre-commit) or a `.git/hooks/pre-commit` shim. Runs `<tool> doctor --quick --json` and blocks the commit on any finding.
2. **CI workflow.** A GitHub Actions / GitLab / Bitbucket job that runs `<tool> doctor health` plus a regression-check step. The regression check uses the **doctor's own `.doctor/runs/<id>/scorecard.json`** + `jq`, NOT this skill's `scripts/scorecard.py` — the script lives in the skill repo, not the target's CI workdir, so `./scripts/scorecard.py` would `command not found` on the runner.
3. **Demote related manual-playbook skill** (if any). Update the related skill's `SKILL.md` so the first recommendation is `<tool> doctor --fix`, with the original playbook kept intact as a fallback per AGENTS.md no-delete.

**Canonical implementation.** All three outputs are spelled out in **[`subagents/integration-wirer.md`](../../subagents/integration-wirer.md)** — verbatim hook script, full CI YAML + jq regression check, and the demote-skill procedure. PHASES.md is the high-level overview; the subagent is the source of truth. Do NOT duplicate the snippets here — they drift (per round-49 fresh-eyes finding).

**Subagent.** `subagents/integration-wirer.md`.

**Exit criteria.**
- CI run on a feature branch passes the doctor health check.
- A pre-commit attempt on a corrupted fixture is blocked.
- The related manual-playbook skill, if any, has its top-of-file recommendation updated to point at `<tool> doctor`.

---

## Phase 9 — Real-World Fixture Suite

**Goal.** `tests/doctor_fixtures/` tree with one fixture per failure mode plus combinatorial pairs for the worst offenders. This is the regression net.

**Each fixture directory** (`tests/doctor_fixtures/<failure-mode>/`):

```
fm-jsonl-tombstone-drift/
├── README.md             ← what this fixture represents; expected exit code
├── corrupt.sh            ← reproducibly create the broken state in a temp dir
├── assert.sh             ← assert the post-fix state is healthy
└── golden/               ← (optional) pre-fix and post-fix golden artifacts for comparison
```

**Combinatorial pairs.** For the worst offenders (P0 + P0, P0 + P1), build pair-fixtures that simulate two failures at once. Some pairs MUST be in the conflict matrix and refuse with exit 4; others should be repaired in dependency order.

**Outputs.**

- One fixture dir per failure mode + ≥ 5 combinatorial pairs for the worst offenders.
- `tests/doctor_fixtures/run_all.sh` — invokes every fixture's `corrupt.sh`, runs `<tool> doctor --fix`, runs `assert.sh`, then runs `<tool> doctor undo` and asserts byte-identical to corrupted.
- A CI step that runs `tests/doctor_fixtures/run_all.sh` on every PR touching `<tool>` doctor code.

**Subagent.** `subagents/fixture-author.md`.

**Exit criteria.** `tests/doctor_fixtures/run_all.sh` exits 0. Round-trip test passes for every fixture.

---

## Phase 10 — Final Agent-UX Pass

**Goal.** A fresh agent invokes the new doctor cold (no prior context) and reports what was confusing, ambiguous, or missing. Apply notes in one polish pass.

**Process.**

1. Spawn a fresh subagent (`subagents/cold-agent-prober.md`) with NO context from this skill, the workspace, or the target repo's recent commits. Hand it ONLY the binary, the canonical task list (`<workspace>/canonical_tasks.md`), and `<tool> doctor robot-docs` output.
2. The agent attempts each canonical task and writes a transcript per task to `<workspace>/agent_simulations/post_pass_<N>/<task>.transcript.jsonl`.
3. The agent reports: what was confusing in `--help`, what JSON fields were ambiguous, what error it could not act on without escalating, what it wished existed.
4. Feed those notes back into one more polish pass (Phase 4 → 6 → 7).
5. Re-run the cold prober. The notes must shrink. If they don't, file as P0 beads for the next pass.

**Subagent.** `subagents/cold-agent-prober.md` (must be a fresh subagent, NOT one that has seen this conversation).

**Exit criteria.**

- Cold prober's transcripts are captured for every canonical task.
- A polish pass was run in response to the notes.
- The next cold prober run produces fewer or different notes.
- `<workspace>/HANDOFF.md` is written with: queued beads, summary stats, and a note on what to try next pass.

---

## Termination Thresholds (Phase 4/5/6/7 loop exit)

The loop terminates when ALL of:

- Median per-failure-mode score uplift in the last pass is **< 25 points**.
- **No failure mode regressed** by more than 50 points (a regression > 50 is a **hard stop** — investigate before continuing).
- Phase 4 produced no new top-N detector/fixer that wasn't a near-duplicate of one already applied.
- Phase 7 fresh-eyes ran clean two times in a row (only trivial edits).
- The fixture suite from Phase 9 round-trips: corrupt → `--fix` → assert healthy → `undo` → byte-identical to corrupted, for every fixture.
- `scripts/validate-doctor.sh` exits 0.
- `scripts/diff-scorecards.py` reports no regression > 50 points.
