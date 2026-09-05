# CHANGELOG — rust-undefined-behavior-exorcist skill

Versioning is content-driven. The live website has numeric versions; this file
keeps the agent-facing history in the skill package itself so future agents can
understand why the workflow changed without mining git first.

---

## 2026.05.16-1 — current-Miri flag correction

### Fixed

- Removed `-Zmiri-check-number-validity` from the taught Miri matrix, CI
  template, generated runbook snippet, and axis-diff artifact naming because
  current nightly Miri rejects the flag before tests run.
- Clarified that plain Miri catches invalid enum/scalar value UB on current
  nightlies, while MSan remains the fallback for uninitialized-memory cases
  where Miri is not enough.

## 2026.05.15-4 — changelog and package consistency

### Added

- Added this in-package changelog so the UB skill has the same local revision
  history ergonomics as `rust-unsafe-code-exorcist`.
- Tracked `scripts/syn-walkers/Cargo.lock`, matching the manifest and making
  syn-walker helper builds reproducible.

### Fixed

- Replaced the remaining scaffolded `aliasing` and `validity` syn-walker
  binaries with real heuristic sweeps. The walkers now report shared-to-mutable
  pointer casts, mutable raw-pointer mutation sites, unchecked initialization,
  questionable `mem::zeroed`, raw-slice construction, UTF-8 unchecked conversion,
  and `unreachable_unchecked` sites for follow-up proof.
- Fresh-eyes follow-up: aligned the zero-validity helper with its contract so
  raw pointer types are not incorrectly reported as invalid `mem::zeroed`
  candidates, including qualified raw-pointer target types.
- Fresh-eyes follow-up: tightened validity walker callee matching to use AST
  path segments, avoiding substring matches while catching directly imported
  hazards such as `from_raw_parts(...)`.
- Fresh-eyes follow-up: pruned generated/build directories from syn-walker
  traversal so running a walker at a project root does not accidentally scan
  `target/`, `node_modules/`, or similar heavy output trees.
- Fresh-eyes follow-up: made the transmute walker emit JSON through
  `serde_json`, avoid substring false positives for helper names containing
  `transmute`, normalize generic-pair spacing, and taught the data-race walker
  to recognize fully-qualified `Send` / `Sync` paths.
- Updated the syn-walkers README so it no longer tells agents the shipped
  binaries are stubs to be filled in later.

## 2026.05.15-3 — public-package hardening and no-worktree harmonization

### Added

- Added `assets/disclosure-email-template.md` for private maintainer disclosure
  of confirmed UB.

### Changed

- Harmonized the UB skill around the same no-git-worktree invariant as the
  unsafe-code skill: remediation happens in the active checkout, while
  historical release checks use non-git archive snapshots under the audit
  workspace.
- Normalized placeholder command snippets, transcript fences, and path examples
  so generated docs validate cleanly and are easier for terminal agents to
  follow.
- Tightened disclosure, remediation, soak-design, semgrep, triangulation, and
  operator-library guidance.

### Fixed

- Hardened install, preflight smoke-test, Miri unsupported extraction,
  convergence tracking, and operator validation helpers with clearer fail-closed
  behavior and less private-tool leakage.

## 2026.05.15-2 — Miri verdict completeness

### Fixed

- Required complete Miri axis verdict coverage before accepting an axis
  comparison.
- Treated unsupported, missing, or ambiguous Miri output as inconclusive instead
  of passing or failing a UB finding prematurely.
- Hardened Miri axis diffing and archive checks so malformed or partial inputs
  fail loudly.

## 2026.05.15-1 — helper ergonomics and phase validation

### Added

- Added the subagent kernel-passing convention so spawned agents inherit the
  same invariant set and do not drift from the UB taxonomy.
- Added audit-dir bootstrap hardening, preflight smoke tests, phase validation,
  Miri axis diffing, final-artifact authoring, and remediation-executor guidance.
- Added advanced UB detectors for surfaces the standard sweep misses.

### Fixed

- Added uniform `-h` / `--help` handling across the shell and Python helper
  scripts so agents can discover usage without reading each file.

## 2026.05.14-1 — initial public package

### Added

- Published the full 12-phase UB audit pipeline with corpus, taxonomy, operator
  library, artifact contracts, remediation principles, disclosure guidance, and
  bead handoff workflow.
- Added primary-source quote banks, session kickoff templates, a triangulated
  kernel, and references for bisection, backporting, validation, hidden
  barriers, project types, and release-forward remediation.
- Shipped scripts for Miri, sanitizers, loom, fuzzing, Kani, ast-grep pattern
  sweeps, syn-based walkers, runbook generation, toolchain installation, corpus
  validation, and skill self-testing.
- Added specialized subagents for Miri, sanitizers, fuzzing, loom, Kani,
  disclosure, runbooks, bisection, remediation architecture, static sweeps, and
  final synthesis.
