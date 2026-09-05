# greenfield-oracle-wirer

> Phase 3 (greenfield variant) • For projects where `detect-project-class.sh` returns `UNKNOWN` (or the user explicitly invokes `gauntlet-greenfield` mode). Authors the 5-mode greenfield Oracle: Spec / Property / Self / Round-trip / External-tool.

## Inputs

- `<workspace>/phase0_project_class.json` — `detected_class == "UNKNOWN"` (greenfield trigger).
- `<workspace>/phase0_intake.json` — user confirmed `mode == "gauntlet-greenfield"`.
- `<workspace>/docs/contracts/spec_version_contract.toml` — Phase 2 output (the spec pinning, in place of `<reference>_version_contract.toml`).
- The project's spec source(s): typically `docs/spec/v1/`, `README.md` "Hard Requirements", `AGENTS.md` "Hard Requirements (Non-Negotiable)", `COMPREHENSIVE_PLAN_*.md`, etc.

## Deliverables

Layout depends on whether the target project is a Cargo **workspace** or a **single-crate** package (detect via reading `<target>/Cargo.toml`). For both layouts, the same module set is authored — only the path collapses.

**Workspace projects** (most ports — frankensqlite, frankenredis, etc.):
- `crates/<project>-harness/src/spec_oracle.rs` — one verifier per `[SPEC-NNN]` tag.
- `crates/<project>-harness/src/property_oracle.rs` — bridges proptest into the MismatchSignature pipeline.
- `crates/<project>-harness/src/self_oracle.rs` — insta-snapshot-bridged self-oracle.
- `crates/<project>-harness/src/roundtrip_oracle.rs` — every encode→decode + serialize→parse + pack→unpack roundtrip wired as one scenario per round-trip pair.
- `crates/<project>-harness/src/external_tool_oracle.rs` — Miri / Clippy / cargo-deny / cargo-audit adapters.
- `crates/<project>-harness/src/oracle_preflight_doctor.rs` — greenfield variant: verifies spec SHA-256, property-suite version, golden-snapshot freshness, external-tool versions.
- `crates/<project>-harness/src/oracle.rs` — composite Oracle dispatching across all 5 modes per scenario.

**Single-crate projects** (e.g., `eidetic_engine_cli` — Cargo.toml has `[workspace] exclude = [...]` and an explicit comment "single binary crate ... not a workspace in phase 0"):
- `src/harness/mod.rs` — `#[cfg(any(test, feature = "harness"))] pub mod spec_oracle; ...`
- `src/harness/spec_oracle.rs` (and `property_oracle.rs`, `self_oracle.rs`, `roundtrip_oracle.rs`, `external_tool_oracle.rs`, `oracle_preflight_doctor.rs`, `oracle.rs`) — same contents as the workspace variant; paths collapse one level.

Promoting a single-crate project to a workspace requires user signoff — never do it unprompted. Many single-crate projects (eidetic, plus AGENTS.md rules like "NO WORKTREES") have made an intentional architectural choice.

**Common to both layouts:**
- `tests/spec_oracle_smoke.rs` — one trivial smoke test per oracle mode (one `#[test]` fn each).
- `<workspace>/phase3_oracle_wiring.md` — summary + per-mode coverage map + the layout decision (workspace vs single-crate) so future agents know.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase3-greenfield-oracle`
- **Reservations needed:** `tool://oracle-wirer-greenfield` (exclusive, TTL 4h).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

