# FEATURE-UNIVERSE.md — FeatureUniverse Design

The `FeatureUniverse` is the structured manifest of every reference-side feature the port claims (or explicitly declines) to implement. It is the single source of truth that drives the parity scorecard, the per-family coverage dashboard, the conformal-band release decision, and the certification bundle. It lives in `crates/<port>-harness/src/parity_taxonomy.rs` (bd-1dp9.1.1 in FrankenSQLite).

Cross-references: [`../THREE-PILLARS.md § Pillar (c) Surface-Parity`](../THREE-PILLARS.md), [`PROJECT-CLASSES.md`](PROJECT-CLASSES.md), [`INVARIANT-CATALOG.md`](INVARIANT-CATALOG.md), [`../methodology/CONFORMAL-RATCHET.md`](../methodology/CONFORMAL-RATCHET.md), [`../tooling/STATIC-TOOLCHAIN.md`](../tooling/STATIC-TOOLCHAIN.md).

---

## Feature Struct (Verbatim)

From MINING-3 §11:
```rust
pub struct Feature {
    pub id: FeatureId,                   // F-SQL-001
    pub title: String,
    pub weight: f64,                     // sum-per-category == 1.0
    pub status: ParityStatus,            // Passing | Partial | Missing | Excluded
    pub exclusion_rationale: Option<String>,
}
```

Adjacent types:
```rust
pub struct FeatureId(pub String);   // e.g., "F-SQL-001", "F-RESP-014", "F-TORCH-072"

pub enum ParityStatus {
    Passing,    // present + Tier-N equivalence holds
    Partial,    // present, conformance gaps known (must point at open beads)
    Missing,    // absent, would be in-scope (must point at open beads)
    Excluded,   // intentionally out of scope; counts as coverage debt for strict-100%
}
```

The `Feature` struct is the row schema; the `FeatureUniverse` is the loader + iterator + validator. Each row also carries (in the on-disk TOML representation) `category`, `description`, `references[]` (links to spec sections / reference docs), and `proof_obligations[]` (pointer into the `InvariantCatalog` — see [`INVARIANT-CATALOG.md`](INVARIANT-CATALOG.md)).

---

## Three Loader-Enforced Invariants

Per MINING-3 §11, the loader enforces three load-bearing invariants. **No `Feature` can be created bypassing the loader.** Construction is private to `parity_taxonomy.rs`; consumers use `FeatureUniverse::load(path) -> Result<Self, LoaderError>`.

### Invariant 1: `sum(weights) == 1.0` per category

> "1. `sum(weights) == 1.0` per category enforced by loader."

If weights don't sum to 1.0 per category, the loader rejects with `LoaderError::WeightSumViolation { category, sum, expected: 1.0 }`. Floating-point tolerance is `1e-9`. No silent normalization — the contract is that the author balanced the weights and the loader merely verifies.

Practical consequence: adding a new `Feature` to a category requires either (a) reducing another feature's weight or (b) reassigning the entire category in `docs/contracts/parity_score_contract.toml` and documenting the rebalance in the changelog. Phase 12 surface architects MUST do this rebalance in the same commit that introduces the new feature.

### Invariant 2: `truncate_score` for cross-platform determinism

> "2. `truncate_score` for cross-platform reproducibility (6 decimal places)."

Verbatim from `score_engine.rs`:
```rust
pub fn truncate_score(x: f64) -> f64 { /* truncate to 6 decimal places */ }
```

Rationale (verbatim): "x86 vs ARM vs WASM differ at LSB; truncation ensures bytewise identical scores regardless of CPU."

Implementation note: `truncate_score` must use integer arithmetic, NOT f64-rounded truncation. The canonical implementation is:
```rust
pub fn truncate_score(x: f64) -> f64 {
    let scaled = (x * 1_000_000.0) as i64;   // truncate via integer cast
    (scaled as f64) / 1_000_000.0
}
```
A f64-rounded `(x * 1e6).round() / 1e6` is NOT the same and will differ across platforms in the 7th decimal place. The integer cast is the contract.

