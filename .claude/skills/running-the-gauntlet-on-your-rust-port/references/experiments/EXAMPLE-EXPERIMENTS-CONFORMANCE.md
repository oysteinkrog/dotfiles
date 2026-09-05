# Worked Conformance Experiments

Six worked conformance experiments using the template from [EXPERIMENT-DESIGNS-TEMPLATE.md](EXPERIMENT-DESIGNS-TEMPLATE.md). Each anchors on a real machinery from the FrankenSQLite conformance stack: the 30-line `scenario()` template, Differential V2 envelope, metamorphic transforms, fault VFS, crash boundaries, e-processes, the mismatch minimizer, and the oracle preflight doctor.

Use as models for your project's `CONFORMANCE_HYPOTHESIS_LEDGER.md`.

---

## CONF-0001: Subject implements SQL three-valued logic for `NULL = NULL`

- **pillar:** conformance
- **hypothesis:** Subject's NULL semantics match reference (csqlite) for the canonical three-valued logic table: `NULL = NULL → NULL`, `NULL IS NULL → 1`, `NULL <> NULL → NULL`, `NULL IS NOT NULL → 0`, and equivalent under `WHERE` filtering and aggregate behavior.
- **motivation:** SQL's three-valued logic is one of the most common port-divergence sources (per CC.md §2.2 Oracle Catalog and §19 Subject-vs-Oracle pattern). Property-based fuzz (`bolero`) generated 50K queries with NULL operands; preliminary scan flagged 3 candidate divergences before classification.
- **minimal_reproducer:**
  ```rust
  // tests/null_semantics_oracle_e2e.rs
  scenario(
      &["CREATE TABLE t(a INTEGER); INSERT INTO t VALUES (NULL), (1), (NULL), (2);"],
      &[
          "SELECT NULL = NULL",
          "SELECT NULL IS NULL",
          "SELECT NULL <> NULL",
          "SELECT NULL IS NOT NULL",
          "SELECT * FROM t WHERE a = NULL",      // returns no rows
          "SELECT * FROM t WHERE a IS NULL",     // returns 2 rows
          "SELECT COUNT(*) FROM t WHERE a = a",  // returns 2 (NULL = NULL is NULL, filtered)
          "SELECT COUNT(a) FROM t",              // returns 2 (NULLs not counted)
          "SELECT COUNT(*) FROM t",              // returns 4
      ],
      "null_three_valued_logic",
  );
  ```
- **expected_signal:** All 9 queries return the same `NormalizedValue` between subject and oracle. Per the 30-line `scenario()` template: both-error agreement is OK (no NULL queries should error here); one-error-one-OK is hard failure.
- **falsifiability_criteria:** Any query produces `MismatchClassification::TrueDivergence`. Note: `NullHandlingDifference` classification gets `triage_priority: 1` (one step below TrueDivergence) — also blocking but tagged for the NULL bucket.
- **one_line_invocation:**
  ```bash
  cargo test -p fsqlite-e2e --test null_semantics_oracle_e2e -- --nocapture
  ```
- **results_inline:** `CONFIRMED_GAP` (initial round) → `NO_EVIDENCE` (after fix) — Initial run produced 1 TrueDivergence on the `SELECT * FROM t WHERE a = NULL` form (subject returned 2 rows due to coerce-to-zero bug); subsequent fix in `crates/fsqlite-vdbe/src/comparator.rs` produced 0 mismatches. Now wired as permanent regression test; failure bundle for original divergence preserved at `tests/artifacts/conformance/CONF-0001-orig/`.
- **evidence_artifact_paths:**
  - `tests/artifacts/conformance/CONF-0001/oracle_replies.json`
  - `tests/artifacts/conformance/CONF-0001/subject_replies.json`
  - `tests/artifacts/conformance/CONF-0001-orig/failure_bundle.json`
- **closure_predicate:** "Retry only if reference (`sqlite3`) NULL semantics change in version 3.53+."

---

