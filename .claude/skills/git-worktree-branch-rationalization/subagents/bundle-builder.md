---
name: bundle-builder
description: Phase 3 — backup refs + git object bundle + per-branch artifacts (commits.tsv, meta.txt, diff-vs-merge-base.diff, format-patch series) + per-worktree dirty captures (staged.diff, unstaged.diff, status.txt, .untracked.list, untracked.tar.gz, meta.txt) + index + README; byte-equality + bundle-round-trip verified. Hard gate before destructive phases.
---

# Bundle Builder

Owns Phase 3. The irreversibility gate (Axiom 3, ⬡ BUNDLE). This phase MUST complete with byte-equality AND bundle round-trip verified before any classification or destructive action runs. If the bundle is wrong, the entire run is unsafe — halt.

Why: Axiom 4 says all five reversibility layers (backup ref + object bundle + per-branch diff/format-patch + per-worktree dirty archive + meta + index) must reflect the same content. Silos produce the deepest failures.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle directory; default `<project-parent>/<basename>-branch-worktree-archive-<YYYY-MM-DD>/`

## Outputs

- `<bundle>/branches/<slug>/{meta.txt,commits.tsv,diff-vs-merge-base.diff,format-patch/*.patch}` — per-branch artifacts (one set per `branches.tsv` row).
- `<bundle>/worktrees/<sanitized-path>/{meta.txt,status.txt,staged.diff,unstaged.diff[,.untracked.list,untracked.tar.gz]}` — per-worktree dirty captures (untracked pair only when `has_untracked`).
- `<bundle>/object-bundle.pack` — `git bundle create --all` covering canonical + tags + every backup ref.
- `<bundle>/index.tsv` — `kind|name|sha|merge-base|verdict-placeholder|bundle-paths` for every branch and captured worktree (verdict filled in Phase 6).
- `<bundle>/README.md` — recovery recipes annotated with branch-specific footguns and cross-link to git-stash-janitor's stash-side rule.
- `<workspace>/bundle_path.txt` — absolute path to `{BUNDLE}` for downstream phases.
- `<workspace>/bundle_verification.log` — must contain zero `MISMATCH` and zero `MISSING` lines.
- **Side effects:** writes `refs/branch-rationalization-backup/<slug>` for every branch (one ref per branch; survives `git branch -d`). Never modifies `refs/heads/*`.
- **Decision contract:** `verify-bundle.sh` exit code drives the gate — exit 0 = Phase 4 may run; non-zero = HALT and spawn incident-responder.

## Workflow

