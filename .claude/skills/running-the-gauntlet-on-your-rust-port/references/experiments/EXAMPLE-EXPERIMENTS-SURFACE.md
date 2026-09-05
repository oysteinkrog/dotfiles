# Worked Surface Experiments

Six worked surface-parity experiments using the template from [EXPERIMENT-DESIGNS-TEMPLATE.md](EXPERIMENT-DESIGNS-TEMPLATE.md). Surface experiments verify coverage claims at the symbol / opcode / command / PRAGMA / IO-format level against the reference project's enumeration source-of-truth.

The discipline: **the surface contract is a file, not a feeling**. Every claim of "we support X" is backed by a `FeatureUniverse` entry with `status ∈ {Passing, Partial, Missing, Excluded}`, and Excluded items carry both an `exclusion_rationale` and a retry-condition predicate. Excluded never silently rounds up to success; per [methodology/KERNEL.md], "Excluded items still count as coverage debt for a strict-100% claim."

Use as models for your project's `SURFACE_PARITY_HYPOTHESIS_LEDGER.md`.

---

## SURF-0001: Every entry in `numpy.__all__` is covered by a FeatureUniverse entry

- **pillar:** surface
- **hypothesis:** For the pinned NumPy reference version (e.g., 1.26.0), every name in `numpy.__all__` resolves to exactly one FeatureUniverse entry with a non-Missing-without-Excluded status. The FrankenNumPy `fnp_python_covers_full_numpy_all` test should report 499/499.
- **motivation:** `numpy.__all__` is the canonical enumeration source-of-truth. If our FeatureUniverse misses a name, our coverage claim is overstated. If we list a name that doesn't appear in `__all__`, our weight normalization is wrong. The `numpy.__all__` test is the surface-parity bootstrapping gate.
- **minimal_reproducer:**
  ```bash
  python -c "import numpy; print('\n'.join(sorted(numpy.__all__)))" > /tmp/numpy_all.txt
  cargo run --bin feature-universe-dump -- --category numpy > /tmp/fu_numpy.txt
  diff /tmp/numpy_all.txt /tmp/fu_numpy.txt
  ```
- **expected_signal:** Zero-diff output. Cardinality matches `len(numpy.__all__)` (499 for NumPy 1.26.0). Every entry has `status ∈ {Passing, Partial, Excluded}`. Missing-without-exclusion = invalid state caught by `parity_taxonomy.rs::validate()`.
- **falsifiability_criteria:** Any name in `__all__` absent from FeatureUniverse, OR any FeatureUniverse entry without a corresponding `__all__` name, OR any `ParityStatus::Missing` entry that lacks an explicit `Excluded` counterpart.
- **one_line_invocation:**
  ```bash
  cargo test -p fnp-harness --test feature_universe_covers_numpy_all -- --nocapture
  ```
- **results_inline:** `CONFIRMED_GAP` (initial) → `NO_EVIDENCE` (after backfill) — Initial run reported 487/499 (12 missing entries: `numpy.recarray`, `numpy.chararray`, etc.). Each backfilled with explicit Excluded status + `exclusion_rationale: "Legacy NumPy 1.x recarray API; subject implements ndarray-record alternative"` + closure predicate `"Retry only if upstream NumPy 2.x retains recarray"`. Final 499/499 pass; sum of category weights normalized to 1.0.
- **evidence_artifact_paths:**
  - `tests/artifacts/surface/SURF-0001/numpy_all_499.txt`
  - `tests/artifacts/surface/SURF-0001/feature_universe_dump.txt`
  - `tests/artifacts/surface/SURF-0001/missing_before_fix.json`
  - `tests/artifacts/surface/SURF-0001/exclusion_rationales.toml`
- **closure_predicate:** "Retry only if NumPy reference version bumps; surface coverage gate is permanent."

---

## SURF-0002: Every PRAGMA in `sqlite3 .pragma list` is Passing FeatureUniverse or Excluded with rationale

- **pillar:** surface
- **hypothesis:** Every PRAGMA name printed by the reference `sqlite3 .pragma list` command exists in the FrankenSQLite FeatureUniverse with `status ∈ {Passing, Partial, Excluded}`. Missing-without-Excluded is an invalid state.
- **motivation:** PRAGMAs are the canonical SQL-class extension surface. SQLite has ~70 PRAGMAs; FrankenSQLite implements a subset. The gap (= Missing without Excluded) is where users will discover an undocumented hole. The contract: every PRAGMA either works (Passing/Partial) or is consciously excluded.
- **minimal_reproducer:**
  ```bash
  echo ".pragma list" | sqlite3 :memory: | sort > /tmp/sqlite_pragmas.txt
  cargo run --bin feature-universe-dump -- --category pragma | sort > /tmp/fu_pragmas.txt
  diff /tmp/sqlite_pragmas.txt /tmp/fu_pragmas.txt
  ```
