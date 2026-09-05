# scripts/ — What's actually here

The gauntlet skill is a **methodology document with a provided helper library**. The 34 scripts in this directory are the actual, runnable, opinionated helpers. Many *additional* script paths get cited in cookbook recipes, methodology docs, and subagent prompts — those are **per-project pseudocode showing intent**; adopters implement them per their project shape (or inline the operations).

## Provided scripts (run these)

The 34 scripts below are real, tested, idempotent, and intended for direct invocation.

### Bootstrap

| Script | Purpose |
|---|---|
| `install-toolchain.sh` | Verify + install Rust + bench + fuzz + sanitizer + analysis toolchain; idempotent; emits a per-tool green/yellow/red report. |
| `init-workspace.sh` | Create `<project>__gauntlet_workspace/`; `git init`; drop AGENTS.md mandate paragraph; seed the three negative-result ledgers; write the version-contract skeleton. |
| `check-skills.sh` | Audit which helper skills are installed; print missing-skill list with `jsm install` suggestions. |
| `detect-project-class.sh` | Heuristically classify the target as SQL / RESP / Numerical-Python / ML-System / HTTP-Protocol / Greenfield. |
| `kickoff.sh <mode>` | Print the verbatim mode-specific kickoff prompt for the orchestrator (extracted from `references/methodology/KICKOFF-PROMPTS.md`). Pipe to your dispatcher (e.g., `ntm send`) or paste into an Agent prompt. Modes: `gauntlet-full | gauntlet-greenfield | audit-only | harden-pillar | add-feature | incremental-rebase | compliance-pass | red-team | migration | cass-mine-only | quick-smoke`. |
| `gauntlet.sh` | Top-level orchestrator entry point; dispatches the selected phase/subagent sequence and drives `reports/convergence_tracker.json` through `convergence-tracker.sh`. |
| `dispatch-subagent.sh` | Best-effort subagent dispatch wrapper; dry-run by default, with NTM / inline / rch handoff modes. |
| `gauntlet-status.sh` | Terminal-native dashboard snapshot of a gauntlet workspace. |

### Per-phase helpers

| Script | Phase | Purpose |
|---|---|---|
| `oracle-preflight-doctor.sh` | Phase 3 + every phase entry | Verifies reference binary, version, identity strings, fixture corpus sanity; emits green/yellow/red. |
| `run-bench-matrix.sh` | Phase 5 / 9 / 11 | Runs `comprehensive-bench` against subject + reference; emits JSON v3 + scorecard + `.bench-history/`. |
| `run-narrow-benches.sh` | Phase 5 / 9 / 11 | Runs every focused per-workload bench in sequence; captures flamegraphs + samply + dhat + strace. |
| `run-conformance-suite.sh` | Phase 6 / 9 / 11 | Runs every oracle E2E + differential V2 + metamorphic + property + fuzz harness; dedups by MismatchSignature. |
| `run-fault-injection-matrix.sh` | Phase 6 / 15 | Exercises every named fault profile + crash boundary; asserts post-recovery consistency. |
| `compute-feature-coverage.sh` | Phase 7 / 9 / 11 | Emits per-family dashboard verdict + raw coverage JSON. |
| `compute-parity-score.sh` | Phase 9 / 11 / CI | Reads scorecards; applies category weights; runs Beta-posterior + conformal-band math; emits truncate_score'd output. |
| `apply-ratchet.sh` | Phase 9 / 11 / CI | Compares current lower bound to `reports/ratchet_state.json`; emits `Allow | Block | Quarantine | Waiver`. |
| `update-ratchet-state.sh` | Phase 9 / 11 / CI | Explicit score-artifact entrypoint around `apply-ratchet.sh <workspace> --score <score-artifact>`. |
| `mine-ledger.sh` | Pre-perf-work / Phase 8 | Greps the negative-ledger + 60-day cass for failure terms; produces a candidate-blocker report. Supports `--lint <ledger.md>` for retry-condition predicate validation. |
| `mine-cass-cross-machine.sh` | Phase 0.5 / Pre-perf-work | Invokes cass on local + css + csd + ts1 + ts2; aggregates session-history hits. |
| `convergence-tracker.sh` | Phase 11 round close | Computes round-over-round new-finding counts; exits non-zero until convergence reached. CI gate-able. |
| `bead-graph-validator.sh` | Phase 13 | Runs `br dep cycles` + null-safe `bv --robot-insights` cycle checks against a repo/workspace with `.beads/`; asserts every remediation bead has the 3 required deps. Use `--output-root <workspace>` when validating `<target>/.beads` from a copied workspace script. |
| `final-report-builder.sh` | Phase 16 | Collates `phase16_*` markdown into `FINAL_GAUNTLET_REPORT.md` + builds certification-bundle directory. |
| `run-fresh-eyes-pass.sh` | Phase 14 | Driver for the 3 verbatim fresh-eyes prompts a/b/c. |
| `run-soak-campaign.sh` | Phase 15 | Dispatches long-running fuzz / miri / loom / shuttle / crash-boundary / BOCPD / e-process campaigns to rch. |
| `replay-failure.sh` | post-failure | Replays a FailureBundle deterministically given its `seed + fixture_id + schedule_fingerprint + repro_command`. |

