# Git Notes and Signatures — Preserving GPG Signatures, Notes, and Author Identity

`git cherry-pick`, `git merge --squash`, and harmonized-synthesis-via-Edit each handle GPG signatures, git notes, and author identity differently. This file specifies the contract: what gets preserved, what gets re-signed, what's lost, and how the bundle's recovery story handles each.

> **The premise.** A recovered commit isn't byte-equal to its source — the parent SHA differs, the tree may differ if there's a 3-way merge, and the timestamp is the apply time, not the original commit time. Everything that depends on the commit object's hash (signatures, notes attached by hash, signed-tag refs) requires explicit handling.

---

## 1. GPG signatures

Three rules govern signature handling:

1. **`git cherry-pick` doesn't preserve original signatures.** The cherry-picked commit is a NEW commit (different parent → different hash), so the source's signature can't apply.
2. **`git cherry-pick -S` re-signs with the current signer.** If the project requires signed commits, this is mandatory.
3. **The skill never disables signing.** Per AGENTS.md "Mandatory explicit plan" + the broader principle that signature requirements are project policy: the skill respects `commit.gpgsign=true` whether globally or per-repo.

### 1.1 Detecting whether the project requires signed commits

Phase 1 (`scripts/discover-project.sh`) probes:

```bash
# A. Per-repo config:
[ "$(git -C "$PROJECT" config --get commit.gpgsign 2>/dev/null)" = "true" ] && requires_signing=true

# B. GPG signing key set:
[ -n "$(git -C "$PROJECT" config --get user.signingkey 2>/dev/null)" ] && has_signing_key=true

# C. Branch protection requires signed commits (via gh):
if command -v gh >/dev/null && [ -f "$WS/github_state.json" ]; then
    canonical=$(jq -r '.canonical_branch' "$PROJECT/project_profile.json")
    requires_signing_branch=$(gh api "repos/$REPO_OWNER/$REPO_NAME/branches/$canonical/protection" 2>/dev/null \
        | jq -r '.required_signatures.enabled // false')
    [ "$requires_signing_branch" = "true" ] && requires_signing=true
fi

# D. Recent commits on canonical are signed:
recent_signed=$(git -C "$PROJECT" log --format='%G?' "$canonical" -20 2>/dev/null | grep -c -E '^[GU]$')
[ "$recent_signed" -ge 15 ] && observed_signing=true
```

The result is recorded in `project_profile.json`:

```json
{
    "signing": {
        "requires_signing": true,
        "has_signing_key": true,
        "signing_key": "0x1234ABCD",
        "observed_signing_rate_on_canonical": 0.95,
        "branch_protection_requires_signatures": true
    }
}
```

### 1.2 Required environment

Before any Phase 8 apply that requires signing, the skill verifies:

```bash
# GPG_TTY must be set for non-interactive signing in some setups:
[ -z "$GPG_TTY" ] && export GPG_TTY=$(tty)

# user.signingkey must resolve:
git -C "$PROJECT" config --get user.signingkey >/dev/null \
    || halt "user.signingkey not set; required because requires_signing=true"

# The signing key must be available in the agent's GPG keyring:
gpg --list-secret-keys "$(git config --get user.signingkey)" >/dev/null 2>&1 \
    || halt "signing key not present in GPG keyring"

# A test sign must succeed:
echo test | gpg --clearsign --local-user "$(git config --get user.signingkey)" >/dev/null \
    || halt "signing test failed; check passphrase / GPG agent"
```

If signing is required but the prerequisites fail, the skill halts at Phase 1 and surfaces clear diagnostics. It **does not** proceed with unsigned commits — that would silently violate the project's security model.

### 1.3 Per-strategy signature handling

