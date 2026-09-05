# Self-Test

Trigger phrases that should activate this skill. If any of these fail to wake the skill, re-run `/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools` (or rewrite the description by hand) and tighten the description in SKILL.md frontmatter.

---

## Should trigger

- "Clean up my repo's tree — there's a bunch of junk committed"
- "I have random `.db` and `.json` files at the project root"
- "An agent left intermediate `.md` reports in the repo root — clean them up"
- "Tidy this repo — get the ad-hoc scripts out of the project root"
- "The repo junk cleaner pass on `<path>`"
- "Move the planning docs to `docs/` and delete the temp files"
- "Audit my repo for files that shouldn't be tracked"
- "What committed files are actually ephemeral artifacts?"
- "Help me figure out which root-level files belong elsewhere"
- "Sweep the repo for SQLite databases, `.wal` files, and other junk that should be `.gitignore`d"
- "I have 100+ files at the project root and most don't belong there"
- "Clean up my repo so people don't think the code is messy from the file list"
- "There are old planning docs and skill outputs at root — sort them out"
- "Repo janitor pass on `<path>`"
- "I want to remove ephemeral detritus from my repo and add the patterns to `.gitignore`"
- "Find tracked files that should never have been committed (binaries, logs, scratch scripts)"

---

## Less obvious phrasings that should also trigger

- "My repo root is a mess; sort the files into proper directories"
- "Help me find all the cruft accumulated from agent runs"
- "There are dozens of `.bak` and `.tmp` files committed; remove them"
- "Untrack everything that should never have been committed"
- "I need a `.gitignore` audit — what's tracked that shouldn't be?"
- "Phase out the SQLite WAL files that got committed"
- "Old benchmark JSON / `*.profraw` / coverage outputs are tracked — clean up"
- "Get rid of `nohup.out` / `findings.jsonl` / random `progress_bd-*.md` at root"
- "Resume a prior repo-cleanup run on this project" (then run `phase-status.sh`)
- "Archive the old cleanup workspace and start fresh" (resumability path)
- "What's the next phase to run on this cleanup?" (use `phase-status.sh`)
- "An agent committed an Ed25519 key — get it out of history" (escalates to `harden-secret-leak` mode)
- "We just merged a refactor that left orphan files at root — clean them up"
- "Apply a `.gitignore` rule and untrack the matching files in one go"

---

## Should NOT trigger

- "Stash my current changes" → `/git-stash-janitor` (or just `git stash push`)
- "Clean up my git stashes" → `/git-stash-janitor`
- "Recover a deleted file" → `git reflog` or `git checkout <sha> -- <path>`
- "Clean up old branches" → manual `git branch -d`
- "Squash my commits before pushing" → interactive rebase
- "Delete a single file" → `git rm <file>`; this skill is for repo-wide audits
- "Build a documentation site" → `/documentation-website-for-software-project`
- "Run tests on my repo" → `/release-preparations`
- "Scan for security vulnerabilities" → `/ubs` or `/security-audit-for-saas`
- "What does `.gitignore` do?" → general git docs
- "Set up `.gitignore` for a fresh project" → `gh-actions` template seeds OR a generic gitignore generator
- "I forgot to commit my changes" → `git status` + `git add` + `git commit`
- "I need to remove a leaked secret from history" → this skill's [INCIDENT-PLAYBOOK § Secret Leak](references/INCIDENT-PLAYBOOK.md#secret-leak-recovery) covers it as an *escalation path*, but the user's primary intent is secret rotation, not janitorial cleanup. The skill should still be useful here, just biased to the secret-leak flow.

---

## End-to-end smoke test on a synthetic dirty repo

The skill should categorize these candidates correctly. The dummy repo emulates a real Apr-27 cleanup target (frankensqlite-style polyglot repo with planning docs, scratch scripts, ELF binaries, log leakage, and one secret).

