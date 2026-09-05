# Skill Bootstrap (Phase 0.5)

Detailed Phase 0.5 playbook: how the gauntlet's first 30 minutes set up the toolchain, workspace, project class, helper-skill inventory, and oracle preflight check — all idempotent, all with green/yellow/red verdicts, and all running before any test or bench fires.

The five scripts called from `SKILL.md`'s Bootstrap section, in order:

1. `scripts/install-toolchain.sh`
2. `scripts/init-workspace.sh`
3. `scripts/detect-project-class.sh`
4. `scripts/check-skills.sh`
5. `scripts/oracle-preflight-doctor.sh`

This file expands each into the moves an orchestrator (and any drop-in subagent during a resume) needs to execute. A botched bootstrap silently corrupts every later phase, so the per-tool verdicts are the gate.

---

## Required Helper Skills (full list)

Each helper skill has a one-line purpose. The skill is "missing" if `check-skills.sh` does not find it in `~/.claude/skills`, `~/.codex/skills`, or `~/.gemini/skills`. `jsm list` marks whether a missing skill is installable, but does not by itself make the skill available to the current agent.

| Skill | One-line purpose |
|---|---|
| `/operationalizing-expertise` | Distill a methodology into corpus + quote bank + triangulated kernel + operator library + validators. Used for Phase 0 quote-bank construction. |
| `/codebase-archaeology` | Per-crate / per-module surface inventory; primary tool for Phase 1. |
| `/codebase-report` | Compose surface-archaeology results into a routing report. |
| `/profiling-software-performance` | Build profile-first contract; produce ranked hotspot tables; primary tool for Phase 5. |
| `/extreme-software-optimization` | The keep-gate / ratchet / negative-ledger doctrine. The methodological backbone of Phase 5 + 11. |
| Advanced mathematical tool compilation | Turn frontier-math into implementable software artifacts. Built into Phase 10. |
| Advanced systems-method mining | Apply public systems techniques to the project. Built into Phase 10. |
| `/testing-metamorphic` | TransformFamily / EquivalenceExpectation / MismatchClassification. Powers Phase 6 metamorphic harness. |
| `/testing-fuzzing` | cargo-fuzz + AFL + arbitrary + bolero. Powers Phase 6 fuzz. |
| `/testing-conformance-harnesses` | Differential V2 + oracle E2E harness construction. Powers Phase 6. |
| `/testing-golden-artifacts` | Three-tier equivalence + insta. Powers Phase 4. |
| `/testing-real-service-e2e-no-mocks` | Real-DB / real-RPC harness patterns. Powers Phase 6 cross-process tests. |
| `/multi-pass-bug-hunting` | Audit-fix-rescan cycle. Powers Phase 14 fresh-eyes. |
| `/deadlock-finder-and-fixer` | "There is almost always a fourth instance." Powers Phase 15 loom/shuttle. |
| `/lean-formal-feedback-loop` | "Treat proof friction as evidence." For projects with Lean/Coq invariants. |
| `/multi-agent-swarm-workflow` | Squad/Swarm orchestration; powers Phase 11+15. |
| `/agent-fungibility-philosophy` | "Every agent is fungible and a generalist." Used for cc_N lane assignment. |
| `/flywheel` | Extract generative grammar from session history; powers Phase 10 idea-wizard mining. |
| `/idea-wizard` | 30→5 idea distillation. Phase 10 driver. |
| `/beads-workflow` | Plan→beads conversion + polish loop. Phase 13. |
| `/cass` | Session-history search. Phase 8 (60-day mining) + every perf-bead pre-flight. |
| `/agent-mail` | Cross-agent thread coordination (the MCP). |
| `/ubs` | Ultimate Bug Scanner. Phase 14 + final review. |
| `/dcg` | Destructive-command guardrails. Always-on safety. |
| `/rch` | Remote-build offload. Powers any >5 min compute. |

---

## `jsm install <name>` Flow

When `jsm` (jeffreys-skills.md CLI) is installed and authenticated, missing skills install in seconds.

### Subscription check

```bash
jsm whoami 2>&1
```

- If output contains `Subscription: active (tier=paid)` → proceed with `jsm install`.
- If output contains `Subscription: trial` or `inactive` → warn, fall back to inline mode for paid skills.
- If `jsm` is not on PATH → fall back entirely to inline mode (no install; pipeline still works).

### Headless OAuth (if needed)

```bash
jsm auth status || jsm auth headless
```

`jsm auth headless` opens a one-time URL the user pastes a code back into. Idempotent: subsequent runs no-op if a valid token exists.

