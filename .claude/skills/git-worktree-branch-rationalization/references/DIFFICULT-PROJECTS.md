# Difficult Projects — Weird Repo Shapes Beyond REPO-ARCHETYPES.md

[REPO-ARCHETYPES.md](REPO-ARCHETYPES.md) covers the 20 common archetypes the skill auto-detects (GitFlow, monorepo, submodules, LFS, signed commits, etc.). This file fills the gap: rare-but-real repo shapes that need extra handling, mostly because they break assumptions in the bundle, the apply, or the inventory. Each section describes the shape, why it breaks defaults, the detection signal, the adjustment, and the cross-link.

> **Why a separate file?** REPO-ARCHETYPES has the *taxonomy* — the categorization the skill uses for routine path-selection. This file has the *footguns* — the rough edges where the skill's defaults are wrong and need explicit adjustment. The split mirrors how OPERATOR-LIBRARY (cognitive moves) is separate from FAILURE-MODES (when those moves break).

These are presented in roughly increasing rarity / increasing user-visible-pain order.

---

## DP-1 — Sparse checkouts

**Shape.** `git config core.sparseCheckout` is `true`; `.git/info/sparse-checkout` (or `.git/info/sparse-checkout-cone`) lists patterns that determine which paths are materialized in the working tree. Files outside the cone are *tracked* (in the index, in commits, in branches' diffs) but not present on disk.

**Why it breaks defaults.**

- The bundle's per-branch unified diff captures the *full* content (the index always has everything; `git diff <merge-base>..<branch>` reads from the index/objects). So branch-side recovery is fine.
- BUT the per-worktree dirty-state captures (Phase 3's `staged.diff`, `unstaged.diff`, untracked tarball) only include files inside the sparse cone. A worktree with a sparse cone of `src/api/**` will have nothing captured for `src/web/**` — even if there are untracked files in `src/web/` that the user "knows about" via a pre-existing checkout that was later sparse-narrowed.
- Apply at Phase 8: applying a diff that touches a path outside the sparse cone fails because the file isn't materialized. Surface to user: "expand sparse-checkout to include `<path>`?"

**Detection.**

```bash
# project_profile.json:archetypes adds 'sparse' (already in REPO-ARCHETYPES A17)
# Augmentation: per-worktree sparse cone capture
for wt in $(git worktree list --porcelain | awk '/^worktree / {print $2}'); do
  cone=$(git -C "$wt" config core.sparseCheckout && cat "$wt/.git/info/sparse-checkout" 2>/dev/null \
         || cat "$(git -C "$wt" rev-parse --git-dir)/info/sparse-checkout" 2>/dev/null)
  echo -e "$wt\t$cone" >> "$WS/sparse_cones.tsv"
done
```

**Adjustment.**

- Phase 3 README explicitly notes: "worktree dirty captures are limited to the sparse cone in effect at the moment of capture."
- Phase 8 apply: if the diff touches a path outside the cone, surface the missing-file message verbatim AND propose `git sparse-checkout add <path>` as the operator next step. Never run it without confirmation.
- Phase 10 worktree removal: cone-aware — the captured archive is the cone-restricted snapshot; restoration requires re-applying the sparse cone *first* before applying the captured dirty state.

**Why this matters.** Many large monorepos use sparse checkouts to reduce disk usage. A rationalization run that silently misses untracked content outside the cone is a recovery footgun.

**Cross-link.** [REPO-ARCHETYPES.md A17](REPO-ARCHETYPES.md#a17--repo-with-sparse-checkout); [WORKTREE-STATE.md](WORKTREE-STATE.md).

---

## DP-2 — Shallow clones (`git clone --depth 1`)

**Shape.** The repo was cloned with depth 1 (or other small depth). `git rev-parse --is-shallow-repository` returns `true`. `.git/shallow` lists the shallow boundary commits. The history visible to git ends at those boundaries; commits beyond are missing.

**Why it breaks defaults.**

- The reflog window is severely truncated — most reflog entries reference SHAs that aren't in the local object store.
- Many `git rev-list --count <merge-base>..<branch>` queries return inflated values or fail (because merge-base computation needs ancestors).
- `git cherry -v <canonical> <branch>` may return spurious results (patch-id matching against truncated history).
- Phase 3 bundle: `git bundle create --all` on a shallow repo creates a bundle that's only valid against the same shallow boundary on a recipient.

**Detection.**

```bash
git -C "$PROJECT" rev-parse --is-shallow-repository
# Returns 'true' if shallow.
```

**Adjustment.**

- **Refuse Phase 8 apply.** The skill cannot safely cherry-pick when the merge-base computation is unreliable.
- **Run in `bundle-only-mode`**: emit Phases 1–6 (inventory, bundle, triage, harmonization plan) but skip apply + cleanup. The user is told to run `git fetch --unshallow origin` first if they want the full skill.
- The bundle is still useful as an audit artifact; it just can't be *consumed* by the cleanup phase.
- Surface unmistakably at Phase 0:

```
This is a shallow clone (depth=1). The skill cannot safely apply cherry-picks
or harmonize variants because the merge-base computation is unreliable on
shallow histories. Options:
  (a) Run `git fetch --unshallow origin` first (network-heavy; may take minutes
      on a large repo); then re-invoke the skill.
  (b) Run in `--bundle-only-mode`: produces inventory + bundle + triage + harmonization
      plan; no destructive cleanup. Useful for audit, useless for cleanup.
  (c) Abort.
```

**Cross-link.** [WHEN-NOT-TO-USE.md](WHEN-NOT-TO-USE.md); Pro Git §10 (`git bundle` semantics).

---

## DP-3 — Partial clones (`git clone --filter=blob:none`)

**Shape.** Trees and commits are present; blobs are lazy-fetched on demand. `git rev-parse` returns valid SHAs but the underlying file content may not be in the local object store until it's accessed. `extensions.partialClone` is set in `.git/config`.

**Why it breaks defaults.**

- Phase 3 bundle creation (`git diff --binary <merge-base>..<branch>` for every branch) **triggers blob fetches** for every modified path. On a large repo with many branches, this can pull tens of GB.
- The bandwidth implications are silent — the user clicked "rationalize" without realizing the bundle would force a bulk fetch.
- The `git bundle create --all` command bundles only what's locally present; missing blobs are not auto-fetched and the bundle is incomplete.

**Detection.**

```bash
git -C "$PROJECT" config --get extensions.partialClone   # non-empty means partial clone
git -C "$PROJECT" config --get remote.origin.promisor    # true → blobs are promisor-tracked
```

**Adjustment.**

- Surface the bandwidth implication at Phase 0:

```
This is a partial clone (filter=blob:none). Bundle creation will lazy-fetch
blobs for all modified files across all branches; this can be ~N GB depending
on branch count and content size.

Estimated fetch: <calculate from branch count + average diff size>.
Continue? (y/n)
```

- Phase 3 explicitly fetches missing blobs in advance (one bulk operation, easier to monitor than scatter-fetches per file):

```bash
git -C "$PROJECT" fetch --filter=blob:none origin --no-tags
git -C "$PROJECT" rev-list --objects --missing=print "$BACKUP_REFS_NS" \
  | awk '/^?/ {print substr($0,2)}' \
  | git -C "$PROJECT" cat-file --batch-check  # forces blob fetch via batch
```

- The `--filter=blob:none` clone of the bundle remains incomplete unless the user explicitly runs `git lfs fetch --all` or `git fetch --no-filter`.

**Cross-link.** Pro Git §10.6.5 (partial clones); [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md).

---

## DP-4 — Bare clones used for multi-worktree workflows

**Shape.** Layout common to power users:

```
~/work/foo.git/                    ← bare clone (the source-of-truth git dir)
~/work/foo-main/                   ← worktree-as-main on canonical
~/work/foo-feat-1/                 ← worktree on feat-1
~/work/foo-feat-2/                 ← worktree on feat-2
```

`~/work/foo.git/` IS the bare repo; every "worktree" is a `git worktree add` linked from the bare. There's no "main repo with linked worktrees" — the bare directory plays that role.

**Why it breaks defaults.**

- `git rev-parse --is-bare-repository` returns `true` on the bare directory; per [WHEN-NOT-TO-USE.md](WHEN-NOT-TO-USE.md), the skill refuses bare repos. But this isn't a CI bare clone with no worktrees; it's a user's deliberate workflow with several worktrees.
- The skill's working assumption — "main worktree at the repo root, linked worktrees elsewhere" — breaks. There is no main worktree.

**Detection.**

```bash
is_bare=$(git -C "$PROJECT" rev-parse --is-bare-repository)
worktrees=$(git -C "$PROJECT" worktree list | wc -l)
[ "$is_bare" = "true" ] && (( worktrees >= 2 )) && echo "BARE-AS-WORKTREE-HUB"
```

**Adjustment.**

- The skill operates against the linked worktrees, never the bare. Pick one of the worktrees as the "active worktree" for the run (typically the one CWD'd-to by the user).
- All Phase 8 commits go on the rationalization branch in the bare's namespace (`refs/heads/branch-rationalization-<DATE>`); the rat-branch is materialized in a fresh worktree (`git worktree add ~/work/foo-ratbranch branch-rationalization-<DATE>`) for the apply.
- Phase 10 cleanup removes worktrees normally; the bare's HEAD is never touched (it's typically `master` or `main` and is not in scope).

**Why this matters.** Power users who use this pattern are already comfortable with `git worktree`; refusing the skill on their setup is over-strict. The skill recognizes the pattern and adapts.

**Cross-link.** [REPO-ARCHETYPES.md A9](REPO-ARCHETYPES.md#a9--bare-then-clone-ci-repo) (related but different — A9 is CI, this is power-user).

---

## DP-5 — Submodule-of-submodule (recursive)

**Shape.** Parent repo has submodules; each submodule has its own submodules. Common in vendored-fork setups or massive Linux-kernel-style organizations. `git submodule status --recursive` shows multiple levels of nesting.

**Why it breaks defaults.**

- The default submodule handling per [REPO-ARCHETYPES.md A6](REPO-ARCHETYPES.md#a6--submodules) covers parent-only. With recursion, a branch's "submodule pointer change" may cascade through multiple levels.
- Recovery requires the entire chain of submodule remotes to be reachable.
- The bundle's `submodule_pointers.tsv` per branch must record the full chain.

**Detection.**

```bash
recursive_count=$(git -C "$PROJECT" submodule status --recursive | wc -l)
direct_count=$(git -C "$PROJECT" submodule status | wc -l)
[ "$recursive_count" -gt "$direct_count" ] && echo "RECURSIVE SUBMODULES"
```

**Adjustment.**

- At Phase 0, surface the recursion depth and ask whether to operate against parent only (default) or recurse.
- If the user opts to recurse: each submodule gets its own `worktree_branch_rationalization_workspace` and its own bundle. Coordinate via the parent's run-id thread.
- Recovery story: the `index.tsv` of the parent's bundle includes a `recursive_chain` column listing the full submodule pointer chain at backup time.

**Cross-link.** [REPO-ARCHETYPES.md A6](REPO-ARCHETYPES.md#a6--submodules); [ADVANCED-RECOVERY.md](ADVANCED-RECOVERY.md) section on submodule divergence.

---

## DP-6 — Repos with `git lfs`

**Shape.** Files matching patterns in `.gitattributes` (e.g., `*.psd filter=lfs`, `*.ipa filter=lfs`) are stored as LFS pointer text files in the git history; the actual binary content lives in an LFS server.

**Why it breaks defaults.**

- Phase 3 bundle's per-branch unified diff captures the **pointer file**, not the LFS blob. Pointers are small text:
  ```
  version https://git-lfs.github.com/spec/v1
  oid sha256:abc123...
  size 1048576
  ```
- Recovery from the bundle reproduces the pointer; the binary requires `git lfs fetch` against an LFS server. If the server is no longer reachable (the LFS storage was deleted, the credentials expired, the bandwidth limit was hit), the binary is gone.

**Detection.**

```bash
git -C "$PROJECT" config --get-all filter.lfs.process >/dev/null 2>&1 && echo "LFS"
grep -q 'filter=lfs' "$PROJECT/.gitattributes" 2>/dev/null && echo "LFS"
```

**Adjustment.**

- Bundle README explicitly notes the LFS limitation:

```
## LFS notice
This repo uses git-lfs. The bundle contains:
  - LFS pointer files (text, in branches/<slug>/diff-vs-merge-base.diff)
  - NOT the LFS blobs themselves

To fully restore an LFS-tracked file:
  1. git apply --3way <bundle>/branches/<slug>/diff-vs-merge-base.diff   (restores pointer)
  2. git lfs pull                                                          (fetches blob)
  Both steps require:
    - git-lfs installed
    - LFS server reachable at <origin's LFS URL>
    - Sufficient LFS bandwidth allowance
```

- Phase 8 apply: if a cherry-pick involves LFS pointer changes, run `git lfs pull` before running the project's tests (the tests usually need the binary content).
- Phase 10 cleanup: `git branch -d` does NOT delete LFS objects; LFS retention is governed by the LFS server. The handoff explicitly says: "LFS objects are not deleted by this run; manage LFS retention via your LFS server's controls."

**Cross-link.** [REPO-ARCHETYPES.md A7](REPO-ARCHETYPES.md#a7--lfs-managed-binaries).

---

## DP-7 — Repos with `git annex`

**Shape.** Similar to LFS but more elaborate — `git-annex` uses cryptographic content addressing and supports many backend storages (S3, rsync, web, IPFS, etc.). `git annex` symlinks point at content stored in `.git/annex/objects/<hash>/`. Some content may be locally absent ("`git annex get` to fetch").

**Why it breaks defaults.**

- The skill's bundle treats annex symlinks as opaque text; the symlink target is recorded in the diff but the actual content is in the annex store, not in git.
- Recovery requires the annex remote to be reachable.

**Detection.**

```bash
[ -d "$PROJECT/.git/annex" ] && echo "GIT-ANNEX"
git -C "$PROJECT" config --get-regexp 'annex\..*' >/dev/null 2>&1 && echo "GIT-ANNEX"
```

**Adjustment.**

- Bundle README adds an "Annex caveat" section paralleling the LFS one.
- Phase 8 apply: `git annex get` after the cherry-pick if annex content is needed for tests.
- The skill operates on the symlinks (which are git-tracked); annex content lifecycle is not in scope.

**Why this matters.** git-annex is rare but real in scientific computing, dataset management, and some media production workflows; ignoring it silently breaks the recovery story.

**Cross-link.** [git-annex documentation](https://git-annex.branchable.com/).

---

## DP-8 — Worktrees with custom `core.worktree`

**Shape.** A worktree's `.git` file (or in a separate-`.git` setup, the per-worktree `.git/worktrees/<id>/config`) overrides `core.worktree`. The git-tracked tree is at one location; the working tree is at another. Rare, but legal — used in some CI configurations and in `git svn` migrations.

**Why it breaks defaults.**

- `git -C <worktree-path>` may not work as expected; the actual working directory is elsewhere.
- The skill's per-worktree status capture (Phase 3) reads from the wrong location.

**Detection.**

```bash
for wt in $(git worktree list --porcelain | awk '/^worktree / {print $2}'); do
  custom_wt=$(git -C "$wt" config --local --get core.worktree 2>/dev/null)
  [ -n "$custom_wt" ] && echo "$wt has custom core.worktree=$custom_wt"
done
```

**Adjustment.**

- When detected, use the configured `core.worktree` value as the actual file-system path for capture; record both `git_dir_path` and `working_tree_path` in `worktrees.tsv`.
- Phase 10 worktree removal: `git worktree remove` respects the override; the skill calls it directly without manipulating the path.

**Why this matters.** A capture at the wrong path silently misses the user's actual changes.

---

## DP-9 — Repos with `extensions.partialClone` AND missing objects

**Shape.** Partial clones can have inflated `git rev-list --count` numbers when the object graph is incomplete. The `git rev-list` walker can reach commits whose parents aren't local; it counts them anyway, producing inflated ahead/behind metrics.

**Why it breaks defaults.**

- `branches.tsv:ahead` and `branches.tsv:behind` may be wrong.
- `git cherry -v` may report patch-id mismatches because the comparison doesn't have all blobs.

**Detection.** Same as DP-3 (`extensions.partialClone` is set), but with an additional graph-completeness check:

```bash
# Check whether walking from canonical reaches all commits without missing objects:
git -C "$PROJECT" rev-list --objects --missing=print "$CANONICAL" | head -20
# Empty output = complete graph; non-empty = some objects missing
```

**Adjustment.**

- Warn the user: "ahead/behind counts may be inflated due to partial clone; consider `git fetch --unshallow` or `git fetch --no-filter` for accurate triage."
- Phase 5 triage adds a confidence penalty (-0.1) on rows where the count is suspect.

**Cross-link.** [DP-3](#dp-3--partial-clones-git-clone---filterblobnone).

---

## DP-10 — Massive repos (≥1M commits, ≥10 GB packfiles)

**Shape.** Linux kernel scale. `git rev-list --count HEAD` returns 7+ digits; `du -sh .git` shows tens of GB.

**Why it breaks defaults.**

- Phase 3 bundle creation can take 20+ minutes; `git bundle create --all` over a backup namespace with 200 entries may produce a multi-GB bundle.
- Per-branch `git diff --binary <merge-base>..<branch>` is fast individually but slow in aggregate.
- `git bundle list-heads` round-trip verification on a multi-GB bundle is slow.
- Memory pressure during bundle write may trigger swap.

**Detection.**

```bash
commits=$(git -C "$PROJECT" rev-list --count HEAD)
packfile_size=$(du -sb "$PROJECT/.git/objects/pack" | awk '{print $1}')
(( commits > 1000000 )) || (( packfile_size > 10737418240 )) && echo "MASSIVE"
```

**Adjustment.**

- Show progress during Phase 3: "bundling branch 47 of 213..."
- Offer `--bundle-batch-size N` flag (default 50, lowered to 10 on massive repos): build the object bundle in batches, each with its own verification step.
- Use `git pack-objects --depth=50 --window=10` for tighter packs (smaller bundle file).
- Stream the byte-equality check (incremental SHA-256 over the bundle as it's written) rather than reading it whole at the end.

**Cross-link.** [BUNDLE-FORMAT-SPEC.md "Massive repo handling"](BUNDLE-FORMAT-SPEC.md).

---

## DP-11 — Repos with `core.commitGraph` enabled but stale

**Shape.** `git commit-graph` is a perf optimization storing precomputed parent + topological order data in `.git/objects/info/commit-graph`. If the file is stale (commits exist that aren't in the graph), some queries return inconsistent results.

**Why it breaks defaults.**

- `git rev-list` may use the commit graph and miss recent commits.
- `git merge-base --octopus` may return wrong values.
- `git cherry -v` may misclassify.

**Detection.**

```bash
[ -f "$PROJECT/.git/objects/info/commit-graph" ] && \
  git -C "$PROJECT" commit-graph verify 2>&1 | grep -q "warning\|error" && \
  echo "STALE COMMIT-GRAPH"
```

**Adjustment.**

- Suggest `git commit-graph write --reachable` before Phase 2 inventory.
- The skill never modifies `.git/`; the user runs the rebuild themselves.

**Why this matters.** Subtle and rare, but on long-running repos with frequent agent activity, the commit graph can lag.

---

## DP-12 — Repos with hooks that mutate state at read-time

**Shape.** Pre-commit, pre-push, post-checkout hooks that modify files (auto-format on checkout; regenerate generated code on every checkout). Some hooks even mutate `.git/` state.

**Why it breaks defaults.**

- Phase 8 cherry-pick triggers post-checkout if the rat-branch's working tree is updated; the hook may modify files not part of the keeper.
- Pre-commit hooks may regenerate files (timestamps; build metadata) that the commit captures.

**Detection.**

```bash
for hook in $PROJECT/.git/hooks/{pre-commit,post-checkout,pre-push,post-merge}; do
  [ -x "$hook" ] || continue
  # Heuristic: if the hook contains 'git add' or 'git commit', it's mutating
  grep -lE '\b(git add|git commit|git update-ref)\b' "$hook" >/dev/null && \
    echo "MUTATING HOOK: $hook"
done
```

**Adjustment.**

- Surface to user at Phase 0: "your hooks at `<paths>` mutate state at read-time. Phase 8 will trigger them; the per-keeper commit may include unintended changes."
- **Refuse Phase 8 apply if a pre-commit hook makes destructive changes outside the rationalization-branch worktree.** The skill cannot guarantee non-rat-branch worktrees stay untouched.
- Per [SKILL.md "Anti-Patterns"](../SKILL.md#anti-patterns-never-do): do **not** bypass the hooks (`--no-verify`); fix the hook OR fix the underlying mutation.

**Cross-link.** [REPO-ARCHETYPES.md A12](REPO-ARCHETYPES.md#a12--repo-with-pre-commit-hooks-husky--lefthook--pre-commit--git-native).

---

## DP-13 — Repos behind corporate proxies / SSO / SAML

**Shape.** `gh` requires SSO re-auth; `git push` requires a fresh SAML token; `https://` URLs go through a corporate proxy that rewrites tokens. Common in enterprise environments.

**Why it breaks defaults.**

- `scripts/github-pr-awareness.sh` calls `gh api` which may fail with 401 or 403 if the SSO token has expired.
- `git fetch` (read-only) may fail if the proxy requires recent auth.

**Detection.**

```bash
gh auth status 2>&1 | grep -i 'expired\|requires\|sso'   # SSO/SAML hints
git -C "$PROJECT" config --get-regexp 'http\..*\.proxy' >/dev/null 2>&1 && echo "HAS PROXY"
```

**Adjustment.**

- Treat `gh api` failures as soft (skip PR awareness; don't block the run).
- Skip `git fetch` in Phase 0.5; rely on the local view; warn the user that "ahead/behind counts may not reflect remote state."
- Phase 11 handoff explicitly tells the user: "if your SSO/SAML token expired during the run, refresh and re-fetch before pushing the rat-branch."

**Why this matters.** Corporate environments are common in production-critical work; the skill should degrade gracefully.

---

## DP-14 — Repos with case-insensitive filesystems (macOS default, Windows)

**Shape.** macOS (HFS+/APFS default) and Windows (NTFS default) treat `Foo.rs` and `foo.rs` as the same file. Linux is case-sensitive.

**Why it breaks defaults.**

- A branch that renames `Foo.rs` to `foo.rs` looks like a no-op on macOS but is a real change on Linux.
- `git diff` may report no change; the apply may fail on case-sensitive filesystems.

**Detection.**

```bash
case_sensitive=$(touch "$PROJECT/.casecheck.txt"; touch "$PROJECT/.CASECHECK.TXT"; \
                 [ -f "$PROJECT/.CASECHECK.TXT" ] && [ -f "$PROJECT/.casecheck.txt" ] && \
                 [ "$(ls "$PROJECT" | grep -ci casecheck)" = "2" ] && echo true || echo false)
rm -f "$PROJECT/.casecheck.txt" "$PROJECT/.CASECHECK.TXT" 2>/dev/null
```

(Note: this test creates and removes ephemeral files; the `rm -f` here is on user-namespace filenames the skill itself just created — not user data — and is the only acceptable form. DCG allows this pattern because it's a roundtrip on a known-name we just authored.)

**Adjustment.**

- If filesystem is case-insensitive, branches whose only diff is a case-rename are surfaced as `divergent-refactor` (the apply on Linux would land a different result than on macOS).
- The user is told to validate on the target filesystem before merging the rat-branch.

---

## DP-15 — Repos with `.gitattributes` text/eol normalization

**Shape.** Files like `* text=auto eol=lf` or `*.bat eol=crlf` cause line-ending conversion at checkout/commit. Diffs may show line-ending changes that aren't really there.

**Why it breaks defaults.**

- `git cherry -v` patch-id matching uses the *post-normalization* content; a branch whose only "change" is line-ending may classify wrongly.
- The bundle's diff captures the post-normalization content; restoration on a system with different normalization rules may produce different files.

**Detection.**

```bash
[ -f "$PROJECT/.gitattributes" ] && grep -E 'eol=|text=' "$PROJECT/.gitattributes" >/dev/null && \
  echo "EOL-NORMALIZATION ACTIVE"
```

**Adjustment.**

- Branches whose only diff is line-ending changes → `garbage` verdict (the normalization rules will re-emit the canonical form).
- The bundle's README notes: "this repo has line-ending normalization; the diffs in `branches/<slug>/diff-vs-merge-base.diff` are post-normalization."

---

## DP-16 — Repos with non-UTF8 paths or commit messages

**Shape.** A branch was created with a non-UTF8 commit message (legacy SHIFT-JIS, latin-1, etc.) OR the working tree has paths that aren't valid UTF-8.

**Why it breaks defaults.**

- TSV files (the workspace's main data format) assume UTF-8; non-UTF-8 paths break the encoding.
- `awk -F'\t'` may misinterpret split bytes.

**Detection.**

```bash
git -C "$PROJECT" log --format='%H %s' | iconv -f utf-8 -t utf-8 -c >/dev/null
# Non-zero exit means non-UTF-8 messages exist.
```

**Adjustment.**

- Use base64 encoding for non-UTF-8 paths and messages in TSV files.
- Bundle README notes: "some commit messages were base64-encoded due to non-UTF-8 content; decode via `cat <field> | base64 -d`."

**Why this matters.** Niche but real in old internationalized repos.

---

## DP-17 — Repos with `.git` extensions (`extensions.objectFormat=sha256`)

**Shape.** Newer git (2.42+) supports SHA-256 object format. `git config extensions.objectFormat sha256` makes the repo SHA-256 throughout.

**Why it breaks defaults.**

- Some scripts assume 40-char SHA-1; SHA-256 is 64 chars.
- Tooling that hard-codes SHA-1 byte length will break.

**Detection.**

```bash
[ "$(git -C "$PROJECT" config extensions.objectFormat 2>/dev/null)" = "sha256" ] && echo "SHA-256"
```

**Adjustment.**

- Use `git rev-parse` to get SHAs; never assume length.
- TSV files store SHAs as strings; awk doesn't care about length.
- The bundle is git-format-agnostic; `git bundle create` works on either.

**Why this matters.** The skill should be future-proof; SHA-256 adoption is slow but real.

---

## DP-18 — Repos with very-long branch names (>250 chars)

**Shape.** Some agent swarms generate branch names with long descriptive content (`agent-cc-12-attempt-3-fix-mysql-ok-packet-cap-with-defensive-null-check-and-redaction-v2-final-FINAL-redo`).

**Why it breaks defaults.**

- Path-based artifact storage (`branches/<slug>/...`) has filesystem limits (255 chars on most systems for a single path component; longer paths are valid up to PATH_MAX, often 4096).
- Slug computation uses the branch name; long slugs blow past per-component limits.

**Detection.**

```bash
git -C "$PROJECT" branch | awk '{print $NF}' | awk 'length > 200'
```

**Adjustment.**

- Slug truncation: `<safe-name-truncated-to-100-chars>-<sha1[0:12]>`. The truncation drops middle characters preferentially; the prefix (often the most distinguishing) is preserved.
- The bundle's `index.tsv` records the full original name; only the on-disk slug is truncated.

---

## DP-19 — Repos with worktrees on different filesystems

**Shape.** Main repo on `/data/projects/foo/`; one worktree on `/mnt/external/foo-wt-debug/` (NFS); another on `/tmp/foo-wt-quick/` (tmpfs).

**Why it breaks defaults.**

- Hardlinks across filesystems fail; `git worktree add` may fall back to copies (silently slower; uses more disk).
- The bundle path may need to be on a different filesystem than the worktree it's archiving.

**Detection.**

```bash
for wt in $(git worktree list --porcelain | awk '/^worktree / {print $2}'); do
  fs=$(stat -c '%m' "$wt")
  echo "$wt on filesystem mounted at $fs"
done
```

**Adjustment.**

- `worktrees.tsv` records each worktree's filesystem mount point.
- Bundle path defaults to next-to-the-main-repo's filesystem; the user is asked if a different mount is preferred.
- Removing a worktree on tmpfs is fast; on NFS may be slow but otherwise normal.

---

## DP-20 — Repos used as a Docker volume mount

**Shape.** The repo is at `/data/projects/foo/` on the host; a Docker container has it bind-mounted at `/workspace/`. The skill may be invoked from inside the container OR from the host; paths differ.

**Why it breaks defaults.**

- `git worktree list` returns paths relative to the running process's view (the container's `/workspace/...`); the same paths don't exist on the host.
- The bundle path defaults to `<project-parent>/...`; if invoked from inside the container, that's `/` (parent of `/workspace`) — which is read-only.

**Detection.**

```bash
[ -f /.dockerenv ] && echo "INSIDE DOCKER"
mount | grep "type fuse\|type 9p\|type overlay" | grep -q "$PROJECT" && echo "BIND-MOUNTED"
```

**Adjustment.**

- Surface the issue at Phase 0; ask the user to specify a bundle path that's writable from the current namespace.
- The skill doesn't try to be clever about path-translation between container and host; the user picks an explicit path.

---

## Combinations

Real difficult-project setups often combine multiple DPs. Examples:

| Combo | Effect |
|---|---|
| DP-1 + DP-3 (sparse + partial clone) | Per-worktree captures lose content outside cone AND blob-fetches needed for bundle creation |
| DP-2 + DP-12 (shallow + mutating hooks) | Refuse the run; shallow precludes apply, mutating hooks make read-only triage unsafe |
| DP-6 + DP-10 (LFS + massive repo) | Bundle creation is bandwidth-bound (LFS pointers fetched on every diff); +30-60 min to Phase 3 |
| DP-9 + DP-13 (partial clone + corporate SSO) | Triage confidence drops; gh auth may fail; degrade gracefully |
| DP-15 + DP-16 (EOL + non-UTF-8) | Surface heuristics fail; recommend manual review |

For repos matching ≥3 DPs, escalate the mode automatically (Quick → Standard → Comprehensive) and surface the cumulative caveat in the handoff.

---

## Cross-References

- The 20 common archetypes the skill auto-detects: [REPO-ARCHETYPES.md](REPO-ARCHETYPES.md)
- Bundle format and verification: [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md)
- Worktree-state discipline: [WORKTREE-STATE.md](WORKTREE-STATE.md)
- When to refuse: [WHEN-NOT-TO-USE.md](WHEN-NOT-TO-USE.md)
- Failure-mode catalog (git mechanics): [FAILURE-MODES.md](FAILURE-MODES.md)
- Recovery procedures: [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md), [ADVANCED-RECOVERY.md](ADVANCED-RECOVERY.md)