| Phase 8 strategy | Signature behavior | Notes |
|---|---|---|
| `cherry-pick` | `git cherry-pick -S` re-signs with current signer | Original signature is on the source commit (still in bundle's backup ref); the recovered commit has a new signature |
| `squash-merge` | `git commit -S` re-signs the squash commit | Source commits' signatures stay on the bundle's backup ref |
| `rebase-and-merge` | `git rebase -S <upstream>` re-signs each rebased commit | Same — sources retain their signatures in the backup namespace |
| `harmonized-synthesis` | `git commit -S` after the Edit-tool synthesis | Synthesis is new content; new signature is appropriate |
| `split-apply` (8b) | `git cherry-pick -S` for each picked commit | Same as cherry-pick |
| `dirty-worktree-only` | `git commit -S` after applying captured diffs | New signature on the new commit |

The signing flag is set in `apply-keeper.sh`:

```bash
# In scripts/apply-keeper.sh:
if [ "$(jq -r '.signing.requires_signing' "$WS/project_profile.json")" = "true" ]; then
    SIGN_FLAG="-S"
else
    SIGN_FLAG=""
fi

case "$STRATEGY" in
    cherry-pick)
        git cherry-pick $SIGN_FLAG --no-commit "$SOURCE_SHA"
        # ... gates run ...
        git commit $SIGN_FLAG -m "$COMMIT_MSG"
        ;;
    squash-merge)
        git merge --squash "$SOURCE_BRANCH"
        # ... gates run ...
        git commit $SIGN_FLAG -m "$COMMIT_MSG"
        ;;
    # ...
esac
```

### 1.4 What the source commit's signature meant — and what's lost

A signed commit on the source branch attests: "the author at the time of original authorship vouched for this content." After cherry-pick:

- The recovered commit attests: "the rationalization-branch author at apply time vouches for this content."
- The original attestation is preserved on the **bundle's backup ref** — `refs/branch-rationalization-backup/<slug>` still points at the original signed commit.
- The bundle's `format-patch/*.patch` series contains the signature info as part of the patch metadata (`From: ... PGP-SIGNATURE: ...`).

What's lost: the chain-of-custody for who originally signed. If a security-sensitive project relies on signed commits as proof of authorship, the rationalization-branch commit message must explicitly cite the source author + signature:

```
Subject: recover defensive OK-packet length-cap from wip-BACK-1742

Originally drafted on branch wip-BACK-1742 (sha 8a3d2c9, signed by 0xABCD1234 — Alice <alice@example.com>).
The defensive guard caps OK-packet payload length to MAX_PAYLOAD ...

[body per COMMIT-MESSAGE-CRAFT.md]

Original-Signed-By: 0xABCD1234 (Alice <alice@example.com>)
Original-Commit: 8a3d2c9 (in bundle § branches/wip-BACK-1742-8a3d2c9bf01a/)
Recovered-And-Re-Signed-By: 0x1234ABCD (the rationalization-branch author)

Beads-Issue: beads-1234
```

The `Original-Signed-By:` and `Recovered-And-Re-Signed-By:` trailers are added by `commit-message-author.md` (Phase 8 subagent) when `requires_signing=true`. Cross-link to [COMMIT-MESSAGE-CRAFT.md](COMMIT-MESSAGE-CRAFT.md) for the trailer schema.

> **Why explicit trailers?** Per AGENTS.md "Document the confirmation": every action with security implications is recorded. The trailers make the chain-of-custody auditable: future readers of the rationalization-branch commit can resolve back to the original signed commit in the bundle's backup ref.

---

## 2. Git notes

`git notes` are out-of-band metadata attached to a commit by SHA. When the commit's SHA changes (cherry-pick, squash, rebase), notes don't follow automatically.

### 2.1 The contract

The skill **preserves notes** during cherry-pick by explicitly copying them:

```bash
# In scripts/apply-keeper.sh, after a successful cherry-pick:
NEW_SHA=$(git rev-parse HEAD)
SOURCE_SHA="$1"

# If the source commit has notes, copy them to the new commit:
if git notes show "$SOURCE_SHA" >/dev/null 2>&1; then
    git notes copy "$SOURCE_SHA" "$NEW_SHA"
    echo "notes_copied" >> "$WS/apply_log_extras.tsv"
fi
```

Apply log records this:

```
apply_log.tsv columns: ... new_commit_sha, source_sha, notes_copied (yes/no), ...
```

### 2.2 What about non-default note refs?

Some workflows use multiple note refs (e.g., `refs/notes/code-review`, `refs/notes/build-results`). The skill discovers and preserves them all:

```bash
for note_ref in $(git for-each-ref refs/notes --format='%(refname:short)'); do
    note_name=${note_ref#notes/}
    if git notes --ref="$note_name" show "$SOURCE_SHA" >/dev/null 2>&1; then
        git notes --ref="$note_name" copy "$SOURCE_SHA" "$NEW_SHA"
        echo "notes_copied_ref=$note_name" >> "$WS/apply_log_extras.tsv"
    fi
done
```

### 2.3 Notes for squash-merge and harmonized-synthesis

For squash-merge: there are multiple source commits, each potentially with notes. The skill **concatenates** the notes:

```bash
# For each source commit being squashed:
combined_notes=""
for src in $SOURCE_SHAS; do
    if git notes show "$src" >/dev/null 2>&1; then
        combined_notes+="\n--- from $src ---\n$(git notes show "$src")"
    fi
done

if [ -n "$combined_notes" ]; then
    echo -e "$combined_notes" | git notes add -F - "$NEW_SHA"
fi
```

For harmonized-synthesis: the synthesis combines hunks from multiple sources. The skill writes a NEW note that **references** the source notes rather than concatenating (to avoid duplication):

```
This synthesis recovers content from:
  - agent-cleanup-pass-3 @ 4f0e2a1 (see notes via: git notes show 4f0e2a1)
  - feature/length-cap @ b91d77c (see notes via: git notes show b91d77c)
  - feature/redact-secrets @ 5e22a8b (see notes via: git notes show 5e22a8b)

For metadata details, consult the source commits in refs/branch-rationalization-backup/<slug>.
```

### 2.4 Notes that don't survive

If a note's content is **bound to the old SHA** (e.g., a code-review note that says "I reviewed commit 8a3d2c9 — looks good"), the note is now misleading on the new commit. The skill **doesn't** rewrite note content; it copies as-is. The user reviews and edits if desired.

---

## 3. Author identity

### 3.1 Cherry-pick preserves author by default

```bash
# Before cherry-pick:
git log -1 --format='%an <%ae> | %cn <%ce>' "$SOURCE_SHA"
# Output: Alice <alice@example.com> | Alice <alice@example.com>

# After cherry-pick on rationalization branch:
git cherry-pick "$SOURCE_SHA"
git log -1 --format='%an <%ae> | %cn <%ce>'
# Output: Alice <alice@example.com> | Bob <bob@example.com>
#                                      ↑ committer changed (the rationalization-branch operator)
```

The **author** is preserved (Alice still gets credit for the work). The **committer** changes (the rationalization-branch operator is the one who applied it). Both are recorded in the commit object.

### 3.2 Squash-merge does NOT preserve author

```bash
# Source branch has 5 commits by Alice:
git log --format='%an' "$SOURCE_BRANCH" | sort -u
# Output: Alice <alice@example.com>

# After squash-merge:
git merge --squash "$SOURCE_BRANCH"
git commit -m "..."
git log -1 --format='%an'
# Output: Bob <bob@example.com>  ← the squasher
```

The squashed commit's author is the **squasher** (Bob, the rationalization-branch operator). The original authors are lost from the commit object.

To preserve attribution, the skill records source authors in the **commit message body** (not as `Co-Authored-By` trailers, which require user opt-in per AGENTS.md):

```
Subject: harmonize logger hardening from agent-cleanup-pass-3 + feature/length-cap

[body per COMMIT-MESSAGE-CRAFT.md]

Source authors:
  - Alice <alice@example.com> (agent-cleanup-pass-3)
  - Carol <carol@example.com> (feature/length-cap)
  - David <david@example.com> (feature/redact-secrets)

Beads-Issue: beads-1234
```

This is a **citation**, not a `Co-Authored-By` trailer. The distinction:

| Format | When used | Effect on git tooling |
|---|---|---|
| Body citation (`Source authors: ...`) | Default for squash-merge and harmonized-synthesis | Visible in `git log`, no special tooling treatment |
| `Co-Authored-By: Name <email>` trailer | Only when user explicitly asks | GitHub displays the co-author in PR; counted in contribution graphs; may have legal implications under DCO |

Per AGENTS.md (and SKILL.md "Anti-Patterns"): "messages that bypass `Co-Authored-By` discipline (don't add it unless user asked)." The skill defaults to body citations, never trailers.

### 3.3 Harmonized-synthesis author

For harmonized synthesis, the synthesis is **new code** — a composition that didn't exist on any source branch. The author is the rationalization-branch operator (the one running the skill). Source authors are cited in the body per § 3.2.

This is the philosophically correct attribution: the synthesis IS the operator's work. They're standing on the source authors' shoulders, but the integration is theirs.

### 3.4 Rebase-and-merge

`git rebase` preserves both author and committer in the standard case. In Phase 8 rebase-and-merge:

```bash
# Switch to a temp branch from the source:
git switch -c /tmp/rebase-source "$SOURCE_BRANCH"

# Rebase onto the rationalization branch:
git rebase branch-rationalization-$DATE

# Merge:
git switch branch-rationalization-$DATE
git merge --no-ff /tmp/rebase-source

# Cleanup:
git branch -D /tmp/rebase-source
```

Each rebased commit retains its original author. The merge commit (`--no-ff`) is authored by the operator. This is the **most attribution-preserving** strategy and is preferred for long branches with diverse authorship.

---

## 4. Trailers

### 4.1 What trailers does the skill add by default?

| Trailer | Default behavior | Why |
|---|---|---|
| `Beads-Issue: <run-id>` | Always added | Per AGENTS.md "Mapping Cheat Sheet": "Commit messages: Include `beads-###` for traceability" |
| `Original-Signed-By:` | Only when source commit was signed AND project requires signing | Chain-of-custody (§ 1.4) |
| `Recovered-And-Re-Signed-By:` | Only when project requires signing | Chain-of-custody (§ 1.4) |
| `Source-Branch:` | Always added | Cross-reference to bundle for recovery |
| `Source-SHAs:` | For multi-source recoveries (squash + harmonized + split-apply) | Cross-reference per source |
| `Co-Authored-By:` | NEVER unless user explicitly asks | Per AGENTS.md |
| `Signed-off-by:` | Only if project's pre-commit hook adds it (DCO projects) | The skill defers to project policy |
| `Reviewed-by:`, `Tested-by:`, etc. | NEVER | These are real attestations the skill can't truthfully make |

### 4.2 The user's authorization to add `Co-Authored-By`

If the user explicitly asks ("please add Co-Authored-By trailers for harmonized syntheses"), the skill does so:

```bash
if [ -n "$USER_AUTHORIZED_COAUTHORS" ]; then
    coauthor_block=""
    for src_author in $SOURCE_AUTHORS; do
        coauthor_block+="Co-Authored-By: $src_author"$'\n'
    done
    COMMIT_MSG="$COMMIT_MSG"$'\n\n'"$coauthor_block"
fi
```

The user's authorization is recorded in the workspace (similar to the cleanup_authorization pattern):

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) USER AUTHORIZED: add Co-Authored-By trailers per user request" >> "$WS/coauthor_authorization.txt"
```

---

## 5. Branch protection rules requiring signed commits

Phase 0.5 (`scripts/github-pr-awareness.sh`) detects this:

```bash
gh api "repos/$REPO_OWNER/$REPO_NAME/branches/$CANONICAL/protection" 2>/dev/null | jq -r '
{
    required_signatures: .required_signatures.enabled,
    required_status_checks: .required_status_checks.contexts,
    required_pull_request_reviews: .required_pull_request_reviews,
    enforce_admins: .enforce_admins.enabled
}' > "$WS/branch_protection_$CANONICAL.json"
```

If `required_signatures` is true, `project_profile.json:signing.branch_protection_requires_signatures` is set to true, which forces `requires_signing=true` regardless of local config. This protects against the case where:
- The user's local config doesn't have `commit.gpgsign=true`
- But the canonical branch's protection rule requires signed commits
- The skill produces unsigned commits
- The user pushes; the push is rejected by the remote
- The user is confused

By detecting upstream's policy, the skill produces signed commits proactively.

---

## 6. Merge commits and multiple parents

Some recovery scenarios involve merge commits (commits with >1 parent). Notes and signatures are first-parent-biased.

### 6.1 Cherry-picking a merge commit

```bash
# Naive cherry-pick fails:
git cherry-pick <merge-sha>
# Error: commit <merge-sha> is a merge but no -m option was given.
```

The skill uses `-m 1` to pick the first-parent diff:

```bash
git cherry-pick -m 1 -S <merge-sha>
```

This loses the second-parent's distinct content. The skill records this in `apply_log.tsv:notes` and surfaces in the commit message:

```
Subject: recover content from merge commit <sha>

