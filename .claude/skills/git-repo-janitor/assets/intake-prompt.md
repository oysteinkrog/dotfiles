# Intake Prompt — Phase 0 Up-Front Confirmations

Use this template verbatim at Phase 0. Fill the brackets, present to user, wait for explicit go-ahead before any work begins.

---

```
I'm about to run the **git-repo-janitor** skill on `<project-path>`.

Before I start, please confirm a few things:

**1. Target.** Operating on `<absolute-project-path>`. Is that correct?
   (If you give me a git URL instead, I'll clone to /tmp/<basename> and operate against that.)

**2. Repo state preview.**
   - Tracked top-level files: <count>
   - Junk-smell candidates detected: <N>
   - Detected archetype: <archetype>  (single-rust-crate / polyglot-monorepo / claude-skill-repo / nextjs-saas / python-package / go-cli / unknown)
   - Primary branch: <primary>  (NOT assumed `main`)
   - Branch synonyms: <synonyms-or-none>  (e.g., `master` mirroring `main`)

**3. Variant.**  (orchestration depth — orthogonal to mode)
   Auto-detected: <variant>  (Quick 5–24 / Standard 25–149 / Comprehensive 150+)
   Override? (yes/no)

**4. Mode.**
   Default: `full` (triage + apply moves + gated deletes + gitignore updates).
   Alternatives:
     - `triage-only` (audit + plan; zero mutations — recommended if you haven't seen the candidate list yet)
     - `move-only` (apply moves but skip deletes/gitignore)
     - `delete-only` (skip moves; just `git rm` + gitignore)
     - `gitignore-only` (just `.gitignore` updates with shadowing audit)
     - `harden-secret-leak` (auto-suggested by Phase 2.5 if a real secret is detected)
     - `recover-from-bad-cleanup` (use after a cleanup ran wrong)
     - `add-archetype-profile` (skill-extension; teach the skill a new repo type)
     - `maintenance-review` (re-run on a previously-cleaned repo to find new junk)
   Confirm `full`? (yes/no/<alt>)
   See `references/OPERATING-MODES.md` for the full per-mode contract (phases-run, stop condition, forbidden actions).

**5. Recovery branch name.**
   Default: `repo-janitor-<YYYY-MM-DD>`. Override? (yes/no/<alt>)

**6. Bundle path.**
   Default: `<project-root>/.repo_janitor_workspace/recovery-bundle-<YYYY-MM-DD>/`
   Override? (yes/no/<alt>)

**7. Reference-rewrite policy.**
   Default: `auto-rewrite-with-confirmation` (skill rewrites references via Edit tool, surfaces every change for confirmation).
   Alternatives: `surface-only` (skill never edits source; you do the rewrites) / `auto-rewrite-trusted-formats` (markdown links and YAML auto; code imports surface).
   Confirm default? (yes/no/<alt>)

**8. Resume?**
   <if .repo_janitor_workspace exists> A previous run's workspace exists from <ts>.
   - (a) Resume from saved state
   - (b) Archive old workspace and start fresh
   - (c) Abort
   Pick: ?

**9. Concurrent agents?**
   Are other agents working in this repo right now? (yes/no)
   If yes, I'll set advisory file reservations to prevent collisions; otherwise I'll proceed.

**10. Quality gates.**
    Auto-detected:
    - test:      <test_command>
    - typecheck: <typecheck_command>
    - lint:      <lint_command>
    - build:     <build_command>
    Run all of these on every Phase 6/7/8 commit? (yes/no/<adjust>)

**11. Protected globs.**
    The skill will NEVER touch files matching these patterns:
    <protected_globs from project_profile.json>
    Add more? Remove any? (you can add but not remove the archetype defaults)

When everything's confirmed, type "go" or "proceed" and I'll start with Phase 1 (Project Reconnaissance).

Reminder: **I will not push the recovery branch** — that's your call. **I will not delete the bundle** — that's also your call. Phase 7 (deletes) and Phase 8 (gitignore) require verbatim authorization from you before they run.
```
