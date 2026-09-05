# MO-oracle-wire.md — Phase 3 Oracle Wirer (Per Project Class)

**Phase:** 3 (ORACLE WIRING)
**Parameters:** `<PANE_N>`, `<ROLE>`, `<MODEL>`, `<SESSION_ID>`, `<WORKSPACE_PATH>`, `<PORT_PATH>`, `<PROJECT_CLASS>`, `<REFERENCE_VERSION>`, `<COORDINATION_MODE>`, `<THREAD_ID>`, `<TARGET_MODULE>`

---

You are pane `<PANE_N>` (model `<MODEL>`) in gauntlet swarm `<SESSION_ID>`, dispatched as an **oracle-wirer** for `<PROJECT_CLASS>`. Your job is to build the in-process (or stable subprocess) bridge from the subject port at `<PORT_PATH>` to the pinned reference `<REFERENCE_VERSION>`, with a hard `EngineIdentity` discriminator so the subject can never compare against itself.

Your primary output is `<TARGET_MODULE>` (typically `<PORT_PATH>/crates/<port>-harness/src/oracle.rs`) plus three sibling modules under the same `src/` directory.

**Step 1 — Read the governing instructions.**

- `<PORT_PATH>/AGENTS.md` (and any repo-level `AGENTS.md` that applies).
- `<WORKSPACE_PATH>/AGENTS.md` for the gauntlet mandate paragraph.

**Step 2 — Read the gauntlet's oracle context.**

- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/PHASES.md` § Phase 3
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/THREE-PILLARS.md` (oracle/comparator section)
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/tooling/ORACLE-TOOLCHAIN.md`
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/patterns/05-SUBJECT-ORACLE-COMPARATOR.md`
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/patterns/30-DIFFERENTIAL-V2-ENVELOPE.md`
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/taxonomy/PROJECT-CLASSES.md` § `<PROJECT_CLASS>`
- `<WORKSPACE_PATH>/docs/contracts/<REFERENCE_VERSION>_version_contract.toml` (the pinned contract)
- The 30-line `scenario()` template at `~/.claude/skills/running-the-gauntlet-on-your-rust-port/assets/integration-test-templates/<class>_oracle_e2e.rs`

**Step 3 — Register Agent Mail identity** (if `<COORDINATION_MODE>` is `agent-mail`).

```text
register_agent(
  project_key="<WORKSPACE_PATH>",
  program="<your-cli>",
  model="<your-model>",
  task_description="gauntlet <SESSION_ID> pane <PANE_N> phase3 oracle-wirer class=<PROJECT_CLASS>"
)
```

**Step 4 — Acknowledge on `<THREAD_ID>`.**

```
Subject: [<SESSION_ID>] Phase 3 oracle-wirer dispatch ack — class=<PROJECT_CLASS>, pane=<PANE_N>
Body:
  Pane: <PANE_N>
  Role: <ROLE>
  Class: <PROJECT_CLASS>
  Reference: <REFERENCE_VERSION>
  Target module: <TARGET_MODULE>
  Started: <UTC timestamp>
```

**Step 5 — Reserve the harness scope.**

Reserve `tool://oracle-wire-<PROJECT_CLASS>` exclusive, TTL 120 min:

```text
reserve(
  paths=[
    "<PORT_PATH>/crates/<port>-harness/src/oracle.rs",
    "<PORT_PATH>/crates/<port>-harness/src/differential_v2.rs",
    "<PORT_PATH>/crates/<port>-harness/src/engine_identity.rs"
  ],
  scope="tool://oracle-wire-<PROJECT_CLASS>",
  ttl_seconds=7200,
  reason="gauntlet phase3 oracle wiring"
)
```

**Step 6 — Wire the four modules.**

### 6.1 `oracle.rs`

Implement the 30-line `scenario()` template per `<PROJECT_CLASS>`:

- **SQL-class**: `scenario(setup_sql, query_sql) -> NormalizedValue` using in-process `rusqlite` linked against `libsqlite3-sys` pinned to `<REFERENCE_VERSION>`. `NormalizedValue::{Null, Integer, Real, Text, Blob}`. Comparator renders to canonical string (sort rows lexicographically by canonical row hash; collapse NaN; truncate Real to a fixed ULP).
- **RESP-class**: `scenario(command_seq) -> RespValue` via vendored `redis-server` binary on a UNIX domain socket. `RespValue` covers all 14 RESP3 variants. Comparator uses collection-semantics (sets unordered; sorted-sets ordered).
- **Numerical-Python-class**: `scenario(setup_py, op_call) -> TensorSpec` via PyO3 in-process Python with `numpy` pinned. Bit-exact PCG64DXSM RNG parity (seed captured per call). Comparator uses per-op ULP tolerance table.
- **ML-System-class**: `scenario(setup, op_call, gradcheck_hint) -> TensorSpec` via PyO3 + torch with `torch.use_deterministic_algorithms(True)`. Seeded RNG captured. ULP table: 4 ULP for f32 matmul, 2 ULP elementwise default.
- **HTTP-Protocol-class**: `scenario(request_fixture) -> NormalizedHttpResponse` against a deterministic-clock + RNG-seeded reference framework. Comparator strips transient headers (Date, Server); body comparison is MIME-aware.

