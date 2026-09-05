# `.gitignore` Craft

The skill's most language-specific concern. `.gitignore` semantics have multiple footguns; this reference codifies the rules.

---

## The semantics that matter

1. **`.gitignore` only affects untracked files.** Adding a glob to `.gitignore` does NOT remove already-tracked files from the index. To stop tracking a file you also have to `git rm --cached <file>` (and commit the removal).
2. **Order matters.** Later patterns override earlier ones — `*.log` then `!important.log` un-ignores a specific file.
3. **Anchoring matters.** `temp/` matches any directory named `temp` anywhere; `/temp/` matches only the repo-root `temp/`.
4. **Trailing slashes matter.** `temp` matches files AND directories named `temp`; `temp/` matches only directories.
5. **`*` doesn't cross slashes.** `temp_*` matches `temp_a.py` but not `subdir/temp_a.py`. Use `**/temp_*` for any-depth.
6. **A negation rule cannot un-ignore a file inside an already-ignored directory.** If `target/` is ignored, `!target/important.txt` won't work; the directory itself is excluded from traversal.

---

## The skill's `.gitignore` change protocol

For every proposed addition, the gitignore-author subagent:

1. **Compute the candidate set the rule would shadow:**
   ```bash
   git ls-files <pattern>
   ```
2. **If non-empty:** the rule shadows tracked files. Two paths:
   - Pair the addition with `git rm --cached <files>` in the same commit (the user wants to *both* untrack AND prevent recurrence).
   - Narrow the glob OR add a `!path/to/specific/file` negation rule.
3. **If empty:** the rule is forward-only. Just add it.
4. **Always run `git check-ignore -v <fake-test-path-matching-pattern>`** after the commit to verify the new pattern fires correctly.
5. **Group additions thematically** in the file (preserve existing structure):
   ```gitignore
   # SQLite dev/test databases
   *.sqlite
   *.sqlite3
   *.db
   *.sqlite-wal
   *.sqlite-shm
   storage*.sqlite3*

   # Skill outputs
   .skill-loop-progress.md
   .skill-*-progress.md

   # Per-bead progress (use docs/progress/ instead)
   /progress.md
   /progress_bd-*.md
   /bd-*.md
   ```

---

## Common rule recipes

### SQLite dev databases
```gitignore
# Generic SQLite (extensive)
*.sqlite
*.sqlite3
*.db
*.db3
# WAL/SHM/journal siblings
*.sqlite-wal
*.sqlite-shm
*.sqlite-journal
*.sqlite3-wal
*.sqlite3-shm
*.db-wal
*.db-shm
*.db-journal
# Common dev names
storage*
storage.sqlite3*
dev.sqlite*
test.db*
```

### Skill outputs (the Apr-27 pattern)
```gitignore
# Slash-skill intermediate outputs
.skill-loop-progress.md
.skill-*-progress.md
.simplify-and-refactor-progress.md
.modes-of-reasoning-output.md
```

### Per-bead progress (the frankensqlite pattern)
```gitignore
# Per-bead progress reports — use docs/progress/ instead
/progress.md
/progress_bd-*.md
/bd-*.md
```

### Tool outputs
```gitignore
nohup.out
*.log
!CHANGELOG.md   # in case wildcard would catch this
*.profraw
*.profdata
lcov.info
.coverage
.coverage.*
coverage_report.*
coverage*.json
coverage*.txt
findings.jsonl
ubs_*.jsonl
ubs_crit.jsonl
rustc-ice-*.txt
*.snap.new
*.snap.tmp
```

### Editor / OS detritus
```gitignore
# Editor backups
*.bak
*~
*.swp
*.swo
*.orig
*.rej
# IDE state
.vscode/
.idea/
*.iml
.zed/
# OS files
.DS_Store
Thumbs.db
Desktop.ini
```

### Build leakage
```gitignore
# Rust
/target/
**/target/
target_*/
*.rs.bk

# Python
__pycache__/
*.py[cod]
*.egg-info/
build/
dist/
.tox/
.venv/
venv/
.pytest_cache/

# Node
node_modules/
dist/
.next/
build/
.turbo/

# Go
/*.test
/*.out
```

### Secrets (always)
```gitignore
# Private keys (NEVER commit these)
*.key
*.pem
*.p12
*.pfx
*.jks
*.keystore
id_rsa
id_ed25519
id_ecdsa
id_dsa
# .pub files are SAFE to commit; explicitly un-ignore if a wildcard catches them
!*.pub

# .env (not templates)
.env
!.env.example
!.env.template
!.env.sample
!.env.test

# Cloud credentials
*credentials*.json
service-account*.json
gcp-key*.json

# Generic
*_secret*
*-secret-*
secret_*
*.token
*_token.txt
```

---

## The "force-add bypass" failure mode

`.gitignore` is advisory at the filesystem boundary, not at the index. `git add -f <file>` overrides it. If the file is already tracked when the rule is added, the rule has no effect on existing index state.

**The mcp_agent_mail Apr-27 incident:** `signing-*.key` was already in `.gitignore` when the leaked `signing-77c6e768.key` was committed. Someone used `git add -f`. The `.gitignore` rule didn't help.