### Install loop

```bash
# Read the helper list from the Phase 0 inventory.
./scripts/check-skills.sh "$WORKSPACE" || true
MISSING_SKILLS=$(jq -r '.skills[] | select(.available == false) | .name' "$WORKSPACE/phase0_skill_inventory.json")
for skill in $MISSING_SKILLS; do
  jsm install "$skill" --no-prompt --non-blocking || echo "WARN: $skill install failed; using inline fallback"
done
```

**Non-blocking offer:** the orchestrator never blocks on `jsm install`. The install runs in the background while Phase 0 continues; if a needed skill isn't ready by the time its phase fires, the inline fallback kicks in.

### Inline fallback (when jsm missing)

Every helper-skill reference in this gauntlet skill has an inline fallback in [`methodology/SKILL-FALLBACKS.md`](../methodology/SKILL-FALLBACKS.md). The orchestrator uses those sections when the named skill is not installed. The pipeline degrades gracefully; per-phase quality drops modestly because the inline prompts lack the full helper-skill's tooling but maintain the core workflow.

---

## `scripts/install-toolchain.sh` Flow

Verify + install the Rust toolchain + bench/fuzz/sanitizer/analysis tools. Idempotent. Per-tool green/yellow/red verdict.

### Tools installed/verified

| Category | Tools |
|---|---|
| **Rust core** | `rustup`, `cargo`, `rustc` nightly + components: `rust-src`, `miri`, `rustfmt`, `clippy`, `llvm-tools-preview` |
| **Bench** | `cargo-criterion`, `hyperfine`, `cargo-flamegraph`, `samply`, `cargo-show-asm`, `dhat`, `heaptrack` |
| **Fuzz** | `cargo-fuzz`, `cargo-afl`, `bolero`, `arbitrary` (via cargo add as needed) |
| **Sanitizer** | `cargo-llvm-cov`; ASan/TSan/MSan/LSan flags wired via `RUSTFLAGS` (no install, just env) |
| **Static analysis** | `ast-grep`, `semgrep`, `cargo-geiger`, `cargo-audit`, `cargo-deny`, `cargo-expand` |
| **Concurrency** | `loom`, `shuttle` (cargo add to harness crate) |
| **Snapshots** | `cargo-insta` |
| **System** | `strace`, `perf`, `fio` (sudo install warning if missing) |

### Verdict format

```
[install-toolchain] rustup           GREEN  (1.27.1)
[install-toolchain] cargo            GREEN  (1.83.0-nightly)
[install-toolchain] miri             GREEN  (rustc 1.83.0-nightly)
[install-toolchain] cargo-criterion  YELLOW (installed; --version check failed; investigate)
[install-toolchain] hyperfine        GREEN  (1.18.0)
[install-toolchain] cargo-flamegraph GREEN  (0.6.5)
[install-toolchain] samply           RED    (not found; `cargo install samply` failed; permissions issue?)
[install-toolchain] strace           GREEN  (5.16)
...
```

**Verdict rules:**
- **GREEN:** installed AND version meets minimum.
- **YELLOW:** installed but version unknown or below recommended; pipeline can proceed but skill fidelity reduced.
- **RED:** missing and install attempt failed; **blocks** any phase that depends on this tool.

### Idempotence

Re-running the script is safe: each tool check uses `which <tool>` + `<tool> --version`; install commands are guarded by `command -v <tool> >/dev/null || cargo install <tool>`.

Output: `<workspace>/phase0_toolchain_inventory.json` + console summary.

---

## `scripts/init-workspace.sh` Flow

Create the workspace directory; initialize git; drop the AGENTS.md mandate paragraph; seed the three negative-evidence ledgers; write the version-contract skeleton.

### Inputs
- `<target>` — absolute path to the Rust port being audited.
- `<workspace>` — absolute path to the gauntlet workspace (default: sibling of target named `<basename>__gauntlet_workspace`).

### Operations (each idempotent)

1. `mkdir -p <workspace>` (no-op if exists; warn if non-empty).
2. `cd <workspace> && git init` (no-op if `.git` exists).
3. `cp assets/agents-md-mandate-paragraph.md <workspace>/AGENTS.md` — this is the gauntlet workspace's local operating rule file. The orchestrator does not modify the target's files automatically; it surfaces the paragraph for the user to land in the target if desired.
4. **Seed the three negative-evidence ledgers** at workspace root and mirror them into `docs/progress/`:
   - `PERF_NEGATIVE_RESULTS.md`
   - `CONFORMANCE_NEGATIVE_RESULTS.md`
   - `SURFACE_DEFERRALS.md`
   - `docs/progress/perf-negative-results.md`
   - `docs/progress/conformance-negative-results.md`
   - `docs/progress/surface-deferrals.md`
   Each seeded with the verbatim header from MINING-1 §3 and one example entry from the retry-condition vocabulary.
