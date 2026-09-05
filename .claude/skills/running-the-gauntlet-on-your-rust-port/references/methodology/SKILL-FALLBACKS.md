# SKILL-FALLBACKS — Inline Fallbacks for Every Helper Skill the Gauntlet References

The gauntlet orchestrates a constellation of public helper skills (`/operationalizing-expertise`, `/codebase-archaeology`, `/profiling-software-performance`, ...). When one is missing, **fall back inline** — never block a phase on a missing skill. The pipeline degrades gracefully; the discipline holds.

This file is the canonical fallback playbook per skill: one-sentence purpose, the inline fallback prompt the orchestrator emits in lieu of the skill, and the threshold at which the orchestrator STOPS and asks the user to `jsm install <skill>` rather than continuing degraded.

---

## Detection

`scripts/check-skills.sh` writes `<workspace>/phase0_skill_inventory.json`:

```json
{
  "schema_version": "gauntlet.phase0_skill_inventory.v1",
  "generated_at": "2026-05-23T00:00:00Z",
  "jsm_available": true,
  "missing_count": 3,
  "skills": [
    {"name":"operationalizing-expertise","claude":true,"codex":true,"gemini":false,"jsm_installable":false,"available":true},
    {"name":"lean-formal-feedback-loop","claude":false,"codex":false,"gemini":false,"jsm_installable":true,"available":false}
  ]
}
```

Derive missing skills with `jq -r '.skills[] | select(.available == false) | .name' "$WORKSPACE/phase0_skill_inventory.json"`. If `jsm_available` is true and `jsm whoami` succeeds, propose `jsm install <name>` for each missing skill at Phase 0. Otherwise fall back inline and document the degradation in `phase0_workspace_init.md`.

---

## Per-skill fallback playbooks

### Skill-writing guidance

**Purpose (one sentence):** Create, validate, and debug Claude Code skill files (SKILL.md frontmatter, references/, scripts/, subagents/).

**Inline fallback prompt:** This skill carries its own structure contract; an orchestrator extending or debugging the gauntlet's own scaffolding can follow:

> Apply the contract: every SKILL.md has YAML frontmatter with `name` + `description` ≤ 1024 chars; references/ contains deep-dive markdown; scripts/ contains executable helpers; subagents/ contains per-subagent prompt files. Validate with this skill's `scripts/validate-skill.py`.

**When to STOP and ask for a stronger validator:** When the orchestrator is asked to edit this skill itself and the self-contained validator reports ambiguity. Otherwise proceed with the public validator.

---

### Corpus-to-skill extraction guidance

**Purpose (one sentence):** Build a new Claude Code skill by mining a CLI tool's behavior or a codebase's patterns.

**Inline fallback prompt:**
> Mine the target tool/codebase manually: (1) run `<cli> --help` recursively; (2) `cargo doc --document-private-items` for Rust; (3) extract verbatim usage examples from documentation; (4) cluster into operational modes; (5) author SKILL.md per this skill's structure contract. The mining files in this skill's `references/` directory are the model for the corpus-extraction discipline.

**When to STOP and ask for a dedicated corpus-extraction pass:** When the orchestrator is asked to create a NEW gauntlet-class skill for a different domain. The agent can author it inline, but the discipline of corpus → quote bank → triangulated kernel → operator library → validators is harder to apply manually.

---

### `/operationalizing-expertise`

**Purpose (one sentence):** Turn a methodology corpus into corpus + quote bank + triangulated kernel + operator library + validators (Track A workflow).

**Inline fallback prompt:**
> The Track A deliverables for THIS skill already exist (see [SOURCE-CORPUS.md](SOURCE-CORPUS.md)). If extending the gauntlet's corpus with new evidence (e.g., a new FrankenSQLite bible revision, a new sibling's session history), follow [SOURCE-CORPUS.md § How to extend the corpus](SOURCE-CORPUS.md) — the 5-step process for adding quotes / axioms / operators / patterns.

