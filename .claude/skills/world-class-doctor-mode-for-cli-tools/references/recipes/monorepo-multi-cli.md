# Recipe: Monorepo with multiple CLIs (parent doctor delegates to sub-CLI doctors)

**When to use.** The target is a monorepo containing 2+ user-facing CLI binaries (Cargo workspace with multiple `[[bin]]` crates; npm workspace with multiple `bin` packages; Go monorepo with multiple `cmd/<name>/main.go`). Each sub-CLI may have its own state surface (its own DB, its own config dir, its own .doctor/runs/), and the user wants ONE entry point to diagnose them all.

**Examples in this repo's corpus:**
- `/dp/mcp_agent_mail_rust` — Cargo workspace producing `mcp-agent-mail` (server), `am` (CLI), `mcp-agent-mail-conformance` (test runner). The CLI binary `am` has the doctor surface; the others don't.
- `/dp/coding_agent_session_search` — Cargo workspace producing `cass` (main CLI) and `cass-pages-perf-bundle` (helper). Doctor lives on `cass`.

When a project has only ONE binary with a doctor surface, the standard 9-subcommand structure applies; this recipe is for the rarer case where MULTIPLE binaries each warrant their own doctor.

---

## Architecture

```
<repo> doctor                          ← parent: aggregator
├── <repo> doctor --only=cli-a         ← scope to one sub-CLI
├── <repo> doctor --only=cli-b
└── <repo> doctor --json               ← unified JSON output

   under the hood:
       <cli-a> doctor --json   →
       <cli-b> doctor --json   →   merge → emit unified report
       <cli-c> doctor --json   →
```

The parent is a thin aggregator. It does NOT implement detectors itself; it INVOKES each sub-CLI's doctor and merges results. Each sub-CLI follows the standard 9-subcommand contract.

## Where the parent lives

| Workspace style | Parent doctor lives in |
|-----------------|-----------------------|
| Cargo workspace | A new bin crate `<repo>-tools/` with `[[bin]] name = "<repo>"`. Or, designate one sub-crate as the entry-point crate (e.g., `am` in mcp_agent_mail_rust) and add a `doctor monorepo` subcommand there. |
| npm workspace | A root-level `bin` field in the top `package.json` pointing to a project-specific entry-point script. The skill provides no template for this (the path `scripts/repo-doctor.js` mentioned here is a placeholder; you write the actual aggregator per the project). Future: a `scripts/scaffold-doctor.sh --language=typescript --aggregator=monorepo` mode could emit a starter. |
| Go monorepo | A new `cmd/<repo>-doctor/main.go` that imports each sub-CLI's `internal/doctor` package and dispatches. |

## Capabilities aggregation

The parent's `capabilities --json` MUST include:

```jsonc
{
  "schema_version": "1.0",
  "tool": "<repo>",
  "subsystems": [...],         // union of all sub-CLI subsystems
  "detectors": [...],          // union, with sub-CLI prefix on FM ids
  "fixers": [...],             // union, sub-CLI prefix
  "sub_doctors": [             // NEW field for monorepo recipe
    {
      "name": "cli-a",
      "binary": "/path/to/cli-a",
      "version": "0.4.7",
      "capabilities_url": "... or inline {...}"
    },
    ...
  ]
}
```

Each FM id is prefixed with the sub-CLI name to keep the namespace clean: `fm-am-state_files-jsonl-tombstone-drift` (under `am`) vs `fm-mcp-agent-mail-state_files-...` (under the server). Without the prefix, two sub-CLIs with similar subsystems would have id collisions.

## Diagnose flow

```pseudocode
parent_doctor.diagnose():
    sub_findings = []
    for sub in capabilities.sub_doctors:
        rc, json_out = run(f"{sub.binary} doctor --json")
        # rc 0 (clean) or 1 (findings) both feed the merge.
        if rc not in {0, 1}:
            return parent_exit_4("sub-CLI {sub.name} unreachable; rc={rc}")
        for finding in json_out.findings:
            finding.id = f"{sub.name}-{finding.id}"   # prefix
            sub_findings.append(finding)
    emit unified report with sub_findings.
    overall_exit = 1 if sub_findings else 0
```

## Fix flow

The parent CANNOT route fixes through ONE `mutate()` chokepoint — each sub-CLI has its own. Instead:

```pseudocode
parent_doctor.fix():
    # Per-sub-CLI execution, sequentially (NOT parallel — one sub's mutations
    # may invalidate another's preconditions).
    for sub in capabilities.sub_doctors:
        rc = run(f"{sub.binary} doctor --fix --json", capture=False)
        if rc not in {0, 2}:   # 2 = partial; OK to continue with next sub
            return parent_exit_3(f"sub-CLI {sub.name} fix failed; rolling back parent run-id")
    aggregate_actions = sum across each sub's run_dir/actions.jsonl
    emit unified scorecard.
```

The parent's `--fix` operation is bracketed by per-sub-CLI mutate-chokepoints; each sub-CLI's atomicity is preserved.

## Undo flow

The parent's `undo <run-id>` MUST cascade to every sub-CLI that participated in that run:

```pseudocode
parent_doctor.undo(run_id):
    parent_run_dir = .doctor/runs/<run_id>/
    sub_run_ids = read parent_run_dir/manifest.json::sub_runs
    for sub_name, sub_run_id in sub_run_ids:
        rc = run(f"{cli_for(sub_name)} doctor undo {sub_run_id}")
        if rc != 0:
            return exit_3("sub-CLI undo failed; manual recovery required")
```

The parent's run-dir stores a manifest mapping each sub-CLI's run-id, so the cascade is deterministic.