Cross-platform CI test: run the parity-score computation on x86_64-linux + aarch64-darwin + wasm32 + (where available) riscv64; the truncated output must be byte-identical.

### Invariant 3: Deterministic iteration order by FeatureId

> "3. `FeatureUniverse::features()` returns sorted by FeatureId for deterministic iteration → deterministic scoring → meaningful SHA-256 of report."

`FeatureUniverse::features() -> impl Iterator<Item = &Feature>` sorts by `FeatureId.0` lexicographically. The underlying storage MUST be `BTreeMap<FeatureId, Feature>` (or `Vec<Feature>` sorted at load time), NEVER `HashMap`. Any consumer that iterates in a different order is in violation of the contract.

Practical consequence: the SHA-256 of the rendered parity-score report is itself a function of the FeatureUniverse contents AND the iteration order. Deterministic iteration is what makes that SHA-256 meaningful as a release-bundle artifact.

---

## FeatureId Scheme: `F-{CATEGORY}-{SEQ}`

`FeatureId` is `F-` + per-class CATEGORY prefix + `-` + zero-padded sequence number (3 digits, e.g., `F-SQL-001`, `F-SQL-042`, `F-SQL-237`). Sequence numbers are append-only — once issued, never reused, never renumbered (even if the feature is later marked `Excluded`).

### Per-Class CATEGORY Tables

**SQL-Class CATEGORY codes** (suggested seed; ratify in Phase 2):
| CATEGORY | Surface family |
|---|---|
| `SQL` | Core SQL syntax (SELECT, INSERT, UPDATE, DELETE) |
| `DDL` | Data Definition (CREATE/DROP/ALTER TABLE, INDEX, VIEW, TRIGGER) |
| `TYPE` | Type affinity, casts, dynamic typing |
| `NULL` | NULL semantics, three-valued logic |
| `JOIN` | INNER/LEFT/RIGHT/FULL/CROSS, natural joins, USING |
| `AGG` | Aggregate functions, GROUP BY, HAVING |
| `WIN` | Window functions, OVER, frame specs |
| `CTE` | Common Table Expressions, recursive CTEs |
| `JSON` | JSON1 extension |
| `FK` | Foreign keys, deferrable constraints, cascade actions |
| `TRG` | Trigger semantics, INSTEAD OF, RETURNING |
| `TX` | Transactions, SAVEPOINT, isolation |
| `MVCC` | Concurrent writers, BEGIN CONCURRENT, snapshot stability |
| `WAL` | WAL mode, checkpoint, journal modes |
| `IDX` | Index features, partial, expression, covering |
| `PRAGMA` | PRAGMA introspection, runtime config |
| `FUNC` | Scalar functions (string, math, date/time) |
| `COLL` | Collation sequences, custom collations |
| `FTS` | FTS5 extension |
| `RTREE` | R-Tree extension |
| `VTAB` | Virtual table API |

**RESP-Class CATEGORY codes:**
| CATEGORY | Surface family |
|---|---|
| `RESP` | Protocol parsing, RESP2/RESP3 framing |
| `STR` | String commands (GET/SET/MGET/MSET/INCR/APPEND/...) |
| `HASH` | Hash commands (HGET/HSET/HGETALL/HMGET/...) |
| `LIST` | List commands (LPUSH/RPUSH/LRANGE/BLPOP/...) |
| `SET` | Set commands (SADD/SREM/SMEMBERS/SINTER/...) |
| `ZSET` | Sorted set commands (ZADD/ZRANGE/ZRANGEBYSCORE/...) |
| `STREAM` | Stream commands (XADD/XREAD/XGROUP/XACK/...) |
| `PUBSUB` | Publish/Subscribe (PUBLISH/SUBSCRIBE/PSUBSCRIBE/...) |
| `TX` | MULTI/EXEC/DISCARD/WATCH transactional semantics |
| `SCRIPT` | EVAL/EVALSHA/SCRIPT LOAD Lua |
| `SCAN` | SCAN/HSCAN/SSCAN/ZSCAN cursor iteration |
| `EXP` | Key expiration (EXPIRE/PEXPIRE/TTL/PERSIST) |
| `KEY` | Key management (DEL/EXISTS/KEYS/RENAME/...) |
| `SERVER` | Server commands (INFO/CONFIG/DEBUG/...) |
| `RDB` | RDB persistence |
| `AOF` | AOF persistence |
| `REPL` | Replication (REPLICAOF/PSYNC/...) |
| `CLUSTER` | Cluster commands (CLUSTER SLOTS/CLUSTER NODES/MOVED/ASK/...) |
| `CLIENT` | Client commands (CLIENT LIST/CLIENT KILL/CLIENT NO-EVICT/...) |
| `MOD` | Module API |

