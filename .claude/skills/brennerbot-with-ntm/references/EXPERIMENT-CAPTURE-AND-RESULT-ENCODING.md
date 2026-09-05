# EXPERIMENT-CAPTURE-AND-RESULT-ENCODING.md — Run, Record, Encode, Post

<!-- TOC: Why structured experiment capture | The 4 CLI commands | The ExperimentResult schema | Capture mode (run vs record) | Encoding to artifact deltas | Posting via Agent Mail | Default output path | Threat model + non-goals | Per-phase experiment activity | Anti-patterns | Cross-references -->

A brennerbot session that runs computational experiments needs more than "we ran the test and it passed." It needs **auditable experiment capture** — a structured record of what was run, where, when, how long, what came out, and how that maps to artifact deltas.

This file specifies the experiment capture protocol (run/record), the result encoding (to artifact deltas), and the posting workflow (via Agent Mail).

Mined from `/dp/brenner_bot/specs/experiment_capture_protocol_v0.1.md` + `experiment_result_encoding_v0.1.md`.

---

## Why structured experiment capture

Three failures of ad-hoc experiment runs:

1. **"I forgot what I ran"** — argv, working directory, environment lost
2. **"I can't reproduce it"** — git provenance not recorded
3. **"It hung forever"** — no timeout enforcement; runaway processes

Three benefits of structured capture:

1. **Provenance per run** — argv + cwd + tool versions + git SHA recorded
2. **Reproducibility** — anyone can re-run the same command in the same state
3. **Bounded execution** — default 900s timeout (override with `--timeout`)

---

## The 4 CLI commands

```bash
# 1. Run a command and capture stdout/stderr + provenance
brenner experiment run --thread-id RS-... --test-id T-... --timeout 900 -- <command...>

# 2. Record results from an already-executed run (e.g., manual test)
brenner experiment record --thread-id RS-... --test-id T-... --exit-code N \
  --stdout-file <path> --stderr-file <path>

# 3. Encode captured results for artifact deltas
brenner experiment encode --result-file <path> --out-file <encoded-path>

# 4. Post encoded results to session participants via Agent Mail
brenner experiment post --result-file <encoded-path> \
  --sender <agent> --to <agent1,agent2,...> --project-key "$PWD"
```

The 4 commands form a pipeline:
```
run/record → encode → post
```

Each step is independent — you can run + manually compose deltas, or record from existing logs and re-encode.

---

## The ExperimentResult schema

```typescript
interface ExperimentResult {
  // IDs
  result_id: string;         // UUID
  thread_id: string;         // session
  test_id: string;           // T-NNN

  // Provenance
  capture_mode: "run" | "record";
  argv: string[];            // command + args
  cwd: string;               // working directory
  tool_versions?: Record<string, string>;  // bun, python, etc.
  git_provenance?: {
    sha: string;
    branch: string;
    is_dirty: boolean;
  };

  // Execution
  started_at: string;        // ISO
  ended_at: string;          // ISO
  duration_ms: number;
  exit_code: number;
  timed_out: boolean;
  timeout_seconds: number;

  // Output
  stdout: string;            // full stdout (or path reference for large)
  stderr: string;
  stdout_path?: string;      // for large outputs
  stderr_path?: string;

  // Schema versioning
  schema_version: "v0.1";
}
```

The schema is **strict** — no optional fields creep in to mask missing data. Per AGENTS.md no-deletion: once written, the result file is preserved.

---

## Capture mode (run vs record)

### `run` mode

The wrapper executes the command, captures output, enforces timeout:

```bash
brenner experiment run \
  --thread-id RS-20260301-cell-fate \
  --test-id T1 \
  --timeout 900 \
  --cwd /data/projects/elegans \
  -- python -m pytest -q tests/par_polarity_test.py
```

- `--timeout 900` enforces 15-min cap (default)
- `--cwd <path>` overrides working directory (default: current)
- After `--`: the command itself

The wrapper:
1. Records `started_at`, argv, cwd
2. Spawns the process
3. Captures stdout/stderr (in-memory or to file)
4. Enforces timeout (kills process if exceeded)
5. Records `exit_code`, `ended_at`, `duration_ms`, `timed_out`
6. Writes ExperimentResult JSON to `--out-file` (or default path)

CLI exit codes:
- `0`: wrapper successfully wrote the result JSON file (regardless of experiment outcome)
- non-zero: wrapper-itself error (invalid flags, spawn failure, write failure)

The experiment's outcome is in `exit_code` *inside* the JSON file. This decoupling means:
- Test runners that exit nonzero on test failures still produce a wrapper-success result
- Wrapper failures are distinguishable from experiment failures

### `record` mode

For experiments that already ran (manually, via CI, in a separate process):

```bash
brenner experiment record \
  --thread-id RS-... \
  --test-id T1 \
  --exit-code 0 \
  --stdout-file ./logs/T1.stdout.txt \
  --stderr-file ./logs/T1.stderr.txt \
  --command "python -m pytest -q"
```