## CONF-0002: Metamorphic transform `WHERE p AND q ≡ WHERE q AND q AND p` (Predicate family)

- **pillar:** conformance
- **hypothesis:** Under the `TransformFamily::Predicate` rewrite "duplicate one conjunct and reorder", the rewritten query returns the same `MultisetEquivalence` answer as the original — regardless of which plan the planner chooses.
- **motivation:** The metamorphic machinery (`crates/fsqlite-harness/src/metamorphic.rs`) catches optimizer bugs that pure differential testing misses: if both engines pick the same wrong plan, differential is silent. Metamorphic rewrites force planner divergence. The duplicate-conjunct rewrite is algebraically sound (`q AND q ≡ q`) and exercises the planner's pushdown logic. EquivalenceExpectation is `MultisetEquivalence` (order may vary across plans).
- **minimal_reproducer:**
  ```rust
  let original = "SELECT * FROM t WHERE a > 5 AND b < 10";
  let rewritten = "SELECT * FROM t WHERE b < 10 AND b < 10 AND a > 5";

  let r0 = subject_rows(&conn, original)?;
  let r1 = subject_rows(&conn, rewritten)?;

  // MultisetEquivalence: sort both, compare
  let mut s0 = r0.clone(); s0.sort();
  let mut s1 = r1.clone(); s1.sort();
  assert_eq!(s0, s1, "metamorphic equivalence violated");
  ```
- **expected_signal:** Across 1000 seeded queries (`derive_entry_seed(corpus_entry_id)`, never `rand::random()`), zero `MismatchClassification::TrueDivergence`. `OrderDependentDifference` outcomes are OK under MultisetEquivalence (triage_priority 4, non-blocking).
- **falsifiability_criteria:** Any TrueDivergence; or per-fuzz-corpus-entry crash.
- **one_line_invocation:**
  ```bash
  cargo test -p fsqlite-e2e --test metamorphic_predicate_family -- --nocapture --test-threads=1
  ```
- **results_inline:** `CONFIRMED_GAP` — caught planner bug where `b < 10 AND b < 10` triggered double-evaluation of a side-effecting `random()` subquery in the WHERE clause. Bug bisected via `MismatchSignature` dedup to a single root cause across 47 corpus entries; `Subsystem::Planner` classified. Fix moved deduplication to the predicate canonicalization stage.
- **evidence_artifact_paths:**
  - `tests/artifacts/conformance/CONF-0002/metamorphic_corpus.jsonl`
  - `tests/artifacts/conformance/CONF-0002/failures_by_signature.json`
  - `tests/artifacts/conformance/CONF-0002/failure_bundles/` (47 bundles, deduplicated to 1 signature)
- **spawned_hypotheses:** `[CONF-0003: same rewrite on Projection family; CONF-0004: same rewrite on Structural family (wrap in subquery)]`
- **closure_predicate:** "Retry only if planner pushdown logic changes; new TransformFamily corpus entries added monthly."

---

## CONF-0003: `BeforeWalFrameAppend` crash boundary produces recoverable state

- **pillar:** conformance
- **hypothesis:** When a crash is armed at the `CrashBoundary::BeforeWalFrameAppend` boundary, the post-recovery state contains either (a) every committed transaction with no torn frame, or (b) every committed transaction *except* the in-flight one — never a torn-half state with partial frame bytes.
- **motivation:** WAL crash safety is the single highest-priority correctness property in any SQLite-class storage engine. The crash-boundary protocol injection (CC.md §10 + `crates/fsqlite-wal/src/fault_hooks.rs`) defines 8 named boundaries. `BeforeWalFrameAppend` is the most subtle: bytes for the next frame *might* be partially written if we crash mid-`pwrite`, but the WAL format requires whole frames. Crash discipline: "not 'right state' but 'committed-or-not-committed-no-partial'."
- **minimal_reproducer:**
  ```rust
  let mut vfs = FaultInjectingVfs::new(MemoryVfs::new());
  arm_crash_boundary(CrashBoundary::BeforeWalFrameAppend, FaultHookArm::Once);
  let conn = open_with_vfs(&vfs)?;
  conn.execute("BEGIN; INSERT INTO t VALUES (1), (2); COMMIT")?;  // crashes mid-COMMIT
  // Now reopen
  let conn2 = open_with_vfs(&vfs)?;
  // Assert: either rows present (committed before crash) or absent (crash before durability), never partial
  let rows = subject_rows(&conn2, "SELECT a FROM t ORDER BY a")?;
  assert!(rows == vec![] || rows == vec![vec!["1".into()], vec!["2".into()]]);
  ```
