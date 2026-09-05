# IDENTITY-AND-REPRODUCIBILITY — Run Identity Stack + FailureBundle Contract

This file is the operational contract for "how do I replay this exact run?" — the run identity stack, the e2e log schema, the FailureBundle, deterministic seed derivation, and content-addressed artifact identity. Every artifact the gauntlet emits is constructed so a future agent can replay it bit-for-bit. See [KERNEL.md § K-10 + K-11](KERNEL.md) for the axioms; see [../../SKILL.md § Polish Bar](../../SKILL.md) for the relevant polish bar entries this file justifies.

---

## (a) The run identity stack

Every emitted artifact carries the following identity fields. They are not aspirational — `oracle_preflight_doctor` refuses to start a lane if any field cannot be populated.

| Field | Format | Source | Purpose |
|---|---|---|---|
| `run_id` | `{bead_id}-{timestamp}-{pid}` | Composed at lane entry | Distinguishes two runs of the same test; **excluded from `artifact_id` hash** (K-11). |
| `trace_id` | UUIDv4 | Generated at coordinator | Joins logs/spans across subagents in one phase. |
| `scenario_id` | Stable string per scenario | Test-defined | Cross-run signature for the same logical test. |
| `seed` | u64 | `derive_entry_seed(corpus_entry_id)` — never `rand::random()` | Deterministic replay of stochastic test paths. |
| `source_commit_sha` | git SHA-1 (40 hex) | `git rev-parse HEAD` at lane entry | What code produced this artifact. |
| `fixture_manifest_sha256` | SHA-256 (64 hex) | `fixture_root_contract.manifest_sha256` | What inputs were tested against. |
| `backend` | enum | Lane configuration | Subject's backend mode (e.g., `wal`, `concurrent`, `serialized`). |
| `mode` | enum | Lane configuration | Engine mode (e.g., `parity`, `metamorphic`, `fuzz`, `crash-boundary`). |
| `placement_profile` | enum | `placement_profile.toml` | One of `baseline_unpinned | recommended_pinned | adversarial_cross_node`. |
| `artifact_path` | filesystem path | Lane-determined | Where the artifact was written. |
| `artifact_hash` | SHA-256 | Computed post-write | Content-addressed identity (excludes `run_id` — see (e)). |
| `replay_command` | shell string | Lane-emitted | One-liner to reproduce: `cargo test --lib -p <crate> -- --exact <test> --nocapture` + env. |

The stack lives in the envelope (see Differential V2 in [../tooling/ORACLE-TOOLCHAIN.md](../tooling/ORACLE-TOOLCHAIN.md) and MINING-2 §2). Every artifact lane embeds it.

### Placement profile

```
baseline_unpinned       — no CPU affinity; the default for casual runs.
recommended_pinned      — pinned to a specific NUMA node + thread set; the keep-gate default.
adversarial_cross_node  — deliberately scattered across NUMA nodes to stress cache coherence.
```

The placement profile is part of identity because "this perf result on `baseline_unpinned`" is not comparable to "this perf result on `recommended_pinned`" — the same code can show a 10% delta solely from placement. Pin the profile in every comparison.

---

## (b) E2E log schema — `LOG_SCHEMA_VERSION = "1.0.0"`

Logs are not free text for humans; they are machine inputs to future agents. The schema is versioned. From MINING-2 §16:

```rust
pub const LOG_SCHEMA_VERSION: &str = "1.0.0";

pub const REQUIRED_EVENT_FIELDS: &[&str] = &[
    "run_id",      // {bead_id}-{timestamp}-{pid}
    "timestamp",   // ISO 8601 UTC
    "phase",       // setup | execute | validate | teardown
    "event_type",
];

pub const REPLAYABILITY_KEYS: &[&str] = &[
    "scenario_id",
    "seed",
    "phase",
    "context.invariant_ids",
    "context.artifact_paths",
];
```

**Contract:** if the `REPLAYABILITY_KEYS` are present on an event, a future agent drops into the exact failure point. If any are missing, the event fails `log_schema_validator` and the lane exits non-zero.

**Logs as API:** "Not free text for humans; machine-consumable trace future agents parse to compute coverage and bisect regressions." — MINING-2 §16.

### Concretely, every log line is a JSON object

```jsonc
{
  "run_id": "bd-3go.3-20260522T142311Z-12453",
  "timestamp": "2026-05-22T14:23:11.034Z",
  "phase": "execute",
  "event_type": "oracle_divergence",
  "scenario_id": "null_semantics_e2e/three_valued_in_with_null_list",
  "seed": 8174629384172934,
  "context": {
    "invariant_ids": ["INV-1", "INV-SSI-FP"],
    "artifact_paths": ["round_7/phase6_conformance/failures/null_semantics_in_null_list/failure_bundle.json"]
  },
  "first_divergence": "/queries/3/row/2/col/1",
  "classification": "NullHandlingDifference"
}
```

