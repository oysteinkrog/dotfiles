# Recipe — Multi-Binary Toolkit

Shape: a single repo produces multiple binaries that share state (e.g., `br` + `bv` both read `.beads/`; `cargo` + `cargo-deny` + `cargo-audit` share `Cargo.toml`).

The doctor architecture: **one shared `mutate()` chokepoint in a common library; each binary gets its own `<binary> doctor` subcommand calling into that library.**

---

## Architecture

```
crates/
├── doctor-core/                      ← shared library
│   ├── src/
│   │   ├── mutate.rs                 ← THE chokepoint (lives here, not in any binary)
│   │   ├── capabilities.rs           ← per-binary capabilities builder
│   │   ├── runtime.rs                ← run-id, run-dir, actions.jsonl emitter
│   │   ├── ops.rs                    ← Op enum
│   │   └── lock.rs                   ← cross-binary advisory lock
│   └── Cargo.toml
├── br/                               ← binary 1
│   ├── src/
│   │   ├── main.rs
│   │   └── doctor/
│   │       ├── mod.rs                ← `<br> doctor` subcommand wiring
│   │       ├── detectors_state_files.rs
│   │       ├── fixers_state_files.rs
│   │       └── ...
│   └── Cargo.toml
└── bv/                               ← binary 2 (same shape)
    └── ...
```

`doctor-core` exports:

```rust
pub mod mutate;
pub mod capabilities;
pub mod runtime;
pub mod ops;
pub mod lock;

pub use mutate::{mutate, MutateContext, ActionResult};
pub use ops::Op;
pub use capabilities::{Capabilities, DetectorSpec, FixerSpec};
```

Each binary's `Cargo.toml`:

```toml
[dependencies]
doctor-core = { path = "../doctor-core" }
```

---

## Cross-binary state sharing

When `br doctor --fix` and `bv doctor --fix` could touch the same file (e.g., `.beads/issues.jsonl`), the **shared lock** in `doctor-core::lock` serializes them.

```rust
// doctor-core/src/lock.rs
use std::path::Path;
use fs2::FileExt;

pub struct DoctorLock {
    file: std::fs::File,
    path: std::path::PathBuf,
}

impl DoctorLock {
    pub fn acquire(repo_root: &Path, ttl_seconds: u64) -> Result<Self, AcquireError> {
        let lock_dir = repo_root.join(".doctor");
        std::fs::create_dir_all(&lock_dir)?;
        let lock_path = lock_dir.join(".doctor.lock");
        let file = std::fs::OpenOptions::new()
            .create(true).read(true).write(true).open(&lock_path)?;
        match file.try_lock_exclusive() {
            Ok(()) => Ok(Self { file, path: lock_path }),
            Err(_) => Err(AcquireError::Held),
        }
    }
}

impl Drop for DoctorLock {
    fn drop(&mut self) {
        let _ = self.file.unlock();
        // Per AGENTS.md no-delete: the lockfile is NOT deleted on drop;
        // it stays as a marker. Next acquirer sees it but the OS-level
        // lock is gone.
    }
}
```

Both `br` and `bv` acquire the SAME `.doctor/.doctor.lock` before mutating. They serialize naturally.

---

## Per-binary capabilities, cross-referenced

Each binary's `capabilities --json::siblings[]` lists the others. An agent can discover the toolkit by querying any one:

```jsonc
// br doctor capabilities --json
{
  "schema_version": "1.0",
  "tool": "br",
  "doctor_contract_version": "1.0",
  "siblings": [
    {"name": "bv", "doctor_subcommand": "bv doctor", "shared_write_scopes": [".beads"]}
  ],
  "subsystems": ["state_files", "configs", "schemas"],
  "detectors": [...],
  "fixers": [...],
  ...
}
```

```jsonc
// bv doctor capabilities --json
{
  "schema_version": "1.0",
  "tool": "bv",
  "siblings": [
    {"name": "br", "doctor_subcommand": "br doctor", "shared_write_scopes": [".beads"]}
  ],
  ...
}
```

A tool-aware agent can call `br doctor capabilities --json | jq '.siblings[].doctor_subcommand'` and discover `bv doctor` exists; can then run BOTH for full coverage.

---

## Cross-binary version skew (the headline FM class)

```
fm-multi-binary-version-skew
  severity: P1
  symptoms:
    - br is 0.4.7 but bv is 0.4.5
    - bv writes a new `metadata` field in beads.jsonl that br 0.4.5 doesn't recognize
    - br mutates the same field with old semantics, corrupting bv's writes
  detector:
    Read each binary's --version. Cross-reference against doctor_contract_version.
    If contract versions differ across siblings, emit P1.
  fixer:
    Refuse — auto-fix would require reinstalling a binary the user controls.
    Listed under capabilities::manual_remediations:
      "Run `cargo install --path crates/bv` (or your installer) to bring bv up to br's version."
  fixture:
    Install br 0.4.7, bv 0.4.5; assert detector emits the finding;
    upgrade bv; assert detector clears.
```

---

## Per-run scorecard slicing

Per-binary scorecard slicing is a recipe-level requirement, not a current `scripts/scorecard.py render` flag. Until native slicing exists, keep the `tool` field on each `failure_mode_scores.jsonl` row and render per-binary scorecards from filtered workspaces (for example, a temporary workspace containing only rows where `tool == "br"`). The intended overall aggregate is a binary-weighted average:

```
overall_aggregate = sum_over_binaries(binary_aggregate × binary_weight) /
                    sum_over_binaries(binary_weight)
```

Default `binary_weight = 1.0` per binary. The user can override (e.g., set `bv` to 0.3 if it's a less-critical viewer of the data).

---

## Phase 4 fan-out for multi-binary

Phase 4 dispatches one implementer **per (binary, subsystem) pair**. Agent Mail file reservations prevent two implementers (one for `br`, one for `bv`) from racing on `crates/doctor-core/src/mutate.rs` — they coordinate via thread `doctor-<pass>-impl-shared-mutate` to land changes serially.

The synthesizer in Phase 3 produces a `cross_binary_concerns.md` listing every shared file and which binary "owns" it. The owner does the actual implementation; siblings consume the shared API.

---

## Common pitfalls

- **Two `mutate()` definitions**, one in each binary. Avoid: put `mutate()` in `doctor-core`. The validator catches duplicate definitions.
- **Different exit-code dictionaries** across binaries. They MUST be identical (or proper supersets). The agent shouldn't have to guess "what does exit 4 mean from `bv`?" — it's the same as `br`.
- **Independent run-artifact directories** per binary. Don't — share `.doctor/runs/<run-id>/` across all binaries in the toolkit. The `actions.jsonl` lines record `tool: "br"` vs. `tool: "bv"`.
- **Skipping the cross-binary sibling check.** A `<br> doctor capabilities --json` that doesn't list `bv` is incomplete; agents won't discover the second tool.
