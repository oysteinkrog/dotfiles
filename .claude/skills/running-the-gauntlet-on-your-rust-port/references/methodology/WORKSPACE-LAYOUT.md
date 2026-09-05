# Workspace Layout Specification

Pinned directory layout for `<project>__gauntlet_workspace/`. Every script and subagent assumes this structure; deviation breaks resumability. This file is the canonical reference; deviations need a corresponding update here + a `phase0_workspace_layout_revision.md` entry.

## Top-level

```
<project>__gauntlet_workspace/
├── .git/                                    # git init'd at Phase 0; every artifact version-controlled
├── .beads/issues.jsonl                      # bead graph (seeded from assets/beads-seed/issues.jsonl)
├── .claude/settings.json                    # local hooks (if hooks-installer ran)
├── MEMORY.md                                # session index (≤200 lines); per methodology/MEMORY-MD-CONVENTION.md
├── README.md                                # one-pager: what this workspace is for + how to resume
├── AGENTS.md                                # the gauntlet mandate paragraph + project-specific failure terms
├── convergence_tracker.json                 # state machine; written by convergence-tracker.sh
├── PERF_NEGATIVE_RESULTS.md                 # perf-pillar negative ledger (seeded from assets/negative-ledger-seed.md)
├── CONFORMANCE_NEGATIVE_RESULTS.md          # conformance-pillar
├── SURFACE_DEFERRALS.md                     # surface-pillar
├── GAUNTLET_EXPERIMENT_DESIGNS.md           # cross-pillar hypothesis ledger
├── PERF_HYPOTHESIS_LEDGER.md                # perf-only hypotheses
├── CONFORMANCE_HYPOTHESIS_LEDGER.md         # conformance-only hypotheses
├── SURFACE_PARITY_HYPOTHESIS_LEDGER.md      # surface-only hypotheses
├── FINAL_GAUNTLET_REPORT.md                 # rendered at Phase 16 (absent until convergence)
├── PARITY_RUNBOOK.md                        # rendered at Phase 16
├── RELEASE_CERTIFICATION_TEMPLATE.md        # rendered at Phase 16
├── docs/
│   ├── contracts/
│   │   ├── <reference>_version_contract.toml
│   │   ├── supported_surface_matrix.toml
│   │   ├── canonical_parity_contract.md
│   │   ├── parity_score_contract.toml
│   │   ├── eprocess_calibration.toml
│   │   └── ulp_tolerance_v1.toml            # ML-class only
│   ├── design/                              # ADRs + design docs the agent produces
│   └── progress/                            # mirrors of the three negative ledgers (legacy path)
├── reports/
│   ├── ratchet_state.json                   # monotonic per-pillar lower bounds
│   ├── ratchet_history.jsonl                # append-only audit
│   ├── scorecards.json                      # current parity scorecard
│   └── ratchet_audit_<date>.md              # rendered by ratchet-curator at Phase 16
├── scripts/                                 # pinned copy of skill scripts; used by generated CI workflows
│   ├── gauntlet.sh
│   ├── compute-parity-score.sh
│   ├── compute-feature-coverage.sh
│   ├── apply-ratchet.sh
│   └── ...
├── waivers/
│   └── <date>-<slug>.md                     # structured dated waivers (waiver-author)
├── .bench-history/
│   └── <bench-name>.latest.json             # pass-over-pass gate input; committed to git
├── tcl_reference_baseline/                  # SQL-class only; captured by run-tcl-tests.sh
│   └── *.expected
├── tests/
│   ├── fixtures/                            # gauntlet-side fixtures (separate from port fixtures)
│   └── artifacts/perf/<lane>/               # per-lane perf artifacts (mirrored from port if desired)
├── bible_excerpts/                          # offline-reference excerpts (extract-from-bibles.sh)
│   ├── INDEX.md
│   ├── vocab.md
│   ├── optimizations.md
│   ├── math_toolkit.md
│   ├── skills_map.md
│   ├── sibling_status.md
│   └── codex_*.md
├── cass_findings_<run_id>.jsonl             # per-run cass-miner output
├── cass_findings_<run_id>_summary.md
├── numpy_all.json                           # Numerical-class only
├── numpy_coverage.json                      # Numerical-class only
├── resp_protocol_diff.txt                   # RESP-class only
├── openapi_port.canonical.json              # HTTP-class only
├── openapi_reference.canonical.json         # HTTP-class only
├── openapi_schema_diff.txt                  # HTTP-class only
├── gradcheck_results.json                   # ML-class only
├── replay/<bundle-sig>-<commit-sha>/        # one dir per replay run
├── orchestrator.log                         # gauntlet.sh top-level log
├── sessions/                                # per-session detail files (methodology/MEMORY-MD-CONVENTION.md)
│   └── session_<NNN>_<topic>.md
├── round_<N>/                               # per-iteration artifacts
│   ├── conformance_findings.json
│   ├── perf_findings.json
│   ├── surface_findings.json
│   ├── mt8_profile.{flame.svg,samply.json}
│   ├── mt8_top_frames.json
│   ├── mt8_attribution_index.md
│   ├── tcl_results.jsonl                    # SQL-class only
│   ├── tcl_summary.md                       # SQL-class only
│   ├── tcl_actual/                          # SQL-class only
│   ├── tcl_failures/<sig>/                  # SQL-class only
│   └── <pillar>_failures/<sig>/             # FailureBundles
│       └── bundle.json
├── phase0_workspace_init.md
├── phase0_toolchain_inventory.json
├── phase0_project_class.json
├── phase0_skill_inventory.json
├── phase0_intake.json
├── phase0_hooks_installed.md                # if hooks-installer ran
├── phase1_recon_<crate>.md                  # one per crate
├── phase1_unified_recon.md                  # collated by synthesizer
├── phase2_scope_decision.md
├── phase3_oracle_wiring.md
├── phase4_golden_capture.md
├── phase5_perf_harness.md
├── phase6_conformance_harness.md
├── phase7_surface_inventory.md
├── phase8_ledger_seeded.md
├── phase9_baseline_summary.md
├── phase10_idea_wizard_yield.md
├── phase11_loopback_required.md             # only if a soak run surfaces a regression
├── phase12_remediation_index.md
├── phase12_remediation_<gap>.md             # one per gap
├── phase13_beads_summary.md
├── phase14_fresh_eyes_diff.md
├── phase14_fresh_eyes_round_<N>/            # per-round fresh-eyes artifacts
├── phase14_red_team_<lens>.md               # if red-team-attacker ran
├── phase14_red_team_<lens>/<finding>/       # per-finding reproducers
├── phase14_triangulation_<lens>/            # if triangulator ran
├── phase15_soak_designs.md
├── phase15_soak_fuzz/<target>/
├── phase15_soak_miri/<crate>/
├── phase15_soak_loom/<test>/
├── phase15_soak_crash/<boundary>/
├── phase15_soak_bocpd/
├── phase15_soak_adversarial/<gate>/
├── phase16_final_report.md
├── phase16_runbook.md
├── phase16_certification.md
├── certification_bundle/                    # rendered at Phase 16
│   ├── BUNDLE_MANIFEST.json
│   ├── confidence_gate.json
│   ├── verification_contract.json
│   ├── release_certificate.json
│   ├── ci_artifact_manifest.json
│   ├── benchmark_summary.json
│   ├── scorecards.json
│   ├── critical_path_report.json
│   └── ratchet_state.json
├── cookbook/                                # rendered at Phase 16 by cookbook-author
│   ├── INDEX.md
│   ├── PROJECT-SPECIFIC-MOTIONS.md
│   └── <motion-slug>.md
├── sibling_audits/                          # rendered by sibling-status-auditor
│   ├── <sibling>_<date>.md
│   └── <sibling>_next_actions.md
└── onboarding_<role>_<expertise>.md         # rendered by knowledge-transfer
```

