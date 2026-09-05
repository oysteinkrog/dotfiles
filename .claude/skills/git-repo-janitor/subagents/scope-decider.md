# Subagent: scope-decider

**Phase:** 0.5
**Spawn:** Once per run.

## Role

Draft `phase0_scope_decision.md` (per SCOPE-DECISION.md) with required / conditional-included / conditional-skipped / not-doing buckets. Sets the run's contract.

## Prompt

You are drafting the scope decision for this run.

Read:
- `<workspace>/interview_log.md` (the user's stage-by-stage answers)
- `<workspace>/project_profile.json` (archetype + ci_gates + branch_synonyms)
- The proposed mode (from interview Stage 1)

Build `phase0_scope_decision.md` with the format in SCOPE-DECISION.md. Sections:

1. **Header**: mode, tier (file count + complexity overlay), run intent (one-line summary of user's Stage 1+2 answers).

2. **REQUIRED**: Phases that always run for this mode (e.g., Phase 0, 1, 2, 2.5, 3, 4, 5 are required for `triage-only`).

3. **CONDITIONAL (will run if applicable)**: Phases that run if their input is non-empty (e.g., Phase 6 if move plan non-empty).

4. **CONDITIONAL-SKIPPED**: Phases that might apply but won't run for this mode/tier. Include rationale.

5. **NOT DOING**: Categories explicitly excluded. Sources:
   - Mode rules (e.g., `triage-only` excludes Phases 6/7/8)
   - User's answers (e.g., user said "skip Cat C" or "don't touch legacy/")
   - Archetype-driven (e.g., a `single-rust-crate` doesn't activate `python_cache_smells`)
   - Operational policy (e.g., user's MEMORY.md says `asupersync` is external-primary-dev)

6. **CONDITIONAL BUNDLES**: For each smell-rule cluster in SCOPE-DECISION.md "Conditional bundle activation table", mark `[x]` activated or `[ ]` dormant with reason.

7. **ESTIMATED SCOPE**: wall time, candidate count (preview), recovery commits expected, ref rewrites expected, user attention required.

8. **ESCALATION POSSIBILITIES**: List the modes this run could escalate to and the trigger conditions.

Sample output (truncated):

```markdown
## Phase 0 Scope Decision — repo-janitor-2026-05-08 on `<repo>`

**Mode:** full
**Tier:** T3 (4,200 tracked files) + 2 complexity points (LFS, submodules) → T4 effective
**Run intent:** "Clean up post-swarm junk; agent left ~80 candidates; user wants the complete sweep"

### REQUIRED
- [ ] Phase 0, 1, 2, 2.5, 3, 4, 5 — always for this mode
...

### NOT DOING
- [ ] Phase 11 user-lens review (off by default)
- [ ] `legacy/` subdir (per user MEMORY.md: "frozen archive")
- [ ] Cat C TOML moves (refs too pervasive; user signed off on skip)
...
```

## Output

`<workspace>/phase0_scope_decision.md` per SCOPE-DECISION.md schema.

## Tools used

Read, Edit.

## Time budget

3-5 min.
