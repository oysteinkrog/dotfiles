---
name: running-the-gauntlet-on-your-rust-port
description: >-
  Convergent multi-round honest-evaluation gauntlet for any mature Rust port
  (FrankenSQLite-class). Use when running the gauntlet, certifying parity,
  measuring honest perf vs reference, building oracle/differential/metamorphic
  harnesses, surface-parity audits, or shipping a release-readiness scorecard.
---

<!-- TOC: One Rule | Three Pillars | Up-Front Confirmations | Skill Bootstrap | Mode Router | Tier Triage | Project Class Router | The 16-Phase Loop | Parallelism Model | Convergence Rule | Operator Library | Pattern Library | Keep-Gate Rules | Negative-Ledger Mandate | Verification-First | Source Corpus | Polish Bar | Anti-Patterns | Cookbook | Final Artifacts | Reference Index | Scripts | Subagents | Assets | Self-Test -->

# Running the Gauntlet on Your Rust Port

> **The One Rule.** Honesty is encoded in the harness, not in the reviewer. Every claim — perf ratio, conformance pass rate, surface coverage — must survive a hostile reading of its own artifacts. If the gate can flip on a rerun, on a different host, on a fresh `target/`, on a renamed bench-history file, or on a quiet PRAGMA default change, the gate is a lie. Build gates that refuse to lie.

> **What this skill produces.** A version-controlled `<project>__gauntlet_workspace/` sibling directory containing: a 16-phase convergent multi-round evaluation against the pinned reference; a per-pillar evidence bundle (oracle differential corpus, comprehensive-bench matrix, FeatureUniverse with `present|partial|missing|excluded` accounting); three durable negative-evidence ledgers (perf / conformance / surface) with retry-condition predicates per closed entry; a remediation plan with isomorphic-rewrite alternatives scored on a fixed rubric; a polished bead graph ready for swarm execution; and a `FINAL_GAUNTLET_REPORT.md` + `PARITY_RUNBOOK.md` + `RELEASE_CERTIFICATION_TEMPLATE.md` triple for the project maintainers. **Convergence requires a minimum of 10 full rounds.**

---

## What This Skill Is For

You point this skill at a Rust *port* of a mature reference project (SQLite, Redis, NumPy, PyTorch, JAX, pandas, SciPy, NetworkX, FastAPI, FastMCP, SQLModel, Whisper — or any sibling) and ask one of:

1. *"Run the gauntlet on `<port>` and tell me exactly where it stands vs the reference."*
2. *"Certify this port for a release; produce the parity scorecard + the release-readiness bundle."*
3. *"We just rebased onto a new reference version — re-run the gauntlet incrementally."*
4. *"Audit my port's negative-ledger discipline; mine 60 days of session history; retire dead hypotheses."*
5. *"Design and dispatch the remediation plan for every confirmed gap, polished into beads."*

The skill answers each by routing through the same kernel (Subject/Oracle/Comparator), the same operator library (cognitive moves with glyphs), the same 16-phase loop (workspace → recon → contract → oracle → golden → perf → conformance → surface → ledger → baseline → idea-wizard → iterate → remediate → beads → fresh-eyes → soak → final), and the same convergence rule (≥10 rounds; ≥2 consecutive clean rounds; every open hypothesis resolved).

The methodology is mined verbatim from the FrankenSQLite bibles: `/data/projects/frankensqlite/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CC.md` (~5,065 lines, 32 `# PART` headings) + `..._CODEX.md` (~3,798 lines, 19 numbered sections). Every pattern in this skill traces back to a real artifact lane, a closed bead, or a negative-ledger entry in that codebase. See **[exemplars/FRANKENSQLITE-BIBLE.md](references/exemplars/FRANKENSQLITE-BIBLE.md)** for the section-by-section routing table.

---

## The Three Pillars (Decomposition)

| Pillar | Question it answers | Headline artifact | Gate type |
|---|---|---|---|
| **(a) Performance** | "Is the port actually faster than the reference on this workload, measured honestly?" | `comprehensive-bench` JSON v3 + `.bench-history/<bench>.latest.json` + per-category weighted score | pass-over-pass ratchet; primary score `−3%`, geomean `−5%`, per-category `−10%`, p90 `−15%`, throughput `−5%` |
| **(b) Conformance** | "Does the port produce the same answer as the reference for the same input, including under fault and crash?" | Differential V2 envelope (content-addressed `artifact_id = SHA-256` of canonical JSON excluding run_id) + metamorphic corpus + crash-boundary recovery proof + e-process invariants | conformal lower-bound ratchet; release uses LOWER bound, not point estimate |
| **(c) Surface parity** | "What fraction of the reference's declared surface does the port implement, and what fraction is explicitly excluded?" | FeatureUniverse + SurfaceMatrix (`present|partial|missing|n/a|excluded`) + per-family coverage dashboard | feature-coverage release-gate; partial never rounds up to success |

The agent is **forbidden from declaring victory on one pillar while another regresses**. Full pillar decomposition, success criteria, and gating rules: **[THREE-PILLARS.md](references/THREE-PILLARS.md)**.

---

## Up-Front Confirmations (Ask Before Starting)

1. **Target port path?** Confirm the absolute path (e.g., `/data/projects/frankensqlite`), or a git URL we should clone into `/tmp/<basename>/` and operate on the worktree.
2. **Workspace directory?** Default: `<basename>__gauntlet_workspace/` as a sibling, `git init`-ed. Confirm OK to create (or reuse if resuming).
3. **Project class?** Auto-detected by `scripts/detect-project-class.sh` (SQL-class / RESP-class / Numerical-Python-class / ML-System-class / HTTP-Protocol-class). Confirm the class and matching oracle-wiring strategy. See **[taxonomy/PROJECT-CLASSES.md](references/taxonomy/PROJECT-CLASSES.md)**.
4. **Reference version to pin?** e.g., `sqlite-3.52.0`, `redis-7.2.5`, `torch-2.X.Y`, `numpy-1.26.0`. Recorded in `docs/contracts/<reference>_version_contract.toml`.
5. **Local vs `rch`-offloaded heavy passes?** Recommend `rch` for anything >5 minutes wall time (full `comprehensive-bench` matrix, multi-day Miri / sanitizer / fuzz / loom / shuttle / crash-boundary / BOCPD soak runs). See **[orchestration/ORCHESTRATION.md § rch offload heuristic](references/orchestration/ORCHESTRATION.md)**.
6. **Fresh run, incremental rebase, or resume?** If `<workspace>/` exists, offer to re-enter the loop at the next pending round (idempotent), or to start a fresh run.
7. **Final-artifact tier?** Internal-only / public-release / certification-bundle (the last requires every required-pass constant in **[methodology/CERTIFICATION.md](references/methodology/CERTIFICATION.md)**).

Missing public helper skills (`/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/profiling-software-performance`, `/extreme-software-optimization`, `/testing-metamorphic`, `/testing-fuzzing`, `/testing-conformance-harnesses`, `/testing-golden-artifacts`, `/testing-real-service-e2e-no-mocks`, `/multi-pass-bug-hunting`, `/deadlock-finder-and-fixer`, `/lean-formal-feedback-loop`, `/multi-agent-swarm-workflow`, `/agent-fungibility-philosophy`, `/flywheel`, `/idea-wizard`, `/beads-workflow`, `/cass`, `/agent-mail`, `/ubs`, `/dcg`, `/rch`): if `jsm` is installed and authenticated, offer to `jsm install <name>` for each missing one as a non-blocking bootstrap step. The pipeline ships inline fallbacks for every referenced helper.

---

## Skill Bootstrap (Phase 0.5 — right after inputs, before partition)

Before `init-workspace.sh` copies the helper scripts into the gauntlet
workspace, run these commands from the installed skill directory or set
`SKILL_DIR` to that absolute path and use the prefix below. After Phase 0,
the copied workspace scripts are available at `<workspace>/scripts/`.

```bash
SKILL_DIR="/path/to/running-the-gauntlet-on-your-rust-port"
"$SKILL_DIR/scripts/install-toolchain.sh" --workspace <workspace> # rustup nightly + miri + rust-src + cargo-criterion + hyperfine + cargo-flamegraph + samply + cargo-show-asm + cargo-fuzz + cargo-afl + cargo-llvm-cov + cargo-geiger + cargo-audit + cargo-deny + dhat + heaptrack + ast-grep + semgrep + loom + shuttle + cargo-expand + cargo-insta
"$SKILL_DIR/scripts/init-workspace.sh" <target> <workspace>     # mkdir + git init + AGENTS.md mandate paragraph + three negative-ledger seeds + version-contract skeleton
"$SKILL_DIR/scripts/detect-project-class.sh" <target> --workspace <workspace> # writes <workspace>/phase0_project_class.json
"$SKILL_DIR/scripts/check-skills.sh" <workspace>                # inventory of helper skills + jsm state; exit 1 is yellow/advisory
"$SKILL_DIR/scripts/oracle-preflight-doctor.sh" <target> --workspace <workspace> # readiness probe; yellow is expected until contracts/oracle wiring are pinned, red blocks
```

Full bootstrap detail (subscription checks, headless OAuth, inline fallback when `jsm` is missing): **[orchestration/SKILL-BOOTSTRAP.md](references/orchestration/SKILL-BOOTSTRAP.md)** and **[methodology/SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md)** for the per-helper-skill fallback prompts.

---

## Mode Router (Pick the Pipeline Shape)

The gauntlet runs in one of 11 modes, scoped to the user's intent. The 16-phase loop is the same; the **subset of phases that run** and **the exit criteria** differ. Default: `gauntlet-full`.

| Mode | Use when | Phases run |
|---|---|---|
| `gauntlet-full` | First-pass evaluation of a port | 0-16 |
| `gauntlet-greenfield` | Novel Rust project with no mature upstream reference | 0-16 with spec/property/self/round-trip/external-tool Oracle |
| `audit-only` | Existing port; want a report + plan, not code changes | 0-9 |
| `harden-pillar --pillar <pillar>` | A specific pillar regressed; focus capacity there | 0, 9, 10, 11, 12, 13, 14 |
| `add-feature --feature-id <feature-id>` | Adding one Feature to a port that's otherwise at parity | 5, 6, 7, 12, 13, 14 |
| `incremental-rebase` | Port's main branch moved; re-run affected phases | 0, 1, 9, 11, 14, 16 |
| `compliance-pass` | Re-certify against a moved reference version | 0, 1, 2, 14, 15, 16 |
| `red-team` | Adversarial-only attack against existing gates | 15 |
| `migration --new-ref-version <version>` | Switching reference versions | 0-4, 9, 11, 12-14, 16 |
| `cass-mine-only` | Just mine ledger + cass; no further phases | 0 + cass mining |
| `quick-smoke` | Minimal pass against a tiny port (SELF-TEST) | 0, 9 (quick mode) |

Driver: `"$SKILL_DIR/scripts/gauntlet.sh" <target> [<workspace>] --mode <mode>`. Modes that need an extra value use explicit flags: `--pillar <pillar>`, `--feature-id <feature-id>`, or `--new-ref-version <version>`. Per-mode verbatim kickoff prompts: **[methodology/KICKOFF-PROMPTS.md](references/methodology/KICKOFF-PROMPTS.md)**. Full mode definitions + exit criteria + required artifacts: **[methodology/MODE-ROUTER.md](references/methodology/MODE-ROUTER.md)**.