Note: source was a merge commit; cherry-picked with -m 1 (first parent).
The second parent's distinct contribution is in branch <other-branch> (preserved in bundle § branches/<other-branch>/).
If the second parent's content is needed, it requires separate recovery.
```

### 6.2 Notes on merge commits

`git notes copy <merge-sha> <new-cherry-pick-sha>` copies the note as-is. The note's content (which may reference both parents) is now misleading because the cherry-pick only captured one parent's content. The skill **doesn't auto-edit** notes; the user reviews.

### 6.3 Signatures on merge commits

A signed merge commit attests to the merge as a whole (both parents). After cherry-pick with `-m 1`, the signature is meaningless (only one parent's content is present). The skill records this in `Original-Signed-By:` with a caveat:

```
Original-Signed-By: 0xABCD1234 (Alice <alice@example.com>) — note: original was a merge commit;
                    cherry-picked with -m 1; signature attestation is for the full merge, not this subset.
```

---

## 7. Edge cases

### 7.1 The signing key is unavailable mid-run

If the GPG agent times out mid-Phase-8, signing fails. The skill halts:

```bash
git cherry-pick -S "$SOURCE_SHA"
# Error: gpg: signing failed: ...
```

The apply-keeper script halts the run, leaves the rationalization branch tip at the last successful commit, and surfaces:

```
ERROR: GPG signing failed during apply of <source-sha>.
The rationalization branch is at <last-successful-commit-sha>.
To resume:
  1. Verify GPG agent: gpg --list-secret-keys
  2. Re-test signing: echo test | gpg --clearsign
  3. Re-run the skill with --resume; it will pick up at apply N+1
