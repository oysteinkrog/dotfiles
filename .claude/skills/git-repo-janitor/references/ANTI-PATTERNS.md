# Anti-Patterns

The most common ways the skill could go wrong, with worked examples and fixes. Each entry has a real or near-real session source.

---

## A1. Use `rm` instead of `git rm`

**✗** `rm <path>` (filesystem deletion bypassing git)
**✓** `git rm <path>` (records the deletion in git history)

**Why:** `rm` removes the file from disk but git still tracks it as a modification (the index entry persists). The next `git commit -a` would commit the removal, but the rename/delete record is missing.

**Worked example:** A panicked Phase 7 worker removes a candidate via `rm` because they think `git rm` failed. `git status` shows `deleted: <path>` (modified, not deleted-from-index). The cleanup commit still works, but `git log --diff-filter=D -- <path>` won't show the proper deletion record, complicating future recoveries.

---

## A2. Use `mv` + `git add` instead of `git mv`

**✗** `mv <src> <dst>; git add <dst>; git rm <src>` (manual emulation of `git mv`)
**✓** `git mv <src> <dst>` (single command; preserves rename detection)

**Why:** Git's rename detection runs on commits. If content is similar enough (default ~50% threshold), it auto-detects the rename. But `git mv` records the rename explicitly, immune to threshold misses. And: tooling like `git log --follow` and `git blame --follow` only follows explicit renames cleanly.

**Worked example:** Frankensqlite cleanup moved 16 planning docs. With `git mv`, every move shows as `R 100%` in `git status` and `git log --follow docs/planning/X.md` traces back to the root-level `X.md`. With `mv` + `git add`, two of the 16 had content drift >50% (history additions during the move), and rename detection failed — `git log --follow` returned only the post-move history.

---

## A3. Mass-rewrite references with `sed -i`

**✗** `sed -i 's|X\.md|docs/planning/X.md|g' $(grep -lr "X.md" .)`
**✓** Edit-tool rewrites, one (file, old_string, new_string) at a time, logged in `reference_rewrite_log.tsv`

**Why:**
- `sed` regex can over-match (e.g., `X.md` matches inside `XX.md` or `X.md.backup`).
- Brittle on lines with shell metacharacters.
- No rollback record.
- Per AGENTS.md "No Script-Based Changes": "Brittle regex-based transformations create far more problems than they solve."

**Worked example:** A cleanup tries to rewrite all references to `PLAN.md` → `docs/planning/PLAN.md`. `sed -i` over-matches in a Python file's docstring `# See PLAN.md.html for details`, producing `docs/planning/PLAN.md.html`. The bug is invisible until someone clicks the link.

---

## A4. Skip REFERENCE-GREP for "obvious junk"

**✗** "It's clearly named `scratch.py`, just delete it."
**✓** Always REFERENCE-GREP. ≥1 inbound hit forces verdict to `surface-to-user`.

**Why:** Filename smell is high-confidence but not certainty. Real-world overrides include test helpers, dev-time entry points, and module imports that look junky but are load-bearing.

**Worked example:** `command_palette.md` in ntm looked like a stranded markdown doc. REFERENCE-GREP found it used by `tests/integration/config_test.go:251` as a runtime config source. Verdict flipped from `move` to `keep-in-place`.

---

## A5. Believe `.gitignore` shadows already-tracked files

**✗** Adding `*.db` to `.gitignore` and assuming the existing `storage.db` becomes hidden.
**✓** SHADOWING-AUDIT first; pair `.gitignore` addition with `git rm --cached <files>` if shadowing tracked files.