**When to STOP and ask user to `jsm install /operationalizing-expertise`:** When the gauntlet itself is being extended to a new project class not in [taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md). Adding a new class requires the full Track A discipline.

---

### `/codebase-archaeology`

**Purpose (one sentence):** Deep recon of an existing codebase — entry points, data flow, key types, integration points.

**Inline fallback prompt:**
> Phase 1 recon without `/codebase-archaeology`: (1) `cat <target>/README.md AGENTS.md Cargo.toml | head -200`; (2) `cargo metadata --format-version 1 | jq '.workspace_members'`; (3) `rg --type=rust 'pub fn|pub struct|pub trait|impl.*for|#\[no_mangle\]'`; (4) `ast-grep --pattern 'pub $$$' --lang rust`; (5) per crate, write `phase1_recon_<crate>.md` with sections: Public surface table / Perf surface / Conformance surface / Reference-mapping table. The template is in [PHASES.md § Phase 1](../PHASES.md).

**When to STOP and ask user to `jsm install /codebase-archaeology`:** When the target port is T4+ (Platform tier) — manual recon at that scale is error-prone. At T1-T3 the inline fallback is adequate.

---

### `/codebase-report`

**Purpose (one sentence):** Produce a structured codebase report (project-at-a-glance + architecture sketch + top-5-things-to-know).

**Inline fallback prompt:**
> Write `<workspace>/phase1_codebase_report.md` using:
> ```markdown
> # <port> codebase report
> ## Project at a glance
> - Type: <CLI / library / service / framework>
> - LOC: <tokei output>
> - Crates: <count from cargo metadata>
> - Reference: <reference name + pinned version>
> - Project class: <from phase0_project_class.json>
> ## Architecture sketch
> [ASCII / mermaid showing call graph or data flow]
> ## Top 5 things a new contributor must know
> 1. <most surprising design decision>
> 2. ...
> ```

**When to STOP and ask user to `jsm install /codebase-report`:** Never — the inline fallback is always adequate for this scope.

---

### `/profiling-software-performance`

**Purpose (one sentence):** Establish ranked-evidence hotspot table BEFORE any optimization — "no hotspot list → no change."

**Inline fallback prompt:**
> Phase 5 hot-path attribution without `/profiling-software-performance`: (1) `cargo flamegraph --bench <name>`; (2) `samply record -- <bench>`; (3) `perf stat -e instructions,branches,branch-misses,cache-references,cache-misses <bench>`; (4) `dhat --tool=dhat <bench>` for allocation profiles; (5) per-hotspot ≥0.1% self-time becomes a candidate (per the MT8 attribution rule in [KEEP-GATE-RULES.md](KEEP-GATE-RULES.md)). The 19-field proof-pack card in [SKILL.md § Profile-First Contract](../../SKILL.md) is the contract.

**When to STOP and ask user to `jsm install /profiling-software-performance`:** When the port is T4+ and the perf-pillar is the regression target. The full skill's discipline is hard to replicate inline at scale.

---

### `/extreme-software-optimization`

**Purpose (one sentence):** Profile first; prove behavior unchanged; one change at a time — the keep-gate discipline.

**Inline fallback prompt:**
> Keep-gate discipline without `/extreme-software-optimization`: read [KEEP-GATE-RULES.md](KEEP-GATE-RULES.md) — the 10 rules ARE the inline replacement. Every kept perf change must satisfy all 10 (profile-first, both gates same window, `release-perf` profile, `concurrent_mode_default_guard.txt` equivalent, symmetric retry shells, identical PRAGMAs, `selections=` byte-identical, `cv_pct` reported, MT8 attribution, pass-over-pass ratchet).

**When to STOP and ask user to `jsm install /extreme-software-optimization`:** Never — the skill's discipline is fully captured in [KEEP-GATE-RULES.md](KEEP-GATE-RULES.md) and [ANTI-PATTERNS.md](ANTI-PATTERNS.md).

