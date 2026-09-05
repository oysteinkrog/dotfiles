# Case Study: SQLModel Rust — `/dp/sqlmodel_rust`

The compile-time-codegen + ORM-round-trip class. Inherits the FrankenSQLite SQL-class floor for dialect parity but adds a Python SQLModel/SQLAlchemy oracle for ORM semantics + a derive-macro schema-snapshot surface.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | SQL-class with compile-time-codegen + ORM-roundtrip overlays ([PROJECT-CLASSES.md § SQL-Class](../taxonomy/PROJECT-CLASSES.md)) |
| **Tier** | **T2 — Single-crate borderline T3** (effectively T3 because of the codegen surface) |
| **Recommended mode** | `gauntlet-full` (first proper application); inherits FrankenSQLite floor for the SQL dialect dimension |
| **Reference pinning** | `docs/contracts/sqlmodel_version_contract.toml` (likely `sqlmodel-0.0.16` + `sqlalchemy-2.x` + `pydantic-2.x`) AND `docs/contracts/csqlite_version_contract.toml` (inherited from frankensqlite parity for the SQLite dialect) |
| **README claims summary** | Derive-macro-driven Rust ORM with Python SQLModel/SQLAlchemy API parity, multi-dialect SQL generation. Recent activity (commits `542292f`, `1a48b04`, `4972caa`) shows reentrant-query fix + async-socket type-annotation fix + Cargo.lock regen for fsqlite 0.1.3 path deps — the SQL parity link to FrankenSQLite is active. |

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance (vs SQLModel/SQLAlchemy) | ❌ | no central harness |
| Conformance (vs SQLite via inherited frankensqlite floor) | ⚠️ | implicit via fsqlite dep |
| Negative ledger | ❌ | absent |
| cass | ⚠️ partial | |
| Agent Mail | ⚠️ partial | |
| bv | ⚠️ partial | |
| Math layer (§75–76) | ❌ | absent |
| MT-scale harness | ❌ | absent |
| RaptorQ | ❌ | inherited via fsqlite if applicable |
| Derive-macro schema oracle | ⚠️ | snapshots informal |
| Query-builder golden files | ✅ | per-pattern SQL golden likely exists |
| Dialect-specific golden (Postgres/MySQL/SQLite) | ⚠️ | partial |
| Schema-migration snapshots | ⚠️ | partial |
| Model-derive compile-fail tests | ✅ | implemented |
| DB-roundtrip fixtures | ⚠️ | partial |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** Per-query benches probably exist. ORM-overhead (query-build + execute + materialize) breakdown unclear.

**First 3 gaps:**
1. **Query-build time vs execute time not separated** — ORM overhead is in query-build; perf claims that fold both hide regressions in either.
2. **N+1 query detection not in bench harness** — lazy-loading vs eager-loading perf gap is order-of-magnitude.
3. **Connection-pool perf not gridded** — pool-size × concurrent-query × per-query cost grid missing.

### (b) Conformance — current state + first 3 gaps

**Current state.** Generated SQL golden files; model-derive compile-fail tests; DB-roundtrip fixtures.

**First 3 gaps:**
1. **Multi-dialect SQL rendering** — Postgres, MySQL, SQLite each have differing SQL renderings; per-dialect golden coverage partial.
2. **Relationship loading semantics** — lazy vs eager; transaction-boundary interactions.
3. **`RETURNING` clause across dialects** — Postgres native, SQLite 3.35+, MySQL 8.0+ via `LAST_INSERT_ID()`; semantics drift.

### (c) Surface — current state + first 3 gaps

