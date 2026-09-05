<!-- final-gauntlet-report-template.md — skeleton for FINAL_GAUNTLET_REPORT.md
     Copied by final-report-author at Phase 16 into <workspace>/.
     All <TOKEN> values are substituted at render time. -->

---
name: FINAL_GAUNTLET_REPORT
schema_version: gauntlet.final-report.v1
generated_at_utc: "<ISO_8601>"
run_id: "<run_id>"
port_name: "<port>"
reference_name: "<reference>"
reference_version: "<X.Y.Z>"
project_class: "<sql|resp|numerical-python|ml-system|http-protocol>"
source_file_hashes:
  - path: "convergence_tracker.json"
    sha256: "<...>"
  - path: "reports/ratchet_state.json"
    sha256: "<...>"
  - path: "scorecards.json"
    sha256: "<...>"
---

# FINAL_GAUNTLET_REPORT — `<port>` vs `<reference>` `<X.Y.Z>`

## 1. Executive Summary

On **perf** the port stands at category-weighted score `<truncate_score>` with conformal lower bound `<truncate_score>`. On **conformance** the parity score is `<X>` with conformal lower bound `<Y>`. On **surface**, `<P>` features Passing, `<Q>` Partial, `<M>` Missing, `<E>` Excluded (coverage debt `<D>`%).

Convergence reached after `<N>` rounds; the last 2 rounds produced `<a>` and `<b>` new genuine findings respectively (both below the 3-finding clean-round threshold). Every open hypothesis closed.

Recommendation: **`<SHIP | HOLD | BLOCK>`**.

## 2. Per-Pillar Status

### 2a. Performance

| Category | Score | cv_pct | Ratio vs reference | Primary MT8 frame attribution |
|---|---|---|---|---|
| `ReadSingle` | `<X>` | `<%>` | `<X.YYY>×` | `<top frame ≥0.1% self-time>` |
| `ReadAggregate` | … | … | … | … |
| `WriteSingle` | … | … | … | … |
| `WriteBulk` | … | … | … | … |
| `ConcurrentWriters` | … | … | … | … |
| `MixedOltp` | … | … | … | … |

Pass-over-pass deltas (vs `.bench-history/<bench>.latest.json`):
- primary score: `<+X%>`
- geomean: `<+X%>`
- p90: `<+X%>`
- throughput: `<+X%>`

All within gate thresholds (primary −3%, geomean −5%, per-category −10%, p90 −15%, throughput −5%).

### 2b. Conformance

| Behavior class | Oracle pass | FailureBundle count | Distinct MismatchSignatures | E-process e-value |
|---|---|---|---|---|
| `NULL semantics` | `<N>/<T>` | `<n>` | `<sig>` | `<e>` (below 1/α) |
| `GROUP BY edges` | … | … | … | … |
| … | … | … | … | … |

Conformal lower bound on parity score: `<truncate_score>` (above ratchet floor `<truncate_score>`).

### 2c. Surface Parity

| FeatureUniverse category | Passing | Partial | Missing | Excluded | Weighted contribution |
|---|---|---|---|---|---|
| `<CAT-A>` | `<n>` | `<n>` | `<n>` | `<n>` | `<X.XX>` |
| `<CAT-B>` | … | … | … | … | … |
| … | … | … | … | … | … |

Coverage debt: `<D>` % (= weighted sum of Missing + Excluded over not-N/A features).

## 3. Findings Table (severity-ranked)

| Severity | Pillar | Finding ID | Description | Evidence path | Remediation bead |
|---|---|---|---|---|---|
| CRITICAL | conformance | F-2025-001 | … | `tests/artifacts/…` | `bd-…` |
| HIGH | perf | F-2025-002 | … | `tests/artifacts/…` | `bd-…` |
| MEDIUM | surface | F-2025-003 | … | `…` | `bd-…` |
| LOW | … | … | … | … | … |

## 4. Per-Pillar Remediation Plan

### 4a. Performance

For each confirmed gap (mined from `phase12_remediation_*.md`):

