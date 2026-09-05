# VERIFICATION-FIRST.md — Toolchain Discipline

This skill's methodology is evergreen — first-principles classification, operator library, polish bar. But the TOOLCHAIN it depends on is volatile:

- `miri` changes with every nightly; flags get renamed, defaults shift.
- `loom` API has had breaking changes between 0.5, 0.6, 0.7.
- `cargo-fuzz` requires libfuzzer linking that breaks on new Rust nightlies sometimes.
- `cargo-careful` is sometimes-blocked by rustc internal API churn.
- `cargo-geiger` count semantics changed across versions; comparing across versions can be apples-to-oranges.

**Core rule.** Do not claim a rewrite is sound until it has passed the harness AS RUN ON THE EXACT NIGHTLY + EXACT CRATE VERSIONS recorded in `<audit-dir>/phase0_toolchain.json` AND logged in `<audit-dir>/audit/phase9/verify.log`. A green run on a single commit is not a proof of soundness; it's a successful experiment.

---

## Audit trail required

Every tool run records:
- Tool name + version (e.g., `miri 0.1.0 nightly-2026-05-12`).
- Exact command line.
- Exit status.
- Stdout + stderr verbatim.

Captured by `scripts/verify.sh` and tee'd to per-tool log files under `<audit-dir>/audit/phase9/`.

If a reviewer cannot reproduce the harness run from the recorded versions, the audit is not finished.

---

## Pinning the nightly

```bash
# Phase 0 records the nightly version used:
rustc +nightly --version --verbose | tee -a <audit-dir>/phase0_toolchain.json
```

Don't `rustup update` mid-audit. If a nightly bug surfaces, document it; if a fix lands on a newer nightly, document the upgrade decision in `<audit-dir>/phase0_toolchain.json § upgrades`.

For long audits (>1 day), pin to a specific nightly date:

```bash
rustup install nightly-2026-05-12
rustup default nightly-2026-05-12  # or use +nightly-2026-05-12 explicitly
```

This avoids surprise drift mid-run.

---

## Per-tool reproduce-ability

### miri

```json
{
  "tool": "miri",
  "rustc_version": "rustc 1.92.0-nightly (a1b2c3d4 2026-05-12)",
  "miri_version": "miri 0.1.0",
  "miri_flags": "-Zmiri-strict-provenance -Zmiri-disable-isolation",
  "sysroot": "/home/ubuntu/.cache/miri/HOST-aarch64-unknown-linux-gnu-stable",
  "command": "cargo +nightly miri test --workspace --all-features"
}
```

If miri's behavior changes between two runs of the SAME command, file as a miri bug (and link the bug in `<audit-dir>/audit/phase9/verify.log`). Don't suppress the inconsistent run.

### loom

```json
{
  "tool": "loom",
  "loom_version": "0.7.x",
  "rustflags": "--cfg loom",
  "preemption_bound": 3,
  "max_branches": null,
  "command": "RUSTFLAGS=\"--cfg loom\" cargo test --features loom_concurrency_tests --release"
}
```

Loom's coverage depends on `preemption_bound`. Record it. A "loom-green at preemption_bound=2" is different from "loom-green at preemption_bound=4".

### cargo-fuzz

```json
{
  "tool": "cargo-fuzz",
  "fuzz_version": "0.12.x",
  "libfuzzer_version": "linked-from-rustc-nightly-...",
  "max_total_time_seconds_per_target": 60,
  "targets": ["target_a", "target_b"],
  "corpus_dirs": ["fuzz/corpus/target_a", "..."]
}
```

For sustained fuzzing (CI nightly), bump `max_total_time` and persist `fuzz/corpus/` across runs. The corpus IS the audit trail — keep it under version control.

### cargo-mutants

```json
{
  "tool": "cargo-mutants",
  "mutants_version": "25.x",
  "in_place": false,
  "jobs": 4,
  "skip_calls": ["std::process::exit"],
  "outcome_path": "audit/phase9/mutants/outcomes.json"
}
```

`cargo mutants` is slow. For weekly CI, run on diff-only mode: `cargo mutants --in-diff <main..HEAD>`.

### cargo-geiger

```json
{
  "tool": "cargo-geiger",
  "geiger_version": "0.12.x",
  "command": "cargo +nightly geiger --output-format Json --all-features",
  "baseline_path": "phase1/*__geiger.json",
  "post_path": "geiger-after.json"
}
```

Don't compare geiger counts across geiger versions. The metric definition can drift.

---

## Verification flow per refactor change (audit-and-refactor mode)

For each authorized cluster/site change:

1. CI or local verification runs `verify.sh` against the active branch.
2. CI compares `cargo +nightly geiger` count to main's baseline; refuses if count went up.
3. Local re-run by the reviewer (`bash verify.sh`).
4. If everything is green AND the reviewer accepts the plan, merge or close out according to the repo workflow.

If `verify.sh` requires nightly + components a developer doesn't have, the PR template tells them how to install (links to TOOLCHAIN-RUNBOOK.md § Installation).

---

## Verification flow for `pre-release-soundness-gate` mode

The gate is automated:

1. `verify.sh` clean: required.
2. Geiger delta vs prior version: ≤ 0.
3. CI matrix green on default AND `safe-only`.
4. Every (A) site has a hardened SAFETY comment (verified by a doc-comment lint).
5. `REVIEWER_RESPONSES.md` exists with confidence ≥ Medium.

If any of these fails, `cargo publish` is gated. The skill writes a one-page report explaining which gate failed and how to remediate.

---

## When the toolchain is missing or broken

If `cargo +nightly miri test` fails to install or run on the target's platform:
- Skip miri; record the skip in `<audit-dir>/phase0_toolchain.json § skips` with explanation (e.g., "miri unavailable on aarch64-apple-darwin nightly-2026-05-12 — see rust-lang/miri#NNNN").
- Run all other tools.
- The audit summary line shows "VERIFY.SH: PARTIAL (miri skipped — reason: X)".

This is acceptable in modes where miri coverage is not required (e.g., `verify-only` on a project where prior audits already covered miri). It is NOT acceptable for `pre-release-soundness-gate`.

---

## Tool-specific known-bad versions

| Tool | Version | Issue |
|------|---------|-------|
| miri | versions paired with rustc nightlies that have a regression in stacked borrows (rare) | Pin to a known-good nightly |
| cargo-fuzz | with libfuzzer that doesn't match the rustc nightly | Reinstall with `--force` after rustup update |
| cargo-careful | versions tied to deprecated rustc internal APIs | Update to latest |
| loom | 0.5 vs 0.6 API changes | Pin per-crate; don't mix |
| cargo-geiger | 0.10 → 0.11 changed default include-set | Always specify `--output-format Json` and parse with explicit field selection |

Don't memorize this table — re-check at run start. Phase 0's `install-toolchain.sh --check` script reports any version drift since the last audit.

---

## When `verify.sh` reports green but you're not sure

The harness has limits. It doesn't:
- Prove ABSENCE of bugs — it tests known-class hazards.
- Cover targets miri can't run (link `extern` libraries).
- Cover concurrency interleavings beyond loom's preemption bound.
- Cover fuzz inputs beyond what libfuzzer can generate.

A green harness is necessary but not sufficient. The audit also relies on:
- Manual review (Phase 7 fresh-eyes, Phase 10 maintainer-empathy).
- Adversarial reclassification (Phase 6).
- Multi-model triangulation on the riskiest sites.

The honest claim after a green run: "We have not found UB. We have raised the bar for finding UB above our current toolchain's ceiling. We retain the residual risk in proportion to what we couldn't test."

That sentence belongs in the user-facing summary.