---

### Advanced mathematical tool compilation

**Purpose (one sentence):** Route frontier-math results (probability bounds, fountain codes, e-processes) into implementable artifacts.

**Inline fallback prompt:**
> Phase 10's frontier-math step: read MINING-1 §7 (mathematical-toolkit catalog — 32 entries) and identify which apply to the current project class. Per applicable entry, ask: (1) what's the implementable consequence? (2) what's the evidence threshold? (3) what's the rollback recipe if the math holds but the implementation doesn't?

**When to STOP and ask for expert math review:** When the port is FrankenSQLite/FrankenTorch class and the §75-76 toolkit is being applied. The math-to-code translation is error-prone.

---

### Advanced systems-method mining

**Purpose (one sentence):** Apply 130+ buried CS breakthroughs to a project (Idreos cracking, Leis cooling, Kraska learned indexes, etc.).

**Inline fallback prompt:**
> Phase 10's systems-method mining step: read MINING-1 §7 catalog entries 19-30 (database cracking, LeanStore cooling, learned indexes, direct-DML, MonetDB vectorized, Cicada read-ts, Azuma, Nemhauser, PAC-Bayes, Little's Law + MPC, Lai-Robbins, renewal-reward). Per applicable entry, write a one-paragraph applicability assessment for the current port. Only the ≥0.1% candidates land in `<workspace>/round_<N>/ideas/advanced_methods.md`.

**When to STOP and ask for a dedicated literature pass:** When the port is database-shaped (SQL-class or storage-engine-shaped) and the public systems-technique catalog applies broadly. Otherwise inline is sufficient.

---

### `/testing-metamorphic`

**Purpose (one sentence):** "When you can't verify *what* the output is, verify *how* outputs relate to each other under known input transformations."

**Inline fallback prompt:**
> Phase 6's metamorphic harness without `/testing-metamorphic`: read MINING-2 §4 verbatim. Implement the `TransformFamily` enum (Predicate / Projection / Structural / Literal), `EquivalenceExpectation` enum (ExactRowMatch / MultisetEquivalence / SetEquivalence / TypeCoercionEquivalent), `MismatchClassification` enum (TrueDivergence / OrderDependentDifference / TypeAffinityDifference / NullHandlingDifference / FloatingPointDifference / FalsePositive). Per `TransformFamily`, write at least one test that demonstrates the strongest sound equivalence; document any weakening (e.g., `SetEquivalence` because order is plan-dependent) with a soundness-proof comment.

**When to STOP and ask user to `jsm install /testing-metamorphic`:** Never — the discipline is fully captured in MINING-2 §4 verbatim.

---

### `/testing-fuzzing`

**Purpose (one sentence):** Differential / structural / API fuzz harnesses with cargo-fuzz / cargo-afl / arbitrary / bolero.

**Inline fallback prompt:**
> Phase 6's fuzz step without `/testing-fuzzing`: `cargo install cargo-fuzz`; `cargo fuzz init`; per oracle entry point, write `fuzz_targets/<target>.rs` with `fuzz_target!(|input: Vec<u8>| { ... })` that drives both subject and reference and asserts equivalence per the comparator from [tooling/ORACLE-TOOLCHAIN.md](../tooling/ORACLE-TOOLCHAIN.md). Run `cargo fuzz run <target> -- -max_total_time=60` for smoke; `-max_total_time=86400` for Phase 15 soak.

**When to STOP and ask user to `jsm install /testing-fuzzing`:** When the port needs structural fuzzing (arbitrary-derived inputs with non-trivial validity constraints). Without the skill, structural fuzz is much harder.

---

### `/testing-conformance-harnesses`

**Purpose (one sentence):** Build conformance harnesses that pin contract-level behavior between a subject and a reference.

