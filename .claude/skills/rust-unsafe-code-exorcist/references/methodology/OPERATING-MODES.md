# OPERATING-MODES.md — Mode Definitions

The 7 modes share the same phase loop but differ in stop conditions, required artifacts, and whether they touch the project repo. Pick the smallest mode that fully covers the user's ask.

`scripts/detect-mode.sh` auto-suggests a mode based on heuristics; the user can override.

---

## `audit-only` (default)

**Use when.** Existing project; user wants a defensible report only.

**Phases.** 0 → 10 (all phases).

**Project-repo touch.** None. Every artifact lives in `<audit-dir>/`.

**Required deliverables.**
- `<audit-dir>/unsafe-inventory.jsonl`
- `<audit-dir>/audit/sites/<crate>/*.md`
- `<audit-dir>/audit/synthesis/{invariants,soundness-surface,refactor-clusters}.md`
- `<audit-dir>/audit/classification/site-<id>.md` per site
- `<audit-dir>/audit/plans/site-<id>.md` per site
- `<audit-dir>/.beads/` (bead graph committed)
- `<audit-dir>/verify.sh` (built but not wired into project CI)
- `<audit-dir>/REVIEWER_RESPONSES.md`

**Exit signal.** Audit dir committed; user receives `AUDIT_SUMMARY.md` summary line + a path to read.

---

## `audit-and-refactor`

**Use when.** User wants selected (C) refactors landed in the project repo, (B) feature-flagged, or (A) hardened, with reviewable active-checkout diffs. PRs are optional and use ordinary branches; git worktrees are forbidden.

**Phases.** 0 → 10 + **Phase 8.5 active-checkout refactor pass**.

**Project-repo touch.** Yes, but only AFTER Phase 8 bead conversion AND explicit user authorization. Workflow:

1. Phase 8 bead graph is generated as in `audit-only`.
2. The orchestrator confirms the active checkout with `git status --short` and preserves unrelated user/peer edits.
3. If PR flow is desired, the orchestrator creates an ordinary branch in the active checkout, e.g. `git -C <project> switch -c unsafe-exorcist/<cluster-id>`.
4. Refactor agents claim beads via `br update <id> --status=in_progress` and implement the approved plan in `<project>`.
5. Each authorized cluster/site becomes a focused diff; a PR is opened only if the user/repo workflow requests it. Phase 7 fresh-eyes runs against `<project>` before closeout.
6. The project's CI matrix is updated to include `safe-only` per the harness builder.

**Required deliverables.** Everything from `audit-only` PLUS:
- Focused commits or PRs for user-authorized refactor clusters/sites.
- CI matrix entry committed to project repo.
- `verify.sh` committed to project repo (or another user-approved project-local verifier path).
- Updated SAFETY comments per (A) site committed to project repo.

**Exit signal.** All user-authorized refactors are verified; CI/local gates are green; the user has commit hashes or PR links.

---

## `harden-incident`

**Use when.** A specific unsoundness was reported (CVE, miri finding from a user, prod crash linked to UB, fuzz finding from an external party).

**Phases.** 1 (scoped to blast radius) → 4 → 5 (scoped) → 7 → 8 → then expand to full `audit-only`.

**Project-repo touch.** Yes, for the incident scope. Refactor pass for the incident sites uses the active checkout, like `audit-and-refactor`; git worktrees are forbidden.

**Required deliverables.**
- Root-cause analysis (`<audit-dir>/incident-rca.md`) — what the bug was, how it was triggered, who's affected.
- Per-site plan + bead for every site in the blast radius.
- Regression test in the project repo pinned to the incident name (e.g., `tests/regression_cve_2026_NNNNN.rs`).
- Active-checkout commit or PR landing the fix.
- After the incident is closed: expand to full `audit-only` so the rest of the project is reviewed.

**Exit signal.** Incident-closing PR merged; regression test in main; full audit kickoff scheduled.

---

## `dependency-soundness`

**Use when.** The project itself is mostly safe but pulls in unsafe-heavy deps; the user wants a soundness-surface analysis of which dep-unsafe is reachable from the project's public API.

**Phases.** 1 (deps + local) → 3 (soundness-surface emphasis) → 4 → 5 (wrap-or-replace plans for deps; SAFETY hardening of project-side bridges) → 7 → 8 → 9.

**Project-repo touch.** Yes, but the changes are usually:
- Replace dep A with dep B (where B has less or audited unsafe).
- Wrap a dep's API in a stricter abstraction in our crate.
- File upstream issue / PR against the dep.

**Required deliverables.**
- `<audit-dir>/audit/synthesis/dep-soundness.md` listing every dep with `geiger > 0` AND a `pub` API path reaching it from this project.
- Per-dep wrapper plans where applicable.
- Upstream issues filed (with links recorded in `dep-soundness.md`).

**Exit signal.** Every reachable dep-unsafe is either (a) wrapped, (b) replaced, (c) filed upstream, or (d) explicitly justified by a (A)-style write-up in the project's docs.

---

## `verify-only`

**Use when.** Project already passed a prior audit; user wants the CI verification harness only.

**Phases.** 9 (build harness from existing audit) → 10 (review).

**Project-repo touch.** Yes — the harness needs to be wired into the project's CI.

