# Incident Playbook

What to do when things go sideways mid-run. Each incident has a recovery flow with explicit commands. The skill never auto-runs filter-repo or force-push — it surfaces the plan and waits for the user.

---

## Secret Leak Recovery

**Trigger:** Phase 2.5 finds a real secret (filename match + content fingerprint match). The most common case is a private signing key force-added with `git add -f` despite a pre-existing `.gitignore` rule.

**Apr-27 mcp_agent_mail incident:** A real Ed25519 signing private key (`signing-77c6e768.key`) was committed in feature commit `6de5816` ("feat: Enhance file reservations, search fallback, and robustness") despite `.gitignore` already containing `signing-*.key`. Someone used `git add -f` to bypass it. The key had been on origin for ~30 days. The `.pub` was safe to keep; only the `.key` needed to disappear from history.

### Step 0 — Halt and confirm

When Phase 2.5 surfaces a secret, the skill HALTS the routine cleanup and presents:

```
🚨 REAL <secret-type> COMMITTED TO <visibility> REPO: <path>

- File: <description from content fingerprint>
- First commit: <sha> "<commit-message>"
- Pushed to origin: <yes/no>
- Exposure window: <N days>
- Used by: <code path that loads it, if any>

I will NOT delete or rewrite anything until you confirm:

  1. Generate a NEW <secret-type> NOW (not 'later') — this is the ONLY
     way to mitigate the existing exposure. Anyone who cloned the repo
     since the introducing commit has the secret.

  2. Confirm: is the <pub/companion> file safe to keep in the repo?
     (Public keys are safe; service-account JSON IS NOT — the entire
     file is the secret.)

  3. Are there other private keys / secrets I haven't surfaced that
     I should also rotate at the same time?

Once those are settled, paste this verbatim to authorize the rewrite:

  yes I have rotated the secret and want to filter it out of git history
  and force-push to origin's <branch> (and <synonym-branches>)
```

**The skill never runs filter-repo until that exact authorization arrives.**

### Step 1 — Mirror backup

Before any history rewrite, the skill takes a full mirror backup that includes every ref (branches, tags, notes, stash, reflog). This is the ultimate undo:

```bash
BACKUP_TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_PATH=/tmp/<repo>-backup-$BACKUP_TS.git
git clone --mirror . "$BACKUP_PATH"
du -sh "$BACKUP_PATH"
echo "BACKUP_PATH=$BACKUP_PATH"
```

If anything goes wrong: `git clone "$BACKUP_PATH" /tmp/<repo>-restore` and inspect.

### Step 2 — Verify origin is fully synced (Axiom 16 guard)

This is the most easily-skipped step and the one that most often causes a partial rewrite. The Apr-27 incident hit this exact bug: the local clone had 199 commits but origin had 793 — running `filter-repo` against the local 199-commit slice rewrote only that slice, leaving the secret in the upstream 594 commits.

```bash
# Capture pre-state
git for-each-ref --format='%(refname) %(objectname)' refs/heads/ refs/tags/ \
  > /tmp/<repo>-refs-before-filter.txt
wc -l /tmp/<repo>-refs-before-filter.txt

# Compare local vs origin
git fetch origin --tags
local_count=$(git rev-list --count <branch>)
origin_count=$(git rev-list --count origin/<branch>)
echo "local: $local_count commits"
echo "origin: $origin_count commits"
[[ "$local_count" -eq "$origin_count" ]] || {
  echo "MISMATCH — syncing local to origin first"
  git update-ref refs/heads/<branch> refs/remotes/origin/<branch>
  git update-ref refs/heads/<synonym> refs/remotes/origin/<synonym>  # if applicable
  git checkout <branch>
  # Re-verify
  [[ "$(git rev-list --count <branch>)" -eq "$origin_count" ]] || {
    echo "STILL MISMATCH — investigate manually before continuing"
    exit 1
  }
}
```

The skill ALSO confirms the secret-introducing commit is reachable from `<branch>` after the sync. If it's not (e.g., on a feature branch that origin doesn't have), the user is asked which branches need rewriting.

### Step 3 — Run `git filter-repo`

```bash
# git-filter-repo removes the file from EVERY commit that ever touched it
# `--invert-paths --path X` means "drop this path from history"
echo "Y" | git-filter-repo \
  --invert-paths \
  --path 'signing-77c6e768.key' \
  --force
```