**Numerical-Python-Class CATEGORY codes:**
| CATEGORY | Surface family |
|---|---|
| `NPYDT` | dtype system, promotion rules, casting |
| `NPYUF` | ufunc dispatch, loop selection, broadcasting |
| `NPYRED` | Reductions (sum/mean/prod/min/max/argmin/argmax/...) |
| `NPYSHAPE` | Shape transforms (reshape/transpose/squeeze/expand_dims/...) |
| `NPYIDX` | Indexing (basic, advanced, boolean, fancy) |
| `NPYLA` | linalg (matmul/dot/solve/inv/svd/qr/eig/...) |
| `NPYFFT` | fft (fft/ifft/fft2/rfft/...) |
| `NPYRNG` | Random (PCG64DXSM-byte-exact, distributions, choice) |
| `NPYIO` | IO (load/save/savez/loadtxt/...) |
| `PDDF` | DataFrame core, dtypes, alignment |
| `PDGB` | groupby |
| `PDMERGE` | merge/join/concat/merge_asof |
| `PDWIN` | rolling/expanding/window |
| `PDIO` | read_csv/to_csv/read_parquet/... |
| `SCIPYLA` | Sparse linalg, dense linalg |
| `SCIPYSPARSE` | Sparse matrix formats |
| `SCIPYOPT` | Optimization |
| `SCIPYINT` | Integration |
| `SCIPYSTATS` | Distributions, hypothesis tests |
| `NXALGO` | NetworkX algorithms (BFS/DFS/shortest paths/centrality/...) |
| `NXGEN` | NetworkX generators |
| `NXIO` | NetworkX IO |

**ML-System-Class CATEGORY codes:**
| CATEGORY | Surface family |
|---|---|
| `ATEN` | aten op dispatch |
| `AUTOGRAD` | autograd graph, gradient computation |
| `NN` | nn modules (Linear/Conv/Attention/BatchNorm/...) |
| `OPTIM` | optimizers (SGD/Adam/AdamW/...) |
| `DATA` | DataLoader, Dataset, sampler |
| `DIST` | torch.distributed (all-reduce/scatter/gather/...) |
| `JIT` | TorchScript / `torch.jit` |
| `EXPORT` | `torch.export`, ONNX export |
| `COMPILE` | `torch.compile`, inductor |
| `QUANT` | Quantization (static/dynamic/QAT) |
| `JAXPR` | JAX primitives + JAXPR IR |
| `JIT_JAX` | `jit`, `pjit` |
| `GRAD_JAX` | `grad`, `value_and_grad` |
| `VMAP` | `vmap` |
| `XLA` | XLA compilation, HLO passes |
| `WHISPER` | franken_whisper-specific (audio preprocessing, decoding, model inference) |

**HTTP-Protocol-Class CATEGORY codes:**
| CATEGORY | Surface family |
|---|---|
| `ROUTE` | Routing, path matching, parameter extraction |
| `EXTRACT` | Extractors (Query/Path/Json/Form/Multipart/...) |
| `VALID` | Validation (Pydantic-equivalent error shape) |
| `OPENAPI` | OpenAPI schema generation |
| `MW` | Middleware (CORS/Auth/Compression/...) |
| `DI` | Dependency Injection, scopes |
| `WS` | WebSockets |
| `STREAM` | Streaming responses (SSE, chunked, websocket frames) |
| `MCP` | MCP protocol (tools/resources/prompts/capabilities) |
| `JSONRPC` | JSON-RPC dispatch (for fastmcp_rust) |

