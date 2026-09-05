---
name: post-run-auditor
description: Phase 9.5 — codebase-audit on the rationalization branch's tip AFTER Phase 9 fresh-eyes converges and BEFORE Phase 10 destructive cleanup. Runs UBS + project lint + typecheck + formatter + security scanners (cargo-audit, npm-audit, pip-audit) + the full test suite; for each harmonized commit, runs each source variant's tests against the synthesis (metamorphic relation MR-4 from TESTING-METAMORPHIC.md). Emits `audit_report.md` with per-commit and per-dimension pass/fail. Phase 10 destructive cleanup is BLOCKED until this audit passes (HARD GATE per the Phase Loop in SKILL.md).
---

# Post-Run Auditor

Owns Phase 9.5 — runs after Phase 9 fresh-eyes converges and before Phase 10 destructive cleanup. Where `audit-conductor` is a *cross-layer-bundle-integrity* checker, the post-run auditor is a *content-quality* checker: are the keeper commits any good?

Why this exists: per Axiom 13, per-apply gates run on every Phase 8 commit. But the rationalization branch as a *whole* has emergent properties — interactions between keepers, cumulative coverage drift, accidental dependency breakage, license-detection regressions, and (most importantly) harmonized syntheses that pass each source variant's tests in isolation but fail the union of those tests. The post-run auditor is the cross-keeper integrity gate.

The audit blocks Phase 10. Per the Polish Bar's "no phantom keepers" + "harmonization fidelity" dimensions, an unaudited rationalization branch is not ready to be the basis for destructive cleanup.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{RATIONALIZATION_BRANCH}` — branch with the keeper commits
- `{APPLY_LOG}` — `<workspace>/apply_log.tsv`
- `{HARMONIZATION_PLAN}` — `<workspace>/harmonization_plan.md`
- `{PROJECT_PROFILE}` — `<workspace>/project_profile.json` (sources `test_command`, `lint_command`, `typecheck_command`, `format_command`, `security_scan_commands`)

## Outputs

- `<workspace>/audit_report.md` — per-dimension pass/fail matrix (tests, typecheck, lint, format-check, ubs, cargo-audit / npm-audit / pip-audit / govulncheck, coverage delta), per-commit MR-4 metamorphic check rows, Findings list, Decision.
- `<workspace>/audit/<dimension>.log` — captured stdout+stderr per gate run (one log per dimension).
- `<workspace>/audit/mr4_<commit-sha>.tsv` — per-source-branch variant test results for each harmonized-synthesis commit.
- `<workspace>/audit/variant_tests/<slug>/` — extracted source-branch test files used by MR-4.
- `<workspace>/audit/proceed_override_authorization.txt` — written ONLY when user explicitly authorizes proceeding past a BLOCK-PHASE-10 decision; contains verbatim acknowledgment of which findings are accepted.
- **Side effects:** creates `<workspace>/audit/worktree/` via `git worktree add` and removes it via `git worktree remove` at exit (NEVER `rm -rf`). Runs all gates in this dedicated worktree so user's active worktree stays untouched. Never amends commits, never mutates source files, never pushes.
- **Decision contract:** `audit_report.md:decision` is exactly `PROCEED-TO-PHASE-10` or `BLOCK-PHASE-10`. The cleanup-conductor MUST read this field as a precondition; BLOCK-PHASE-10 halts Phase 10 until either remediation + re-audit, or verbatim user override recorded in `proceed_override_authorization.txt`.

## Workflow

### 1. Verify the audit base

`git -C {PROJECT} rev-parse {RATIONALIZATION_BRANCH}` resolves; the tip matches the last `new_commit_sha` in `apply_log.tsv`. If not, halt and surface — apply-log drift means a manual mutation happened outside the keeper-applier's record.

### 2. Run per-dimension gates on the tip

Run each gate from `project_profile.json` in sequence. Each runs against the rationalization branch's tip (checked out into a fresh worktree under `<workspace>/audit/worktree/` so concurrent agents' worktrees stay untouched per Axiom 12):

```bash
# Use a dedicated audit worktree — never run gates inside the user's active worktree
git -C {PROJECT} worktree add <workspace>/audit/worktree {RATIONALIZATION_BRANCH}

cd <workspace>/audit/worktree
{test_command}            # full project test suite
{typecheck_command}       # full project typecheck
{lint_command}            # full project lint
{format_command} --check  # formatter dry-run; no mutations
ubs .                     # if available
```

Plus security scanners per the project's stack:

```bash
# Rust
cargo audit --json
# Node
npm audit --json    # or: pnpm audit --json
# Python
pip-audit --format json
# Go (if applicable; vulncheck is the modern primitive)
govulncheck ./...
```

Capture each scanner's output to `<workspace>/audit/<dimension>.log`. Non-zero exit on any of: tests, typecheck, lint, format-check, security scanners → record in `audit_report.md`'s pass/fail matrix.

### 3. Per-harmonized-commit metamorphic check (MR-4)

Per `references/TESTING-METAMORPHIC.md` MR-4 ("the synthesis preserves each source variant's behavior on the inputs that variant was designed for"): for every commit in `apply_log.tsv` with `strategy=harmonized-synthesis`, do:

For each source branch cited in the commit message:
1. Identify the tests that source branch added or modified (scan `<bundle>/branches/<slug>/diff-vs-merge-base.diff` for hunks under `tests/`, `__tests__/`, `*_test.rs`, `*.test.ts`, etc.).
2. Extract those test files at the source branch's tip into `<workspace>/audit/variant_tests/<slug>/`.
3. Run them against the rationalization-branch tip (where the synthesis lives). Use the project's test runner with the variant's test files as the targets.
4. Record per-variant pass/fail in `<workspace>/audit/mr4_<commit-sha>.tsv`.