**Required deliverables.**
- `verify.sh` in project repo.
- `.github/workflows/soundness.yml` (or equivalent) with the matrix entry for `safe-only`.
- One-page README about the harness and how to run it locally.
- A `pre-existing-ub` bead list if the harness surfaces anything new.

**Exit signal.** CI green; user has the harness running on every PR.

---

## `pre-release-soundness-gate`

**Use when.** Before cutting a public crate release.

**Phases.** 1 → 9 (full audit + harness), but with the bar set HIGHER: every (A) MUST have hardened SAFETY comments AND a clippy-or-similar lint catching caller-side violations.

**Project-repo touch.** Yes — for the SAFETY comments + lint config. No code rewrites unless Phase 4/6 finds something that must be (C).

**Required deliverables.**
- Everything from `audit-only`.
- Hardened SAFETY comments committed to project repo.
- `clippy.toml` updates per (A) site's proof obligation.
- `verify.sh` clean with `cargo +nightly geiger` delta ≤ 0 vs baseline.
- CI matrix green on default AND `safe-only`.

**Exit signal.** User can `cargo publish` with confidence; the audit summary is in the release notes.

---

## `dual-feature-migration`

**Use when.** Add a `safe-only` feature flag to a previously perf-only crate. Common case: a crate that's been pure-`unsafe` for SIMD throughout, where the user wants downstream-of-OSS-policy to have a safe build option.

**Phases.** 1 (scoped to perf-path) → 4 → 5 (B-only) → 7 → 8 → 9.

**Project-repo touch.** Yes — the feature flag, conditional compilation, and CI matrix all land in the project repo.

**Required deliverables.**
- Every site classified (B) has its safe-only branch committed.
- CI matrix entry committed.
- Per-target benches published (criterion + hyperfine + flamegraph for each target the crate ships).
- A README / CHANGELOG entry explaining the feature: when to use, what's the perf cost, how to opt in.

**Exit signal.** Default features still ship the perf path; `--features safe-only` builds clean; CI matrix green on both.

---

## `forbid-soundness`

**Use when.** Project already enforces `#![forbid(unsafe_code)]` at the crate root. The audit's value shifts to verifying the forbid is consistent across modules + auditing the transitive dep unsafe.

**Phases.** 1 (forbid-attribute map + standard enum) → 3 (dep-soundness focus) → 4 (per-dep, not per-site) → 5 (inherited contracts + dep swaps) → 7 (forbid-consistency check) → 8 → 9.

**Project-repo touch.** Read-only by default; refactor authorization optional for dep-swap PRs.

**Required deliverables.**
- `audit/phase1/forbid-attribute-map.md` showing every file's effective unsafe-policy.
- `audit/synthesis/inherited-contracts.md` — every dep with unsafe + reachable from `pub` + the contract this project inherits.
- Per dep-(B) candidate: swap evaluation OR rejection rationale.
- Per dep-(C) candidate: drafted upstream issue.
- CI check enforces the forbid (verified in `verify.sh`).

**Exit signal.** Forbid is consistent + every reachable dep has an inherited-contract entry + no `#![allow(unsafe_code)]` overrides exist (or each is justified + bead-filed).

Full protocol: [FORBID-SOUNDNESS-MODE.md](FORBID-SOUNDNESS-MODE.md).

---

## Auto-detection heuristics

`scripts/detect-mode.sh` looks at:

| Signal | Suggested mode |
|--------|----------------|
| Recent commit message contains "CVE" or "incident" | `harden-incident` |
| `Cargo.toml` has `[features] safe-only` already | `verify-only` (audit ratified) or `dual-feature-migration` (incomplete) |
| Project is a library crate, has `cargo publish` history, no recent breaking changes | `pre-release-soundness-gate` (if version bump is near) or `audit-only` |
| `geiger` count > 50, project is application not library | `audit-only` (likely a large refactor target) |
| `geiger` count low but `cargo tree | xargs -I{} cargo geiger {}` shows heavy unsafe in deps | `dependency-soundness` |
| `#![forbid(unsafe_code)]` at crate root | `forbid-soundness` |
| Default | `audit-only` |

The detector prints reasoning; the user confirms or overrides.

---

## Mode-to-deliverable matrix

| Deliverable | audit-only | audit-and-refactor | harden-incident | dep-soundness | verify-only | pre-release-gate | dual-feature |
|-------------|------------|--------------------|-----------------|--------------|-------------|-----------------|--------------|
| Inventory JSONL | ✓ | ✓ | scoped | ✓ | from prior | ✓ | scoped |
| Per-site write-ups | ✓ | ✓ | scoped | ✓ | from prior | ✓ | scoped |
| Synthesis | ✓ | ✓ | scoped | ✓ + dep | from prior | ✓ | scoped |
| Classification | ✓ | ✓ | scoped | ✓ | from prior | ✓ | scoped |
| Plans | ✓ | ✓ | scoped | ✓ | from prior | ✓ | scoped |
| Beads | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| verify.sh | audit-dir | project | project | project | project | project | project |
| CI matrix | audit-dir | project | project | project | project | project | project |
| PRs to project | none | optional ordinary branch | optional ordinary branch | optional ordinary branch | none | SAFETY-only | feature flag |
| `REVIEWER_RESPONSES.md` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Active-checkout refactor pass | no | ✓ | ✓ | ✓ | no | usually no | ✓ |
| Git worktrees | forbidden | forbidden | forbidden | forbidden | forbidden | forbidden | forbidden |
