# SELF-TEST — running-the-gauntlet-on-your-rust-port

This file documents how to verify the skill activates correctly, and how to smoke-test it end-to-end against a small Rust port.

---

## Trigger-phrase probe

Open a fresh Claude Code session in any Rust-port directory and ask one of the following. Each should activate this skill (Claude should reach for it in its planning, not just answer ad-hoc).

1. "Run the gauntlet on this Rust port."
2. "Certify FrankenSQLite for release."
3. "Build the oracle + differential harness for this Rust reimplementation."
4. "Audit our port's parity with the reference, all three pillars."
5. "Set up the FrankenSQLite-style performance + conformance + surface gauntlet on this project."
6. "Honest perf measurement matrix vs the reference impl."
7. "FeatureUniverse + SurfaceMatrix for this Rust port."
8. "Set up the negative-evidence ledger discipline on this repo."
9. "Run convergent multi-round evaluation against the reference."
10. "Polish the parity scorecard into a release-readiness bundle."
11. "Mine 60 days of cass for rejected perf candidates before I touch this hot path."

**Pass criterion:** Claude opens `SKILL.md`, then reads at least one of `references/PHASES.md`, `references/THREE-PILLARS.md`, or `references/taxonomy/PROJECT-CLASSES.md` before answering.

**Fail modes to watch for:**
- Claude answers from training data without opening the skill.
- Claude opens the skill but skips the project-class router and tries a one-size-fits-all approach.
- Claude offers a single-pass evaluation instead of the 16-phase loop.

---

## Skill-file validator

Run the writing-skills validator to confirm SKILL.md conforms:

```bash
SKILL="${SKILL_DIR:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
"$SKILL/scripts/validate-skill.py"
```

Expected: exit 0 and final line `Skill is valid`. This package is intentionally large, so the validator currently emits many size / nested-reference / missing-TOC warnings; warnings are acceptable for this skill, errors are not.

---

## Directory inventory check

```bash
SKILL="${SKILL_DIR:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
test -f $SKILL/SKILL.md
test -f $SKILL/SELF-TEST.md
test -d $SKILL/references/methodology
test -d $SKILL/references/taxonomy
test -d $SKILL/references/tooling
test -d $SKILL/references/experiments
test -d $SKILL/references/remediation
test -d $SKILL/references/orchestration
test -d $SKILL/references/exemplars
test -d $SKILL/subagents
test -d $SKILL/scripts
test -d $SKILL/scripts/ast-grep-surface-patterns
test -d $SKILL/scripts/syn-walkers
test -d $SKILL/assets
test -f $SKILL/references/PHASES.md
test -f $SKILL/references/AGENT-PROMPTS.md
test -f $SKILL/references/THREE-PILLARS.md
test -f $SKILL/references/methodology/KERNEL.md
test -f $SKILL/references/methodology/OPERATORS.md
test -f $SKILL/references/methodology/KEEP-GATE-RULES.md
test -f $SKILL/references/methodology/RETRY-CONDITION-VOCABULARY.md
test -f $SKILL/references/methodology/CONVERGENCE.md
test -f $SKILL/references/taxonomy/PROJECT-CLASSES.md
test -f $SKILL/references/taxonomy/FEATURE-UNIVERSE.md
test -f $SKILL/references/taxonomy/INVARIANT-CATALOG.md
test -f $SKILL/references/tooling/BENCH-TOOLCHAIN.md
test -f $SKILL/references/tooling/ORACLE-TOOLCHAIN.md
test -f $SKILL/scripts/install-toolchain.sh
test -f $SKILL/scripts/init-workspace.sh
test -f $SKILL/scripts/oracle-preflight-doctor.sh
test -f $SKILL/scripts/convergence-tracker.sh
echo OK
```

Expected: prints `OK`.

---

## Cross-link sanity check

Every reference file should resolve relative links to other files in the skill.

```bash
SKILL="${SKILL_DIR:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
"$SKILL/scripts/check-cross-links.py" "$SKILL" --verbose
```

Expected: exit 0 and diagnostic output ending with `files clean.`. The maintained checker skips external links, absolute local paths, angle-bracket placeholders, and runtime-generated workspace paths.

---

## Orchestrator dry-run smoke test

This proves the first command a cold agent reaches for can parse args and route phases without requiring a fully instrumented target.