- `--exit-code N` is required (the experiment's outcome)
- `--stdout-file` and/or `--stderr-file` for output (or `--stdout`/`--stderr` for inline)
- `--command` for best-effort provenance (optional in v0)

The wrapper writes a similar JSON record but with `capture_mode: "record"`.

---

## Encoding to artifact deltas

After capture, encode the result to a delta:

```bash
brenner experiment encode \
  --result-file results/experiment_T1.json \
  --out-file results/experiment_T1_encoded.json
```

The encoder:
1. Reads ExperimentResult JSON
2. Locates the test in artifact (matching `test_id`)
3. Generates an EDIT delta for the matched test
4. Sets `last_run` fields from ExperimentResult
5. Sets `status` based on exit_code:
   - `exit_code == 0` → "passed" (provisional)
   - `exit_code != 0` → "failed" or "error" (requires interpretation)
   - `timed_out` → "blocked"

Output delta:

```json
{
  "operation": "EDIT",
  "section": "discriminative_tests",
  "target_id": "T1",
  "payload": {
    "test_id": "T1",
    "last_run": {
      "result_id": "abc123-...",
      "result_path": "artifacts/RS-.../experiments/T1/20260301T140000Z_abc123.json",
      "run_at": "2026-03-01T14:00:00.000Z",
      "exit_code": 0,
      "timed_out": false,
      "duration_ms": 87000,
      "summary": "Test passed (n=15, p<0.001)"
    },
    "status": "passed"
  }
}
```

The encoder's job is mechanical: ExperimentResult → DELTA. It does NOT interpret what the result means for hypotheses — that's done via test-bind (per TEST-EXECUTION-AND-BINDING.md).

---

## Posting via Agent Mail

After encoding:

```bash
brenner experiment post \
  --result-file results/experiment_T1_encoded.json \
  --sender GreenCastle \
  --to BlueLake,PurpleMountain \
  --project-key "$PWD"
```

The post:
1. Wraps the encoded delta in a DELTA mail message (per MESSAGE-BODY-SCHEMA-PER-TYPE.md)
2. Subject: `DELTA[opus]: Test T1 result captured (passed)` (or similar)
3. Body: the delta block + summary prose
4. Sends via Agent Mail to specified recipients
5. Recipients can ack or respond via critique

The DELTA gets compiled into the artifact at next compilation round.

---

## Default output path

If `--out-file` is not specified:

```
artifacts/<thread_id>/experiments/<test_id>/<timestamp>_<short-uuid>.json
```

Example:
```
artifacts/RS-20260301-cell-fate/experiments/T1/20260301T140000Z_abc123.json
```

This is **co-located with the session artifact** + thread-id-scoped + per-test-id. The structure makes it trivial to:
- Find all experiments per session
- Find all runs per test
- Order chronologically by timestamp prefix

---

## Threat model + non-goals

Per `/dp/brenner_bot/specs/experiment_capture_protocol_v0.1.md`:

### What this protocol does

- Records argv + cwd + timestamps + tool versions
- Records git provenance when available
- Enforces default timeout (900s, override-able)
- Captures stdout/stderr with bounded size

### What this protocol does NOT do

- **Hard sandboxing / isolation** — running code is still risky
- **Automatic execution of agent-proposed code** — agents propose; operator authorizes
- **Automatic interpretation** — no auto-killing of hypotheses; that's via test-bind
- **Full lab notebook storage in canonical artifact** — large outputs go to result files

It DOES NOT protect against:
- Malicious code deleting files
- Secrets exfiltration over the network
- Resource exhaustion (RAM/disk) beyond best-effort timeouts

These are operator responsibilities. Per DESIGN-PRINCIPLES-CLI-FIRST.md Principle 3 (Fail-Closed Security): agents propose; operator authorizes; the wrapper records.

---

## Per-phase experiment activity

| Phase | Experiment activity |
|-------|---------------------|
| 4 investigation | Heavy: `experiment run` per discriminative test; encode + post |
| 5 cross-exam | (re-runs to address critiques) |
| 6 distillation | (no new experiments; aggregate prior results) |
| 7 audit | Verify ExperimentResult provenance for all tests |
| 8 freeze | All `last_run` fields populated; results files committed |

For T1-T2: lightweight (run via shell directly is OK).
For T3+: structured capture mandatory.
For T4+: full provenance + git_provenance + reproducibility tarball (per SESSION-REPLAY-AND-REPRODUCIBILITY.md).

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Run experiments via plain shell (no wrapper) | No provenance; replay impossible |
| Skip timeout for "long-running" tests | Default 900s catches runaway; override explicitly if needed |
| Use `record` when `run` is possible | `record` has weaker provenance (operator may misreport command) |
| Hand-edit ExperimentResult JSON | Per AGENTS.md: no script-based code changes; preserve original |
| Include large outputs inline | Use `stdout_path` + `stderr_path` for >100KB |
| Encode before run completes | Timed-out / unfinished runs encode incorrectly |
| Post without encoding | DELTA needs encoded form per delta_output_format spec |
| Skip the post step | Other panes don't see the result; artifact doesn't update |
| Reuse result_id across runs | UUIDs are unique; never reuse |

---

## Cross-references

- [TEST-EXECUTION-AND-BINDING.md](TEST-EXECUTION-AND-BINDING.md) — bind result to H |
- [DELTA-PROTOCOL-FAIL-FAST.md](DELTA-PROTOCOL-FAIL-FAST.md) — DELTA format
- [MESSAGE-BODY-SCHEMA-PER-TYPE.md](MESSAGE-BODY-SCHEMA-PER-TYPE.md) — DELTA mail body
- [SESSION-REPLAY-AND-REPRODUCIBILITY.md](SESSION-REPLAY-AND-REPRODUCIBILITY.md) — reproducibility tarball
- [DESIGN-PRINCIPLES-CLI-FIRST.md](DESIGN-PRINCIPLES-CLI-FIRST.md) — Principle 3 (fail-closed)
- [TAXONOMIES-COMPLETE-CATALOG.md](TAXONOMIES-COMPLETE-CATALOG.md) — test states
- /dp/brenner_bot/specs/experiment_capture_protocol_v0.1.md — capture spec
- /dp/brenner_bot/specs/experiment_result_encoding_v0.1.md — encoding spec