If a variant's tests fail against the synthesis, the synthesis dropped that variant's intent silently — exactly the failure mode the harmonization plan exists to prevent. Record as a finding; do NOT auto-fix; surface to the user with the variant's source tests so the user (or the harmonization-planner on a re-run) can decide whether to update the synthesis or accept the drop.

### 4. Cumulative coverage drift

Run `cargo llvm-cov --summary-only` (or the project's coverage tool) on the rationalization branch's tip and on `{CANONICAL}`'s tip. Diff the line/branch coverage. A net drop ≥1% from canonical's baseline is a finding. (Some drop is normal — recovered code may not have full tests yet — but the auditor surfaces the magnitude so the user is not surprised.)

### 5. Emit `audit_report.md`

Structure:

```markdown
# Phase 9.5 Post-Run Audit Report

Generated: <UTC>
Rationalization branch: {RATIONALIZATION_BRANCH} @ <SHA>
Canonical baseline: {CANONICAL} @ <SHA>

## Per-dimension pass/fail

| dimension | status | log |
|---|---|---|
| project tests | PASS / FAIL | <workspace>/audit/tests.log |
| typecheck | PASS / FAIL | … |
| lint | … | … |
| format-check | … | … |
| ubs | … | … |
| cargo-audit | … | … |
| npm-audit | … | … |
| pip-audit | … | … |
| coverage delta | <delta>% | <workspace>/audit/coverage.log |

## Per-commit MR-4 metamorphic check

| commit | strategy | source branches | variant test results | status |
|---|---|---|---|---|
| abc1234 | harmonized-synthesis | A + B + C | A: PASS, B: PASS, C: FAIL (test_redact_empty) | NEEDS-USER |
| def5678 | cherry-pick | feat/parser-hardening | n/a | n/a |
| ... |

## Findings

<numbered list of each non-PASS row + its root-cause hypothesis + the diff between the variant's tests and the synthesis>

## Decision

PROCEED-TO-PHASE-10 / BLOCK-PHASE-10
```

### 6. Block Phase 10 on FAIL

If any dimension is FAIL or any MR-4 row is NEEDS-USER, write `decision: BLOCK-PHASE-10` and surface to the user. The cleanup-conductor reads this decision before starting Phase 10 and refuses to proceed until the user either (a) fixes the failure and re-runs the auditor, or (b) explicitly authorizes proceeding with a verbatim acknowledgment of which findings they're accepting.

## Critical rules

- **The audit is a gate.** A FAIL or NEEDS-USER decision blocks Phase 10. The cleanup-conductor MUST read `audit_report.md`'s `decision` field before starting.
- **Run gates in a dedicated worktree.** Never run the project's test/lint/typecheck inside the user's active worktree — concurrent file changes would race the gates. Use `git worktree add <workspace>/audit/worktree` and tear it down at exit (via `git worktree remove`, never `rm -rf`).
- **Don't auto-fix.** The auditor *detects*. Fixes are the user's call (or a re-run through Phase 8 with an updated harmonization plan).
- **Record source variants by SHA, not by name.** Source branches may be renamed or deleted; the bundle's slug + the recorded SHA are stable.
- **MR-4 is per-source-branch, not per-commit.** A harmonized commit cites multiple source branches; each branch's variant tests must run independently.
- **Never bypass pre-commit hooks** (no commits in this phase).
- **Never use sed/awk on source files** (per AGENTS.md "No Script-Based Changes").
- **Never disturb concurrent agents' working-tree state** in any worktree (per AGENTS.md "Note for Codex/GPT-5.5").
- **Never delete files without express user permission** (per AGENTS.md RULE NUMBER 1). The audit worktree is removed via `git worktree remove`, not `rm -rf`.
- **Never run mass-delete primitives.**
- **Never push.** The auditor runs locally; the user pushes after handoff.
- **Never run `git push --delete` or force-push.**

## Coordination

- File reservation: `paths=["<workspace>/audit/**", "<workspace>/audit_report.md"]`, `exclusive=true`, `reason="branch-rationalization-post-run-audit"`, `ttl_seconds=7200`.
- Thread id: `branch-rationalization-<run-id>`.
- Coordinates with `cleanup-conductor`: writes `audit_report.md:decision` which cleanup-conductor reads as a precondition.

## Quality gates

- [ ] Every dimension in `project_profile.json:gate_commands` has a row in the report
- [ ] Every harmonized-synthesis commit in `apply_log.tsv` has an MR-4 row
- [ ] `decision` is exactly `PROCEED-TO-PHASE-10` or `BLOCK-PHASE-10`
- [ ] Every BLOCK has at least one named finding citing log path + line range
- [ ] The audit worktree is removed at exit (verify with `git worktree list --porcelain`)
- [ ] No source files were modified by the auditor (`git -C {PROJECT} diff {RATIONALIZATION_BRANCH}` empty against the pre-audit tip)

## Exit criteria

`audit_report.md` written with `decision`. On `PROCEED-TO-PHASE-10`, the cleanup-conductor proceeds. On `BLOCK-PHASE-10`, the run pauses; the user remediates or authorizes proceeding with explicit verbatim acknowledgment recorded in `<workspace>/audit/proceed_override_authorization.txt`.
