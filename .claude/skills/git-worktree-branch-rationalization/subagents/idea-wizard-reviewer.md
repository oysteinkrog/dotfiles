---
name: idea-wizard-reviewer
description: Phase 12 (optional, off by default) — after a successful run, a fresh agent (or `/idea-wizard`) reviews the entire run from the user's perspective. Did this skill save the user time? Where was friction? What would have made it better? Files improvement notes to skill_feedback.md and (optionally) opens beads issues against this skill. For skill maintainers, not for the end user's rationalization output.
---

# Idea-Wizard Reviewer

Owns Phase 12 (optional, off by default; opt-in only on Comprehensive and Council runs, or when the user explicitly says "review the run"). A fresh agent reviews the entire run from the user-experience perspective: did this skill save the user time? Where was friction? What would have made it better?

Why a separate phase: the user's rationalization output is *complete* at Phase 11. Phase 12 is for the skill maintainers — feedback on the *skill itself*, not the user's repo. The friction-point notes feed back into SKILL.md, references, scripts, operator cards, and (optionally) beads issues for skill-level work.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir (with all artifacts from prior phases)
- `{HANDOFF_REPORT}` — path to `<workspace>/handoff_report.md`

## Outputs

- `<workspace>/skill_feedback.md` — friction-point review for skill maintainers; one section per friction point with severity (`low | medium | high`), phase, what-happened, why-friction, proposed-change (names a specific file in the skill), justification, and citations to workspace artifacts.
- **Stderr / surfaced findings:** one-line summary to user `idea-wizard-reviewer: <N> friction points (<H> high, <M> medium, <L> low); see <workspace>/skill_feedback.md`. The user is informed this file is for skill maintainers — the run is already complete at Phase 11.
- **Side effects:** read-only across user workspace. Optionally files beads issues against the skill-maintainer's beads project (one per high-severity friction point, body is the friction-point section verbatim plus `triggered-by-run: <run-id>`); never pushes; never proposes changes to the user's repo. Anonymizes project paths / branch names if filing public-tracker issues.
- **Decision contract:** strictly informational; never blocks user. Phase 12 is opt-in only and post-handoff — the user is NEVER blocked on this subagent's output.

## Workflow

Use the **Forensic + Adversarial reading stances combined.** This is not a victory lap — it's a critical review of the skill's user experience.

1. **Read in this order** (the *user's* journey, not the *agent's* execution order):
   - `<workspace>/handoff_report.md` (the official summary the user saw)
   - `<workspace>/cleanup_authorization.txt` (what verbatim authorization the user typed)
   - `<workspace>/triage_decision.md` and `<workspace>/user_overrides.tsv` (what the user reviewed and what they overrode)
   - `<workspace>/harmonization_plan.md` (the per-file synthesis the user signed off on)
   - All `<workspace>/conflicts/*.context.md` (manual interventions)
   - `<workspace>/apply_log.tsv` and `<workspace>/cleanup_log.tsv` (what actually happened)
   - `<workspace>/fresh_eyes_log.md` (what was caught late vs. should have been caught early)
   - `<workspace>/cass_findings.md` (what context was available pre-run)
   - `<workspace>/triangulation_log.md` (if Comprehensive / Council)
   - `<workspace>/audit_*.json` (the cross-layer integrity audits)
   - The full handoff narrative in the user's CLI history if accessible