## Conventions

- **Read-only after commit**: every `phase<N>_*.md` is read-only after the phase commits. To revise, write `phase<N>_*_revision_<M>.md` (append-only).
- **Round directories**: `round_<N>/` is sealed at the end of each round. New round = `round_<N+1>/`.
- **Per-class branches**: SQL/RESP/Numerical/ML/HTTP-only files are absent for other classes (e.g., `tcl_reference_baseline/` doesn't exist for RESP-class).
- **Resumability test**: every script that reads from `<workspace>/` must check the file exists; missing file = write a `RESUMABILITY_BROKEN.md` entry per [`methodology/COMPACTION-SURVIVAL.md`](COMPACTION-SURVIVAL.md).

## Git policy

The workspace's `.git/` is the workspace's own history (NOT the port's git). Conventions:

- Every artifact is staged + committed before the next phase begins.
- Branch model: stay on `main`; the workspace is single-trunk.
- Commit message format: `phase<N>: <one-line summary>` or `round_<N>: <one-line summary>`.
- The `landing-the-plane.sh` hook (if installed) enforces "no uncommitted changes at Stop".
- The workspace's git history is the audit trail.

## What is NOT in the workspace

- The port's source code (lives in `<project>/`).
- The port's `.beads/` (lives in `<project>/.beads/`).
- Built binaries (live in `<project>/target/`).
- The two bibles (read-only on the host filesystem at `/data/projects/frankensqlite/`).

The workspace is the **gauntlet's working memory**; the port is the **subject under test**.