This removes the `origin` remote (filter-repo's safety design); we'll re-add it.

```bash
# Verify the secret is gone from ALL of history
git log --all --oneline -- 'signing-77c6e768.key'  # should be empty
git ls-tree HEAD | grep signing                    # should NOT contain .key
git rev-list --count <branch>                       # should match pre-filter count
```

If the count went DOWN: `git filter-repo` collapsed empty commits. That's normal but check what was lost.

### Step 4 — Re-add origin and verify divergence

```bash
git remote add origin <origin-url>
git fetch origin
git rev-list --count <branch>..origin/<branch>   # commits in origin not in local (after rewrite)
git rev-list --count origin/<branch>..<branch>   # commits in local not in origin (after rewrite)
```

These should be equal — every commit was rewritten 1:1, just without the secret in any of them.

### Step 5 — Force-with-lease push to ALL synonym branches

```bash
git push --force-with-lease origin <branch>
# If repo pushes main → master synonym (frankensqlite/CASS pattern):
git push --force-with-lease origin <branch>:<synonym>
```

`--force-with-lease` is safer than `--force`: it refuses if origin advanced since the last fetch.

```bash
# Verify origin is clean
git fetch origin
git log origin/<branch> --all --oneline -- 'signing-77c6e768.key' | head -3
# Empty = secret gone from origin too
```

### Step 6 — Broaden `.gitignore`

The `.gitignore` already had `signing-*.key` in the Apr-27 incident. Add belt-and-suspenders patterns:

```gitignore
# Private keys (never commit these)
*.key
!*.pub.key      # if any literal `.pub.key` files are intentionally tracked
*.pem
*.p12
*.pfx
*.jks
*.keystore
id_rsa
id_rsa.pub      # only the private should be ignored; .pub is safe
id_ed25519
id_ed25519.pub
id_ecdsa
id_dsa

# Cloud credentials
*credentials*.json
service-account*.json
gcp-key*.json
.aws/credentials

# Generic secret-named
*_secret*
*-secret-*
secret_*
*.token
*_token.txt

# .env (not templates)
.env
!.env.example
!.env.template
!.env.sample
!.env.test
```

Run SHADOWING-AUDIT before committing — make sure no currently-tracked file matches the new patterns.

### Step 7 — Install `.githooks/pre-commit` to prevent recurrence

The `git add -f` bypass means `.gitignore` alone is insufficient. The hook scans staged paths.

`.githooks/pre-commit`:

```bash
#!/usr/bin/env bash
# Block commits that contain likely secret files.
set -euo pipefail

FAIL=0
for path in $(git diff --cached --name-only --diff-filter=AM); do
  case "$path" in
    *.key | *.pem | *.p12 | *.pfx | *.jks | *.keystore | \
    id_rsa | id_ed25519 | id_ecdsa | id_dsa | \
    .env | *credentials*.json | service-account*.json | \
    *_secret* | *-secret-* | secret_* | *.token)
      # Allow templates and public keys
      case "$path" in
        *.example | *.template | *.sample | *.dist | *.placeholder | \
        *.pub | id_rsa.pub | id_ed25519.pub | .env.example | .env.template)
          continue
          ;;
      esac
      printf '\033[31m✗ Pre-commit blocked: likely secret file(s) staged.\033[0m\n'
      printf '\033[31m    - %s  (matches private-key filename pattern)\033[0m\n' "$path"
      FAIL=1
      ;;
  esac
done

if [[ $FAIL -eq 1 ]]; then
  printf '\033[33mIf a finding is a false positive, run:\033[0m\n'
  printf '\033[33m    git commit --no-verify\033[0m\n'
  printf '\033[33mBut review the file first — the last leak was a real Ed25519 key.\033[0m\n'
  exit 1
fi
```

```bash
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

### Step 8 — Smoke-test the hook

```bash
echo "fake-content" > test-fake.key
git add -f test-fake.key
git commit -m "test commit"   # should be BLOCKED with the red message
git restore --staged test-fake.key
rm test-fake.key
```

If the hook doesn't block: investigate before continuing.

### Step 9 — Document in AGENTS.md

Add a section noting the new pre-commit guard and how to bypass it for false positives. Reference the incident date and the introducing commit so future readers know why the layers are there.

### Step 10 — Final commit + push

```bash
git add .gitignore .githooks/ AGENTS.md
git commit -m "$(cat <<'EOF'
security: prevent private-key commits — broader .gitignore + .githooks/pre-commit + AGENTS.md

A real <secret-type> (<path>) was committed in <sha> despite .gitignore already
containing <pre-existing-rule>. The leak was force-added with `git add -f`,
bypassing .gitignore. To prevent recurrence:

- Broaden .gitignore: add <new-patterns>
- Install .githooks/pre-commit that scans staged paths against secret-smells
  (cannot be bypassed by `git add -f`)
- Document the hook in AGENTS.md so contributors know how to install it

After this commit:
- New users clone normally
- core.hooksPath needs to be set per-clone:
    git config core.hooksPath .githooks
EOF
)"
git push origin <branch>
git push origin <branch>:<synonym>   # if applicable
```

### Step 11 — Tell the user what they need to do

Even after history rewrite, the secret is still on:
- Anyone who cloned the repo before the rewrite
- GitHub's archive (the GraphQL API can retrieve dangling commits for some time)
- CI logs that ran during the exposure window

The skill emits explicit guidance:

> ⚠️ **Even after this rewrite, treat the secret as compromised.** Forks
> and old clones still have it. The mitigation is the new key (which you
> rotated in Step 0); this rewrite only stops further inadvertent
> distribution.

---

## Working-tree mid-run conflict

**Trigger:** Phase 6 / 7 / 8 sees changes in the working tree from concurrent agents (per AGENTS.md "Note for Codex/GPT-5.5"). Per Axiom 8: never disturb concurrent agents' work.

**Recovery flow:**

1. Re-snapshot `git status` and `git diff` to `wt_phase<N>.txt`.
2. Treat the changes as if you made them.
3. Continue with the mutation. If `git mv <src> <dst>` fails because `<src>` was already moved by an agent: confirm the move actually happened (`git ls-files | grep <src>` empty, `git ls-files | grep <dst>` non-empty), then mark the candidate `applied-by-other-agent` and skip.
4. If `git rm <path>` fails because the path was already deleted: same — mark `applied-by-other-agent` and skip.
5. Never `git stash` the agent's changes. Never `git restore`. Never `git checkout --`.

---

## A `git mv` collision

**Trigger:** `git mv <src> <dest>` fails because `<dest>` already exists.

**Causes:**
- Phase 6 is being re-run after partial completion.
- The destination dir already has a same-named file from a different category.
- A concurrent agent already moved a different file to the same destination.

**Recovery flow:**

1. Compare `<src>` and `<dest>` content via `diff` or `sha256sum`.
2. If identical: the move already happened; skip with `applied-by-other-agent` mark.
3. If different content:
   - If the user wants the new file to win: rename the existing dest first (`git mv <dest> <dest>.old.YYYYMMDD`).
   - If the user wants the existing dest to win: skip the move; mark the candidate `keep-in-place-due-to-collision`.
   - **Default: surface to user.** Don't auto-resolve.

---

## A reference rewrite breaks the build

**Trigger:** After Phase 6 reference rewrites, `cargo check` (or equivalent) fails.

**Recovery flow:**

1. Capture the build error.
2. Use `git status -s` and `git diff` to inspect what was rewritten.
3. Common causes:
   - Path constant became too long for a `&str` literal that was implicitly relying on file-relative semantics.
   - The new path doesn't exist yet because a directory wasn't created.
   - The reference was inside a `format!`/`println!` and the rewrite broke the format string's escape sequences.
4. **Roll back via `git restore <files>`** for files modified by the skill in this Phase 6 batch (do NOT roll back files modified by other agents).
5. Re-do the rewrite via the Edit tool (one occurrence at a time) with manual verification.
6. Re-run gates.

If after 2 retries the build still fails: surface to user with full context. Do not silently revert the move.

---

## A `.gitignore` change shadows tracked files

**Trigger:** Phase 8 SHADOWING-AUDIT finds tracked files matching a proposed glob.

**Recovery flow:**

1. List every tracked file the new pattern would shadow:
   ```bash
   git ls-files <pattern>
   ```
2. Decide per file:
   - Truly should be ignored AND removed: `git rm --cached <file>` first, then add to `.gitignore`. The file stays on disk but becomes untracked.
   - Truly should be ignored AND deleted: include in Phase 7 delete plan.
   - Should NOT be ignored: narrow the glob (e.g., `temp_*` → `temp_scratch.txt` if there's only one specific file to ignore) OR add a negation rule (`!important_temp.txt`).
3. Re-run SHADOWING-AUDIT until clean.
4. The Phase 8 commit pairs the `git rm --cached` runs with the `.gitignore` adds in a single commit so the diff tells one story.

---

## A `git filter-repo` was run but origin still has the secret

**Trigger:** After Step 5 force-push, `git log origin/<branch> -- <secret-path>` still shows the path.

**Causes:**
- Tag refs that weren't rewritten (filter-repo by default does rewrite tags; check if `--tag-name-filter` was set).
- Synonym branch (e.g., `master`) wasn't force-pushed.
- A different branch on origin still has the path; e.g., a feature branch the user forgot about.

**Recovery flow:**

1. List ALL refs on origin: `git ls-remote origin | head -30`.
2. For each ref that still has the secret: force-with-lease push the rewritten history to it.
3. If a tag references a commit that originally had the secret, the tag's name is preserved but its SHA is now different — that's correct. Just push the rewritten tags: `git push --force --tags origin`.
4. Re-verify with `git log origin/<branch> -- <secret-path>` — must be empty.

---

## A bundle's working-tree-copy doesn't match the live blob

**Trigger:** Phase 3 verify-bundle.sh hits a SHA-256 mismatch.

**Causes:**
- File changed between the `git ls-files` snapshot (Phase 2) and the `cp` (Phase 3) — concurrent agent.
- LFS pointer wasn't smudged before copying.
- File has trailing-newline auto-fixup from a `core.autocrlf` setting.

**Recovery flow:**

1. Re-snapshot the live working tree.
2. If the live SHA != Phase-2 SHA: re-run Phase 2 to refresh `candidates.tsv`, then re-run Phase 3.
3. If LFS: re-do the `git lfs smudge` step.
4. If autocrlf: configure `core.autocrlf=false` for the bundle session.
5. If after 2 retries the SHAs still don't match: HALT the run. The repo is unsafe to operate on without understanding the source of drift.

---

## A user wants to undo a Phase 6 move after the run completed

**Trigger:** User says "actually I wanted to keep `X.md` at root" after the cleanup branch is committed.

**Recovery flow:**

```bash
# Find the commit that moved it
git log --oneline --diff-filter=R -- '<dest>/X.md' | head -3