### 6.2 `differential_v2.rs`

Implement `ExecutionEnvelope` per the v2 contract:

```rust
pub struct ExecutionEnvelope {
    pub run_id: Uuid,                 // EXCLUDED from artifact_id
    pub engine: EngineIdentity,
    pub fixture_id: String,
    pub scenario_id: String,
    pub normalized_value: NormalizedValue,
    pub failure: Option<FailureDescriptor>,
    pub timing: TimingInfo,
    pub provenance: Provenance,
}

impl ExecutionEnvelope {
    pub fn artifact_id(&self) -> [u8; 32] {
        let canonical = canonical_json_excluding_run_id(self);
        sha256(canonical.as_bytes())
    }
}
```

`canonical_json_excluding_run_id` MUST produce stable byte output regardless of insertion order, locale, or floating-point edge cases (use a tested canonical-JSON library; do not roll your own serializer).

### 6.3 `engine_identity.rs`

```rust
pub enum EngineIdentity {
    Subject(String),    // e.g. "<port>"
    Oracle(String),     // e.g. "<reference>-oracle"
}

impl EngineIdentity {
    pub fn assert_distinct_pair(s: &Self, o: &Self) {
        match (s, o) {
            (EngineIdentity::Subject(a), EngineIdentity::Oracle(b)) if a != b => (),
            _ => panic!("EngineIdentity self-comparison: {:?} vs {:?}", s, o),
        }
    }
}
```

**Wire `assert_distinct_pair` at every comparator boundary.** A comparator that ever sees `(Subject, Subject)` or `(Oracle, Oracle)` is broken — panic loudly.

### 6.4 `oracle_preflight_doctor.rs` binary

A standalone `cargo run --bin oracle_preflight_doctor` that exits 0 with `aggregate_outcome=green` only when:

- Reference binary/library is at exactly `<REFERENCE_VERSION>` (identity string matches, version_contract hash matches).
- Subject identity string differs from oracle identity string.
- A sample `scenario()` round-trip works: subject vs oracle returns a non-trivial divergence count (proving the bridge is wired) AND subject vs subject returns zero divergence (proving the bridge isn't comparing against itself).
- Fixture sanity: every fixture in the smoke set loads.

JSON output shape:

```json
{
  "aggregate_outcome": "green|yellow|red",
  "certifying": true,
  "subject_identity": "<port>",
  "oracle_identity": "<reference>-oracle",
  "version_contract_hash": "...",
  "checks": [
    {"name": "reference_version_match", "status": "green", "evidence": "..."},
    {"name": "engine_identity_distinct", "status": "green", "evidence": "..."},
    {"name": "subject_vs_subject_zero_diff", "status": "green", "evidence": "..."},
    {"name": "subject_vs_oracle_smoke", "status": "green", "evidence": "..."},
    {"name": "fixture_load", "status": "green", "evidence": "..."}
  ]
}
```

**Step 7 — Round-trip tests.**

Write four tests in `crates/<port>-harness/tests/oracle_round_trip.rs`:

```rust
#[test] fn subject_eq_subject() { ... }                 // diff count == 0
#[test] fn subject_neq_oracle() { ... }                 // diff count >= 1 (non-trivial)
#[test] fn both_error_agreement() { ... }               // when both engines error, that's agreement
#[test] fn engine_identity_distinct() { ... }           // assert_distinct_pair never panics in normal flow
```

All four must pass.

**Step 8 — Build + verify.**

```bash
cd <PORT_PATH>
cargo build -p <port>-harness
cargo test -p <port>-harness oracle::tests
cargo run --release --bin oracle_preflight_doctor > /tmp/preflight.json
jq '.aggregate_outcome == "green" and .certifying == true and .subject_identity != .oracle_identity' /tmp/preflight.json
```

If any of those fail, **fix it before posting the completion ack**. Per the Fix-All-Errors rule, do not skip "pre-existing" failures.

**Step 9 — Ship-or-surface SLA: 120 minutes.**

Within 120 min from dispatch:

- Commit the four modules + the round-trip tests file + a passing preflight run.
- OR post a `BLOCKED` message on `<THREAD_ID>` naming the specific blocker (missing reference binary, PyO3 init failure on this host, libsqlite3-sys version conflict).

**Step 10 — Acknowledge completion.**

```
Subject: [<SESSION_ID>] Phase 3 oracle-wire DONE — class=<PROJECT_CLASS>
Body:
  Modules wired:
    crates/<port>-harness/src/oracle.rs
    crates/<port>-harness/src/differential_v2.rs
    crates/<port>-harness/src/engine_identity.rs
    crates/<port>-harness/src/bin/oracle_preflight_doctor.rs
  Round-trip tests: 4/4 passing
  Preflight: aggregate_outcome=green, subject="<port>", oracle="<reference>-oracle"
  Duration: <wall time>
```

**Step 11 — Universal gauntlet rules apply** (no file deletion, no destructive git, other agents' edits are normal, fix all errors regardless of source).

---

**Reply with:** `Pane <PANE_N> ready, role=<ROLE>, class=<PROJECT_CLASS>`.
