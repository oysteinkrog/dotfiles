# Pattern 13 — SINGLE-CRATE-VS-WORKSPACE-DECISION

**Family:** Kernel — Phase 3 layout decision for greenfield projects. Pairs with [pattern:10-REFERENCE-PINNING](10-REFERENCE-PINNING.md) (port-mode default is workspace) and the eidetic case study at [`../case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md).

**When to apply:** Phase 3 of gauntlet-greenfield mode, before generating the harness skeleton. Also re-applies on every round where the layout might drift (Phase 12 remediation that adds a new crate, Phase 14 fresh-eyes review). The decision is binary: harness code goes under `src/harness/` (single-crate) OR under `crates/<name>-harness/` (workspace). Wrong choice = wrong code lives in wrong directory = unfixable churn downstream.

## What

A Phase-3 read-only inspector of three signals — (1) the project's `Cargo.toml` for a `[workspace]` table, (2) presence/absence of `[workspace] exclude = [...]` patterns that imply intent, (3) `AGENTS.md` for an explicit "NO WORKTREES" or "SINGLE CRATE ONLY" directive — combined into a single `LayoutDecision` verdict (`SingleCrate` | `Workspace`). The verdict is committed to `<workspace>/phase3_layout_decision.json` and is irreversible within a gauntlet run (a re-decision requires a Phase 0 re-entry). All Phase 3-16 subagents read this file before writing any path.

The decision is *load-bearing* because Rust's compilation model and `cargo`'s workspace semantics are not symmetric: code that compiles cleanly in a workspace will break in a single-crate when the crate's edition/features differ; code that compiles in a single-crate will require `pub use` re-export rituals to be visible from a sibling workspace crate. Choosing wrong means a P12 remediation can't access the type it needs to test.

## Why

The eidetic precedent (see [`../case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md)): the project's `AGENTS.md` carries the verbatim directive:

> "NO WORKTREES. NO SIBLING WORKSPACES. The harness lives inside `src/harness/` of the existing crate. Do not promote to a workspace member without explicit user approval."

The reason is operational: eidetic ships as a single binary; adding a workspace member changes the release artifact graph, the cargo-deny config, the cross-compilation matrix, the `cargo install` UX. The user has a hard preference and the orchestrator must honor it.

Failure mode prevented: *silent workspace promotion*. A Phase 3 subagent looks at the eidetic project, sees "well, harnesses usually live in their own crate," and emits a generated `crates/ee-harness/Cargo.toml` + adds a `[workspace] members = ["crates/ee-harness"]` to the root. The user notices weeks later when their `cargo install --path .` no longer works because the install spec now requires a workspace selector. The negative-ledger entry for this is large and recurring across greenfield projects.

The second failure mode prevented: *splitting code across surprise crates*. Once a workspace is promoted, every subsequent code drop has to decide which crate it goes in. The decision gradient is shallow ("the harness crate seems fine"), so code lands wherever the agent typed first. Six months in, the dependency graph has cycles, the test infrastructure can't reach internal types without `pub`-leakage, and refactoring back to single-crate is days of work.

The third failure mode prevented: *test-discovery confusion*. Integration tests in `tests/` live at the crate level. In a workspace, `cargo test --workspace` runs every crate's tests; in a single-crate, only that crate's. Phase 6 oracle E2E tests need to know which surface they're targeting. If the layout decision drifts mid-round, the test runner targets the wrong surface and reports false-clean.

## The pattern

### The decision struct