---

## ParityStatus Enum Semantics

```rust
pub enum ParityStatus {
    Passing,
    Partial,
    Missing,
    Excluded,
}
```

### `Passing`
The feature is present in the port AND the corresponding `ProofObligation`s in the `InvariantCatalog` are satisfied (every linked `ArtifactRef` resolves and hash-matches). At minimum, at least one `OracleDifferential` proof obligation must be present and passing; richer features carry additional `MetamorphicProperty`, `ProptestInvariant`, `CrashBoundary`, `EProcess`, `FuzzNonPanic`, `InstaSnapshot` obligations (see [`INVARIANT-CATALOG.md § ProofKind`](INVARIANT-CATALOG.md)).

### `Partial`
The feature is present in the port BUT one or more `ProofObligation`s are failing or missing. The `Feature` row MUST link to one or more open beads (`partial_blocker_beads: Vec<BeadId>`) and the negative ledger MUST have an entry explaining the gap with a retry-condition predicate.

`Partial` weight contribution to the parity score: 0.5 × weight (per MINING-2 §11 scoring model: "Partial → fractional success (0.5, weighted)").

### `Missing`
The feature is absent from the port AND is in scope per the `supported_surface_matrix.toml`. MUST link to open beads (`missing_blocker_beads: Vec<BeadId>`).

`Missing` weight contribution: 0.0.

### `Excluded`
The feature is intentionally out of scope. MUST have `exclusion_rationale: Option<String>` populated AND a `retry_condition` in `supported_surface_matrix.toml` describing what would change to re-include it.

`Excluded` weight contribution: 0.0 — BUT excluded items still count as coverage debt for a strict-100% claim. The `release_traceability()` report lists them explicitly so a release reader can see what was excluded.

**Allowed transitions** (per Phase 12 architect gate; see [`../THREE-PILLARS.md § Pillar (c) thresholds`](../THREE-PILLARS.md)):
- `Missing → Partial → Passing` (promotion)
- `Partial → Passing` (promotion)
- `Excluded → Partial → Passing` (promotion; retire the exclusion-rationale)
- Any → `Excluded` (only with rationale + retry-condition)
- `Passing → Partial` — **rejected at Phase 12**
- `Passing → Missing` — **rejected at Phase 12**
- `Partial → Missing` — **rejected at Phase 12**

---

## Weight Assignment Rubric

Within a category, weights should reflect:
1. **Frequency of use in the reference's real-world workloads** (cite a source: docs, blog post, profiling of representative client)
2. **Centrality to the surface** (e.g., `SELECT` is more central than `EXPLAIN QUERY PLAN`)
3. **Surface-area within the feature** (e.g., `JOIN` covers 5 join types × 4 ON-clause shapes = 20 logical sub-features; deserves more weight than `TRUNCATE`)
4. **Conformance complexity** (features with many edge cases — NULL semantics, dtype promotion, ULP boundaries — deserve more weight to incentivize coverage)

The rubric is documented in `docs/contracts/parity_score_contract.toml` alongside the actual weights:
```toml
# rubric_version = "1.0"
# Each weight is a value in (0, 1] within its category; weights per category MUST sum to 1.0.
# Rationale fields cite the frequency-of-use source and the surface-area count.

[category.SQL]
total_weight_invariant = 1.0
rationale_source = "C SQLite docs + measured frequency from <sample-app-corpus-sha>"

[[category.SQL.feature]]
id = "F-SQL-001"
title = "SELECT with WHERE and basic projections"
weight = 0.20
rationale = "Top-1 query shape in <corpus>; 73% of all read queries"
surface_subcases = 12
references = ["sqlite-3.52.0:lang_select.html"]

[[category.SQL.feature]]
id = "F-SQL-002"
title = "INSERT with literal values"
weight = 0.15
rationale = "Top-1 write shape; baseline ACID test surface"
surface_subcases = 8
references = ["sqlite-3.52.0:lang_insert.html"]

# ... rest of category ...
```

