# CHANGELOG — rust-unsafe-code-exorcist skill

Versioning is calendar-style (`YYYY.MM.DD-N`) since the skill is content-driven, not API-driven. Material changes to the classification kernel bump a `KERNEL_v.X.X` marker inside [CLASSIFICATION-RUBRIC.md](references/methodology/CLASSIFICATION-RUBRIC.md); cosmetic / additive changes don't.

Each audit run records the skill version that produced it (in `AUDIT_SUMMARY.md § Provenance`), so future audits can decide whether to invalidate cached judgments.

---

## 2026.05.15-3 — final active-checkout harmonization

### Fixed

- Added an explicit compatibility-path warning in `SKILL.md` so agents do not infer worktree permission from the two legacy filenames that still contain `worktree`.
- Hardened the Phase 8.5 post-merge verification instructions to inspect `git status --short` before branch switches or pulls, preserving dirty user/peer work in shared checkouts.
- Shortened the frontmatter description so the production sync validator accepts the skill while still advertising the no-worktree invariant.
- Replaced Claude-specific `AskUserQuestion` requirements in remediation prompts with agent-neutral user-input wording, so Codex and other local agents can follow the same flow without tool-name confusion.
- Clarified README and intake wording so first-time users and non-Claude agents see the same terminal-agent workflow rather than a Claude-only path.
- Fresh-eyes follow-up: aligned the installer log contract on `<audit-dir>/phase0/installs.log` and removed stale Claude-only prerequisite/fallback/testing wording.
- Fresh-eyes script audit: `diff-audit-vs-baseline.sh` now rejects malformed CLI arguments cleanly, and `generate-soundness-changelog.sh` fails closed instead of claiming success when the log insertion anchor is missing.
- Fresh-eyes artifact-contract cleanup: Phase 8 bead guidance now consistently points agents at `<audit-dir>/phase8_bead_commands.sh`, and risk-score documentation now matches the generated `<audit-dir>/risk-scores.json` artifact.

## 2026.05.15-2 — mock-code audit cleanup

### Fixed

- Added the real `scripts/classify-new.sh` helper referenced by CI integration docs. It scans PR diffs for newly-added unsafe-related Rust lines and emits tentative markdown or JSONL classifications instead of leaving a nonexistent script path.
- Hardened `scripts/generate-soundness-changelog.sh` so it no longer appends placeholder metrics when `AUDIT_SUMMARY.md` is missing. Missing summaries now fail closed unless the caller passes `--allow-incomplete`, and repeat runs are idempotent per audit dir.
- Removed ambiguous placeholder/stub wording from helper docs and agent prompts that could confuse future agents during self-audits.
- Removed private authoring-skill references from the public helper inventory, fallback docs, testing docs, and archetype language.
- Fresh-eyes follow-up: `scripts/check-skills.sh` now inventories `~/.codex/skills` as well as `~/.claude/skills` and project-local `.claude/skills`, preventing false "missing skill" reports for Codex-only installs.

## 2026.05.15-1 — agent ergonomics and self-test hygiene

### Fixed

- Made first-run install-path guidance portable across Claude and Codex skill locations. Entry points, subagent prompts, fast-track docs, cookbook recipes, testing docs, prerequisites, and platform notes now either use the actual skill directory or fall back from `~/.claude/skills/rust-unsafe-code-exorcist` to `~/.codex/skills/rust-unsafe-code-exorcist`.
- Replaced the hardcoded private-repo path in `SELF-TEST.md` with a portable `SKILL` resolver that tells agents exactly what to set if neither common install path exists.
- Corrected the `clone-and-bootstrap.sh` synopsis in `QUICK-REFERENCE.md` so value-taking flags show their required values.
- Made the bootstrap `git/info/exclude` example idempotent instead of appending duplicate `/.unsafe-audit/` lines on repeat runs.
- Hardened `scripts/self-test.sh` so Python syntax checks compile in memory instead of writing `__pycache__` artifacts under the skill tree, and made Markdown link scanning robust for paths with spaces.

## 2026.05.14-3 — remove git-worktree remediation flow

### Fixed

- Replaced the Phase 8.5 remediation path with an active-checkout protocol. Authorized refactors now happen in the active checkout, optionally on an ordinary branch, and the skill explicitly forbids `git worktree add`, per-cluster worktree directories, and secondary checkout copies.
- Updated the agent-facing spine (`SKILL.md`, operating modes, kickoff prompts, implementer prompt, checklist, CI template, incident templates, quick reference, glossary, and related subagent notes) so future agents no longer route audit-and-refactor or incident fixes through worktrees.

