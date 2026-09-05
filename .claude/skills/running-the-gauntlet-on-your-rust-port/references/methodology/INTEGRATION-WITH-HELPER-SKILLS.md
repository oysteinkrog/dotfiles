# Integration With Helper Skills

How the gauntlet composes with every referenced helper skill. Each entry: when the gauntlet calls in, what data is passed, what comes back, what gates the fallback.

## Skill-writing guidance

**When the gauntlet calls in:** never at runtime. General skill-writing guidance is used to author this skill and to author per-port project-specific skill extensions like `gauntlet-frankensqlite-extensions`.

**Fallback if missing:** N/A; the skill is already authored.

## Corpus-to-skill extraction guidance

**When:** when a port-specific extension skill needs to be authored (e.g., a `gauntlet-frankensqlite-mvcc-extensions` skill encoding the project's specific MVCC invariants).

**Fallback:** the orchestrator inlines the "research + distill + create" workflow (cass mining → draft → polish) per `methodology/SKILL-FALLBACKS.md`.

## /operationalizing-expertise — Track A artifact set

**When:** the gauntlet IS a Track A artifact. The `methodology/SOURCE-CORPUS.md` documents how this skill maps to corpus + quote-bank + kernel + operator library + validators.

**Reused in runtime:** `subagents/cookbook-author.md` uses the Track A "operator library + composition cheat-sheet" pattern.

## /codebase-archaeology + /codebase-report

**When:** Phase 1 RECON dispatches one `surface-archaeologist` instance per crate; each is essentially a parameterized codebase-archaeology run with the three pillars as lenses.

**What's passed:** `<port>/crates/<crate-name>/` path.

**What comes back:** `<workspace>/phase1_recon_<crate>.md` per the schema in `methodology/PHASE-OUTPUT-SCHEMAS.md § Phase 1`.

**Fallback:** the agent inlines: read every `pub fn` / `pub struct` / `impl ... for ...` / `#[no_mangle]` / `extern "C"` / macro-expanded surface; map each to reference impl; emit the markdown by hand.

## /profiling-software-performance

**When:** Phase 5 (initial harness build) AND Phase 9 (baseline) AND Phase 11 (per-round). The `mt8-attribution-profiler` subagent IS the profiling-software-performance entry point.

**Rule it enforces (from skill):** "Ranked evidence before any optimization. No hotspot list → no change."

**Fallback:** the agent uses `samply record` + `cargo flamegraph` + `dhat-rs` per `tooling/BENCH-TOOLCHAIN.md` directly.

## /extreme-software-optimization

**When:** Phase 12 REMEDIATION DESIGN for every perf candidate. The skill's `Impact × Confidence / Effort ≥ 2.0` gate is the perf-pillar additional gate in `methodology/RUBRICS.md`.

**Rule (from skill):** "Profile first. Prove behavior unchanged. One change at a time."

**Fallback:** the rubric in `methodology/RUBRICS.md` is fully inlined — the orchestrator can score candidates without /extreme-software-optimization installed.

## Advanced mathematical tool compilation

**When:** Phase 10 IDEA-WIZARD ROUND. The `advanced-methods-miner` subagent runs the "TRULY think even harder" prompt to surface advanced-math compilations (Ville, Azuma, Vovk, Lai-Robbins, McAllester PAC-Bayes) for the specific port's failure signature.

**Fallback:** the orchestrator inlines a manual round of: read `references/math/*` for the math toolkit; read the port's negative ledger; ask "which of these frontier results matches the residual gap shape?"

## Advanced systems-method mining

**When:** Phase 10. Same subagent (`advanced-methods-miner`); the orchestrator mines a broad public systems-technique catalog.

**Fallback:** for SQL-class, the CC.md PART XVI math toolkit (32 rows) is the closest in-skill substitute (lifted into `references/exemplars/QUOTE-BANK.md § §6 — Mathematical machinery` quote bank entries).

## /testing-metamorphic

**When:** Phase 6 metamorphic harness authoring. `subagents/metamorphic-author.md` uses the skill's "MR Strength Matrix (Fault-Sensitivity × Independence / Cost ≥ 2.0)" gate to decide which transforms to author first.

**Fallback:** `pattern:40-METAMORPHIC-TRANSFORMS.md` ships the 4-family TransformFamily + EquivalenceExpectation + MismatchClassification + SeedContract inline.

## /testing-fuzzing + /testing-conformance-harnesses + /testing-golden-artifacts + /testing-real-service-e2e-no-mocks

**When:** Phase 6 building the conformance + fuzz + golden harnesses.

**Fallback:** `references/tooling/FUZZ-TOOLCHAIN.md` + `ORACLE-TOOLCHAIN.md` + `pattern:55-INSTA-GOLDEN-SNAPSHOTS.md` ship the playbooks inline.

## /multi-pass-bug-hunting

**When:** Phase 14. The three verbatim fresh-eyes prompts ARE the multi-pass approach.

**Rule (from skill):** "First pass finds obvious bugs. Second pass finds bugs hidden by the obvious ones. Third pass catches what you introduced fixing the first two."

**Fallback:** `references/methodology/FRESH-EYES-PROMPTS.md` is the inline playbook.

## /deadlock-finder-and-fixer

**When:** Phase 6 concurrency harness authoring + Phase 15 soak runs.

**The 9-class concurrency taxonomy (per the skill):**
1. classic AB-BA
2. async/sync re-entrance
3. waker starvation
4. RAII Drop in lock scope
5. reader-writer upgrade
6. channel/queue cycle
7. shared cache miss-storm
8. signal handler in critical section
9. external resource (DB, socket, FS) cycle

**The "always a fourth instance" rule:** when an agent finds 3 instances of a concurrency bug, the 4th is somewhere they haven't looked yet. Don't close until you find it.

**Fallback:** `references/tooling/CONCURRENCY-TOOLCHAIN.md` documents the 9-class taxonomy.

## /lean-formal-feedback-loop

**When:** Phase 0.5 — the cass-miner subagent's mandate is "Step 0.5 history-mining as mandatory" per this skill.

**Fallback:** `subagents/cass-miner.md` is fully inline.

## /multi-agent-swarm-workflow + /agent-fungibility-philosophy

**When:** Phase 11 ITERATE (per-round agent spawning). `orchestration/AGENT-FUNGIBILITY.md` documents the lane convention + the swarm-init prompt verbatim.

**Fallback:** the swarm-init prompt is inlined in `orchestration/AGENT-FUNGIBILITY.md`.

## /flywheel

**When:** every phase. The MEMORY.md + session_*.md convention IS this skill's compaction-survival contract.

**Fallback:** `methodology/MEMORY-MD-CONVENTION.md` + `methodology/COMPACTION-SURVIVAL.md` are fully inline.

## /idea-wizard

**When:** Phase 10. `subagents/idea-wizard-orchestrator.md` invokes the verbatim Phase-2 prompt ("30 clever non-obvious gauntlet techniques for THIS port → winnow to 5 → 10 more").

**Fallback:** the prompt is inlined in the subagent file.

## /beads-workflow

**When:** Phase 13. `subagents/bead-author.md` + `subagents/bead-polisher.md` invoke /beads-workflow's "EXACT PROMPT — Plan to Beads Conversion" + the polish prompt.

**Fallback:** the orchestrator hand-authors beads per `assets/beads-seed/issues.jsonl` shape; polish is iterative manual editing.

## /cass

**When:** Phase 0.5 + every perf-bead pre-flight + Phase 11 round-start. The `cass-miner` subagent + `scripts/mine-cass-cross-machine.sh` invoke /cass's Cross-Machine Search.

**Rule (from /cass skill):** "Never run bare `cass` (TUI). Always use `--robot` or `--json`."

**Fallback:** if /cass unavailable, write a blocker entry per `assets/agents-md-mandate-paragraph.md` and proceed with degraded confidence.

## /agent-mail

**When:** any time multiple subagents are dispatched in parallel. File reservations + threads coordinate the cc_N lane convention.

**Fallback:** the orchestrator serializes parallel work; throughput drops but correctness is preserved.

## /ubs + /dcg

**When:** Phase 14 static gates + every commit. `assets/hooks/dcg-passthrough.sh` delegates to /dcg if installed.

**Fallback:** the gauntlet's `run-fresh-eyes-pass.sh` runs `ubs` directly if on PATH; if absent, skips with a warning. `dcg-passthrough.sh` passes through unchanged.

## /rch

**When:** any operation expected to take >5 minutes wall time. Per `pattern:255-RCH-OFFLOAD-DISCIPLINE`.

**Rule from skill:** "Use when compilation is slow, workers are unhealthy, hook routing is unclear, or remote sync/execution is failing."

**Fallback:** if /rch unavailable, the operation runs locally. The cost discipline is documented (a wasted 8h bench is a real cost; the user authorized it).

## Bootstrap: what to install first

If the user has `jsm` installed, the gauntlet's `subagents/workspace-bootstrapper.md` proactively offers to `jsm install` missing skills at Phase 0. Recommended priority order:

1. `/cass` — used everywhere; biggest impact if absent.
2. `/beads-workflow` — Phase 13 depends on it.
3. `/profiling-software-performance` + `/extreme-software-optimization` — Phase 5/9/11/12.
4. `/testing-metamorphic` + `/testing-fuzzing` + `/testing-conformance-harnesses` + `/testing-golden-artifacts` — Phase 6.
5. `/multi-pass-bug-hunting` + `/deadlock-finder-and-fixer` — Phase 14/15.
6. `/idea-wizard` + advanced-methods mining + frontier-math compilation — Phase 10 (one round).
7. `/codebase-archaeology` + `/codebase-report` — Phase 1.
8. `/multi-agent-swarm-workflow` + `/agent-fungibility-philosophy` + `/flywheel` — Phase 11.
9. `/lean-formal-feedback-loop` — pre-flight.
10. `/agent-mail` + `/rch` — orchestration backbone (especially T3+).
11. `/ubs` + `/dcg` — safety nets.

## Cross-references

- [`methodology/SKILL-FALLBACKS.md`](SKILL-FALLBACKS.md) — per-skill fallback prompts.
- [`orchestration/SKILL-BOOTSTRAP.md`](../orchestration/SKILL-BOOTSTRAP.md) — Phase 0.5 install flow.
- [`methodology/SOURCE-CORPUS.md`](SOURCE-CORPUS.md) — Track A mapping.
