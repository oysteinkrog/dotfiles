# TIER-TRIAGE — Engagement Tiers for the Gauntlet

Pick a tier FIRST; the gauntlet scales to it. Tiers are orthogonal to modes (see [MODE-ROUTER.md](MODE-ROUTER.md)) — mode tells you *which phases run*, tier tells you *how much depth, how many workers, how many patterns to apply, and which artifacts are mandatory vs. optional*.

**Right-sizing matters in both directions.** Don't over-build a T1 (you'll ship late and the discipline rots before anyone uses it). Don't under-build a T5 (the gauntlet's value comes from cross-cutting integration; a half-built T5 looks superficially fine and silently lies to its release gates).

`scripts/detect-tier.sh` proposes a tier from LOC + crate count + sub-product count + downstream-consumer count. The user can override.

---

## Tier-at-a-glance

| Tier | Size | Typical port | Wall time per round | Worker count | rch-offload | Multi-model | Cert. bundle |
|---|---|---|---|---|---|---|---|
| **T1** Tiny | <2k LOC, single crate | toy port, code-kata, SELF-TEST | hours | 1 | optional | no | optional |
| **T2** Single-crate | 2k-20k LOC, single crate | franken_whisper-cli wrapper | ~day | 1-2 | optional | no | optional |
| **T3** Workspace | 20k-200k LOC, multi-crate | fastmcp_rust, franken_whisper, sqlmodel_rust | days | 2-6 | recommended | yes | recommended |
| **T4** Platform | 200k+ LOC, sub-products | frankensqlite, frankentorch, frankenredis | days-weeks | 6-12 | mandatory | mandatory | required |
| **T5** Multi-port family | Multiple ports running gauntlet simultaneously | Franken-family roll-up, all numerical-class siblings together | weeks | NTM-orchestrated swarm | mandatory | mandatory | required |

Concrete examples (from [exemplars/SIBLING-PROJECTS-STATUS.md](../exemplars/SIBLING-PROJECTS-STATUS.md)):

| Port | Tier | Rationale |
|---|---|---|
| FrankenSQLite | **T4** | 6,040-line `comprehensive_bench.rs`, 380-entry perf negative-results ledger, 18 harness modules in `crates/fsqlite-harness/`, MT-scale workload across 8 threads, RaptorQ-FEC. The reference adoption. |
| FrankenTorch | **T4** | Live PyTorch oracle, distributed training surface, GPU contention, 5 checkpoint-save + 2 distributed-collective crash boundaries. |
| FrankenRedis | **T4** | RESP2/RESP3 + 241 commands + RDB v11 + AOF + replication + Lua. Multi-protocol, persistence-heavy. |
| FrankenNumPy | **T3** | `numpy.__all__` structural parity, bit-exact PCG64DXSM RNG, ufunc dispatch surface. Workspace-tier mainly because NumPy is single-threaded in its hot paths (no MT-scale harness). |
| FrankenJAX | **T3** | Primitive catalog + JAXPR IR + nested transform matrix. |
| FrankenPandas | **T3** | "1,252 packets" of conformance evidence; DataFrame/Series/Index APIs + dtype coercion. |
| FrankenSciPy | **T3** | "767 files" of evidence; CASP solver portfolio. |
| FrankenNetworkX | **T3** | Backend-protocol parity + graph fixture corpus. |
| FastAPI Rust | **T3** | Routing, extractors, OpenAPI schema, middleware. |
| FastMCP Rust | **T3** | JSON-RPC, tools/resources/prompts, four-valued outcomes. |
| SQLModel Rust | **T3** | Derive macro + query builder + dialect SQL generation. |
| franken_whisper | **T3** | ML-System class but CLI-shaped surface; per-op ULP + checkpoint-save boundaries. |
| `tests/fixtures/tiny-port/` | **T1** | Single-crate skeleton used in SELF-TEST. |

A "Franken-family roll-up" (running the gauntlet across all numerical-class siblings in one swarm, sharing the parity score contract and cross-validating) is a **T5**.

---

## T1 — Tiny

### Profile
- Single crate, <2k LOC.
- Single contributor (or a coding-kata participant).
- No multi-thread requirement.
- Reference is single-binary (e.g., a tiny domain library).
- Typical use case: SELF-TEST workflow; first port someone writes when learning the methodology.

