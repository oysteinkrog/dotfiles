---
name: harness-builder
description: Phase 9 — build verify.sh and CI matrix entry from the audit's findings.
tools:
  - Read
  - Write
  - Edit
  - Bash
---

# Harness Builder Subagent

You produce two files:

1. `<audit-dir>/verify.sh` — composite harness (template at `assets/verify.sh.template`).
2. `<audit-dir>/ci-matrix.yml` — GitHub Actions matrix (template at `assets/ci-matrix.yml.template`).

## Inputs

- `<audit-dir>/phase0_toolchain.json` — which tools are available locally.
- `<audit-dir>/audit/classification/` — (B) sites whose `safe-only` feature must be in the matrix.
- `<audit-dir>/audit/plans/` — concurrency-touching (C) sites that need loom; new public surfaces that need fuzz targets.

## Producing verify.sh

Start from `assets/verify.sh.template`. Adjust:

- Remove steps for tools the project doesn't need (e.g., loom if no concurrency-touching rewrites).
- Add the project's existing test invocations.
- Set `PROJECT_DIR` correctly (the project repo, not the audit dir).
- Make it executable: `chmod +x verify.sh`.

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT_DIR="${AUDIT_DIR:-$SCRIPT_DIR}"

infer_project_dir() {
  if [ -f "$AUDIT_DIR/phase1/project-root.txt" ]; then
    sed -n '1p' "$AUDIT_DIR/phase1/project-root.txt"
    return
  fi
  local cur
  cur="$(realpath "$AUDIT_DIR/..")"
  while [ "$cur" != "/" ]; do
    if [ -f "$cur/Cargo.toml" ]; then
      printf '%s\n' "$cur"
      return
    fi
    cur="$(dirname "$cur")"
  done
  realpath "$AUDIT_DIR/.."
}

PROJECT_DIR="${PROJECT_DIR:-${1:-$(infer_project_dir)}}"

LOG="$AUDIT_DIR/audit/phase9/verify.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

cd "$PROJECT_DIR"

echo "==> [1/9] cargo +nightly miri test"
cargo +nightly miri test --workspace --all-features

# ... rest of the harness ...
```

The harness MUST:
- Run miri (both default + strict-provenance).
- Run cargo-careful.
- Run loom IF the project has loom suites.
- Run cargo-fuzz IF the project has fuzz targets.
- Run cargo-mutants on the refactored modules.
- Run cargo-geiger and diff vs the Phase 1 baseline: legacy `phase1/cargo-geiger.json` or current per-crate `phase1/*__geiger.json`.
- Run `cargo test` under default features AND `--features safe-only --no-default-features`.

## Producing the CI matrix

Start from `assets/ci-matrix.yml.template`. Adjust:

- Matrix axes match the project's shipped targets.
- Job names match the project's repo conventions.
- Add a `cron:` schedule for nightly fuzz / mutants (those are slow; run weekly).

The matrix MUST cover:

- `cargo test` for every (OS, rust, features) combination the project ships.
- `cargo +nightly miri test` as a single non-matrix job.
- `loom` as a single non-matrix job if applicable.
- `cargo +nightly fuzz` smoke (60s per target) as a single non-matrix job.
- `cargo +nightly geiger` delta check vs main as a PR-only job.

## Wiring tool prerequisites

Update audit-dir Cargo.toml fragments that the harness reads:

- Add `[features] safe-only = []` to every Cargo.toml that has a (B) site.
- Add `[target.'cfg(loom)'.dev-dependencies] loom = "0.7"` to every Cargo.toml that has a concurrency-touching (C) rewrite.
- Add `fuzz/` subdir scaffolding (via `cargo fuzz init`) for crates with new public surfaces.

For audit-and-refactor mode, these Cargo.toml changes propagate to the project repo via Phase 8.5 active-checkout edits. For audit-only mode, they live in the audit dir's plans as instructions.

## Constraints

- Do NOT modify the project repo (this is Phase 9; project-repo writes only happen in Phase 8.5 + later).
- All harness changes live in `<audit-dir>/`.
- The harness must be reproducible — every step has a fixed version pin (recorded in `phase0_toolchain.json`).
- The harness's exit contract: exit 0 only if all configured steps exit 0.

## Self-check

After producing the files, run the harness once in the audit dir as a dry-run:

```bash
bash <audit-dir>/verify.sh
```

If it fails, triage findings per [PHASES.md § Phase 9](../references/methodology/PHASES.md#phase-9--verification-harness) (IN-SCOPE → fix the plan; OUT-OF-SCOPE → file `pre-existing-ub-N`).

The dry-run is your validation that the harness actually does what it claims.
