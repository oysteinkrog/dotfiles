# Canonical Doctor Exemplars

This file is the source of truth for "what good looks like." Every quote is mined from a real `/dp` project under user ownership and includes a citation. Phase 4 implementers should read this before writing any code; Phase 7 fresh-eyes should compare every applied change against the exemplars.

Counter-examples (real CLIs that fail one or more Polish Bar items) live in [COUNTER-EXAMPLES.md](COUNTER-EXAMPLES.md). CASS-mined surprising patterns live in [CASS-FINDINGS.md](CASS-FINDINGS.md).

---

## Exemplar 1 — `xf doctor` (Rust + clap + serde)

**File:** `/dp/xf/src/doctor.rs`

What it gets right:

- **Typed `CheckCategory`, `CheckStatus`, `HealthCheck` records** with `#[serde(rename_all = "snake_case")]` — JSON output is deterministic and tagged.
- **Explicit `suggestion: Option<String>`** on every `HealthCheck` — every finding can carry a remediation hint.
- **Categories partition the surface**: `Archive`, `Database`, `Index`, `Performance`. Each subsystem has its own module so detectors stay narrow.
- **`is_ok()` on `CheckStatus`** so callers don't have to pattern-match.

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CheckStatus { Pass, Warning, Error }

#[derive(Debug, Clone, Serialize)]
pub struct HealthCheck {
    pub category: CheckCategory,
    pub name: String,
    pub status: CheckStatus,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub suggestion: Option<String>,
}
```

What we'd add (the upgrade target):

- No `--fix` — `xf doctor` is read-only.
- No `--robot-triage` mega-command.
- No `mutate()` chokepoint (because no fix path).
- No backups, no run-id, no `.doctor/runs/`.
- No `capabilities --json`.

Lift: **add the fixer half of the contract**, route everything through `mutate()`, emit run artifacts, score against the rubric. The detector half is already strong.

---

## Exemplar 2 — `br doctor` (Rust; the most mature implementation in `/dp`)

**File:** `/dp/beads_rust_c49_72yf27/src/cli/commands/doctor.rs`

What it gets right:

- **Distinct `DoctorReport`, `DoctorRun`, `DoctorRepairResult`, `LocalRepairResult`, `RecoveryAuditRecord` types** — every artifact is its own typed shape with `#[serde(skip_serializing_if = "Option::is_none")]` and `#[serde(rename_all = "lowercase")]`.
- **Distinguishes findings from repair actions** — `findings: Vec<String>` vs. `applied_actions: Vec<String>` vs. `quarantined_artifacts: Vec<String>`. The contract is precise about what changed vs. what was observed.
- **Quarantine-instead-of-delete** semantics — `quarantined_artifacts` lists files moved aside (NOT deleted) when their integrity can't be verified. This is the AGENTS.md no-delete pattern in code.
- **`PriorJsonlRebuildFailureEvidence`** type — the doctor remembers prior failed rebuilds and refuses to re-attempt without explicit acknowledgment. State doesn't get worse on repeat invocation.
- **Workspace classification anomaly tracking** — `WorkspaceClassification`, `AnomalyClass`, `ReliabilityAuditRecord` allow fine-grained "this workspace is in state X; we will perform Y; here's what we backed up".
- **Hard-coded sentinel error prefixes** for known unsafe states (`JSONL_REBUILD_AUTHORITY_ERROR_PREFIX`, `JSONL_REBUILD_REPEAT_ERROR_PREFIX`) — agents can pattern-match on the prefix.

```rust
#[derive(Debug, Clone, Serialize)]
struct RecoveryAuditRecord {
    phase: String,
    action: String,
    outcome: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    reason: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    applied_actions: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    quarantined_artifacts: Vec<String>,
    ...
}
```

What we'd lift to "world-class":

- **Add `mutate()` chokepoint** — currently each repair function does its own writes; we want one chokepoint per the rubric.
- **Add per-run artifact directory** (`.doctor/runs/<id>/`) — currently the `RecoveryAuditRecord` is in stdout JSON only.
- **Add `doctor undo <run-id>`** — currently no inverse pair.
- **Add `doctor capabilities --json`** to declare the contract.

Lift: **wrap the existing repair functions in a `mutate()` chokepoint** + **emit per-run backups + actions.jsonl** + **add the agent-ergonomic surface (capabilities, robot-docs, --robot-triage)**.

---

## Exemplar 3 — `caam doctor` (Go + cobra)

**File:** `/dp/coding_agent_account_manager/cmd/caam/cmd/doctor.go`

What it gets right:

- **Status taxonomy `pass | warn | fail | fixed`** — `fixed` is a first-class outcome distinct from `pass`. After a fix run, `fixed` items get rolled into `PassCount` for the OK calculation but counted separately for reporting.
- **`DependencySpec` declarative struct** — each external dependency is described declaratively: name, binaries, install hints per OS, custom check function. This is reflective: `caam doctor` can describe its own dependency tree to an agent.
- **`--auto` + `--yes` two-step gate** — auto-install missing deps requires both flags, never just one. The default is "ask first."
- **`--validate` is opt-in** — token validation hits APIs and is gated; the cheap path runs offline.

```go
type CheckResult struct {
    Name    string `json:"name"`
    Status  string `json:"status"` // "pass", "warn", "fail", "fixed"
    Message string `json:"message"`
    Details string `json:"details,omitempty"`
}

type DoctorReport struct {
    Timestamp       string        `json:"timestamp"`
    OverallOK       bool          `json:"overall_ok"`
    PassCount       int           `json:"pass_count"`
    WarnCount       int           `json:"warn_count"`
    FailCount       int           `json:"fail_count"`
    FixedCount      int           `json:"fixed_count"`
    CLITools        []CheckResult `json:"cli_tools"`
    Dependencies    []CheckResult `json:"dependencies"`
    Directories     []CheckResult `json:"directories"`
    Config          []CheckResult `json:"config"`
    Profiles        []CheckResult `json:"profiles"`
    Locks           []CheckResult `json:"locks"`
    AuthFiles       []CheckResult `json:"auth_files"`
    TokenValidation []CheckResult `json:"token_validation,omitempty"`
}
```

What we'd add:

- **No `mutate()` chokepoint** — `--fix` writes inside each `checkDirectories`/`checkLocks` function. Centralize.
- **No backups before mutation** — the `--fix` path creates dirs and removes stale locks without recording a backup.
- **No `doctor undo`.**
- **No per-run artifacts.**
- **No `schema_version`.**

Lift: **same as `xf doctor` and `br doctor` — wrap in `mutate()` + emit run artifacts + add reversibility.**

---

## Exemplar 4 — `caam robot` (Go; the gold standard for agent-ergonomic surface)

**File:** `/dp/coding_agent_account_manager/cmd/caam/cmd/robot.go`

