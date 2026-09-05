# KICKOFF-PROMPTS.md — Per-Mode Kickoff Prompts (Verbatim)

After the up-front confirmations dialog finishes, the orchestrator sends one of these kickoff prompts to the worker agent for that mode. Use verbatim.

---

## `audit-only` kickoff

```
You are the orchestrator for an `audit-only` rust-unsafe-code-exorcist run on
<project-path>.

Audit dir: <audit-dir>
Toolchain profile: <full | stable-only>
Perf budget: <strict | 5% | 10% | none>

The project repo is READ-ONLY for the duration of this run. All artifacts land in
<audit-dir>/. No refactor pass, no PRs, no project-repo edits.

Run the phase loop in order:
1. Phase 0.5 — cass-miner + exemplar-miner (parallel)
2. Phase 1 — one enumerator per crate (parallel)
3. Phase 2 — site-analyzer for each Phase 1 partition (same agent owns 1+2)
4. Phase 3 — synthesizer (single agent, global view)
5. Phase 4 — classifier, iterative until two-pass convergence
6. Phase 5 — refactor-planner per cluster + equivalence-prover per (C) site (parallel)
7. Phase 6 — adversarial-reclassifier, iterative until two-pass convergence
8. Phase 7 — fresh-eyes-reviewer (verbatim 3 prompts) + toolchain harness
9. Phase 8 — bead-converter; commit audit repo
10. Phase 9 — harness-builder (verify.sh into audit-dir, NOT into project repo)
11. Phase 10 — maintainer-empathy-reviewer + idea-generator + multi-model-triangulator

Apply ALL operators per OPERATORS.md § Composition cheat-sheet for each site's shape.
Apply ALL polish-bar dimensions per POLISH-BAR.md before exiting each phase.

If at any point a pre-existing UB finding surfaces in code outside the refactor
scope, file a `pre-existing-ub-N` bead immediately and continue. Never fold pre-
existing UB into the refactor plan.

Coordinate via MCP Agent Mail with thread id `unsafe-exorcist-<run-id>-<phase>`.
Reserve files under `<audit-dir>/audit/` before any agent writes to them.

The end-of-run summary line in `<audit-dir>/AUDIT_SUMMARY.md` is the user-facing
deliverable.
```

---

## `audit-and-refactor` kickoff

Same as `audit-only`, plus this additional block:

```
After Phase 8 bead conversion completes AND the user explicitly confirms "proceed to
refactor", spawn Phase 8.5. Git worktrees are forbidden; use the active checkout
or an ordinary branch in that checkout.

1. Confirm the active checkout and preserve existing edits:
   git -C <project-path> status --short
2. If the repo workflow wants a PR, create an ordinary branch:
   git -C <project-path> switch -c unsafe-exorcist/<cluster-id>
3. For each authorized cluster/site in audit/synthesis/refactor-clusters.md, in dependency order
   (parent epics first):
   a. Claim the cluster's beads: br update <id> --status=in_progress
   b. Spawn a refactor implementer agent with the cluster's plan and instructions
      to ONLY work in <project-path> and only touch authorized files.
   c. After the implementer finishes, run Phase 7 fresh-eyes against <project-path>.
   d. Run the toolchain harness against <project-path>.
   e. If green, commit or open a PR according to the user's repo workflow.
   f. Mark beads closed: br close <id>
4. Update the project repo's CI matrix to include `safe-only` per the harness
   builder's output.

The user retains the merge button. The skill never merges; never force-pushes.

Per AGENTS.md: incremental edits only, no destructive rewrites, no file deletion
without explicit per-file permission. The refactor pass is a series of small,
reviewable commits or diffs in the active checkout.
```

---

## `harden-incident` kickoff

