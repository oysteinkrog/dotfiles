# CERTIFICATION — Strict-Conformant-Release.v1 Template

This file is the operational template for the gauntlet's release certificate (`strict-conformant-release.v1`). A certified release ships an evidence bundle that survives a hostile reading: every constant must hold exactly, every evidence class must be present, every gate must pass its ratchet, every artifact must be fresh and content-addressed. See [../../SKILL.md § Final Artifacts](../../SKILL.md) for where this template lands; the actual builder is `scripts/final-report-builder.sh` (gauntlet skill scripts dir). The certification bundle is what the project maintainers ship publicly.

---

## (a) Required-pass constants (verbatim)

These four constants are non-negotiable for a `strict-conformant-release.v1` claim:

```rust
const CERTIFICATION_MIN_VERIFICATION_PCT: f64 = 100.0;
const CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT: f64 = 100.0;
const CERTIFICATION_MAX_HIGH_SEVERITY_COUNTEREXAMPLES: u64 = 0;
const CERTIFICATION_MAX_EVIDENCE_AGE_HOURS: u64 = 24;
```

| Constant | Meaning | Failure mode if violated |
|---|---|---|
| `CERTIFICATION_MIN_VERIFICATION_PCT = 100.0` | Every required ProofObligation across the InvariantCatalog has been satisfied — no `pass | fail-missing-evidence | fail-invalid-references` returns "fail-*". | Certifies *less than the full claim*; release shippable only as a non-strict variant. |
| `CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT = 100.0` | The certifying-required test suite has 100% pass rate (not 99.9%, not "all but 3 flaky"). | A flaky suite signals harness instability; certifying a flaky harness propagates the lie. |
| `CERTIFICATION_MAX_HIGH_SEVERITY_COUNTEREXAMPLES = 0` | Zero `TrueDivergence`-classified mismatches; zero unresolved adversarial-search counterexamples; zero open Phase-15 critical beads. | A single open high-severity counterexample defeats the certification. |
| `CERTIFICATION_MAX_EVIDENCE_AGE_HOURS = 24` | Every cited artifact (bench JSON, oracle suite, fault VFS recovery, e-process log, ratchet state) has `timestamp` within 24 hours of the certification timestamp. | Stale evidence may not reflect the current source; the certification cannot rest on aged proof. |

The constants live in `certification_policy.rs` (per MINING-3 §15 bootstrapping day-60). The CI gate that enforces them is `scripts/check-certification-constants.sh`.

---

## (b) Evidence-bundle classes

The certification bundle is a directory containing these eight classes; each is content-addressed and the bundle as a whole is signed.

### 1. Confidence gate JSON — `bundle/confidence_gate.json`
```jsonc
{
  "schema_version": "confidence_gate.v1",
  "release_decision": "Allow",          // Allow | Block | Quarantine | Waiver
  "evidence_age_hours": 4.2,
  "min_verification_pct_observed": 100.0,
  "required_suite_pass_rate_pct_observed": 100.0,
  "high_severity_counterexample_count": 0,
  "constants_enforced": ["CERTIFICATION_MIN_VERIFICATION_PCT","CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT","CERTIFICATION_MAX_HIGH_SEVERITY_COUNTEREXAMPLES","CERTIFICATION_MAX_EVIDENCE_AGE_HOURS"]
}
```

### 2. Verification contract JSON — `bundle/verification_contract.json`
Per-Feature × per-ProofObligation status with artifact references. From MINING-3 §13:
```
pass                      → allowed
fail-missing-evidence     → blocked-by-contract
fail-invalid-references   → blocked-by-contract
fail-mixed                → blocked-by-both
```
Every Feature gets a row; every ProofObligation under each gets a status. The bundle holds only `pass` rows for a strict release.

### 3. Release certificate JSON — `bundle/release_certificate.json`
The signed cap on the bundle:
```jsonc
{
  "schema_version": "strict-conformant-release.v1",
  "project": "frankensqlite",
  "version": "0.42.0",
  "reference": { "name": "csqlite", "version": "3.52.0", "contract_sha256": "..." },
  "parity_score": 0.847291,             // truncate_score'd conformal LOWER bound
  "ratchet_state_sha256": "...",
  "feature_universe_sha256": "...",
  "invariant_catalog_sha256": "...",
  "issued_at": "2026-05-22T14:23:11Z",
  "evidence_bundle_sha256": "...",      // Merkle root over (1)..(8)
  "signers": ["release-architect@example.com","perf-lead@example.com","safety-lead@example.com"],
  "signature": "..."                     // detached PGP signature over the bundle hash
}
```

### 4. CI artifact manifest — `bundle/ci_manifest.json`
Lists every artifact in the bundle with its SHA-256, schema version, and source CI run id. Lets a downstream consumer cross-check the bundle's provenance against the CI logs.

### 5. Benchmark summary — `bundle/benchmark_summary.json`
`fsqlite-e2e.comprehensive-bench-report.v3` (or class-equivalent) for the certifying run, plus the diff against `.bench-history/<bench>.latest.json` showing the gate-by-gate pass:
- `primary_score_regression_pct ≥ −3.0`
- `geomean_regression_pct ≥ −5.0`
- `category_geomean_regression_pct ≥ −10.0` per category
- `p90_regression_pct ≥ −15.0`
- `pass_over_pass_throughput_drop_pct ≥ −5.0`