**Anti-pattern:** uniform weights (e.g., 1/N for every feature in the category). This is a tell that the author didn't think about frequency-of-use. The Phase 12 surface architect should reject uniform-weighted contracts as `fail-missing-evidence` (no rationale = no evidence the weights are correct).

---

## SurfaceMatrix: `supported_surface_matrix.toml` Sample

The `supported_surface_matrix.toml` is the per-feature on-disk declaration. The `FeatureUniverse::load()` reads this file plus `parity_score_contract.toml` and constructs the in-memory `BTreeMap<FeatureId, Feature>`.

```toml
# schema_version = "1.0.0"
# Every reference symbol from phase1_unified_recon.md MUST have a row here.
# Loader rejects rows with empty `rationale` or `retry_condition` where required.

[[feature]]
id = "F-SQL-001"
category = "SQL"
title = "SELECT with WHERE and basic projections"
weight = 0.20
status = "passing"
references = ["sqlite-3.52.0:lang_select.html"]
proof_obligations = ["INV-SQL-001-oracle", "INV-SQL-001-metamorphic-predicate"]

[[feature]]
id = "F-SQL-042"
category = "CTE"
title = "Recursive CTE with WITH RECURSIVE"
weight = 0.06
status = "partial"
references = ["sqlite-3.52.0:lang_with.html"]
proof_obligations = ["INV-SQL-042-oracle"]
partial_blocker_beads = ["bd-recur1", "bd-recur2"]
partial_gap_description = "MATERIALIZED hint not yet recognized; non-recursive UNION ALL split into both branches"

[[feature]]
id = "F-SQL-129"
category = "JSON"
title = "JSON1 extension - json_each() and json_tree()"
weight = 0.03
status = "missing"
references = ["sqlite-3.52.0:json1.html"]
proof_obligations = []
missing_blocker_beads = ["bd-json1-each"]

[[feature]]
id = "F-SQL-204"
category = "FTS"
title = "FTS5 extension"
weight = 0.0
status = "excluded"
references = ["sqlite-3.52.0:fts5.html"]
proof_obligations = []
exclusion_rationale = "FTS5 is a separately-versioned extension; targeting 1.0 of port; will revisit at 2.0."
retry_condition = "Re-include if FrankenSQLite 2.0 ratchet target includes full-text-search OR if a downstream user (sqlmodel_rust) requires FTS5 surface."
```

Loader validation:
- Every `feature` row has `id`, `category`, `title`, `weight`, `status` populated
- `status = "partial"` requires `partial_blocker_beads` non-empty AND `partial_gap_description` non-empty
- `status = "missing"` requires `missing_blocker_beads` non-empty (or `retry_condition` if blocked-by-architecture)
- `status = "excluded"` requires `exclusion_rationale` non-empty AND `retry_condition` non-empty
- `weight` is `0.0` for `missing` and `excluded`; non-zero for `passing` and `partial`
- Every `proof_obligations` entry resolves to an `InvariantCatalog` entry (cross-validated by `invariant_catalog::validate()`)

---

## Coverage-Debt Accounting

> "Excluded items still count as coverage debt for a strict-100% claim."

The parity scorecard reports two numbers:

1. **Effective coverage** = Σ(weight × {1.0 if Passing, 0.5 if Partial, 0.0 otherwise}) across all features
2. **Strict coverage** = Σ(weight × {1.0 if Passing, 0.5 if Partial, 0.0 otherwise}) / Σ(weight across ALL features including excluded set with imputed weight)

The "imputed weight" for excluded features is computed from the original reference-side relative-frequency (NOT 0 — that would let the port silently rebalance away any excluded surface). The imputation rule:
```
imputed_weight(excluded_feature) = base_weight_if_included(excluded_feature)
                                  computed from rubric rationale_source for the feature's category
```

