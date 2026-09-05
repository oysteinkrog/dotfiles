<!-- release-certification-template.md — skeleton for RELEASE_CERTIFICATION_TEMPLATE.md
     Copied by certification-bundler at Phase 16 into <workspace>/.
     Strict-conformant-release.v1 template. -->

---
name: RELEASE_CERTIFICATION
schema_version: strict-conformant-release.v1
generated_at_utc: "<ISO_8601>"
run_id: "<run_id>"
port_name: "<port>"
reference_name: "<reference>"
reference_version: "<X.Y.Z>"
bundle_manifest_sha256: "<sha>"
certifying: "<true|false>"
---

# RELEASE CERTIFICATION — `<port>` `<port_version>` against `<reference>` `<reference_version>`

This document is the certification claim. It asserts — under the four required-pass constants of `strict-conformant-release.v1` — that the port is **release-ready**, OR explains precisely which constant failed and what evidence is missing.

The actual evidence lives in `<workspace>/certification_bundle/`. This document is the human-readable index.

## 1. Required-Pass Constants

| Constant | Required | Actual | Pass |
|---|---|---|---|
| `CERTIFICATION_MIN_VERIFICATION_PCT` | `100.0` | `<X>` | `<✅\|❌>` |
| `CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT` | `100.0` | `<X>` | `<✅\|❌>` |
| `CERTIFICATION_MAX_HIGH_SEVERITY_COUNTEREXAMPLES` | `0` | `<N>` | `<✅\|❌>` |
| `CERTIFICATION_MAX_EVIDENCE_AGE_HOURS` | `24` | `<H>` | `<✅\|❌>` |

**Certifying:** `<true | false>`

A `false` here means at least one constant failed; see `<workspace>/certification_bundle/RELEASE_BLOCKED.md` for details. Do NOT ship.

## 2. Convergence Evidence

| Condition | Required | Actual | Pass |
|---|---|---|---|
| Rounds completed | `≥ 10` | `<N>` | `<✅\|❌>` |
| Consecutive clean rounds | `≥ 2` | `<n>` | `<✅\|❌>` |
| Open hypotheses | `0` | `<n>` | `<✅\|❌>` |
| BOCPD terminal regime | `Stable` | `<X>` | `<✅\|❌>` |

## 3. Evidence Bundle Manifest

Every file in `<workspace>/certification_bundle/`:

| File | SHA-256 | Schema version | Source phase |
|---|---|---|---|
| `confidence_gate.json` | `<sha>` | `gauntlet.confidence_gate.v1` | Phase 16 |
| `verification_contract.json` | `<sha>` | `gauntlet.verification_contract.v1` | Phase 16 |
| `release_certificate.json` | `<sha>` | `strict-conformant-release.v1` | Phase 16 |
| `ci_artifact_manifest.json` | `<sha>` | `gauntlet.ci_artifact_manifest.v1` | Phase 16 |
| `benchmark_summary.json` | `<sha>` | `gauntlet.benchmark_summary.v1` | Phase 16 |
| `scorecards.json` | `<sha>` | `gauntlet.scorecards.v1` | Phase 9-11 |
| `critical_path_report.json` | `<sha>` | `bv.robot-insights.v1` | Phase 13 |
| `ratchet_state.json` | `<sha>` | `gauntlet.ratchet_state.v1` | rolling |
| `BUNDLE_MANIFEST.json` | `<sha>` | `gauntlet.certification_bundle_manifest.v1` | Phase 16 |

**`bundle_root_sha256: <sha>`** — sorted-concatenation hash of every file SHA-256.

## 4. Gate / Ratchet Spec

For each gate, the spec the release-certificate validates against:

- **Perf primary score:** `<truncate_score>` must be `≥ ratchet_state.json#/perf/lower_bound − 0` (monotonic; never regresses).
- **Conformance lower bound:** `<truncate_score>` must be `≥ ratchet_state.json#/conformance/lower_bound`.
- **Per-category bounds:** for every category, the conformal lower bound must not regress.
- **Surface coverage:** weighted `Passing + 0.5 × Partial / not-N/A` must be `≥ ratchet_state.json#/surface/lower_bound`.
- **Coverage debt:** `Excluded + Missing` weighted contribution must be `≤ ratchet_state.json#/surface/coverage_debt_ceiling`.
- **E-process Ville:** every monitored invariant's e-value must be `< 1/α` (per `parity_score_contract.toml#/eprocess`).
- **BOCPD:** terminal regime over trailing window must be `Stable`.

## 5. Persisted Baseline (ratchet_state.json)

The current high-water-mark ratchet state. Embedded here for audit; the canonical file lives in `<workspace>/certification_bundle/ratchet_state.json`.

```jsonc
{
  "schema_version": "gauntlet.ratchet_state.v1",
  "perf": {
    "lower_bound": "<truncate_score>",
    "per_category": {
      "ReadSingle":        "<truncate_score>",
      "ReadAggregate":     "<truncate_score>",
      "WriteSingle":       "<truncate_score>",
      "WriteBulk":         "<truncate_score>",
      "ConcurrentWriters": "<truncate_score>",
      "MixedOltp":         "<truncate_score>"
    },
    "last_updated_run_id": "<run_id>",
    "last_updated_at_utc": "<ISO>"
  },
  "conformance": {
    "lower_bound": "<truncate_score>",
    "per_behavior_class": { /* ... */ },
    "last_updated_run_id": "<run_id>",
    "last_updated_at_utc": "<ISO>"
  },
  "surface": {
    "lower_bound": "<truncate_score>",
    "coverage_debt_ceiling": "<X.YY>",
    "last_updated_run_id": "<run_id>",
    "last_updated_at_utc": "<ISO>"
  }
}
```

## 6. Decision

- ✅ `certifying = true` — **SHIP**. All required-pass constants hold; convergence evidence complete; bundle reproducible. The release is certified against `<reference>` `<X.Y.Z>` under `strict-conformant-release.v1`.
- ❌ `certifying = false` — **DO NOT SHIP**. See `<workspace>/certification_bundle/RELEASE_BLOCKED.md` for the failed constant + the missing evidence. Loop back to the appropriate phase (12 for remediation, 15 for soak deepening) until all constants pass.

## 7. Auditor Reproduction

To reproduce this certification independently:

```bash
cd <port>
git checkout <git_sha>
~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/oracle-preflight-doctor.sh . --workspace <workspace>
~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/run-bench-matrix.sh . <workspace>
~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/run-conformance-suite.sh . <workspace>
~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/compute-parity-score.sh <workspace>
diff -r certification_bundle/ <workspace>/certification_bundle/  # MUST be empty
```

Bytewise identity of the bundle confirms the certification was reproducible (per `truncate_score` + content-addressed artifact IDs, K-5 + K-11 in `references/methodology/KERNEL.md`).

---

*Generated by the running-the-gauntlet-on-your-rust-port skill at Phase 16. Schema: `strict-conformant-release.v1`.*
