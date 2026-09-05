# Glossary

Terms used throughout this skill. Cite by name from any artifact.

---

**ACK** — An explicit acknowledgement in `regression_alerts.md` of a regression > 50 points. Format: `ACK: <reason>`. Without an ACK, `scripts/scorecard.py validate` exits non-zero for a regression block emitted by `diff-scorecards.py`.

**Action** — One call to `mutate()`. Each action gets one line in `actions.jsonl`.

**Aggregate score** — The doctor's per-failure-mode median, weighted by `frequency × blast_radius`, summed across all FMs. See [PRIORITY-FORMULA.md](../rubric/PRIORITY-FORMULA.md).

**Append-only** — A file or directory that doctor only adds to, never modifies in place. `actions.jsonl` and `scorecard_history.jsonl` are append-only. `.doctor/runs/<run-id>/` once created is immutable except for the symlink update at `.doctor/latest`.

**Archaeologist** — Phase 1 subagent that enumerates failure modes for one subsystem. See [../subagents/archaeologist.md](../../subagents/archaeologist.md).

**Audit-only mode** — Mode that runs Phases 0, 1, and 6 (scorecard) only — no code changes. Output is recommendations and a scorecard.

**Backup** — A verbatim, byte-identical copy of a file before mutation. Lives at `.doctor/runs/<run-id>/backups/<rel-path>`. Mode and mtime preserved.

**Baseline** — The pre-existing doctor's behavior captured into `<workspace>/baseline/` at the start of `upgrade` mode. Phase 6 scores against this baseline; regressions > 50 pts are hard-stops.

**Bead** — An issue in the project's `br` (beads_rust) tracker. Phase 4 implementers claim beads, work, close. See [BEADS-INTEGRATION.md](BEADS-INTEGRATION.md).

**Blast radius** — The maximum scope of a single fixer's writes. Disclosed in `--dry-run --fix` output. A subset of `capabilities --json::write_scopes`.

**Capabilities** — `<tool> doctor capabilities --json` — the reflective contract document. Lists detectors, fixers, exit codes, env vars, write scopes, schema URLs.

**Chokepoint** — `mutate(path, op)` — the ONLY function in the doctor module that touches disk under `--fix`. The validator (`scripts/validate-doctor.sh`) enforces single-chokepoint.

**Cold prober** — Phase 10 fresh-context subagent that uses the new doctor with no prior knowledge of the skill or workspace. See [../subagents/cold-agent-prober.md](../../subagents/cold-agent-prober.md).

**Conflict matrix** — `<workspace>/analysis/conflict_matrix.md` — pairs of fixers that MUST NEVER run in the same pass + why. Produced by Phase 3 synthesizer.

**Contract** — The agent-facing surface of the doctor: subcommand spelling, flag set, exit codes, JSON schemas, `--robot` envelope. Versioned independently of `tool_version` and `doctor_version` via `doctor_contract_version`.

**Corpus** — The body of evidence the skill operationalizes. See [CORPUS.md](CORPUS.md). Layers: AGENTS.md, /dp exemplars, cass findings, bug tracker, git log, adjacent skills.

**Dependency graph** — `<workspace>/analysis/dependency_graph.json` — DAG of "FM A's fix must precede FM B's fix." Validated by `scripts/validate-dag.py`.

**Detect-then-fix** — Axiom 1. The detector reads, the fixer mutates, never the reverse.

**Detector** — A pure function that examines state and returns `Finding | None`. Never calls `mutate()`.

**Doctor contract version** — Independent semver tracking the agent-facing contract. Major bumps for breaking changes (renamed flag, repurposed exit code, renamed JSON field).

**Doctor version** — The doctor implementation's own version. Minor bumps for new fixers; major for incompatible refactors.

**Drift** — Disagreement between two state surfaces (e.g., DB tombstone says X is deleted but JSONL still has X).

**Evidence** — Concrete proof in a finding's record: `file:line`, `query`, `hash`, `pid`, etc. Not generic prose.

**Failure mode (FM)** — A class of broken-state-on-disk an agent might encounter. NOT a single bug; a *kind* of corruption. Examples: `fm-state-files-jsonl-tombstone-drift`, `fm-schemas-db-version-mismatch`.

**Fast-path detector** — A detector with `tier: "quick"` that runs under `--quick` and `health`. Budget: < 5 ms each.

**Finding** — A concrete instance of a failure mode detected in a specific run. Has an FM ID, severity, evidence, and remediation.

**Fixer** — A function that mutates state via `mutate()` to remediate a finding. Routes EVERY write through the chokepoint.

**Fixture** — A reproducibly-broken state at `tests/doctor_fixtures/<fm-id>/`. Used for round-trip testing. Three files: `corrupt.sh`, `assert.sh`, `README.md`.

**Fresh-eyes** — Phase 7 multi-pass review using three calibrated prompts. Each round dispatches a fresh-context subagent. Loop terminates after two consecutive clean rounds.

**Idempotent** — Run twice = run once. After `--fix` succeeds, a second `--fix` reports `actions_taken: 0` and exits 0.

**`--json` mode** — Stable JSON output to stdout. Includes `schema_version`. Implies `--no-color`, `--no-progress`.

**Kernel** — The 17 universal axioms (Axioms 0–16) plus 7 stretch axioms (Axioms 17–23) in [KERNEL.md](KERNEL.md). Universal axioms apply to every doctor; stretch axioms are load-bearing at Stage 6+ ([GROWTH-LADDER.md](GROWTH-LADDER.md)). 24 axioms total.

**Manual remediation** — A finding with no auto-fixer; the user must act. Listed in `capabilities --json::manual_remediations` with the instruction (e.g., "set ANTHROPIC_API_KEY").