### Per-project-class helpers

| Script | Class | Purpose |
|---|---|---|
| `run-tcl-tests.sh` | SQL-class | Lifts the TCL test suite as a regression corpus; year-sweep across 2026/2025/2024/2023 for SQLite source URLs. |
| `run-numpy-all-check.sh` | Numerical-Python-class | Validates `numpy.__all__` 100% reachability via PyO3 bridge. |
| `gradcheck.sh` | ML-System-class | Drives gradient-check across the test suite (Torch / JAX style). |
| `verify-resp-protocol.sh` | RESP-class | Validates RESP3 frame compliance against the reference `redis-server`. |
| `openapi-schema-diff.sh` | HTTP-Protocol-class | Canonicalizes + diffs OpenAPI schemas between subject + reference. |
| `compute-mismatch-signature.sh` | any class | Computes the `MismatchSignature` content-hash for dedup. |
| `extract-from-bibles.sh` | meta | Extracts the routed FrankenSQLite bible excerpts by current section headers and fails if any excerpt is empty. |

### Surface inventory

| Path | Purpose |
|---|---|
| `ast-grep-surface-patterns/` | YAML patterns for ast-grep; one per surface construct (no-mangle-fn, macro-export, etc.). |
| `syn-walkers/` | Rust source-walker Cargo crate with 4 walker binaries for detecting what ast-grep can't (e.g., public-API drift from reference's `__all__`). |

### Validation

| Script | Purpose |
|---|---|
| `validate-skill.py` | Self-contained structural validator for the public skill copy. |
| `check-cross-links.py` | Checks markdown cross-links inside the skill package or a selected file set. |

---

## Cited-but-not-provided scripts

Many cookbook recipes, methodology docs, and subagent prompts reference scripts that are NOT in this directory — they are **pseudocode showing intent**. Examples:

```bash
# From cookbook/spec-conflict-detected.md:
./scripts/detect-spec-conflicts.sh "$WORKSPACE"

# From methodology/HOOKS-INTEGRATION.md:
./scripts/install-gauntlet-hooks.sh "$WORKSPACE"   # project-specific hook installer
```

These scripts are **NOT provided** in this directory. The cookbook/methodology files describe what they would do; the operator implements per their project shape — usually by gluing together the core helpers above with project-specific glue.

### Why not provide them all?

Three reasons:
1. **Per-project shape:** `dispatch-subagent.sh` looks different per project (different MCP backend, different subagent invocation convention). Hardcoding one would be wrong for most adopters.
2. **Operator preference:** some operators prefer `make` targets; others prefer `just`; others prefer raw shell. The cookbook describes the *operation*; the operator implements per their tool preference.
3. **Methodology evolution:** the gauntlet's methodology evolves faster than its scripts can. The cited script names are the **canonical operation names**; whether they're shell / Python / Rust binaries / inline calls is an implementation detail.

### What this means for an agent reading the skill

When you encounter `./scripts/<name>.sh` in a cookbook recipe or methodology doc:

1. **First check `ls scripts/`** to see if it actually exists.
2. **If it does:** invoke it.
3. **If it does NOT:** the surrounding markdown describes the operation in enough detail that you can either:
   - Inline the operation (it's usually 5-20 lines of shell).
   - Author the script per your project's conventions and check it in.
   - Compose existing helpers (most "missing" scripts are wrappers around 2-3 provided ones).

### What an adopter should do

When adopting the gauntlet on a real project, populate `scripts/` with the project-specific variants of the cited-but-missing scripts. Most adopters end up with 60-80 scripts total (the 34 provided + 25-45 project-specific). The provided helpers are the **foundation**; the project-specific scripts are the **shape**.

---

## Calling conventions

- Most provided scripts follow these conventions; always check `scripts/<name> --help` before invoking a helper in automation:

- **Target/project arguments:** phase runners usually take target project path first, then gauntlet workspace path.
- **Workspace-only helpers:** `check-skills.sh`, `compute-feature-coverage.sh`, `compute-parity-score.sh`, `apply-ratchet.sh`, `convergence-tracker.sh`, `final-report-builder.sh`, and `gauntlet-status.sh` take the workspace as their primary argument.
- **Bead graph validator:** `bead-graph-validator.sh` takes the repo/workspace containing `.beads/` as its first argument. For the normal Phase-13 target graph, use `bead-graph-validator.sh <target> --output-root <workspace>` so reports land in the gauntlet workspace.
- **Flag-only bootstrap helpers:** `install-toolchain.sh` takes `--workspace <dir>` rather than a positional target.
- **Output:** JSON to stdout (machine-readable) OR markdown to a file under `<workspace>/`.
- **Exit codes:** `0` = success; `1` = soft failure (continue); `2` = hard failure (halt); `> 2` = preflight failure (e.g., missing dependency).
- **Idempotent:** safe to re-run; second invocation may exit faster with "already done" message.
- **Read-only by default:** scripts that mutate target source say so in their `--help` and require `--allow-target-writes`; validators should write reports to `<workspace>/` via `--output-root` when they inspect `<target>/`.

Adopters' scripts SHOULD follow the same conventions so the gauntlet's orchestrators can dispatch any of them uniformly.
