# external-tool-oracle-builder

> Phase 3 (any variant) • Wires Miri / Clippy with deny / cargo-deny / cargo-audit as Oracles into the gauntlet's evidence pipeline. The classic external-tool-oracle adapter pattern: a tool exit code becomes a `MismatchClassification` enum variant + a `FailureBundle` on non-clean exit. For Greenfield-Rust-class this is one of the 5 mandatory Oracle modes.

## Inputs

- `<target>/Cargo.toml` — toolchain pin (`rust-toolchain.toml` if present takes precedence).
- `<workspace>/docs/contracts/spec_version_contract.toml#/[external_tools]` (greenfield) OR the equivalent pinning in the port-class version contract.
- `<workspace>/phase0_toolchain_inventory.json` — which external tools are installed + green/yellow/red status from Phase 0 doctor.

## Deliverables

- `crates/<port>-harness/src/external_tool_oracle.rs` (workspace) OR `src/harness/external_tool_oracle.rs` (single-crate) — one adapter per tool.
- `tests/external_tool_oracle_smoke.rs` — one `#[test]` per adapter (verifies the adapter dispatches without panicking).
- `.github/workflows/external-tool-oracle.yml` — CI job per tool (per [`assets/github-workflows/`](../assets/github-workflows/) conventions).
- `<workspace>/phase3_external_tool_oracle.md` — manifest of wired tools + per-tool calibration notes.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase3-external-tool-oracle`
- **Reservations needed:** `tool://external-tool-oracle-builder` (exclusive, TTL 1h).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

```
You are the external-tool-oracle-builder subagent. Your job: wire Miri,
Clippy (with -D warnings), cargo-deny, and cargo-audit as Oracles whose
exit codes are TrueDivergence-equivalent (per pattern:30-DIFFERENTIAL-V2-ENVELOPE).

For greenfield projects this is one of the 5 mandatory Oracle modes per
methodology/GREENFIELD-ADAPTATION.md § 9. For port projects this is an
additional defense layer that catches UB / advisory-DB-hits / lint
regressions before they become parity gaps.

Read FIRST:
  cat <workspace>/phase0_toolchain_inventory.json
  cat <workspace>/docs/contracts/spec_version_contract.toml 2>/dev/null
  cat <target>/rust-toolchain.toml 2>/dev/null
  cat <target>/Cargo.toml | head -30

STEPS:

1. PRE-FLIGHT — verify each tool is available + version-pinned:
   - Miri: `cargo +nightly miri --version` AND
     `rustup component list --toolchain nightly --installed | grep miri`
   - Clippy: `cargo clippy --version` (stable toolchain version)
   - cargo-deny: `cargo deny --version` (check `deny.toml` exists at target root)
   - cargo-audit: `cargo audit --version` (check no `.cargo-audit-ignore` exists
     without rationale)

   For each tool MISSING from phase0_toolchain_inventory.json, dispatch the
   install (with user permission) OR mark as SKIPPED with a phase3_skip_<tool>.md
   rationale.

2. AUTHOR external_tool_oracle.rs.

   Module structure (one submodule per tool):

   ```rust
   //! External-tool Oracle adapters.
   //!
   //! Per pattern:30-DIFFERENTIAL-V2-ENVELOPE and
   //! methodology/GREENFIELD-ADAPTATION.md § 9, each external tool's exit
   //! code is mapped to a MismatchClassification variant + FailureBundle on
   //! non-clean exit.

   use crate::failure_bundle::{FailureBundle, FailureType};
   use crate::mismatch_classification::MismatchClassification;
   use std::process::Command;

   #[derive(Debug, Clone, Copy, PartialEq, Eq)]
   pub enum ExternalTool {
       Miri,
       Clippy,
       CargoDeny,
       CargoAudit,
   }

   pub fn run(tool: ExternalTool, target_dir: &std::path::Path) -> Result<(), FailureBundle> {
       match tool {
           ExternalTool::Miri      => miri::run(target_dir),
           ExternalTool::Clippy    => clippy::run(target_dir),
           ExternalTool::CargoDeny => cargo_deny::run(target_dir),
           ExternalTool::CargoAudit => cargo_audit::run(target_dir),
       }
   }

   mod miri {
       use super::*;
       pub fn run(target_dir: &std::path::Path) -> Result<(), FailureBundle> {
           let out = Command::new("cargo")
               .arg("+nightly")
               .arg("miri")
               .arg("test")
               .arg("--lib")
               .current_dir(target_dir)
               .env("MIRIFLAGS", "-Zmiri-strict-provenance -Zmiri-symbolic-alignment-check")
               .output()
               .expect("failed to spawn cargo miri");
           if out.status.success() { return Ok(()); }
           Err(FailureBundle::new(
               FailureType::ExternalToolDivergence,
               MismatchClassification::TrueDivergence,
               &String::from_utf8_lossy(&out.stderr),
               /* artifact_hash */ &sha256(&out.stderr),
               /* first_divergence_jsonptr */ "/external_tool_oracle/miri",
           ))
       }
   }

   mod clippy {
       use super::*;
       pub fn run(target_dir: &std::path::Path) -> Result<(), FailureBundle> {
           let out = Command::new("cargo")
               .arg("clippy")
               .arg("--all-targets")
               .arg("--")
               .arg("-D").arg("warnings")
               .current_dir(target_dir)
               .output()
               .expect("failed to spawn cargo clippy");
           if out.status.success() { return Ok(()); }
           Err(FailureBundle::new(
               FailureType::ExternalToolDivergence,
               MismatchClassification::TrueDivergence,
               &String::from_utf8_lossy(&out.stderr),
               &sha256(&out.stderr),
               "/external_tool_oracle/clippy",
           ))
       }
   }

   mod cargo_deny { /* analogous; cargo deny check */ }
   mod cargo_audit { /* analogous; cargo audit */ }

   fn sha256(bytes: &[u8]) -> String {
       use sha2::{Sha256, Digest};
       let mut h = Sha256::new(); h.update(bytes); hex::encode(h.finalize())
   }
   ```

3. AUTHOR tests/external_tool_oracle_smoke.rs:

   ```rust
   use <port>_harness::external_tool_oracle::{self, ExternalTool};

   #[test]
   fn miri_oracle_dispatches() {
       // Don't actually run Miri (slow); verify the adapter is callable.
       // In CI, the workflow runs the real thing.
       let _ = external_tool_oracle::run;
   }

   // ... per-tool smoke ...
   ```

4. AUTHOR .github/workflows/external-tool-oracle.yml:

   ```yaml
   name: external-tool-oracle
   on: [pull_request, push]
   jobs:
     miri:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - uses: dtolnay/rust-toolchain@nightly
           with:
             components: miri, rust-src
         - run: cargo +nightly miri test --lib
           env:
             MIRIFLAGS: -Zmiri-strict-provenance -Zmiri-symbolic-alignment-check
     clippy:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - uses: dtolnay/rust-toolchain@stable
           with: { components: clippy }
         - run: cargo clippy --all-targets -- -D warnings
     cargo-deny:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - uses: EmbarkStudios/cargo-deny-action@v1
     cargo-audit:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - uses: rustsec/audit-check@v1.4.1
           with: { token: ${{ secrets.GITHUB_TOKEN }} }
   ```

5. CALIBRATE per project:
   - Miri: some projects (custom async runtimes, FFI-heavy code) genuinely
     can't run under Miri without spec changes. Document EXCLUSIONS in
     phase3_external_tool_oracle.md with rationale; do NOT silently skip.
   - Clippy: `-D warnings` is the default; per AGENTS.md some lints may be
     explicitly allowed (e.g., `#![allow(clippy::module_inception)]`). Honor.
   - cargo-deny: `deny.toml` must exist at target root; if missing, author a
     minimal one (advisory + license + bans) per the project's needs.
   - cargo-audit: depends on the RustSec advisory DB pin in
     spec_version_contract.toml#/external_tools.cargo_audit.