- **`<gap_id>`** — chosen rewrite `<name>` (rubric score `<X.X>`; gates `Impact × Confidence / Effort ≥ 2.0`).
  - Runners-up: `<name>` (`<X.X>`, blocked by `<reason>`); `<name>` (`<X.X>`, blocked by `<reason>`).
  - Proof pack: `artifacts/<bead_id>/proof_pack/`.
  - Bead: `<bd-…>`.

### 4b. Conformance

(Same format; perf rubric replaced by conformal-lower-bound monotonicity check.)

### 4c. Surface

(Same format; gate is `partial → full` feature-coverage check.)

## 5. Unresolved-But-Explicitly-Deferred List

Every entry below carries its load-bearing **retry-condition predicate** verbatim from the ledger. The forbidden-phrase check (no "later", "if it seems important", "we should revisit", "tracked elsewhere") was applied; rejections are flagged at the top of this report — there should be ZERO violations.

| Pillar | Item | Retry-Condition Predicate |
|---|---|---|
| surface | `F-SQL-099 JSON1 functions` | "Reconsider only inside the broader v2.0 release planning (track as bd-future-jsonl)." |
| perf | `prepared-statement parse cache` | "Retry only if a profiler attributes a clearly-above-noise share to `prepared_lookup_time_ns` on a wider workload shape than the current MT8 set." |
| … | … | … |

## 6. Convergence Evidence Appendix

Round-by-round new-findings counts (from `convergence_tracker.json`):

| Round | Perf | Conformance | Surface | Open hypotheses (after) |
|---|---|---|---|---|
| 1  | … | … | … | … |
| 2  | … | … | … | … |
| … | … | … | … | … |
| N-1 | `<a>` | `<a>` | `<a>` | 0 |
| N   | `<b>` | `<b>` | `<b>` | 0 |

Exit conditions:
- ✅ ≥10 rounds (`<N>`)
- ✅ Last 2 rounds <3 new genuine findings each (`<a>`, `<b>`)
- ✅ Every open hypothesis resolved

## 7. Certification Bundle Manifest

Every file in `<workspace>/certification_bundle/`:

| Path | SHA-256 | Schema version | Source phase |
|---|---|---|---|
| `confidence_gate.json` | `<sha>` | `gauntlet.confidence_gate.v1` | Phase 16 |
| `verification_contract.json` | `<sha>` | `gauntlet.verification_contract.v1` | Phase 16 |
| `release_certificate.json` | `<sha>` | `strict-conformant-release.v1` | Phase 16 |
| `ci_artifact_manifest.json` | `<sha>` | `gauntlet.ci_artifact_manifest.v1` | Phase 16 |
| `benchmark_summary.json` | `<sha>` | `gauntlet.benchmark_summary.v1` | Phase 16 |
| `scorecards.json` | `<sha>` | `gauntlet.scorecards.v1` | Phase 9–11 (copied) |
| `critical_path_report.json` | `<sha>` | `bv.robot-insights.v1` | Phase 13 |
| `ratchet_state.json` | `<sha>` | `gauntlet.ratchet_state.v1` | rolling |
| `BUNDLE_MANIFEST.json` | `<sha>` | `gauntlet.certification_bundle_manifest.v1` | Phase 16 |

`bundle_root_sha256: <sha>` — sorted-concatenation hash; reproducible across machines.

## 8. Negative-Ledger Summary

- Perf ledger entries: `<n>`; top-5 most-frequently-cited retry-condition predicates:
  1. "Reconsider only inside the broader DML mutation operator redesign" — `<count>`
  2. "Retry only if a profiler attributes ≥0.5% to `<counter>` on `<wider workload>`" — `<count>`
  3. …
- Conformance ledger entries: `<n>`.
- Surface deferrals: `<n>`.
- Patterns we've definitively retired:
  - `<pattern>` — retried `<k>` times across `<m>` rounds, refuted by `<evidence>`.
  - …

## 9. Open Questions for the Maintainer

(Non-blocking observations the maintainer should know.)

- `<observation 1 — why it matters — what evidence would change the decision>`
- …

---

*Generated by the running-the-gauntlet-on-your-rust-port skill at Phase 16. To reproduce: `scripts/final-report-builder.sh <workspace>`.*