```

The skill **never disables signing** to "make it work."

### 7.2 The signing key changes mid-run

If the user rotates their signing key mid-run, the rationalization branch will have commits signed by the old key (early Phase 8) and the new key (late Phase 8). This is fine — both keys are valid signatures from the user.

### 7.3 Mixed-signing requirements

A project may have `commit.gpgsign=true` per-repo but `requires_signatures=false` on the canonical branch. The skill follows the **stricter** of the two: if either says signing is required, sign.

### 7.4 SSH signatures

Newer git versions support SSH-key signatures (`gpg.format=ssh`). The skill detects:

```bash
sign_format=$(git config --get gpg.format 2>/dev/null)  # gpg | ssh | x509
```

For `ssh`: the same `-S` flag works; the underlying transport is SSH instead of GPG. The skill records `signing.format` in `project_profile.json`.

---

## 8. Verification at Phase 11

The Phase 11 handoff includes a signing summary:

```markdown
## Signing Summary

Project requires signed commits: yes (per branch protection rule on main + repo config commit.gpgsign=true)
Signing format: ssh (gpg.format=ssh)
Signing key: ssh-ed25519 AAAA... (the rationalization-branch operator)

Per-commit signature status (from `git log --format='%G?'`):

| Commit | Strategy | Source SHA | Sig status | Notes |
|---|---|---|---|---|
| aa11bb22 | cherry-pick | 8a3d2c9 | G (good) | Original by Alice <alice@example.com>; re-signed by operator |
| bb22cc33 | harmonized | (3 sources) | G (good) | New synthesis; signed by operator; source authors cited in body |
| cc33dd44 | squash-merge | (5 source commits) | G (good) | Source authors cited in body |

