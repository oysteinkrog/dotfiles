# Pattern 56 — PROPTEST-REGRESSION-DISCIPLINE

**Family:** Kernel — extends the insta-golden discipline ([pattern:55-INSTA-GOLDEN-SNAPSHOTS](55-INSTA-GOLDEN-SNAPSHOTS.md)) to property-test counterexamples. Pairs with [pattern:06-5-MODE-ORACLE-DISPATCH](06-5-MODE-ORACLE-DISPATCH.md) (`OracleMode::Property`) and is the seed-contract artifact behind every greenfield `Property` oracle. Linked to the `✂ EXCLUSION-TEST` operator in [`../methodology/OPERATORS.md`](../methodology/OPERATORS.md).

**When to apply:** Any project that uses `proptest` (or `quickcheck`, with adaptation) for property-based testing. Especially load-bearing in greenfield mode where `OracleMode::Property` is one of the five oracle modes and the property suite is *the* oracle for a swath of behaviors.

## What

A discipline + a configuration + a CI gate that says: **every shrunk counterexample produced by `proptest` is checked into git as `proptest-regressions/<test>.txt`**. The mechanism is `FileFailurePersistence::WithSource("proptest-regressions")` in `Config::default()`, and the gate is a CI check that (a) `proptest-regressions/*.txt` is tracked by git, (b) every test that has ever shrunk a counterexample has its regression file, (c) on every run, before drawing new random cases, proptest replays *all* checked-in seeds to verify they still reproduce (or fail to, which is itself a finding worth flagging).

The third leg of the discipline is *minimization preservation*: when a counterexample is fixed (the bug is patched), the regression seed stays checked in. The seed is now a regression test, not a current bug. Removing it loses the witness that the bug is fixed and re-opens the door to its return.

## Why

