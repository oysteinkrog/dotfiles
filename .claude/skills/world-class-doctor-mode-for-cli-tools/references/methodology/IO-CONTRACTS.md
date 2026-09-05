# IO Contracts — JSONL artifact schemas + script contracts

## JSONL artifacts (workspace)

### `cass_findings.jsonl`

```jsonc
{"quote":"...","kind":"MANUAL_FIX","source_path":"...","agent":"claude","created_at":"...","line_number":42,"query":"<tool> doctor"}
```

### `analysis/inventory_summary.md` (markdown, not JSONL)

One line per FM: `| {fm_id} | {severity} | {subsystem} | {auto_detected} | {auto_fixed} |`.

### `applied_changes.jsonl`

```jsonc
{"fm_id":"fm-...-X","commit_sha":"abcd","files_changed":["src/doctor/jsonl.rs"],"lines_added":120,"lines_removed":3,"applied_at":"2026-05-06T14:23:07Z","implementer":"agent-id"}
```

### `failure_mode_scores.jsonl`

```jsonc
{"fm_id":"fm-...-X","dimension":"data_safety","score":900,"frequency":1.8,"blast_radius":"corrupts_state","evidence_path":"src/doctor/jsonl.rs","evidence_line_or_test":"L42 mutate() call","run_id":"2026-05-06T14-23-07Z__a3f9b2"}
```

One row per (fm_id, dimension). Ten rows per FM, using the canonical dimensions
from `scripts/scorecard.py::DIMENSIONS`. Historical agent-ergonomics aliases
(`output_parseability`, `self_documentation`, etc.) are normalized by
`scorecard.py` for old workspaces but new rows should use canonical names.
`frequency` and `blast_radius` may be repeated on each row for that FM;
`scripts/scorecard.py render` clamps both to [0.5, 2.0] for the aggregate score.
If omitted, they default to 1.0.

### `recommendations.jsonl`

```jsonc
{"id":"R-001","title":"...","priority":7.20,"estimated_uplift":{"data_safety":+200,"observability":+50},"complexity":"M","applied":false,"diff_sketch":"..."}
```

### `safety_harness.jsonl`

```jsonc
{"fm_id":"fm-...-X","test":"reversibility","exit_code":0,"stderr_excerpt":"PASS","started_at":"...","duration_ms":312}
```

### `agent_simulations/post_pass_<N>/<task>.transcript.jsonl`

```jsonc
{"step":1,"command":"<tool> doctor --json","stdout":"{...}","stderr":"...","exit_code":1,"agent_assessment":"got findings; will try --fix next","stuck":false}
```

### `scorecard_history.jsonl` (in `<target>/.doctor/`)

```jsonc
{"run_id":"2026-05-06T14-23-07Z__a3f9b2","started_at":"...","tool_version":"...","doctor_version":"...","ok":true,"total_findings":0,"by_severity":{},"aggregate_score":927,"actions_taken":0,"duration_ms":412,"health_p95_ms":187,"panics_caught":0}
```

### `phases_timing.jsonl` (round-56)

Append-only per-phase / per-subagent timing record. Subagents and orchestrators emit a `start` line on dispatch and a `finish` line on completion. The `dashboard.py` script reads this to render phase progress.

```jsonc
{"schema_version":"1.0","phase":1,"subagent_name":"archaeologist","event":"start","started_at":"2026-05-07T14:23:00Z","started_at_ms":1746635480000,"agent_id":"a3f9b2","note":null}
{"schema_version":"1.0","phase":1,"subagent_name":"archaeologist","event":"finish","finished_at":"2026-05-07T14:25:30Z","duration_ms":150000,"agent_id":"a3f9b2","note":null}
```

Helper `scripts/log-phase-timing.sh` emits one record per call. Subagent prompts and the orchestrator SHOULD invoke it at start and end of each Phase segment. Missing records are non-fatal (dashboard renders "(pending)") but degrade visibility.

---

## Script contracts

Every `scripts/*.sh` and `scripts/*.py` script:

- **stdout**: data only (JSON or empty).
- **stderr**: human-readable progress and diagnostics.
- **Exit codes**: `0` success, `1` regression detected, `2` validation failure, `64` usage error, `66` no_input, `73` cant_create, `74` io_error.
- **`NO_COLOR` honored**.
- **No interactive prompts.**