5. **Write the `<reference>_version_contract.toml` skeleton** in `<workspace>/docs/contracts/`. Filled by Phase 2 (Reference Pinning + Surface Contract).
6. Copy a pinned snapshot of this skill's `scripts/` directory into `<workspace>/scripts/` so later resumes use the same helper implementation even if the installed skill changes.

The workspace is `git init`-ed here, but the script does not auto-commit. The orchestrator makes the first commit after `install-toolchain.sh`, `detect-project-class.sh`, `check-skills.sh`, and `oracle-preflight-doctor.sh` have written their Phase 0 reports.

### AGENTS.md mandate paragraph (verbatim from MINING-1 §3 / CODEX.md §10.2 lines 1464-1472)

```
For major perf campaigns, agents must also mine:
- last 60 days of CASS session history
- recent commits
- perf artifacts
- failed/rejected/slower/regressed terms

If CASS or the ledger is unavailable or reserved, the agent must record a
blocker or patch-ready entry rather than silently skipping the step.

This ledger records performance ideas that were measured and rejected.
Check it before starting a new optimization pass, and add an entry whenever
a candidate is abandoned, reverted, or kept out of the tree because the
benchmark matrix did not move in the intended direction.
```

(Drop into the target's `AGENTS.md`; the workspace also keeps a copy at `AGENTS_MANDATE_FOR_TARGET.md` for reference.)

---

## `scripts/detect-project-class.sh` Flow

Auto-detect the project class. Heuristics walk `Cargo.toml` files in the target.

### Heuristics

| Class | Detection signal |
|---|---|
| **SQL-class** | `Cargo.toml` deps include `libsqlite3-sys`, `rusqlite`, or `sqlparser`; presence of `*.sql` fixtures; `Opcode` enum in source. |
| **RESP-class** | Deps include `redis`, `redis-rs`, `redis-protocol`, `fr-conformance`; presence of `RESP`/`resp_protocol` modules. |
| **Numerical-Python-class** | Deps include `pyo3` + (`numpy` PyPI binding OR `ndarray` crate); presence of `dtype` / `broadcast` modules. |
| **ML-System-class** | Deps include `pyo3` + (`tch`, `torch-sys`, OR `jax-sys`); presence of `autograd` / `kernel_launch` modules. |
| **HTTP-Protocol-class** | Deps include `axum`, `actix-web`, `hyper`, `http`, `tower`; presence of `route` / `middleware` modules. |

### Output

`<workspace>/phase0_project_class.json`:

```json
{
  "schema_version": "gauntlet.phase0_project_class.v1",
  "generated_at": "2026-05-23T00:00:00Z",
  "target": "/data/projects/frankensqlite",
  "detected_class": "SQL-class",
  "confidence": 1.0,
  "matching_reference": "sqlite",
  "sibling_project_example": "frankensqlite",
  "scores": {
    "SQL-class": 5,
    "RESP-class": 0,
    "Numerical-Python-class": 0,
    "ML-System-class": 0,
    "HTTP-Protocol-class": 0
  }
}
```

If `confidence < 0.8` or two classes have similar signal strength, `detect-project-class.sh` exits 1. The orchestrator treats that as yellow, asks the user to confirm the class, and records the confirmed class in `phase0_intake.json.project_class_confirmed`.

---

## `scripts/check-skills.sh` Flow

Inventory the helper skills (from the list above). Write `<workspace>/phase0_skill_inventory.json`.

### Sources checked, in order

1. `jsm list` (if `jsm` on PATH and authenticated)
2. `~/.claude/skills/<name>/SKILL.md` (per-skill folder)
3. `~/.codex/skills/<name>/SKILL.md` (Codex skill location)
4. `~/.gemini/skills/<name>/SKILL.md` (Gemini skill location)

### Output

```json
{
  "schema_version": "gauntlet.phase0_skill_inventory.v1",
  "generated_at": "2026-05-23T00:00:00Z",
  "jsm_available": true,
  "missing_count": 2,
  "skills": [
    {"name":"operationalizing-expertise","claude":true,"codex":true,"gemini":false,"jsm_installable":false,"available":true},
    {"name":"idea-wizard","claude":false,"codex":false,"gemini":false,"jsm_installable":true,"available":false}
  ]
}
```

The orchestrator derives the missing list with:

```bash
jq -r '.skills[] | select(.available == false) | .name' "$WORKSPACE/phase0_skill_inventory.json"
```

Then it offers a non-blocking `jsm install <skill>` for any missing skill whose `jsm_installable` flag is true.

---

## `scripts/oracle-preflight-doctor.sh` Flow

Pre-Phase-3 sanity check on the reference oracle. **Exits non-zero if oracle is unsafe to compare against.**

### Checks

| Check | What it verifies |
|---|---|
| **Reference binary path** | `which sqlite3` (or `redis-server`, `python -c "import torch"`, etc.) resolves; binary is executable. |
| **Reference version** | Output of `<binary> --version` matches `docs/contracts/<reference>_version_contract.toml`. |
| **Subject identity** | `EngineIdentity::Subject` in source resolves to the port's identity string (`frankensqlite`, not `csqlite-oracle`). |
| **Reference identity** | `EngineIdentity::Oracle` resolves to the reference's identity string. |
| **Fixture corpus cardinality** | Per-category cardinality floors met (from `fixture_root_contract.rs`). |
| **Fixture manifest mtime** | Fresh enough (within last 30 days; tunable). |
| **Manifest SHA-256** | Matches the contract; rejects silently-modified corpora. |

### Output

```json
{
  "schema_version": "oracle-preflight-doctor.v1",
  "bead_id": null,
  "run_id": "phase0-r17-1748131245-12345",
  "trace_id": "auto-generated",
  "scenario_id": "preflight",
  "seed": 1748131245,
  "generated_timestamp": "2026-05-22T13:00:45Z",
  "aggregate_outcome": "green",
  "certifying": true,
  "first_failure_diagnosis": null,
  "fixture_ingestion_counters": {"null_semantics": 47, "groupby_having": 31, ...},
  "resolved_oracle_binary_path": "/usr/local/bin/sqlite3",
  "resolved_oracle_version": "3.52.0",
  "fixture_manifest_mtime": "2026-05-15T08:23:11Z",
  "fixture_manifest_sha256": "9a17...",
  "deterministic_replay_command": "./scripts/oracle-preflight-doctor.sh <target> --workspace <workspace>",
  "remediation_class": null,
  "fix_command": null
}
```

**`certifying: true` ONLY when `aggregate_outcome: green`.** Yellow = pipeline can proceed only with an explicit waiver; red = pipeline aborts at this step.

### Per-class adaptations (from MINING-2 §13)

- **SQL:** `sqlite3` binary, version, identity strings, fixture cardinality.
- **RESP:** Server version, protocol mode (RESP2/RESP3), persistence (RDB/AOF on/off), module set, cluster mode.
- **Numerical:** NumPy version, SIMD flags (SSE/AVX/AVX-512 advertised), RNG state policy (default seed for repro), BLAS thread count.
- **ML (Torch):** PyTorch version, CUDA version, cuDNN version, driver version, determinism flags (`torch.use_deterministic_algorithms(True)`), dtype policy, RNG seed policy, model corpus hashes.

---

## Resuming a Prior Run

The orchestrator may be re-instantiated mid-run (compaction, model swap, host restart). The Phase 0.5 scripts are designed for re-entry.

### Detection

1. If `<workspace>/.git` exists with commit history → existing run.
2. Read `<workspace>/phase0_*.json` files (toolchain report, project class, skill inventory).
3. Read latest round number from `<workspace>/tests/artifacts/round-*/` directories.
4. Read four hypothesis ledgers; count open + `NEEDS_REFINEMENT` + `NEW_HYPOTHESIS_SPAWNED` entries.

### Offer

"Found existing gauntlet workspace at round N with M open hypotheses. Resume at next pending sub-phase, or start fresh? `[resume|fresh|abort]`"

### Idempotency contract

Every Phase-0.5 script:
- Reads existing state if present.
- Never overwrites without explicit `--force`.
- Adds new lines / new entries; does not rewrite existing ones.
- Reports "skipped (already done)" when re-running a completed step.

### Resume entry point

`./scripts/gauntlet-status.sh <workspace> --json` outputs:
- Current round number
- Open hypothesis count per pillar
- Next subagent to dispatch (per phase + lane)
- Pending reservations to release (TTL expired)
- Any blocker tags from the latest round

---

## See Also

- [ORCHESTRATION.md](ORCHESTRATION.md) — lane assignment, thread IDs, reservations, rch heuristic
- [BEADS-HANDOFF.md](BEADS-HANDOFF.md) — plan-to-beads conversion + polish loop
- [../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md) — hypothesis-ledger template
