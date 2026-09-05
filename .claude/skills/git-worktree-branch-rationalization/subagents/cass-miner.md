---
name: cass-miner
description: Phase 0.5 — mine prior agent sessions via /cass for context, conventions, prior runs, prior manual rationalization sessions, and past file-collision patterns. Optional but valuable. Skipped cleanly if cass is not installed.
---

# CASS Miner

Owns Phase 0.5 (optional). Searches prior agent sessions for context that informs Phase 4 (protection list), Phase 5 (triage), and Phase 7 (harmonization plan). The skill never *requires* `cass` — if it isn't installed or authenticated, this subagent writes a stub `cass_findings.md` and exits cleanly.

Why it matters here (more than for stash-janitor): branch-and-worktree rationalization on an agent-swarm-aftermath repo benefits enormously from knowing which agents previously touched which files. Past collisions are the strongest predictor of present collisions, and prior runs of *this skill* on *this repo* tell us which branches were already triaged before.

## Inputs at invocation

- `{PROJECT}` — absolute path to the target repo
- `{WORKSPACE}` — `<project>/.worktree_branch_rationalization_workspace/`
- `{BASENAME}` — `basename {PROJECT}`

## Outputs

- `<workspace>/cass_findings.md` — classified findings under sections: Prior runs of this skill, Prior manual rationalization sessions, Past file-collision hot zones, Convention augmentations, Related incidents, Skill-state summary. Always written, even when cass is unavailable (stub form contains only `cass_available: false` plus reason).
- `<workspace>/cass_raw/<query-slug>.json` — one raw cass JSON dump per query (6 queries) when cass is available.
- **Stderr / surfaced findings:** one-line stdout summary `cass-miner: <N> hits across <M> categories; <K> prior runs of this skill; <P> file-collision hot zones`.
- **Side effects:** read-only; cass findings never leave `<workspace>/` and are .gitignored by the skill bootstrap.
- **Decision contract:** `cass_findings.md` first line is `cass_available: true|false`. Downstream phases (4 protection, 5 triage, 7 harmonization) read this file but never block on it.

## Workflow

1. **Verify cass availability:** `cass health --json`. If the command is absent, exits non-zero, or reports unauthenticated, write a stub `<workspace>/cass_findings.md` containing only `cass_available: false` plus the reason, and exit cleanly. Do not fail the run.

2. **Run the default queries** with `--robot --limit 50 --days 90` (never bare `cass` — that launches the TUI and blocks the session). For each, capture the JSON output to `<workspace>/cass_raw/<query-slug>.json`:
   - `"{BASENAME}"` — anything ever discussed about this project
   - `"branch rationalization"` — prior runs of this skill anywhere
   - `"git worktree"` — prior worktree work
   - `"git branch -D"` — past mass-deletion incidents (informs danger flags)
   - `"harmonize branches"` — prior manual rationalization-style sessions
   - `"git-worktree-branch-rationalization"` — explicit prior invocations of this skill

3. **Read each top hit's snippet** (the agent's working-tree dialogue, not just the title). For each hit, classify into:
   - `prior-run-of-this-skill` — find the linked handoff_report.md path; record the rationalization-branch name, what landed, what the bundle path was, whether the user later pushed
   - `prior-manual-rationalization` — sessions where the user (or another agent) cleaned up branches/worktrees by hand; record the branches deleted and the user's stated reasoning (lessons learned for the rubric)
   - `past-file-collision` — sessions where ≥2 agents touched the same file (informs Phase 7's harmonization plan: those files are *known* hot zones)
   - `convention-discovery` — augment `project_profile.json:branch_name_conventions` with patterns the user used in prior sessions (e.g., `agent-cleanup-pass-N`, `wip/discard-me`)
   - `related-incident` — abandoned rebases, force-pushes, "we lost X" — flag for Phase 4 confidence-boost
   - `irrelevant` — discard

4. **Write `<workspace>/cass_findings.md`** structured as:
   ```markdown
   # Cass Findings (Phase 0.5)

   - cass_available: true
   - queries_run: 6
   - hits_classified: <N>
   - run_id: branch-rationalization-<run-id>

   ## Prior runs of this skill
   <one block per prior run with handoff path, rationalization branch, bundle path>

   ## Prior manual rationalization sessions
   <lessons learned per session>

   ## Past file-collision hot zones
   <file -> [prior-touching-agents]; feeds harmonization-planner Phase 7>

   ## Convention augmentations
   <new patterns to add to branch_name_conventions>

   ## Related incidents
   <flagged for Phase 4 protection-list reconfirmation>

   ## Skill-state summary
   <"0 priors", "1 prior run with rationalization-branch still unmerged", etc.>
   ```

5. **Surface to the main agent** via a one-line stdout summary: `cass-miner: <N> hits across <M> categories; <K> prior runs of this skill; <P> file-collision hot zones`.

## Critical rules

- **Never run bare `cass`** — it launches a TUI and blocks the session. Always pass `--robot --json`.
- **Always bound the search** with `--days 90` (or shorter). Older sessions rarely inform a present run.
- **If cass is missing or unauthenticated, skip cleanly.** The skill never *requires* `cass`. Write the stub findings file and let the run continue.
- **Never bypass pre-commit hooks** (no commits in this phase, but stated for completeness).
- **Never use sed/awk on source files** (per AGENTS.md "No Script-Based Changes").
- **Never disturb concurrent agents' working-tree state** in any worktree (per AGENTS.md "Note for Codex/GPT-5.5").
- **Never delete files without express user permission** (per AGENTS.md RULE NUMBER 1).
- **Never run mass-delete primitives.**
- **Privacy:** cass findings stay in `<workspace>/`; don't push them. They live alongside the rest of the workspace and are .gitignored by the skill bootstrap.

## Coordination

- File reservation: `paths=[".worktree_branch_rationalization_workspace/cass_findings.md", ".worktree_branch_rationalization_workspace/cass_raw/**"]`, `exclusive=true`, `reason="branch-rationalization-phase0.5"`, `ttl_seconds=900`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] `cass_findings.md` exists (even if stubbed — `cass_available: false`)
- [ ] If cass was available: every hit has a classification
- [ ] Skill-state summary present at end of file
- [ ] No raw cass dumps leak into the handoff report — only the classified summary

## Exit criteria

Findings file written. The main agent reads:
- The list of prior runs (Phase 4 confirms or supersedes their protection lists)
- The file-collision hot zones (Phase 7 prioritizes these in the harmonization plan)
- The convention augmentations (folded into `project_profile.json` if Phase 1 already ran)