---

## Tier Triage (Pick the Right Depth)

The gauntlet scales. Don't over-build T1; don't under-build T5.

| Tier | Profile | Wall-time per round | Required orchestration |
|---|---|---|---|
| **T1 — Tiny** | Single crate, <2k LOC | hours | Solo agent, local |
| **T2 — Single-crate** | 2-20k LOC | ~day | Pair, local |
| **T3 — Workspace** | Multi-crate, 20-200k LOC | days | Squad (4-6) + `rch` |
| **T4 — Platform** | 200k+ LOC, multiple products | days | Swarm (8-12+) + `rch` + multi-model triangulation |
| **T5 — Multi-port family** | Gauntlet across several ports simultaneously | week+ | Full swarm + cross-port coordinator |

Complexity overlays (each adds +1 tier): GPU dependence, distributed reference, multi-version compatibility required, dual-mode (backend + standalone) operation, regulatory/compliance overlay.

Concrete examples: `frankensqlite` = T4; `franken_whisper` = T3; `fastmcp_rust` = T3; the full Franken-family run = T5. Full triage rubric: **[methodology/TIER-TRIAGE.md](references/methodology/TIER-TRIAGE.md)**.

---

## Project Class Router (Pick the Oracle Wiring)

Five classes; pick the matching oracle-wiring strategy + NormalizedValue type + retry predicate + headline-matrix axes + crash-boundary enumeration. Full per-class playbook: **[taxonomy/PROJECT-CLASSES.md](references/taxonomy/PROJECT-CLASSES.md)**.

| Class | Members | Oracle wiring | NormalizedValue | Crash boundaries |
|---|---|---|---|---|
| **SQL-class** | frankensqlite, sqlmodel_rust | in-process `rusqlite` via `libsqlite3-sys` pinned to contract version; render-to-canonical-string comparator | `{Null, Integer, Real, Text, Blob}` | 8 named: BeforeWalHeaderWrite … AfterCheckpoint |
| **RESP-class** | frankenredis | vendored `redis-server` binary, UNIX domain socket, deterministic command trace | `RespValue` with 14 RESP3 variants + collection-semantics comparator | 6+ AOF/RDB boundaries |
| **Numerical-Python-class** | franken_numpy, frankenpandas, frankenscipy, franken_networkx | PyO3 in-process Python interpreter, `numpy.testing` formatters, **bit-exact PCG64DXSM RNG parity** | `TensorSpec { shape, dtype, device, requires_grad, data_hash }` + per-op ULP tolerance table | 5 checkpoint-save boundaries |
| **ML-System-class** | frankentorch, frankenjax, franken_whisper | PyO3 in-process with `torch.use_deterministic_algorithms(True)` (or equivalent) pinned; seeded RNG captured per-call | TensorSpec + per-op ULP table (4 ULP f32 matmul, 2 ULP elementwise default) | 5 checkpoint-save + 2 distributed-collective |
| **HTTP-Protocol-class** | fastapi_rust, fastmcp_rust | compliance fixture corpus + reference framework with deterministic clock + RNG; HTTP response normalized type (status + headers case-insensitive + body MIME-aware) + OpenAPI schema diff | normalized HTTP response | 5 request-lifecycle: open/header/body-start/body-end/close + cancellation |

---

## The 16-Phase Loop (Mandatory)

```
Phase  0  TOOLCHAIN BOOTSTRAP + WORKSPACE INIT      (single agent; green/yellow/red precondition verdict)
Phase  1  RECON                                     (per-crate subagents; parallel; codebase-archaeology + codebase-report)
Phase  2  REFERENCE PINNING + SURFACE CONTRACT      (single agent; scope-decision coherence)
Phase  3  ORACLE WIRING                             (one subagent per project class)
Phase  4  GOLDEN CAPTURE                            (parallel per tier + per fixture-source; Tier 1 byte / Tier 2 canonical / Tier 3 logical)
Phase  5  PERFORMANCE HARNESS                       (parallel per workload family; comprehensive-bench + narrow benches + hot-path counters + .bench-history + perf-loop + regression detector)
Phase  6  CONFORMANCE HARNESS                       (parallel per behavior class + per metamorphic family + per fault category + per crash boundary + per fuzz target + per invariant e-process)
Phase  7  SURFACE PARITY INVENTORY                  (single agent; FeatureUniverse + InvariantCatalog + dashboard + verification contract)
Phase  8  NEGATIVE-LEDGER + AGENTS.MD MANDATE       (single agent; seed 3 ledgers + AGENTS.md mandate paragraph + cass-mining 60-day grep paragraph)
Phase  9  BASELINE RUN                              (parallel: perf + conformance + surface baseline-runners; first full sweep)
Phase 10  IDEA-WIZARD ROUND                         (/idea-wizard Phase 2 + advanced-methods mining + frontier-math compilation)
Phase 11  ITERATE PHASES 5–10                       (repeat until convergence; MINIMUM 10 ROUNDS)
Phase 12  REMEDIATION DESIGN                        (one architect per pillar; enumerate isomorphic rewrites; score on fixed rubric)
Phase 13  BEADS HANDOFF                             (/beads-workflow plan→beads + 4–5 polish rounds + dependency validation)
Phase 14  FRESH-EYES REVIEW                         (three verbatim prompts; ubs + clippy + fmt + test + miri; loop until two clean passes)
Phase 15  SOAK / DEEP-VALIDATION                    (parallel rch-offloaded long-runs: fuzz, miri, loom, shuttle, crash-boundary, BOCPD, adversarial)
Phase 16  FINAL ARTIFACTS                           (FINAL_GAUNTLET_REPORT.md + PARITY_RUNBOOK.md + RELEASE_CERTIFICATION_TEMPLATE.md + polished bead graph + certification bundle)
```

**Phases 5, 6, 7, 11, 14** are *reapply-until-quiet*. Phase 11 is the convergence loop and is the single most expensive phase (typically days per round; **rch-offload heavily**). Phase 14's two clean rounds are the explicit termination gate before Phase 15. Phase 15 surfaces late-breaking findings; genuine new gaps loop back to Phase 12.

Full per-phase playbook with inputs / outputs / exit criteria / parallelism shape / coordination thread-ID pattern: **[PHASES.md](references/PHASES.md)**. Verbatim agent prompts: **[AGENT-PROMPTS.md](references/AGENT-PROMPTS.md)**.

---

## Parallelism Model

Per-pillar lane assignment (the cc_1 / cc_2 / cc_3 / cc_4 convention from FrankenSQLite):

```
cc_1 → conformance / oracle / differential / metamorphic / fault / crash-boundary
cc_2 → performance / benches / profile-cards / hot-path counters / regression detector
cc_3 → surface parity / coverage / feature universe / invariant catalog
cc_4 → fault / crash / soak / e-process / BOCPD / adversarial search
```

Soft assignment by pillar; agents may cross lanes, but stay-in-lane minimizes MCP Agent Mail reservation collisions. Coordination thread IDs: `gauntlet-<run-id>-<phase>-<bucket>`. Reservations: `tool://comprehensive-bench`, `tool://oracle-runner`, `tool://fuzz-corpus`, `tool://golden-fixtures`, `resource://gpu-0`, `resource://rch-worker-pool`. See **[orchestration/ORCHESTRATION.md](references/orchestration/ORCHESTRATION.md)**.

| Tier | Shape | When |
|---|---|---|
| Solo | 1 worker, serial phases | Tiny port, <5 crates |
| Pair | 2 workers, fan-out only on Phase 5+6 | Single-crate port |
| Squad | 4–6 workers, lane-assigned | Typical Rust port |
| Swarm | 8–12+ workers, lane-assigned + beads-driven + multi-model triangulation on Phase 14 | Multi-crate workspace; certification bundle target |

---

## Convergence Rule (Non-Negotiable)

The gauntlet is convergent when **all three** hold:

1. **Minimum rounds met** — ≥10 full iterations of Phases 5→10.
2. **Two consecutive clean rounds** — each producing <3 *new genuine* findings (computed by `scripts/convergence-tracker.sh` across the three ledgers + every per-bucket findings file).
3. **Every open hypothesis resolved** — `CONFIRMED_GAP | NO_EVIDENCE | NEEDS_REFINEMENT | NEW_HYPOTHESIS_SPAWNED` filled for every entry in `GAUNTLET_EXPERIMENT_DESIGNS.md`, `PERF_HYPOTHESIS_LEDGER.md`, `CONFORMANCE_HYPOTHESIS_LEDGER.md`, `SURFACE_PARITY_HYPOTHESIS_LEDGER.md` (the `NEEDS_REFINEMENT` and `NEW_HYPOTHESIS_SPAWNED` states keep the loop going).

`scripts/convergence-tracker.sh` exits non-zero until convergence is reached and is wired as a CI gate. Compaction-survival: the workspace markdown files are the source of truth so the agent can drop back in mid-run. Full convergence math: **[methodology/CONVERGENCE.md](references/methodology/CONVERGENCE.md)**.

---

## Operator Library (Cognitive Moves)

Composable moves. Apply to any artifact, any candidate optimization, any conformance divergence. Each is a question that, if it fails, names a fix-section. Full card library with triggers, failure modes, prompt modules: **[methodology/OPERATORS.md](references/methodology/OPERATORS.md)**.