## Per-sub-CLI scoping flags

| Flag | Semantics |
|------|-----------|
| `--only=cli-a,cli-b` | Run doctor only against the named sub-CLIs. |
| `--skip=cli-a` | Inverse. |
| `--all` | Default; explicit form. |

These compose with the standard `--only=fm-id1,fm-id2` flag — if both are passed, the FM ids must be filtered against the sub-CLI scope first.

## Scoring caveat

In Phase 6, the parent's scorecard is the WEIGHTED AVERAGE of each sub-CLI's scorecard, weighted by `sub_doctor.invocation_share` (estimated from CASS or the project's billing). A sub-CLI with rare usage shouldn't dominate the parent's aggregate.

```text
parent_aggregate = sum(sub.aggregate × sub.invocation_share) / sum(sub.invocation_share)
```

If `invocation_share` data is unavailable, fall back to uniform weighting.

## Known sharp edges

1. **Sub-CLI version drift.** If `cli-a` is at version 1.0 but `cli-b` is at version 2.0 with a contract bump, the parent must declare the union range of supported `doctor_contract_version`s. Surface this clearly in `capabilities --json::sub_doctors[*].version`.
2. **Long-running sub-CLIs.** A sub-CLI doctor that takes > 5 seconds bottlenecks the parent's `health` command. Mitigation: run sub-CLI healths in parallel (they don't mutate). Cap parent `health` at 200ms by parallelizing.
3. **Cross-sub-CLI invariants** — see dedicated section below.

## Cross-binary invariant detectors (round-56)

When sub-CLI A reads/writes state that belongs to sub-CLI B, neither sub-CLI's per-binary doctor can see the invariant; only a doctor with knowledge of BOTH binaries can. This is a doctor design pattern, not an exception.

### Examples observed in `/dp`

- `/dp/mcp_agent_mail_rust`: the CLI binary `am` reads `mcp-agent-mail` (the server)'s SQLite database directly. If the server's schema is migrated but the CLI hasn't been recompiled with matching expectations, neither the server's nor the CLI's doctor catches the mismatch.
- A common Tauri-style hybrid: the Rust backend writes to a config file the JS frontend reads. Schema drift between them is invisible to either one in isolation.

### Detector pattern

The parent doctor declares cross-binary FMs in its capabilities:

```jsonc
{
  "detectors": [
    {
      "id": "fm-cross-am-server-schema-mismatch",
      "subsystem": "schemas",
      "severity": "P0",
      "description": "CLI binary `am` and server binary `mcp-agent-mail` declare different schema_version constants",
      "estimated_cost_ms": 50,
      "online_required": false,
      "owner": "parent",
      "involves_binaries": ["am", "mcp-agent-mail"]
    }
  ]
}
```

Two new fields:
- `owner`: `"parent"` for cross-binary detectors, `"<sub-name>"` otherwise. Parent's `--only` filtering uses this to scope.
- `involves_binaries`: list of sub-binaries the detector reads. Affects `health`'s parallelism plan: parent can't run cross-binary detectors in parallel with their constituent binaries' updates.

### Detector implementation

```pseudocode
parent_doctor.detect_fm_cross_am_server_schema_mismatch():
    am_caps = json_decode(run("am doctor capabilities --json"))
    server_caps = json_decode(run("mcp-agent-mail doctor capabilities --json"))
    am_schema = am_caps.tool_version    # or a more specific field
    server_schema = server_caps.tool_version
    if not schema_versions_compatible(am_schema, server_schema):
        return Finding(
            id="fm-cross-am-server-schema-mismatch",
            severity="P0",
            evidence={"am_version": am_schema, "server_version": server_schema},
            confidence=1.0
        )
    return None
```

### Fixer pattern

Cross-binary fixers are usually NOT auto-fixable: resolving a schema mismatch requires choosing one as the source-of-truth and recompiling/redeploying the other. The parent emits a `manual_remediations` entry with the user-actionable guidance ("upgrade `am` to version >= X.Y.Z and run `am doctor --fix`").

If a cross-binary fix IS auto-fixable, the parent's mutate() chokepoint coordinates: route the per-binary writes through each sub-binary's `--fix --only=<id>`, recording each sub-run-id in the parent's run-dir manifest. Undo cascades naturally.

### Phase 5 testing

Use `scripts/verify-cross-fm.sh <fm-cross-A-B> <fm-other>` to test interactions. Cross-binary FMs can be paired with single-binary FMs to surface ordering issues.

## Phase 4 implementer guidance

When generating skeletons:
- Each sub-CLI's `doctor.<lang>` is independently scaffolded via `scripts/scaffold-doctor.sh --target <sub-crate-dir> --tool <sub-bin>`.
- The parent's aggregator is hand-written (not scaffolded) because the aggregation logic is project-specific.
- Phase 5 safety-harness runs PER SUB-CLI; the parent has no fixers of its own, so its harness is a smoke test that "parent doctor diagnose" + "parent doctor --fix" produce reports without crashing.

## Phase 8 integration

Same as standard:
- Pre-commit hook: `<repo> doctor --quick` (parent invocation).
- CI: `<repo> doctor health` for the hard gate; `<repo> doctor --json` for the regression check.
- Demote any per-sub-CLI manual playbooks to fallbacks under the parent's `playbook.md`.

## Compatibility

This recipe extends the canonical contract; it does NOT replace any axiom. The 24-axiom kernel applies to EACH sub-CLI's doctor (mutate-chokepoint, undo-only-deletes, etc.). The parent is a thin aggregator that adds delegation semantics on top.
