# When NOT to Use This Skill

The decision tree at the top of SKILL.md gates the obvious cases. This reference is for the subtle ones.

---

## Hard refusals (the skill exits immediately)

| Condition | Why | What to do instead |
|-----------|-----|--------------------|
| `git rev-parse --is-inside-work-tree` returns `false` | Bare repo or not a git tree | Don't run the skill |
| `git rev-parse --is-bare-repository` returns `true` | Bare repos have no working tree to walk | The skill needs a checkout |
| Mid-rebase / mid-merge / mid-cherry-pick / mid-revert / mid-bisect | Working-tree state is not snapshot-able | Finish the operation first |
| No commits in the repo | Nothing to back up against | Add an initial commit first |
| Filesystem read-only | Can't write the workspace, bundle, or commits | Resolve first |

`scripts/git-doctor.sh` runs all of these checks and exits non-zero on any hit.

---

## Soft warnings (proceed but flag)

| Condition | Why warn | What the skill does |
|-----------|----------|---------------------|
| Detached HEAD | The recovery branch needs a base | Skill asks the user to check out a branch first |
| Working tree non-empty | Concurrent agents are common; the skill must be careful | Skill snapshots `wt_phase0.txt` and treats drift as committed-by-self |
| No remote | Push instructions degrade gracefully | Skill prints "no remote configured; push when you have one" |
| Submodules present | Submodule subtrees are out of scope | Skill enumerates `git submodule status`; skips submodule subtrees |
| Very old git (<2.20) | Some operations (`git filter-repo`) may not work | Skill warns; user upgrades or proceeds carefully |
| `core.autocrlf` is set | Bundle SHA-256 may drift due to line-ending normalization | Skill sets `core.autocrlf=false` for the session |
| `.gitignore` already very large (>200 lines) | Risk of ordering bugs in additions | Skill is more conservative about the placement of new lines |
| LFS-tracked files among candidates | Recovery requires LFS-smudged blob, not pointer | Skill smudges before bundle copy; index records both pointer and blob SHA |

---

## "Don't run me here" use cases

### Fewer than 5 junk candidates

Just `git status` + `git ls-files` + manual `git rm`. The recovery-bundle overhead doesn't pay off; the skill will warn and ask before proceeding.

### A clean repo

If the inventory walk surfaces zero candidates, the skill exits with "nothing to do." Don't run it just because it's available.

### A repo that's mid-large-refactor

If the user is in the middle of restructuring — moving directories around, renaming packages — let them finish first. Running the janitor concurrently will fight them and produce worse outcomes than letting the refactor complete.

### A repo where the "junk" is intentional

Some repos track:
- Build outputs (vendored compiled assets, generated SDKs)
- Hand-curated test fixtures (sqlite seed DBs, golden output files)
- Multi-format assets (both `.png` and `.webp` versions kept on purpose for older clients)

The archetype profile (Phase 1) should make this clear. If the user contests the candidate list at Phase 5 ("none of those should be touched"), abort the run rather than try to negotiate.

### Submodules' internal trees

Run a separate skill instance inside the submodule. The parent repo's run treats submodule subtrees as opaque.

### Repos with active ongoing operations on `.gitignore`

If the user is mid-edit on `.gitignore`, the skill will see uncommitted changes — pause until they're committed.

### Repos that aggressively use `git add -f`

If the user has a habit of force-adding files (legitimately, e.g., for documentation that includes example secrets in a sandbox), the secret-scan in Phase 2.5 will surface a lot of false-positive escalations. The user should review and pre-populate `protected_globs` with the legitimately-tracked exceptions.

### Production repos with strict change-control

The skill's recovery-branch approach is designed for self-service push. If the org requires a pre-cleanup ticket, code review by N people, separate audit log, etc.: run the skill in TRIAGE-ONLY mode and feed the categorized plan into the org's change-control process.

### Repos under active CI/CD with no staging

The recovery branch + PR workflow assumes the user can review before merge. If the org auto-deploys from the primary branch with no review gate, advise the user to set up a feature branch + manual approval first.

---

## "I want to use the skill but my workflow is unusual"

### "We use a long-lived recovery branch shared across many cleanups"

Pass `recovery_branch_name=<existing-branch>`; the skill will land commits on top of it instead of branching from primary.

### "We push main → master → release-2026-q2 synonyms"

Phase 1 detects `branch_synonyms`; the handoff prints all three push commands. If detection is wrong, override at Phase 0.

### "Our CI has its own `.gitignore` that we can't modify"

Pass `output_mode=move-only`; the skill skips Phase 8.

### "Concurrent agents keep editing files mid-run"

This is normal — the skill handles it. If the agents are specifically working on root-level files and your changes conflict: pause both, run the skill once, then resume the agents.

### "We don't track binary files in our LFS yet"

The skill works without LFS. LFS detection is conditional; non-LFS files are copied byte-identically without smudge.

### "We use `git crypt` to encrypt files"

The skill operates on the working-tree (decrypted) view. Phase 2.5's secret scan may surface decrypted secrets — that's expected. The user confirms whether the file is meant to be decrypted-in-tree (it shouldn't, in most setups) or just visible to the agent context.