All recovered commits are signed. The rationalization branch is ready to push to a signing-required canonical.
```

The verification runs as part of `polish-bar-check.sh`. If any commit shows `N` (no signature) or `B` (bad signature) when signing is required, the polish bar fails and Phase 10 is blocked.

---

## 9. Cross-links

- [PHASES.md § Phase 1 PROJECT RECONNAISSANCE](PHASES.md) — signing detection
- [PHASES.md § Phase 8 RATIONALIZATION + APPLY](PHASES.md) — signing application
- [PHASES.md § Phase 11 HANDOFF](PHASES.md) — signing verification
- [COMMIT-MESSAGE-CRAFT.md § Trailers](COMMIT-MESSAGE-CRAFT.md) — the trailer schema this file extends
- [POLISH-BAR.md § Verbatim authorization](POLISH-BAR.md) — signing as part of the polish-bar
- [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) — the bundle's backup ref retains the original signed commit
- [INTEGRATION.md § GitHub PR awareness](INTEGRATION.md) — Phase 0.5 captures branch-protection rules that drive signing requirements
- [CI-WORKFLOW-AWARENESS.md](CI-WORKFLOW-AWARENESS.md) — branch protection detection (overlapping concern)
- [AUDIT-AFTER-RUN.md § Commit message quality](AUDIT-AFTER-RUN.md) — verifies trailers are well-formed
- [DRY-RUN-MODE.md](DRY-RUN-MODE.md) — predicts signing behavior (won't actually sign in dry-run)
- [AGENTS.md "Mapping Cheat Sheet"](../../../../AGENTS.md) — `Beads-Issue: <id>` trailer
- [AGENTS.md "Anti-Patterns"](../../../../AGENTS.md) — never add `Co-Authored-By` unless asked
- [AGENTS.md "Mandatory explicit plan"](../../../../AGENTS.md) — verbatim authorization required for `Co-Authored-By` opt-in
- [Pro Git §7 Signing Your Work](https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work) — upstream reference