The `phase` field's vocabulary is fixed: `setup | execute | validate | teardown`. The `event_type` field's vocabulary is per-domain extensible but must be declared in the lane's schema doc.

### Validator

```bash
scripts/log_schema_validator.sh <log-file>
# exits 0 if every event has REQUIRED_EVENT_FIELDS and REPLAYABILITY_KEYS where applicable
# exits non-zero with first offending event on stderr
```

---

## (c) FailureBundle v1.0.0 — reproducibility as schema

> "A partial bundle with provenance is more valuable than no bundle. Never skip manifest writing on failure." — MINING-2 §15

Verbatim from MINING-2 §15:

```rust
pub enum FailureType {
    Assertion, Panic, Divergence, Timeout,
    SsiConflict, MvccInvariant, WalRecovery, FileFormat,
    Extension, Other,
}

pub struct FailureBundle {
    pub failure_type: FailureType,
    pub seed: u64,
    pub fixture_id: String,
    pub schedule_fingerprint: String,
    pub artifact_sha256: Vec<String>,
    pub db_page_previews: Vec<u8>,
    pub wal_state_at_failure: Option<String>,
    pub expected_vs_actual: String,
    pub first_divergence_jsonptr: String,   // /failure/first_divergence
    pub git_sha: String,
    pub toolchain_version: String,
    pub platform: String,
    pub feature_flags: Vec<String>,
}
```

### Per-class adaptations
The struct's spirit (seed + fixture + schedule + state + provenance + diff hints + environment) transfers; the type of state captured changes:

| Class | `wal_state_at_failure` analog | `db_page_previews` analog |
|---|---|---|
| **SQL** | WAL state at failure | DB page previews |
| **RESP** | AOF tail + RDB SHA-256 | key+type counts at the moment of failure |
| **Tensor** | Optimizer state dict | parameter tensor checksums |
| **HTTP** | Request body byte-snapshot | response header dump + body MIME-aware preview |
| **NumPy/Pandas/JAX** | RNG state vector + transform stack | DataFrame schema + row sample |

### The first-divergence rule
> "The pointer at `/failure/first_divergence` jumps to byte-offset where engines first disagreed, not to 'test X failed somewhere'." — MINING-2 §15

`first_divergence_jsonptr` is a JSON Pointer (RFC 6901) into the rendered comparator output. Examples:
- `/queries/3/row/7/col/2` — query #3, row 7, column 2 is the first cell where subject ≠ oracle.
- `/headers/Content-Type` — the HTTP response's `Content-Type` header is where divergence starts.
- `/optimizer_state/param_group/0/lr` — the optimizer state dict's first divergent field.

Without first-divergence, the failure is "test X failed somewhere" — useless to a future agent. With it, the agent's first action is `jq -r '.first_divergence' bundle.json` and then opening the artifact at that exact path.

### The partial-bundle-with-provenance rule
On a failure where some state cannot be captured (process panicked, OS killed it, fixture corrupted mid-run), write the bundle anyway with `null` in the fields you couldn't fill and an explicit `partial_reason` string. **Never skip manifest writing on failure.** A bundle with `seed + git_sha + first_divergence + partial_reason` is dramatically more useful than no bundle at all.

---

## (d) Seed derivation — `derive_entry_seed(corpus_entry_id)`, never `rand::random()`

From MINING-2 §4 (SeedContract):
```rust
fn derive_entry_seed(corpus_entry_id: &str) -> u64 { /* deterministic */ }
```

**Rule:** Every stochastic test path derives its seed from a stable identifier (corpus entry id, scenario id, or scheduled seed). Never `rand::random()`, never `rand::thread_rng()`-derived without capture, never `SystemTime::now().nanos()`.

**Same input → same seed → same SQL → same bugs found.** This is what makes the fuzz corpus replayable and makes regression tests deterministic.

### Implementation pattern

```rust
use blake3::Hasher;

pub fn derive_entry_seed(corpus_entry_id: &str) -> u64 {
    let mut h = Hasher::new();
    h.update(b"seed-v1:");
    h.update(corpus_entry_id.as_bytes());
    let out = h.finalize();
    u64::from_le_bytes(out.as_bytes()[..8].try_into().unwrap())
}
```

The `b"seed-v1:"` prefix is a domain-separation tag; if the seed-derivation policy ever changes, bump to `b"seed-v2:"` and the seeds change in a controlled way (the entire fuzz corpus is regenerated under the new policy).

