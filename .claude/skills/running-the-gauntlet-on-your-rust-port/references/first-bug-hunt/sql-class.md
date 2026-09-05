# First-Bug-Hunt Recipe: SQL-Class

Empirically, these 10 bug classes surface in the first day of running the gauntlet on any SQL-class port (frankensqlite, sqlmodel_rust). Steps are ordered roughly by frequency-of-finding × cost-to-set-up.

**Prerequisites:** oracle wired (`rusqlite` via `libsqlite3-sys`); `scenario()` template available; `normalize_value` rendering; `EngineIdentity` asserted distinct.

Per item: **symptom** → **paste-ready repro** → **MismatchClassification expected** → **severity** → **pattern to apply**.

---

## 1. NULL semantics edges in IN / NOT IN

**Symptom.** `WHERE x IN (subquery)` or `WHERE x NOT IN (subquery)` returns different rows in subject vs oracle when the subquery contains NULL. Classic SQL three-valued-logic landmine: `x NOT IN (NULL, ...)` is always `UNKNOWN` (treated as `FALSE` by `WHERE`), so the row is filtered out — but a subject implementation that treats `NULL` as "not equal to anything" wrongly keeps the row.

**Repro:**
```bash
cargo test --package fsqlite-e2e --test null_semantics_oracle_e2e \
  -- not_in_with_null --nocapture
```

Or via the scenario template:
```rust
scenario(
    &["CREATE TABLE t(x INTEGER); INSERT INTO t VALUES (1), (2), (3);"],
    &[
      "SELECT x FROM t WHERE x IN (SELECT NULL UNION SELECT 2)",
      "SELECT x FROM t WHERE x NOT IN (SELECT NULL UNION SELECT 2)",
    ],
    "null_in_not_in"
);
```

**MismatchClassification:** `NullHandlingDifference` (priority 1).
**Severity:** **high** — silent wrong-rows in production queries.
**Fix pattern:** [pattern:40-METAMORPHIC-TRANSFORMS](../patterns/40-METAMORPHIC-TRANSFORMS.md) `EquivalenceExpectation::ExactRowMatch` + `MismatchClassification::NullHandlingDifference { sentinel: SqlNull }`; add to `null_semantics_oracle_e2e.rs` test corpus.

---

## 2. Three-valued logic in CASE/COALESCE/IIF

**Symptom.** `CASE x WHEN NULL THEN 'a' ELSE 'b' END` always returns `'b'` per SQL standard (NULL ≠ NULL); subject may return `'a'`.

**Repro:**
```rust
scenario(
    &["CREATE TABLE t(x INTEGER); INSERT INTO t VALUES (NULL), (1);"],
    &[
      "SELECT CASE x WHEN NULL THEN 'a' ELSE 'b' END FROM t",
      "SELECT COALESCE(x, 0) FROM t",
      "SELECT IIF(x IS NULL, 1, 0) FROM t",
    ],
    "case_coalesce_iif_null"
);
```

**MismatchClassification:** `NullHandlingDifference`.
**Severity:** **high.**
**Fix pattern:** [pattern:40-METAMORPHIC-TRANSFORMS](../patterns/40-METAMORPHIC-TRANSFORMS.md) `TransformFamily::Literal`; ensure `NULL` literal in CASE-WHEN comparison always evaluates `UNKNOWN`.

---

## 3. GROUP BY with NULL keys

**Symptom.** SQLite groups all NULL values into a single group; some ports treat each NULL as distinct. Result: extra rows for `SELECT x, COUNT(*) FROM t GROUP BY x` when `x` has NULLs.

**Repro:**
```bash
cargo test --package fsqlite-e2e --test group_by_null_keys_oracle_e2e -- --nocapture
```

```rust
scenario(
    &["CREATE TABLE t(x INTEGER); INSERT INTO t VALUES (NULL), (NULL), (1), (1), (2);"],
    &["SELECT x, COUNT(*) FROM t GROUP BY x ORDER BY x NULLS FIRST"],
    "group_by_null_keys"
);
```

**MismatchClassification:** `NullHandlingDifference`.
**Severity:** **high.**
**Fix pattern:** `MultisetEquivalence` is wrong here — `ExactRowMatch` required because NULL-group cardinality is the bug.

---

## 4. Recursive CTE termination

**Symptom.** `WITH RECURSIVE` query that terminates in oracle hangs or stack-overflows in subject. Cause: termination check applied after `LIMIT` evaluation, but `LIMIT 0` should short-circuit.

