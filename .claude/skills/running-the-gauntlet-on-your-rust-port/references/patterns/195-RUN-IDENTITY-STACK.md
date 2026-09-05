# pattern:195-RUN-IDENTITY-STACK

## What

Every artifact emitted by the gauntlet — log line, JSON report, scorecard, failure bundle, bead, commit, ledger entry — embeds a full **run identity stack** that joins it to every other artifact from the same run. The stack is:

```
run_id + trace_id + scenario_id + seed + commit_sha + fixture_hash
       + backend/mode + placement_profile + artifact_path + artifact_hash
       + replay_command
```

These eleven fields together make any artifact from any phase findable, reproducible, and joinable across logs / JSON / scorecards / bundles / beads / commits / ledger. The stack is what turns "we ran the gauntlet" into "we ran the gauntlet on commit `abc123` against fixture-hash `def456` with placement profile `recommended_pinned` and here is the exact `cargo` invocation that reproduces the bundle whose SHA is `789ghi`."

## Why

> "Logs as API: Not free text for humans; machine-consumable trace future agents parse to compute coverage and bisect regressions." — MINING-2 §16

> "Required event fields: run_id = {bead_id}-{timestamp}-{pid}, timestamp ISO 8601 UTC, phase, event_type. Replayability keys: scenario_id, seed, phase, context.invariant_ids, context.artifact_paths." — MINING-3 §14

Failure mode prevented: *the bundle that cannot be replayed*. Without a run-identity stack, a failure observed on Monday cannot be matched to the scorecard from the same Monday run, cannot be matched to the commit that produced the binary, cannot be re-executed without guessing the seed. The stack is the join key that makes evidence aggregable; without it, every artifact is an island.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/e2e_log_schema.rs` — `REQUIRED_EVENT_FIELDS` + `REPLAYABILITY_KEYS`
- `crates/fsqlite-harness/src/differential_v2.rs` — `artifact_id = SHA-256(canonical JSON \ run_id)`
- `crates/fsqlite-harness/src/failure_bundle.rs` — `seed`, `fixture_id`, `schedule_fingerprint`, `git_sha`, `toolchain_version`, `platform`, `feature_flags`
- `crates/fsqlite-harness/src/oracle_preflight_doctor.rs` — `run_id, trace_id, scenario_id, seed`
- The 16-phase pipeline's per-phase output filenames embed `<run_id>` so every file is grep-joinable

## Verbatim shape

The 11-field stack:

```
run_id            = {bead_id}-{ISO8601-UTC-timestamp}-{pid}    # provenance: who ran what when
trace_id          = OpenTelemetry-style 16-byte hex             # joins all spans in the run
scenario_id       = stable string per workload/test             # joins across reruns of the same scenario
seed              = u64                                         # reproduces RNG-driven decisions
commit_sha        = git commit (full 40-char SHA)               # reproduces the binary
fixture_hash      = SHA-256 of fixture root manifest            # reproduces the inputs
backend/mode      = e.g., wal | rollback | bdb                  # reproduces engine config
placement_profile = baseline_unpinned | recommended_pinned
                  | adversarial_cross_node                       # reproduces host topology