| Script | stdout | stderr | Exit codes |
|--------|--------|--------|-----------|
| `check-skills.sh` | (empty) | progress + summary | 0, 1, 64 |
| `install-referenced-skills.sh` | (empty) | progress | 0, 64, 66 |
| `preflight-check.sh` | (empty) | tool inventory summary | 0, 1, 64, 73 |
| `discover-cli.sh` | JSON | progress | 0, 66 |
| `scaffold-workspace.sh` | JSON | progress | 0, 64, 66, 73 |
| `mine-changelog.py` | JSONL if no workspace | progress + output path | 0, 64, 66 |
| `cass-mine.sh` | (empty) | per-query hit counts + summary | 0, 1, 64 |
| `query-corpus.py` | JSONL | match summary | 0, 64, 66 |
| `build-corpus.py` | (empty) | corpus summary | 0, 64, 66 |
| `scaffold-doctor.sh` | JSON status | progress | 0, 64, 66, 73 |
| `scorecard.py render` | JSON summary | progress | 0, 2, 64 |
| `scorecard.py compare-against-baseline` | JSON | progress | 0, 1, 64 |
| `scorecard.py append-history` | (empty) | progress | 0, 74, 64 |
| `scorecard.py validate` | (empty) | progress | 0, 2, 64 |
| `run-safety-harness.sh` | (empty) | PASS/FAIL summary | 0, 1, 64 |
| `verify-undo.sh` | (empty) | PASS/FAIL line | 0, 1, 64 |
| `verify-idempotence.sh` | (empty) | PASS/FAIL line | 0, 1, 64 |
| `verify-crash-recovery.sh` | (empty) | PASS/FAIL line | 0, 1, 64 |
| `verify-concurrency.sh` | (empty) | PASS/FAIL line | 0, 1, 64 |
| `verify-capabilities.sh` | (empty) | PASS/FAIL line | 0, 1, 64 |
| `verify-metamorphic.sh` | (empty) | PASS/FAIL line | 0, 1, 64 |
| `verify-cross-fm.sh` | (empty) | PASS/FAIL line | 0, 1, 64, 66 |
| `conformance-harness.sh` | (empty) | report path + PASS/FAIL | 0, 1, 64, 66 |
| `validate-doctor.sh` | (empty) | violations or "clean" | 0, 1 |
| `validate-fm.py` | (empty) | violations or "OK" | 0, 2, 64 |
| `validate-spec.py` | (empty) | violations or "OK" | 0, 2, 64 |
| `validate-dag.py` | (empty) | "OK" or "CYCLE: ..." | 0, 2, 64 |
| `validate-skill.sh` | (empty) | "OK" or violation list | 0, 1 |
| `diff-scorecards.py` | (empty) | progress + path of artifacts | 0, 1, 64 |
| `compute-fm-id.py` | the slug | (empty) | 0, 64 |
| `manifest-update.sh` | JSON status | "manifest updated" | 0, 5, 64, 66 |
| `beads-from-fms.sh` | (empty) | create/skip summary | 0, 1, 64, 66 |
| `bv-prioritize.py` | (empty) | output summary | 0, 64, 66 |
| `emit-agents-md-section.sh` | Markdown | validation errors | 0, 64, 66 |
| `coverage-gap.py` | Markdown if no `--out` | report path or validation errors | 0, 64, 66 |
| `corpus-grow-suggest.py` | Markdown if no `--out` | report path or validation errors | 0, 64, 66 |
| `dashboard.py` | ASCII dashboard | usage/workspace errors | 0, 64, 66 |
| `single-fm-rescore.sh` | (empty) | rescore summary | 0, 1, 64, 66 |
| `snapshot-capabilities.sh` | (empty) | snapshot status or diff | 0, 1, 2, 64, 66 |
| `log-phase-timing.sh` | (empty) | usage errors only | 0, 64 |
| `migrate-contract.sh` | dry-run/action log | migration summary | 0, 1, 64, 66 |
| `self-apply.sh` | (empty) | meta-check summary | 0, 1, 64 |

> **Baseline snapshotting** (upgrade mode) is performed by [`subagents/baseline-snapshotter.md`](../../subagents/baseline-snapshotter.md), not a standalone script. **Per-FM fixture corrupters** are authored from [`assets/fixture-template.sh`](../../assets/fixture-template.sh) into `tests/doctor_fixtures/<fm-id>/corrupt.sh`. **Scorecard validation** lives at `scorecard.py validate <workspace>` (subcommand of `scorecard.py`).

Scripts are designed to be rerunnable. Scripts that intentionally mutate a
workspace or snapshot (`migrate-contract.sh`, `snapshot-capabilities.sh`,
`single-fm-rescore.sh`, `log-phase-timing.sh`) document first-run/update
semantics in their own headers.