Strict-100% requires `Effective == Strict`, which requires zero `Excluded` features OR every `Excluded` feature having `imputed_weight = 0` (which only holds if the rubric source agrees the feature is irrelevant).

The certification template (`RELEASE_CERTIFICATION_TEMPLATE.md`) requires `CERTIFICATION_MIN_VERIFICATION_PCT = 100.0` for strict-conformant-release.v1. This is the STRICT coverage, not the effective coverage.

The `release_traceability()` report on `InvariantCatalog` lists:
- Total features: N
- Passing: P (weight Σ_P)
- Partial: Q (weight Σ_Q)
- Missing: R (weight Σ_R, blocker beads listed)
- Excluded: S (weight Σ_S, rationales listed)
- Effective coverage: (Σ_P + 0.5·Σ_Q)
- Strict coverage: (Σ_P + 0.5·Σ_Q) / (Σ_P + Σ_Q + Σ_R + Σ_S_imputed)
- Strict-100% certifiable: Y/N + blocker list if N

---

## How to Add a Feature Mid-Run

If Phase 11 round N discovers a new reference-side feature not in `supported_surface_matrix.toml` (e.g., a `PRAGMA` you missed in Phase 1), the protocol is:

1. **STOP the round.** Do NOT add the feature silently to an existing category; this would silently re-normalize weights.
2. **Reopen Phase 2** (see [`../PHASES.md § Phase 2`](../PHASES.md)). Bump `parity_score_contract.toml` version. Re-normalize weights.
3. **Audit existing scorecards for retroactive score change.** The Phase 2 reopen will change the denominator; recompute Phase 9 baseline and Phase 11 round-by-round scores so the convergence-tracker has comparable numbers.
4. **Document in the negative ledger** the candidate that exposed the gap (it goes into `surface-deferrals.md` even if it isn't deferred — the entry records the discovery).
5. **Resume Phase 11 round N+1** with the new feature included from the start of the round.

The fact that this requires reopening Phase 2 is intentional: surface-contract changes are not free; they have to ripple through the entire scorecard machinery.

Same protocol applies if Phase 11 retires an `Excluded → Partial` (the imputed-weight calculation changes) or if Phase 12 picks a remediation that introduces a new feature.

---

## Feature Coverage Dashboard

Per MINING-3 §11: "Feature Coverage Dashboard. Per-family coverage (none | partial | full) with release-gate verdict."

The dashboard (`crates/<port>-harness/src/feature_coverage_dashboard.rs`) reads `FeatureUniverse` and renders per-category and per-family verdicts:

```
Category SQL       (24 features, weight 0.40 of total)
  Passing: 18   weight contribution: 0.30
  Partial:  4   weight contribution: 0.04
  Missing:  2   weight contribution: 0.00 (blocker beads: bd-recur1, bd-json1-each)
  Excluded: 0
  Per-family verdict: PARTIAL (4 Partial, 2 Missing)

Category MVCC      (8 features, weight 0.15 of total)
  Passing: 8    weight contribution: 0.15
  Per-family verdict: FULL

Category FTS       (3 features, weight 0.0 of total — all Excluded)
  Excluded: 3   exclusion_rationale: "Targeting 1.0; revisit at 2.0"
  Per-family verdict: NONE (excluded as coverage debt)

[...]

OVERALL:
  Effective coverage: 0.873421 (truncate_score-applied)
  Strict coverage:    0.823100 (truncate_score-applied; imputes excluded weights)
  Strict-100% certifiable: NO (blocked by 6 Missing features + 3 Excluded with non-zero imputed weight)
  Release-gate verdict: BLOCKED (per CERTIFICATION_MIN_VERIFICATION_PCT = 100.0)
```

The release-gate verdict is the input to the `verification_contract_enforcement` matrix; a `BLOCKED` verdict prevents the certification bundler from issuing a `strict-conformant-release.v1` certificate.