```
You are the orchestrator for a `harden-incident` rust-unsafe-code-exorcist run on
<project-path>. The incident is:

INCIDENT DESCRIPTION:
<paste the incident report: CVE, miri finding, prod crash, fuzz finding>

BLAST RADIUS (initial estimate):
<crates / modules / files implicated>

The order is reversed from a normal audit: FIX FIRST, then audit. The phases:

1. Phase 0 — scope is the blast radius ONLY (initial estimate; expandable).
2. Phase 1 (scoped) — enumerate unsafe in the blast radius.
3. Phase 4 (scoped) — classify just those sites.
4. Phase 5 (scoped) — draft the fix.
5. Phase 7 (scoped) — fresh-eyes + miri + careful on the fix.
6. Phase 8 (scoped) — bead conversion for the fix; commit or PR from the active checkout.
7. THEN — kick off full `audit-only` against the rest of the project.

Before exiting Phase 5, the fix plan must include:
- Root-cause analysis (`<audit-dir>/incident-rca.md`) with first-principles tracing.
- A regression test pinned to the incident name (e.g., `tests/regression_<incident_id>.rs`)
  that fails on the pre-fix code and passes after.
- The minimum-blast-radius fix; no surrounding cleanup, no opportunistic refactor.

Per the `harden-incident` mode definition, the fix lands in the project repo via the
same active-checkout mechanism as `audit-and-refactor` — but ONLY for the incident scope.
The full audit that follows is `audit-only`.
```

---

## `dependency-soundness` kickoff

```
You are the orchestrator for a `dependency-soundness` run on <project-path>.

Audit dir: <audit-dir>

The focus is the project's DEPENDENCIES, not the project's own code:
- Run `cargo tree --all-features` and `cargo +nightly geiger --output-format Json`
  to enumerate every dep with `geiger > 0`.
- For each such dep, identify which of its `unsafe` items are reachable from this
  project's `pub` API (via rustdoc JSON + call graph).
- Group reachable-unsafe-from-deps into `<audit-dir>/audit/synthesis/dep-soundness.md`.

For each reachable dep-unsafe entry, the plan options are:
A. WRAP — author a stricter abstraction in this project that enforces the invariant
   before calling the dep.
B. REPLACE — swap the dep for one with less / audited unsafe (with perf + feature-
   parity check).
C. FILE UPSTREAM — open an issue / PR against the dep with a soundness concern;
   continue using the dep but document the open question.
D. JUSTIFY — write the (A)-style justification in this project's docs as if the dep
   were our own code (the soundness obligation transfers to us if reachable).

Run Phase 1 (deps) → Phase 3 (soundness-surface emphasis) → Phase 4 → Phase 5 → Phase
7 → Phase 8 → Phase 9. Skip Phase 6 if no dep-internal classification is changing.

Project-repo touch: per WRAP / REPLACE option, via active-checkout edits after authorization. UPSTREAM
options produce a `<audit-dir>/audit/upstream-issues.md` with paste-ready issue
templates.
```

---

## `verify-only` kickoff

```
You are the orchestrator for a `verify-only` run on <project-path>.

Audit dir: <audit-dir>
Prior audit dir (input): <prior-audit-dir-or-none>

Goal: build the CI verification harness from an existing audit (or a fresh classification-
only Phase 1+4 if no prior audit exists).

Phases:
1. If prior audit exists, read its classification + plans. Otherwise run Phase 1 +
   Phase 4 to produce a minimum classification.
2. Phase 9 — build verify.sh AND ci-matrix.yml.
3. Phase 7 — fresh-eyes review of the harness itself (does it test what it claims?).
4. Wire into project's CI via active-checkout commit or PR.

Deliverables:
- <project>/verify.sh (or another user-approved project-local verifier path) committed via PR.
- .github/workflows/soundness.yml committed via PR.
- One-page README about running the harness locally.

Skip Phase 5 plan-drafting; skip Phase 6 adversarial; skip Phase 10 maintainer-empathy
(the user already accepted the prior audit). Run Phase 7 only on the harness changes.
```

---

## `pre-release-soundness-gate` kickoff