```bash
SKILL="${SKILL_DIR:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
TARGET="${TARGET_PORT:-$PWD}"     # path to the Rust port under test
WORKSPACE=/tmp/gauntlet-self-test-$(date +%Y%m%d%H%M%S)

"$SKILL/scripts/gauntlet.sh" "$TARGET" "$WORKSPACE" --mode quick-smoke --dry-run
```

Expected: exit 0; output lists Phase 0 helpers, the Phase 0 oracle-preflight readiness probe, and Phase 9 helpers without executing heavy commands.

---

## Real end-to-end smoke test (against a tiny port)

For a real smoke test, use a tiny Rust port that actually includes the gauntlet-facing harness surfaces (`comprehensive_bench`, at least one `*_oracle_e2e.rs`, a surface matrix, and a parity score contract). A plain `cargo new` toy is useful for Phase 0 only; Phase 9 helpers should honestly fail on it because there is no bench or oracle harness to run.

**Setup:**
```bash
# Create a toy SQL-class port: a Rust binary that wraps SQLite via rusqlite,
# plus a trivial "FrankenSQLite-lite" implementing SELECT-1 in pure Rust.
mkdir -p /tmp/frankentoy && cd /tmp/frankentoy
cargo new --bin frankentoy
echo '[dependencies]\nrusqlite = "0.32"' >> Cargo.toml
# (write the trivial select_1() impl in src/lib.rs)
```

**Smoke flow:**
```bash
# Phase 0
SKILL=~/.claude/skills/running-the-gauntlet-on-your-rust-port
TARGET=/tmp/frankentoy
WORKSPACE=/tmp/frankentoy__gauntlet_workspace

"$SKILL/scripts/install-toolchain.sh" --workspace "$WORKSPACE"
"$SKILL/scripts/init-workspace.sh" "$TARGET" "$WORKSPACE"
"$SKILL/scripts/detect-project-class.sh" "$TARGET" --workspace "$WORKSPACE"
"$SKILL/scripts/oracle-preflight-doctor.sh" "$TARGET" --workspace "$WORKSPACE"

# Phase 9 baseline (requires real harness files; expect honest failure on a plain cargo-new toy)
"$SKILL/scripts/run-bench-matrix.sh" "$TARGET" "$WORKSPACE"        # requires a comprehensive_bench cargo bin or equivalent
"$SKILL/scripts/run-conformance-suite.sh" "$TARGET" "$WORKSPACE" --no-fuzz  # requires *_oracle_e2e.rs / differential tests
"$SKILL/scripts/compute-feature-coverage.sh" "$WORKSPACE"         # requires supported_surface_matrix.toml
"$SKILL/scripts/compute-parity-score.sh" "$WORKSPACE"             # requires score observations

# Convergence-tracker should exit non-zero (only 1 round)
"$SKILL/scripts/convergence-tracker.sh" "$WORKSPACE"
```

**Pass criteria for a harnessed toy:**
- Phase 0 scripts exit 0, except `oracle-preflight-doctor.sh` may exit 1 yellow until contracts are pinned.
- Phase 9 scripts exit 0 only if the toy includes the required bench, oracle, surface, and score artifacts; otherwise their non-zero exits are correct evidence-honesty failures.
- `convergence-tracker.sh` exits non-zero until the 10-round convergence condition is met.
- `phase0_workspace_init.md` written.
- `phase0_project_class.json` reports `SQL-class`.
- `.bench-history/comprehensive_bench.latest.json` written with `schema_version: "fsqlite-e2e.comprehensive-bench-report.v3"`.
- For SELECT-1, the comparator returns parity (the trivial impl matches rusqlite).
- `compute-parity-score.sh` emits a lower-bound score >0 (subject implements at least one feature).
- `phase0_skill_inventory.json` lists helper skills with availability flags.

---

## Mirror verification

If your install layout mirrors the skill into multiple harnesses (Claude
Code, Codex, Gemini, etc.), confirm the trees are identical. The exact
paths depend on which harnesses you have installed; the example below
checks the Claude Code → Codex mirror that `jsm` keeps in sync.

```bash
SKILL="${SKILL_DIR:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
MIRROR="${MIRROR_DIR:-$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port}"
diff -r "$SKILL/" "$MIRROR/"
```

Expected: no output (identical trees).

---

## Activation under Haiku

The skill must activate reliably under Haiku as well as Opus. Open a Claude Code session with `--model haiku` and run the trigger-phrase probe above. Pass criterion: same as Opus — opens SKILL.md, then a referenced playbook.