```bash
# Setup: dummy repo with junk
mkdir -p /tmp/repo-janitor-smoke && cd /tmp/repo-janitor-smoke
git init -q -b main
echo "# DummyProject" > README.md
echo "[package]" > Cargo.toml
echo 'name = "dummy"' >> Cargo.toml
mkdir -p src docs
echo "fn main() {}" > src/main.rs

# Plan docs at root (should MOVE to docs/planning/)
echo "# Comprehensive Plan v1" > COMPREHENSIVE_PLAN_FOR_DUMMY.md
echo "# Architecture Proposal" > PROPOSED_ARCHITECTURE.md
echo "# Multi-LLM plan from GPT" > PLAN_TO_PORT_DUMMY__GPT.md
echo "# Multi-LLM plan from Opus" > PLAN_TO_PORT_DUMMY__OPUS.md

# Per-bead progress reports (should MOVE to docs/progress/ + .gitignore)
echo "wip on bd-abc" > progress_bd-abc.md
echo "wip on bd-def" > progress_bd-def.md

# Skill output (should DELETE + .gitignore)
echo "# Skill Loop Progress" > .skill-loop-progress.md

# Scratch scripts (should DELETE)
echo "import json; print('scratch')" > check_db.py
echo "echo scratch" > fix_beads.sh

# Ephemeral logs (should DELETE + .gitignore)
echo "hello" > nohup.out

# Stray ELF binary (should DELETE; simulate by writing magic bytes)
printf '\x7fELF\x02\x01\x01' > test_ptr

# Dev SQLite DB (should DELETE + .gitignore, also `*-wal`/`*-shm`)
sqlite3 storage.sqlite3 'CREATE TABLE t (x INT);' 2>/dev/null || echo "" > storage.sqlite3
touch storage.sqlite3-wal storage.sqlite3-shm

# Stray JSON artifact (should DELETE)
echo '{"scan": "size 0"}' > findings.jsonl

# Old-format duplicate (the .png is the predecessor; .webp is referenced by README)
echo "png-bytes" > illustration.png
echo "webp-bytes" > illustration.webp
echo '<img src="illustration.webp">' >> README.md

# Secret leak (Phase 2.5 should HALT)
printf 'SECRET-32-BYTES-EXACTLY-1234567' > signing-deadbeef.key  # 32-byte fake Ed25519 seed
printf 'public-key-44chars-fake-fake-fake-fake-fake' > signing-deadbeef.pub

git add -A
git commit -q -m "initial"

# Confirm setup
git ls-files | wc -l                 # ~16 tracked files
ls *.py *.sh *.md storage.* 2>/dev/null
```

Invoke the skill with: "Clean up the repo at `/tmp/repo-janitor-smoke`".

Expected behavior:

1. **Phase 0** — skill detects 16+ tracked files; tells the user the count; warns "Quick mode" for ~10–24; archetype detection labels it as `single-rust-crate` (Cargo.toml + `src/main.rs`).
2. **Phase 1** — `project_profile.json` has `primary_branch=main`, `archetype=single-rust-crate`, `test_command=cargo test --workspace`, `protected_globs=["Cargo.toml","Cargo.lock","src/**","README.md","LICENSE*"]`.
3. **Phase 2** — `candidates.tsv` lists the 13 junk-smelling files. `reference_graph.json` shows `illustration.webp` referenced by README, `illustration.png` referenced by nothing.
4. **Phase 2.5 — SECRET LEAK SCAN — should HALT.** `signing-deadbeef.key` is 32 bytes and matches the `signing-*.key` smell rule. Skill surfaces the leak with the literal SHA, asks the user to rotate the key first, and offers the secret-rotation flow.
5. **For the smoke test, reply** "this is a fake test secret in a dummy repo, please proceed with the rest of the cleanup using gitignore-only verdict for it". Skill records the override in `user_overrides.tsv`.
6. **Phase 3** — bundle has 13 working-tree-copies, byte-equality verified.
7. **Phase 4 triage** produces (verdict in caps):
   - `COMPREHENSIVE_PLAN_FOR_DUMMY.md`, `PROPOSED_ARCHITECTURE.md`, `PLAN_TO_PORT_DUMMY__GPT.md`, `PLAN_TO_PORT_DUMMY__OPUS.md` → MOVE to `docs/planning/`
   - `progress_bd-abc.md`, `progress_bd-def.md` → MOVE to `docs/progress/` + `.gitignore` add
   - `.skill-loop-progress.md` → DELETE-AND-GITIGNORE
   - `check_db.py`, `fix_beads.sh`, `findings.jsonl` → DELETE
   - `nohup.out` → DELETE-AND-GITIGNORE
   - `test_ptr` → DELETE (stray ELF)
   - `storage.sqlite3`, `storage.sqlite3-wal`, `storage.sqlite3-shm` → DELETE-AND-GITIGNORE (`storage*.sqlite3*`)
   - `illustration.png` → DELETE (unreferenced; the `.webp` is referenced by README)
   - `signing-deadbeef.key` → SURFACE-TO-USER (per smoke-test override: GITIGNORE-ONLY for the dummy)