# Option 1 — revert the entire commit
git revert <sha>

# Option 2 — surgically undo just this move
git mv '<dest>/X.md' 'X.md'
# Update any references that were rewritten
# (the reference_rewrite_log.tsv shows what to undo)
git commit -m "revert: keep X.md at repo root per user request"
```

The bundle's `working-tree-copies/X.md` is byte-identical to what was moved. The reference graph in `reference-graph.json` shows what references were rewritten and where the old/new paths were.

---

## A user wants to undo a Phase 7 delete after the run completed

**Trigger:** User says "actually I needed `<file>` for X" after delete.

**Recovery flow:**

```bash
# Option 1 — backup ref (preferred)
git checkout refs/repo-janitor-backup/<DATE>-pre-cleanup -- '<path>'
git commit -m "restore: <path> per user request"

# Option 2 — bundle copy
cp <bundle>/working-tree-copies/<path> <project>/<path>
git add '<path>'
git commit -m "restore: <path> per user request"

# Option 3 — git revert the delete commit
git log --oneline --diff-filter=D -- '<path>' | head -3
git revert <sha-of-delete-commit>
```

If the user wants to keep the file but also keep it `.gitignore`d (e.g., to not track it but not delete the local copy):

```bash
git restore --staged <path>   # if just staged
# OR
git checkout HEAD -- <path>   # restore from HEAD
echo '<file-or-pattern>' >> .gitignore
git rm --cached <path>        # untrack but keep on disk
git add .gitignore
git commit -m "untrack <path> while keeping local copy"
```

---

## A pre-commit hook keeps blocking commits incorrectly

**Trigger:** The `.githooks/pre-commit` from Step 7 of secret-leak recovery is too aggressive — it blocks commits to legitimate `.example` or `.test` files.

**Recovery flow:**

1. Identify the false-positive pattern.
2. Edit `.githooks/pre-commit` to add a more specific allowlist exception.
3. Smoke-test:
   ```bash
   echo content > new-allowlisted.example.key
   git add new-allowlisted.example.key
   git commit -m "test"  # should pass
   ```
4. Commit the hook update.

If the user wants to commit a one-off legitimate file that matches a secret pattern (e.g., a curated test fixture): `git commit --no-verify` is the documented escape hatch. The skill's hook output explicitly tells the user about `--no-verify` so they know.
