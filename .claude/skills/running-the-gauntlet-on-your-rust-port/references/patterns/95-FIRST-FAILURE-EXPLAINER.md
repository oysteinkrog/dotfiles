# Pattern 95 — FIRST FAILURE EXPLAINER (replay command + remediation playbook + artifact hashes)

## What

A small composite struct, `FirstFailureExplainer`, that turns the [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) into a 5-line CI summary an agent can act on immediately: (1) first divergence dereferenced via JSONPointer, (2) root-cause domain enum, (3) exact replay command, (4) `RemediationPlaybook` with `owner_hint` + `summary` + `next_commands[]`, (5) `ArtifactHashTable` mapping logical names to SHA-256s. The CI summary is the agent's contract with the human (or follow-up agent) reading the build log: it must contain enough to start work without opening the bundle.

## Why

A CI log that says "test failed, see artifacts/" is a CI log that adds 10 minutes of context-switch to every failure. The 5-line format compresses the bundle's signal into terminal-readable text; the explainer is the bundle's TL;DR.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/first_failure_explainer.rs` — `FirstFailureExplainer` + `RemediationPlaybook` + `ArtifactHashTable` (MINING-2 §17)
- CI integration in `.github/workflows/verification-gates.yml` (emits the 5-line summary on failure)

## Verbatim shape — the three structs

From MINING-2 §17, verbatim:

```rust
pub struct FirstFailureExplainer {
    pub first_divergence: String,                  // dereferenced via jsonptr
    pub root_cause_domain: RootCauseDomain,        // constraint_violation | wal_recovery | mvcc_invariant
    pub replay_command: String,                    // cargo test --lib bd_…
    pub remediation_playbook: RemediationPlaybook,
}

pub struct RemediationPlaybook {
    pub owner_hint: String,
    pub summary: String,
    pub next_commands: Vec<String>,
}

pub struct ArtifactHashTable {
    pub hashes: BTreeMap<String, String>,
}
```

### `RootCauseDomain` (canonical SQL-class)

```rust
pub enum RootCauseDomain {
    ConstraintViolation,
    WalRecovery,
    MvccInvariant,
    Planner,
    Vdbe,
    Storage,
    Parser,
    TypeSystem,
    Pragma,
    Extension,
    Unknown,
}
```

(Mirrors `Subsystem` from [pattern:45-MISMATCH-MINIMIZER](45-MISMATCH-MINIMIZER.md) but at the explainer's coarser granularity.)

## CI summary 5-line format (verbatim MINING-2 §17)

> "CI summary contains in order: (1) first divergence dereferenced, (2) root-cause domain, (3) replay command, (4) playbook with `next_commands[]`, (5) artifact SHA-256 hashes."

Canonical rendering:

```
FAILURE bd-1dp9.2.3 @ 2026-05-22T14:32:01Z
  1. divergence: byte_offset=4096 subject=0x42 oracle=0x43 (see /failure/first_divergence in bundle)
  2. domain:     MvccInvariant
  3. replay:     cargo test -p fsqlite-harness --test bd_1dp9_2_3 -- --exact mvcc_invariant_3_under_torn_wal
  4. playbook:
       owner_hint: mvcc-team / @j_mvcc
       summary:    INV-3 (VersionChainOrder) violated after torn-WAL recovery at offset 8192
       next:
         (a) reproduce: cargo test ... (see above)
         (b) extract:   xxd artifacts/bd-1dp9.2.3/db_page_previews.bin | less
         (c) inspect:   cargo run --bin wal-inspector -- artifacts/bd-1dp9.2.3/wal_state.bin
         (d) hypothesis: write 1-paragraph hypothesis in beads/bd-1dp9.2.3.md
  5. artifacts:
       db_pages         = sha256:c0ffee...
       wal_state        = sha256:deadbe...
       failure_bundle   = sha256:f00d12...
       envelope         = sha256:1a2b3c...
       envelope.artifact_id = 1a2b3c... (content address; see /pattern:30)