8. **Phase 5** — `triage_decision.md` groups by category; user types "go" / "proceed".
9. **Phase 6** — moves applied via `git mv`; `progress_bd-abc.md → docs/progress/progress_bd-abc.md` etc; per-commit `cargo check` (or skipped if no real Rust code) passes.
10. **Phase 7** — `git rm` per glob batch; one commit per logical batch (binaries, scratch scripts, sqlite/wal, etc.).
11. **Phase 8** — `.gitignore` updated with `nohup.out`, `.skill-loop-progress.md`, `/progress_bd-*.md`, `/bd-*.md`, `storage*.sqlite3*`, `signing-*.key`. Shadowing audit shows no shadowing of remaining tracked files.
12. **Phase 9** — fresh-eyes ≥2 clean rounds.
13. **Phase 10** — handoff report shows `13 candidates → 6 moved + 6 deleted + 1 gitignore-only + 0 still pending`. Push command printed.

A run that miscategorizes any of the 13 candidates is a failure for this smoke test.

---

## End-to-end smoke test on the secret-leak path

```bash
mkdir -p /tmp/repo-janitor-secret && cd /tmp/repo-janitor-secret
git init -q -b main
echo "# Repo" > README.md
git add README.md && git commit -q -m initial
# Inject a secret a few commits in
echo "fn main() {}" > main.rs
git add main.rs && git commit -q -m "add main"
printf 'REAL-LOOKING-SECRET-32-BYTES-aaaa' > signing-cafef00d.key  # 32 bytes
git add -f signing-cafef00d.key  # force-add bypasses any .gitignore
git commit -q -m "add config"
echo "another change" >> main.rs
git add main.rs && git commit -q -m "more"
```

Invoke: "clean up `/tmp/repo-janitor-secret`".

Expected:

1. Phase 2.5 surfaces the `signing-cafef00d.key` with full provenance: introduced in commit `<sha>` from "add config", **force-added despite no `.gitignore` rule yet**.
2. Skill asks the user to confirm: (a) is the key real, (b) rotate it now if so, (c) proceed with the secret-rotation flow.
3. If user says "go": mirror-backup → `git filter-repo --invert-paths --path 'signing-cafef00d.key' --force` → verify origin sync (Axiom 16) — N/A in this dummy because there's no remote → broaden `.gitignore` (`signing-*.key`, `*.pem`, `*_secret*`, `id_rsa*`, `id_ed25519*`, `.env`) → install `.githooks/pre-commit` → smoke-test the hook by staging a fake new key and confirming the commit is blocked → document in AGENTS.md.
4. Skill prints the force-push commands but does **not** run them; user pushes.

A run that does any of the following fails this smoke test:
- Skips Phase 2.5 and treats the key as a normal `delete-and-gitignore` candidate
- Runs `git filter-repo` without first running the mirror backup
- Skips the shallow-clone check (Axiom 16) when origin has more commits than local
- Pushes the rewritten history on the user's behalf
- Edits `signing-cafef00d.key` (or any file) using `sed -i` for the cleanup

---

## Smoke test on this skill's static structure