### 6. `scorecards.json` — `bundle/scorecards.json`
Per-category Beta posterior + conformal band + lower bound (the unit of analysis for the ratchet). See [CONFORMAL-RATCHET.md](CONFORMAL-RATCHET.md) for the schema.

### 7. Critical-path report — `bundle/critical_path.md`
Narrative + tabular summary of every Critical / High severity finding from the gauntlet round-history, with resolution status. Format: open / resolved / waived (with waiver id). Strict release: open == 0, waived == 0.

### 8. Ratchet state — `bundle/ratchet_state.json`
The persisted ratchet at certification time (per [CONFORMAL-RATCHET.md § (e)](CONFORMAL-RATCHET.md)):
```jsonc
{
  "schema_version": "ratchet_state.v1",
  "current_lower_bound": 0.847291,
  "per_category_bounds": { "ReadSingle": 0.892341, ... },
  "commit_sha": "1a2b3c4d5e6f...",
  "timestamp": "2026-05-22T14:22:00Z",
  "previous_bound": 0.842172,
  "advance_reason": "..."
}
```

---

## (c) Gate/ratchet spec per evidence class

Each evidence class has a gate or ratchet that must hold:

| Class | Gate / Ratchet | What must hold |
|---|---|---|
| (1) Confidence gate | `release_decision == "Allow"` | All four constants pass (per (a)). |
| (2) Verification contract | Every row `status == "pass"` AND `gate == "allowed"` | No fail-* status; no contract-blocked rows. |
| (3) Release certificate | Signed by ≥3 distinct signers; `evidence_bundle_sha256` validates | Multi-party signing closes the unilateral-release loophole. |
| (4) CI manifest | Every artifact hash matches the file on disk AND is reachable from a CI run id | Bundle is reconstructable from CI; no off-CI artifacts smuggled in. |
| (5) Benchmark summary | All 5 pass-over-pass thresholds met (primary −3, geomean −5, category −10, p90 −15, throughput −5) | Perf gate of [KEEP-GATE-RULES.md](KEEP-GATE-RULES.md) applied at release scope. |
| (6) `scorecards.json` | `truncate_score(conformal_lower_bound) ≥ ratchet.current_lower_bound` | Ratchet monotonicity respected. |
| (7) Critical-path report | `open == 0` AND `waived == 0` for High/Critical severity | No deferred showstoppers. |
| (8) `ratchet_state.json` | All invariants of [CONFORMAL-RATCHET.md § (e)](CONFORMAL-RATCHET.md) | Persisted high-water mark is internally consistent. |

A failure of any single gate **blocks** the certification. There is no partial-strict-release variant; a release either passes the strict bar or it does not.

---

## (d) Persisted baseline — `ratchet_state.json` discipline

The persisted ratchet is the project's permanent high-water mark. It is treated as source-of-truth for release decisions; it is committed to git; it survives across releases.

### Rules for `ratchet_state.json`
1. **Committed to git.** Lives at `reports/ratchet_state.json` (or project-determined path). Never `.gitignored`.
2. **One source of truth.** Any read of the ratchet uses this file; any write goes through `scripts/apply-ratchet.sh`. No ad-hoc edits.
3. **Monotone non-decreasing.** `current_lower_bound` and `per_category_bounds[c]` increase or stay the same on every `Allow`; decrease only under explicit `Waiver`.
4. **Self-validating on read.** `apply-ratchet.sh` reads and re-validates internal invariants before any decision; corrupted state exits non-zero.
5. **History-aware.** Every advance records `previous_bound`, `commit_sha`, `timestamp`, `advance_reason`. A reviewer can `git log -p reports/ratchet_state.json` and read the project's parity history.
6. **Cross-platform reproducible.** All numeric fields are `truncate_score`'d per [KERNEL.md § K-5](KERNEL.md). Two architectures reading the same `ratchet_state.json` decide identically.

### Initial calibration
Day-14 of the bootstrap order (per MINING-3 §15) initializes `ratchet_state.json` from the first full baseline run. The initial bounds are *low* on purpose — every subsequent run gets the chance to raise them, but no run is blocked by an unrealistic floor. As the project matures, the ratchet ratchets up; the floor reflects the project's actual demonstrated parity.

---

## (e) Certification bundler script flow

`scripts/final-report-builder.sh` does:

```
1) Verify Phase 16 prerequisites:
   - convergence-tracker.sh exit 0
   - bead-graph-validator.sh exit 0
   - oracle-preflight-doctor.sh exit 0
   - check-certification-constants.sh exit 0

2) Collate per-phase artifacts into bundle/:
   - bundle/confidence_gate.json          ← from confidence_gate emitter
   - bundle/verification_contract.json    ← from parity_invariant_catalog.validate()
   - bundle/benchmark_summary.json        ← from comprehensive_bench.rs + .bench-history diff
   - bundle/scorecards.json               ← from score_engine.rs
   - bundle/critical_path.md              ← from synthesizer + ledger sweep
   - bundle/ratchet_state.json            ← copy of reports/ratchet_state.json (current)
   - bundle/ci_manifest.json              ← from CI run id + per-artifact SHA-256
   - FINAL_GAUNTLET_REPORT.md             ← composed by final-report-author subagent
   - PARITY_RUNBOOK.md                    ← composed by runbook-author subagent
   - RELEASE_CERTIFICATION_TEMPLATE.md    ← this template with values substituted

3) Compute Merkle root over bundle/:
   evidence_bundle_sha256 = merkle_sha256(bundle/**/*)

4) Compose bundle/release_certificate.json with all hashes filled in.

5) Solicit signatures (≥3 from distinct signers via the project's signing flow).

6) Validate the full bundle one last time:
   - All 4 constants from (a) hold.
   - All 8 evidence classes from (b) present with valid SHA-256.
   - All 8 gates from (c) pass.
   - ratchet_state.json valid per (d).

7) Emit:
   bundle/SUMMARY.txt           ← human-readable one-page
   bundle/release_certificate.json (signed)
   FINAL_GAUNTLET_REPORT.md     ← top-level (also lives in bundle/)

   And tags the source commit:
   git tag -s strict-conformant-release/v0.42.0
```

If any step fails, the script exits non-zero with the specific failure cited (constant violated / evidence class missing / gate failed / ratchet invariant broken / signature count insufficient).

---

## (f) What to do when certification fails

A failed certification is a structured signal, not an emergency. The failure class determines the response:

| Failure | Class | Response |
|---|---|---|
| `CERTIFICATION_MIN_VERIFICATION_PCT < 100.0` | Coverage gap | Identify the unsatisfied ProofObligation(s); either close the gap (preferred) or ship as non-strict variant (clearly labeled). |
| `CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT < 100.0` | Suite instability | Investigate the failing test(s); flake → file as `bd-flake.<seq>` blocker; real failure → loop back to Phase 12. |
| `CERTIFICATION_MAX_HIGH_SEVERITY_COUNTEREXAMPLES > 0` | Open critical | The counterexamples are showstoppers; address each per [SOAK-PROTOCOL.md § (d) loop-back](SOAK-PROTOCOL.md). |
| `CERTIFICATION_MAX_EVIDENCE_AGE_HOURS > 24` | Stale evidence | Re-run the certifying suite + benches + soak (or partial-soak if low-risk) to refresh evidence; rebundle. |
| Benchmark summary gate failed | Perf regression | Apply [OPERATORS.md § 🔁 Pass-Over-Pass-Gate](OPERATORS.md); if structural, [OPERATORS.md § ⊕ Isomorphic-Rewrite](OPERATORS.md); if irreducible, structured waiver per [CONFORMAL-RATCHET.md § (f)](CONFORMAL-RATCHET.md). |
| `scorecards.json` ratchet failed | Conformance regression | Apply [OPERATORS.md § ⚖ Ratchet-Lower-Bound](OPERATORS.md); investigate the per-category bound that dropped; fix or waive. |
| Critical-path open/waived > 0 | Deferred showstoppers | These cannot ship in a strict release. Either resolve them now or downgrade the release tier. |
| `ratchet_state.json` self-validation failed | Tooling/state corruption | Halt; reproduce the failure under [OPERATORS.md § ⚠ Escalate-To-Fresh-Repro](OPERATORS.md); the bundle is not shippable until the ratchet is consistent. |
| Insufficient signatures | Governance | Acquire the missing signatures; do not back-fill or self-sign. |
| Convergence-tracker exit > 0 | Loop incomplete | Phase 16 cannot run while convergence is unmet; loop back to Phase 11. |

**Downgrade option:** If a strict-conformant release is genuinely not achievable in the available time and the project policy admits a tier below strict (e.g., `provisional-release.v1`), it is shipped *clearly labeled* with the constants relaxed and the specific deviations enumerated. The strict template is reserved for releases that meet all four constants and all eight gates exactly.

---

## Cross-links

- This file is referenced by [../../SKILL.md § Up-Front Confirmations § Final-artifact tier](../../SKILL.md) (where the user picks Internal-only / public-release / certification-bundle).
- The four required-pass constants are also enforced by `scripts/check-certification-constants.sh`.
- The ratchet machinery this template depends on is in [CONFORMAL-RATCHET.md](CONFORMAL-RATCHET.md).
- The verification contract status classes (`pass | fail-missing-evidence | fail-invalid-references | fail-mixed`) are detailed in [../taxonomy/INVARIANT-CATALOG.md](../taxonomy/INVARIANT-CATALOG.md) (and MINING-3 §13).
- The signing flow and signer roles are project-specific; the gauntlet only specifies "≥3 distinct signers from distinct roles" and that the certificate is detached-PGP-signed.
- Failure handling per (f) routes through the same operator library used across the rest of the gauntlet: [OPERATORS.md](OPERATORS.md).
- Bundle hash discipline aligns with [IDENTITY-AND-REPRODUCIBILITY.md § content-addressed artifact ID](IDENTITY-AND-REPRODUCIBILITY.md).