```
You are the greenfield-oracle-wirer for Phase 3 (greenfield variant). Your job
is to author the 5-mode Oracle suite for a novel Rust project that has no
external reference. The Subject is the current code; the Oracle is constructed
from the project's own spec + properties + prior-commit baseline + round-trip
tests + external tools.

Read references/methodology/GREENFIELD-ADAPTATION.md before starting; it
specifies the 5 oracle modes + the per-mode authoring approach.

INPUTS:
- <workspace>/phase0_intake.json — must report mode == "gauntlet-greenfield"
- <workspace>/docs/contracts/spec_version_contract.toml — the spec pinning
- <target>/ — the project root with spec sources

STEPS:

1. Pre-flight gate:
     mode=$(jq -r .mode <workspace>/phase0_intake.json)
     [ "$mode" = "gauntlet-greenfield" ] || { echo "greenfield-oracle-wirer skipped: mode=$mode"; exit 0; }

2. Mine the spec sources to extract assertions:
   Read each spec source listed in spec_version_contract.toml#/spec_sources.
   For each "Hard Requirement" / "MUST" / "SHALL" / "INVARIANT" / "PROPERTY"
   statement, tag it `[SPEC-<area>-NNN]` and write the verifier to the project's
   harness as one Rust function:

     // crates/<project>-harness/src/spec_oracle.rs

     /// SPEC-EE-001: every `remember` produces a content-addressable identifier
     /// with collision-rate < 1e-15.
     pub fn verify_spec_ee_001(state: &State, output: &RememberOutput) -> Result<(), SpecViolation> {
         // ... verification logic ...
     }

   Surface the tagged assertion catalog in:
     <workspace>/docs/spec/SPEC-TAGS.md

3. Author the property_oracle bridge:
   - Wire proptest's `TestRunner` into the harness with `FileFailurePersistence::WithSource("regressions")`.
   - Per pattern:40-METAMORPHIC-TRANSFORMS, declare the 4 TransformFamily entries.
   - Use ../assets/property-test-templates/<class>_proptest.rs as a structural
     starting point even though the class is greenfield; the proptest-bridge
     code is class-agnostic.

4. Author the self_oracle:
   - Wire insta with `cargo insta test --review` workflow.
   - For every emitted format (`text`, `json`, `markdown`, etc.) author one
     `assert_snapshot!` per scenario.
   - Snapshots committed under `tests/snapshots/` per insta convention.
   - Snapshot regeneration discipline: only when contract changes (per
     pattern:55-INSTA-GOLDEN-SNAPSHOTS).

5. Author the roundtrip_oracle:
   - For every (encode, decode) pair in the project, author a scenario:
       fn roundtrip_<name>(input: impl Arbitrary, label: &str) {
           let encoded = subject::encode(&input);
           let decoded = subject::decode(&encoded).expect(label);
           assert_eq!(input, decoded, "{label}: round-trip identity violation");
       }
   - For every (serialize, parse), (pack, unpack), (sign, verify) pair: same shape.
   - Wire ../assets/fuzz-target-templates/<class>_fuzz.rs as the differential-fuzz harness.

6. Author the external_tool_oracle:
   - Miri adapter: wraps `cargo +nightly miri test --lib`; UB findings → TrueDivergence-equivalent FailureBundle.
   - Clippy adapter: wraps `cargo clippy --all-targets -- -D warnings`; warning → TrueDivergence-equivalent.
   - cargo-deny adapter: wraps `cargo deny check`; advisory hit → release blocker.
   - cargo-audit adapter: wraps `cargo audit`; RustSec hit → release blocker.

7. Author the oracle_preflight_doctor (greenfield variant):
   Emits {certifying: bool, aggregate_outcome: "green|yellow|red", failures, remediation}.
   Verifies:
   - spec_version_contract.toml#/spec_source_sha256 matches current spec file SHA-256
   - proptest-regressions/*.txt exists for every prop test (no orphans)
   - tests/snapshots/*.snap exists for every assert_snapshot! invocation
   - tests/golden/*.golden exists for every roundtrip pair
   - `cargo +nightly miri test --lib --no-run` succeeds (Miri can build)
   - `clippy --version`, `cargo deny --version`, `cargo audit --version` all present

8. Author the composite oracle.rs:
   The 30-line `scenario()` template (greenfield variant) dispatches across
   the 5 modes:

     fn scenario(name: &str, setup: ..., action: ..., mode: OracleMode) {
         match mode {
             OracleMode::Spec(verifier)       => spec_oracle::run(setup, action, verifier),
             OracleMode::Property(prop)        => property_oracle::run(setup, action, prop),
             OracleMode::Self_(snapshot_name)  => self_oracle::run(setup, action, snapshot_name),
             OracleMode::RoundTrip(encoder, decoder) => roundtrip_oracle::run(setup, action, encoder, decoder),
             OracleMode::ExternalTool(tool)    => external_tool_oracle::run(setup, action, tool),
         }
     }

   Both-error = agreement + one-error-one-OK = hard failure rules apply
   per pattern:K-8 across ALL 5 modes.

9. Write tests/spec_oracle_smoke.rs:
   - Test 1: every oracle mode dispatches without panicking on a trivial input.
   - Test 2: the preflight doctor returns green on the current workspace.
   - Test 3: a synthetic "spec violation" is caught + classified by the spec_oracle.
   - Test 4: an insta-snapshot drift is caught by the self_oracle.

10. Emit phase3_oracle_wiring.md summary:
    - Per-mode coverage: how many [SPEC-NNN] tags? how many properties? how
      many snapshots? how many roundtrip pairs? how many external tools wired?
    - Outstanding gaps: spec assertions without verifiers; behaviors without
      snapshots; encode-decode pairs without roundtrips.
    - Next: Phase 4 GOLDEN CAPTURE will bless the initial snapshots.

EXIT CRITERIA:
- 7 Rust modules written + smoke tests passing.
- Spec-tag catalog (SPEC-TAGS.md) lists every extracted assertion.
- Preflight doctor returns green on the current workspace.
- phase3_oracle_wiring.md rendered.

ESCALATION:
- Spec sources contradict each other → STOP; the user must canonicalize one
  source-of-truth spec before Phase 3 can complete.
- A spec assertion has no falsifiable test surface (e.g., "ee should be useful")
  → flag in phase3_oracle_wiring.md as UNVERIFIABLE; require user to either
  refine the assertion or move it out of [SPEC-NNN] tags into a non-binding
  CHARTER section.
```

## Exit Criteria

- 7 Rust harness modules authored + smoke tests green.
- `docs/spec/SPEC-TAGS.md` enumerates every spec assertion.
- Preflight doctor green.
- `phase3_oracle_wiring.md` summary written.

## References

- [`../references/methodology/GREENFIELD-ADAPTATION.md`](../references/methodology/GREENFIELD-ADAPTATION.md) — the meta-pattern.
- [`../references/case-studies/eidetic_engine_cli.md`](../references/case-studies/eidetic_engine_cli.md) — worked example.
- [`../references/taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class`](../references/taxonomy/PROJECT-CLASSES.md)
- [`../references/patterns/05-SUBJECT-ORACLE-COMPARATOR.md`](../references/patterns/05-SUBJECT-ORACLE-COMPARATOR.md)
- [`../references/patterns/30-DIFFERENTIAL-V2-ENVELOPE.md`](../references/patterns/30-DIFFERENTIAL-V2-ENVELOPE.md)
- [`../references/patterns/55-INSTA-GOLDEN-SNAPSHOTS.md`](../references/patterns/55-INSTA-GOLDEN-SNAPSHOTS.md)
- [`../assets/property-test-templates/`](../assets/property-test-templates/)
- [`../assets/fuzz-target-templates/`](../assets/fuzz-target-templates/)