**First 3 gaps:**
1. **Field-type coverage** — Python types (`int`, `str`, `Optional[T]`, `List[T]`, `datetime`, `UUID`, `Decimal`, `JSON`) → SQL types matrix.
2. **Relationship kinds** — `Relationship(back_populates=)`, `Relationship(sa_relationship_kwargs={...})` — partial.
3. **Migration generation (Alembic-equivalent)** — typically partial.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/sqlmodel_rust /dp/sqlmodel_rust__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: sqlmodel-0.0.16 + SQLAlchemy 2.x + Pydantic 2.x
# - oracle mode: PyO3 SQLModel, with SQLite/Postgres/MySQL dialect fixtures
# - perf weights: QueryBuild=0.20, Insert=0.20, Select=0.20, Update=0.15,
#   Delete=0.10, Relationship=0.10, Migration=0.05
# - conformance floor: query-builder comparator, dialect SQL byte equality,
#   schema-migration snapshots, model-derive compile-fail tests, DB round-trips
# - failure terms: query builder rewrite broke, SQL rendering cache key changed,
#   relationship loading regressed, returning/upsert semantics drifted, N+1 leaked,
#   dialect-specific corner, migration generation drift, async-socket type wrong

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/sqlmodel_rust /dp/sqlmodel_rust__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 72
```

Wall time T2+ × `gauntlet-full`: **14–21 days.**

---

## 5. Expected Pillar Findings

### Performance
1. **N+1 query on relationship traversal** — eager-loading not enabled by default.
2. **Query-build allocates per-WHERE-clause** — builder-pattern allocation cost.
3. **Connection-pool checkout latency** — async lock contention.
4. **Repeated query parsing** — prepared-statement reuse missing.
5. **`session.commit()` per-statement vs batched** — batch-commit opportunity.
6. **Relationship loading triggers extra round-trips** — selectinload vs joinedload heuristic.

### Conformance
1. **`Optional[int]` → `INTEGER NULL` vs `INTEGER` divergence across dialects.**
2. **`List[T]` → JSON column** — Postgres has native ARRAY; SQLite/MySQL use JSON.
3. **`datetime` precision** — sub-second precision varies by dialect.
4. **`UUID` storage** — native (Postgres) vs string (SQLite) vs binary (MySQL).
5. **`Decimal` precision** — `NUMERIC(p,s)` parameters.
6. **Cascade delete on relationship** — Python SQLAlchemy vs Rust port semantics.
7. **Lazy vs eager loading** — `selectinload`, `joinedload`, `subqueryload` differences.
8. **`RETURNING` clause across dialects** — SQLite 3.35+, Postgres native, MySQL `LAST_INSERT_ID`.
9. **`UPSERT` semantics** — `INSERT ... ON CONFLICT` (SQLite/Postgres) vs `INSERT ... ON DUPLICATE KEY UPDATE` (MySQL).
10. **Schema migration generation** — Alembic operations: `add_column`, `drop_column`, `alter_column` — per-dialect SQL differs.

### Surface
1. **Field-type coverage matrix** — Python types × SQL types per dialect.
2. **Custom column types** — `Column(JSONB)`, `Column(ARRAY(Integer))` — Postgres-specific.
3. **Hybrid properties** — typically excluded.

---

## 6. Patterns to Apply First

1. **Inherits FrankenSQLite SQL-class floor** for SQLite dialect; do NOT duplicate work.
2. **Per-dialect golden** — separate fixture trees for `sqlite/`, `postgres/`, `mysql/`.
3. **Derive-macro schema oracle** — for each `#[derive(SQLModel)]` input, generated SQL DDL must match per-dialect baseline.
4. **Query-builder golden files** — for each query pattern (filter, join, order_by, group_by), capture rendered SQL per dialect.
5. **DB-roundtrip fixtures** — each model → insert → select → assert-equal per dialect.
6. **Model-derive compile-fail tests** — macro misuse must compile-fail with deterministic error message.

---

## 7. Estimated Rounds to Convergence

**10–14 rounds.** Codegen + dialect variance + ORM semantics create many edges.

---

## 8. Risk Register

1. **SQLAlchemy 2.x churn** — major API changes from 1.x; pin minor. *Mitigation:* contract pins.
2. **Postgres/MySQL test infrastructure** — requires real DBs in CI; testcontainers vs hosted. *Mitigation:* `testcontainers` for CI; doc the setup.
3. **Cross-dialect feature gaps** — some Postgres features have no MySQL equivalent (`JSONB`, `ARRAY`); document `excluded` per dialect, not globally.

---

## 9. What Ships from Convergence

`certification_bundle/`:
- Universal floor + inherited frankensqlite floor
- `per_dialect_sql_compliance.json` — SQL byte-equality per dialect per query pattern
- `field_type_coverage.json` — Python type × SQL type matrix
- `relationship_semantics.json` — lazy/eager loading semantics agreement
- `migration_generation.json` — Alembic-equivalent operation coverage

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § SQLModel Rust](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § SQL-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/sql-class.md](../first-bug-hunt/sql-class.md)
- [case-studies/frankensqlite.md](frankensqlite.md) — inherited SQL-class floor