**Why:** `.gitignore` only affects untracked files. Tracked files are still tracked even if they match a new ignore pattern. Subsequent `git status` will silently mask the file (in v2.x git's "ignored" output) but `git diff` and `git log` will still see it. Over weeks, the file accumulates committed changes that look like normal commits, while devs assume it's untracked.

**Worked example:** A team added `*.json` to `.gitignore` to prevent debug-output leakage. They forgot `package.json`. CI started silently dropping `package.json` updates from PRs (since reviewers' diff tools showed the file as ignored). The bug surfaced 3 weeks later when a `pnpm install` failed.

---

## A6. Bundle the working tree without snapshotting concurrent agent changes

**✗** Phase 3 copies files based on Phase 2's `candidates.tsv` SHA without re-checking the live state.
**✓** Phase 3 verifies SHA-256 of every working-tree-copy against the live blob right before sealing.

**Why:** Concurrent agents might modify a candidate between Phase 2 and Phase 3. Without a re-verify, the bundle's "byte-identical" copy might already be stale.

**Worked example:** A Phase 3 run on a busy repo. Concurrent agent committed a fix to a candidate after Phase 2 inventoried it. Phase 3 copied the post-fix content into the bundle. If the user later wanted to roll back to "what the candidate looked like at run start", the bundle would have the post-fix content, not the pre-fix.

---

## A7. Force-add a `.gitignore`'d file with `git add -f`

**✗** `git add -f signing-test.key` because "the rule shouldn't apply this once."
**✓** Either rename the file to be `.gitignore`-compatible OR add a narrow exception (`!signing-test.key`) and audit it in the next cleanup pass.

**Why:** `git add -f` bypasses `.gitignore` permanently for that path. The next time someone forgets the rule, no audit trail surfaces it. The mcp_agent_mail Apr-27 incident was exactly this: `signing-77c6e768.key` was force-added despite a `signing-*.key` rule.

**Mitigation:** Pre-commit hook scanning staged paths against secret-smells. Cannot be bypassed by `git add -f`.

---

## A8. Run `git filter-repo` without verifying origin sync

**✗** `git filter-repo --invert-paths --path X.key --force` on a local clone with N commits while origin has M > N commits.
**✓** First: `git fetch origin && git update-ref refs/heads/<branch> refs/remotes/origin/<branch>`, verify counts match, THEN filter-repo.

**Why:** filter-repo only rewrites the commits reachable from local refs. If origin has more commits than local (shallow clone, partial fetch, old checkout), the rewrite leaves the secret in the upstream history — a force-push appears to succeed but origin still has the leak.

**Worked example:** mcp_agent_mail Apr-27. Local had 199 commits; origin had 793. First filter-repo run rewrote 199. Second run, after `git update-ref refs/heads/main refs/remotes/origin/main`, rewrote 793 correctly.

---

## A9. Push the recovery branch on the user's behalf

**✗** Skill ends with `git push origin repo-janitor-2026-04-27`.
**✓** Skill prints the push command in the handoff report; user pushes.

**Why:** The user knows their team's review conventions, branch protections, CI cost considerations, and rollback tolerances. Auto-push removes the human-in-the-loop check that makes the cleanup safe.

This is the same boundary `documentation-website-for-software-project` and `git-stash-janitor` use.

---

## A10. Land cleanup commits directly on the primary branch

**✗** `git checkout main; git rm <files>; git commit -m chore: cleanup`
**✓** `git checkout -b repo-janitor-2026-04-27 origin/main; ...; user pushes; PR against main`

**Why:** Mass-applied recoveries deserve user review. A PR provides a single point of audit for all the moves, deletes, and `.gitignore` changes; landing directly on main bypasses the review.

---

## A11. Use ad-hoc shell scripts to "fix up" reference rewrites

**✗** `find . -name "*.rs" -exec sed -i 's|X|Y|g' {} \;`
**✓** Edit tool, one occurrence at a time.

**Why:** Same as A3 — brittle, no audit, not idempotent, breaks on edge cases. Per AGENTS.md "No Script-Based Changes."

---

## A12. Stash, revert, or overwrite changes from other agents

**✗** `git stash` to "clean up" before Phase 6.
**✓** Treat concurrent agents' working-tree changes as if you committed them. Per AGENTS.md "Note for Codex/GPT-5.5".

**Why:** Multi-agent coordination is real. The other agent has work-in-progress; stashing/reverting it loses that work. The skill snapshots `git status` at every phase, treats observed drift as committed-by-self, and continues.

---

## A13. `rm -rf <bundle>` after a "successful" run

**✗** `rm -rf /data/projects/<repo>/.repo_janitor_workspace/recovery-bundle-2026-04-27/`
**✓** Leave the bundle in place; user manages lifecycle.

**Why:**
- DCG would block it anyway.
- The recovery story has to outlive the run; the bundle is the gold standard backup.
- Bundle deletion should happen after at least one full release cycle, by deliberate user action.

---

## A14. Skip Phase 2.5 secret scan to "save time"

**✗** "It's a private repo, secrets are fine."
**✓** Phase 2.5 is non-negotiable. Always runs.

**Why:**
- "Private" is fluid — repos get open-sourced; teammates leave; backups exist.
- The cost is ~3 minutes; the cost of a missed leak is 30 days of exposure plus a key rotation.
- The mcp_agent_mail incident proves the value: the leak was a real Ed25519 key in a public repo, undetected for 30 days.

---

## A15. Treat the `triage.tsv` as authoritative without user review

**✗** "I'll just apply all the auto-classified rows; the user can revert if they don't like it."
**✓** Phase 5 is a USER GATE. The user reviews the categorized plan and approves before any mutation runs.

**Why:** Auto-classification is statistical. Even at 95% accuracy on 100 candidates, that's 5 wrong verdicts. The user catches these in the categorized plan review faster than the skill can recover from a bad delete.

---

## A16. Move TOML config files referenced by hardcoded paths in source code

**✗** Move `corpus_manifest.toml` from root to `docs/contracts/` because "it's documentation."
**✓** When REFERENCE-GREP finds ≥10 hardcoded path strings in source code, mark the category DEFERRED. Don't move; flag the cost; let the user decide later.

**Why:** Moving requires updating all the hardcoded paths in source code. That's a refactor, not a janitorial cleanup. The frankensqlite Cat-C deferral case codifies this rule.

---

## A17. Auto-rewrite imports in source code

**✗** Edit-tool rewrite of `import scratch` → `import tools.scratch` for a moved Python module.
**✓** Surface every import rewrite to the user; let them confirm before the rewrite runs.

**Why:** Imports go through Python/TypeScript/Rust module resolution. A lexical Edit-tool match might miss aliased imports (`from scratch import X as Y`), re-exports, conditional imports. Surface and confirm.

---

## A18. Edit `.gitignore` without preserving thematic structure

**✗** Append all new patterns at the end of `.gitignore`, regardless of what theme they belong to.
**✓** Group new additions thematically; insert into the right section if one exists.

**Why:** `.gitignore` is a document. The skill's commit message convention names categories; the file's structure should match. Future readers can audit each line back to a category.

---

## A19. Bypass pre-commit hooks with `--no-verify`

**✗** `git commit --no-verify -m "cleanup"` because the pre-commit hook is being annoying.
**✓** If a hook fails, fix the underlying issue. If you can't, surface to user.

**Why:** Hooks exist for a reason. `--no-verify` defeats the very mechanism the user installed. Per AGENTS.md "Mandatory explicit plan": don't bypass safety nets.

---

## A20. Use the same destination for files that conflict on basename

**✗** Move `progress_bd-001.md` → `docs/progress/progress_bd-001.md`, then move `subdir/progress_bd-001.md` → `docs/progress/progress_bd-001.md` (collision).
**✓** Detect basename collisions during Phase 5 plan composition; surface to user; pick a sub-path or rename.

**Why:** A `git mv` collision halts the move. Pre-detection in Phase 5 prevents the user-visible failure.

---

## A21. Mass-delete via `git ls-files | xargs git rm`

**✗** `git ls-files | grep -E '\.bak$' | xargs git rm`
**✓** Per-file `git rm` with explicit list, batched per-category in delete_plan.md.

**Why:**
- `xargs` doesn't show what was deleted in the commit.
- No rollback record.
- File names with spaces/unicode break the pipe.
- The categorized commit pattern is more auditable.

---

## A22. Skip the disk-pressure pre-flight before batch mode

**✗** Run a 13-repo cleanup batch without checking `df -h /tmp`.
**✓** `bash scripts/check-disk-pressure.sh` first; halt if /tmp is >85% full or any cache is >5GB.

**Why:** Cass session B (`16d6227e:179`) recorded a 49 GB `/tmp/rch/<project>` cache that filled tmpfs and broke commits across 13 repos at once. Cleanup is fast; disk recovery from a stuck batch is slow. Always pre-flight.

---

## A23. Auto-stage all `D <path>` rows from git status

**✗** `git add -A` blindly when working tree shows `D <path>` deletions.
**✓** PHANTOM-DELETIONS.md flow: detect first; classify each ` D` row as intentional vs. phantom; restore phantoms first.

**Why:** A naive `git add -A` would have committed 1,527 phantom deletions in the cass-mined frankenterm incident, destroying user work. Per Axiom 24, every ` D` row is checked against `git log --diff-filter=D HEAD -1 -- <path>`; if the file's last commit didn't delete it, the deletion is phantom.

---

## A24. Move TOML configs referenced by hardcoded paths in source

**✗** Move `corpus_manifest.toml` from root to `docs/contracts/` because "it's documentation."
**✓** When REFERENCE-GREP finds ≥10 hardcoded path references in source code, mark category DEFERRED. Don't move; flag the cost; let the user decide later.

**Why:** Cass session A frankensqlite — 15 TOML contracts referenced by 20+ Rust files via hardcoded path strings. Moving them would have required 30+ source updates and risked breaking `cargo test`. The Cat-C deferral pattern is the right call: better at root than half-broken.

---

## A25. Auto-rewrite imports in source code

**✗** Edit-tool rewrite of `import scratch` → `import tools.scratch` for a moved Python module.
**✓** Surface every import rewrite to the user; let them confirm before the rewrite runs.

**Why:** Imports go through Python/TypeScript/Rust module resolution. A lexical Edit-tool match might miss aliased imports (`from scratch import X as Y`), re-exports, conditional imports. `↪ REWRITE-REFERENCES` only handles "lexically straightforward" cases; surface the rest.

---

## A26. Trust SHADOWING-AUDIT to cover force-add bypass

**✗** "I added `*.key` to `.gitignore`. SHADOWING-AUDIT showed no tracked `*.key` files. Done."
**✓** Verify via `git ls-files | grep -E '\.key$'` directly. Install `.githooks/pre-commit` as belt-and-suspenders.

**Why:** SHADOWING-AUDIT correctly checks tracked files against the new pattern, but if a `*.key` file was force-added in the past (cass `1101-1135`: the mcp_agent_mail incident), it's tracked despite the rule. The hook prevents recurrence — `git add -f` cannot bypass a pre-commit hook that scans staged paths.

---

## A27. Push to `main:master` mirror without per-repo policy

**✗** Hardcode `git push origin <branch> && git push origin <branch>:master` in batch mode for every repo.
**✓** BATCH-MODE.md branch-policy registry. Per-repo: detect `main`-only vs. `main:master` mirror vs. `master`-only.

**Why:** Cass session B recorded specific exceptions: `ultimate_bug_scanner` and `toon_rust` use `master`; `sqlmodel_rust` also uses `master`. Pushing `<branch>:master` to a `main`-only repo creates a stale `master` branch that confuses everyone.

---

## A28. Run `git filter-repo` on a shallow clone

**✗** `git filter-repo --invert-paths --path <secret> --force` on a clone with 199 commits when origin has 793.
**✓** Per Axiom 16: verify `git rev-list --count <branch> == git rev-list --count origin/<branch>` first. If not, sync via `git update-ref refs/heads/<branch> refs/remotes/origin/<branch>` before filter-repo.

**Why:** Cass `1124-1135` (mcp_agent_mail Apr-27): the first filter-repo run rewrote 199 commits but origin had 594 more. Force-push appeared to succeed but origin still had the secret in the upstream commits. Re-run after sync was required.

---

## A29. Treat curated artifact dirs as build leakage

**✗** Mark `frankenfs/baselines/` for deletion because the name "baselines/" looks like build output.
**✓** Check for marker files (`.contract`, `MANIFEST`, `README`); check git history for long-lived deliberate commits vs. auto-generated.

**Why:** Cass `02a0eb47` (frankenfs) and `3c105d10` (frankenredis): dated benchmark snapshots (`baselines/baseline-20260219.md`, etc.) and versioned validation contracts (`artifacts/phase2c/`) are deliberately tracked. The skill must distinguish "artifact" the noun (junk) from "artifact" the noun (curated test fixture).

---

## A30. Bypass DCG with creative workarounds

**✗** When DCG blocks `rm -rf /tmp/<bundle>`, try `find /tmp/<bundle> -delete` instead.
**✓** Don't fight DCG. The skill never deletes the bundle. The user manages bundle lifecycle.

**Why:** DCG is the user's intentional safety net. Skirting it for "convenience" is exactly the behavior DCG exists to prevent. Cass session B (`16d6227e:179`): the operator generated a `DELETIONS-FOR-OPERATOR.sh` script and asked the user to run it manually rather than try to circumvent.

---

## A31. Touch a repo flagged external-primary-development

**✗** Run cleanup on `asupersync` because it's in `/data/projects` like everything else.
**✓** Read `~/.claude/MEMORY.md` and per-repo `AGENTS.md`; respect explicit external-primary-dev flags.

**Why:** Some repos have their primary development happen on another machine (laptop, server, teammate's checkout). Pushing aggressive cleanups to such a repo creates merge conflicts the agent doesn't see. Cass session B: "asupersync: primary development happens on another machine, large changes risk conflicts." The skill must auto-detect and refuse without explicit override.

---

## A32. Commit a submodule pointer rewind without surfacing

**✗** `git add -A` includes a submodule whose pointer changed; commit goes through; the submodule loses commits silently.
**✓** SUBMODULE-HANDLING.md classifier. `(rewind)` and `-dirty` markers in `git diff --submodule=log/short` halt the auto-commit and surface to user.

**Why:** Cass `0d0fea77:agent-a406d5931e58d2d4a:1-85`: 5 of 8 dirty submodule paths were rewinds. Naive cleanup would have committed 5 destructive rewinds. Submodule classifier prevents this.

---

## A33. Treat numeric-named files as stale data

**✗** See files `18`, `42`, `7` at root; assume they're version numbers; keep them.
**✓** Filename matches `^[0-9]+$` or contains `:` → `numeric-or-shell-escape-name` smell → delete-no-gitignore.

**Why:** These are accidental shell redirections (`cmd > 18`, `cmd > 'GoldHawk: ...'`). They're 100% junk. Cass `03ef995f:agent-aee254f:1`.

---

## A34. Skip MEMORY.md and AGENTS.md in the orient phase

**✗** Run cleanup without reading the user's persistent rules.
**✓** Phase 0 reads `~/.claude/MEMORY.md` AND per-repo `AGENTS.md`/`CLAUDE.md` BEFORE any other work.

**Why:** Both contain explicit policies (which repos are external-primary-dev, which subdirs are frozen, which files are intentionally tracked). Skipping leads to A24 (mass-delete protected files), A28 (clean external-primary-dev repo), etc. The Brennerian opener calibrates this.

---

## A35. Forget that `.gitignore` is per-clone (not global)

**✗** Add `.gitignore` patterns; assume teammates' clones will get them automatically.
**✓** Document that teammates need to pull AND, if relevant, run `git config core.hooksPath .githooks` for the secret-leak prevention hook to fire on their clones.

**Why:** `.gitignore` patterns ship via the repo, but `core.hooksPath` is per-clone (per the user's git config). The INCIDENT-PLAYBOOK.md Step 12 documents this in the AGENTS.md update; without it, new clones don't get the secret-leak guard.
