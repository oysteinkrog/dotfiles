# Spec Pinning for Greenfield Projects

How Phase 2 (REFERENCE PINNING) adapts when there's no external reference. The skill calls this "SPEC PINNING" for greenfield mode.

Cross-link: [`methodology/GREENFIELD-ADAPTATION.md`](GREENFIELD-ADAPTATION.md), [`subagents/scope-decider.md`](../../subagents/scope-decider.md), [`subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md).

---

## 1. What gets pinned

For a port: the upstream reference version (e.g., `sqlite-3.52.0`).

For greenfield: **5 things**, all canonicalized into `docs/contracts/spec_version_contract.toml`:

1. **The project's own spec source(s)** — the document(s) the agent treats as the Oracle.
2. **The property-suite version** — the proptest harness's commit SHA (proptest is itself an oracle source).
3. **The golden-snapshot version** — the insta snapshot directory's commit SHA.
4. **The round-trip-test corpus** — the (encode, decode) test set's commit SHA.
5. **External-tool versions** — Miri, Clippy lint group, cargo-deny advisory DB pin.

Each becomes a SHA-256-pinned line in the contract; oracle preflight refuses to certify if any drifts.

## 2. The `spec_version_contract.toml` schema

```toml
schema_version = "gauntlet.spec_version_contract.v1"

[meta]
project_class = "Greenfield-Rust-class"
created_at_utc = "<ISO>"
revision = 1

# ---------------------------------------------------------------------------
# [spec_sources] — the project's own spec documents
# ---------------------------------------------------------------------------
[[spec_sources]]
name = "primary-spec"
path = "docs/spec/v1/specification.md"
sha256 = "<sha>"
description = "Authoritative spec; every [SPEC-NNN] assertion is extracted from here."

[[spec_sources]]
name = "hard-requirements"
path = "AGENTS.md#hard-requirements-non-negotiable"
sha256 = "<sha-of-relevant-section>"

[[spec_sources]]
name = "design-plan"
path = "COMPREHENSIVE_PLAN_TO_MAKE_EE.md"
sha256 = "<sha>"
description = "Comprehensive plan; cross-checked against primary-spec for consistency."

# Conflicts between spec sources are a Phase 2 BLOCKER; scope-decider must
# canonicalize one source-of-truth before proceeding to Phase 3.

# ---------------------------------------------------------------------------
# [property_suite] — the proptest harness pin
# ---------------------------------------------------------------------------
[property_suite]
crate = "<port>-harness"
test_dir = "tests/properties/"
proptest_version = "1.5.0"
proptest_regressions_dir = "proptest-regressions/"
property_count_floor = 50          # release-blocker if proptest count drops below

# ---------------------------------------------------------------------------
# [golden_snapshots] — the insta snapshot pin
# ---------------------------------------------------------------------------
[golden_snapshots]
crate = "<port>-harness"
snapshot_dir = "tests/snapshots/"
insta_version = "1.39.0"
snapshot_count_floor = 30          # release-blocker if snapshot count drops below
bless_policy = "manual"            # never auto-bless; every snapshot regen has a bead

# ---------------------------------------------------------------------------
# [roundtrip_corpus] — every (encode, decode) pair
# ---------------------------------------------------------------------------
[[roundtrip_corpus]]
name = "context_pack_v1"
encoder = "subject::ContextPack::encode"
decoder = "subject::ContextPack::decode"
fuzz_target = "fuzz/fuzz_targets/context_pack_roundtrip.rs"

[[roundtrip_corpus]]
name = "embedding_v1"
encoder = "subject::Embedding::encode"
decoder = "subject::Embedding::decode"
fuzz_target = "fuzz/fuzz_targets/embedding_roundtrip.rs"

# ---------------------------------------------------------------------------
# [external_tools] — Miri / Clippy / cargo-deny / cargo-audit pins
# ---------------------------------------------------------------------------
[external_tools.miri]
toolchain = "nightly-2026-05-01"
miriflags = "-Zmiri-strict-provenance -Zmiri-symbolic-alignment-check"

[external_tools.clippy]
toolchain = "1.85.0"
deny_warnings = true
lint_group = "pedantic"
additional_lints = [
  "clippy::missing_safety_doc",
  "clippy::undocumented_unsafe_blocks",
  "unsafe_op_in_unsafe_fn",
]

[external_tools.cargo_deny]
config_path = "deny.toml"
advisory_db_sha = "<sha-of-rustsec-advisory-db-snapshot>"

[external_tools.cargo_audit]
advisory_db_sha = "<same-or-different-sha>"

# ---------------------------------------------------------------------------
# [oracle_modes_enabled] — which of the 5 modes this project uses
# ---------------------------------------------------------------------------
[oracle_modes_enabled]
spec_as_oracle = true
property_oracle = true
self_oracle = true
roundtrip_oracle = true
external_tool_oracle = true
```

## 3. Extracting [SPEC-NNN] tags

The Phase 2 scope-decider walks every spec source listed in `[[spec_sources]]` and extracts every line matching any of:

- `MUST [verb] ...` (RFC-2119 normative)
- `SHALL [verb] ...`
- `INVARIANT: ...`
- `PROPERTY: ...`
- `HARD REQUIREMENT: ...`
- `[SPEC-...]` (already-tagged by the spec author)

Each gets a unique tag `[SPEC-<area>-NNN]` where `<area>` derives from the spec section the assertion lives in (e.g., `[SPEC-EE-001]` for an eidetic-engine assertion under "Hard Requirements").

The catalog is written to `<workspace>/docs/spec/SPEC-TAGS.md`:

```markdown
# SPEC Tags Catalog

Auto-extracted at Phase 2. Every tag below corresponds to one verifier function in
`crates/<port>-harness/src/spec_oracle.rs`.

| Tag | Statement | Source | Verifier |
|---|---|---|---|
| `[SPEC-EE-001]` | Every `remember` produces a content-addressable identifier with collision-rate < 1e-15. | `AGENTS.md § Hard Requirements` | `verify_spec_ee_001` |
| `[SPEC-EE-002]` | Every `recall` returns the same context-pack for the same (query, state_hash). | `AGENTS.md § Hard Requirements` | `verify_spec_ee_002` |
| `[SPEC-EE-003]` | Every `pack` respects the configured token budget within ±1%. | `docs/spec/v1/specification.md § Token Budget` | `verify_spec_ee_003` |
...
```

The catalog count is a release-readiness gate: every tag MUST have a corresponding verifier, AND every verifier MUST have a passing E2E test in `tests/spec_*_oracle_e2e.rs`.

## 4. Spec-conflict detection

When two spec sources contradict each other, Phase 2 is BLOCKED. The scope-decider writes `<workspace>/phase2_spec_conflict.md` listing every conflict pair with:

- Source A path + section + verbatim assertion
- Source B path + section + verbatim assertion
- Resolution-needed-from-user note

The user must canonicalize ONE source-of-truth (typically: amend the secondary source to defer to the primary, or amend both to agree on a new shared assertion). Phase 3 cannot start until `phase2_spec_conflict.md` is empty.

## 5. Unverifiable assertions

Some spec lines are aspirational rather than testable ("ee should be useful"; "ee is hermetic"). The scope-decider classifies each `[SPEC-NNN]` candidate into:

- **Verifiable** — has a falsification test surface; gets a verifier in `spec_oracle.rs`.
- **Charter-only** — useful as direction but not test-able. Moved to `<workspace>/docs/CHARTER.md`; NOT tagged with `[SPEC-NNN]`.
- **Ambiguous** — needs refinement before classification. Flagged in `phase2_unverifiable_assertions.md` for the user.

Ambiguous assertions are a Phase 2 yellow (not blocker; gauntlet can proceed but the surface-coverage claim is weakened until resolved).

## 6. Spec versioning + migration

When the spec evolves (new feature added, requirement refined, etc.):

1. The user updates the spec source.
2. The user runs `scripts/bless-spec.sh` (orchestrator-provided), which:
   - Recomputes the spec source's SHA-256.
   - Detects which `[SPEC-NNN]` tags changed (existing tag with different verbatim text) vs added (new tag).
   - Bumps `spec_version_contract.toml#/meta.revision` (e.g., 1 → 2).
   - Schedules an `incremental-rebase` gauntlet mode run to re-validate the changed/added tags.

The schema-version-bumper subagent ([`subagents/schema-version-bumper.md`](../../subagents/schema-version-bumper.md)) handles the producer + consumer + validator + migration test propagation for the bumped `spec_version_contract.v1 → v2` (if the change is breaking).

## 7. Cross-references

- [`methodology/GREENFIELD-ADAPTATION.md`](GREENFIELD-ADAPTATION.md) — meta-pattern for the 5-mode Oracle.
- [`subagents/scope-decider.md`](../../subagents/scope-decider.md) — owns Phase 2 (and the greenfield variant).
- [`subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md) — Phase 3 greenfield variant.
- [`case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md) — worked example for an eidetic-shape greenfield project.
- [`pattern:10-REFERENCE-PINNING`](../patterns/10-REFERENCE-PINNING.md) — the original port-style pattern.
- [`assets/version-contract-template.toml`](../../assets/version-contract-template.toml) — original template (port variant; this doc is the greenfield analog).
