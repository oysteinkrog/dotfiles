# certification-bundler

> Phase 16 • Assemble `RELEASE_CERTIFICATION_TEMPLATE.md` + the `certification_bundle/` directory — the strict-conformant-release.v1 evidence pack.

## Inputs

- `<workspace>/FINAL_GAUNTLET_REPORT.md` (already written by `final-report-author`).
- `<workspace>/PARITY_RUNBOOK.md` (already written by `runbook-author`).
- `<workspace>/reports/ratchet_state.json`.
- `<workspace>/.bench-history/*.latest.json` (per primary bench).
- `<workspace>/scorecards.json` (parity score, per-category, conformal lower bound).
- The four contract files from Phase 2.
- All `phase15_*_result.json` soak campaign outputs.
- Every per-bead `artifacts/{bead_id}/proof_pack/*` directory referenced by closed remediation beads.

## Deliverables

- `<workspace>/RELEASE_CERTIFICATION_TEMPLATE.md` — pinned to `assets/release-certification-template.md`.
- `<workspace>/certification_bundle/` directory containing:
  - `confidence_gate.json`
  - `verification_contract.json`
  - `release_certificate.json`
  - `ci_artifact_manifest.json`
  - `benchmark_summary.json`
  - `scorecards.json` (copy from workspace root)
  - `critical_path_report.json` (from `bv --robot-insights`)
  - `ratchet_state.json` (copy)
  - `BUNDLE_MANIFEST.json` — top-level inventory: every file in the bundle + SHA-256 + schema_version + source-phase.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase16-cert-bundler`
- **Reservations needed:** `tool://certification-bundler` (exclusive, TTL 60m).
- **Lane:** orchestrator.

## Verbatim Prompt

```
You are the certification-bundler for Phase 16. Your job is to assemble the strict-conformant-release.v1 evidence pack. The bundle must let an external auditor reproduce every claim in FINAL_GAUNTLET_REPORT.md from artifacts alone — no questions to the agent, no questions to the maintainer.

INPUTS (READ ALL first):
- <workspace>/FINAL_GAUNTLET_REPORT.md
- <workspace>/PARITY_RUNBOOK.md
- <workspace>/reports/ratchet_state.json
- <workspace>/.bench-history/*.latest.json
- <workspace>/scorecards.json
- <workspace>/docs/contracts/*.toml + canonical_parity_contract.md
- <workspace>/phase15_*_result.json
- Every artifacts/{bead_id}/proof_pack/ for every CLOSED remediation bead (cross-ref phase13_beads_summary.md)

REQUIRED-PASS CONSTANTS (load-bearing, must hold for release-certifying = true):

  CERTIFICATION_MIN_VERIFICATION_PCT          = 100.0
  CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT  = 100.0
  CERTIFICATION_MAX_HIGH_SEVERITY_COUNTEREXAMPLES = 0
  CERTIFICATION_MAX_EVIDENCE_AGE_HOURS        = 24

Refer to ../references/methodology/CERTIFICATION.md for the full constants table.

STEPS:

1. Verify every required-pass constant against the workspace state. If ANY fails,
   write certification_bundle/RELEASE_BLOCKED.md explaining which constant
   failed and what evidence is missing; do NOT proceed.

2. Build certification_bundle/confidence_gate.json:
   {
     "schema_version": "gauntlet.confidence_gate.v1",
     "lower_bound": <truncate_score from scorecards.json>,
     "ratchet_floor": <from ratchet_state.json>,
     "decision": "Allow" | "Block" | "Quarantine" | "Waiver",
     "evidence_artifact_paths": [...]
   }

3. Build certification_bundle/verification_contract.json — every FeatureUniverse
   entry's ParityStatus + ProofObligation status (from
   parity_invariant_catalog.rs output JSON). Schema: gauntlet.verification_contract.v1.

4. Build certification_bundle/release_certificate.json:
   {
     "schema_version": "strict-conformant-release.v1",
     "generated_at_utc": <ISO 8601>,
     "run_id": <run_id>,
     "port_name": <port>,
     "reference_name": <reference>,
     "reference_version": <pinned version from version_contract.toml>,
     "convergence_evidence": {
      "round_count": <int >= 10>,
      "clean_last_two": true,
      "last_two_findings": [<int>, <int>],
      "open_hypothesis_count": 0
     },
     "required_pass_checks": {
       "min_verification_pct":       {"required": 100.0, "actual": <X>, "pass": bool},
       "required_suite_pass_rate":   {"required": 100.0, "actual": <X>, "pass": bool},
       "max_high_sev_counterexamples": {"required": 0,   "actual": <X>, "pass": bool},
       "max_evidence_age_hours":     {"required": 24,    "actual": <X>, "pass": bool}
     },
     "certifying": <true ONLY if every pass:true>,
     "bundle_manifest_sha256": <sha256 of BUNDLE_MANIFEST.json>
   }

5. Build certification_bundle/ci_artifact_manifest.json — list every CI artifact
   the release depends on (workflow file, gates, snapshot files, fuzz corpora).
   Each entry: artifact_path + sha256 + producing_workflow + last_modified.

6. Build certification_bundle/benchmark_summary.json — collated per-bench primary
   score + per-category weighted score + cv_pct + git_sha. Source: .bench-history/*.latest.json.

7. Copy scorecards.json and ratchet_state.json verbatim.

8. Build certification_bundle/critical_path_report.json — pipe `bv --robot-insights`
   on the workspace's .beads/ and extract the CriticalPath section.

9. Build certification_bundle/BUNDLE_MANIFEST.json — top-level inventory:
   {
     "schema_version": "gauntlet.certification_bundle_manifest.v1",
     "files": [{"path": "...", "sha256": "...", "schema_version": "...", "source_phase": "..."}, ...],
     "bundle_root_sha256": <sha256 of sorted concatenation of file sha256s>
   }

10. Render RELEASE_CERTIFICATION_TEMPLATE.md from ../assets/release-certification-template.md
    by substituting actual values from the bundle. Embed the BUNDLE_MANIFEST.json
    SHA-256 in the template's frontmatter.

EXIT CRITERIA:
- All 9 bundle files exist.
- BUNDLE_MANIFEST.json well-formed; bundle_root_sha256 reproducible.
- release_certificate.json["certifying"] = true (or RELEASE_BLOCKED.md written).
- Every cited artifact path exists and matches its declared sha256.
- Top-of-file frontmatter on RELEASE_CERTIFICATION_TEMPLATE.md is well-formed YAML.
```

## Exit Criteria

- `certification_bundle/` exists with all 9 required JSON files + `RELEASE_CERTIFICATION_TEMPLATE.md`.
- `BUNDLE_MANIFEST.json` lists every file with `sha256` + `schema_version` + `source_phase`.
- `release_certificate.json["certifying"]` is `true` — OR `RELEASE_BLOCKED.md` is written explaining the failure.
- Bundle is reproducible: re-running on the same workspace yields a bitwise identical `bundle_root_sha256`.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 16)
- [../references/methodology/CERTIFICATION.md](../references/methodology/CERTIFICATION.md)
- [../references/methodology/IDENTITY-AND-REPRODUCIBILITY.md](../references/methodology/IDENTITY-AND-REPRODUCIBILITY.md)
- [../assets/release-certification-template.md](../assets/release-certification-template.md)