**Repro:**
```rust
scenario(
    &[],
    &[
      "WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM c LIMIT 0) SELECT * FROM c",
      "WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM c WHERE n < 10) SELECT * FROM c",
    ],
    "recursive_cte_termination"
);
```

**MismatchClassification:** `TrueDivergence { description: "infinite loop or stack overflow" }`.
**Severity:** **critical** — DoS vector.
**Fix pattern:** [pattern:30-DIFFERENTIAL-V2-ENVELOPE](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) with explicit timeout in `scenario()`; first-pass: wrap every oracle query in a 30s timeout.

---

## 5. JOIN type semantics on duplicate keys

**Symptom.** `LEFT JOIN` with duplicate keys on the right side; row multiplication factor differs. Subject may dedup right-side rows; oracle does not.

**Repro:**
```rust
scenario(
    &[
      "CREATE TABLE a(id INTEGER, v TEXT);",
      "CREATE TABLE b(id INTEGER, w TEXT);",
      "INSERT INTO a VALUES (1, 'a'), (2, 'b');",
      "INSERT INTO b VALUES (1, 'x'), (1, 'y'), (1, 'z');",
    ],
    &[
      "SELECT * FROM a LEFT JOIN b USING(id) ORDER BY a.id, b.w",
      "SELECT * FROM a INNER JOIN b ON a.id = b.id ORDER BY a.id, b.w",
    ],
    "join_duplicate_keys"
);
```

**MismatchClassification:** `TrueDivergence { description: "row-multiplication factor mismatch" }`.
**Severity:** **critical** — aggregation results wrong (`SUM` over JOIN inflated).
**Fix pattern:** `ExactRowMatch` mandatory; never `MultisetEquivalence` here.

---

## 6. PRAGMA introspection drift

**Symptom.** `PRAGMA compile_options` / `PRAGMA function_list` / `PRAGMA module_list` return different rows in subject vs oracle. Cause: subject compiled with different feature flags than the linked C SQLite.

**Repro:**
```rust
scenario(
    &[],
    &[
      "PRAGMA compile_options",
      "PRAGMA function_list",
      "PRAGMA module_list",
      "PRAGMA collation_list",
    ],
    "pragma_introspection"
);
```

**MismatchClassification:** `FalsePositive { reason: "expected per-build divergence" }` IF documented; otherwise `TrueDivergence`.
**Severity:** **medium** — client code reading compile_options may make wrong dispatch.
**Fix pattern:** [pattern:105-FEATURE-UNIVERSE](../patterns/105-FEATURE-UNIVERSE.md) — add per-compile-flag axis to FeatureUniverse; document `excluded` per flag.

---

## 7. LIKE / GLOB / ESCAPE corner cases

**Symptom.** `LIKE 'a%' ESCAPE '\'` with subject not honoring ESCAPE for `%` → matches `a\foo`; oracle does not.

**Repro:**
```rust
scenario(
    &["CREATE TABLE t(s TEXT); INSERT INTO t VALUES ('a%b'), ('a_b'), ('abc'), ('a\\%b');"],
    &[
      "SELECT * FROM t WHERE s LIKE 'a\\%b' ESCAPE '\\' ORDER BY s",
      "SELECT * FROM t WHERE s LIKE 'a\\_b' ESCAPE '\\' ORDER BY s",
      "SELECT * FROM t WHERE s GLOB 'a[%]b' ORDER BY s",
      "SELECT * FROM t WHERE s LIKE 'A%' ORDER BY s",   // case-sensitivity per PRAGMA
    ],
    "like_glob_escape"
);
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **medium-high** — SQL injection vectors hide here.
**Fix pattern:** [pattern:40-METAMORPHIC-TRANSFORMS](../patterns/40-METAMORPHIC-TRANSFORMS.md) `TransformFamily::Literal` with escape-char rewrites.

---

## 8. Conflict resolution mode interactions

**Symptom.** `INSERT OR REPLACE` vs `INSERT OR IGNORE` vs `INSERT ... ON CONFLICT DO UPDATE` produce different post-state. SQLite's UPSERT semantics around triggers + foreign keys subtle.

**Repro:**
```rust
scenario(
    &[
      "CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT UNIQUE);",
      "CREATE TABLE log(action TEXT);",
      "CREATE TRIGGER trig AFTER UPDATE ON t BEGIN INSERT INTO log VALUES ('upd'); END;",
      "INSERT INTO t VALUES (1, 'a'), (2, 'b');",
    ],
    &[
      "INSERT OR REPLACE INTO t VALUES (1, 'c'); SELECT * FROM log",
      "INSERT INTO t VALUES (2, 'c') ON CONFLICT(v) DO UPDATE SET v='c'; SELECT * FROM log",
    ],
    "conflict_resolution"
);
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **high** — trigger firing differs (REPLACE deletes-then-inserts; UPSERT updates).
**Fix pattern:** [pattern:30-DIFFERENTIAL-V2-ENVELOPE](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) with multi-statement schema; observe full state via `SELECT * FROM t; SELECT * FROM log`.