1. Run `scripts/build-bundle.sh {PROJECT}` with `BUNDLE_OVERRIDE` env if user provided a custom path. The script creates:

   ### Per branch (one row per `branches.tsv` entry)
   - **Backup ref**: `git update-ref refs/branch-rationalization-backup/<slug> <head_sha>` — byte-identical to live branch tip.
   - `<bundle>/branches/<slug>/meta.txt` — head SHA, merge-base, ahead/behind, upstream, last-commit date, last-commit subject.
   - `<bundle>/branches/<slug>/commits.tsv` — one row per commit not on canonical (`git log --format='%H\t%ct\t%an\t%s' <merge-base>..<branch>`).
   - `<bundle>/branches/<slug>/diff-vs-merge-base.diff` — `git diff --binary <merge-base>...<branch>` (three-dot — diff against merge-base, not against canonical's tip).
   - `<bundle>/branches/<slug>/format-patch/000N-*.patch` — `git format-patch <merge-base>..<branch>` series.

   **Cross-link to stash-janitor footgun**: `git format-patch` is **valid for branches** (Axiom 7). It is NOT valid as a stash-recovery mechanism — that's git-stash-janitor's rule. The bundle README cross-links this so future readers don't generalize the wrong direction. The bundle's `format-patch/*.patch` files are part of the recovery story for branches and have no analogue for stashes.

   ### Per worktree (one row per `worktrees.tsv` entry, skip `is_main` and skip `prunable`)
   - `<bundle>/worktrees/<sanitized-path>/meta.txt` — original path, branch (or detached HEAD), last commit, locks, dirty summary, submodule state.
   - `<bundle>/worktrees/<sanitized-path>/status.txt` — `git -C <path> status --porcelain` snapshot.
   - `<bundle>/worktrees/<sanitized-path>/staged.diff` — `git -C <path> diff --binary --cached`.
   - `<bundle>/worktrees/<sanitized-path>/unstaged.diff` — `git -C <path> diff --binary`.
   - `<bundle>/worktrees/<sanitized-path>/.untracked.list` — only when `has_untracked` is true; NUL-delimited output from `git ls-files --others --exclude-standard -z`.
   - `<bundle>/worktrees/<sanitized-path>/untracked.tar.gz` — only when `has_untracked` is true; `tar --null -czf` over `.untracked.list`.

   ### Whole-namespace
   - `<bundle>/object-bundle.pack` — `git bundle create <bundle>/object-bundle.pack --all` after backup refs are written, so the bundle covers `refs/branch-rationalization-backup/*` plus canonical plus tags. This is the offline-recoverable archive of every branch's commit graph.
   - `<bundle>/index.tsv` — `kind|name|sha|merge-base|verdict-placeholder|bundle-paths` for every branch and every captured worktree (verdict filled in Phase 6).
   - `<bundle>/README.md` — recovery recipes verbatim, annotated with branch-specific footguns:
     - Recovery via backup ref: `git branch <name> refs/branch-rationalization-backup/<slug>`
     - Recovery via bundle: `git fetch <BUNDLE>/object-bundle.pack '+refs/branch-rationalization-backup/*:refs/heads/recovered-*'`
     - Recovery via diff: `git apply --3way <BUNDLE>/branches/<slug>/diff-vs-merge-base.diff`
     - Recovery via format-patch: `git am <BUNDLE>/branches/<slug>/format-patch/*.patch`
     - Recovery of a worktree's dirty state: `git -C <path> apply <BUNDLE>/worktrees/<sanitized-path>/staged.diff` then `--cached` etc.; untracked via `tar --null -xzf untracked.tar.gz -C <path> -T .untracked.list`
     - **Footgun: cherry-picking a merge commit** — use `-m 1` (or appropriate parent); document the choice in the recipe.
     - **Footgun: cherry-picking a squash-merged commit** — produces "nothing to commit"; `git cherry -v` would have flagged it; classify as `already-merged`.
     - **Footgun: format-patch is for branches, not stashes** — see git-stash-janitor's bundle for the stash-side rule.

2. **Run `scripts/verify-bundle.sh {PROJECT}`** — the gate. It must verify:
   - For every `branches.tsv:slug`, `git rev-parse refs/branch-rationalization-backup/<slug>` == the original `head_sha`.
   - `git bundle list-heads <bundle>/object-bundle.pack` resolves every backup ref byte-identically.
   - `git bundle verify <bundle>/object-bundle.pack` exits 0.
   - For every `worktrees.tsv` row that should have captures, the corresponding files exist and are non-empty (status.txt may be empty for a clean worktree; staged.diff and unstaged.diff may be empty; `.untracked.list` and untracked.tar.gz only present when `has_untracked`).
   - `bundle_verification.log` has zero `MISMATCH` and zero `MISSING` lines.

3. **Spot-check 3 random branches** by re-deriving `git diff --binary <merge-base>...<branch>` and `diff`-ing against the bundle's stored diff. All diffs must be empty.

4. **Spot-check 3 random worktrees** (if any have dirty state) by re-deriving `git -C <path> diff --binary --cached` and diffing against staged.diff. All diffs must be empty.

## Critical rules

- **Use `git diff --binary` for both branch diff and worktree captures.** Without `--binary`, tracked binary payloads are silently lost.
- **`git format-patch` IS valid for branches.** Per Axiom 7. Do not generalize git-stash-janitor's "format-patch is wrong" rule — that applies to stashes only.
- **Backup refs go in `refs/branch-rationalization-backup/<slug>`**, not `refs/heads/`. They survive `git branch -d` of the live branch because they are separate refs.
- **Never delete the bundle**, even on user request. The user manages bundle lifecycle (Axiom 18). DCG correctly blocks `rm -rf` on it; the skill is designed never to need that command.
- **If verification fails, HALT the run immediately.** Do not attempt to fix bundle artifacts on the fly; spawn the incident-responder with code matching the failure.
- **Never bypass pre-commit hooks.**
- **Never use sed/awk on source files.**
- **Never disturb concurrent agents' working-tree state** — capturing dirty state from a worktree where another agent is working is *read-only*. Run `git diff --binary` from inside that worktree but never `git stash`, `git checkout`, `git reset`.
- **Never delete files without express user permission.**
- **Never run mass-delete primitives.**

## Coordination

- File reservation: `paths=[".git/refs/branch-rationalization-backup/**", "{BUNDLE}/**"]`, `exclusive=true`, `reason="branch-rationalization-phase3"`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] Every row in `branches.tsv` has a corresponding `refs/branch-rationalization-backup/<slug>` ref byte-identical to the live branch tip
- [ ] Every row in `branches.tsv` has `<bundle>/branches/<slug>/{meta.txt,commits.tsv,diff-vs-merge-base.diff,format-patch/}`
- [ ] Every non-main, non-prunable row in `worktrees.tsv` has `<bundle>/worktrees/<sanitized-path>/{meta.txt,status.txt,staged.diff,unstaged.diff}`; `.untracked.list` and `untracked.tar.gz` present iff `has_untracked` was true
- [ ] `<bundle>/object-bundle.pack` exists; `git bundle verify` exits 0; `git bundle list-heads` resolves every backup ref
- [ ] `<bundle>/index.tsv` row count == sum of branches + captured worktrees, plus a header
- [ ] `<bundle>/README.md` documents the format-patch-is-valid-for-branches note and cross-links to git-stash-janitor's stash-side rule
- [ ] `bundle_verification.log` has zero `MISMATCH` and zero `MISSING` lines
- [ ] Spot-check diffs (3 branches, up to 3 worktrees) all empty

## Exit criteria

`verify-bundle.sh` exits 0; main agent posts "bundle complete and verified at <path>; B branches and W worktrees archived" to user. Phase 4 may now run.
