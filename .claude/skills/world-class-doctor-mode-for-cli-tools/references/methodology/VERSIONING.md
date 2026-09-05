# Versioning — Schema, Contract, and Run-Artifact Compatibility

The doctor publishes three orthogonal version numbers, and each evolves under different rules.

| Version | Where it lives | Semver discipline |
|---------|----------------|-------------------|
| `tool_version` | `capabilities --json::tool_version` | Project's existing semver; not the doctor's concern |
| `doctor_version` | `capabilities --json::doctor_version` | Tracks doctor implementation; minor bumps for new fixers, major for incompatible refactors |
| `doctor_contract_version` | `capabilities --json::doctor_contract_version` | The agent-facing contract: JSON schemas, exit codes, flag set, `--robot` envelope. Major-bump only on breaking changes |

`schema_version` per JSON artifact (`report.json::schema_version`, `scorecard.json::schema_version`, etc.) is also independent — usually equal to `doctor_contract_version` but artifacts CAN bump independently if a single artifact's shape changes.

---

## What's in the contract (and thus governed by `doctor_contract_version`)

- **Subcommand spelling.** `diagnose | fix | undo | explain | capabilities | health | robot-docs | gc | ls`. Renaming any is breaking.
- **Flag spelling.** `--fix --dry-run --only --skip --since --online --explain --severity --quick --json --robot --robot-triage --no-color --no-progress --verbose --force --yes`. Renaming is breaking.
- **Exit-code dictionary.** Codes 0–6, 64, 66, 73, 74. Repurposing a code is breaking.
- **`report.json` top-level fields.** `schema_version`, `tool`, `run_id`, `started_at`, `summary`, `findings[]`, etc. Renaming is breaking; adding is minor.
- **`actions.jsonl` line schema.** `path`, `op`, `before_hash`, `after_hash`, `started_at_ns`, `finished_at_ns`, `run_id`, `fixer_id`, `ok`. Renaming any is breaking.
- **`capabilities --json` shape.** Same rule.
- **`--robot` envelope** (per Q-014): `success`, `command`, `timestamp`, `data`, `error`, `suggestions`, `timing`. Renaming is breaking.

What's NOT in the contract:

- Detector / fixer IDs (these CAN be renamed at minor bumps; agents use `capabilities --json` to discover them).
- Stderr text (human-readable; not an agent contract).
- Internal types within the implementation.
- Run-artifact directory names beyond `runs/<id>/` (agents read via the symlink `latest`, never hard-coded paths).

---

## Backward-compatible additions vs. breaking changes

### Backward-compatible (minor bump)

- Adding a new flag (defaults to off).
- Adding a new exit code (≥ next-free integer).
- Adding a new field to `report.json` (agents must tolerate unknown fields).
- Adding a new detector or fixer.
- Adding a new subsystem.
- Adding a new value to an enum where the agent treats unknown values as the default.
- Tightening a precondition (refusing more cases) IF the new refusal has a clear remediation.

### Breaking (major bump)

- Removing a flag.
- Removing or repurposing an exit code.
- Renaming a top-level JSON field.
- Removing a subcommand.
- Loosening a precondition (now mutating in cases the agent thought were safe-refused).

Per AGENTS.md § Backwards Compatibility (Q-004), pre-1.0 doctors MAY make breaking changes freely; the user accepts churn for not having tech debt. Post-1.0 doctors should bump the major and provide a migration note in `CHANGELOG.md`.

---

## Run-artifact compatibility across versions

The doctor's own undo path needs to read OLD `actions.jsonl` files. If you bump `doctor_contract_version` from 1.0 to 2.0 and the line schema changes, undo against a 1.0 run-id must still work — or the doctor refuses with a clear error.

Two strategies:

### A. Forward-compatible reader (preferred)

The undo reader tolerates both 1.x and 2.x line schemas. New fields are optional; renamed fields are aliased:

```rust
#[derive(Deserialize)]
#[serde(deny_unknown_fields = false)]
struct ActionRecordV2 {
    path: String,
    op: String,
    before_hash: String,
    after_hash: String,
    #[serde(alias = "started_at_ns_v1")]   // accept the old name too
    started_at_ns: u64,
    ...
}
```

The reader pegs to `actions.jsonl::schema_version` (added at the top of the file as a comment line in v2). Old files lacking the comment default to v1.

### B. Refuse-and-direct (when forward-compat is too costly)

`<tool> doctor undo <old-run-id>` returns exit 4 with a finding:

```
"This run was created by a doctor older than the current contract version
(was 1.0, current is 2.0). To undo, install <tool> v0.4.x and run
`<tool> doctor undo <old-run-id>` from there."
```

This is the AGENTS.md no-shim rule (Q-004) applied: don't carry forward-compat code indefinitely; cite the working older version.

The choice between A and B is a project policy decision. For tools with mostly-stable contracts, A is preferred. For research-stage projects with frequent contract churn, B is acceptable.

---

## Negotiating contract version with an agent

A modern agent invocation pattern:

```bash
caps=$(<tool> doctor capabilities --json)
agent_supports="2.0"
tool_speaks=$(echo "$caps" | jq -r .doctor_contract_version)
if [ "$tool_speaks" != "$agent_supports" ]; then
    echo "agent expects contract $agent_supports; tool speaks $tool_speaks; pinning behavior"
fi
```

The doctor MAY support a `--contract-version=1.0` flag that pins behavior to an older contract. This is the inverse of forward-compat reading: the doctor can speak older agents' language. Useful when an agent has cached behavior and a contract bump would surprise it.

This is opt-in — the default is "current contract"; older agents must explicitly request older behavior.

---

## CHANGELOG.md discipline (the doctor's own)

The doctor's `CHANGELOG.md` (in the target repo, not this skill) tracks contract changes. Format:

```markdown
# Doctor Changelog

## 2.0.0 (BREAKING)

- Renamed `actions.jsonl::started_at_ns` → `started_ns`. Migration: install v1.x to undo old runs, then re-run on current state.
- Removed `--legacy-fix` flag (deprecated since 1.4).

## 1.5.0

- Added `--profile-guided` flag (off by default).
- Added new fixer fm-state-files-shm-orphaned. Fixture at tests/doctor_fixtures/fm-state-files-shm-orphaned/.

## 1.4.0

- DEPRECATION: `--legacy-fix` will be removed in 2.0. Use `--fix` instead.
- ...
```

The `release-preparations` skill (when generating release notes for the project) reads this file and includes the doctor section in the project's overall release notes.

---

## How the meta-doctor (Pattern 12) checks versioning

A meta-doctor for the doctor (proposed; see `META-DOCTOR.md`) validates:

- `capabilities --json::doctor_contract_version` parses as semver.
- `report.json::schema_version` matches `capabilities --json::doctor_contract_version` (or has its own schema URL declared).
- The `actions.jsonl` reader at this binary version can parse the most recent N runs in `.doctor/runs/`.
- Every breaking change in `CHANGELOG.md` since the last major bump corresponds to a semver-major release.