```rust
//! crates/<port>-harness/src/layout_decision.rs (when workspace)
//! src/harness/layout_decision.rs (when single-crate)
// (Yes, the chicken-and-egg is real; in greenfield bootstrap, this code starts in
// `src/harness/` and stays there if the verdict is SingleCrate; otherwise it
// migrates as part of the workspace promotion ritual.)

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "verdict", content = "evidence")]
pub enum LayoutDecision {
    SingleCrate {
        crate_name: String,
        harness_dir_rel: PathBuf,        // e.g., "src/harness"
        evidence: Vec<LayoutSignal>,
    },
    Workspace {
        workspace_root_rel: PathBuf,     // e.g., "."
        member_crates: Vec<String>,      // existing members at decision time
        harness_crate_name: String,      // e.g., "<port>-harness"
        harness_crate_dir_rel: PathBuf,  // e.g., "crates/<port>-harness"
        evidence: Vec<LayoutSignal>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub enum LayoutSignal {
    /// Root `Cargo.toml` declares `[workspace]`.
    RootHasWorkspaceTable { members_count: usize },
    /// Root `Cargo.toml` declares `[workspace] exclude = [...]` (intent: don't auto-promote).
    RootWorkspaceExclude { patterns: Vec<String> },
    /// `AGENTS.md` carries an explicit single-crate directive.
    AgentsMdSingleCrateDirective { quoted_line: String, line_no: usize },
    /// `AGENTS.md` carries an explicit "NO WORKTREES" directive.
    AgentsMdNoWorktreesDirective { quoted_line: String, line_no: usize },
    /// `README.md` describes single-binary install (suggests single-crate intent).
    ReadmeSingleBinaryInstall { quoted_line: String },
    /// Multiple existing members — workspace is established.
    ExistingMultipleMembers { count: usize, names: Vec<String> },
    /// User-supplied override from `<workspace>/phase0_intake.json#layout_preference`.
    UserOverride { value: String },
}
```

### The decision algorithm

```rust
pub fn decide_layout(
    project_root: &Path,
    user_override: Option<&str>,
) -> Result<LayoutDecision, LayoutError> {
    let mut signals = Vec::new();

    // (1) Read Cargo.toml.
    let cargo_toml_path = project_root.join("Cargo.toml");
    let cargo_toml: toml::Value = toml::from_str(
        &std::fs::read_to_string(&cargo_toml_path)?
    )?;

    let has_workspace = cargo_toml.get("workspace").is_some();
    let workspace_members: Vec<String> = cargo_toml.get("workspace")
        .and_then(|w| w.get("members"))
        .and_then(|m| m.as_array())
        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();
    let workspace_exclude: Vec<String> = cargo_toml.get("workspace")
        .and_then(|w| w.get("exclude"))
        .and_then(|e| e.as_array())
        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();

    if has_workspace {
        signals.push(LayoutSignal::RootHasWorkspaceTable {
            members_count: workspace_members.len(),
        });
    }
    if !workspace_exclude.is_empty() {
        signals.push(LayoutSignal::RootWorkspaceExclude {
            patterns: workspace_exclude.clone(),
        });
    }
    if workspace_members.len() >= 2 {
        signals.push(LayoutSignal::ExistingMultipleMembers {
            count: workspace_members.len(),
            names: workspace_members.clone(),
        });
    }

    // (2) Scan AGENTS.md for single-crate / no-worktrees directives.
    let agents_md_path = project_root.join("AGENTS.md");
    if agents_md_path.exists() {
        let text = std::fs::read_to_string(&agents_md_path)?;
        for (i, line) in text.lines().enumerate() {
            let trimmed_upper = line.trim().to_uppercase();
            if trimmed_upper.contains("NO WORKTREES")
                || trimmed_upper.contains("DO NOT CREATE NEW BRANCH")
                || trimmed_upper.contains("DO NOT CREATE SIBLING WORKSPACE")
            {
                signals.push(LayoutSignal::AgentsMdNoWorktreesDirective {
                    quoted_line: line.trim().to_string(),
                    line_no: i + 1,
                });
            }
            if trimmed_upper.contains("SINGLE CRATE")
                || trimmed_upper.contains("NO SIBLING WORKSPACE")
                || trimmed_upper.contains("HARNESS LIVES INSIDE")
            {
                signals.push(LayoutSignal::AgentsMdSingleCrateDirective {
                    quoted_line: line.trim().to_string(),
                    line_no: i + 1,
                });
            }
        }
    }

    // (3) README scan for single-binary install hints.
    let readme_path = project_root.join("README.md");
    if readme_path.exists() {
        let text = std::fs::read_to_string(&readme_path)?;
        for line in text.lines() {
            if line.contains("cargo install --path .") && !line.contains("--package") {
                signals.push(LayoutSignal::ReadmeSingleBinaryInstall {
                    quoted_line: line.to_string(),
                });
                break;
            }
        }
    }

    // (4) User override has the highest precedence.
    if let Some(o) = user_override {
        signals.push(LayoutSignal::UserOverride { value: o.to_string() });
    }

    // Decision rule.
    let single_crate_signals = signals.iter().any(|s| matches!(s,
        LayoutSignal::AgentsMdSingleCrateDirective { .. }
        | LayoutSignal::AgentsMdNoWorktreesDirective { .. }
        | LayoutSignal::RootWorkspaceExclude { .. }
        | LayoutSignal::UserOverride { value } if value == "single-crate"
    ));
    let workspace_signals = signals.iter().any(|s| matches!(s,
        LayoutSignal::ExistingMultipleMembers { .. }
        | LayoutSignal::UserOverride { value } if value == "workspace"
    ));

    // Precedence: explicit user override > AGENTS.md directive > existing
    // workspace structure > Cargo.toml `[workspace]` table > default.
    if user_override == Some("single-crate") || single_crate_signals {
        let crate_name = cargo_toml.get("package")
            .and_then(|p| p.get("name"))
            .and_then(|n| n.as_str())
            .ok_or(LayoutError::PackageNameMissing)?
            .to_string();
        Ok(LayoutDecision::SingleCrate {
            crate_name,
            harness_dir_rel: PathBuf::from("src/harness"),
            evidence: signals,
        })
    } else if workspace_signals || (has_workspace && workspace_exclude.is_empty()) {
        let port_name = derive_port_name(project_root)?;
        Ok(LayoutDecision::Workspace {
            workspace_root_rel: PathBuf::from("."),
            member_crates: workspace_members,
            harness_crate_name: format!("{}-harness", port_name),
            harness_crate_dir_rel: PathBuf::from(format!("crates/{}-harness", port_name)),
            evidence: signals,
        })
    } else {
        // Greenfield with no clear signal: default to single-crate (safer; can promote later).
        let crate_name = cargo_toml.get("package")
            .and_then(|p| p.get("name"))
            .and_then(|n| n.as_str())
            .ok_or(LayoutError::PackageNameMissing)?
            .to_string();
        Ok(LayoutDecision::SingleCrate {
            crate_name,
            harness_dir_rel: PathBuf::from("src/harness"),
            evidence: signals,
        })
    }
}
```

### Persistence and read-back

```rust
pub fn write_decision(workspace: &Path, decision: &LayoutDecision) -> std::io::Result<()> {
    let path = workspace.join("phase3_layout_decision.json");
    let json = serde_json::to_string_pretty(decision).unwrap();
    std::fs::write(&path, json)?;
    Ok(())
}