| Glyph | Name | Question | Fix-section |
|---|---|---|---|
| `★` | **Pin-Reference-Version** | "Does every artifact in this run identify the exact reference version it was generated against?" | `docs/contracts/<reference>_version_contract.toml` |
| `✦` | **Enumerate-Surface** | "Is every `pub` item / every dispatched opcode / every command / every public-API symbol on both sides accounted for, with `present|partial|missing|n/a|excluded`?" | [taxonomy/FEATURE-UNIVERSE.md](references/taxonomy/FEATURE-UNIVERSE.md) |
| `◐` | **Wire-Oracle** | "Does the subject have an in-process or stable subprocess bridge to the pinned reference, with `EngineIdentity` to prevent self-comparison?" | [tooling/ORACLE-TOOLCHAIN.md](references/tooling/ORACLE-TOOLCHAIN.md) |
| `⬡` | **Instrument-Hot-Path** | "Does this hot loop have a counter ≥ 0.1% self-time that would attribute a regression to a specific frame?" | [tooling/BENCH-TOOLCHAIN.md § HotPathProfileSnapshot](references/tooling/BENCH-TOOLCHAIN.md) |
| `⚠` | **Escalate-To-Fresh-Repro** | "If this only reproduces on my workstation, does the FailureBundle have the seed, schedule fingerprint, exact repro command, and platform fingerprint?" | [methodology/IDENTITY-AND-REPRODUCIBILITY.md](references/methodology/IDENTITY-AND-REPRODUCIBILITY.md) |
| `⊕` | **Isomorphic-Rewrite** | "What are 2+ behavior-preserving rewrites for this code path, and what does each cost on the rubric?" | [remediation/REMEDIATION-PATTERNS.md](references/remediation/REMEDIATION-PATTERNS.md) |
| `⊙` | **Debounce-False-Positive** | "Is this divergence classified as `TrueDivergence` or as one of the 5 known classes (Order / TypeAffinity / NullHandling / FloatingPoint / FalsePositive)?" | [tooling/ORACLE-TOOLCHAIN.md § MismatchClassification](references/tooling/ORACLE-TOOLCHAIN.md) |
| `⊞` | **Soak** | "Has this been run for the soak duration (24h fuzz / multi-day miri / multi-thousand-iter loom-shuttle / multi-day BOCPD)?" | [methodology/SOAK-PROTOCOL.md](references/methodology/SOAK-PROTOCOL.md) |
| `⌘` | **Reduce / Minimize** | "Has this failure been reduced to its delta-debugged minimum with schema-preservation guard?" | [tooling/ORACLE-TOOLCHAIN.md § mismatch-minimizer](references/tooling/ORACLE-TOOLCHAIN.md) |
| `⟁` | **Triangulate-Profile** | "Do flamegraph + samply + dhat + strace agree on the attribution, or is one source disagreeing?" | [tooling/BENCH-TOOLCHAIN.md § triangulation](references/tooling/BENCH-TOOLCHAIN.md) |
| `⤴` | **Attribute-To-MT8** | "Does this kept perf win name a specific profile frame ≥0.1% self-time, with a quoted citation?" | [methodology/KEEP-GATE-RULES.md § MT8](references/methodology/KEEP-GATE-RULES.md) |
| `🔁` | **Pass-Over-Pass-Gate** | "Have both the focused and broad gates moved in the same run window (same git state, same `target/`, same machine, same minute)?" | [methodology/KEEP-GATE-RULES.md](references/methodology/KEEP-GATE-RULES.md) |
| `⚖` | **Ratchet-Lower-Bound** | "Does the proposed change raise the conformal LOWER bound on parity score without lowering any per-category bound?" | [methodology/CONFORMAL-RATCHET.md](references/methodology/CONFORMAL-RATCHET.md) |
| `🪟` | **Fresh-Eyes** | "Have the three calibrated fresh-eyes prompts run against this code? Has the round come up clean twice?" | [PHASES.md § Phase 14](references/PHASES.md) |
| `🗄` | **Ledger-Retire** | "Does this ledger entry name a concrete retry-condition predicate (not 'later', not 'if it seems important')?" | [methodology/RETRY-CONDITION-VOCABULARY.md](references/methodology/RETRY-CONDITION-VOCABULARY.md) |
| `🧪` | **Experiment-Design** | "Does this suspected gap have a hypothesis-minimal-repro-expected-signal-falsifiability-one-line-invocation-results-inline entry in the appropriate ledger?" | [experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](references/experiments/EXPERIMENT-DESIGNS-TEMPLATE.md) |
| `📐` | **Conformal-Band** | "Does the release decision use the distribution-free conformal LOWER bound and not the point estimate?" | [methodology/CONFORMAL-RATCHET.md](references/methodology/CONFORMAL-RATCHET.md) |
| `🎚` | **Raise-ULP-Tolerance** | "Has the ULP tolerance change been justified, scoped to the operator, and accompanied by a `gradcheck_max_rel_error` snapshot?" | [taxonomy/PROJECT-CLASSES.md § Numerical / ML](references/taxonomy/PROJECT-CLASSES.md) |
| `🪞` | **Engine-Identity-Guard** | "Does every emitted artifact have `EngineIdentity::{Subject,Oracle}` set and asserted-distinct at the comparator?" | [tooling/ORACLE-TOOLCHAIN.md § EngineIdentity](references/tooling/ORACLE-TOOLCHAIN.md) |

Each glyph carries a verbatim quote-bank anchor from FrankenSQLite session history (Track A `/operationalizing-expertise` style). The library is deliberately overlapping — a single perf candidate typically deserves four or five. Paste-ready 1-page wall reference: **[assets/operator-cheatsheet.md](assets/operator-cheatsheet.md)**.

---

## Pattern Library (Numbered, Step-of-5)

The gauntlet's reproducible disciplines are organized as a numbered pattern library — every pattern is its own file at `references/patterns/NN-NAME.md`, numbered in step-of-5 so future insertions don't churn IDs. Each pattern file follows the same shape: **What** / **Why** (verbatim quote) / **Where in FrankenSQLite** / **Verbatim shape** / **Per-class instantiation** / **Composition** / **Pitfalls**. Full inventory + structure: **[patterns/00-INDEX.md](references/patterns/00-INDEX.md)**.

| Family | Range | Pillar | Examples |
|---|---|---|---|
| Kernel | 00-095 | all + conformance | [05 Subject/Oracle/Comparator](references/patterns/05-SUBJECT-ORACLE-COMPARATOR.md), [30 Differential V2](references/patterns/30-DIFFERENTIAL-V2-ENVELOPE.md), [70 E-processes](references/patterns/70-E-PROCESSES.md), [75 Bayesian Conformal](references/patterns/75-BAYESIAN-CONFORMAL-SCORE.md) |
| Surface | 100-120 | surface | [105 FeatureUniverse](references/patterns/105-FEATURE-UNIVERSE.md), [110 InvariantCatalog](references/patterns/110-INVARIANT-CATALOG.md), [115 Closure-Wave](references/patterns/115-CLOSURE-WAVE.md) |
| Performance | 125-175 | perf | [125 comprehensive-bench](references/patterns/125-COMPREHENSIVE-BENCH.md), [150 Profile-First Card](references/patterns/150-PROFILE-FIRST-CARD.md), [160 MT8 Attribution](references/patterns/160-MT8-ATTRIBUTION.md) |
| Negative-evidence | 180-195 | all | [180 Negative Ledger](references/patterns/180-NEGATIVE-LEDGER.md), [185 Retry-Condition Predicate](references/patterns/185-RETRY-CONDITION-PREDICATE.md) |
| 10 winning optimizations | 200-245 | perf | [200 Hot-opcode promotion](references/patterns/200-HOT-OPCODE-PROMOTION.md), [205 AtomicBool empty gate](references/patterns/205-ATOMIC-BOOL-EMPTY-GATE.md), [245 Cache-key eviction audit](references/patterns/245-CACHE-KEY-EVICTION-AUDIT.md) |
| Cross-cutting | 250-260 | all | [250 Isomorphism Proof](references/patterns/250-ISOMORPHISM-PROOF.md), [255 rch offload](references/patterns/255-RCH-OFFLOAD-DISCIPLINE.md) |

Beads reference patterns by ID prefix: `pattern:NN-NAME` as the bead title so the graph stays grep-able. Future agents add new patterns at the next free slot (e.g., `42-…` between 40 and 45) without renumbering siblings.

---

## Keep-Gate Rules (Non-Negotiable for Perf Claims)

Every kept perf change must satisfy ALL of:

| Rule | Test |
|---|---|
| **Profile-first** | Hotspot evidence ≥0.1% self-time exists in `artifacts/{bead_id}/proof_pack/baseline_profile.{flame.svg,samply.json}` BEFORE any source touch. |
| **Both gates move in same run window** | Focused bench + broad bench JSON both committed from the same git state, same `target/`, same machine, same minute. |
| **`release-perf` profile** | Never `--release` (size-optimized). The `release-perf` profile inherits release with `opt-level=3, lto="thin", codegen-units=1, debug="line-tables-only", strip=false, RUSTFLAGS="-C force-frame-pointers=yes"`. |
| **`concurrent_mode_default_guard.txt` equivalent** | Per-project feature-defining-mode-default proof file dropped into every artifact lane. |
| **Symmetric retry shells** | Both engines wrapped in identical retry shells of identical framework cost, even if one engine doesn't structurally need the retry. |
| **Identical PRAGMAs / config** | Reference-side and subject-side PRAGMAs / config / pool sizes byte-identical (modulo project-specific feature flags whose default state is the proof file). |
| **`selections=` byte-identical** | When both engines emit a counter, the counter values match exactly between runs that should be byte-identical. |
| **cv_pct reported** | Every microbench result reports the coefficient of variation; if `cv_pct > 5`, the result is noise and not eligible for keep. |
| **MT8 attribution** | The kept win names a specific frame ≥0.1% self-time (e.g., "Closed 0.44% MT8 PublishedPages::clear residual"). Below 0.1% is the **micro-lever trap**. |
| **Pass-over-pass ratchet** | `.bench-history/<bench>.latest.json` committed; new run within the gate thresholds (primary `−3%`, geomean `−5%`, per-category `−10%`, p90 `−15%`, throughput `−5%`). |

Full keep-gate playbook with the FrankenSQLite vocabulary glossary (keep gate / within noise / fresh-eyes pass / scratch worktree / correctness-abandoned / focused vs broad gate / behavior-preserving / fused-design target / DML mutation operator / hot path / cold start / MT8 attribution / micro-lever / frontier / refresh / durable infra / pulled the pin): **[methodology/KEEP-GATE-RULES.md](references/methodology/KEEP-GATE-RULES.md)**.

---

## Negative-Ledger Mandate (AGENTS.md Paragraph)

Every long-running perf operation MUST grep the three ledgers (`docs/progress/perf-negative-results.md`, `conformance-negative-results.md`, `surface-deferrals.md`) first, mine 60 days of cass skill / cass CLI session history for failure terms (`rejected, reverted, abandoned, slower, regressed, didn't help, within noise, no improvement, failed to improve, rolled back, backed out, not a keep, keep gate`, plus the project-specific terms from [taxonomy/PROJECT-CLASSES.md § failure-terms](references/taxonomy/PROJECT-CLASSES.md)), and check recent commits before starting work. If `cass` or the ledger is unavailable, **record a blocker entry rather than silently skipping**.

