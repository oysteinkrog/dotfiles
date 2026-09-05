# Intake Prompt — Verbatim Template

> The orchestrator emits this *verbatim* at the start of every gauntlet invocation, BEFORE any toolchain action. The user's answers populate `<workspace>/phase0_intake.json`.

---

I'm about to run the gauntlet on your Rust port. To do this correctly I need 7 decisions from you up front. The pipeline is mode-aware — wrong answers here cascade into days of wasted compute on the wrong workload.

1. **Target port path?**
   - Local path? Confirm the absolute path (e.g. `/data/projects/frankensqlite`).
   - Or a git URL — I'll clone into `/tmp/<basename>/` and operate on the worktree.
   - Default: current working directory.

2. **Workspace directory?**
   - Default: `<basename>__gauntlet_workspace/` as a sibling of the target port.
   - I will create it and `git init` it (the workspace is version-controlled separately so every experiment, reproducer, interim finding, and minimized failure bundle is recoverable).
   - If it already exists I will offer to *resume at the next pending round* rather than redo work. Confirm OK?

3. **Project class?** I auto-detect via `scripts/detect-project-class.sh`. The classes are:
   - **SQL-class** — frankensqlite, sqlmodel_rust → in-process `rusqlite` oracle.
   - **RESP-class** — frankenredis → vendored `redis-server` via UNIX socket.
   - **Numerical-Python-class** — franken_numpy, frankenpandas, frankenscipy, franken_networkx → PyO3 in-process bridge with bit-exact PCG64DXSM RNG parity.
   - **ML-System-class** — frankentorch, frankenjax, franken_whisper → PyO3 + `torch.use_deterministic_algorithms(True)` + per-op ULP tolerance table.
   - **HTTP-Protocol-class** — fastapi_rust, fastmcp_rust → compliance fixture corpus + reference framework + OpenAPI schema diff.

   Confirm the detected class, or override.

4. **Reference version to pin?**
   - e.g. `sqlite-3.52.0`, `redis-7.2.5`, `torch-2.X.Y`, `numpy-1.26.0`.
   - This is recorded in `docs/contracts/<reference>_version_contract.toml`. Every artifact in the run embeds the contract hash so a stale-oracle drift is caught by `oracle-preflight-doctor.sh`.

5. **Local vs `rch`-offloaded heavy passes?**
   - The full `comprehensive-bench` matrix (93+ scenarios), multi-day Miri runs, fuzz / loom / shuttle / crash-boundary / BOCPD soaks all exceed 5 min wall-time. I strongly recommend dispatching them to `rch` workers (`rch exec --`).
   - Confirm `rch` is configured (`rch status` returns green), or accept local execution with the long-wall-time cost.

6. **Fresh run, incremental rebase, or resume?**
   - **Fresh** — start at Phase 0.
   - **Incremental** — the port's main branch moved; re-run only the affected phases (auto-detected from `git diff` against the workspace's last-known-good ref).
   - **Resume** — workspace exists and the last run was interrupted; pick up at the first pending round.

7. **Final-artifact tier?**
   - **Internal-only** — gauntlet runs but no certification template emitted.
   - **Public-release** — `FINAL_GAUNTLET_REPORT.md` + `PARITY_RUNBOOK.md` emitted.
   - **Certification-bundle** — strict-conformant-release.v1 evidence pack with all four required-pass constants checked (`CERTIFICATION_MIN_VERIFICATION_PCT = 100.0`, `CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT = 100.0`, `CERTIFICATION_MAX_HIGH_SEVERITY_COUNTEREXAMPLES = 0`, `CERTIFICATION_MAX_EVIDENCE_AGE_HOURS = 24`).

After your answers I will:
- Offer to `jsm install` any missing public helper skills (`/profiling-software-performance`, `/extreme-software-optimization`, `/testing-metamorphic`, `/testing-fuzzing`, `/testing-conformance-harnesses`, `/testing-golden-artifacts`, `/multi-pass-bug-hunting`, `/deadlock-finder-and-fixer`, `/lean-formal-feedback-loop`, `/multi-agent-swarm-workflow`, `/agent-fungibility-philosophy`, `/flywheel`, `/idea-wizard`, `/beads-workflow`, `/cass`, `/agent-mail`, `/ubs`, `/dcg`, `/rch`) — non-blocking; the pipeline ships inline fallbacks.
- Run `scripts/install-toolchain.sh` (asks permission before any install).
- Write `phase0_workspace_init.md` + the four contract files.
- Begin Phase 1 (RECON) with per-crate parallel `surface-archaeologist` subagents.

Convergence requires **a minimum of 10 full rounds** of Phases 5–10, with two consecutive clean rounds (<3 new genuine findings each) AND every open hypothesis resolved. This is not a one-pass evaluation. Plan accordingly.

Please answer the 7 questions, then I'll proceed.