artifact_path     = filesystem location of the emitted artifact # links log -> file
artifact_hash     = SHA-256 of the artifact's canonical form    # content-addressable identity
replay_command    = one-line invocation that reproduces         # the leaf reproducer
```

The crucial split (from K-11): `artifact_id = SHA-256(canonical JSON excluding run_id)`. Two runs of the same test produce the same `artifact_id` (content-address) but different `run_id` (provenance).

## Joinability matrix

Every gauntlet artifact carries enough of the stack to join to every other:

| Artifact | Carries fields |
|---|---|
| Log line | `run_id, trace_id, scenario_id, seed, phase, event_type, timestamp, context.artifact_paths` |
| JSON report (v3) | `run_id, scenario_id, seed, commit_sha, fixture_hash, backend/mode, placement_profile, schema_version` |
| Scorecard | `run_id, fixture_hash, commit_sha, scorecards.json.sha256, replay_command` |
| Failure bundle | `seed, fixture_id, schedule_fingerprint, git_sha, toolchain_version, platform, feature_flags, /failure/first_divergence` |
| Bead | `bead_id, links: [run_id, artifact_path, artifact_hash]` |
| Git commit | trailer includes `Run-Id: ...`, `Artifact-Hash: ...`, optional `Closes-Bead: bd-...` |
| Ledger entry | `bead_id, scratch_worktree (= run_id-named dir), commit, profile_evidence_path, replay_command` |

A query of the form "find the failure bundle whose `seed` matches the ledger entry's `replay_command`" is a single `jq` over the workspace; this is what makes the ledger *operational*, not just historical.

## Per-class instantiation

| Class | `backend/mode` set | `placement_profile` set | `replay_command` shape |
|---|---|---|---|
| SQL | `{wal, rollback, mvcc-concurrent}` | `{baseline_unpinned, recommended_pinned, adversarial_cross_node}` | `cargo test -p fsqlite-e2e --test <name> -- --exact <scenario>` |
| RESP | `{persistence-none, aof, rdb, aof+rdb, cluster}` | `{single-host, cluster-3node, cluster-6node}` | `cargo test -p frankenredis-e2e --test <name> -- --exact <scenario> --resp-version 3` |
| Numerical-Python | `{cpu-blas-openblas, cpu-blas-mkl, gpu-cuda}` | `{baseline_unpinned, omp-pinned-8}` | `cargo test -p franken_numpy-e2e --test <name> --features pyo3 -- --exact <scenario>` |
| ML-System | `{cpu, cuda, mps, distributed-2rank, distributed-8rank}` | `{single-gpu, single-node-8gpu, 2node-8gpu}` | `cargo test -p frankentorch-e2e --test <name> -- --exact <scenario> --deterministic` |
| HTTP-Protocol | `{single-process, multi-worker, fastapi-uvicorn-oracle}` | `{loopback, same-host-cross-process, cross-node}` | `cargo test -p fastapi_rust-e2e --test <name> -- --exact <scenario>` |

## Composition

- Pairs with [pattern:100-E2E-LOG-SCHEMA](100-E2E-LOG-SCHEMA.md) — the schema's `REQUIRED_EVENT_FIELDS` and `REPLAYABILITY_KEYS` are the log-line projection of the stack.
- Pairs with [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — `artifact_id` (canonical hash minus run_id) is the content-address half; `run_id` is the provenance half.
- Pairs with [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — the bundle is the leaf-reproducer; it carries the largest subset of the stack.
- Pairs with [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — `.bench-history/*.latest.json` is keyed by `commit_sha`, joined to scorecards by `run_id`.
- Pairs with [pattern:180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) — every ledger entry's scratch-worktree path embeds the `run_id`.

## Pitfalls

- **`run_id` reused across phases.** Each phase's outputs should carry the same `run_id` (so they join) but each *invocation* generates a fresh one. Using the same `run_id` across two distinct campaigns destroys the join key.
- **`artifact_id` collapsed into `run_id`.** Then two runs of the same test produce different artifact ids and the regression detector breaks. K-11 is explicit: hash excludes `run_id`.
- **`replay_command` left as "see the docs".** A leaf-reproducer is one line. If the docs say "to reproduce, run cargo with these flags and then…" the agent has failed; the field must be cut-and-paste.
- **`fixture_hash` referencing a directory but not the manifest.** The manifest's SHA is the join key; the directory mtime is not. Without the manifest hash, "same fixtures" cannot be proved across machines.
- **`placement_profile` defaulting silently to `baseline_unpinned`.** Same-minute benches on different placement profiles produce different ratios; the field must be explicit.
- **`backend/mode` missing on FrankenRedis/FrankenTorch artifacts.** The per-class mode space is wider than SQL; an artifact without the mode is unreplayable.
- **Filename without `<run_id>`.** A file named `bench_2026-05-20.json` collides with itself across two same-day runs; the file must be `bench_<run_id>.json` so it's globally unique.