**Inline fallback prompt:**
> Phase 3+6 conformance scaffolding without `/testing-conformance-harnesses`: implement the 30-line `scenario()` template from MINING-2 §1 verbatim. Adapt the `NormalizedValue::normalize_value` rendering per project class (per [taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md)). Both-error = agreement; one-error-one-OK = hard failure; EngineIdentity asserted-distinct at every comparator entry.

**When to STOP and ask user to `jsm install /testing-conformance-harnesses`:** Never — the discipline is fully captured in MINING-2 §1 + §3 verbatim.

---

### `/testing-golden-artifacts`

**Purpose (one sentence):** Capture and version golden artifacts at three tiers (byte / canonical / logical) with manifest + checksums.

**Inline fallback prompt:**
> Phase 4 golden capture without `/testing-golden-artifacts`: per fixture source, capture (1) Tier 1 raw bytes → `sha256sum > manifest`; (2) Tier 2 canonical-normalized (post-VACUUM for SQL-class, post-`use_deterministic_algorithms` for ML-class); (3) Tier 3 logical dump (row count + columns + values via `==`). The contract rule from MINING-2 §6: "Encode the distinction; never paper over it" — a Tier 2 match is not Tier 1; the JSON report must name which tier succeeded.

**When to STOP and ask user to `jsm install /testing-golden-artifacts`:** Never — the three-tier discipline is fully captured in MINING-2 §6 verbatim.

---

### `/testing-real-service-e2e-no-mocks`

**Purpose (one sentence):** Mock-free integration / E2E tests with real DBs, real APIs, real services + structured logging.

**Inline fallback prompt:**
> Phase 6's E2E pathway without `/testing-real-service-e2e-no-mocks`: use the in-process oracle (rusqlite for SQL-class, vendored redis-server subprocess for RESP-class, PyO3 in-process Python for Numerical/ML-class). No mocking. The skill's discipline of "transaction rollback isolation, test data factories, structured JSON-line test logging" maps directly to the FailureBundle + E2E log schema from MINING-2 §15-16.

**When to STOP and ask user to `jsm install /testing-real-service-e2e-no-mocks`:** When the port has HTTP-Protocol-class third-party service integrations (e.g., FastMCP Rust with real MCP clients). Without the skill, the structured-logging discipline is harder to maintain.

---

### `/multi-pass-bug-hunting`

**Purpose (one sentence):** "First pass finds obvious bugs. Second pass finds bugs hidden by the obvious ones. Third pass catches what you introduced fixing the first two."

**Inline fallback prompt:**
> Phase 14's fresh-eyes discipline IS the multi-pass bug hunting workflow. Use the three calibrated prompts verbatim from [AGENT-PROMPTS.md § Phase 14](../AGENT-PROMPTS.md) (Reviewer A / B / C). Iterate until two consecutive rounds are clean.

**When to STOP and ask user to `jsm install /multi-pass-bug-hunting`:** Never — the discipline is fully captured in Phase 14's design.

---

### `/deadlock-finder-and-fixer`

**Purpose (one sentence):** "There is almost always a fourth instance" — systematic deadlock root-causing.

**Inline fallback prompt:**
> Phase 15's concurrency soak (`loom` + `shuttle`) without `/deadlock-finder-and-fixer`: when loom/shuttle finds an interleaving deadlock, do NOT immediately fix the apparent locking-order violation. Instead: (1) reproduce deterministically with the schedule fingerprint from the FailureBundle; (2) enumerate the 9 deadlock classes from [tooling/CONCURRENCY-TOOLCHAIN.md](../tooling/CONCURRENCY-TOOLCHAIN.md); (3) for each class, check if the codebase has *another* instance of the same pattern; (4) fix all instances together (the discipline assumes there are usually 3-5 instances of any concurrency bug; fixing one in isolation leaves the others to surface later).

**When to STOP and ask user to `jsm install /deadlock-finder-and-fixer`:** When the port has MVCC-class concurrency (FrankenSQLite, FrankenRedis). Without the skill's discipline, fixes tend to whack-a-mole.

---

### `/lean-formal-feedback-loop`