---

## 9. ATTACH / TEMP visibility

**Symptom.** `ATTACH DATABASE 'other.db' AS other` with `SELECT * FROM other.t` — subject finds table; or doesn't; or finds wrong table when both `main` and `other` have a `t`.

**Repro:**
```rust
scenario(
    &[
      "ATTACH DATABASE ':memory:' AS other",
      "CREATE TABLE main.t(x INTEGER); INSERT INTO main.t VALUES (1);",
      "CREATE TABLE other.t(x INTEGER); INSERT INTO other.t VALUES (2);",
      "CREATE TEMP TABLE t(x INTEGER); INSERT INTO t VALUES (3);",
    ],
    &[
      "SELECT * FROM t ORDER BY x",                // which one wins?
      "SELECT * FROM main.t ORDER BY x",
      "SELECT * FROM other.t ORDER BY x",
      "SELECT * FROM temp.t ORDER BY x",
    ],
    "attach_temp_visibility"
);
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **high.**
**Fix pattern:** name-resolution-order documented as per-SQLite-version contract; [pattern:115-CLOSURE-WAVE](../patterns/115-CLOSURE-WAVE.md) Resolver domain.

---

## 10. ALTER TABLE rename propagation across triggers / views / indexes

**Symptom.** `ALTER TABLE t RENAME TO u` should rewrite references in dependent triggers, views, and (sometimes) indexes. Subject may rewrite some but not all.

**Repro:**
```rust
scenario(
    &[
      "CREATE TABLE t(x INTEGER);",
      "CREATE VIEW v AS SELECT * FROM t WHERE x > 0;",
      "CREATE TRIGGER trig AFTER INSERT ON t BEGIN SELECT 1; END;",
      "CREATE INDEX idx ON t(x);",
      "ALTER TABLE t RENAME TO u;",
    ],
    &[
      "SELECT sql FROM sqlite_master WHERE name='v'",     // should reference 'u' now
      "SELECT sql FROM sqlite_master WHERE name='trig'",   // should reference 'u' now
      "SELECT sql FROM sqlite_master WHERE name='idx'",
      "INSERT INTO u VALUES (1)",
      "SELECT * FROM v",
    ],
    "alter_rename_propagation"
);
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **critical** — schema corruption.
**Fix pattern:** [pattern:115-CLOSURE-WAVE](../patterns/115-CLOSURE-WAVE.md) covering Parser + Resolver + Storage domains; integration test in `alter_rename_oracle_e2e.rs`.

---

## Empirical first-day stats (calibration)

Running this recipe on a *new* SQL-class port typically surfaces:
- **2–4 of the above 10 in the first hour** (high-frequency edge cases: NULL handling + GROUP BY NULL + recursive CTE)
- **6–8 in the first day** (after the harness is built and the corpus is wide enough)
- **All 10 within first 3 rounds** of the gauntlet

Items 4 (recursive CTE termination) and 9 (ATTACH/TEMP visibility) tend to be the deepest — they require multi-statement scenarios and frequently surface follow-on `NEW_HYPOTHESIS_SPAWNED` ledger entries.

---

## Cross-references

- [PROJECT-CLASSES.md § SQL-Class](../taxonomy/PROJECT-CLASSES.md)
- [case-studies/frankensqlite.md](../case-studies/frankensqlite.md)
- [case-studies/sqlmodel_rust.md](../case-studies/sqlmodel_rust.md)
- [patterns/40-METAMORPHIC-TRANSFORMS.md](../patterns/40-METAMORPHIC-TRANSFORMS.md)
- [patterns/115-CLOSURE-WAVE.md](../patterns/115-CLOSURE-WAVE.md)
