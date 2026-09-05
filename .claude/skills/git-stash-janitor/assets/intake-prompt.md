# Intake Prompt — Up-Front Confirmations Template

Use this template verbatim when invoking the skill. Replace `{...}` with detected values.

---

I'm about to run the git-stash-janitor skill on `{PROJECT_PATH}`.

**Stash count up front:** `{N}` stashes (per `git stash list | wc -l`).

> Note: many users mistake `*N` in their zsh prompt for "N commits ahead". It's
> the stash count.

Before I start, a few confirmations:

1. **Target path:** `{PROJECT_PATH}` — confirm this is the repo you want triaged.
   (If you provided a git URL, I'll clone it to `/tmp/<basename>` and operate
   on the clone.)

2. **Mode:** auto-detected as **{MODE}** based on stash count `{N}`:
   - Quick (5–9 stashes by default; <5 only after "run anyway"): hand-curated, single agent, ~10–20 min
   - Standard (10–80): 2–4 parallel triage workers, ~30–90 min
   - Comprehensive (80+ or stash references deleted/renamed files): 5+ workers,
     archaeology subagents, ~2–6 h

   You can override.

3. **Output mode:** default `full` — triage + apply keepers + gated cleanup.
   Alternatives:
   - `triage-only`: stop after Phase 5 (decision table); no commits, no drops
   - `apply-only`: skip Phase 9 cleanup; leave stashes intact

4. **Recovery branch:** keepers will land on `stash-recovery-{YYYY-MM-DD}` off
   `{PRIMARY_BRANCH}`. Confirm OK or specify a different name.

5. **Bundle path:** the recovery bundle (backup refs + per-stash diffs + meta)
   will be created at `{BUNDLE_PATH}`. This is where every stash is captured
   before any destructive action runs. Confirm OK.

6. **Resuming a prior run?** I see `.stash_janitor_workspace/` already exists.
   (Only shown when relevant.) Options:
   - Resume: continue from saved state
   - Fresh: archive old workspace, start over
   - Abort

7. **Concurrent agents in this repo right now?** If yes, I'll register an
   advisory file reservation on `.git/**` so a parallel stash-janitor invocation
   would notice. Working-tree changes from other agents are normal — per
   AGENTS.md, I'll treat them as if I made them and not disturb.

8. **Quality gates auto-detected:**
   - Test: `{TEST_COMMAND}`
   - Typecheck: `{TYPECHECK_COMMAND}`
   - Lint: `{LINT_COMMAND}`
   - UBS available: `{UBS_AVAILABLE}`

   These will run on every Phase 6 keeper apply (per-apply, not just at end).
   Confirm or correct.

Reply with "go" (or specify any overrides) and I'll start with Phase 1
(project reconnaissance: read AGENTS.md, README.md, run codebase archaeology).