**Purpose (one sentence):** "Treat proof friction as evidence" — formal-method-assisted refactoring with Lean.

**Inline fallback prompt:**
> Phase 12's isomorphism-proof step without `/lean-formal-feedback-loop`: use the 5-line proof template from [remediation/ISOMORPHISM-PROOF-TEMPLATE.md](../remediation/ISOMORPHISM-PROOF-TEMPLATE.md). The template covers: "Change: ... / Ordering preserved / Tie-breaking unchanged / Floating-point / RNG seeds / Golden outputs". For a remediation that materially changes invariants, the proof template should reference a property test or metamorphic test that exercises the invariant pre/post change.

**When to STOP and ask user to `jsm install /lean-formal-feedback-loop`:** Optional. Lean-assisted verification is rare even in T4 contexts; the 5-line template is sufficient for most remediations.

---

### `/multi-agent-swarm-workflow`

**Purpose (one sentence):** Orchestrate parallel agent workers with tmux + Agent Mail + reservations.

**Inline fallback prompt:**
> Phase 11's swarm dispatch without `/multi-agent-swarm-workflow`: if `/agent-mail` is installed, the orchestrator can dispatch subagents via Task tool with per-thread coordination. If neither is installed, drop to Pair tier (single worker per pillar, sequential) and accept the longer wall time. Document the degradation in `<workspace>/orchestration_constraints.md`.

**When to STOP and ask user to `jsm install /multi-agent-swarm-workflow`:** When the tier is T4+ and rch-offload is mandatory. Without swarm orchestration, T4 effective wall time multiplies by 4-8x.

---

### `/agent-fungibility-philosophy`

**Purpose (one sentence):** "Every agent is fungible and a generalist" — design subagent prompts so any worker can pick up any lane.

**Inline fallback prompt:**
> When writing subagent prompts (the files in `subagents/`), apply the rule: every subagent prompt should be self-contained enough that a fresh agent with NO prior context can complete the lane by reading just the prompt + the files it references. Test by handing a subagent prompt to a fresh model and verifying the output is in-spec.

**When to STOP and ask user to `jsm install /agent-fungibility-philosophy`:** Never — the discipline is captured in the gauntlet's subagent prompt design.

---

### `/flywheel`

**Purpose (one sentence):** "Don't summarize — extract the *generative grammar*. Your repeated behaviors ARE your methodology."

**Inline fallback prompt:**
> Phase 10's idea-wizard discipline DRAWS ON the flywheel pattern. The Track A discipline from [SOURCE-CORPUS.md](SOURCE-CORPUS.md) IS the flywheel applied to FrankenSQLite. When the orchestrator notices a repeated behavior across rounds (e.g., "we keep rediscovering that PRAGMA defaults flipped"), it should land that repetition in the negative-ledger as a structured grammar element, not as another one-off finding.

**When to STOP and ask user to `jsm install /flywheel`:** Never — the discipline is embedded in the gauntlet's methodology.

---

### `/idea-wizard`

**Purpose (one sentence):** Generate non-obvious improvement ideas for a project (Phase-2 prompt produces 30 ideas, winnow to 5, then 10 more).

**Inline fallback prompt:**
> Phase 10's idea-wizard step without the skill: emit this prompt to a fresh agent context:
> "You are reviewing <port> for the gauntlet. The negative-ledger says these N candidates have been rejected: <list>. The current baseline says these M pillars regress: <list>. Generate 30 non-obvious gauntlet techniques specific to this port — techniques NOT already in the ledger or the advanced-methods catalog. Apply the FrankenSQLite quote-bank lens from references/exemplars/EXEMPLARS.md. Output 30 ideas as a numbered list with one-line falsifiability per idea. Then pick the top 5; then generate 10 more. Total ≥45 ideas, each with falsifiability."

**When to STOP and ask user to `jsm install /idea-wizard`:** Optional. The inline prompt is adequate; the skill's adds are stylistic polish.

