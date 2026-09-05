# runbook-author

> Phase 16 • Assemble `PARITY_RUNBOOK.md` — the maintainer-facing operations manual for keeping the port at parity going forward.

## Inputs

- `<workspace>/FINAL_GAUNTLET_REPORT.md` (written first by `final-report-author`).
- `<workspace>/phase14_fresh_eyes_diff.md` (the cumulative remediation diff that shipped).
- `<workspace>/phase15_soak_designs.md` + per-soak campaign result jsons.
- Project-class verdict from `<workspace>/phase0_project_class.json` (drives per-class CI gates).
- The four contract files from Phase 2: `<reference>_version_contract.toml`, `supported_surface_matrix.toml`, `canonical_parity_contract.md`, `parity_score_contract.toml`.
- All three negative-evidence ledgers.

## Deliverables

- `<workspace>/PARITY_RUNBOOK.md` — pinned to `assets/parity-runbook-template.md`.
- `<workspace>/phase16_runbook.md` — authorship metadata pointer.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase16-runbook`
- **Reservations needed:** `tool://runbook-author` (exclusive, TTL 30m).
- **Lane:** orchestrator.

## Verbatim Prompt

```
You are the runbook-author for Phase 16. Your job is to write PARITY_RUNBOOK.md — a maintenance-mode document the project's owners will read when (a) onboarding a new contributor, (b) wiring CI gates, (c) responding to a regression alert. The runbook must work months from now without you in the loop.

INPUTS (read all before writing):
- <workspace>/FINAL_GAUNTLET_REPORT.md
- <workspace>/phase14_fresh_eyes_diff.md
- <workspace>/phase0_project_class.json
- <workspace>/docs/contracts/*.toml + canonical_parity_contract.md
- <workspace>/PERF_NEGATIVE_RESULTS.md + CONFORMANCE_NEGATIVE_RESULTS.md + SURFACE_DEFERRALS.md

SECTIONS (in this order):

1. **CI Gates to Wire** — paste-ready GitHub Actions step blocks for each:
   - Per-category-weighted score ratchet (calls `scripts/apply-ratchet.sh`).
   - Pass-over-pass throughput gate (compares `.bench-history/*.latest.json` to current).
   - Conformance-lower-bound ratchet (calls `scripts/compute-parity-score.sh` → ratchet).
   - Feature-coverage-dashboard release-gate (calls `scripts/compute-feature-coverage.sh`).
   - E-process alarms (e-value crosses `1/α` → fail build, attach FailureBundle).
   - BOCPD regime alarms (regime != Stable → warn; ShiftDetected → block).
   - Fault-VFS budget (count of `fsqlite_test_vfs_faults_injected_total` per CI run).
   - Crash-boundary coverage (every named boundary armed at least once per release).
   - Flake budget (cv_pct > 5 on a microbench across 3 consecutive runs → flake-quarantine bead).
   - Bead-graph validator (`scripts/bead-graph-validator.sh`).
   - Convergence-tracker (`scripts/convergence-tracker.sh`, advisory after release).

2. **Snapshots to Keep Green** — list every insta snapshot the harness maintains (planner output, VDBE bytecode / RESP frame sequences / OpenAPI schemas / JIT-compiled IR — whichever applies). Per snapshot: file path, regeneration command, the discipline ("regenerate only when the underlying contract changes; never to make a red test green").

3. **Fuzz Corpora to Preserve** — every `fuzz/corpus/<target>/` and `proptest-regressions/*.txt` directory. Per corpus: size, last-minimization date, the regeneration cost.

4. **`// SAFETY:` Template** — paste-ready. Every `unsafe` block must carry a `// SAFETY:` comment that names: the invariant being upheld, the precondition the caller must guarantee, the postcondition the block establishes, the witness (test/fuzz/miri run that exercises it). Show one annotated example for each unsafe primitive the port uses.

5. **Clippy Lint Group Minimum** — `[lints.rust]` and `[lints.clippy]` blocks for Cargo.toml. At minimum: `unsafe_op_in_unsafe_fn = "forbid"`, `clippy::pedantic = "warn"`, `clippy::missing_safety_doc = "deny"`. Per project class, add domain-specific lints.

6. **AGENTS.md Mandate Paragraph** — verbatim from ../assets/agents-md-mandate-paragraph.md. Paste-ready for the project's AGENTS.md. Includes the 60-day cass-mining paragraph + ledger-grep-before-perf-work rule + project-specific failure-term list (pull from ../references/taxonomy/PROJECT-CLASSES.md row matching phase0_project_class.json).

7. **Negative-Ledger Format** — the mandatory-fields table + the retry-condition vocabulary + the forbidden-phrase list ("later", "if it seems important", "we should revisit", "tracked elsewhere"). Show 3 verbatim sample entries from the project's own ledger.

8. **Retry-Condition Vocabulary** — the 8 verbatim templates from ../references/methodology/RETRY-CONDITION-VOCABULARY.md.

9. **When To Escalate** — concrete triggers: e-value crosses 1/α; BOCPD ShiftDetected for 2+ windows; conformal lower-bound drops below ratchet floor; FeatureUniverse loader rejects on weight-sum; cv_pct > 5 three runs in a row on the primary bench.

10. **Resuming the Gauntlet** — exact commands to re-run a fresh round of Phases 5-10 against a moved-forward main branch. Cross-reference ../references/PHASES.md.

OUTPUT FORMAT:
- Markdown only.
- Frontmatter: name, generated_at_utc, schema_version (`gauntlet.parity-runbook.v1`), project_class, run_id.
- Every command is paste-ready (literal, no `<placeholder>` unless it's a fillable arg the maintainer supplies at runtime).

EXIT CRITERIA:
- All 10 sections populated.
- Every CI-gate block is syntactically valid YAML.
- Every `// SAFETY:` example is a real example from the port's source (grep first).
- Frontmatter well-formed.
```

## Exit Criteria

- `PARITY_RUNBOOK.md` exists with all 10 sections populated.
- Every CI-gate YAML block parses (run a YAML-lint mental check).
- Every cited file path exists in the port.
- Frontmatter YAML well-formed; `schema_version: gauntlet.parity-runbook.v1`.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 16)
- [../references/methodology/RETRY-CONDITION-VOCABULARY.md](../references/methodology/RETRY-CONDITION-VOCABULARY.md)
- [../references/taxonomy/PROJECT-CLASSES.md](../references/taxonomy/PROJECT-CLASSES.md)
- [../assets/parity-runbook-template.md](../assets/parity-runbook-template.md)
- [../assets/agents-md-mandate-paragraph.md](../assets/agents-md-mandate-paragraph.md)