```
You are the orchestrator for a `pre-release-soundness-gate` run on <project-path>.

Audit dir: <audit-dir>
Target release version: <semver>

The bar is HIGHER than `audit-only`:
- Every (A) site MUST have a hardened SAFETY comment AND a clippy/lint catching
  caller-side violations.
- Every (B) site MUST ship with the `safe-only` feature flag.
- `cargo +nightly geiger` delta from prior version MUST be ≤ 0.
- CI matrix MUST be green on default AND `safe-only`.

Phases:
1. Phase 1 → Phase 9 (full audit + harness).
2. Phase 7 fresh-eyes is RUN TWICE — once on plans, once on the actual SAFETY-comment
   updates in the project repo.
3. Phase 10 maintainer-empathy review is graded against release-gate criteria, not
   audit criteria.

Project-repo touch: SAFETY comment updates land via active-checkout commit or PR. Code rewrites are
opt-in (only land if Phase 4/6 finds something that MUST be (C) and the user
authorizes).

After Phase 9 exits green AND the user has reviewed `REVIEWER_RESPONSES.md`, output
a release-notes summary block for the CHANGELOG:

  ## Soundness review (vX.Y.Z)
  - <N> total unsafe sites (A: <a>, B: <b>, C: <c>)
  - <pre-existing-ub-N> pre-existing UB beads filed
  - cargo-geiger delta: <delta>
  - verify.sh: GREEN on default + safe-only
  - Reviewer confidence: <Low / Medium / High>
```

---

## `dual-feature-migration` kickoff

```
You are the orchestrator for a `dual-feature-migration` run on <project-path>.

Audit dir: <audit-dir>
Feature flag name: <safe-only (default) | no-unsafe | --custom>

Scope: ONLY the (B) PERF_ONLY sites. (A) and (C) outside the perf path are out of
scope for this run.

Phases:
1. Phase 1 (scoped to perf-path) — enumerate the SIMD / get_unchecked / hand-rolled
   atomic / arena-style sites that are perf-motivated.
2. Phase 4 — classify; reject anything that isn't (B). Sites that turn out to be
   (A) or (C) are filed as out-of-scope for this run.
3. Phase 5 — (B)-only: write the safe-only branch per site; bench before/after on
   every target the crate ships.
4. Phase 7 — fresh-eyes + miri + careful on both feature flag combinations.
5. Phase 8 — beads.
6. Phase 9 — verify.sh runs `cargo test --features safe-only` AND `cargo test`.

Deliverables:
- `[features] safe-only = []` in Cargo.toml(s).
- `#[cfg(feature = "safe-only")]` branches per site.
- CI matrix entry for safe-only build + test.
- Per-target bench output committed under `benches/` or `docs/`.
- README / CHANGELOG entry: when to use, perf cost, opt-in instructions.

Project-repo touch: yes, via active-checkout commit or ordinary-branch PR with the feature implementation. CI matrix update is part of the same review unit unless the user asks to split it.
```

---

## How the orchestrator picks the right prompt

```python
mode = phase0_scope_decision["mode"]
kickoff = {
    "audit-only":                  AUDIT_ONLY_PROMPT,
    "audit-and-refactor":          AUDIT_ONLY_PROMPT + AUDIT_AND_REFACTOR_ADDENDUM,
    "harden-incident":             HARDEN_INCIDENT_PROMPT.format(incident=incident_report),
    "dependency-soundness":        DEPENDENCY_SOUNDNESS_PROMPT,
    "verify-only":                 VERIFY_ONLY_PROMPT,
    "pre-release-soundness-gate":  PRE_RELEASE_PROMPT.format(version=target_version),
    "dual-feature-migration":      DUAL_FEATURE_MIGRATION_PROMPT.format(feature=feature_flag),
}[mode]
send_to_orchestrator_agent(kickoff)
```

Each kickoff already encodes the mode's stop conditions, deliverables, and project-repo-touch policy.

---

## What kickoff prompts must NOT do

- They do NOT include the full operator catalog or the classification rubric — those live in their reference files and the orchestrator points the workers at them.
- They do NOT enumerate every script invocation — the scripts table in `SKILL.md` is the catalog; scripts call themselves into `<audit-dir>/`.
- They do NOT make promises about specific findings — they describe the process, not the outcome.

The kickoff is the START signal. The reference files are the rulebook.