- **expected_signal:** Across 1000 fuzz-seeded write-then-crash scenarios, every recovered DB is one of the two acceptable states. No partial-frame, no torn-frame, no zero-length frame in WAL. `fsqlite_test_vfs_faults_injected_total` metric reports 1000 fault injections.
- **falsifiability_criteria:** Any scenario produces a third state (partial commit visible / partial values / corrupted page); any `FailureType::WalRecovery` in the FailureBundle.
- **one_line_invocation:**
  ```bash
  cargo test -p fsqlite-e2e --test wal_crash_boundary_recovery -- --nocapture --test-threads=1
  ```
- **results_inline:** `NO_EVIDENCE` — 1000 scenarios all recovered to one of the two acceptable states. Determinism verified: same seed → same 17 valid bytes per torn-write attempt (`DEFAULT_FAULT_SEED: u64 = 0xD1A6_A3F4_9B17_0C5E`). E-process for `WriteSetConsistency` (INV-4) accumulated >10K observations under fault load with E-value well below `1/α = 1000`.
- **evidence_artifact_paths:**
  - `tests/artifacts/conformance/CONF-0003/recovery_outcomes.jsonl` (1000 entries)
  - `tests/artifacts/conformance/CONF-0003/fault_trigger_records.jsonl`
  - `tests/artifacts/conformance/CONF-0003/eprocess_inv4_trace.json`
- **closure_predicate:** "Retry only if WAL frame format changes OR if new fault profile (e.g., `partial-pwrite-with-aio`) is added to the matrix."

---

## CONF-0004: E-process for INV-3 (VersionChainOrder) stays below `1/α` after 10M operations

- **pillar:** conformance
- **hypothesis:** Under the calibration `p₀ = 1e-6, λ = 0.9, α = 0.001` (software-enforced invariant per MINING-2 §10), the per-operation e-process for `MvccInvariant::VersionChainOrder` stays below the rejection threshold `1/α = 1000` after 10M operations on the canonical `mt_mvcc_bench` shared-table workload.
- **motivation:** INV-3 ("chains descending by `commit_seq`") is the most write-intensive MVCC invariant. Per Ville's inequality: `P_{H_0}(∃t: E_t ≥ 1/α) ≤ α`. If the e-process crosses 1/α at any t, we reject the null (subject violates INV-3 in production). Anytime-valid: check after every operation, no Bonferroni correction. **No alpha-budget pollution.**
- **minimal_reproducer:**
  ```rust
  let monitor = EProcessMonitor::new(MvccInvariant::VersionChainOrder, EProcessParams::software_default());
  for _ in 0..10_000_000 {
      let observation = do_one_mvcc_operation_with_witness();  // returns (observed_outcome, expected_outcome)
      monitor.observe(observation);
      assert!(monitor.e_value() < 1.0 / 0.001, "e-process crossed Ville threshold at op {i}");
  }
  ```
- **expected_signal:** Final e-value < 1000 (1/α). Per-operation e-value trajectory plottable and monotone in expectation under H₀. No threshold crossing.
- **falsifiability_criteria:** E-value ≥ 1000 at any observation. (Crossing = rejection of H₀ = subject violates INV-3 = bug to fix and FailureBundle to emit.)
- **one_line_invocation:**
  ```bash
  cargo test -p fsqlite-e2e --test mvcc_inv3_eprocess --release -- --nocapture --ignored
  ```