**Mitigation:** `.githooks/pre-commit` that scans staged paths against secret-smells. The hook cannot be bypassed by `git add -f` (it runs after staging, before commit). See [INCIDENT-PLAYBOOK.md § Step 7](INCIDENT-PLAYBOOK.md#step-7--install-githookspre-commit-to-prevent-recurrence).

---

## Order: deletes BEFORE gitignore (always)

Phase 7 (`git rm`) MUST commit before Phase 8 (`.gitignore`). If you reverse the order:
1. The `.gitignore` add doesn't actually un-track existing files.
2. Subsequent `git status` won't show the (now-ignored, still-tracked) files as anything special.
3. The next `git rm` may fail or behave surprisingly.

The skill enforces this order in PHASES.md — Phase 7 always precedes Phase 8.

For the special case of "untrack but don't delete from disk": pair `git rm --cached <file>` with the `.gitignore` add in the SAME commit. The single commit's diff shows: index entry removed + `.gitignore` line added. Future readers can see both halves of the action together.

---

## Anti-patterns

### ✗ Add `*` patterns at the bottom of an already-organized `.gitignore`
This re-orders implicitly. If a thematic section above already had `*.log` ignored, adding `*` at the bottom doesn't help — the file was already covered. Worse, broad `*` patterns shadow many things at once.

**Fix:** Add to the right thematic section. The skill's gitignore-author preserves existing structure.

### ✗ Use `**/*.json` to ignore JSON outputs
Catches `package.json`, `tsconfig.json`, `composer.json`, etc.

**Fix:** Be specific. `**/coverage*.json`, `**/findings*.jsonl`, `**/.skill-*.json`.

### ✗ Forget the `!` exception when broadening a glob
Adding `*.png` to `.gitignore` shadows your hero image (`hero.png`) and your share image (`og-image.png`).

**Fix:** SHADOWING-AUDIT first. If shadowing is unintended, narrow OR add `!hero.png` / `!og-image.png` exceptions.

### ✗ Ignore directories without trailing slash
`temp` ignores both files and directories named `temp`. If you only meant the directory, write `temp/`.

### ✗ Think `git rm --cached` deletes the file
It only un-tracks. The file stays on disk. Useful for "I want to keep my local copy but stop tracking it." If you also want it gone from disk: `git rm` (without `--cached`).

### ✗ Believe `.gitignore` retroactively removes already-tracked files
It doesn't. See "force-add bypass" above and the mcp_agent_mail incident.

---

## Verifying a rule fires

```bash
git check-ignore -v <path>
```

Output format:
```
.gitignore:284:*.key    test-fake.key
```

This says: line 284 of `.gitignore` (with pattern `*.key`) matched `test-fake.key`. If the output is empty, the rule did NOT fire — investigate before assuming it works.

The skill's gitignore-author always runs this check after the commit.

---

## Repo-archetype `.gitignore` opinions

Some archetypes have opinionated `.gitignore` content. The skill's archetype detection (Phase 1) seeds the protected_globs and also flags expected `.gitignore` patterns:

- **Rust crate:** `/target/`, `**/*.rs.bk`, `Cargo.lock` (committed for binary crates, ignored for libraries — the skill leaves the existing decision alone)
- **Python package:** `__pycache__/`, `*.pyc`, `.venv/`, `dist/`, `build/`, `*.egg-info/`, `.coverage`, `.pytest_cache/`
- **Node.js / Next.js:** `node_modules/`, `.next/`, `dist/`, `.turbo/`, `*.tsbuildinfo`
- **Go:** `/*.test`, `/*.out`, `/<binary-name>` (matching the package name from `go.mod`)
- **Claude skill repo:** `.repo_janitor_workspace/`, `.stash_janitor_workspace/`, `.<skill>_workspace/` for known skill workspace dirs

When the skill's audit finds a missing archetype-standard rule, it's surfaced in the Phase 5 plan — not auto-added unless the user OKs.

---

## Synthesis: a clean `.gitignore` reads top-down

A `.gitignore` is a document, not a config dump. The skill's commit message convention for Phase 8 commits explicitly groups additions thematically and explains *why each section exists*:

```
chore(gitignore): forbid SQLite dev DBs, skill outputs, and per-bead progress at root

After Phase 7 removed 12 files matching these smells, codify the prevention:

- SQLite dev DBs (3 patterns): /storage*.sqlite3*, *-wal, *-shm — these are
  generated when running tests against a real DB and have no business in git.
- Skill outputs (2 patterns): .skill-loop-progress.md, .skill-*-progress.md —
  intermediate state of the simplify and modes-of-reasoning skills.
- Per-bead progress (3 patterns): /progress.md, /progress_bd-*.md, /bd-*.md —
  the canonical home for these is docs/progress/; root-level files are leakage.

Verified via SHADOWING-AUDIT: no currently-tracked files match any of the new
patterns. Verified via `git check-ignore -v <fake-paths>`: every pattern fires
correctly on its target shape.
```

A future reader can audit each line of `.gitignore` back to a triage row's evidence. That auditability is the skill's gift to the project.