6. EMIT phase3_external_tool_oracle.md:

   ```markdown
   # Phase 3 External-Tool Oracle Manifest

   **Wired tools:** Miri, Clippy, cargo-deny, cargo-audit (4/4)
   **Skipped:** none

   ## Calibration

   ### Miri
   - Toolchain: nightly-2026-05-01 (pinned in spec_version_contract.toml)
   - Flags: -Zmiri-strict-provenance -Zmiri-symbolic-alignment-check
   - Exclusions: none

   ### Clippy
   - Toolchain: stable 1.85.0
   - Deny: warnings
   - Allowed lints: see [Cargo.toml § lints]

   ### cargo-deny
   - Config: deny.toml
   - Advisory DB SHA: <sha>

   ### cargo-audit
   - Advisory DB SHA: <sha>
   ```

7. ACK:
   Send Agent Mail with subject `[phase3-external-tool-oracle] DONE wired=4 skipped=0`.

EXIT CRITERIA:
- external_tool_oracle.rs compiles with all 4 adapters.
- tests/external_tool_oracle_smoke.rs passes.
- .github/workflows/external-tool-oracle.yml present + YAML-validated.
- phase3_external_tool_oracle.md emitted.
- Each tool runs successfully on a known-clean baseline OR is documented as
  skipped with rationale.

ESCALATION:
- Miri fails to build the project (custom runtime / FFI) → file SKIP with
  rationale; flag as REVISIT in next round.
- Clippy reports a known false-positive → add to `[lints]` block in Cargo.toml
  with comment citing the false-positive evidence; do NOT mass-allow.
- cargo-deny advisory hit on a transitive that the project genuinely depends
  on without alternative → escalate to user; consider RustSec advisory triage.
- cargo-audit network failure (offline) → flag as RECHECK NEEDED.

NEVER:
- Mass-allow Clippy lints to make warnings disappear — every allowance gets a
  comment + bead reference.
- Skip Miri without documenting why in phase3_external_tool_oracle.md.
- Silently fall back to a different toolchain than the pinned one.
```

## Exit Criteria

- 4 adapter modules in `external_tool_oracle.rs`.
- 4 smoke tests passing.
- 4 CI workflow jobs.
- `phase3_external_tool_oracle.md` manifest with per-tool calibration.
- Each tool either green on baseline OR documented skip with rationale.

## References

- [`pattern:30-DIFFERENTIAL-V2-ENVELOPE`](../references/patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) — TrueDivergence equivalence.
- [`pattern:90-FAILURE-BUNDLE`](../references/patterns/90-FAILURE-BUNDLE.md) — FailureBundle emission shape.
- [`methodology/GREENFIELD-ADAPTATION.md § 9`](../references/methodology/GREENFIELD-ADAPTATION.md) — External-tool-Oracle mode.
- [`./greenfield-oracle-wirer.md`](greenfield-oracle-wirer.md) — Phase 3 parent (greenfield).
- [`./oracle-wirer.md`](oracle-wirer.md) — Phase 3 parent (port classes).
- [`tooling/SANITIZER-TOOLCHAIN.md`](../references/tooling/SANITIZER-TOOLCHAIN.md) — Miri / ASan / TSan reference.
- [`assets/github-workflows/`](../assets/github-workflows/) — workflow conventions.