- **results_inline:** `NO_EVIDENCE` — 10M operations completed; final e-value 1.7 (well below 1000). Monitor wired into `mt_mvcc_bench --threads=8` for continuous CI observation. Also feeds the BOCPD regime detector (`replay_harness.rs`); per-window regime stayed `Stable` throughout.
- **evidence_artifact_paths:**
  - `tests/artifacts/conformance/CONF-0004/eprocess_trajectory.csv` (10M rows; 60MB)
  - `tests/artifacts/conformance/CONF-0004/regime_per_window.json`
  - `tests/artifacts/conformance/CONF-0004/final_e_value.txt` → `1.7`
- **closure_predicate:** "Retry only if MVCC version-chain ordering rules change OR if calibration parameters change."

---

## CONF-0005: Mismatch minimizer produces unique `MismatchSignature` for failures sharing a root cause

- **pillar:** conformance
- **hypothesis:** Two failures that derive from the same root cause produce identical `MismatchSignature` values (where `signature.hash` is the truncated SHA-256 of the canonical minimal repro). The minimizer (`crates/fsqlite-harness/src/mismatch_minimizer.rs`) deduplicates correctly so a single root cause maps to a single bead, not N beads.
- **motivation:** Without this, every fuzz iteration that triggers the same bug opens a new bead. The minimizer's binary-partition narrowing + schema-preservation guard is the dedup primitive. This experiment is a regression test against the dedup logic itself — adversarial-search style.
- **minimal_reproducer:**
  ```rust
  // Construct two failures known to share a root cause: planner picks wrong index for compound predicates
  let f1 = run_until_failure("CREATE TABLE t(a,b); INSERT INTO t SELECT i, i%7 FROM gs(1,1000); SELECT * FROM t WHERE a > 100 AND b = 3 AND a < 200")?;
  let f2 = run_until_failure("CREATE TABLE u(x,y,z); INSERT INTO u SELECT i, i%5, 'foo' FROM gs(1,500); SELECT * FROM u WHERE x > 50 AND z = 'foo' AND x < 150")?;

  let s1 = MismatchMinimizer::minimize(&f1).signature();
  let s2 = MismatchMinimizer::minimize(&f2).signature();
  assert_eq!(s1.hash, s2.hash);
  assert_eq!(s1.subsystem, Subsystem::Planner);
  ```
- **expected_signal:** `s1.hash == s2.hash` after canonicalization. Both classified `Subsystem::Planner`. Both reduced to ≤3 statements (schema preserved; setup not removed per the rule "schema setup never removed").
- **falsifiability_criteria:** Different hashes (dedup broken — would file 2 beads instead of 1), OR same hash but different subsystem (canonical form is too aggressive — merging unrelated bugs).
- **one_line_invocation:**
  ```bash
  cargo test -p fsqlite-harness --test mismatch_minimizer_dedup_regression
  ```
- **results_inline:** `NO_EVIDENCE` — both failures minimize to identical signature (`hash: "9f4a..."`, `subsystem: Planner`, `minimal_statement_count: 3`). The bisect found the smaller statement count was bounded below by the schema-preservation guard. Wired as permanent regression test.
- **evidence_artifact_paths:**
  - `tests/artifacts/conformance/CONF-0005/f1_failure_bundle.json`
  - `tests/artifacts/conformance/CONF-0005/f2_failure_bundle.json`
  - `tests/artifacts/conformance/CONF-0005/f1_minimized.sql`
  - `tests/artifacts/conformance/CONF-0005/f2_minimized.sql`
  - `tests/artifacts/conformance/CONF-0005/signatures.json`
- **closure_predicate:** "Retry only if `MismatchSignature` algorithm changes (e.g., new canonicalization rule, new Subsystem variant)."

---

## CONF-0006: Oracle preflight doctor catches a fake oracle binary (negative test)