### Required patterns from the library (minimum)
1. ★ Pin-Reference-Version
2. ◐ Wire-Oracle
3. ✦ Enumerate-Surface (FeatureUniverse can have ≤5 features)
4. ⬡ Instrument-Hot-Path (one `HotPathProfileSnapshot` row sufficient)
5. ⊙ Debounce-False-Positive (the 5 mismatch classes still apply)
6. 🪞 Engine-Identity-Guard

Skipped at T1 (acceptable but documented in the workspace):
- `⊞` Soak — overkill for hours-long ports
- `⤴` Attribute-To-MT8 — no MT workload exists
- `📐` Conformal-Band — Beta posterior point estimate is sufficient at <100 fixtures

### Required subagents (minimum)
- `subagents/workspace-bootstrapper.md`
- `subagents/oracle-wirer.md`
- `subagents/oracle-test-author.md`
- `subagents/bench-author.md`
- `subagents/feature-universe-builder.md`
- `subagents/final-report-author.md`

Skipped at T1: every soak runner, the mismatch-minimizer-builder (the universe is small enough to triage by hand), the multi-model triangulation runner.

### Required phases (gauntlet-full mode)
0, 1, 2, 3, 4, 5, 6, 7, 8, 9, **10 (lightweight: 5-10 ideas, not 30)**, **11 (≥3 rounds, ≥1 clean — relaxed from the standard ≥10 / ≥2 because the search space is tiny)**, 12, 13, 14 (1 reviewer, not 3), 16. Phase 15 OPTIONAL.

### Certification bundle expectations
Optional. If produced, the bundle is minimal: `confidence_gate.json`, `scorecards.json`, `release_certificate.json`. No need for the full 8-document strict-conformant-release.v1.

### Wall time
2-8 hours for `gauntlet-full`. 15-30 min for `quick-smoke`.

### Common mistakes
- Over-building: adding the full 8-WAL-boundary crash matrix to a port that has no WAL.
- Skipping Phase 8 negative-ledger because "there's no history yet" — wrong; the discipline is established here, not retrofitted.
- Skipping Phase 14 because "the code is simple" — most likely place for a bug is "obviously correct" code.

---

## T2 — Single-crate

### Profile
- Single crate, 2k-20k LOC.
- 1-3 contributors.
- May have a small concurrency surface (an async client, a pool) but no MVCC-style invariant catalog.
- Reference may be a single binary or a small library.
- Examples: a thin Rust wrapper around a CLI tool (franken_whisper-cli); a single-purpose protocol parser.

### Required patterns from the library (minimum)
T1 list +
7. ⚠ Escalate-To-Fresh-Repro
8. 🗄 Ledger-Retire (the three negative-ledgers become load-bearing as the round count climbs)
9. 🧪 Experiment-Design (one `GAUNTLET_EXPERIMENT_DESIGNS.md` per port)
10. 🔁 Pass-Over-Pass-Gate (`.bench-history` is committed)

### Required subagents
T1 list +
- `subagents/mismatch-minimizer-builder.md`
- `subagents/idea-wizard-orchestrator.md`
- `subagents/iteration-coordinator.md`
- `subagents/baseline-runner-perf.md` / `-conformance.md` / `-surface.md`

### Required phases (gauntlet-full mode)
0-16 all phases run. **Phase 11 ≥5 rounds, ≥2 clean** (relaxed from ≥10 / ≥2). Phase 15 soak: 1-day fuzz, 1-day Miri (not full multi-day).

### Certification bundle expectations
Optional but recommended. Minimal bundle: `confidence_gate.json`, `verification_contract.json`, `scorecards.json`, `release_certificate.json`. Skip the per-machine ratchet diff (single host is sufficient at T2).

### Wall time
~1 day per round; ~1 week for `gauntlet-full`. `incremental-rebase` finishes in hours.

### Common mistakes
- Skipping the metamorphic harness because "the API surface is small" — metamorphic relations catch bugs that exhaustive enumeration misses; even at T2, the four `TransformFamily` variants are cheap and valuable.
- Stopping the iteration loop at 3 rounds because findings dried up — the contract is ≥5 rounds *AND* ≥2 clean; both, not either.

---

## T3 — Workspace

### Profile
- Multi-crate Cargo workspace, 20k-200k LOC.
- Multi-contributor; multiple ongoing branches.
- Concurrency surface that warrants `loom` / `shuttle` (typically async I/O, connection pool, optional fork-join).
- Reference is a library or framework with a non-trivial dispatch table.
- Examples: fastmcp_rust, franken_whisper, fastapi_rust, sqlmodel_rust, franken_numpy, franken_pandas, franken_scipy.