```bash
SKILL_DIR=/data/projects/je_private_skills_repo/.claude/skills/git-repo-janitor

# Frontmatter parses
head -8 "$SKILL_DIR/SKILL.md" | grep -E '^name:|^description:'

# Every reference exists
for f in "$SKILL_DIR/references"/*.md; do
  [[ -f "$f" ]] || echo "MISSING: $f"
done

# Every subagent exists
for f in "$SKILL_DIR/subagents"/*.md; do
  [[ -f "$f" ]] || echo "MISSING: $f"
done

# Every script is executable + has shebang
for s in "$SKILL_DIR/scripts"/*.sh; do
  [[ -x "$s" ]] || echo "NOT EXECUTABLE: $s"
  head -1 "$s" | grep -q '^#!' || echo "NO SHEBANG: $s"
done

# discover-project.sh works on a real repo
bash "$SKILL_DIR/scripts/discover-project.sh" "$SKILL_DIR/../../.." 2>&1 | grep -E 'primary_branch|archetype|test_command'
```

Expected: no errors, frontmatter has both fields, all references / subagents / scripts present, discover-project produces a profile with archetype detected.

---

## Resumption smoke test

```bash
# Run the skill on /tmp/repo-janitor-smoke; kill mid-Phase 6 (after 1-2 moves committed).
# Re-run; verify:
# - Phase 1 re-uses project_profile.json
# - Phase 2 re-runs (cheap)
# - Phase 2.5 re-runs (cheap; security regression-check)
# - Phase 3 detects existing bundle, re-verifies (skips re-build if intact)
# - Phase 4 re-runs only un-batched ranges
# - Phase 5 re-presents the table
# - Phase 6 reads apply_log.tsv and skips already-committed moves
# - Phase 7/8 not yet started → run normally
# - No duplicate commits authored
# - Reference rewrites that were already done aren't redone
```

---

## Idempotence smoke test

```bash
# Run the skill on a clean repo:
cd /tmp && mkdir -p clean-repo && cd clean-repo
git init -q -b main
echo "# clean" > README.md && git add . && git commit -q -m init

# Invoke skill: "Clean up my repo at /tmp/clean-repo"
# Expected:
# - Phase 1 produces project_profile.json
# - Phase 2 produces empty candidates.tsv
# - Phase 2.5 finds no secrets
# - Phase 3 produces empty bundle
# - Phases 4-9 short-circuit
# - Phase 10 emits "0 candidates triaged, 0 commits authored, repo already tidy"
# - No commits on the repo
# - .gitignore unchanged
```

---

## Validation checklist (when forking / extending this skill)

- [ ] Frontmatter starts at line 1 (no blank line before `---`)
- [ ] Description is third-person and includes "Use when" triggers
- [ ] SKILL.md body fits the spine; depth is in references/
- [ ] Every reference linked from SKILL.md exists
- [ ] Every subagent linked from SKILL.md exists
- [ ] Every script is executable + has a shebang
- [ ] `git rm` is the ONLY filesystem-deletion verb the skill recommends; `rm`/`find -delete`/`xargs rm` never appear as recommended commands
- [ ] `git mv` is the ONLY rename verb; `mv` + `git add` never appears
- [ ] `git filter-repo` is mentioned ONLY in the secret-leak playbook and only with the mirror-backup + Axiom-16 shallow-clone guard
- [ ] The SHADOWING-AUDIT operator (`git ls-files <glob>`) is referenced in: SKILL.md axiom 6, OPERATOR-LIBRARY.md `🛡 SHADOWING-AUDIT` card, scripts/update-gitignore.sh sanity check, subagents/gitignore-author.md
- [ ] The "force-add bypass" failure mode appears in: SKILL.md failure modes, INCIDENT-PLAYBOOK.md, subagents/gitignore-author.md, FAILURE-MODES.md
- [ ] The Axiom 16 shallow-clone-corrupts-filter-repo guard is referenced in: SKILL.md kernel, INCIDENT-PLAYBOOK.md secret-leak section, scripts/git-doctor.sh, RECOVERY-RECIPES.md