## 2026.05.14-2 — first-invocation feedback fixes + Phase 11 remediation

First-invocation results on `beads_rust` v0.2.10 (a project already at `forbid(unsafe_code)` with zero in-tree unsafe) surfaced bugs and UX rough edges. Fresh-eyes review of those fixes uncovered three additional pre-existing bugs that real-world script runs surfaced. This release addresses all of them, adds an end-of-audit user-gated remediation flow, and makes the auto-install offer explicit.

### Fixed

- **`scripts/cargo-tree-soundness.sh`** — no longer silently emits an empty report when `cargo geiger` is missing. Now detects the absence up-front, writes a clearly-flagged `## Status: DEGRADED` section with install instructions and a re-run command, exits 3, and logs the degraded state to stderr. (Highest-impact bug: for `dependency-soundness` / `forbid-soundness` modes, this script IS the headline artifact.)
- **`scripts/enumerate-unsafe.sh`** — multiple fixes:
  - `cargo expand` and `cargo geiger` invocations now tee their stderr to `<crate>__expand.stderr.log` / `<crate>__geiger.stderr.log` and emit a `<crate>__expand.failed` / `<crate>__geiger.failed` sentinel when they fail or produce empty output. Sentinels are cleared on subsequent successful runs.
  - Forces `RCH_DISABLED=1` around `cargo expand` so remote-compilation helpers can't silently intercept and return zero bytes.
  - **NEW**: `cargo expand` now iterates per-target (lib + each bin) instead of running once unqualified. Previous behavior failed silently on crates with both `[lib]` and `[[bin]]` (very common for CLI tools with a library API) because `cargo expand` errors out with "extra arguments to rustc can only be passed to one target."
  - **NEW**: post-expansion unsafe extraction no longer uses `ast-grep -p 'unsafe $$$'` (which doesn't parse as valid Rust syntax and silently returns `[]`). Replaced with a targeted regex `\bunsafe[[:space:]]+(fn|impl|trait|extern|\{)` that actually matches macro-emitted unsafe constructs.
- **`scripts/generate-inventory.mjs`** — usage message now explains that this script takes ONE arg (the audit dir) and explicitly contrasts with `enumerate-unsafe.sh` which takes TWO. Detects the common mistake of passing both and emits a remediation hint.
- **`assets/verify-forbid-soundness.sh.template`** — fresh-eyes review caught two parse-fallback bugs:
  - Empty grep result was hitting the FAILED branch instead of "?" (SKIP). Now distinguishes empty / non-numeric / "?" / 0 / N cases explicitly.
  - `CURRENT_TOTAL` could be `null` / empty / non-numeric on geiger schema drift; arithmetic comparison would error. Now normalizes null/empty to "?" and guards the comparison with numeric regex.
- **`SKILL.md` § Skill Bootstrap** — clarifies the ordering: create the in-project audit dir BEFORE running `check-skills.sh` / `install-toolchain.sh --check` (both reject `/tmp/...` paths via `audit-dir-guard.sh`). `check-prerequisites.sh` is the exception and can be run first.

### Added

- **SKILL.md § Phase 11 — Remediation Offer** — NEW user-gated phase after Phase 10. After `AUDIT_SUMMARY.md` is written, the agent presents findings and offers to fix them in six sub-flows: install missing toolchain components, file candidate beads via `br create`, apply (C) REFACTORABLE rewrites via the Phase 8.5 implementer, add `safe-only` feature flag for (B) sites, harden (A) SAFETY comments, wire `verify.sh` into CI. The agent NEVER applies fixes without explicit user authorization beyond the original `audit-only` permission. Each sub-flow documents its scope; `worktree-implementer.md` is reused as the legacy filename for (C) work. Output goes to `<audit-dir>/PHASE11_LOG.md`.
- **SKILL.md § Offering to install missing tools** — new subsection in the Bootstrap section making explicit that after `phase0_toolchain.json` is written, the agent asks the user whether to install missing components. Three options (install-all, install-mode-critical, skip-and-degrade) with `install-toolchain.sh` as the executor. Per-tool confirmation is mandatory; nothing is installed silently.
- **`assets/verify-forbid-soundness.sh.template`** — tailored `verify.sh` template for projects that already declare `#![forbid(unsafe_code)]`. Skips miri/loom/fuzz/mutants (which have nothing to verify on an unsafe-free crate) and replaces them with the eight checks that actually catch regressions: forbid attribute presence, Cargo lint table presence, zero `allow(unsafe_code)` overrides, zero source-level unsafe declarations, `cargo check`, `cargo clippy`, optional `cargo geiger` local + dep-side drift, optional `cargo expand` accounting (with categorical breakdown of compiler-emitted derive output), optional `safe-only` feature test, project tests. Configurable via `CRATE_ROOT_FILE`, `GEIGER_BASELINE_FILE`, `EXPAND_OTHER_BUDGET`, `RUN_TESTS` env vars.
- **`SKILL.md` § Mode Router** — new `forbid-soundness` mode row with explicit must-finish-with criteria. `detect-mode.sh` already emits this mode when it sees a top-level forbid; the documentation was lagging.
- **`SKILL.md` § Mode variants on the phase loop** — new `forbid-soundness` row explaining that Phases 4-6 collapse (no in-tree sites to classify or adversarially defeat) and the audit's value lives in dep characterization + drift detection.
- **`references/patterns/40-MACRO-GENERATED-UNSAFE.md` § Compiler-emitted derive output (rustc 1.97-nightly+)** — documents `unsafe impl ::core::clone::TrivialClone` and `unsafe { ::core::intrinsics::unreachable() }` emissions from built-in derives, with worked example from beads_rust (261,511-line expansion → 103 unsafe occurrences: 88 TrivialClone + 6 unreachable + 9 string/comment hits). Explains why these don't trip `#![forbid(unsafe_code)]` and how `verify-forbid-soundness.sh.template` accounts for them.

### Enhanced

- **`scripts/check-prerequisites.sh`** — "Modes you can run RIGHT NOW" now lists `forbid-soundness` as the first mode (most common for "good" Rust crates) and clarifies that `audit-only (full)`'s miri/cargo-geiger gating doesn't apply to forbid-soundness projects (those have nothing in-tree for miri to verify).
- **`SKILL.md` § Phase Loop diagram** — adds `Phase 11 REMEDIATION-OFFER` row pointing to the new section.

### Fresh-eyes round 2 (post-Phase 11 review)

A second review pass focused on agent ergonomics caught three more issues:

- **`AskUserQuestion` 4-option cap** — Phase 11's original prompt had 7 options. Restructured into a two-tier flow: Tier 1 picks overall posture (Apply-everything / Selective / Preparatory / Skip), Tier 2 drills down per sub-flow only if the user picked Selective. Mode-aware suppression for sub-flows with no actionable findings.
- **`verify-forbid-soundness.sh.template` hardcoded `src/lib.rs`** — would fail on binary-only crates. Now auto-detects `src/lib.rs` → `src/main.rs` → `cargo metadata` lookup, in that precedence order. Tested against synthetic binary-only fixture.
- **`install-toolchain.sh` lacked an agent-friendly non-interactive install mode.** Adding `echo y |` to bypass the prompt is unsafe because it hides per-tool review. Added `--install-confirmed` flag that bypasses the prompt EXPLICITLY (signaling that the caller asserts prior user authorization) and logs each install command to `<audit-dir>/phase0/installs.log`. Mutually exclusive with `--check`.

### Documentation tightening

- `Quick Start` clarifies that the audit dir is created AFTER user authorization (not automatically), and mentions the optional Phase 11 remediation phase.
- `30-Second Mental Model` notes the `forbid-soundness` fast-path for projects that already declare `#![forbid(unsafe_code)]`.
- `Project-Type Defaults` table adds a `Forbid crate` row pointing to the new PROJECT-TYPES.md section.
- `Skill Bootstrap` now defines the path placeholders (`<project>`, `<audit-dir>`, `<skill-dir>`) used throughout the document.
- `Pre-Flight & End Checklist` adds a Phase 11 checkbox covering remediation log + summary update + active-checkout isolation invariant.

### Run-on-the-canary

All fixes were validated by re-running the modified scripts against `beads_rust` v0.2.10 (a `forbid-soundness` exemplar) AND a synthetic binary-only test fixture after each batch of edits. The new sentinel files surfaced two pre-existing bugs that had been silently masking signal (cargo expand multi-target failure, ast-grep `unsafe $$$` non-match) — both fixed in the same release. See `/data/projects/beads_rust/.unsafe-audit/SKILL_FEEDBACK.md` for the source feedback document.

---

## 2026.05.14 — gap-closure round 2

Closes the remaining gaps surfaced by re-reading the original prompt against the v4 implementation.

### Added

- **Pattern bundle `25-INTRINSICS-AND-COMPILER-HINTS.md`** — dedicated coverage of `core::intrinsics::*`, `core::hint::*_unchecked`, `core::ptr::read/write/copy/swap/drop_in_place`. Closes a category the prompt named explicitly that was previously dispersed across other bundles.
- **Pattern bundle `27-UNSAFECELL-PATTERNS.md`** — manual `UnsafeCell` patterns (UC-1..UC-7): Cell / RefCell / OnceCell graduations, lock primitives, single-thread escape hatches, Pin interactions, Sync impl audit. Closes another named category.
- **`REJECTED-PATTERNS.md`** (methodology) — 18 entries `[R-001]..[R-018]` cataloging refactors we tried and explicitly chose NOT to land, with measured rationale + "re-litigate if" conditions. The negative-space companion to `EXEMPLAR-CATALOG.md`.
- **`HYBRID-CLASSIFICATIONS.md`** (methodology) — protocol for sites that mix bucket characteristics (e.g., (A) FFI shim with (B) inner perf code).
- **`INVENTORY-SCHEMA.md`** (methodology) — canonical schema doc for `unsafe-inventory.jsonl`. Every field, every `kind` enum value, the lifecycle, validation queries.
- **`FORBID-SOUNDNESS-MODE.md`** (methodology, via task 49) — overlay for projects already enforcing `#![forbid(unsafe_code)]`.
- **`scripts/clone-and-bootstrap.sh`** — automate GitHub-URL → cloned project → in-project audit dir.
- **`scripts/self-test.sh`** — meta-pass validating the skill installation: validators + syntax + link resolution + orphan checks + slop scan.
- **`scripts/publish-cargo-vet-certs.sh`** — convert dep-soundness findings into `cargo vet certify` commands.
- **`assets/audit-dir-gitignore.template`** — `.gitignore` dropped into newly-created audit dirs.
- **`assets/audit-dir-readme.template`** — `README.md` dropped into newly-created audit dirs explaining the artifact layout to maintainers.
- **`COOKBOOK.md` Recipe 11.5** — paste-ready "audit a project from a GitHub URL" recipe with monorepo / ref / shallow / SSH-auth handling.

### Enhanced

- **`scripts/run-miri.sh`** — now runs `cargo +nightly miri run --bin <name>` for every binary target after the test phase. Closes the explicit Phase-7 deviation from the original prompt.
- **`scripts/enumerate-unsafe.sh`** — new ast-grep / ripgrep patterns for `UnsafeCell`, `core` / `std` intrinsics, unchecked hints, pointer reads/writes/copies, raw pointer declarations, and const/mut raw pointer casts. Closes the "raw pointer creation/deref" + "manual UnsafeCell" + "intrinsics" enumeration gaps named in the original prompt.
- **`scripts/generate-inventory.mjs`** — `classifyKind` now recognizes the new kinds and normalizes to schema-canonical names; exact duplicate rows from fallback-mode variant patterns are collapsed before stable IDs are assigned.
- **`PHASES.md`** — Phase 3 description explicitly names "invariant chokepoint" (the term the original prompt used) for the safe-wrapper-per-cluster construct. Phase 4 convergence-proof artifact is now explicitly named (`convergence-proof-pass-N.md` + `convergence-proof-FINAL.md`).
- **`CLASSIFICATION-RUBRIC.md`** — links to `HYBRID-CLASSIFICATIONS.md` for the two-bucket-characteristic case. Kernel markers preserved (no breaking changes inside the kernel-bounded region).
- **`subagents/synthesizer.md`** — uses the "invariant chokepoint" terminology.
- **`subagents/bead-converter.md`** — gained a "Handing off to your swarm" section explaining how to dispatch bead-graph work via `br ready` + `bv --robot-triage` + MCP Agent Mail. Includes a concrete JSONL example of the resulting bead graph.
- **`subagents/adversarial-reclassifier.md`** — consults `REJECTED-PATTERNS.md` before proposing alternatives; refuses duplicate refactor proposals already-rejected with measured rationale.
- **`assets/intake-prompt.md`** — Q1 (target project path) expanded from one-line to concrete protocol: HTTPS / SSH URL handling, `--ref`, `--subdir`, `--shallow`, monorepo handling.
- **`GLOSSARY.md`** — adds "invariant chokepoint" definition.
- **`PRE-EXISTING-UB-PROTOCOL.md`** — adds triage scorecard mapping (severity × exploitability × fix-cost) to bead priority.
- **`TRIANGULATION.md`** — adds cost projection per-site / per-audit / per-model.
- **`PREREQUISITES.md`** + **`intake-prompt.md`** — strengthened `ubs` install path with concrete `jsm install ubs` + curl-fallback sequence.
- **`SKILL-FALLBACKS.md`** — clearer "where skill packages come from" section pointing at the jsm + jeffreys-skills.md ecosystem.
- **`pin-projection-auditor.md`** + **`audit-pin-projection-soundness.sh`** — cross-link "Pair:" sections so the doc and script find each other.
- **`95-INDEX.md`** — fills in previously-missing pattern bundles in the by-project-shape table (30-CONCURRENCY, 90-OPERATIONS, 100-CRYPTOGRAPHY-AUDIT, 130-TAGGED-POINTER-MIGRATION).

### Fixed

- `generate-inventory.mjs` `classifyKind` had buggy regex patterns (e.g., `/^unsafefn/i` never matched `unsafe_fn` due to the underscore). Replaced with exact-string equality.
- Fresh-eyes pass on Phase 1 enumeration fixed one-based line normalization, project-relative file paths, duplicate `cargo expand` source rows, `geiger_count: 0` for safe hazard-signal rows, `pub unsafe fn` / extern-block detection, `std::ptr::*` detection, and `as *mut T` raw-pointer casts.
- Fresh-eyes pass on artifact containment fixed project-relative paths for `.unsafe-audit-*` and nested drift audit dirs, schema-relative expanded-row paths, custom audit-dir `.gitignore` hints, and the installed `verify.sh <project>` argument contract.

---

## 2026.05.13 — v4 (newcomer-onboarding pass)

Audited the skill against a newcomer-experience rubric and the AGENTS.md "agent-ergonomic skills" feedback. Added the orientation surface needed for a first-time user to land an audit.

### Added

- `README.md` at skill root — human-friendly orientation.
- `references/methodology/PREREQUISITES.md`, `GLOSSARY.md`, `PLATFORM-NOTES.md`, `MENTAL-MODEL.md`, `QUICK-REFERENCE.md`, `COOKBOOK.md`, `TROUBLESHOOTING.md`, `FAST-TRACK-MODES.md`, `ARCHETYPES.md`, `TESTING.md`, `DECISION-TREE.md`, `EXAMPLES.md`, `ANTI-PATTERNS-FOR-USERS.md`, `MODEL-DIFFERENCES.md`.
- `scripts/check-prerequisites.sh` — preflight check before any audit invocation.

---

## 2026.05.13 — v3 (cross-cutting capabilities)

Added the v3 capabilities for projects with ongoing audit needs.

### Added

- Continuous mode (`CONTINUOUS-MODE.md`, `cron-drift-check.sh`).
- Risk scoring (`RISK-SCORING.md`, `compute-risk-score.mjs`).
- Soundness debt dashboard (`SOUNDNESS-DEBT.md`).
- CI integration (`CI-INTEGRATION.md`, `gh-actions-auditor.yml.template`).
- Differential audit (`DIFFERENTIAL-AUDIT.md`, `diff-audit-vs-baseline.sh`).
- Inverse audit (`INVERSE-AUDIT.md`, `inverse-auditor.md`).
- Soundness archeology (`SOUNDNESS-ARCHEOLOGY.md`, `git-history-soundness-mine.sh`, `archeologist.md`).
- Cross-crate contracts (`CROSS-CRATE-CONTRACTS.md`, `contract-verifier.md`).
- Audit-driven test generation (`AUDIT-DRIVEN-TEST-GEN.md`, `test-generator.md`).
- SECURITY.md generation (`SECURITY-MD-GENERATION.md`, `security-md-author.md`).
- Project-level soundness log (`PROJECT-LEVEL-CHANGELOG.md`).
- Incident forward-propagation (`INCIDENT-FORWARD-PROPAGATION.md`).
- Domain-specific overlays (`DOMAIN-MODES.md`, `100-CRYPTOGRAPHY-AUDIT.md`, `130-TAGGED-POINTER-MIGRATION.md`).

---

## 2026.05.13 — v2 (the 10-phase + 7-mode kernel)

The structural exemplar pass: full 10-phase loop, all 7 operating modes, the polish bar, the operator library.

### Added

- All 10 phases in `PHASES.md` with exit criteria + exact prompts.
- All 7 operating modes in `OPERATING-MODES.md`.
- The 24 operators in `OPERATORS.md`.
- `CLASSIFICATION-RUBRIC.md` with the `KERNEL_v1.0` markers.
- Per-site templates in `assets/`.
- Polish bar (`POLISH-BAR.md`).
- Source corpus structure (`SOURCE-CORPUS.md`, `EXEMPLAR-CATALOG.md` with 43 `[E-NNN]` entries).
- All 32 subagents in `subagents/`.
- All 30+ scripts in `scripts/`.

---

## 2026.05.13 — v1 (initial skill scaffold)

Initial commit. SKILL.md + minimal references + the first cut at the methodology kernel.