`scripts/mine-ledger.sh` and `scripts/mine-cass-cross-machine.sh` (invokes cass on local + css + csd + ts1 + ts2 per the cass skill's Cross-Machine Search section) implement this check. Both are called by every perf-bead pre-flight.

Mandatory negative-ledger entry fields (load-bearing **retry-condition predicate**, never "later", never "if it seems important"): **[methodology/RETRY-CONDITION-VOCABULARY.md](references/methodology/RETRY-CONDITION-VOCABULARY.md)**. Per-failure-class cass-mining recipes: **[methodology/CASS-MINING.md](references/methodology/CASS-MINING.md)**.

---

## Verification-First (For Volatile Facts)

Mined-from-bible facts are point-in-time. Some are evergreen (the kernel axioms, the operator library, the 30-line `scenario()` template); others are volatile per-reference-version (the exact PRAGMA list for `sqlite-3.52.0`, the exact COMMAND COUNT for `redis-7.2.5`, the exact per-op ULP tolerances for `torch-2.X.Y`). Rule: do not stake a release claim on a volatile fact UNTIL it has been verified against live primary sources AND logged in `<workspace>/provider_audit_log.md`.

Per-class verification checklists + audit log schema + the "back-off vs proceed" decision tree: **[methodology/VERIFICATION-FIRST.md](references/methodology/VERIFICATION-FIRST.md)**.

---

## Source Corpus (Track A from operationalizing-expertise)

This skill IS a Track A artifact per `/operationalizing-expertise`. The complete corpus + distillation chain:

- **Corpus**: the two FrankenSQLite bibles + the per-pillar mining extracts at `/data/tmp/gauntlet-skill-mining/MINING-{1,2,3}-*.md`.
- **Quote bank**: 50+ tagged anchors in **[exemplars/EXEMPLARS.md § Quote Bank](references/exemplars/EXEMPLARS.md)**.
- **Triangulated kernel**: the 12 K-N axioms in **[methodology/KERNEL.md](references/methodology/KERNEL.md)** (paste-ready: **[assets/cc-axioms.md](assets/cc-axioms.md)**).
- **Operator library**: 19 cognitive moves in **[methodology/OPERATORS.md](references/methodology/OPERATORS.md)**.
- **Pattern library**: 54 numbered patterns under **[references/patterns/](references/patterns/00-INDEX.md)**.
- **Validators**: 34 scripts in `scripts/` + 4 syn-walkers + 6 ast-grep YAMLs.

Extending the corpus (adding quotes, axioms, operators, patterns): **[methodology/SOURCE-CORPUS.md](references/methodology/SOURCE-CORPUS.md)**.

---

## The Polish Bar (Non-Negotiable)

| Dimension | Test |
|---|---|
| **Reference pinning** | `<reference>_version_contract.toml` exists; every artifact embeds the contract hash. |
| **EngineIdentity** | Every comparator output carries `Subject::<port>` and `Oracle::<reference>`; asserted-distinct at the comparator. |
| **Three-tier equivalence** | Golden artifacts label themselves Tier 1 byte / Tier 2 canonical / Tier 3 logical; never paper over the distinction. |
| **First-divergence jsonptr** | Every conformance failure has `/failure/first_divergence` populated. |
| **FailureBundle with provenance** | Every E2E failure emits a `FailureBundle v1.0.0` with seed + fixture id + schedule fingerprint + exact repro command + state snapshots + diff hints + environment. "A partial bundle with provenance is more valuable than no bundle." |
| **E-processes for hardware invariants** | Hardware-enforced invariants get `p₀=1e-9, λ=0.999, α=1e-6`; software-enforced get `p₀=1e-6, λ=0.9, α=0.001`; global e-value via arithmetic mean (conservative under dependence); Ville's-inequality anytime-valid rejection. |
| **Conformal lower-bound for release** | Beta posterior per category × pass rate; distribution-free conformal band; release decisions use LOWER bound, not point estimate; `truncate_score` to 6 decimal places. |
| **FeatureUniverse weight invariant** | `sum(weights) == 1.0 per category` enforced by the loader; deterministic iteration order by FeatureId. |
| **Excluded-as-debt** | Excluded items still count as coverage debt for a strict-100% claim. |
| **Verification-contract enforcement** | A bead cannot close with weak evidence (`pass | fail-missing-evidence | fail-invalid-references | fail-mixed` × `allowed | blocked-by-base-gate | blocked-by-contract | blocked-by-both`). |
| **Negative-ledger entry per rejected candidate** | Mandatory fields including retry-condition predicate. |

Full rubric + per-pillar checklists + verification queries: **[methodology/KERNEL.md](references/methodology/KERNEL.md)**.

---

## Anti-Patterns (Never Do)

| ✗ | Why | Fix |
|---|---|---|
| Cherry-picked baseline | The kept win evaporates next pass | Baseline = `.bench-history/<bench>.latest.json` committed to git, period. |
| "It works on my machine" perf claim | Different host = different ratio | Pin the placement profile (`baseline_unpinned | recommended_pinned | adversarial_cross_node`); both gates same minute. |
| Population inside timed window | Free win disappears under realistic load | `measure_with_teardown` teardown call is OUTSIDE `start.elapsed()`. |
| Agreement-by-error-message-string | Two engines failing differently look "agreed" | Both-error = agreement REGARDLESS of message; one-error-one-OK = hard failure. |
| Oracle compared against itself | Apparent 100% pass rate | `EngineIdentity` discriminator + oracle preflight doctor checks subject ≠ oracle identity strings. |
| Size-optimized release profile for perf | LTO and codegen-units differences swamp the signal | `release-perf` profile mandatory; never `--release`. |
| Concurrent mode silently off | "MVCC perf win" was running serial | `concurrent_mode_default_guard.txt` (or project-equivalent) in every artifact lane. |
| `cv_pct` dropped from report | Noise looks like signal | Every microbench reports `cv_pct`; `>5%` is noise. |
| Flake masquerading as throughput win | Once-in-five-runs result becomes "the new baseline" | Pass-over-pass on `.bench-history` + median + MAD detector. |
| "We should be aware of recent research" without a queue | Discovery dies in the chat scrollback | Every clever idea lands in `GAUNTLET_EXPERIMENT_DESIGNS.md` with hypothesis-minimal-repro-expected-signal-falsifiability-one-line-invocation. |
| Communication purgatory | Agents wait on each other forever | MCP Agent Mail thread IDs per phase; no synchronous "are you done yet" reads. |
| Tidying up other agents' edits | Destroys parallel work | Treat unfamiliar changes as your own; never stash / revert / overwrite other agents' work. |
| Reading entire file instead of grep-first | Wastes context | `rg` to shortlist, `ast-grep` for AST shape, Read only the lines you need. |
| Hallucinating a function that doesn't exist | Skill recommendations rot | Before recommending a file/function/flag, grep for it. |
| Writing prose where structured table is required | Downstream consumers can't parse | Robot-emitting commands always emit machine-readable JSON; the markdown is the human view. |
| Running bare `cass` / `bv` / `cargo bench` / `cargo test --workspace` in automated session | TUIs block; full-workspace runs hammer the host | `cass --robot`, `bv --robot-*`, `cargo bench --bench <one>`, `cargo test -p <one-crate>`. |

Full catalog with the bead trail for each: **[methodology/ANTI-PATTERNS.md](references/methodology/ANTI-PATTERNS.md)**.

---

## Cookbook (Operator Pipelines for Recurring Motions)

When a maintainer (or future agent) hits one of the gauntlet's recurring situations — a perf regression, an oracle divergence, a cv_pct flake, an e-process rejection, a BOCPD shift, a ratchet block — the cookbook gives a paste-ready operator pipeline + literal scripts + bead-naming convention so the response is 10 minutes rather than 2 hours.

The 12 default motions:

1. `perf-regression-triage` — "Pass-over-pass shows -X% on a primary score. Recipe?"
2. `oracle-divergence-triage` — "An oracle test went red. Procedure?"
3. `surface-gap-found` — "FeatureUniverse reports a Missing entry. How to close?"
4. `cv_pct-flake` — "A microbench cv_pct went above 5%. Quarantine vs fix?"
5. `e-process-rejection` — "INV-X e-value crossed 1/α. Response?"
6. `bocpd-shift-detected` — "Regime became ShiftDetected mid-soak. Investigate."
7. `ratchet-block` — "apply-ratchet.sh emitted Block. Waive vs fix vs revert?"
8. `mt8-attribution-flat` — "No frame ≥0.1% — saturated easy gains. Next?"
9. `dependency-version-bump` — "Reference version bumped. Re-run scope decision."
10. `new-fault-class-discovered` — "A new FaultKind reproduces a real failure."
11. `cross-pillar-regression` — "Fixing perf lowered conformance. Waive vs redesign?"
12. `fresh-onboardee-needs-trust-tier-up` — "Onboardee passed week 4. Next?"

Cookbook is generated per-project by the `cookbook-author` subagent and lives at `<workspace>/cookbook/<motion-slug>.md`. Each entry: trigger + operator pipeline + literal scripts + beads to claim + exit criteria + anti-pattern callouts + cross-references.

---

## Final Artifacts (Phase 16)

The skill produces three load-bearing documents + the polished bead graph + the certification bundle:

1. **`FINAL_GAUNTLET_REPORT.md`** — executive summary; full findings table with severity; per-pillar remediation plan; unresolved-but-deferred list with retry-condition predicates; convergence-evidence appendix (round-by-round new-findings counts proving the loop converged); certification-bundle manifest.
2. **`PARITY_RUNBOOK.md`** — for the project maintainers, how to keep the port at parity going forward: which CI gates to wire, which insta snapshots to keep green, which fuzz corpora to preserve, which `// SAFETY:` template to apply, which Clippy lint group is bare minimum, the AGENTS.md mandate paragraph + failure-term list, the negative-ledger format + retry-condition vocabulary.
3. **`RELEASE_CERTIFICATION_TEMPLATE.md`** — strict-conformant-release.v1 template: required-pass constants (`CERTIFICATION_MIN_VERIFICATION_PCT = 100.0`, `CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT = 100.0`, `CERTIFICATION_MAX_HIGH_SEVERITY_COUNTEREXAMPLES = 0`, `CERTIFICATION_MAX_EVIDENCE_AGE_HOURS = 24`); evidence-bundle classes; gate/ratchet spec; persisted baseline.
4. **Polished bead graph** — every remediation bead has a test-bead dependency AND a benchmark-bead dependency AND a documentation-bead dependency; `br dep cycles --json | jq '(.cycles // []) | length == 0'` passes; `bv --robot-insights | jq '(.Cycles // []) | length == 0'` passes.
5. **Certification bundle** — confidence gate JSON, verification contract JSON, release certificate JSON, CI artifact manifest, benchmark summary, `scorecards.json`, critical-path report, ratchet state.

---

## Reference Index

### Core playbooks
| Need | File |
|------|------|
| 16-phase playbook with inputs / outputs / exit criteria / parallelism / coordination thread IDs | [PHASES.md](references/PHASES.md) |
| Verbatim agent prompts per subagent | [AGENT-PROMPTS.md](references/AGENT-PROMPTS.md) |
| Three-pillar decomposition + per-pillar success criteria + gating rules | [THREE-PILLARS.md](references/THREE-PILLARS.md) |

### Methodology
| Need | File |
|------|------|
| Universal axioms (Subject/Oracle/Comparator; honesty in the harness; negative evidence first-class; both gates same run window; truncate_score; BEAD_ID + SCHEMA_VERSION) | [methodology/KERNEL.md](references/methodology/KERNEL.md) |
| Cognitive operators with glyphs (full card library; triggers, failure modes, prompt modules) | [methodology/OPERATORS.md](references/methodology/OPERATORS.md) |
| Keep-gate discipline + perf vocabulary glossary | [methodology/KEEP-GATE-RULES.md](references/methodology/KEEP-GATE-RULES.md) |
| Retry-condition predicate templates with examples mined from the 380-entry FrankenSQLite ledger | [methodology/RETRY-CONDITION-VOCABULARY.md](references/methodology/RETRY-CONDITION-VOCABULARY.md) |
| Convergence math (round-over-round counts; 10-round minimum; 2-consecutive-clean rule; open-hypothesis resolution) | [methodology/CONVERGENCE.md](references/methodology/CONVERGENCE.md) |
| Bayesian + conformal scoring (Beta posterior + distribution-free band + lower-bound ratchet + truncate_score) | [methodology/CONFORMAL-RATCHET.md](references/methodology/CONFORMAL-RATCHET.md) |
| Run identity stack + reproducibility contract | [methodology/IDENTITY-AND-REPRODUCIBILITY.md](references/methodology/IDENTITY-AND-REPRODUCIBILITY.md) |
| Soak protocol (24h fuzz / multi-day miri / multi-thousand-iter loom-shuttle / multi-day BOCPD / adversarial-search) | [methodology/SOAK-PROTOCOL.md](references/methodology/SOAK-PROTOCOL.md) |
| Strict-conformant-release.v1 certification template + required-pass constants | [methodology/CERTIFICATION.md](references/methodology/CERTIFICATION.md) |
| Anti-pattern catalog with bead trails | [methodology/ANTI-PATTERNS.md](references/methodology/ANTI-PATTERNS.md) |
| Mode router (11 modes: gauntlet-full / gauntlet-greenfield / audit-only / harden-pillar / add-feature / incremental-rebase / compliance-pass / red-team / migration / cass-mine-only / quick-smoke) | [methodology/MODE-ROUTER.md](references/methodology/MODE-ROUTER.md) |
| Tier triage (T1-T5 engagement sizing + complexity overlays) | [methodology/TIER-TRIAGE.md](references/methodology/TIER-TRIAGE.md) |
| Per-mode verbatim kickoff prompts | [methodology/KICKOFF-PROMPTS.md](references/methodology/KICKOFF-PROMPTS.md) |
| Verification-first protocol (evergreen vs volatile facts; live-source audit log) | [methodology/VERIFICATION-FIRST.md](references/methodology/VERIFICATION-FIRST.md) |
| Cass-mining recipes per failure class (60-day cross-machine search) | [methodology/CASS-MINING.md](references/methodology/CASS-MINING.md) |
| Multi-model triangulation prompts (Codex / Gemini / Grok / Claude) | [methodology/TRIANGULATION.md](references/methodology/TRIANGULATION.md) |
| Per-sibling case studies (recommended mode + likely findings + tier) | [methodology/CASE-STUDIES.md](references/methodology/CASE-STUDIES.md) |
| Inline fallback prompts for every helper skill | [methodology/SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md) |
| Optional Claude Code hooks (pre-commit / pre-push / UserPromptSubmit / Stop) | [methodology/HOOKS-INTEGRATION.md](references/methodology/HOOKS-INTEGRATION.md) |
| Source corpus structure (Track A from operationalizing-expertise) | [methodology/SOURCE-CORPUS.md](references/methodology/SOURCE-CORPUS.md) |
| Compact alphabetical glossary of every term-of-art | [methodology/GLOSSARY.md](references/methodology/GLOSSARY.md) |
| Per-phase + per-bead exit criteria + per-pillar release-readiness | [methodology/DEFINITION-OF-DONE.md](references/methodology/DEFINITION-OF-DONE.md) |
| 13-artifact proof-pack rubric + 12-question reviewer checklist | [methodology/PROOF-PACK-RUBRIC.md](references/methodology/PROOF-PACK-RUBRIC.md) |
| 6-dimension universal candidate scoring rubric + per-pillar gates | [methodology/RUBRICS.md](references/methodology/RUBRICS.md) |
| MEMORY.md + session_*.md convention (per /flywheel) | [methodology/MEMORY-MD-CONVENTION.md](references/methodology/MEMORY-MD-CONVENTION.md) |
| 5-layer compaction-survival contract | [methodology/COMPACTION-SURVIVAL.md](references/methodology/COMPACTION-SURVIVAL.md) |
| Pinned directory layout for `<project>__gauntlet_workspace/` | [methodology/WORKSPACE-LAYOUT.md](references/methodology/WORKSPACE-LAYOUT.md) |
| Phase-output JSON schemas + bump policy | [methodology/PHASE-OUTPUT-SCHEMAS.md](references/methodology/PHASE-OUTPUT-SCHEMAS.md) |
| Per-helper-skill integration + bootstrap priority order | [methodology/INTEGRATION-WITH-HELPER-SKILLS.md](references/methodology/INTEGRATION-WITH-HELPER-SKILLS.md) |
| Verbatim 3 Phase-14 fresh-eyes prompts (a, b, c) | [methodology/FRESH-EYES-PROMPTS.md](references/methodology/FRESH-EYES-PROMPTS.md) |
| Deep hypothesis review — review kernel + operator algebra + escalation path for Phase 10/11/14 | [methodology/DEEP-HYPOTHESIS-REVIEW.md](references/methodology/DEEP-HYPOTHESIS-REVIEW.md) |
| Greenfield adaptation — 5-mode Oracle for novel non-port Rust projects (Spec / Property / Self / Round-trip / External-tool) | [methodology/GREENFIELD-ADAPTATION.md](references/methodology/GREENFIELD-ADAPTATION.md) |
| Spec pinning for greenfield (Phase 2 variant) — `spec_version_contract.toml` schema + `[SPEC-NNN]` tag extraction | [methodology/SPEC-PINNING-FOR-GREENFIELD.md](references/methodology/SPEC-PINNING-FOR-GREENFIELD.md) |
| 8 decision trees (mode selection, project class, pattern lookup, deep-review escalation, greenfield Oracle modes, single-crate vs workspace, loop-back or proceed, waiver vs fix) | [methodology/DECISION-TREES.md](references/methodology/DECISION-TREES.md) |
| Monitoring + dashboards — 3-layer viewer architecture (terminal-native / markdown-tracker / Prometheus+Grafana) + per-event signal table + notification routing | [methodology/MONITORING-AND-DASHBOARDS.md](references/methodology/MONITORING-AND-DASHBOARDS.md) |

### Pattern Library (numbered, step-of-5)
| Need | File |
|------|------|
| Full pattern index + family table + composition rules | [patterns/00-INDEX.md](references/patterns/00-INDEX.md) |

Per-pillar pattern entry points (see `patterns/00-INDEX.md` for the full 54-file table):
- **Conformance kernel**: [05 Subject/Oracle/Comparator](references/patterns/05-SUBJECT-ORACLE-COMPARATOR.md) → [30 Differential V2](references/patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) → [40 Metamorphic Transforms](references/patterns/40-METAMORPHIC-TRANSFORMS.md) → [70 E-processes](references/patterns/70-E-PROCESSES.md) → [75 Bayesian Conformal Score](references/patterns/75-BAYESIAN-CONFORMAL-SCORE.md)
- **Performance kernel**: [125 comprehensive-bench](references/patterns/125-COMPREHENSIVE-BENCH.md) → [135 measure_with_teardown](references/patterns/135-MEASURE-WITH-TEARDOWN.md) → [150 Profile-First Card](references/patterns/150-PROFILE-FIRST-CARD.md) → [155 Bench-History Ratchet](references/patterns/155-BENCH-HISTORY-RATCHET.md) → [160 MT8 Attribution](references/patterns/160-MT8-ATTRIBUTION.md)
- **Surface kernel**: [105 FeatureUniverse](references/patterns/105-FEATURE-UNIVERSE.md) → [110 Invariant Catalog](references/patterns/110-INVARIANT-CATALOG.md) → [115 Closure-Wave](references/patterns/115-CLOSURE-WAVE.md) → [120 Verification Contract](references/patterns/120-VERIFICATION-CONTRACT.md)
- **Negative evidence**: [180 Negative Ledger](references/patterns/180-NEGATIVE-LEDGER.md) → [185 Retry-Condition Predicate](references/patterns/185-RETRY-CONDITION-PREDICATE.md) → [190 Cass Mining](references/patterns/190-CASS-MINING.md)
- **10 winning optimizations**: [200 Hot-Opcode Promotion](references/patterns/200-HOT-OPCODE-PROMOTION.md) through [245 Cache-Key Eviction Audit](references/patterns/245-CACHE-KEY-EVICTION-AUDIT.md)

### Taxonomy
| Need | File |
|------|------|
| Per-class instantiations (SQL / RESP / Numerical-Python / ML-System / HTTP-Protocol) | [taxonomy/PROJECT-CLASSES.md](references/taxonomy/PROJECT-CLASSES.md) |
| FeatureUniverse design + weight-normalization + truncate_score + iteration order | [taxonomy/FEATURE-UNIVERSE.md](references/taxonomy/FEATURE-UNIVERSE.md) |
| ProofObligation taxonomy + ArtifactRef contract | [taxonomy/INVARIANT-CATALOG.md](references/taxonomy/INVARIANT-CATALOG.md) |

### Tooling
| Need | File |
|------|------|
| criterion / hyperfine / flamegraph / samply / dhat / heaptrack / strace / fio invocations with pitfalls | [tooling/BENCH-TOOLCHAIN.md](references/tooling/BENCH-TOOLCHAIN.md) |
| rusqlite / PyO3 / subprocess-RESP / HTTP-replay invocations + oracle preflight doctor | [tooling/ORACLE-TOOLCHAIN.md](references/tooling/ORACLE-TOOLCHAIN.md) |
| cargo-fuzz / cargo-afl / arbitrary / bolero with differential-fuzz example targets | [tooling/FUZZ-TOOLCHAIN.md](references/tooling/FUZZ-TOOLCHAIN.md) |
| loom / shuttle / asupersync-LabRuntime / DPOR with 9-class deadlock taxonomy | [tooling/CONCURRENCY-TOOLCHAIN.md](references/tooling/CONCURRENCY-TOOLCHAIN.md) |
| ASan / TSan / MSan / LSan nightly-only flags + env-var matrix | [tooling/SANITIZER-TOOLCHAIN.md](references/tooling/SANITIZER-TOOLCHAIN.md) |
| ast-grep / semgrep / cargo-geiger / cargo-deny / cargo-audit / cargo-expand / syn-walkers / cargo doc --document-private-items | [tooling/STATIC-TOOLCHAIN.md](references/tooling/STATIC-TOOLCHAIN.md) |

### Experiments
| Need | File |
|------|------|
| Experiment-design template (hypothesis / repro / expected-signal / falsifiability / one-line-invocation / results-inline) | [experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](references/experiments/EXPERIMENT-DESIGNS-TEMPLATE.md) |
| Worked perf experiments from FrankenSQLite artifact lanes | [experiments/EXAMPLE-EXPERIMENTS-PERF.md](references/experiments/EXAMPLE-EXPERIMENTS-PERF.md) |
| Worked conformance experiments | [experiments/EXAMPLE-EXPERIMENTS-CONFORMANCE.md](references/experiments/EXAMPLE-EXPERIMENTS-CONFORMANCE.md) |
| Worked surface experiments | [experiments/EXAMPLE-EXPERIMENTS-SURFACE.md](references/experiments/EXAMPLE-EXPERIMENTS-SURFACE.md) |

### Cookbook (12 motion recipes)
| Need | File |
|------|------|
| Recipe index | [cookbook/INDEX.md](references/cookbook/INDEX.md) |
| Perf regression triage motion | [cookbook/perf-regression-triage.md](references/cookbook/perf-regression-triage.md) |
| Oracle divergence triage motion | [cookbook/oracle-divergence-triage.md](references/cookbook/oracle-divergence-triage.md) |
| Surface gap closure motion | [cookbook/surface-gap-found.md](references/cookbook/surface-gap-found.md) |
| cv_pct flake quarantine motion | [cookbook/cv-pct-flake.md](references/cookbook/cv-pct-flake.md) |
| E-process rejection motion | [cookbook/e-process-rejection.md](references/cookbook/e-process-rejection.md) |
| BOCPD shift-detected motion | [cookbook/bocpd-shift-detected.md](references/cookbook/bocpd-shift-detected.md) |
| Ratchet block motion (waive vs fix vs revert) | [cookbook/ratchet-block.md](references/cookbook/ratchet-block.md) |
| MT8 attribution flat motion (saturated easy gains) | [cookbook/mt8-attribution-flat.md](references/cookbook/mt8-attribution-flat.md) |
| Dependency version bump motion | [cookbook/dependency-version-bump.md](references/cookbook/dependency-version-bump.md) |
| New fault class discovered motion | [cookbook/new-fault-class-discovered.md](references/cookbook/new-fault-class-discovered.md) |
| Cross-pillar regression motion (perf↓ + conformance↑) | [cookbook/cross-pillar-regression.md](references/cookbook/cross-pillar-regression.md) |
| Onboardee trust-tier-up motion | [cookbook/fresh-onboardee-trust-tier-up.md](references/cookbook/fresh-onboardee-trust-tier-up.md) |
| Spec-source contradiction detected (greenfield Phase 2 blocker) | [cookbook/spec-conflict-detected.md](references/cookbook/spec-conflict-detected.md) |
| Single-crate vs workspace decision (Phase 3 layout call) | [cookbook/single-crate-vs-workspace-decision.md](references/cookbook/single-crate-vs-workspace-decision.md) |
| Spec-tag orphan cleanup (retire-or-implement orphan tags + orphan verifiers) | [cookbook/spec-tag-orphan-cleanup.md](references/cookbook/spec-tag-orphan-cleanup.md) |
| Six-month soak revival (restarting on a port idle ≥6 months) | [cookbook/six-month-soak-revival.md](references/cookbook/six-month-soak-revival.md) |
| Cross-architecture determinism failure (x86 vs ARM LSB cascade) | [cookbook/cross-architecture-determinism-failure.md](references/cookbook/cross-architecture-determinism-failure.md) |
| Insta-snapshot explosion (200+ snapshots after refactor) | [cookbook/insta-snapshot-explosion.md](references/cookbook/insta-snapshot-explosion.md) |
| Embedding-cache staleness diagnostic (eidetic-class + any semantic-embedding cache) | [cookbook/embedding-cache-staleness.md](references/cookbook/embedding-cache-staleness.md) |
| Asupersync cancel leak (custom async runtime cancel-correctness) | [cookbook/asupersync-cancel-leak.md](references/cookbook/asupersync-cancel-leak.md) |

### Per-sibling case studies (12 deep dives)
| Need | File |
|------|------|
| FrankenSQLite (T4, SQL) | [case-studies/frankensqlite.md](references/case-studies/frankensqlite.md) |
| FrankenRedis (T3, RESP) | [case-studies/frankenredis.md](references/case-studies/frankenredis.md) |
| FrankenTorch (T4, ML) | [case-studies/frankentorch.md](references/case-studies/frankentorch.md) |
| FrankenJAX (T4, ML) | [case-studies/frankenjax.md](references/case-studies/frankenjax.md) |
| franken_numpy (T3, Numerical) | [case-studies/franken_numpy.md](references/case-studies/franken_numpy.md) |
| FrankenPandas (T4, Numerical) | [case-studies/frankenpandas.md](references/case-studies/frankenpandas.md) |
| FrankenSciPy (T3, Numerical) | [case-studies/frankenscipy.md](references/case-studies/frankenscipy.md) |
| franken_networkx (T3, Numerical) | [case-studies/franken_networkx.md](references/case-studies/franken_networkx.md) |
| fastapi_rust (T3, HTTP) | [case-studies/fastapi_rust.md](references/case-studies/fastapi_rust.md) |
| fastmcp_rust (T3, HTTP/MCP) | [case-studies/fastmcp_rust.md](references/case-studies/fastmcp_rust.md) |
| sqlmodel_rust (T2, SQL/ORM) | [case-studies/sqlmodel_rust.md](references/case-studies/sqlmodel_rust.md) |
| franken_whisper (T3, ML) | [case-studies/franken_whisper.md](references/case-studies/franken_whisper.md) |
| **eidetic_engine_cli (T3, Greenfield-Rust-class)** — canonical worked example of running the gauntlet on a novel non-port Rust project | [case-studies/eidetic_engine_cli.md](references/case-studies/eidetic_engine_cli.md) |

### First-bug-hunt recipes (per class)
| Need | File |
|------|------|
| SQL-class — 10 highest-yield bug classes | [first-bug-hunt/sql-class.md](references/first-bug-hunt/sql-class.md) |
| RESP-class — 10 highest-yield bug classes | [first-bug-hunt/resp-class.md](references/first-bug-hunt/resp-class.md) |
| Numerical-Python-class | [first-bug-hunt/numerical-python-class.md](references/first-bug-hunt/numerical-python-class.md) |
| ML-System-class | [first-bug-hunt/ml-system-class.md](references/first-bug-hunt/ml-system-class.md) |
| HTTP-Protocol-class | [first-bug-hunt/http-protocol-class.md](references/first-bug-hunt/http-protocol-class.md) |
| **Greenfield-Rust-class (eidetic-shape)** — 10 highest-yield bug classes specific to novel non-port Rust projects | [first-bug-hunt/greenfield-rust-class.md](references/first-bug-hunt/greenfield-rust-class.md) |

### Math worked examples
| Need | File |
|------|------|
| E-process anytime-valid testing (Howard-Ramdas-McAuliffe-Sekhon 2021) — full 1000-obs worked example | [math/e-process-worked.md](references/math/e-process-worked.md) |
| Bayesian + conformal band release decision (Vovk-Gammerman-Shafer 2005) — full 6-category worked example | [math/conformal-band-worked.md](references/math/conformal-band-worked.md) |
| BOCPD regime detection (Adams-MacKay 2007) — full 120-obs worked example | [math/bocpd-worked.md](references/math/bocpd-worked.md) |
| Ville supermartingale proof — rigorous why anytime-valid testing works (Doob optional stopping; no Bonferroni) | [math/ville-supermartingale-proof.md](references/math/ville-supermartingale-proof.md) |
| Bayesian posterior update for the conformal-band ratchet — Beta-Bernoulli conjugacy + truncate_score discipline | [math/bayesian-posterior-update.md](references/math/bayesian-posterior-update.md) |

### CI Integration
| Need | File |
|------|------|
| GitHub Actions full matrix — per-workflow cadence + branch-protection set + paste-ready YAML excerpts + self-hosted-runner guidance | [ci-integration/GITHUB-ACTIONS-FULL-MATRIX.md](references/ci-integration/GITHUB-ACTIONS-FULL-MATRIX.md) |
| GitLab CI equivalent — same coverage, `.gitlab-ci.yml` syntax + tagged self-hosted runners + protected branch rules | [ci-integration/GITLAB-CI-EQUIVALENT.md](references/ci-integration/GITLAB-CI-EQUIVALENT.md) |

### Remediation
| Need | File |
|------|------|
| 10 winning optimization patterns verbatim with proof numbers + transferability notes | [remediation/REMEDIATION-PATTERNS.md](references/remediation/REMEDIATION-PATTERNS.md) |
| ProofInvariantClass taxonomy + 5-line proof template ("Change: ... Ordering preserved / Tie-breaking unchanged / Floating-point / RNG seeds / Golden outputs") | [remediation/ISOMORPHISM-PROOF-TEMPLATE.md](references/remediation/ISOMORPHISM-PROOF-TEMPLATE.md) |

### Orchestration
| Need | File |
|------|------|
| Subagent fan-out + MCP Agent Mail thread/reservation conventions + cc_N lane convention + rch offload heuristic | [orchestration/ORCHESTRATION.md](references/orchestration/ORCHESTRATION.md) |
| Skill bootstrap (jsm install, subscription, OAuth, inline fallbacks) | [orchestration/SKILL-BOOTSTRAP.md](references/orchestration/SKILL-BOOTSTRAP.md) |
| Plan→beads conversion prompt + polish loop + dependency validation | [orchestration/BEADS-HANDOFF.md](references/orchestration/BEADS-HANDOFF.md) |
| Agent fungibility doctrine + cc_N lane convention + swarm-init prompt verbatim | [orchestration/AGENT-FUNGIBILITY.md](references/orchestration/AGENT-FUNGIBILITY.md) |
| Parallel fan-out cookbook — 6 concrete patterns for dispatching parallel subagents | [orchestration/PARALLEL-FAN-OUT-COOKBOOK.md](references/orchestration/PARALLEL-FAN-OUT-COOKBOOK.md) |
| **NTM integration — gauntlet on NTM tmux panes (not in spite of)** — per-phase NTM dispatch table + pipeline schema + robot-mode discipline + failure-recovery ladders | [orchestration/NTM-INTEGRATION.md](references/orchestration/NTM-INTEGRATION.md) |
| NTM quickstart — paste-ready 5-command end-to-end gauntlet via NTM | [orchestration/NTM-QUICKSTART.md](references/orchestration/NTM-QUICKSTART.md) |

### Exemplars
| Need | File |
|------|------|
| Quote-bank anchors from FrankenSQLite session history (Track A operationalizing-expertise) + rituals + verbatim prompts | [exemplars/EXEMPLARS.md](references/exemplars/EXEMPLARS.md) |
| Section-by-section routing into the two FrankenSQLite bibles | [exemplars/FRANKENSQLITE-BIBLE.md](references/exemplars/FRANKENSQLITE-BIBLE.md) |
| Sibling-project adoption status: which has adopted / which is missing or partial / next action | [exemplars/SIBLING-PROJECTS-STATUS.md](references/exemplars/SIBLING-PROJECTS-STATUS.md) |
| Source-anchored quote bank (`[Q-NNN]` anchors per `/operationalizing-expertise` FORMATS) — 100+ entries | [exemplars/QUOTE-BANK.md](references/exemplars/QUOTE-BANK.md) |
| Quote bank Round-5 additions — 50+ NEW `[Q-201]`+ verbatim quotes from the two bibles | [exemplars/QUOTE-BANK-V2-ADDITIONS.md](references/exemplars/QUOTE-BANK-V2-ADDITIONS.md) |
| Rituals — the recurring agent behaviors that became the methodology (Track A generative grammar per /flywheel) | [exemplars/RITUALS.md](references/exemplars/RITUALS.md) |
| Rituals Round-5 additions — 8 new rituals (BEFORE-CONFORMANCE-WORK, BEFORE-SPEC-EDIT, AFTER-SOAK-FINDING, AFTER-BOCPD-SHIFT-DETECTED, BEFORE-DEEP-REVIEW-ESCALATION, WRITE-THE-WAIVER-ENTRY, DAILY-RATCHET-AUDIT, PRE-COMMIT-SAFETY-NET) | [exemplars/RITUALS-V2.md](references/exemplars/RITUALS-V2.md) |

### Troubleshooting
| Need | File |
|------|------|
| Common symptoms + fixes (flaky bench, oracle preflight failures, reservation conflicts, missing baseline, ratchet quarantine, BOCPD regime stuck, cass index stale) | [TROUBLESHOOTING.md](references/TROUBLESHOOTING.md) |

---

## Scripts

The 34 scripts in `scripts/` are the actual, runnable, opinionated helpers. Many *additional* script paths get cited in cookbook recipes / methodology docs / subagent prompts — those are **pseudocode showing intent**; adopters implement per their project shape. The convention + full inventory is documented in [references/SCRIPTS-INVENTORY.md](references/SCRIPTS-INVENTORY.md).

| Script | Purpose |
|--------|---------|
| `scripts/install-toolchain.sh` | Verify + install the full Rust + bench + fuzz + sanitizer + analysis toolchain; idempotent; per-tool green/yellow/red report. |
| `scripts/init-workspace.sh` | Create `<project>__gauntlet_workspace/`, `git init`, drop AGENTS.md mandate paragraph, seed three ledgers, write version-contract skeleton. |
| `scripts/detect-project-class.sh` | Auto-detect project class (SQL / RESP / Numerical-Python / ML-System / HTTP-Protocol); write `phase0_project_class.json`. |
| `scripts/check-skills.sh` | Inventory referenced helper skills + `jsm` state; write `phase0_skill_inventory.json`. |
| `scripts/oracle-preflight-doctor.sh` | Reference binary path/version, identity strings, fixture sanity, manifest hash; JSON output; non-zero on red. |
| `scripts/run-bench-matrix.sh` | Run `comprehensive-bench` against subject + reference; emit JSON v3 + scorecard + `.bench-history/*.latest.json`. |
| `scripts/run-narrow-benches.sh` | Run every focused per-workload bench in sequence; capture flamegraphs / samply / dhat / strace; per-workload attribution profiles. |
| `scripts/run-conformance-suite.sh` | Run every oracle E2E + differential V2 + metamorphic + property + fuzz harness; dedup by `MismatchSignature`; `FailureBundle` per divergence. |
| `scripts/run-fault-injection-matrix.sh` | Exercise every named fault profile + every crash boundary; assert post-recovery consistency. |
| `scripts/run-soak-campaign.sh` | Dispatch long-running fuzz / miri / loom / shuttle / crash-boundary / BOCPD / e-process campaigns to `rch`. |
| `scripts/compute-feature-coverage.sh` | Emit per-family dashboard verdict. |
| `scripts/compute-parity-score.sh` | Read scorecards, apply category weights, run Beta-posterior + conformal-band math, emit lower-bound + `truncate_score`'d output. |
| `scripts/apply-ratchet.sh` | Compare current lower bound to `reports/ratchet_state.json`; emit `Allow | Block | Quarantine | Waiver`. |
| `scripts/mine-ledger.sh` | Grep negative-ledger + 60-day cass for failure terms; candidate-blocker report; called by every perf-bead pre-flight. |
| `scripts/mine-cass-cross-machine.sh` | Invoke cass on local + css + csd + ts1 + ts2; aggregate session-history hits. |
| `scripts/convergence-tracker.sh` | Round-over-round new-finding counts across three ledgers + per-bucket findings; non-zero until 2 consecutive rounds <3 new findings AND every open hypothesis resolved. |
| `scripts/bead-graph-validator.sh` | `br dep cycles` + null-safe `bv --robot-insights` cycle checks; assert every remediation bead has test+bench+doc dependencies. |
| `scripts/final-report-builder.sh` | Collate `phase16_*` markdown into `FINAL_GAUNTLET_REPORT.md` + build certification-bundle directory. |
| `scripts/ast-grep-surface-patterns/` | Per-project-class surface-detection patterns (`pub fn`, `pub struct`, `impl ... for ...`, `#[no_mangle]`, `extern "C"`, `PRAGMA <name>`, `Opcode::<name>`, `pub const COMMAND_<name>`, `#[command]`, `#[pyfunction]`, `pub struct ... HandlerExt`). |
| `scripts/syn-walkers/` | Rust source-walker programs (Cargo crate) for predicates ast-grep can't express; subcommands: `public-api-diff`, `extern-c-signatures`, `no-mangle-symbols`, `pyfunction-coverage`. |
| `scripts/validate-skill.py` | Self-contained structural validator for this public skill copy. |
| `scripts/gauntlet-status.sh` | Terminal-native snapshot of a gauntlet workspace state (phase / round / per-pillar ratchet / open hypotheses / live NTM + rch / next action). Supports text / markdown / JSON modes. Per [`methodology/MONITORING-AND-DASHBOARDS.md § Layer A`](references/methodology/MONITORING-AND-DASHBOARDS.md). |
| `scripts/dispatch-subagent.sh` | Unified CLI for invoking or rendering a gauntlet subagent prompt. Backends: `ntm` (NTM pipeline) / `claude-code` (Agent-tool prompt export) / `inline` (print prompt) / `dry-run` (default). Per [`orchestration/PARALLEL-FAN-OUT-COOKBOOK.md`](references/orchestration/PARALLEL-FAN-OUT-COOKBOOK.md). |
| `scripts/check-cross-links.py` | Validates every markdown link points at an existing file. Used by the pre-commit safety net (per [`exemplars/RITUALS-V2.md § PRE-COMMIT-SAFETY-NET`](references/exemplars/RITUALS-V2.md)). |
| `scripts/gauntlet.sh` | Single-entry orchestrator that dispatches the entire 16-phase pipeline (or a mode-restricted subset) against a target port. |
| `scripts/kickoff.sh` | Prints the verbatim mode-specific kickoff prompt for the orchestrator. |
| `scripts/replay-failure.sh` | Takes a FailureBundle, replays it deterministically at a specified commit; reports passed / failed / shape-changed. |
| `scripts/compute-mismatch-signature.sh` | Hashes a minimal divergent reproducer into a stable MismatchSignature for dedup. |
| `scripts/run-tcl-tests.sh` | (SQL-class only) Runs the upstream SQLite TCL test suite through the port's CLI shim; diffs against captured reference baseline. |
| `scripts/run-numpy-all-check.sh` | (Numerical-class only) Verifies the port covers every entry in `numpy.__all__`; strict 100% gate. |
| `scripts/gradcheck.sh` | (ML-class only) Runs torch.gradcheck against the port's autograd; asserts gradient agreement within per-op ULP tolerance. |
| `scripts/verify-resp-protocol.sh` | (RESP-class only) Drives a RESP transcript through port + reference; asserts byte-identical wire output (canonicalized). |
| `scripts/openapi-schema-diff.sh` | (HTTP-class only) Diffs the port's OpenAPI schema against the reference framework's; canonical-key-sorted comparison. |
| `scripts/run-fresh-eyes-pass.sh` | Runs the three verbatim Phase-14 fresh-eyes prompts in sequence; loops until two consecutive clean rounds. |
| `scripts/update-ratchet-state.sh` | Applies a specific score artifact through the same monotonicity + waiver gate as `scripts/apply-ratchet.sh`. |
| `scripts/extract-from-bibles.sh` | Re-extracts the key sections of the two FrankenSQLite bibles into `<workspace>/bible_excerpts/` for offline reference. |

---

## Subagents

| Subagent | Phase | Purpose |
|---|---|---|
| `subagents/workspace-bootstrapper.md` | 0 | Toolchain + workspace + version-contract + ledger seeds + AGENTS.md mandate paragraph. |
| `subagents/surface-archaeologist.md` | 1 | Per-crate / per-top-level-module archaeology; one instance per crate. |
| `subagents/scope-decider.md` | 2 | Reference pinning + surface contract + scope decisions explicit. |
| `subagents/oracle-wirer.md` | 3 | One per project class; oracle bridge + EngineIdentity + 30-line scenario template. |
| `subagents/oracle-preflight-doctor-builder.md` | 3 | `oracle_preflight_doctor.rs` + per-class adaptations. |
| `subagents/golden-capturer.md` | 4 | Parameterized per tier and per fixture-source; emits Tier 1/2/3 golden artifacts. |
| `subagents/bench-author.md` | 5 | One per workload family; comprehensive-bench skeleton + focused per-workload benches. |
| `subagents/hot-path-counter-instrumenter.md` | 5 | `HotPathProfileSnapshot` per §23.6 row for the project class. |
| `subagents/oracle-test-author.md` | 6 | Parameterized per behavior class (NULL semantics, GROUP BY, etc.). |
| `subagents/metamorphic-author.md` | 6 | One per TransformFamily (Predicate / Projection / Structural / Literal). |
| `subagents/mismatch-minimizer-builder.md` | 6 | Delta-debugging binary partition + project-specific schema-preservation rule. |
| `subagents/fault-injector-author.md` | 6 | One per fault category. |
| `subagents/crash-boundary-wirer.md` | 6 | One per protocol boundary. |
| `subagents/fuzz-author.md` | 6 | One per differential fuzz target. |
| `subagents/eprocess-modeler.md` | 6 | One per invariant; e-process with hardware-vs-software parameters. |
| `subagents/feature-universe-builder.md` | 7 | `parity_taxonomy.rs` + weight normalization + iteration order. |
| `subagents/invariant-catalog-builder.md` | 7 | `parity_invariant_catalog.rs` + ProofObligation enumeration. |
| `subagents/coverage-dashboard-builder.md` | 7 | `feature_coverage_dashboard.rs` + per-family verdict. |
| `subagents/ledger-seeder.md` | 8 | Three ledgers + AGENTS.md mandate + cass-mining 60-day paragraph. |
| `subagents/baseline-runner-perf.md` | 9 | Full bench matrix + `.bench-history` initial commit + JSON v3. |
| `subagents/baseline-runner-conformance.md` | 9 | Oracle suite + differential corpus + metamorphic + FailureBundle per divergence. |
| `subagents/baseline-runner-surface.md` | 9 | FeatureUniverse load + dashboard verdict + integrity guardrails. |
| `subagents/idea-wizard-orchestrator.md` | 10 | Verbatim `/idea-wizard` Phase 2 prompt; 30→5, then 10 more. |
| `subagents/advanced-methods-miner.md` | 10 | Public literature/method mining + frontier-math compilation. |
| `subagents/iteration-coordinator.md` | 11 | Convergence-tracker driver; gates the loop. |
| `subagents/synthesizer.md` | 11 | Reads all per-bucket findings, writes the global picture. |
| `subagents/remediation-architect.md` | 12 | One per pillar; enumerate isomorphic rewrites; score on rubric. |
| `subagents/bead-author.md` | 13 | Plan→beads conversion via `/beads-workflow`. |
| `subagents/bead-polisher.md` | 13 | 4–5 polish rounds; do not oversimplify. |
| `subagents/fresh-eyes-reviewer-a.md` | 14 | First verbatim fresh-eyes prompt. |
| `subagents/fresh-eyes-reviewer-b.md` | 14 | Second verbatim fresh-eyes prompt (random-walk + AGENTS.md compliance). |
| `subagents/fresh-eyes-reviewer-c.md` | 14 | Third verbatim fresh-eyes prompt (fellow-agent code review). |
| `subagents/soak-runner-fuzz.md` | 15 | 24h+ differential fuzz against previously-divergent APIs. |
| `subagents/soak-runner-miri.md` | 15 | Multi-day Miri across harness internals. |
| `subagents/soak-runner-loom.md` | 15 | Multi-thousand-iter loom + shuttle. |
| `subagents/soak-runner-crash-boundary.md` | 15 | Multi-thousand-iter deterministic fault VFS. |
| `subagents/soak-runner-bocpd.md` | 15 | Multi-day BOCPD on parity-score stream; assert `Stable` regime. |
| `subagents/soak-runner-adversarial.md` | 15 | Adversarial-search against every gate; counterexamples become regression tests. |
| `subagents/final-report-author.md` | 16 | `FINAL_GAUNTLET_REPORT.md`. |
| `subagents/runbook-author.md` | 16 | `PARITY_RUNBOOK.md`. |
| `subagents/certification-bundler.md` | 16 | Strict-conformant-release.v1 bundle. |
| `subagents/cass-miner.md` | 0 / pre-11 / pre-12 | Mines 60-day cass session history (local + css + csd + ts1 + ts2) for failure terms; writes blocker entry if cass unavailable. |
| `subagents/mt8-attribution-profiler.md` | 5 / 9 / 11 | Runs MT8 (or class-equivalent) profile under steady-state, extracts top-10 self-time frames ≥0.1%. |
| `subagents/tcl-test-runner.md` | 6 / 11 (SQL-class) | Runs upstream SQLite TCL test suite through the port's CLI shim; dedup divergences by `MismatchSignature`. |
| `subagents/python-reference-bridger.md` | 3 (Numerical/ML/Python-ref) | Wires PyO3 in-process bridge with reference imported into sub-interpreter; pins determinism flags + per-call seed capture. |
| `subagents/schema-version-bumper.md` | 7 / on-demand | Safely propagates a schema bump through every producer + consumer + validator + migration test. |
| `subagents/waiver-author.md` | 12 alt / 14 | Authors structured dated waivers for legitimate ratchet step-backs; user signoff mandatory, never self-signed. |
| `subagents/hypothesis-spawner.md` | 11 | Mechanically converts `NEEDS_REFINEMENT` / `NEW_HYPOTHESIS_SPAWNED` results into new ledger entries; keeps open-hypothesis count honest. |
| `subagents/red-team-attacker.md` | 14 (T3+) / `red-team` mode | Holistic attacker across 6 lenses (agent-honesty-bias, cross-pillar-coupling, ...). Distinct from `soak-runner-adversarial` (mechanical). |
| `subagents/knowledge-transfer.md` | onboarding | Generates project-specific 4-week onboarding curriculum + trust ladder + buddy recommendation. |
| `subagents/hooks-installer.md` | 0 / on-demand | Installs Claude Code hooks (PreToolUse / PostToolUse / UserPromptSubmit / Stop) to enforce gauntlet discipline at tool-call boundaries. |
| `subagents/replay-runner.md` | 11 / on-demand | Replays a single `FailureBundle` deterministically; reports passed / failed / shape-changed. |
| `subagents/ratchet-curator.md` | 9 / 11 / 16 | Owns `reports/ratchet_state.json`; monotonic-update enforcement + waiver application + stale-field audit + history log. |
| `subagents/triangulator.md` | 14 (T3+) | Multi-model triangulation dispatch (Codex / Gemini / Grok / Claude) per `methodology/TRIANGULATION.md`. |
| `subagents/cookbook-author.md` | 16 / on-demand | Generates `<workspace>/cookbook/<motion>.md` files composing operators into recipes for recurring gauntlet motions. |
| `subagents/sibling-status-auditor.md` | on-demand | Audits a sibling Rust-port's adoption against the pattern library; updates `SIBLING-PROJECTS-STATUS.md`. |
| `subagents/ntm-orchestrator.md` | cross-cutting / every phase | The gauntlet's NTM-native dispatcher: spawns the swarm, dispatches per-phase pipelines, runs the unstick ladder, monitors via `ntm work triage` + `ntm activity`. |
| `subagents/deep-hypothesis-reviewer.md` | Phase 10/11/14 escalation | Spawns a user-authorized deep review session inside the gauntlet workspace to resolve a contested question via hypothesis pruning. |
| `subagents/greenfield-oracle-wirer.md` | Phase 3 (greenfield variant) | For projects where `detect-project-class.sh` returns `UNKNOWN`. Authors the 5-mode greenfield Oracle: Spec / Property / Self / Round-trip / External-tool. |
| `subagents/spec-tag-extractor.md` | Phase 2 (greenfield variant) | Walks every `[[spec_sources]]` and extracts `[SPEC-NNN]` tags into a verifiable / charter-only / ambiguous catalog. |
| `subagents/spec-conflict-resolver.md` | Phase 2 escalation (greenfield variant) | Only invoked when spec sources contradict. Walks each conflict pair; proposes A/B/C strategies; requires user signoff per pair. |
| `subagents/roundtrip-corpus-author.md` | Phase 6 (greenfield + any with serialization APIs) | Enumerates every (encode, decode) pair; authors one property + one fuzz target per pair; wires into roundtrip_oracle.rs. |
| `subagents/external-tool-oracle-builder.md` | Phase 3 (any variant) | Wires Miri / Clippy (-D warnings) / cargo-deny / cargo-audit as Oracles whose exit codes are TrueDivergence-equivalent. |

---

## Assets

| Asset | Purpose |
|---|---|
| `assets/intake-prompt.md` | Verbatim at very start of skill invocation. |
| `assets/agents-md-mandate-paragraph.md` | Drop-in paragraph for the target project's AGENTS.md. |
| `assets/negative-ledger-seed.md` | Header + retry-condition vocabulary + first example entry. |
| `assets/version-contract-template.toml` | `<reference>_version_contract.toml` skeleton. |
| `assets/supported-surface-matrix-template.toml` | SurfaceMatrix skeleton. |
| `assets/parity-score-contract-template.toml` | Category weights skeleton. |
| `assets/final-gauntlet-report-template.md` | `FINAL_GAUNTLET_REPORT.md` skeleton. |
| `assets/parity-runbook-template.md` | `PARITY_RUNBOOK.md` skeleton. |
| `assets/release-certification-template.md` | Strict-conformant-release.v1 template. |
| `assets/experiment-design-template.md` | Hypothesis / repro / expected-signal / falsifiability / one-line-invocation / results-inline. |
| `assets/cc-axioms.md` | The 12 K-N kernel axioms in compressed paste-ready form for project AGENTS.md / onboarding. |
| `assets/operator-cheatsheet.md` | 1-page glyph + composition cheatsheet for wall printout. |
| `assets/eprocess-calibration-template.toml` | Per-invariant e-process calibration (hardware/software parameter sets + per-invariant overrides). |
| `assets/per-class-checklists/sql.md` | Per-phase adoption checklist for SQL-class ports. |
| `assets/per-class-checklists/resp.md` | Per-phase adoption checklist for RESP-class ports. |
| `assets/per-class-checklists/numerical.md` | Per-phase adoption checklist for Numerical-Python-class ports. |
| `assets/per-class-checklists/ml.md` | Per-phase adoption checklist for ML-System-class ports. |
| `assets/per-class-checklists/http.md` | Per-phase adoption checklist for HTTP-Protocol-class ports. |
| `assets/per-class-checklists/greenfield.md` | Per-phase adoption checklist for Greenfield-Rust-class projects (single-crate vs workspace handling; 5-mode Oracle; project-specific fault surface). |
| `assets/integration-test-templates/greenfield_oracle_e2e.rs` | Paste-ready greenfield E2E showing all 5 oracle modes dispatched in one file (Spec / Property / Self / Round-trip / External-tool). |
| `assets/property-test-templates/greenfield_proptest.rs` | Paste-ready greenfield `proptest` skeleton with 5 metamorphic properties suited to greenfield (encode/decode identity, budget-respect-monotonicity, idempotent-on-second-call, deterministic-given-seed, no-panic-on-arbitrary-input). |
| `assets/fuzz-target-templates/greenfield_fuzz.rs` | Paste-ready greenfield `cargo-fuzz` differential target. |
| `assets/integration-test-templates/sql_oracle_e2e.rs` | Paste-ready 30-line `scenario()` template for SQL-class oracle E2E tests. |
| `assets/integration-test-templates/resp_oracle_e2e.rs` | Paste-ready RESP-class oracle E2E test (vendored redis-server + UNIX socket + canonicalized comparator). |
| `assets/integration-test-templates/numerical_oracle_e2e.rs` | Paste-ready Numerical-class oracle E2E (PyO3 + numpy + ULP-tolerant comparator). |
| `assets/integration-test-templates/ml_oracle_e2e.rs` | Paste-ready ML-class oracle E2E (PyO3 + torch + TensorSpec + ULP table + gradcheck). |
| `assets/integration-test-templates/http_oracle_e2e.rs` | Paste-ready HTTP-class oracle E2E (request fixture + MIME-aware body comparison + transient-header strip). |
| `assets/proof-pack-skeleton/` | Profile-first proof-pack directory skeleton with `delta_summary.json` + `rerun.sh` + `rollback.md` + `{criterion,hyperfine,alloc_census,syscalls,smoke}/`. |
| `assets/property-test-templates/{sql,resp,numerical,ml,http}_proptest.rs` | Paste-ready `proptest` skeleton per class with ProofInvariantClass + checked-in regressions + seed contract. |
| `assets/fuzz-target-templates/{sql,resp,numerical,ml,http}_fuzz.rs` | Paste-ready `cargo-fuzz` differential-fuzz targets per class. |
| `assets/recovery-verifier-template/` | Cargo crate skeleton implementing `RecoveryVerifier` trait + per-class verifiers (SQL/RESP/ML). |
| `assets/contributing-templates/CONTRIBUTING.md` | Contributor onboarding for gauntlet-adopted ports — K-N axioms + trust ladder + bead-claim workflow + ledger discipline + AGENTS.md mandate. |
| `assets/contributing-templates/CODEOWNERS` | GitHub CODEOWNERS template grouped by cc_N lane (cc_1 conformance / cc_2 perf / cc_3 surface / cc_4 soak). |
| `assets/beads-seed/issues.jsonl` | Seed `.beads/issues.jsonl` with 23 root beads covering Phases 0-9 (the floor every gauntlet adopts). |
| `assets/beads-seed/README.md` | Dependency graph documentation + verification + extension instructions. |
| `assets/ntm-pipelines/gauntlet-phase-<NN>-<name>.yaml` | 7 NTM pipelines (schema_version 2.0) for declarative per-phase fan-out: Phase 1 RECON, Phase 3 ORACLE-WIRING, Phase 6 CONFORMANCE-HARNESS, Phase 9 BASELINE, Phase 11 ITERATE, Phase 14 FRESH-EYES, Phase 15 SOAK. |
| `assets/ntm-marching-orders/MO-<name>.md` | 5 paste-ready marching-order templates dispatched per pane: recon-archaeology, oracle-wire, baseline-run, fresh-eyes-pass, soak-dispatch. Substitution variables: `${PANE_N}`, `${WORKSPACE_PATH}`, `${ROLE}`, `${MODEL}`, `${COORDINATION_MODE}`, plus per-MO `PARAM_*`. |
| `assets/hooks/*.sh` | 7 Claude Code hook scripts: dcg-passthrough, check-cass-mined-before-perf, auto-stage-bench-history, verify-concurrent-mode-guard, run-bead-graph-validator, warn-if-perf-change-without-ledger-grep, landing-the-plane. |
| `assets/github-workflows/*.yml` | 7 GitHub Actions workflows for the CI gates: parity-score-ratchet, bench-pass-over-pass, conformance-suite, feature-coverage, eprocess-ville-alarm, fault-vfs-coverage, bead-graph-validator. |

---

## Self-Test

Trigger phrases that should activate this skill:

- "Run the gauntlet on this Rust port"
- "Certify FrankenSQLite for release"
- "Build the oracle + differential harness for this Rust reimplementation"
- "Audit our port's parity with the reference, all three pillars"
- "Set up the FrankenSQLite-style performance + conformance + surface gauntlet on this project"
- "Honest perf measurement matrix vs the reference impl"
- "FeatureUniverse + SurfaceMatrix for this Rust port"
- "Set up the negative-evidence ledger discipline on this repo"
- "Run convergent multi-round evaluation against the reference"
- "Polish the parity scorecard into a release-readiness bundle"
- "Mine 60 days of cass for rejected perf candidates before I touch this hot path"

Trigger-phrase probe + end-to-end smoke test on a tiny port: [SELF-TEST.md](SELF-TEST.md).
