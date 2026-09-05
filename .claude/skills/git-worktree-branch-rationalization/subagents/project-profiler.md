---
name: project-profiler
description: Phase 1 — read AGENTS.md/README.md, run codebase archaeology, detect canonical branch, quality-gate commands, merge style, protected-by-convention patterns; write project_profile.json.
---

# Project Profiler

Owns Phase 1. Reads the project's instructions, samples the codebase, and produces `project_profile.json` — the source of truth for canonical branch, quality-gate commands, conventions, **merge-style preference**, **protected-by-convention patterns**, and **branch-protection rules**.

Why: Axiom 5 says `main` is not the universal default; canonical must be detected, not assumed. Axiom 8 says `-d` over `-D` whenever possible — but the cleanup conductor needs the project's preferred merge style (squash / rebase-and-merge / merge) to know how the keepers will be presented to canonical, which determines whether `-d` will actually succeed.

## Inputs at invocation

- `{PROJECT}` — absolute path to the target repo
- `{WORKSPACE}` — `<project>/.worktree_branch_rationalization_workspace/`

## Outputs

- `<workspace>/project_profile.json` — source-of-truth profile: `canonical_branch` + `canonical_detection_method`, `merge_style` (squash | rebase-and-merge | merge | unknown), `protected_patterns` (always includes canonical, currently-checked-out, `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages` plus repo-specific globs), `branch_protection_source`, `branch_name_conventions`, `commit_message_convention`, `test_command`, `typecheck_command`, `lint_command`, `architecture_summary` (≥150 words referencing actual file paths).
- **Stderr / surfaced findings:** main agent reads back `architecture_summary`, `canonical_branch` + detection method, `merge_style`, and `protected_patterns` count to user as Phase 1 sanity check before Phase 2.
- **Side effects:** read-only across the project; reads AGENTS.md / CLAUDE.md / README.md / `.github/settings.yml` / `.github/branch-protection.yml` / `CONTRIBUTING.md` and samples the last 50 commits. Refuses to proceed if canonical can't be detected via the three methods (Axiom 5: never assume `main`).
- **Decision contract:** `project_profile.json:canonical_branch` non-empty is the gate — empty value blocks Phase 2. The profile is the source of truth consulted by every downstream phase; subsequent phases that depend on it (Phase 4 protection, Phase 5 triage, Phase 8 keeper-applier strategy choice) refuse to start without a valid profile.

## Workflow

Use the **Brennerian opener** verbatim:

> First read ALL of the AGENTS.md file (or AGENT.md, CLAUDE.md, .cursor/rules/*, .github/copilot-instructions.md — whatever the project uses) and the README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code and technical architecture and purpose of the project.

After reading the rules:

1. Run `scripts/discover-project.sh {PROJECT}` to scaffold `project_profile.json` with auto-detected fields.
2. Read 5–10 representative source files (largest top-level directories) to understand architecture.
3. Sample the last 50 commit messages to confirm the auto-detected commit-message convention.
4. **Detect canonical branch** in this order — record which method matched:
   - `git symbolic-ref refs/remotes/origin/HEAD` → trim `refs/remotes/origin/`
   - `git config --get init.defaultBranch`
   - heuristic: `main` > `master` > `develop` > `trunk` > `default` if present in `git for-each-ref refs/heads`
5. **Detect merge-style preference** — record `merge_style` ∈ {`squash`, `rebase-and-merge`, `merge`, `unknown`}:
   - Inspect `.github/settings.yml` (Probot Settings) for `repository.allow_*` flags.
   - Inspect last 50 canonical commits via `git log --format=%P` — if every commit has exactly one parent, project squashes/rebases; if many have two parents, project uses `--no-ff` merges.
   - Inspect canonical commit messages for `Squashed commit of the following:` markers.
   - Default to `unknown` if no signal; keeper-applier degrades to cherry-pick-per-commit.
6. **Detect protected-by-convention patterns** — write to `protected_patterns` field as a list of glob/regex pairs:
   - Always include: `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`.
   - Plus the canonical branch name itself.
   - Plus the currently-checked-out branch (per Axiom 11; never deleted while active).
   - Plus anything matching repo conventions found in AGENTS.md / README.md / `CONTRIBUTING.md` (e.g., `staging/*`, `prod`, `legacy/*`).
7. **Detect branch-protection rules** — read `.github/branch-protection.yml` if present (some projects use the `probot/settings` schema), or `.github/settings.yml`. Extract any branch globs marked as protected and union them into `protected_patterns`. If neither file exists, record `branch_protection_source: none`.
8. Inspect existing branch-name prefixes via `git for-each-ref --format='%(refname:short)' refs/heads | awk -F'/' '{print $1}' | sort | uniq -c` to populate `branch_name_conventions` (e.g., `feat/*`, `fix/*`, `agent/*`, `wip/*`).
9. Augment `project_profile.json` with a 200-word `architecture_summary` field.

Why each detection matters:
- **canonical name** → ★ INVENTORY uses it as the merge-base for every branch; ◐ VERIFY-ON-CANONICAL grep-scopes against it.
- **merge_style** → ⊟ SQUASH-MERGE vs ⊠ REBASE-AND-MERGE vs ✧ CHERRY-PICK strategy choice in keeper-applier.
- **protected_patterns** → 🔒 PROTECT in Phase 4 auto-flags before user sees the inventory; never enter the rationalization pipeline.
- **branch_protection rules** → defense-in-depth; if a branch is config-protected on the host, the skill treats it as protected locally too.

## Coordination

- File reservation: `paths=[".worktree_branch_rationalization_workspace/project_profile.json"]`, `reason="branch-rationalization-phase1"`, `exclusive=true`, `ttl_seconds=900`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] AGENTS.md / CLAUDE.md / equivalent has been read in full
- [ ] README.md has been read in full
- [ ] `project_profile.json` has a non-empty `canonical_branch` AND records the `canonical_detection_method`
- [ ] `merge_style` is one of `squash` / `rebase-and-merge` / `merge` / `unknown` (never empty)
- [ ] `protected_patterns` includes at minimum: canonical, currently-checked-out, `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`
- [ ] `test_command` / `typecheck_command` / `lint_command` keys present (empty string means no command detected)
- [ ] Architecture summary is ≥150 words and references actual file paths from the repo

## Critical rules

- **Never assume `main`.** Per Axiom 5; refuse to proceed if canonical can't be detected from the three methods above without surfacing to the user.
- **Never bypass pre-commit hooks.**
- **Never use sed/awk on source files** (per AGENTS.md "No Script-Based Changes").
- **Never disturb concurrent agents' working-tree state** (per AGENTS.md "Note for Codex/GPT-5.5").
- **Never delete files without express user permission** (per AGENTS.md RULE NUMBER 1).
- **Never run mass-delete primitives.**

## Exit criteria

`project_profile.json` exists and is read-back valid JSON. Main agent reads the `architecture_summary`, `canonical_branch` (with detection method), `merge_style`, and `protected_patterns` count to the user as a sanity check before Phase 2 starts.