What it gets right (every word of this is paste-ready for the doctor's `--robot` mode):

```go
// RobotOutput is the standard response wrapper for all robot commands.
type RobotOutput struct {
    Success     bool        `json:"success"`
    Command     string      `json:"command"`
    Timestamp   string      `json:"timestamp"`
    Data        interface{} `json:"data,omitempty"`
    Error       *RobotError `json:"error,omitempty"`
    Suggestions []string    `json:"suggestions,omitempty"`
    Timing      *RobotTiming `json:"timing,omitempty"`
}

type RobotError struct {
    Code    string `json:"code"`
    Message string `json:"message"`
    Details string `json:"details,omitempty"`
}

type RobotTiming struct {
    StartedAt  string `json:"started_at"`
    DurationMs int64  `json:"duration_ms"`
}
```

- **Standard wrapper** — every robot command returns the same envelope. An agent can pattern-match generically.
- **`Suggestions` array of paste-ready commands** — when the result is `Success: false`, the agent has next-step commands without asking.
- **`Timing` block** — agents can budget cost.
- **Subcommands**: `robot status`, `robot next`, `robot act`, `robot health`, `robot watch` (NDJSON stream), `robot limits`. The `watch` subcommand is particularly strong — it's the streaming variant of `health`.
- **Header comment block** that names the design principles in-source: "JSON output by default", "no interactive prompts", "structured errors with error_code", "actionable suggestions in output", "exit codes 0=success, 1=error, 2=partial success."

Lift: **adopt this envelope verbatim** for the doctor's `--robot` mode. Every doctor subcommand wraps its data in `RobotOutput`. `Suggestions` is the doctor's `next_steps` field renamed; `Timing` is mandatory.

---

## Exemplar 5 — `cm doctor` (Bun/TS; from the cass-mined session)

**Source:** CASS finding (gemini session 2025-12-07T23-37) — `cm` is a "cass memory system" that exposes V1 commands `context | mark | playbook | stats | doctor | reflect`.

What it gets right (per the session quote):

- **`cm doctor` "diagnoses system state"** — listed alongside `init`, `stats`, `playbook`. It's a first-class verb in the V1 command set.
- **Cleanly separated subsystems**: storage, dependencies, config. Each gets its own diagnostic.
- **Identifies environment problems** ("missing API keys") with named remediation.

What we'd add:

- We don't yet have evidence the `cm doctor` has `--fix` or `--robot-triage` or `mutate()`. Treat as a name-and-shape exemplar rather than a behavior exemplar.

---

## Exemplar 6 — `cass health` (Rust; the cheap-liveness pattern)

**Surface:** `cass health` returns a one-line liveness summary with structured exit code. AGENTS.md cites it as the pattern. From AGENTS.md § cass:

```bash
cass health
cass search "pattern matching" --robot --limit 5
cass capabilities --json
cass robot-docs guide
```

What it gets right:

- **`cass health` is cheap** (< 200 ms). Used for CI scheduling.
- **`cass capabilities --json`** declares the contract.
- **`cass robot-docs guide`** prints a paste-ready handbook.
- **Strict stdout/stderr split**: "stdout is data-only, stderr is diagnostics; exit code 0 means success."
- **Exit-code dictionary** referenced from `cass capabilities --json`.

Lift: **adopt the four-verb shape `<tool> doctor health | capabilities --json | robot-docs | --robot-triage` verbatim.** This is the agent's discovery API.

---

## Exemplar 7 — `dcg explain` (Rust; the typo-redirect pattern)

**Surface:** `dcg` blocks destructive commands. When it blocks, it emits a structured error naming the safe alternative. From AGENTS.md § dcg:

> "Sub-millisecond execution for typical commands"
> "Pattern System: 34 safe patterns (whitelist), 16 destructive patterns (blacklist), default allow"

What it gets right (for our purposes):

- **Block-with-redirect pattern**: when the agent issues `git reset --hard`, dcg returns a structured error naming `git revert <sha>` (or `git stash`) as the safer alternative. The error doesn't just say "blocked" — it says **what to use instead**.
- **`dcg --json` returns a structured response with `decision`, `pattern_id`, `reason`, `suggestion`** — every field an agent needs to act, no prose to grep.

Lift: **the doctor's exit-4 unsafe-refused path adopts the same shape**: `{decision: "refused", reason: "schema_version_unknown", observed_version: "3", supported_versions: ["1","2"], alternative_command: "upgrade <tool> or run the documented migration first"}`. Errors teach. Lock-held refusals use exit 5, not exit 4.

---

## Exemplar 8 — `mcp_agent_mail` `health_check` and file reservations

**Project:** `/dp/mcp_agent_mail_rust/`

What it gets right:

- **`health_check` MCP tool** — expensive checks gated; cheap path always available.
- **File reservations as advisory locks** — `file_reservation_paths(project_key, agent_name, ["src/**"], ttl_seconds=3600, exclusive=true)` is the same primitive doctor needs to acquire before mutating shared files.
- **Pre-commit guard install/uninstall idempotence** — `install_precommit_guard` is callable any number of times. Re-install is a no-op. Same model the doctor's `integration-wirer` should follow in Phase 8.
- **`force_release_file_reservation`** — explicit override path for the case where a reservation outlived its holder. The doctor should expose `--force` only after this same explicit acknowledgment.

Lift: **acquire `file_reservation_paths` for shared files in Phase 4** (mutate(), help text, capabilities schema, run-artifact emitter); **make `<tool> doctor` itself idempotent on install (Phase 8 wiring)**.

---

## Cross-cutting lifts

After studying all eight exemplars, the consolidated lift is:

1. **Type-driven JSON with `#[serde(rename_all = "snake_case")]`** + `skip_serializing_if`. (xf, br)
2. **Status taxonomy with `fixed` as a first-class outcome.** (caam)
3. **Quarantine-instead-of-delete.** (br)
4. **Per-FM declarative spec** like `caam`'s `DependencySpec` — let the doctor describe its own contract reflectively. (caam)
5. **Standard `RobotOutput` envelope with `Suggestions` and `Timing`.** (caam)
6. **Cheap-liveness `health` + reflective `capabilities --json` + paste-ready `robot-docs`.** (cass, caam)
7. **Block-with-redirect error shape.** (dcg)
8. **Advisory-lock acquisition before mutation; idempotent install.** (mcp_agent_mail)

What all eight are missing, and what this skill's `mutate()` chokepoint adds:

- **A single chokepoint for every disk write.**
- **Verbatim per-run backups under `.doctor/runs/<id>/backups/`.**
- **`actions.jsonl` recording every mutation with before/after SHA-256.**
- **`<tool> doctor undo <run-id>`** as a true byte-identical inverse.
- **A scorecard rubric pinned to fixtures + tests.**