---

### `/beads-workflow`

**Purpose (one sentence):** Convert markdown plans into beads (`br`) with proper dependencies; bridge planning to swarm execution.

**Inline fallback prompt:**
> Phase 13's bead handoff without `/beads-workflow`: if `/beads-br` is installed (the CLI), the orchestrator can call `br create --title "..." --desc "..." --dep <parent-bead>` directly. Apply the discipline: every remediation bead has a test-bead + bench-bead + doc-bead dependency. Run `br dep cycles`; assert empty. If neither skill nor CLI is installed, maintain the plan in `<workspace>/phase13_bead_plan.md` as a markdown table; workers manually claim by editing rows.

**When to STOP and ask user to `jsm install /beads-workflow`:** When the tier is T3+ and the bead graph has >20 entries. Manual bead-graph management at scale is error-prone.

---

### `/cass`

**Purpose (one sentence):** Mine past agent sessions for working prompts, decisions, and patterns — cross-machine search.

**Inline fallback prompt:**
> Phase 8's cass-mining step without `/cass`: see [CASS-MINING.md § When cass is unavailable](CASS-MINING.md). Fall back to `rg --json -i "<failure-term>" ~/.claude/projects/`. Document the partial coverage; stamp emitted artifacts with `provenance: cass_partial_or_skipped_at_<timestamp>`.

**When to STOP and ask user to `jsm install /cass`:** When the AGENTS.md mandate paragraph is being seeded for a target project. The mandate requires 60-day cross-machine mining; without `/cass` the mandate's promise can't be honored, only documented as a blocker.

---

### `/agent-mail`

**Purpose (one sentence):** MCP-based coordination between parallel agent workers (thread IDs, reservations, inboxes).

**Inline fallback prompt:**
> Squad/Swarm tier requires Agent Mail for coordination. Without it:
> - Drop to Solo/Pair tier (single worker per pillar, sequential).
> - OR coordinate via filesystem lockfiles: `<workspace>/.lock_<file>` per shared file; workers `flock` the lockfile before editing. Primitive but works.
> Document the orchestration constraint in `<workspace>/orchestration_constraints.md`.

**When to STOP and ask user to `jsm install /agent-mail`:** When tier is T3+ AND rch-offload is in use. Without Agent Mail the swarm becomes effectively sequential.

---

### `/ubs` — Ultimate Bug Scanner

**Purpose (one sentence):** Pre-commit / pre-review code review for bugs, security, validation of AI-generated code.

**Inline fallback prompt:**
> Phase 14's UBS step without the skill: use the project's existing linter (`cargo clippy --all-targets -- -D warnings`, `cargo clippy --all-targets -- -W clippy::pedantic`, `cargo fmt --check`, `cargo test --workspace`, `cargo +nightly miri test -p <port>-harness`). Add `cargo geiger` for unsafe-block surveys and `cargo audit` for vulnerability scans.

**When to STOP and ask user to `jsm install /ubs`:** When the port has nontrivial `unsafe` code (FrankenSQLite, FrankenTorch). Without UBS the unsafe-block survey is less systematic.

---

### `/dcg` — Destructive Command Guard

**Purpose (one sentence):** Block dangerous commands (rm -rf, git reset --hard, DROP DATABASE, kubectl delete) at the agent harness level.