> "**Checked-in `proptest-regressions/<test>.txt`** — every shrunk counterexample committed to git." — [`GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) §6 (Property-Oracle authoring).

Failure mode prevented: *non-reproducible property failures*. Default proptest behavior writes regression files to `~/.cache/proptest`, which is per-machine and per-user. Agent A's CI run fails on seed `0xABCD...`; Agent B's local run uses seed `0xDEAD...`; B can't reproduce A's failure; eventually A's failure is dismissed as "flaky". Without checked-in regressions, every shrunk counterexample is wasted work — the next agent doesn't get to start from "the shrunk minimal reproduction"; they start from "the cv_pct is suspicious, let me re-fuzz from scratch".

The second failure mode prevented: *regressions gitignored by default*. The default `.gitignore` templates from `cargo init` do not list `proptest-regressions/`, but it's common to see `*.txt` ignored in projects that adopted an aggressive ignore policy early. The explicit-include rule (`!proptest-regressions/`) must land before the first property test, or the first shrunk counterexample silently goes unchecked-in. This is the silent-pass shape that the discipline exists to prevent.

The third failure mode prevented: *seed deletion on bug fix*. The natural cleanup instinct: "the bug is fixed, the regression file is obsolete, delete it." But the file is the *witness* that the bug is fixed; with the seed removed, no future run will replay that exact input. Six months later a refactor reintroduces the bug; nobody notices because the regression seed that would have caught it was deleted.

The fourth failure mode prevented: *replay without verification of reproduction*. Sometimes the checked-in seed *no longer* reproduces the bug (because the bug was fixed, or because an unrelated change altered the random draw indirectly). Without an audit step, the agent assumes "no failure on replay = green"; but the seed may no longer be probing the original bug class at all. The discipline includes an audit that proves each seed still drives the test through its intended code path.

## The pattern

### The `Config` shape (per-test or per-crate)

```rust
//! tests/properties/_proptest_config.rs
//! Included by every property test as `#[path = "_proptest_config.rs"] mod _proptest_config;`

use proptest::test_runner::{Config, FileFailurePersistence};

/// Standard config: persist to checked-in `proptest-regressions/` directory.
/// Always use this; never `Config::default()`.
pub fn standard_config() -> Config {
    Config {
        // 256 = good default; greenfield projects with a sparse Oracle should
        // bump to 1024 (configurable per-test via `with_cases`).
        cases: 256,

        // Allow up to 4096 attempts to grow a valid case (default 1024); proptest's
        // default can starve on tight precondition filters.
        max_local_rejects: 65_536,
        max_global_rejects: 1024,

        // THE KEY LINE: regressions go to a checked-in directory next to the test file.
        // `WithSource("proptest-regressions")` resolves relative to CARGO_MANIFEST_DIR.
        failure_persistence: Some(Box::new(FileFailurePersistence::WithSource(
            "proptest-regressions"
        ))),

        // Verbose result reporting; counterexamples printed in full in CI logs.
        result_cache: proptest::test_runner::basic_result_cache,
        ..Config::default()
    }
}

/// Config variant for tests with expensive setup (e.g., spinning up SQLite).
pub fn expensive_setup_config() -> Config {
    Config { cases: 32, ..standard_config() }
}

/// Config variant for fuzz-style soak runs (Phase 15).
pub fn soak_config() -> Config {
    Config { cases: 100_000, ..standard_config() }
}
```

### Per-test usage

```rust
//! tests/properties/remember_collision_proptest.rs

#[path = "_proptest_config.rs"]
mod _proptest_config;
use _proptest_config::standard_config;

use proptest::prelude::*;

proptest! {
    #![proptest_config(standard_config())]

    /// SPEC-EE-001: collision rate < 1e-15 across 1M `remember` calls.
    #[test]
    fn prop_remember_collision_bound(
        seed in any::<[u8; 32]>(),
        ops in proptest::collection::vec(any::<RememberOp>(), 1..256),
    ) {
        let engine = test_engine_with_seed(&seed);
        let mut ids = std::collections::HashSet::new();
        for op in ops {
            let id = engine.remember(op.payload());
            prop_assert!(ids.insert(id), "collision on payload {:?}", op.payload());
        }
    }
}
```

When this test shrinks a counterexample, proptest writes:

```
crates/<port>-harness/tests/properties/proptest-regressions/remember_collision_proptest.txt

# Seeds for failure cases proptest has generated in the past. It is
# automatically read and these particular cases re-run before any
# novel cases are generated.
#
# It is recommended to check this file in to source control so that
# everyone who runs the test benefits from these saved cases.
cc 1f8c3a2b9d4e7f5a... # shrinks to ([0u8; 32], vec![RememberOp::Empty, RememberOp::Empty])
cc 8d4e7a3b1c2f9e6d... # shrinks to ([1u8; 32], vec![RememberOp::Large(N)])
```

### The CI gate

```bash
#!/usr/bin/env bash
# scripts/check-proptest-regressions-tracked.sh
set -euo pipefail
workspace="${1:?usage: $0 <workspace>}"
cd "$workspace"

# (a) Every property test source file must have either no regressions yet, or
#     a tracked `proptest-regressions/<test>.txt`.
fails=0
while IFS= read -r -d '' test_file; do
  test_name=$(basename "$test_file" .rs)
  test_dir=$(dirname "$test_file")
  regression_file="$test_dir/proptest-regressions/${test_name}.txt"

  # If the regression file exists, it MUST be tracked.
  if [[ -f "$regression_file" ]]; then
    if ! git ls-files --error-unmatch "$regression_file" >/dev/null 2>&1; then
      echo "ERROR: untracked regression file: $regression_file"
      fails=$((fails + 1))
    fi
  fi
done < <(find . -path '*/tests/properties/*.rs' -print0)

# (b) `.gitignore` must explicitly include `proptest-regressions/` (or be silent on it).
if grep -E '^[!]?proptest-regressions/?$' .gitignore 2>/dev/null \
   | grep -v '^!proptest-regressions' >/dev/null; then
  echo "ERROR: .gitignore excludes proptest-regressions; add '!proptest-regressions/' override"
  fails=$((fails + 1))
fi

if [[ $fails -gt 0 ]]; then
  echo "Failed $fails proptest-regression-discipline check(s)"
  exit 64
fi
echo "All proptest regression files are tracked."
```

### The replay-still-reproduces audit (per-round, Phase 11 entry)

```rust
//! crates/<port>-harness/src/proptest_regression_auditor.rs

/// For every property test with a checked-in regression file, replay each seed
/// and report whether it still drives the test to its assertion (i.e., still
/// exercises the originally-counterexample-producing code path).
///
/// Three outcomes per seed:
///   - Reproduces: seed still fails → the bug is still open.
///   - SilentlyPassed: seed runs but assertion no longer fails → bug is fixed,
///                     witness preserved. (Expected and good.)
///   - PathDivergence: seed runs but does not exercise the originally-failing
///                     code path → seed has lost its signal value, FLAG.
pub fn audit_regressions(
    workspace: &Path,
) -> Result<RegressionAuditReport, AuditError> {
    let mut report = RegressionAuditReport::default();
    for entry in walk_property_tests(workspace) {
        let regression_path = entry.regression_file_path();
        if !regression_path.exists() {
            continue;
        }
        let seeds = parse_regression_file(&regression_path)?;
        for seed in seeds {
            let outcome = replay_seed_with_coverage(&entry.test_path, &seed)?;
            report.add(entry.clone(), seed, outcome);
        }
    }
    Ok(report)
}
```

The audit's `RegressionAuditReport` is emitted as `<workspace>/round_<N>/proptest_audit.md` and the orchestrator surfaces any `PathDivergence` as a yellow on Phase 11.

## Minimization preservation rule

When a property bug is fixed:

1. **Do not delete the regression seed.** Run the test; verify the seed now passes (i.e., `SilentlyPassed` per the audit).
2. **Add a comment to the regression file** annotating the fix: `# bd-1234: fixed in commit abc123 on 2026-04-12`.
3. **Bank the fix in the conformance ledger** per [pattern:180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) (positive-evidence half: the property-bug ledger).

The regression file grows over the project's lifetime; that's expected. Auto-trim (proptest can be configured to drop old seeds) is **forbidden**. If the file becomes unwieldy (>1MB), break the property into smaller properties; do not delete seeds.

## Variants per project class

| Class | Common property shapes | Regression-file lifetime |
|---|---|---|
| **SQL-class** | "every SELECT with ORDER BY produces sorted output", "WAL replay is idempotent" | Long; SQL semantics are stable, seeds rarely lose signal |
| **RESP-class** | "RESP3 frames round-trip", "MULTI/EXEC is atomic under fault" | Medium; RESP3 type-tag changes can invalidate seeds |
| **Numerical-Python** | "ufunc dispatch is dtype-promotion-stable", "PCG64DXSM stream is bit-exact" | Long; numerical semantics rarely shift |
| **ML-System** | "softmax sum-to-one within ε", "autograd-vs-JVP within ε" | Medium; CUDA-kernel updates can shift ULP and invalidate seeds (re-audit on every device-driver upgrade) |
| **HTTP-Protocol** | "request-response causality", "idempotency-key honored" | Long; HTTP semantics are RFC-stable |
| **Greenfield-Rust** | Project-defined; for eidetic: "every `pack` respects token budget", "every `recall` is deterministic in (query, state)" | Long if spec is stable; the regression file IS the contract |

### Per-class config table

| Class | `cases` default | `max_local_rejects` | `failure_persistence` directory |
|---|---|---|---|
| SQL | 256 (4096 for soak) | 65_536 | `tests/properties/proptest-regressions/` |
| RESP | 256 | 16_384 | same |
| Numerical-Python | 64 (more expensive setup) | 8_192 | same |
| ML-System | 32 | 1_024 | same |
| HTTP-Protocol | 256 | 16_384 | same |
| Greenfield-Rust | 1024 (sparse oracle, want more coverage) | 65_536 | same |

## Failure modes

| Failure | Symptom | Detection | Fix |
|---|---|---|---|
| **Regressions gitignored** | First property failure shrinks counterexample; `git status` shows nothing new; agent assumes "no regression file produced"; CI fails next round on a different seed. | `scripts/check-proptest-regressions-tracked.sh` runs at Phase 14. | `.gitignore` must include `!proptest-regressions/`; CI hard-fails if any property test directory is missing the override. |
| **Deleted on minimization** | Property bug fixed; regression file deleted in the same commit; six months later, refactor reintroduces the bug; nobody notices. | Audit `git log -p proptest-regressions/` for deletions; flag any deletion not in a "regression-file-pruning" commit. | Regression-file deletion is forbidden by a `.git/hooks/pre-commit` check; the only allowed way to remove a seed is to break the property into a new one with a clean regression slate. |
| **Replayed without verifying it still reproduces** | Bug was fixed but seed comment never updated; agent reading the file thinks the bug is still open and re-opens an investigation. | Regression-auditor's `SilentlyPassed` outcome should produce a comment-update prompt. | Add `# bd-NNNN: fixed in <sha>` comment on fix; auditor surfaces uncommented `SilentlyPassed` seeds as P12 cleanup work. |
| **Per-machine cache used instead of in-tree dir** | Default `Config::default()` puts files in `~/.cache/proptest`; nothing is checked in. | CI grep for `Config::default()` in property test files. | Mandatory `standard_config()` helper; CI rejects PRs that construct a `Config` directly. |
| **Per-test config drift** | Some tests use 100 cases, some 10000; coverage claim varies per-test in unprincipled ways. | Audit `with_cases(N)` overrides; flag any that diverge from the per-class default without rationale. | Per-class config catalog with rationale documented; per-test override requires a comment citing the rationale. |
| **Regression file format drift across proptest versions** | Bumping `proptest` from 1.4 → 1.5 changes the regression file header; old files become unreadable. | CI `cargo test` failure on stale regression file. | `proptest` version pinned in `spec_version_contract.toml#[property_suite].proptest_version`; bumps go through [pattern:31-SCHEMA-VERSION-MIGRATION-DUAL-READER](31-SCHEMA-VERSION-MIGRATION-DUAL-READER.md). |
| **PathDivergence accumulating silently** | Seeds increasingly fail to exercise the originally-counterexample code path; regression suite becomes coverage-theater. | Auditor's `PathDivergence` count metric per round; threshold-alarm at 10% of seeds. | Quarterly P12 cleanup bead: prune divergent seeds, regenerate via fresh fuzz with current code, replace. |
| **Auditor's coverage check missing** | Replay reports "all green" because every seed just runs; no check that they exercise the test's intent. | Audit needs `replay_seed_with_coverage` (instrumented), not naive `replay_seed`. | Instrument via cargo-llvm-cov or per-test branch-coverage assertions; "the seed must hit assertion N or the originally-counterexample-producing branch B" is the contract. |
| **Property suite version not pinned** | Property suite at commit X for the harness vs commit Y for the test runner; ambiguous which `prop_*` definitions apply. | `[property_suite]` block in `spec_version_contract.toml` ([`SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) §2). | Pin `property_suite_version` SHA; `[property_count_floor = 50]` to prevent silent regression. |
| **Property count drops below floor** | Refactor removes 30 properties; release ships with 20 instead of 50. | `[property_count_floor]` check at release gate. | Release-blocker; properties can be replaced but not net-removed. |

## Cross-references

- [pattern:06-5-MODE-ORACLE-DISPATCH](06-5-MODE-ORACLE-DISPATCH.md) — `OracleMode::Property.regression_seeds` references file paths produced by this pattern.
- [pattern:11-SPEC-TAG-EXTRACTION](11-SPEC-TAG-EXTRACTION.md) — every property maps back to a `[SPEC-NNN]` tag; the property is the implementation of the verifier.
- [pattern:31-SCHEMA-VERSION-MIGRATION-DUAL-READER](31-SCHEMA-VERSION-MIGRATION-DUAL-READER.md) — proptest regression format bumps go through dual-reader.
- [pattern:40-METAMORPHIC-TRANSFORMS](40-METAMORPHIC-TRANSFORMS.md) — metamorphic relations are commonly expressed as proptest properties.
- [pattern:45-MISMATCH-MINIMIZER](45-MISMATCH-MINIMIZER.md) — proptest's shrinker is the per-test minimizer; this pattern preserves its output.
- [pattern:55-INSTA-GOLDEN-SNAPSHOTS](55-INSTA-GOLDEN-SNAPSHOTS.md) — sibling discipline for golden snapshots; both `tests/snapshots/` and `proptest-regressions/` are checked-in artifacts.
- [pattern:60-FAULT-VFS](60-FAULT-VFS.md) — fault-injected properties have especially long-lived regression seeds.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — property failures populate failure bundles; the regression seed is one of the bundle's reproducibility primitives.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — `fail-missing-evidence` if a property fails in CI but no regression file is committed.
- [pattern:275-THEORY-KILL-IMMEDIATE-CLOSE](275-THEORY-KILL-IMMEDIATE-CLOSE.md) — when a property's NO_EVIDENCE outcome lands, the regression file's annotation cycle closes the loop.
- [`../methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) §6 — property-Oracle authoring uses this pattern as the artifact spec.
- [`../methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) §2 — `[property_suite]` contract block.
- [`../../subagents/roundtrip-corpus-author.md`](../../subagents/roundtrip-corpus-author.md) — owns the per-roundtrip property authoring + regression-file lifecycle (greenfield + serialization-heavy projects). For port classes, the per-class oracle-test-author subagents per [`../../assets/integration-test-templates/`](../../assets/integration-test-templates/) own this lifecycle.
- [`../../assets/property-test-templates/sql_proptest.rs`](../../assets/property-test-templates/sql_proptest.rs) — template that uses `standard_config()`.