pub fn read_decision(workspace: &Path) -> std::io::Result<LayoutDecision> {
    let path = workspace.join("phase3_layout_decision.json");
    let text = std::fs::read_to_string(&path)?;
    Ok(serde_json::from_str(&text).expect("decision file is durable + schema-pinned"))
}
```

### How downstream subagents consume the decision

Every Phase 3-16 subagent that needs to know where harness code lives:

```rust
fn harness_module_path(workspace_root: &Path) -> PathBuf {
    let decision = read_decision(workspace_root).expect("decision is Phase 3 invariant");
    match decision {
        LayoutDecision::SingleCrate { harness_dir_rel, .. } => {
            workspace_root.join(harness_dir_rel)
        }
        LayoutDecision::Workspace { harness_crate_dir_rel, .. } => {
            workspace_root.join(harness_crate_dir_rel).join("src")
        }
    }
}
```

The path for a generated test file:

```rust
fn test_file_path(workspace_root: &Path, name: &str) -> PathBuf {
    let decision = read_decision(workspace_root).unwrap();
    match decision {
        LayoutDecision::SingleCrate { .. } => {
            workspace_root.join("tests").join(format!("{name}.rs"))
        }
        LayoutDecision::Workspace { harness_crate_dir_rel, .. } => {
            workspace_root.join(harness_crate_dir_rel).join("tests").join(format!("{name}.rs"))
        }
    }
}
```

## Variants per project class

| Class | Default verdict | Common signals |
|---|---|---|
| **SQL-class (port: e.g., FrankenSQLite)** | `Workspace` | Port projects historically use workspaces; multiple crates (port, harness, bench, fuzz) are standard |
| **RESP-class (port)** | `Workspace` | Same as SQL |
| **Numerical-Python (port)** | `Workspace` | Plus typically a separate `<port>-py` crate for Python bindings |
| **ML-System (port)** | `Workspace` | Often 3-5 crates (core, autograd, dispatch, py-bindings, harness) |
| **HTTP-Protocol (port)** | `Workspace` | Plus `<port>-codegen` crate for typed-extractor generation |
| **Greenfield-Rust (single-binary CLI like eidetic)** | `SingleCrate` (default + typically reinforced by AGENTS.md) | Single binary install; "NO WORKTREES" directive common |
| **Greenfield-Rust (library + multiple consumers)** | `Workspace` | If `Cargo.toml` already declares members, honor it |

### Per-class harness path templates

| Verdict | Harness module | Tests dir | Bench dir | Fuzz dir |
|---|---|---|---|---|
| `SingleCrate` | `src/harness/` | `tests/` (crate-level) | `benches/` (crate-level) | `fuzz/` (crate-level; uses `cargo-fuzz`) |
| `Workspace` | `crates/<port>-harness/src/` | `crates/<port>-harness/tests/` | `crates/<port>-bench/benches/` | `crates/<port>-fuzz/fuzz/` |

## Re-decision and promotion ritual

A `SingleCrate → Workspace` promotion is a deliberate, user-approved ritual:

1. Author `<workspace>/phase0_intake.json#layout_preference = "workspace"`.
2. Re-enter Phase 0 (re-run `init-workspace.sh --re-entry`).
3. The scope-decider subagent runs the promotion ritual inline (no separate `layout-promoter` subagent; the operation is low-frequency and lives within scope-decider's Phase 3 / Phase 0 re-entry scope):
   - Creates `crates/<port>-harness/`.
   - Moves `src/harness/*.rs` → `crates/<port>-harness/src/`.
   - Updates root `Cargo.toml` with `[workspace] members = [".", "crates/<port>-harness"]`.
   - Rewrites every `use crate::harness::*` to `use <port>_harness::*`.
   - Adds `<port>-harness` as a `[dev-dependencies]` of the root crate.
   - Commits as a single migration commit with the proof-isomorphism per [pattern:250-ISOMORPHISM-PROOF](250-ISOMORPHISM-PROOF.md).
4. Promotion is logged in `<workspace>/MEMORY.md` and `<workspace>/sessions/session_<NNN>_layout_promotion.md`.

Demotion (`Workspace → SingleCrate`) is rarer; same ritual in reverse, with extra care for `pub` re-export removal.

## Failure modes

| Failure | Symptom | Detection | Fix |
|---|---|---|---|
| **Silent workspace promotion** | Phase 3 emits `crates/<port>-harness/Cargo.toml` against an explicit `NO WORKTREES` AGENTS.md. | `phase3_layout_decision.json` exists; reviewer flags the verdict against AGENTS.md content. | Decision step is HARD-MANDATORY before any code generation; CI checks the file exists; emit `LayoutError` on conflict between signals. |
| **Splitting code across surprise crates** | A Phase 12 remediation adds a new optimization to `crates/<port>-harness/src/foo.rs` even though the layout is SingleCrate; broken build. | `cargo metadata` integration test in CI; verifies harness code lives in the decision-declared dir only. | Every code-emitting subagent calls `read_decision` and respects it; PRs that violate are rejected by the layout-decision-enforcer hook. |
| **Decision file missing on Phase 4 entry** | Phase 4 starts; no `phase3_layout_decision.json`; harness path defaulted to `src/harness/`; project is actually a workspace. | Pre-phase-entry self-test per [`COMPACTION-SURVIVAL.md`](../methodology/COMPACTION-SURVIVAL.md). | Phase 4 BLOCKS if `phase3_layout_decision.json` is missing; orchestrator falls back to re-run Phase 3. |
| **User override mid-round** | User edits `phase0_intake.json#layout_preference` partway through Round N. | `init-workspace.sh --re-entry` runs the promotion ritual; without it, decision drifts. | Override changes are only honored at Phase 0 re-entry; mid-round changes are noted but not applied until next Phase 0. |
| **AGENTS.md directive added mid-project** | Project starts as Workspace; user later adds "NO WORKTREES" to AGENTS.md without de-promotion. | Decision-detector re-run at Phase 14 fresh-eyes; flags AGENTS.md signal that contradicts current `phase3_layout_decision.json`. | Surface as a yellow; require user to run demotion ritual to reconcile. |
| **Default-to-single-crate silently chosen for a library that should be workspace** | Greenfield project has no AGENTS.md directive, no workspace table, but is intended as a library with consumers — single-crate verdict picked. | Round-2 review flags single-crate layout for a project that has `[lib]` table and multiple `bin/` entries; suggest workspace promotion. | Project-class detector (`scripts/detect-project-class.sh`) gains a "library suspect" signal that pre-suggests workspace via `phase0_intake.json`. |
| **Decision-file edited by hand to change verdict** | Future agent edits `phase3_layout_decision.json` to flip from SingleCrate to Workspace without running promotion ritual. | File has a `decision_sha = sha256(verdict + evidence)` field; mismatch detected on read. | File is immutable; any verdict change requires re-run of the decide-layout binary AND the promotion ritual. |
| **Eidetic-style precedent ignored** | Agent reads "NO WORKTREES" in AGENTS.md and interprets it as "no `git worktree`", not "no Cargo workspaces". | Phase 14 fresh-eyes review catches misinterpretation; eidetic case study referenced in MEMORY.md. | Pattern's "Why" section quotes the directive verbatim; case study lists the user's intent explicitly; AGENTS.md template recommends "NO CARGO WORKSPACE" for unambiguous single-crate intent. |

## Cross-references

- [pattern:06-5-MODE-ORACLE-DISPATCH](06-5-MODE-ORACLE-DISPATCH.md) — adapter modules live under the harness path this decision establishes.
- [pattern:10-REFERENCE-PINNING](10-REFERENCE-PINNING.md) — the contract file lives at `docs/contracts/` regardless of layout, but the consumer code is layout-sensitive.
- [pattern:11-SPEC-TAG-EXTRACTION](11-SPEC-TAG-EXTRACTION.md) — `spec_tag_extractor.rs` location depends on this decision.
- [pattern:12-SPEC-CONFLICT-DETECTION](12-SPEC-CONFLICT-DETECTION.md) — detector binary location depends on this decision.
- [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) — doctor binary location depends on this decision.
- [pattern:55-INSTA-GOLDEN-SNAPSHOTS](55-INSTA-GOLDEN-SNAPSHOTS.md) — snapshot directory location depends on this decision.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — invalid-references = a verifier in the wrong crate.
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — `.bench-history/` lives at repo root regardless, but bench targets are layout-sensitive.
- [pattern:255-RCH-OFFLOAD-DISCIPLINE](255-RCH-OFFLOAD-DISCIPLINE.md) — `cargo build --workspace` vs `cargo build --package <name>` differ depending on this decision; rch sync respects the decision.
- [pattern:280-SCRATCH-WORKTREE-CONVENTION](280-SCRATCH-WORKTREE-CONVENTION.md) — scratch worktrees ignore the layout-decision; they're outside the repo.
- [`../methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) §11 — workflow integration point.
- [`../methodology/COMPACTION-SURVIVAL.md`](../methodology/COMPACTION-SURVIVAL.md) — `phase3_layout_decision.json` is a Layer 3 durable artifact.
- [`../case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md) — the canonical SingleCrate precedent.
- [`../../subagents/scope-decider.md`](../../subagents/scope-decider.md) — owns Phase 3; reads decision before generating any path.
- The SingleCrate → Workspace promotion ritual is documented inline in this pattern's "Mutability" section; no separate subagent is provisioned (low-frequency operation; the scope-decider handles re-entry).