**Inline fallback prompt:**
> The gauntlet never needs to issue destructive commands against the TARGET port (the gauntlet's discipline is to write into `<workspace>/` and `<target>/.beads/issues.jsonl` only). If a subagent attempts `rm -rf` or `git reset --hard` against `<target>/`, the orchestrator should HALT, surface to user, and demand explicit authorization. Without `/dcg`, the orchestrator enforces this discipline manually.

**When to STOP and ask user to `jsm install /dcg`:** Recommended for all gauntlet runs (the cost of one accidental destructive command is high; the cost of `/dcg` installation is near-zero).

---

### `/rch` — Remote Compile Host

**Purpose (one sentence):** Offload slow cargo/gcc/bun builds to remote workers; route compilation to faster hosts.

**Inline fallback prompt:**
> Phase 5/9/11/15 heavy dispatch without `/rch`: run locally and accept the wall-time cost. Pin to dedicated cores via `taskset -c 0-7`; disable hyperthreading via `echo off > /sys/devices/system/cpu/smt/control` (requires sudo); use `nice -n -20` for the bench process. Without rch, T4 gauntlet runs may not be tractable on a single host within reasonable wall time; document the constraint and surface to user.

**When to STOP and ask user to `jsm install /rch`:** When the tier is T4+ — local-only execution makes T4 gauntlet-full effectively impossible within month-long budgets.

---

## jsm installer

```bash
# Linux/macOS
curl -fsSL https://jeffreys-skills.md/install.sh | bash

# Windows (PowerShell)
irm https://jeffreys-skills.md/install.ps1 | iex
```

After install:

```bash
jsm login
# Browser opens for OAuth; or use --headless for SSH sessions

# Bulk install all missing skills from the inventory.
WORKSPACE=<workspace>
./scripts/check-skills.sh "$WORKSPACE" || true
for skill in $(jq -r '.skills[] | select(.available == false) | .name' "$WORKSPACE/phase0_skill_inventory.json"); do
  jsm install "$skill" || echo "WARN: $skill install failed; using inline fallback"
done
```

The loop reads `phase0_skill_inventory.json`, picks the missing list, and runs `jsm install <name>` for each. Failures are logged but don't abort.

---

## When to refuse vs fall back (the meta-rule)

- **Refuse** (halt and ask the user) if the missing skill is the ONLY source for an outcome AND the outcome is a hard release-gate requirement. Example: `/cass` is missing AND the user wants a certified release; the AGENTS.md mandate cannot be honored without the 60-day cross-machine mine.

- **Fall back** (proceed degraded) if the missing skill is one of many sources for the same outcome, OR if the outcome is "nice to have" at the current tier. Example: `/codebase-archaeology` is missing at T1; manual recon is adequate.

- **Document the degradation** in EVERY case (refuse OR fall back). The `<workspace>/skill_fallbacks_taken.md` is appended per phase; the final report cites it.

The default is **fall back, don't block**. Surface the missing skill in the phase summary so the user knows what they got vs. what they would have gotten with the full toolkit.

---

## Optional project-local bulk installer

```bash
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="${1:-}"
[[ -z "$WORKSPACE" ]] && { echo "usage: $0 <workspace>"; exit 2; }

# Read the missing-skills list
MISSING=$(jq -r '.skills[] | select(.available == false) | .name' "$WORKSPACE/phase0_skill_inventory.json")

if [[ -z "$MISSING" ]]; then
  echo "All referenced skills already installed."
  exit 0
fi

# Verify jsm is authenticated
if ! jsm whoami >/dev/null 2>&1; then
  echo "ERROR: jsm not authenticated. Run 'jsm login' first."
  exit 1
fi

# Install
for SKILL in $MISSING; do
  echo "Installing $SKILL..."
  if jsm install "$SKILL"; then
    echo "  ✓ $SKILL installed"
  else
    echo "  ✗ $SKILL install failed; will use inline fallback"
    echo "$SKILL" >> "$WORKSPACE/skill_install_failures.txt"
  fi
done

# Re-inventory
./scripts/check-skills.sh "$WORKSPACE"

echo "Bulk install complete. Re-check inventory: cat $WORKSPACE/phase0_skill_inventory.json"
```

---

## See also

- [SKILL.md § Up-Front Confirmations](../../SKILL.md) — where missing-skill detection happens.
- [orchestration/SKILL-BOOTSTRAP.md](../orchestration/SKILL-BOOTSTRAP.md) — full bootstrap detail.
- [CASS-MINING.md § When cass is unavailable](CASS-MINING.md) — the cass-specific fallback.