- **expected_signal:** Zero diff. Every PRAGMA accounted for. `parity_taxonomy.rs::validate()` returns empty `Vec<Violation>`.
- **falsifiability_criteria:** Any PRAGMA in reference list absent from FeatureUniverse (= Missing without Excluded = invalid state). Or any FeatureUniverse PRAGMA entry not in reference list (typo / stale).
- **one_line_invocation:**
  ```bash
  cargo test -p fsqlite-harness --test pragma_universe_matches_sqlite3
  ```
- **results_inline:** `CONFIRMED_GAP` — Reference SQLite 3.52.0 lists 71 PRAGMAs; FeatureUniverse covered 64 Passing + 5 Partial. The 2 missing were `module_list` and `pragma_list` themselves (introspection PRAGMAs). Backfilled with `status: Excluded`, `exclusion_rationale: "Self-referential introspection PRAGMAs; subject implements via SQL functions instead per CONTRACT.md §4.3"`, closure predicate `"Retry only if introspection PRAGMA usage exceeds 1% of corpus queries"`.
- **evidence_artifact_paths:**
  - `tests/artifacts/surface/SURF-0002/sqlite_pragmas_71.txt`
  - `tests/artifacts/surface/SURF-0002/fu_pragmas_before.txt`
  - `tests/artifacts/surface/SURF-0002/fu_pragmas_after.txt`
- **closure_predicate:** "Retry only if reference SQLite adds new PRAGMA or our PRAGMA support expands; gate is permanent."

---

## SURF-0003: Category weights sum to 1.0 across every category in `parity_score_contract.toml`

- **pillar:** surface
- **hypothesis:** For every category in `parity_score_contract.toml`, the sum of `weight` fields equals 1.0 (modulo `truncate_score` 6-decimal precision). The loader's invariant must catch any drift.
- **motivation:** Weight normalization is one of the three load-bearing invariants of `parity_taxonomy.rs` (per MINING-3 §11). If category weights sum to 0.97 or 1.03, the global score becomes meaningless: a Passing category contributes more or less than intended. This experiment is a regression test for the loader itself.
- **minimal_reproducer:**
  ```rust
  use fsqlite_harness::parity_taxonomy::FeatureUniverse;
  let fu = FeatureUniverse::load_from_contract("docs/contracts/parity_score_contract.toml")?;
  for (category, features) in fu.by_category() {
      let sum: f64 = features.iter().map(|f| f.weight).sum();
      let truncated = (sum * 1e6).round() / 1e6;
      assert_eq!(truncated, 1.0, "category {category} weights sum to {truncated}, not 1.0");
  }
  ```