### Required patterns from the library (full)
All 19 glyphs from [OPERATORS.md](OPERATORS.md). At T3 every operator is in scope; the library is designed for T3 as its default tier.

### Required subagents
The full subagent roster from [SKILL.md § Subagents](../../SKILL.md). Notable additions vs. T2:
- All metamorphic authors (one per `TransformFamily`)
- All fault-injector authors (one per `FaultKind`)
- All crash-boundary wirers (one per `CrashBoundary` for the class)
- All e-process modelers (one per invariant)
- All three fresh-eyes reviewers (a, b, c)
- All seven soak runners

### Required phases (gauntlet-full mode)
0-16 all phases run. **Phase 11 ≥10 rounds, ≥2 clean** (the standard). **Phase 15 full soak**: 24h+ fuzz, multi-day Miri, multi-thousand-iter loom/shuttle, multi-thousand-iter crash-boundary, multi-day BOCPD, adversarial.

### rch-offload requirements
**Recommended.** Everything >5 min wall time → `rch`. The full `comprehensive-bench` matrix (93+ scenarios) almost always >30 min; Phase 11 iteration easily 1-3 days per round on local hardware. Phase 15 fans the seven soak runners out to `rch`; `scripts/run-soak-campaign.sh` can also run any selected subset directly.

### Multi-model triangulation
Yes. Phase 14 fresh-eyes runs three model panels (Claude + Codex + Gemini per [TRIANGULATION.md](TRIANGULATION.md)). The marginal value is high at T3 because the codebase is large enough that single-model blind spots become real.

### Certification bundle expectations
**Recommended.** Full strict-conformant-release.v1 bundle: confidence gate JSON, verification contract JSON, release certificate JSON, CI artifact manifest, benchmark summary, `scorecards.json`, critical-path report, ratchet state.

### Wall time
1-3 days per round; ~2 weeks for `gauntlet-full`. `incremental-rebase` in hours-to-day.

### Common mistakes
- Running locally instead of on `rch` — multi-day wall time blocks the host for everything else.
- Treating Phase 14 as a single-reviewer pass — all three calibrated reviewers (a, b, c) are required at T3.
- Skipping the FeatureUniverse weight invariant check (`sum(weights) == 1.0`) because "we know it's right" — the loader-enforced check is K-5 verbatim.
- Conflating "the harness compiles" with "the harness is gating correctly". At T3 you actively try to break the harness during Phase 15 adversarial.

---

## T4 — Platform