**Mega-command** — `<tool> doctor --robot-triage` — single call returning summary + findings + actions_planned + recommended_command + capabilities_url. Collapses 3 round-trips to 1. Full canonical schema (also `schema_version`, `quick_ref`, `robot_docs_command`) in [CLI-SURFACE.md](CLI-SURFACE.md).

**Meta-doctor** — Pattern 12: a doctor that validates *this skill itself*. Sketched in [META-DOCTOR.md](META-DOCTOR.md).

**Mode** — Operating mode at intake: `add | upgrade | audit-only | re-score-only | single-failure-mode-rescore | absorb-playbook`. See [OPERATING-MODES.md](OPERATING-MODES.md).

**`mutate()`** — The chokepoint. See [MUTATE-CHOKEPOINT.md](MUTATE-CHOKEPOINT.md).

**Negative-space spec** — The "things this doctor will NEVER do" section of `robot-docs`. Makes an agent willing to run unsupervised.

**Online detector** — A detector that requires network access. Marked `online_required: true` in capabilities. Skipped unless `--online`.

**Op** — One of seven canonical variants: `WriteFile | AppendFile | Rename | Chmod | DbExec | DbMigrate | SymlinkAtomic`. `Chown` is an optional 8th variant (see [MUTATE-CHOKEPOINT.md § The op enum](MUTATE-CHOKEPOINT.md)) that recipes may implement when needed; none of the 5 reference recipes do. NO `DeletePath` ever.

**Operator** — A cognitive move per [OPERATORS.md](OPERATORS.md). Composable; a single fixer typically deserves 4–5 operators.

**Pass** — One execution of the full skill phase loop. Pass 1, 2, 3 are sequential; each builds on the last.

**Phase** — One of the 10 phases in the loop: PROJECT ARCHAEOLOGY, REPAIR SPEC, SYNTHESIS, IMPLEMENTATION, SAFETY HARNESS, AGENT-ERGONOMIC SURFACE, FRESH EYES, INTEGRATION, FIXTURE SUITE, FINAL UX. See [PHASES.md](PHASES.md).

**Polish Bar** — The non-negotiable invariants every shipped doctor must satisfy. See [POLISH-BAR.md](POLISH-BAR.md).

**Priority** — `frequency × score_gap × blast_radius`. Ranks failure modes for implementer ordering. See [PRIORITY-FORMULA.md](../rubric/PRIORITY-FORMULA.md).

**Quarantine** — The fixer's "delete" semantics. `Op::Rename` moves a file to `<run-dir>/quarantine/<rel-path>`; the user reviews and decides on actual deletion. Retention cleanup is separate and gated by `doctor gc --before <date> --yes`.

**Quote** — A stable-ID excerpt from the corpus. Cited as `Q-NNN`. See [QUOTE-BANK.md](QUOTE-BANK.md).

**Read-only by default** — `<tool> doctor` (no flags) never mutates project state. `--fix` is opt-in.

**Repair spec** — `<workspace>/analysis/repair_specs/<fm-id>.md` — the specification for one fixer: detector pseudocode, fixer pseudocode, preconditions, invariants, backup spec, inverse, idempotence sketch, fixture spec.

**Reservation** — An Agent Mail file lock acquired before editing shared files. See [AGENT-MAIL-INTEGRATION.md](AGENT-MAIL-INTEGRATION.md).

**Reversibility** — Axiom 3. Every fix has an inverse. `<tool> doctor undo <run-id>` restores byte-for-byte.

**`--robot` mode** — `--json` plus the structured error wrapper (per Q-014). Standard envelope: `success, command, timestamp, data, error, suggestions, timing`.

**Robot-docs** — `<tool> doctor robot-docs` — paste-ready agent handbook.

**Round-trip** — Corrupt → fix → assert healthy → undo → cmp-strict against corrupted. The Phase 9 fixture gate.

**Run-artifact** — Files inside `.doctor/runs/<run-id>/`: `report.json`, `actions.jsonl`, `backups/`, `undo.sh`, `scorecard.json`, `report.md`, `stderr.log`.

**Run-id** — `sha256(target_sha + iso8601_utc_seconds)[..6]`. Deterministic up to the second.

**Scorecard** — Per-FM × per-dimension scores against the 10-dim rubric. Generated by `scripts/scorecard.py render`. Lives at `<workspace>/scorecard.md` and `failure_mode_scores.jsonl`.

**Severity** — P0 (corrupts state, loses data) | P1 (degrades correctness) | P2 (nuisance) | P3 (cosmetic). Maps to bead priority.

**Subsystem** — A partition of the project's state for archaeology. Standard: `state_files | configs | schemas | caches | sockets | hooks | plugins | secrets | permissions | external_artifacts | concurrency_primitives | network | userland_state`.

**Synthesizer** — Phase 3 single-agent that produces taxonomy, dependency_graph, conflict_matrix, safety_envelope, playbook narrative chapters.

**Trust manifest** — The bundled list of files an installer-pattern doctor verifies. Includes checksums + signatures + permissions per file. See [../recipes/installer.md](../recipes/installer.md).

**Validator** — A script in `scripts/validate-*` (or a `scorecard.py validate` subcommand) that turns judgment into a CI gate. `validate-doctor.sh`, `validate-fm.py`, `validate-spec.py`, `validate-dag.py`, `validate-skill.sh` (meta-doctor), `scorecard.py validate <workspace>` (rejects >=700 scores lacking evidence and unacked regression blocks emitted by `diff-scorecards.py`).

**Worktree** — A `git worktree add` checkout sharing the parent's `.git`. Default operating location for code changes during a pass: `<workspace>/worktree/` on branch `doctor-mode-pass-<N>`.

**Write scope** — A path the doctor MAY write to. Listed in `capabilities --json::write_scopes`. Out-of-scope writes refuse with exit 4.