- **expected_signal:** All categories sum to 1.0 (within `truncate_score`'s 6-decimal precision). Loader rejects any contract that violates this with `LoaderError::WeightSumViolation`.
- **falsifiability_criteria:** Any category sums to ≠1.0 (loader silently accepts), OR loader rejects with wrong error class.
- **one_line_invocation:**
  ```bash
  cargo test -p fsqlite-harness --test parity_score_contract_weight_invariant
  ```
- **results_inline:** `NO_EVIDENCE` — All 6 categories (Parser, Resolver, Planner, Vdbe, Storage, Wal) sum to 1.000000 exactly. The loader rejects a deliberately-broken contract fixture (`tests/fixtures/contracts/broken_weights.toml`) with the correct error class. Wired as permanent regression test against contract drift.
- **evidence_artifact_paths:**
  - `tests/artifacts/surface/SURF-0003/category_weight_sums.json`
  - `tests/artifacts/surface/SURF-0003/loader_negative_test.txt`
- **closure_predicate:** "Retry only if `parity_score_contract.toml` schema changes OR if a new category is added; the invariant is permanent."

---

## SURF-0004: Every Excluded entry has both `exclusion_rationale` AND a retry-condition predicate

- **pillar:** surface
- **hypothesis:** No FeatureUniverse entry has `status: Excluded` without (a) a non-empty `exclusion_rationale` and (b) a closure predicate from the 8-form retry vocabulary. Forbidden predicates: "later", "TBD", "if it seems important", "tracked elsewhere" without a beads ID.
- **motivation:** The negative-ledger discipline applies to surface exclusions too. Excluded without rationale = silent coverage debt that disappears from view. Excluded with "later" / "tracked elsewhere" without ID = same problem, lipstick on. The contract must name what would change the exclusion.
- **minimal_reproducer:**
  ```rust
  let fu = FeatureUniverse::load_from_contract(...)?;
  for f in fu.features() {
      if matches!(f.status, ParityStatus::Excluded) {
          assert!(f.exclusion_rationale.is_some(), "Excluded entry {} missing rationale", f.id);
          assert!(f.closure_predicate.is_some(), "Excluded entry {} missing closure predicate", f.id);
          let pred = f.closure_predicate.as_ref().unwrap();
          for forbidden in &["later", "TBD", "if it seems important", "TODO"] {
              assert!(!pred.to_lowercase().contains(forbidden),
                      "Excluded entry {} closure predicate uses forbidden word: {pred}", f.id);
          }
      }
  }
  ```
- **expected_signal:** Test passes. All Excluded entries carry both fields; closure predicate uses one of the 8 retry-vocabulary forms (see [../methodology/RETRY-CONDITION-VOCABULARY.md](../methodology/RETRY-CONDITION-VOCABULARY.md)).
- **falsifiability_criteria:** Any Excluded entry without rationale; any closure predicate containing forbidden lazy words.
- **one_line_invocation:**
  ```bash
  cargo test -p fsqlite-harness --test excluded_entries_have_rationale_and_predicate
  ```
- **results_inline:** `CONFIRMED_GAP` (initial) → `NO_EVIDENCE` (after rewrite) — 4 entries had `closure_predicate: "later"` and 1 had `"tracked elsewhere"`. Each rewritten with concrete predicate: e.g., "Retry only if `module_list` introspection PRAGMA appears in user corpus" (vs former "later"). Permanent regression test against lazy-exclusion drift.
- **evidence_artifact_paths:**
  - `tests/artifacts/surface/SURF-0004/exclusion_audit_before.json`
  - `tests/artifacts/surface/SURF-0004/exclusion_audit_after.json`
- **closure_predicate:** "Retry only if Excluded entry count grows above threshold OR a new exclusion vocabulary form is sanctioned."

---

## SURF-0005: FrankenJAX primitive catalog covers all 113/113 VJP+JVP primitives

- **pillar:** surface
- **hypothesis:** For the pinned JAX reference version, the FrankenJAX primitive catalog covers 100% of primitives that have both a forward-mode JVP rule and a reverse-mode VJP rule (per the JAX-source enumeration). Currently 113 such primitives (per MINING-1 §8 sibling status).
- **motivation:** ML-class projects (FrankenTorch, FrankenJAX) treat the primitive catalog as the surface contract. A missing primitive = silent coverage hole = potential numerical correctness failure under `grad` / `vmap` composition. The cardinality count (113) is JAX-version-specific; pinned in `docs/contracts/jax_version_contract.toml`.
- **minimal_reproducer:**
  ```bash
  python -c "
  import jax
  import inspect
  primitives = set()
  for name in dir(jax.lax):
      obj = getattr(jax.lax, name)
      if hasattr(obj, 'def_impl') and obj in jax._src.ad.primitive_jvps and obj in jax._src.ad.primitive_transposes:
          primitives.add(name)
  print(len(primitives))
  print('\n'.join(sorted(primitives)))
  " > /tmp/jax_vjp_jvp.txt

  cargo run --bin feature-universe-dump -- --category primitive --requires vjp,jvp > /tmp/fj_primitives.txt
  diff /tmp/jax_vjp_jvp.txt /tmp/fj_primitives.txt
  ```
- **expected_signal:** Zero diff. Count matches 113.
- **falsifiability_criteria:** Any VJP+JVP primitive in reference enumeration absent from FrankenJAX catalog. Or any catalog entry not in JAX source.
- **one_line_invocation:**
  ```bash
  cargo test -p fjax-harness --test primitive_catalog_covers_jax_vjp_jvp
  ```
- **results_inline:** `CONFIRMED_GAP` — 113/113 expected; 87/113 observed in initial round. 26 primitives missing (notably `lax.scan`, `lax.while_loop`, `lax.cond` — control-flow primitives). Each backfilled either as `Passing`, `Partial` (with TransformFamily limit), or `Excluded` with rationale. Surface-parity score for JAX category jumped 87→113/113 over Phase-11 rounds 4-7.
- **evidence_artifact_paths:**
  - `tests/artifacts/surface/SURF-0005/jax_vjp_jvp_113.txt`
  - `tests/artifacts/surface/SURF-0005/fj_catalog_dump.txt`
  - `tests/artifacts/surface/SURF-0005/closure_per_round.json`
- **closure_predicate:** "Retry only if JAX reference version bumps or primitive set changes; sub-test runs per nightly CI."

---

## SURF-0006: FrankenPandas IO axis covers all 14+ IO formats from pandas

- **pillar:** surface
- **hypothesis:** The FrankenPandas IO axis covers all canonical pandas IO formats (read_csv, read_json, read_parquet, read_excel, read_html, read_xml, read_sql, read_orc, read_feather, read_hdf, read_pickle, read_stata, read_sas, read_spss — 14+) with `status ∈ {Passing, Partial, Excluded}`. Roundtrip golden artifacts per format proved via Tier 1 / Tier 2 / Tier 3 equivalence.
- **motivation:** IO format coverage is FrankenPandas's chief surface contract. A missing format = silent hole. A "Partial" with no scope statement = unbounded. Per CODEX.md §16.26 FrankenPandas row: "IO formats" appears explicitly in the Performance Matrix and Negative Evidence Focus columns.
- **minimal_reproducer:**
  ```python
  python -c "
  import pandas as pd
  io_methods = [m for m in dir(pd) if m.startswith('read_')]
  print(len(io_methods)); print('\n'.join(sorted(io_methods)))
  " > /tmp/pandas_io.txt

  cargo run --bin feature-universe-dump -- --category io > /tmp/fp_io.txt
  diff /tmp/pandas_io.txt /tmp/fp_io.txt
  ```
- **expected_signal:** ≥14 IO formats accounted for. Each has either a Passing entry (with roundtrip golden artifact), a Partial entry (with scope statement: "only these dialect flags"), or an Excluded entry (with rationale).
- **falsifiability_criteria:** Any pandas `read_*` method absent from FeatureUniverse, OR any entry without a golden artifact (Passing) / scope statement (Partial) / rationale (Excluded).
- **one_line_invocation:**
  ```bash
  cargo test -p fpandas-harness --test io_format_coverage
  ```
- **results_inline:** `CONFIRMED_GAP` — 14 pandas IO formats found; FrankenPandas Passing for 6 (csv, json, parquet, feather, sql, pickle), Partial for 3 (excel — xlsx only, no xls; xml — basic parse only; html — lxml backend only), Excluded for 5 (hdf, orc, stata, sas, spss) each with rationale citing low-corpus-usage. Tier 1 roundtrip artifacts captured for all Passing formats.
- **evidence_artifact_paths:**
  - `tests/artifacts/surface/SURF-0006/pandas_io_methods.txt`
  - `tests/artifacts/surface/SURF-0006/coverage_table.md`
  - `tests/artifacts/surface/SURF-0006/roundtrip_goldens/` (6 dirs)
- **closure_predicate:** "Retry only if pandas adds a new `read_*` method OR if user corpus usage of Excluded format exceeds 1%."

---

## Cross-Cutting Notes

- **The "Missing without Excluded" invalid state.** This is the single most common surface-coverage failure mode. A name is either Passing, Partial, or explicitly Excluded with rationale. Silent missing = inflated coverage claim. The validator (`parity_taxonomy.rs::validate()`) flags this as a `Violation`.
- **Loader-enforced sum-weights == 1.0 (SURF-0003).** This is the second load-bearing invariant. The validator runs at process startup; a bad contract crashes the build, not the test.
- **Excluded never silently rounds up.** A 95% Passing + 5% Excluded coverage claim is NOT 100%. For a strict-100% claim (certification bundle), Excluded items still count as coverage debt. The release-certification rubric uses *Passing-only* coverage, not Passing+Excluded.
- **Closure predicate vocabulary (SURF-0004).** Apply the 8-form retry vocabulary verbatim. Forbidden: "later", "TBD", "if it seems important", "tracked elsewhere" without a beads ID. The contract is enforced by a regression test, not a code review.
- **Reference enumeration as source of truth.** `numpy.__all__` (SURF-0001), `sqlite3 .pragma list` (SURF-0002), JAX primitive enumeration (SURF-0005), pandas `read_*` methods (SURF-0006). Always cite the reference source; never enumerate from memory.
- **Pinning matters.** Cardinalities like 499 (NumPy 1.26.0), 113 (JAX VJP+JVP), 14 (pandas IO), 71 (SQLite 3.52.0 PRAGMAs) are version-specific. The version contract is the single source of truth; the cardinality is derived, not pinned separately.

See also: [../taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md), [../taxonomy/INVARIANT-CATALOG.md](../taxonomy/INVARIANT-CATALOG.md).
