# single-crate-vs-workspace-decision

> Phase 3 starts; the target project's `Cargo.toml` reveals a **single-crate** layout (one `[package]`, no `crates/` subdirectory, possibly an explicit `[workspace] exclude = [...]` opt-out). The greenfield-oracle-wirer expects either layout; pick the right one — and DO NOT promote to a workspace without user signoff.

This recipe documents the decision tree, the precedent (eidetic), and the operational consequences for the harness module path (`src/harness/` vs `crates/<project>-harness/src/`).

Cross-link: [`subagents/greenfield-oracle-wirer.md § Deliverables`](../../subagents/greenfield-oracle-wirer.md), [`assets/per-class-checklists/greenfield.md § Project shape sanity`](../../assets/per-class-checklists/greenfield.md), [`methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md).

## Trigger

Any of:

- `cargo metadata --no-deps --format-version=1 | jq '.workspace_members | length'` returns `1` AND the project root `Cargo.toml` contains a `[package]` block (single-crate layout).
- The target's `Cargo.toml` contains `[workspace] exclude = [...]` — an explicit opt-out from any containing workspace (sign of an intentional single-crate decision).
- The target's `AGENTS.md` (or analog) contains a comment like "single binary crate ... not a workspace in phase 0" — explicit architectural choice.
- Phase 3 oracle-wirer subagent reads the layout and emits `phase3_layout_decision_needed.md`.
- During pre-flight, the harness path resolution finds `crates/` does NOT exist and the orchestrator needs the layout pinned before writing files.

Do NOT enter this recipe if the project is unambiguously a workspace (multiple `[package]` members in `crates/`) — proceed with the workspace path. Do NOT enter if the project's layout is mid-migration (e.g., commits-in-flight); wait for migration to complete.

## Decision tree

```
START
  │
  ├─ Multiple [package] members under crates/?
  │     YES → workspace layout; use crates/<project>-harness/src/  →  EXIT (no recipe needed)
  │     NO  → continue ↓
  │
  ├─ Single-crate; AGENTS.md says "single binary crate ... not a workspace"?
  │     YES → INTENTIONAL single-crate; stay single-crate; use src/harness/  →  EXIT
  │     NO  → continue ↓
  │
  ├─ Single-crate; Cargo.toml has [workspace] exclude = [...] opt-out?
  │     YES → likely intentional single-crate (the author wrote the opt-out
  │           on purpose); default to single-crate; ASK USER before promoting
  │     NO  → continue ↓
  │
  ├─ Single-crate; no signal either way; project is small (<50k LOC, <20 modules)?
  │     YES → stay single-crate; use src/harness/; DEFER promotion until needed
  │     NO  → continue ↓
  │
  └─ Single-crate; >50k LOC OR explicit user request to promote?
        YES → ESCALATE TO USER (this recipe's escalation step)
              if user signs off: promote per "Promotion procedure" below
              if user declines:  stay single-crate; record decision
        NO  → stay single-crate; default
```

Most projects in the Greenfield-Rust-class land in the **stay single-crate** branch. The eidetic precedent (below) is the canonical example.

## Eidetic precedent

`/data/projects/eidetic_engine_cli/Cargo.toml` opens with this comment:

```toml
# Empty [workspace] table opts this package OUT of any containing workspace
# found by Cargo's parent-directory autodiscovery. AGENTS.md is explicit:
# "single binary crate with a library surface in the same package; not a
# workspace in phase 0". On RCH workers, the synced project sometimes
# lands under /data/projects/ which contains an unrelated FCP workspace
# Cargo.toml at the parent — without this opt-out, cargo treats eidetic
# as a member of that workspace and tries to load its (missing) crates.
#
# `exclude` keeps cargo's subdirectory autodiscovery from picking up the
# fuzz/ subproject (its own [package]) and the franken_publish_status
# test fixture (its own nested [workspace]). Without these excludes,
# cargo would try to inherit workspace.package.license-file from
# eidetic's root, which is undefined on purpose ...
[workspace]
exclude = [
    "fuzz",
    "tests/fixtures",
    ".ci",
]

[package]
name = "eidetic-engine"
version = "0.1.0"
edition = "2024"
...
```

And `AGENTS.md` reinforces:

> single binary crate with a library surface in the same package; not a workspace in phase 0

Plus `AGENTS.md` Rule #2: "NO WORKTREES. EVER. NO EXCEPTIONS." — which compounds the intentionality of the single-checkout, single-crate stance.

Consequences for the gauntlet on eidetic per [`case-studies/eidetic_engine_cli.md § 4 First-pass recipe`](../case-studies/eidetic_engine_cli.md):

```
# Phase 3 ORACLE WIRING (greenfield 5-mode) — 3-4h
# NOTE: eidetic is intentionally a single-binary-crate per its Cargo.toml comment
# ("single binary crate with a library surface in the same package; not a
# workspace in phase 0") and AGENTS.md Rule #2 "NO WORKTREES. EVER. NO EXCEPTIONS."
# So harness modules live INSIDE the existing crate under src/harness/, NOT in a
# new crates/ subdirectory.
#   src/harness/spec_oracle.rs
#   src/harness/property_oracle.rs
#   src/harness/self_oracle.rs
#   src/harness/roundtrip_oracle.rs
#   src/harness/external_tool_oracle.rs
#   src/harness/oracle_preflight_doctor.rs
#   src/harness/mod.rs  (pub mod declarations; `#[cfg(any(test, feature = "harness"))]` gated)
```

Note the `#[cfg(any(test, feature = "harness"))]` gating: harness modules compile only under `cargo test` or with the `harness` feature explicitly enabled. This keeps the production binary slim (no harness bytes in the shipped `ee` binary) while making the harness available to integration tests.

## Stay-single-crate procedure (default)

When the decision is "stay single-crate" (the common case):

```bash
PORT=<absolute path to target>

# 1. Create the harness directory
mkdir -p "$PORT/src/harness/"

# 2. Author src/harness/mod.rs with cfg-gated module declarations
cat > "$PORT/src/harness/mod.rs" <<'EOF'
//! Greenfield gauntlet harness modules. Gated behind `#[cfg(any(test, feature
//! = "harness"))]` so they do not ship in the production binary.
//!
//! Authored by subagents/greenfield-oracle-wirer.md per Phase 3.

#![cfg(any(test, feature = "harness"))]

pub mod spec_oracle;
pub mod property_oracle;
pub mod self_oracle;
pub mod roundtrip_oracle;
pub mod external_tool_oracle;
pub mod oracle_preflight_doctor;
pub mod hot_path_counters;
EOF

# 3. Add `pub mod harness;` to src/lib.rs (NOT src/main.rs — main is a thin
#    entry point; harness lives in the library surface so tests can use it)
grep -q "pub mod harness;" "$PORT/src/lib.rs" || \
  echo "pub mod harness;" >> "$PORT/src/lib.rs"

# 4. Add the `harness` feature to Cargo.toml's [features] block
#    (do NOT make it part of `default` — it stays opt-in for production builds)
#    [features]
#    harness = []

# 5. Confirm tests build with the harness available
cd "$PORT" && cargo test --features harness --no-run

# 6. Record the layout decision in <workspace>/phase0_layout.json
cat > "$WORKSPACE/phase0_layout.json" <<EOF
{
  "layout": "single-crate",
  "harness_path": "src/harness/",
  "rationale": "AGENTS.md explicit + Cargo.toml [workspace] exclude opt-out",
  "user_signoff_required_for_promotion": true,
  "decided_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
```

## Promotion procedure (requires user signoff)

Promote to workspace ONLY when ALL of:

1. The user has explicitly authorized the promotion (verbatim quote captured in `<workspace>/USER_AUTHORIZATIONS.md`).
2. The project has crossed a size threshold where multi-crate genuinely helps (typically: >100k LOC, OR multiple independently-versioned components, OR external consumers of a library surface).
3. The promotion plan documents the bill-of-materials: which directories move, which paths change, every `[dependencies]` block updated.

```bash
# DO NOT RUN unprompted. User authorization required first.

PORT=<absolute path>

# 0. Prove user authorization
test -f "$WORKSPACE/USER_AUTHORIZATIONS.md" && \
  grep -q "promote-to-workspace authorized" "$WORKSPACE/USER_AUTHORIZATIONS.md" || \
  { echo "ABORT: user authorization missing"; exit 1; }

# 1. Plan the bill of materials
cat > "$WORKSPACE/promotion_plan.md" <<EOF
# Workspace promotion plan for $(basename $PORT)
## Crates to create
- crates/$(basename $PORT)-core/       — library surface; moved from src/lib.rs
- crates/$(basename $PORT)-cli/        — binary; moved from src/main.rs + src/cli/
- crates/$(basename $PORT)-harness/    — harness modules; moved from src/harness/
## Workspace root Cargo.toml
- [workspace] members = [...]
- [workspace.package] version, edition, rust-version (shared)
- [workspace.dependencies] shared dep pins
## Files moved
... (full enumeration)
## Risks
- nested [workspace] in fuzz/ may need update
- tests/fixtures with their own [package] may need rewiring
- existing benches/ may need re-routing per crate boundary
EOF

# 2. Get the user to bless the plan
echo "USER REVIEW: $WORKSPACE/promotion_plan.md before proceeding"
# (orchestrator pauses; resumes only after the user's "yes" lands in
#  USER_AUTHORIZATIONS.md against this specific promotion-plan hash)

# 3. Execute the promotion in a single atomic commit
# (omitted: project-specific; use scripts/promote-to-workspace.sh as the
#  template, parameterized per the bill of materials above)
```

## Beads to claim (or create)

- `phase3-layout-decision-<round>` — the bead that holds this recipe's evidence.
- Dependency: `methodology/GREENFIELD-ADAPTATION § 11 Worked recipe` — layout pinning is part of the bootstrap.
- Dependency: the project's `AGENTS.md` (or analog) — the contract the layout must honor.
- If promotion: dependency on `epic-workspace-promotion-<project>` epic with the bill-of-materials sub-beads.

## Exit Criteria

- [ ] Layout decision recorded in `<workspace>/phase0_layout.json` with rationale, harness path, and user-signoff status.
- [ ] If stay-single-crate: `src/harness/mod.rs` exists with `#[cfg(...)]` gating; `pub mod harness;` added to `src/lib.rs`; `harness` feature defined in `Cargo.toml`; `cargo test --features harness --no-run` succeeds.
- [ ] If promoted: user authorization captured in `USER_AUTHORIZATIONS.md`; promotion plan reviewed; atomic commit landed; CI green on the new workspace structure.
- [ ] `phase3_oracle_wiring.md` records the layout decision so future agents don't re-litigate it.
- [ ] No stray `crates/` directory created in a single-crate project; no stray `src/harness/` in a workspace project.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| Promoting to workspace silently because "multi-crate is the gauntlet's preferred layout". | The gauntlet has NO preferred layout. The skill explicitly supports both. Unauthorized promotion violates AGENTS.md and breaks the user's architectural choice. |
| Creating `crates/<project>-harness/` next to `src/` in a single-crate project. | Cargo treats `crates/` as a sub-workspace by autodiscovery; this breaks the parent crate. If you must add a multi-crate harness path in a single-crate project, you must promote the parent or add `[workspace] exclude = ["crates"]` — both require user signoff. |
| Ignoring AGENTS.md's explicit "single binary crate ... not a workspace" comment. | AGENTS.md is the user's standing order. Override only with verbatim user authorization. |
| Skipping the `#[cfg(...)]` gating on harness modules. | The production binary inflates with harness bytes; users notice slower startup and larger downloads. Even if the impact is small, the discipline matters for soundness. |
| Forgetting to add the `harness` feature flag to `Cargo.toml`. | The harness becomes inaccessible to integration tests outside `cargo test` (e.g., `cargo bench` with harness counters fails to compile). |
| Adding the `harness` feature to `default = [...]`. | Same problem as no gating — harness ships by default. |
| Promoting to workspace and forgetting to update `fuzz/`'s nested workspace declaration. | cargo-fuzz silently breaks; fuzz targets stop building; nobody notices for a release cycle. |

## Cross-references

- [`../methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) — the meta-pattern, including the eidetic Phase 3 worked recipe.
- [`../case-studies/eidetic_engine_cli.md § 4 First-pass recipe`](../case-studies/eidetic_engine_cli.md) — canonical single-crate decision in practice.
- [`../../subagents/greenfield-oracle-wirer.md § Deliverables`](../../subagents/greenfield-oracle-wirer.md) — the subagent that consumes this decision.
- [`../../assets/per-class-checklists/greenfield.md § Project shape sanity`](../../assets/per-class-checklists/greenfield.md) — the checklist that references this recipe.
- [`../taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class`](../taxonomy/PROJECT-CLASSES.md) — the class row.
- Related motions: [spec-conflict-detected.md](spec-conflict-detected.md), [spec-tag-orphan-cleanup.md](spec-tag-orphan-cleanup.md).