- **pillar:** conformance
- **hypothesis:** When `$PATH`-resolved `sqlite3` binary is replaced with a no-op stub that emits empty output, `oracle_preflight_doctor.sh` emits aggregate outcome `red` with `certifying: false` and refuses to allow any parity / certification lane to proceed.
- **motivation:** The "fake oracle" silent-pass is the worst-case failure for an honest harness — every test "passes" because the oracle returns nothing and the comparator agrees with nothing. The preflight doctor is the guard. This experiment exercises the guard from the wrong side: it intentionally breaks the oracle to confirm the gate flips red.
- **minimal_reproducer:**
  ```bash
  set -e
  WORK=$(mktemp -d)
  cat > "$WORK/sqlite3" <<'EOF'
  #!/bin/sh
  exit 0
  EOF
  chmod +x "$WORK/sqlite3"
  PATH="$WORK:$PATH" ./scripts/oracle-preflight-doctor.sh "$TARGET"
  # Expect: exit code non-zero; JSON report aggregate_outcome="red"; certifying=false.
  ```
- **expected_signal:** Script exits non-zero. JSON report contains `"aggregate_outcome": "red"`, `"certifying": false`, and a `first_failure_diagnosis` naming "version mismatch", "identity string mismatch", or "fixture cardinality below floor". Remediation class names a specific class; `fix_command` is shell-runnable.
- **falsifiability_criteria:** Script exits zero (gate failed open), OR `certifying: true` (worst possible failure).
- **one_line_invocation:**
  ```bash
  ./scripts/test-oracle-preflight-doctor-negative.sh
  ```
- **results_inline:** `NO_EVIDENCE` — fake binary detected on first check (`expected SQLite version 3.52.0; got empty version string`); aggregate `red`; `certifying: false`; remediation class `OracleVersionMismatch`; `fix_command: "install sqlite3 3.52.0; cf docs/contracts/sqlite_version_contract.toml"`. The doctor refused to let `oracle-runner` proceed. Permanent negative-test in CI.
- **evidence_artifact_paths:**
  - `tests/artifacts/conformance/CONF-0006/preflight_report_red.json`
  - `tests/artifacts/conformance/CONF-0006/preflight_exit_code.txt` → `1`
- **closure_predicate:** "Retry only if `oracle_preflight_doctor.rs` schema changes; integration test runs nightly."

---

## Cross-Cutting Notes

- **Both-error = agreement (CONF-0001).** A common source of false-pass: declaring a divergence when only message text differs across error returns. The 30-line `scenario()` template (MINING-2 §1) enforces: `(Err(_), Err(_)) → agreement`, regardless of message.
- **`MismatchClassification` triage tier (CONF-0001, CONF-0002).** CI fails only on `TrueDivergence`. Other classes (NullHandling, TypeAffinity, FloatingPoint, OrderDependent, FalsePositive) flow into a triage queue. **Triage priority is fixed at compile time**, not negotiable.
- **`derive_entry_seed`, never `rand::random()` (CONF-0002).** Reproducibility is non-negotiable. The `SeedContract` (MINING-2 §4) means same `corpus_entry_id` → same seed → same SQL → same bugs found in CI 6 months later.
- **Crash-boundary discipline (CONF-0003).** "Not 'right state' but 'committed-or-not-committed-no-partial'." The acceptance set is two states, not one. Any third state is a bug, regardless of how plausible the partial state looks.
- **E-process anytime-validity (CONF-0004).** No Bonferroni correction. Check after every operation. The global e-value is the arithmetic mean of per-invariant e-values — a valid e-process under H₀ regardless of dependence.
- **Mismatch dedup as primitive (CONF-0005).** A bisect that hits a known bug *links* rather than *opens* a new beads issue.
- **Oracle preflight doctor as guard (CONF-0006).** This is the meta-experiment: testing the harness's ability to refuse to lie even when fed a lying oracle.

See also: [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md), [../tooling/ORACLE-TOOLCHAIN.md](../tooling/ORACLE-TOOLCHAIN.md).