```

## Per-class instantiation — `RootCauseDomain` variants

### RESP-class

| Variant | Trigger |
|---|---|
| `RespProtocol` | RESP frame parse failure |
| `Persistence` | RDB/AOF roundtrip failure |
| `Replication` | Primary-replica divergence |
| `Cluster` | Slot ownership inconsistency |
| `PubSub` | Ordering violation |
| `CommandDispatch` | Wrong handler invoked |
| `Eval` | Lua script semantic difference |
| `Modules` | Module API divergence |
| `Networking` | Socket-level fault |
| `Unknown` | (fallback) |

### ML-class

| Variant | Trigger |
|---|---|
| `Autograd` | Forward vs reverse divergence |
| `KernelLauncher` | CUDA error / kernel selection mismatch |
| `DispatchTable` | Wrong ATen op dispatched |
| `AllocatorPool` | Memory layout mismatch |
| `NcclTransport` | Distributed collective failure |
| `JitCache` | Cache key bug |
| `Determinism` | Non-deterministic op leaked |
| `Numerical` | NaN/Inf propagation |
| `Unknown` |

### Numerical-class

| Variant | Trigger |
|---|---|
| `DtypePromotion` |
| `BroadcastEngine` |
| `UfuncDispatch` |
| `RngGenerator` |
| `BlasLapack` |
| `ArrayMemory` |
| `Unknown` |

### HTTP-class

| Variant | Trigger |
|---|---|
| `Routing` |
| `Extraction` |
| `Validation` |
| `Middleware` |
| `DI` |
| `Serialization` |
| `OpenApiSchema` |
| `Unknown` |

## `replay_command` discipline

- Must be **exact** — copyable and pasteable, no `<placeholder>` tokens.
- Must include the seed where deterministic seeds matter: `cargo test … -- --exact bd_xyz_test_name --seed 0xD1A6A3F49B170C5E`.
- Must include feature flags when off-default: `cargo test … --features fsqlite_wal_durable_writes_v2`.
- Must include the binary entrypoint for non-`cargo test` failures: `cargo run --bin comprehensive_bench -- --workload mvcc --concurrency 8 --seed 0xDEAD`.

## `RemediationPlaybook.next_commands[]` discipline

- Each command is a single line, copy-paste-ready.
- Ordered by what's most likely to be needed first.
- Include both *inspection* commands (`xxd`, `less`, `samply view`) and *action* commands (`cargo expand`, `cargo run --bin minimizer`).
- For known root causes, include the hypothesis-template command: `echo "Hypothesis: ..." > beads/bd-xyz.md`.

## Composition

- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — the explainer reads `first_divergence_jsonptr` from the bundle.
- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — `artifact_id` is included in `ArtifactHashTable` as the content-address key.
- [pattern:45-MISMATCH-MINIMIZER](45-MISMATCH-MINIMIZER.md) — `replay_command` should reproduce the *minimized* divergence, not the original.
- [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) — preflight red emits an explainer (the `remediation_class` + `fix_command` map directly into the explainer's playbook).
- [pattern:195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md) — `run_id` keys the explainer to its run for cross-bundle correlation.

## Pitfalls

- **`first_divergence` rendered as "see bundle".** Defeats the purpose. The dereferenced value is what goes in the summary; "see bundle" is what the consumer was about to do anyway.
- **`replay_command` with `--release` instead of the release-perf profile.** Per the keep-gate rules; the replay must use the same profile as the failing build.
- **`owner_hint` set to "@team".** Useless; the hint should name a person or a beads filter that resolves to a person.
- **`next_commands[]` over 10 entries.** That's a playbook, not a checklist. Cap at 5; the 6th means the explainer is duplicating work that belongs in the bead body.
- **`ArtifactHashTable` includes timestamps.** Hashes are content addresses; timestamps belong in `run_id`. Keep the hash table pure SHA-256.
- **Explainer not emitted unless verbose.** The 5-line summary should be the *default* failure output; the bundle is the verbose detail. Reversed defaults hide signal.
- **Explainer JSON ≠ what's printed.** If CI prints a different 5-line summary than the explainer JSON contains, the two will drift. Print *from* the JSON.
- **Cargo-test-only replay command for a fault-injected failure.** A failure that requires `FAULT_SEED=…` and `WAL_FORMAT_VERSION=…` env vars must include them in the replay command.
- **Playbook stops at "investigate".** "Investigate" is not a next-command; "open the bundle in viewer X and check field Y" is. Be specific.
- **No `bead_id_of_fix` field after triage.** The explainer is mutable post-triage: when the bug is fixed, update the explainer to point at the closing bead, so future regressions cite the prior fix immediately.