### Fault-VFS default seed
The fault-VFS has its own determinism constant (from MINING-2 §8):
```rust
const DEFAULT_FAULT_SEED: u64 = 0xD1A6_A3F4_9B17_0C5E;
// Torn-write at WAL offset 8192 with valid_bytes=17 produces exactly 17 bytes every run.
```
Same magic constant in every run → same fault sequence → same recovery path exercised → same bugs found. The seed is in the FailureBundle so reproducing the fault is a copy-paste.

---

## (e) Content-addressed artifact ID

From MINING-2 §2:
```rust
pub fn artifact_id(&self) -> String {
    let canonical = CanonicalEnvelope { /* same fields minus run_id */ };
    let json = serde_json::to_string(&canonical).expect("envelope serialization must not fail");
    sha256_hex(json.as_bytes())
}
```

**Invariant:** `artifact_id = SHA-256 of canonical JSON excluding run_id`. Two runs with identical semantic inputs produce the same artifact ID even with different `run_id` (timestamp/PID).

### What this lets you do
- **Dedup** the ledger by `artifact_id` — two runs of the same test produce the same id; the ledger entry references one id, not two.
- **Diff** two runs that should be identical by checking their `artifact_id`s differ; if so, find the semantic difference (someone changed a PRAGMA, a fixture mtime drifted, a feature flag flipped).
- **Cite** a result by `artifact_id` in commit messages, ledger entries, and bead descriptions. The cite survives `git mv`, file rename, lane reorganization.
- **Validate** that a kept artifact hasn't been tampered with — recompute the id from the canonical JSON; compare.

### Canonical JSON rules
The `CanonicalEnvelope` is constructed so that:
1. Field order is deterministic (use `serde_json::Map`'s `BTreeMap` backing, not insertion order).
2. Float fields are stringified with a fixed precision (or use [CONFORMAL-RATCHET.md § truncate_score](CONFORMAL-RATCHET.md) at the boundary).
3. `run_id` is `Option<String>` and `#[serde(skip_serializing_if = "Option::is_none")]` — excluded from the hash.
4. Booleans serialize as `true`/`false`, not `1`/`0`.
5. Null fields are `null`, not omitted (or omitted via `skip_serializing_if = "Option::is_none"` — choose one rule and apply consistently).

### What is included vs excluded

| Field | In `artifact_id` hash? | Why |
|---|:---:|---|
| `format_version` | ✓ | Schema changes change the artifact's identity. |
| `scenario_id` | ✓ | Different scenarios = different artifacts. |
| `seed` | ✓ | Different seeds = different test paths = different artifacts. |
| `engines` (versions, identities) | ✓ | Different engine versions = different oracle = different result space. |
| `pragmas` / config | ✓ | Different PRAGMAs = different observable behavior. |
| `schema` (DDL) | ✓ | Different DDL = different test surface. |
| `workload` (DML) | ✓ | Different workload = different artifact. |
| `canonicalization` rules | ✓ | Different normalization = different comparator = different artifact. |
| `run_id` | ✗ | Provenance, not identity. |
| `timestamp` | ✗ | Provenance, not identity. |
| `pid` | ✗ | Provenance, not identity. |
| `hostname` | ✗ | Provenance, not identity. |

---

## Cross-links

- This file implements [KERNEL.md § K-10 + K-11](KERNEL.md).
- The FailureBundle is mandated by [../../SKILL.md § Polish Bar § FailureBundle](../../SKILL.md) and emitted by the [OPERATORS.md § ⚠ Escalate-To-Fresh-Repro](OPERATORS.md) operator.
- The e2e log schema validator is invoked by every lane; see [../tooling/ORACLE-TOOLCHAIN.md § preflight](../tooling/ORACLE-TOOLCHAIN.md) for where it integrates.
- Deterministic seed derivation is required by [SOAK-PROTOCOL.md](SOAK-PROTOCOL.md) for replayable soak runs.
- Content-addressed artifact id pairs with [CONFORMAL-RATCHET.md § truncate_score](CONFORMAL-RATCHET.md) — the float fields in the canonical envelope are `truncate_score`'d before hashing.
- Placement profile is referenced in [ANTI-PATTERNS.md § "It works on my machine"](ANTI-PATTERNS.md) and is the fix for cross-host perf-claim non-reproducibility.
- The Differential V2 envelope structure (`ExecutionEnvelope`, `EngineVersions`, `PragmaConfig`, `CanonicalizationRules`) lives in [../tooling/ORACLE-TOOLCHAIN.md § Differential V2](../tooling/ORACLE-TOOLCHAIN.md).
