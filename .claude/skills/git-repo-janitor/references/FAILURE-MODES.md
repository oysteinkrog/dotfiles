# Failure Modes — Diagnostic Playbook

Each failure mode includes: symptom, cause, diagnostic command, recovery action.

---

## F1. `git mv <src> <dest>` fails with "destination exists"

**Symptom:** `fatal: destination exists, source=<src>, destination=<dest>`

**Cause:** The destination path already has a file. Either Phase 6 is being re-run after partial completion, or the destination dir already had a same-named file from a different category, or a concurrent agent already did the move.

**Diagnostic:**
```bash
ls -la <dest>
sha256sum <src> <dest>
git log --diff-filter=R -- <dest>
```

**Recovery:** See [INCIDENT-PLAYBOOK § A `git mv` collision](INCIDENT-PLAYBOOK.md#a-git-mv-collision).

---

## F2. `git rm <path>` fails with "did not match any files"

**Symptom:** `fatal: pathspec '<path>' did not match any files`

**Cause:** Concurrent agent already removed the file, OR the path was relative to the wrong directory, OR the file is `.gitignore`'d (rare for tracked files but possible).

**Diagnostic:**
```bash
git ls-files <path>          # is it still tracked?
git status                    # any pending deletes?
git log --diff-filter=D -- <path>  # was it deleted by another agent?
```

**Recovery:** Mark `applied-by-other-agent` in apply_log.tsv, continue.

---

## F3. SHADOWING-AUDIT surfaces a tracked file under a proposed `.gitignore` rule

**Symptom:** `git ls-files <pattern>` returns one or more paths.

**Cause:** The proposed pattern is too broad and would mask currently-tracked files.

**Diagnostic:**
```bash
git ls-files <pattern>
# Inspect each match — is it intentional or a mistake?
```

**Recovery:** Either narrow the glob, add a negation rule (`!<specific-path>`), OR pair the addition with `git rm --cached <files>` and verbatim-auth from user. See [GITIGNORE-CRAFT.md § shadowing](GITIGNORE-CRAFT.md).

---

## F4. Bundle SHA-256 mismatch in Phase 3

**Symptom:** `bundle_verification.log` has a `MISMATCH: <path> live=<sha1> bundle=<sha2>` line.

**Cause:** File changed between Phase 2 inventory and Phase 3 bundle copy. Concurrent agent edit; LFS smudge issue; autocrlf normalization.

**Diagnostic:**
```bash
git status -- <path>           # uncommitted changes from another agent?
git lfs ls-files | grep <path>  # is it LFS?
git config core.autocrlf
```

**Recovery:**
1. Re-snapshot working tree.
2. If LFS: re-do `git lfs smudge`.
3. If autocrlf: configure `core.autocrlf=false` for the session.
4. Re-run Phase 2 + Phase 3.

If after 2 retries the SHAs still don't match: HALT. The repo is unsafe to operate on.

---

## F5. Reference rewrite breaks the build

**Symptom:** `cargo check` (or equivalent) fails after a Phase 6 batch, and the failures touch files the skill rewrote.

**Cause:** A path-constant rewrite was correct lexically but wrong semantically (e.g., the new path doesn't exist yet because the dir wasn't created in time, or the path crosses a workspace boundary).

**Diagnostic:** Read the build error. Cross-reference against `reference_rewrite_log.tsv` for any rewrite in the affected files.

**Recovery:** See [INCIDENT-PLAYBOOK § A reference rewrite breaks the build](INCIDENT-PLAYBOOK.md#a-reference-rewrite-breaks-the-build).

---

## F6. Phase 4 misclassifies a file (false-positive delete)

**Symptom:** Phase 9 fresh-eyes catches that a file the skill marked `delete-and-gitignore` was actually a referenced test fixture.

**Cause:** REFERENCE-GREP missed the reference because of:
- An aliased import (`from scratch import helper as h`, then `h()` called).
- A reference inside a string that looks like a doc-comment, but is actually an `os.path.join` arg at runtime.
- A reference inside a build script (Makefile, Justfile) that the grep-include list missed.

**Diagnostic:** `grep -rn "<basename-without-ext>" --include="*"` (no extension filter) and inspect each hit.

**Recovery:** Add the file's reference back via [RECOVERY-RECIPES § Restore one file](RECOVERY-RECIPES.md). Update the skill's grep include list to catch the missed reference type for future runs.

---

## F7. `git filter-repo` rewrote only part of history

**Symptom:** After force-push, `git log origin/<branch> -- <secret-path>` still shows the path.

**Cause:** Local clone was shallow / partial; origin had more commits than local. Axiom 16 violated.

**Diagnostic:**
```bash
git rev-list --count <branch>
git rev-list --count origin/<branch>
# If different: shallow-clone trap
```

**Recovery:** See [INCIDENT-PLAYBOOK § A `git filter-repo` was run but origin still has the secret](INCIDENT-PLAYBOOK.md#a-git-filter-repo-was-run-but-origin-still-has-the-secret).

---

## F8. Pre-commit hook blocks legitimate file

**Symptom:** `git commit` fails with "Pre-commit blocked: likely secret file(s) staged" but the file is a documented test fixture.

**Cause:** Hook's filename rules are too aggressive.

**Diagnostic:** Inspect the staged file vs. the hook's pattern set.

**Recovery:**
1. If false-positive: edit `.githooks/pre-commit` to add a more specific allowlist exception. Smoke-test the change.
2. If one-off: `git commit --no-verify -m "test fixture; reviewed and confirmed safe"` is the documented escape hatch.

---

## F9. Concurrent agent committed a candidate mid-Phase 6

**Symptom:** `git mv` succeeds but `git commit` shows the wrong files (other agent's commits interleaved).

**Cause:** Concurrent agent committed between Phase 6's `git mv` and Phase 6's `git commit`.

**Diagnostic:** `git log --oneline -5` shows commits not authored by the skill.

**Recovery:** This is normal. Continue. Per AGENTS.md: treat as if you committed them. The reference graph and apply_log still work — they're keyed by file paths and commit SHAs.

---

## F10. `.gitignore` was modified mid-run

**Symptom:** Phase 8 SHADOWING-AUDIT shows different results than Phase 5 expected; the `.gitignore` file's diff shows lines the skill didn't add.

**Cause:** Concurrent agent edited `.gitignore` (rare; usually agents avoid this).

**Diagnostic:** `git log -- .gitignore` shows recent commits.

**Recovery:** Re-run Phase 5's SHADOWING-AUDIT against the new `.gitignore`. Update the proposed diff. Re-confirm with user if any pattern landed for free.

---

## F11. Beads database is locked

**Symptom:** `br create ...` fails with "database is locked".

**Cause:** A parallel `br` process holds the lock.

**Diagnostic:** `lsof .beads/beads.db` to find the holder.

**Recovery:** Skip the beads-issue creation; record `beads_skipped: true` in the handoff report. The run still succeeds.

---

## F12. The user's git config has unusual settings

**Symptom:** `git mv` doesn't preserve rename detection; `git diff` shows weird whitespace; `git log --follow` doesn't follow.

**Cause:** `core.autocrlf=true`, `merge.renameLimit=0`, `diff.renames=false`, etc.

**Diagnostic:** `git config --list | grep -E '^(core|diff|merge)\.'`

**Recovery:** The skill never modifies user git config. Surface unusual settings to the user; they decide whether to override per-session (`git -c diff.renames=true ...`) or globally.

---

## F13. The skill is invoked on a sub-directory of a repo

**Symptom:** `git ls-files` returns paths but they're relative to the sub-dir, not the repo root.

**Cause:** Skill was invoked from `/data/projects/<repo>/crates/<sub>/` instead of `/data/projects/<repo>/`.

**Diagnostic:** `git rev-parse --show-toplevel` returns a path that's a parent of the cwd.

**Recovery:** `scripts/git-doctor.sh` resolves to repo root and operates from there. Surface to user that the run will cover the entire repo, not just the sub-dir.

---

## F14. Working-tree drift mid-Phase 9 fresh-eyes

**Symptom:** Phase 9 round 2 finds new findings that round 1 didn't have.

**Cause:** Concurrent agents committed changes that triggered new issues (e.g., a new file was added that has stale references to a moved path).

**Recovery:** Rounds aren't strictly idempotent in active repos; document the new findings, fix them, run another round. The "≥2 clean rounds" rule is about consistency at termination, not perfect determinism.

---

## F15. Phase 2.5 finds a `.pub` without a matching `.key`

**Symptom:** `signing-77c6e768.pub` is present but no `.key` is in the working tree.

**Cause:** Either the `.key` was never committed (safe, the `.pub` is legitimate) OR the `.key` was committed historically and is now in the git history but not in the working tree.

**Diagnostic:**
```bash
git log --all -- '*signing-*.key' | head -10
```

If git history shows the `.key`: a previous attempt removed it from the working tree but didn't filter-repo. The history still has it. ESCALATE: this is a partial-mitigation state — the user thinks the leak is fixed but origin still has it.

**Recovery:** Run the secret-leak playbook for the historical `.key` reference.

---

## F16. The user's repo doesn't push `main` → `master` synonym

**Symptom:** Skill prints `git push origin <branch>:master` but the user gets "remote rejected: master is not a tracking branch."

**Cause:** Auto-detected synonym was wrong; not every repo follows the frankensqlite/CASS pattern.

**Recovery:** The skill's Phase 1 should have detected `branch_synonyms=[]` from `git branch -r | grep master`. If it falsely populated `["master"]`, the user can override at Phase 0 confirmation, or just ignore the synonym push command.

---

## F17. `cargo check` is slow, gates take forever per-commit

**Symptom:** Phase 6 commits each take 5+ minutes because gates re-compile the world.

**Cause:** `cargo check --workspace` recompiles every crate on incremental changes.

**Recovery:** Scope gates per-batch:
- For moves that only touch markdown / non-code files: skip `cargo check` entirely; rely on Phase 9 full gate sweep.
- For moves that touch source code (reference rewrites): scope `cargo check -p <affected-crate>`.
- Capture the gate timing in `apply_log.tsv` so the user sees the per-commit duration; if it's too slow they can move to Comprehensive variant (which uses fewer, larger commits).

---

## F18. `tar czf <bundle>.tar.gz <bundle>` fails for users wanting to share

**Symptom:** User wants to send the bundle to a teammate; `tar` fails because of LFS smudged blobs (large files).

**Cause:** Bundle's `working-tree-copies/` may contain large blobs (LFS-smudged content); `tar` works fine but the resulting archive may be huge.

**Recovery:** Document the LFS situation; suggest `tar czf <bundle>-no-lfs.tar.gz --exclude='working-tree-copies/path/to/large-blob' <bundle>` if the recipient doesn't need the LFS blobs.

---

## F19. /tmp build-cache exhaustion mid-cleanup

**Symptom:** Mid-Phase 6, commands fail with "no space left on device" or "cannot allocate memory." `df -h /tmp` shows /tmp at 100% full.

**Cause:** A background build cache (e.g., `/tmp/rch/<project>` from rch, or `/tmp/cargo*` from cargo) has filled tmpfs. The skill itself isn't using much; another tool is.

**Diagnostic:**
```bash
df -h /tmp
du -sh /tmp/* 2>/dev/null | sort -rh | head -20
```

**Recovery:**
1. Halt the cleanup (the skill auto-halts on disk-pressure detection).
2. Surface to user: "We need to clean up /tmp before continuing. Suggested commands:"
3. Common cleanups: `rm -rf /tmp/rch /tmp/cargo*` (or DCG-blocked; user runs manually).
4. Verify free space recovered.
5. Resume the skill via `run_state.json`.

**Prevention:** Phase 0 disk-pressure pre-flight via `scripts/check-disk-pressure.sh`. Source: cass session B (`16d6227e:179` — 49 GB rch cache nearly broke a 13-repo run).

---

## F20. Concurrent-agent commit race

**Symptom:** Phase 6 runs `git commit`; commit fails with "your branch is behind origin/<branch>" or with merge conflicts.

**Cause:** Another agent staged + committed to the same branch between this skill's `git diff --staged` snapshot and the commit.

**Diagnostic:**
```bash
git fetch origin
git log --oneline origin/<branch>..<branch>
git log --oneline <branch>..origin/<branch>
```

**Recovery:**
1. Re-snapshot via `scripts/snapshot-tree.sh phase6_retry`.
2. Compare to the planned change-set; if drift introduced new files, re-classify.
3. If drift is ahead-of-base: `git pull --rebase` (the skill is on a fresh recovery branch, so rebase against origin/<recovery-branch> if exists; against `origin/<primary>` otherwise).
4. Re-attempt the commit.

If after 3 retries the conflict persists: HALT. The other agent is in active conflict; the user must coordinate.

Source: cass session B (`16d6227e:179`); cass session A (`0d0fea77:96`).

---

## F21. Push to `main:master` mirror divergence

**Symptom:** `git push origin main:master` fails with "non-fast-forward."

**Cause:** Origin's `master` branch is ahead of origin's `main` (the mirror got updated by a different process). Standard `--force-with-lease` push doesn't help because lease check is per-ref.

**Diagnostic:**
```bash
git fetch origin
git log origin/main..origin/master   # commits on master not on main
git log origin/master..origin/main   # commits on main not on master
```

**Recovery:**
1. Investigate the divergence cause.
2. If origin/master is genuinely ahead (someone pushed there directly): manual reconciliation; user merges or chooses one.
3. If origin/master is just stale: `git push --force-with-lease origin main:master` will work after a fresh fetch.

**Prevention:** BATCH-MODE.md branch-policy registry. Source: cass session B (`16d6227e:179` — asupersync mirror divergence).

---

## F22. Phantom-deletion commit trap

**Symptom:** A naive cleanup auto-stages all `D <path>` rows from `git status`; the resulting commit deletes 1500+ files the user wanted to keep.

**Cause:** Files were `rm`'d outside git (intentionally or accidentally) but never staged. `git add -A` would commit those deletions.

**Diagnostic:** `scripts/detect-phantom-deletions.sh` per Axiom 24.

**Recovery:** PHANTOM-DELETIONS.md restoration script. Layer 3 git revert if commits already landed.

**Prevention:** Phase 1.5 phantom-deletion detection (mandatory). Source: cass sessions `4f24d3e7:agent-a71d4204...` (frankenterm 1527 phantom deletions) and `agent-a38de5a0...` (frankenterm-rch 1524 phantom deletions).

---

## F23. Vercel ignored-build script silently moved away

**Symptom:** Cleanup completes successfully; days later, Vercel deployment fails with `bash: scripts/vercel-ignore-build.sh: No such file or directory`.

**Cause:** Phase 6 moved `scripts/vercel-ignore-build.sh` (or analogous CI/CD script). The reference in `vercel.json` (or `.github/workflows/`, `wrangler.toml`, `netlify.toml`, etc.) was not in REFERENCE-GREP's scope.

**Diagnostic:** Read `vercel.json`, `.github/workflows/*.yml`, `wrangler.toml`; grep for the moved path.

**Recovery:**
1. Either restore the script to its original location (Layer 1: `git checkout refs/repo-janitor-backup/<DATE>-pre-cleanup -- scripts/vercel-ignore-build.sh`).
2. OR update the `vercel.json` reference via Edit tool.
3. Re-deploy.

**Prevention:** REFERENCE-GREP scope must include `vercel.json`, `netlify.toml`, `wrangler.toml`, `*.cloudbuild.yaml`, `.github/workflows/*.yml`, `Dockerfile*`, `Makefile`. Source: cass session `3478dbbc:agent-a500553:1` (historical_soldiers Vercel build failure).

---

## F24. Submodule `-dirty` suffix mis-classified as a normal pointer change

**Symptom:** Phase 6 auto-stages a submodule pointer change; commit later produces an "incomplete" submodule reference.

**Cause:** The submodule's working tree had uncommitted changes (`-dirty` suffix in `git diff --submodule=short`). Committing the pointer doesn't capture those changes.

**Diagnostic:**
```bash
git diff --submodule=short | grep -- '-dirty'
git diff --submodule=log
```

**Recovery:**
1. `cd <submodule-path>; git status` to see uncommitted changes.
2. Decide: commit them inside the submodule (separate commit, separate push) OR discard.
3. Refresh parent repo; re-attempt.

**Prevention:** SUBMODULE-HANDLING.md classifier (`scripts/detect-submodule-issues.sh`). Source: cass session `0d0fea77:agent-a406d5931e58d2d4a:1-85` (Rust compiler repo with 8 dirty submodule paths).

---

## F25. Curated artifact dir misread as junk

**Symptom:** Phase 4 marks `frankenfs/baselines/` for deletion; Phase 5 user catches it but only because they're paying close attention.

**Cause:** The dir name "baselines/" looks like build output, but it's a versioned dataset/contract directory (dated benchmark snapshots that are deliberately tracked).

**Diagnostic:** Check for marker files (`.contract`, `MANIFEST`, `README`); check git history (long-lived, deliberate commits, not auto-generated).

**Recovery:** User overrides the verdict at Phase 5; skill records in `user_overrides.tsv`.

**Prevention:** Phase 4 triage workers should check for marker files before flagging dirs as junk. Phase 0 user-supplied protected_globs is the explicit allowlist. Source: cass sessions `02a0eb47:agent-ac7ffc8:1` (frankenfs/baselines/), `3c105d10:agent-aa5afbc:1` (frankenredis/artifacts/phase2c/).

---

## F26. Numerically-named files and shell-escape names

**Symptom:** Files like `18`, `42`, `7`, `GoldHawk:`, `SilverFox:` appear at root.

**Cause:** Accidental shell redirection (e.g., `cmd > 18` instead of `cmd > log18.txt`; or scripts that print "GoldHawk: ..." being captured by `> output`).

**Diagnostic:** filename matches `^[0-9]+$` or contains `:`; content is typically log-like or random.

**Recovery:** Verdict `delete-no-gitignore` (one-off; pattern won't recur cleanly).

**Prevention:** Add `^[0-9]+$` and `*[:]*` filename smell rules to FILE-SMELLS.md. Source: cass session `03ef995f:agent-aee254f:1` (mcp_agent_mail).

---

## F27. Stale legacy pre-commit hook

**Symptom:** Every `git commit` fails with "bd sync --flush-only: command not found" or similar.

**Cause:** Project migrated from one tool to another (e.g., Go beads `bd` → Rust beads `br`) but the old pre-commit hook stayed installed.

**Diagnostic:** `cat .git/hooks/pre-commit` (or `cat .githooks/pre-commit`); look for references to migrated tools.

**Recovery:**
1. Verify the hook is genuinely stale (not catching real issues).
2. Disable: `chmod -x .git/hooks/pre-commit` OR `git config core.hooksPath /dev/null` for the session.
3. After cleanup completes: re-enable or replace the hook.

**Prevention:** Phase 0 hook detection; flag stale hooks. Source: cass session B (`16d6227e:179` — sqlmodel_rust legacy `bd` hook).

---

## F28. External-primary-development repo accidentally cleaned

**Symptom:** User runs cleanup on a repo that's primary-developed elsewhere (e.g., `asupersync` per the user's MEMORY.md). The cleanup creates commits + push commands; pushing them creates merge conflicts with the other machine's work.

**Cause:** Skill didn't check MEMORY.md for the external-primary-dev list.

**Recovery:**
1. DON'T push the recovery branch.
2. `git revert` the cleanup commits OR delete the recovery branch and discard.
3. Add the repo to MEMORY.md's external-primary-dev list explicitly.

**Prevention:** Phase 0 reads `~/.claude/MEMORY.md`; refuses to mutate any repo in the external-primary-dev list. BATCH-MODE.md skip-list-first principle. Source: cass session B (`16d6227e:179` — asupersync warning).

---

## F29. Force-add bypass in `.gitignore` audit

**Symptom:** Phase 8 SHADOWING-AUDIT shows zero shadowed tracked files for a `*.key` pattern; the user assumes no `*.key` files exist; later, `git status` reveals a tracked `signing-X.key`.

**Cause:** The `*.key` was force-added with `git add -f` despite the `.gitignore` rule. SHADOWING-AUDIT (which runs `git ls-files <glob>`) correctly returns the tracked file. If we missed it, our query was wrong.

**Diagnostic:**
```bash
git ls-files | grep -E '\.key$'   # always reveals force-added .key files
```

**Recovery:** This is the secret-leak case. INCIDENT-PLAYBOOK § Secret Leak.

**Prevention:** SHADOWING-AUDIT must use `git ls-files <pattern>` literally; never trust `.gitignore` to imply no tracked files. Source: Apr-27 mcp_agent_mail Ed25519 key incident.