### Profile
- 200k+ LOC across multiple sub-products / crates / modules.
- Large contributor pool; multiple parallel campaigns.
- Concurrency surface includes MVCC-style invariant catalogs (FrankenSQLite's INV-1..INV-7), distributed coordination (FrankenTorch's NCCL), or persistence-state machines (FrankenRedis's RDB/AOF).
- Reference is itself a platform (SQLite, PyTorch, Redis, JAX with full transform composition).
- Examples: frankensqlite, frankentorch, frankenredis.

### Required patterns from the library (full + extensions)
All 19 glyphs + **per-class extensions** documented in [taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md). Specific T4 additions:
- Cross-machine ratchet diff (truncate_score'd across x86/ARM/WASM).
- Adversarial-search auto-generator (when a new gate lands, an adversarial-search task is auto-queued for it).
- BOCPD on the parity-score stream (regime classification stays `Stable` throughout the multi-day window).
- Full §75-76 mathematical toolkit applied wherever it earns its keep: Cahill-Fekete SSI rule, Mazurkiewicz traces, Adaptive Replacement Cache, RaptorQ fountain codes, XXH3 page checksums, Argon2id KEK.

### Required subagents
The full roster + **multi-agent swarm coordination via NTM** (see [multi-agent-swarm-workflow](../../../multi-agent-swarm-workflow/SKILL.md)). At T4 the orchestrator dispatches not just subagents but other agent processes — typically 8-12 concurrent workers per round.

### Required phases (gauntlet-full mode)
0-16 all phases at full discipline. **Phase 11 ≥10 rounds, ≥2 clean** is a floor — T4 ports often run 15-25 rounds before convergence because the codebase is large enough that genuine new findings keep surfacing. **Phase 15 ≥3-day fuzz, ≥4-day Miri, ≥10,000-iter loom-shuttle, ≥7-day BOCPD.**

### rch-offload requirements
**Mandatory.** Cannot run T4 locally without the host being unusable. `rch` worker pool with ≥4 workers for the soak campaign; ≥2 workers for the perf bench matrix; ≥1 worker for the fuzz corpus. See [orchestration/ORCHESTRATION.md § rch offload heuristic](../orchestration/ORCHESTRATION.md).

### Multi-model triangulation
**Mandatory.** Phase 14 fresh-eyes runs all three models on every round. Disagreements are surfaced for human review (per [TRIANGULATION.md § Consensus rules](TRIANGULATION.md)) and not auto-resolved.

### Certification bundle expectations
**Required.** Full strict-conformant-release.v1 + per-machine ratchet diff + cross-platform `truncate_score` proof + adversarial-search counterexample list (empty == green).

### Wall time
Days-weeks per round; **30+ days** for `gauntlet-full`. `incremental-rebase` in days. `compliance-pass` in 1-3 days.

### Common mistakes
- Trying to do T4 with T3's worker count — convergence stalls at ~7 rounds because the search space is too large.
- Treating BOCPD as "nice to have" — at T4 the parity-score stream is the only honest detector of slow drift across the multi-week window.
- Skipping cross-machine ratchet diff because "it's the same Rust" — x86/ARM/WASM differ at the LSB; without `truncate_score` the ratchet flickers.

---

## T5 — Multi-port family

### Profile
- Multiple ports running the gauntlet *simultaneously*, sharing the parity-score contract, cross-validating findings.
- The "Franken-family roll-up": all numerical-class siblings (franken_numpy + franken_scipy + frankenpandas + frankentorch + frankenjax) run the gauntlet in lockstep against a shared per-class FeatureUniverse, with cross-port consistency gates.
- Used at organization scale; one gauntlet team responsible for the full family's release.

### Required patterns from the library
All 19 + the **cross-port consistency operator** (T5-only):

> **⛬ Cross-Port-Consistency:** "For every FeatureUniverse entry that appears in ≥2 ports of the family, does the per-port status agree (modulo declared per-port exclusions)? If port-A says `Passing` and port-B says `Partial` for the same Feature with the same expected behavior, that's a CONFIRMED_GAP for port-B and a regression-test opportunity for port-A."

### Required subagents
T4 roster + a **family-orchestrator** subagent (typically run as an NTM session) that:
- Coordinates Phase 11 iteration across all member ports (each port iterates independently, but the family-orchestrator gates promotion of any port until its siblings agree on shared Features).
- Maintains a shared `family_feature_universe.toml` that is the union of per-port FeatureUniverses with cross-references.
- Dispatches multi-model triangulation across the family (a finding in port-A's Phase 14 is shared with port-B's reviewer for cross-validation).

### Required phases
Full 0-16, run *per-port* AND a family-level Phase 12.5 (cross-port consistency) and Phase 16.5 (family-roll-up report) interposed.

### rch-offload requirements
**Mandatory.** `rch` worker pool sized to the family count × the per-port soak runners. NTM tmux session manages the worker mesh.

### Multi-model triangulation
**Mandatory.** Per-port triangulation + family-level triangulation (one model reviews all per-port findings to spot cross-port consistency issues).

### Certification bundle expectations
**Required.** Per-port bundles + a family-level `FAMILY_RELEASE_CERTIFICATION.md` cross-referencing them.

### Wall time
Months for the initial `gauntlet-full`. Subsequent quarterly `audit-and-fix` cycles on a continuous basis.

### Common mistakes
- Treating each port's gauntlet as fully independent — the cross-port consistency gate is the highest-leverage finding source at T5.
- Trying to enforce strict-100% cross-port agreement — declare per-port exclusions explicitly in the family contract; cross-port consistency means "agreement modulo declared deltas", not "uniform".
- Not using NTM for orchestration — the family-orchestrator is a long-running coordination process; tmux-based isolation is what keeps it surviving across agent restarts.

---

## Complexity overlay (per-feature axis)

Sometimes a port falls between tiers because a single *feature* (rather than the whole codebase) is unusually complex. Use the overlay to bump effort just for that feature:

| Feature axis adds tiers | Example | What changes |
|---|---|---|
| **MVCC / concurrent transactions** | FrankenSQLite's BEGIN CONCURRENT | +1 tier for the MT-scale harness + e-process invariant catalog |
| **Distributed coordination** | FrankenTorch NCCL all-reduce | +1 tier for the cross-rank crash boundaries + 2 distributed-collective fault profiles |
| **Persistence state machine** | FrankenRedis RDB+AOF | +1 tier for the persistence-crash boundary matrix |
| **Numerical determinism (ULP)** | FrankenJAX rewrite rules | +1 tier for the per-op ULP tolerance table + bit-exact RNG parity |
| **Compile-time codegen** | SQLModel Rust derive macro | +1 tier for the macro-expansion oracle + compile-fail test suite |
| **Protocol versioning** | FrankenRedis RESP2 vs RESP3 | +1 tier for the per-version oracle wiring |
| **Multi-VFS** | FrankenSQLite fault VFS + memory VFS + posix VFS | +1 tier for the per-VFS fault profile matrix |

A T3 codebase with two of these axes effectively executes as T4 for those features. Document the bump in `<workspace>/tier_assessment.md`.

---

## Tier assessment template

At Phase 0, `subagents/workspace-bootstrapper.md` emits `<workspace>/tier_assessment.md`:

```markdown
# Tier Assessment for <port>

## Sizing inputs
- LOC: <number> (from `tokei <target>/src`)
- Crate count: <number> (from `cargo metadata --format-version 1 | jq '.packages | length'`)
- Sub-product count: <number> (from `<target>/Cargo.toml` workspace members)
- Downstream consumers: <number> (from cargo / pypi / npm reverse-deps if applicable)
- Contributor count: <number> (from `git shortlog -s -n --since='90 days ago' | wc -l`)

## Proposed tier
**<T1 | T2 | T3 | T4 | T5>**

## Complexity overlay axes activated
- [ ] MVCC / concurrent transactions
- [ ] Distributed coordination
- [ ] Persistence state machine
- [ ] Numerical determinism (ULP)
- [ ] Compile-time codegen
- [ ] Protocol versioning
- [ ] Multi-VFS / multi-backend

## Effective tier (after overlay)
**<resulting tier>**

## Implications
- Required patterns: <numbered list>
- Required subagents: <list>
- Phase 11 minimum rounds: <number>
- Phase 15 soak budget: <wall time>
- rch-offload: <optional | recommended | mandatory>
- Multi-model triangulation: <no | yes | mandatory>
- Certification bundle: <optional | recommended | required>
- Expected wall time for gauntlet-full: <hours | days | weeks | months>

## Rationale
<one paragraph explaining the tier choice, noting any borderline judgments>
```

The user reviews this at Up-Front Confirmations. If they push back ("we're a T4 but treat it as T3 — we can't afford the swarm"), document the deviation and adjust the wall-time + worker estimates. **Do not silently downgrade discipline**; if T4's certification bundle is required for the use case, declining to do the work is a *no-go* finding, not a "we did T3 instead" finding.

---

## Tier × mode budget table

Combine [MODE-ROUTER.md § Mode-tier overlay](MODE-ROUTER.md) with this file:

| Tier | gauntlet-full | audit-only | harden-pillar | add-feature | incremental-rebase |
|---|---|---|---|---|---|
| T1 | hours | hours | hours | minutes | minutes |
| T2 | ~week | days | days | hours | hours |
| T3 | ~2 weeks | ~3 days | 3-7 days | hours-days | hours-day |
| T4 | 30+ days | ~week | ~week | days | days |
| T5 | months | weeks | weeks | weeks | days-week |

Quote these wall times to the user. A T4 `gauntlet-full` quoted at "a day" is the most common scope-mismatch failure mode in this skill.

---

## Common mistakes (across all tiers)

- **Picking T1 when the codebase is T3.** "It's just a small port" but the reference is SQLite — you need the full discipline, the iteration loop, the soak. Right-size by reference complexity, not by port size.
- **Picking T5 when the family doesn't exist yet.** T5 requires multiple sibling ports running the gauntlet — if only one port has the workspace set up, you're running T4 with extra coordination overhead.
- **Bumping tier mid-run.** If Phase 9 reveals the port is actually T4 (e.g., a hidden MVCC surface), don't quietly continue at T3 — re-emit `tier_assessment.md`, surface to the user, and either complete at T3 with the deficiencies declared, or restart at T4.
- **Skipping the complexity overlay.** A T3 codebase with MVCC + distributed coordination is effectively T5 for those features. Declare it.

See [SKILL.md § Up-Front Confirmations](../../SKILL.md) for how the orchestrator confirms the tier with the user before any phase runs.