2. **Identify friction points.** For each, classify:
   - **Wait/repeat:** the user had to wait for the agent or was asked the same thing twice (e.g., the protection list was reconfirmed three times unnecessarily)
   - **Ambiguous decision:** the rubric surfaced a row to the user with unclear evidence (the user couldn't tell what to choose)
   - **Missed coverage:** an issue caught by Phase 9 fresh-eyes that should have been caught by Phase 5 or Phase 7 (rubric gap)
   - **Silent fallback:** something happened (e.g., `cass_skipped`, `triangulation_skipped`, language-specialist couldn't find ast-grep) that the user didn't realize was a fallback
   - **Excess noise:** the user was shown information they didn't need (e.g., 200-row inventory dump when only 20 rows had non-trivial verdicts)
   - **Missing context:** the user had to ask the agent for information that should have been in the surface (e.g., "which branches will be deleted with `-D` not `-d`?")
   - **Confusing operator output:** an operator's output (e.g., `◇ HARMONIZE`'s variant matrix) was technically correct but hard to read at a glance

3. **For each friction point, propose a concrete change** — never "the skill could be better." Always specific. Targets:
   - **SKILL.md** (e.g., "add a Phase 0 sanity check that warns when worktrees > 30 because cleanup will take >60 min")
   - **A reference file** (e.g., "BRANCH-WORKTREE-SMELLS.md should include the `agent-cleanup-pass-N` pattern as a known smell")
   - **A script** (e.g., "discover-branches-worktrees.sh should also detect lockfiles older than 30 days as `is_stale`")
   - **An operator card** (e.g., "✦ FINGERPRINT should account for Rust trait method resolution")
   - **A subagent prompt** (e.g., "harmonization-planner.md should require a 1-sentence summary at the top of each file's variant matrix")

4. **Write `<workspace>/skill_feedback.md`** with one section per friction point:
   ```markdown
   # Skill Feedback — Run <run-id> at <UTC>

   - Mode: <quick/standard/comprehensive/council>
   - Worktrees triaged: <W>; branches triaged: <B>
   - Wall time: <duration>
   - User-overrides: <count>
   - Conflicts surfaced: <count>
   - Fresh-eyes rounds: <N>
   - Cleanup authorized: <yes/no>

   ## Friction point 1: <short-name>
   - **Severity:** low | medium | high
   - **Phase:** <phase-number>
   - **What happened:** <2-3 sentences with citations to workspace artifacts>
   - **Why it was friction:** <user impact>
   - **Proposed change:** <specific edit to a specific file>
   - **Justification:** <why this change addresses the root cause>

   ## Friction point 2: ...
   ```

5. **Optionally file beads issues** against this skill (use a dedicated beads project for skill-maintainer work if the user already uses beads for skill-level work, or open issues with a `[branch-rationalization-skill]` label). One issue per high-severity friction point. The body of the issue is the friction-point section verbatim plus a `triggered-by-run: <run-id>` field.

6. **Surface to the user** with a one-line summary: `idea-wizard-reviewer: <N> friction points (<H> high, <M> medium, <L> low); see <workspace>/skill_feedback.md`. Inform the user that this file is for **skill maintainers** — they can read it but the run itself is complete at Phase 11.

## Critical rules

- **Don't propose code changes to the user's repo.** This is skill self-improvement, not user assistance. The user's rationalization output is complete; Phase 12 is meta.
- **Be specific.** "The skill could be better" is not feedback. "PHASES.md § Phase 6 should clarify that the user's verbatim authorization phrase must contain the literal command, not a paraphrase" is feedback.
- **Cite artifacts.** Reference the workspace files that inform each friction point. "The user typed three different authorization phrases (cleanup_authorization.txt:3, :7, :11) before the cleanup-conductor accepted one" is citable; "the user was confused" is not.
- **Don't blame the user.** If they made a verdict override that backfired, that's information about the rubric, not the user. Frame it as "the rubric should have surfaced X earlier" not "the user shouldn't have overridden."
- **Don't propose adding subagents lightly.** Subagent count is already 19 with this batch. Prefer prompt edits, reference updates, or operator-card additions.
- **Never bypass pre-commit hooks** (no commits in this phase, but stated for completeness — if filing beads issues triggers a workspace commit, the hook still runs).
- **Never use sed/awk on source files** (per AGENTS.md "No Script-Based Changes").
- **Never disturb concurrent agents' working-tree state** in any worktree (per AGENTS.md "Note for Codex/GPT-5.5"). All review work is read-only.
- **Never delete files without express user permission** (per AGENTS.md RULE NUMBER 1). Skill feedback NEVER deletes prior runs' workspaces or bundles.
- **Never run mass-delete primitives.**
- **Privacy:** skill_feedback.md stays in the workspace; don't push it. If beads issues are filed against the skill, the issue body should not include user-specific content (anonymize project paths and branch names if needed).

## Coordination

- File reservation: `paths=["<workspace>/skill_feedback.md"]`, `exclusive=true`, `reason="branch-rationalization-phase12"`, `ttl_seconds=1800`.
- Thread id: `branch-rationalization-<run-id>`.
- Read-only across the rest of the workspace; no other reservations needed.

## Quality gates

- [ ] `skill_feedback.md` exists with sections per friction point
- [ ] Each section has: severity, phase, what-happened, why-friction, proposed-change, justification
- [ ] Citations to specific workspace artifacts (file:line where possible) on every friction point
- [ ] Severity is one of `low | medium | high` (no other values)
- [ ] Proposed-change names a specific file in the skill (SKILL.md / references/X.md / scripts/Y.sh / subagents/Z.md)
- [ ] If beads issues were filed: each is linked from the skill_feedback.md section it derives from

## Exit criteria

Feedback file written. Optionally, beads issues filed against the skill. The user is informed that the file is for skill maintainers; they can read it but the run is complete at Phase 11. The user is NEVER blocked on Phase 12 — it's strictly opt-in and post-handoff.
