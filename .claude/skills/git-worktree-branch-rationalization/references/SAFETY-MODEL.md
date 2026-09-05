# Safety Model — Reversibility Chain Per Destructive Action

This file enumerates every action the skill takes that *could* lose work, and the multi-layer reversibility chain that backs each one up. **Two destructive operations** can happen in this skill: **branch deletion** (`git branch -d`/`-D`) and **worktree removal** (`git worktree remove`). Each has its own layered backup story; both share the same verbatim-authorization gate.

> **Why:** Per [SKILL.md Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms), "All five reversibility layers must reflect the same content. If a Phase 3 byte-equality check disagrees on even one entry, the run is unsafe — halt." The "five layers" enumerated below are the per-action chain; they all settle from the same Phase 3 bundle.

---

## Threat Model

The user gives this skill access to a repo with valuable, possibly-fragile work spread across:
- **Local branches** (often 30–500 in agent-swarm aftermath)
- **Linked worktrees** (often 5–80, some with uncommitted dirty state)

The skill's job is to keep useful content and remove the rest. Things that could go wrong:

1. **Mis-classification** — a useful branch gets verdict `garbage` or `superseded`.
2. **Wrong delete** — a similarly-named branch gets deleted instead of the intended one.
3. **Corrupted bundle** — the bundle's diffs / format-patch series don't match the live branches.
4. **Lost backup refs** — `git gc --prune=now` after manual `git update-ref -d refs/branch-rationalization-backup/*`.
5. **Bypassed authorization** — destructive action runs without explicit user OK.
6. **Concurrent agent destruction** — the skill stashes/reverts/overwrites concurrent agents' work in a worktree.
7. **Dirty worktree silently lost** — `git worktree remove --force` runs on a worktree whose dirty state wasn't archived.
8. **Bypassed quality gates** — a recovered keeper introduces a regression.
9. **Compounding errors** — multiple keepers applied in sequence, each subtly broken.
10. **Ambiguous user authorization** — user said "yes" but didn't realize the cleanup plan changed since they last looked.
11. **Bundle deletion** — the bundle and backup refs both get destroyed before recovery is needed.
12. **Order error** — branches deleted before their pinning worktrees are removed; `-d` refuses; `-D` runs anyway and deletes content the user thought was protected.

---

## Reversibility Chain — Branch Deletion

`git branch -d <name>` (or `-D` for unmerged branches) removes the ref from `refs/heads/`. The reflog keeps the commit reachable for ~30–90 days, but the skill treats reflog as the weakest layer. Five independent layers stand between a deletion and lost work:

### Layer 1: Backup Ref (`refs/branch-rationalization-backup/<slug>`)

Created by `⬡ BUNDLE` in Phase 3:

```
.git/refs/branch-rationalization-backup/agent-cc-12-feat-parser  → def456…
.git/refs/branch-rationalization-backup/agent-cod-3-mysql-fix    → 789abc…
…
```

**Inside the repo** (in `.git/refs/`), byte-identical to the live branch SHA at Phase 3 snapshot. Survives:

- `git branch -d <name>` / `git branch -D <name>` — only `refs/heads/<name>` is removed; the backup ref under `refs/branch-rationalization-backup/<slug>` is untouched.
- `git gc --prune=now` — the backup ref is a real ref, garbage collection sees it as a root.
- `git stash clear` — irrelevant to branches.
- Project relocation (the ref lives in `.git/`, which moves with the repo).

Does NOT survive:

- Manual `git update-ref -d refs/branch-rationalization-backup/<slug>` followed by `git gc --prune=now`. The skill never runs this; the user might.
- `rm -rf .git/refs/branch-rationalization-backup/` (catastrophic; would only happen via an explicit, user-authorized command outside the skill).
- `rm -rf .git/` (catastrophic).

> **Why:** [SKILL.md Axiom 8](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git branch -d` over `git branch -D` whenever possible. After Phase 8 lands every keeper, every applied-keeper branch IS fully merged from the rationalization branch's perspective — `-d` will succeed."

### Layer 2: Object Bundle (`<bundle>/object-bundle.pack`)

Created by `⬡ BUNDLE` in Phase 3:

```
<project-parent>/<basename>-branch-worktree-archive-<DATE>/
  object-bundle.pack    ← git bundle create --stdin <<< "refs/branch-rationalization-backup/*"
```

**Outside the repo** (in the parent directory). It's a single self-contained git pack file plus a heads-list. Survives:

- Anything that happens to `.git/`
- `git gc`
- Repository corruption
- Project relocation (the bundle uses absolute heads, but `git fetch <bundle>` works regardless of CWD)

Does NOT survive:

- Explicit `rm` of the bundle directory (DCG blocks `rm -rf`; the skill never runs this; the user might).
- Filesystem corruption / disk loss.

Recovery from this layer:

```bash
git fetch <bundle>/object-bundle.pack \
  refs/branch-rationalization-backup/agent-cc-12-feat-parser:refs/heads/agent-cc-12-feat-parser
```

### Layer 3: Per-Branch Diff (`<bundle>/branches/<slug>/diff-vs-merge-base.diff`)

Created by `⬡ BUNDLE` in Phase 3:

```bash
git diff --binary <merge_base>...<branch> > <bundle>/branches/<slug>/diff-vs-merge-base.diff
```

**Outside the repo**, human-readable (binary content base85-encoded inline). Survives the same conditions as Layer 2.

Recovery:

```bash
git checkout -b agent-cc-12-feat-parser-recovered <merge_base>
git apply <bundle>/branches/agent-cc-12-feat-parser/diff-vs-merge-base.diff
git add -A && git commit -m "recover from bundle diff"
```

This collapses the branch's commit history into one commit but preserves all content. Use Layer 2 (`git fetch`) for full-fidelity history restore.

### Layer 4: Per-Branch Format-Patch Series (`<bundle>/branches/<slug>/format-patch/*.patch`)

Created by `⬡ BUNDLE` in Phase 3:

```bash
git format-patch <merge_base>..<branch> -o <bundle>/branches/<slug>/format-patch/ \
  --binary --no-renames
```

**Outside the repo**, one patch per commit, mailbox format. Preserves commit messages, authorship, dates. Survives the same conditions as Layer 2.

> **Why:** [SKILL.md Axiom 7](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git format-patch` IS valid for branches; it is NOT for stashes. A branch is a normal commit chain — `git format-patch <merge-base>..<branch>` produces a clean ordered series. If you came from git-stash-janitor, do not generalize the 'format-patch is wrong' rule."

Recovery:

```bash
git checkout -b agent-cc-12-feat-parser-recovered <merge_base>
git am <bundle>/branches/agent-cc-12-feat-parser/format-patch/*.patch
```

This restores the full commit-by-commit history.

### Layer 5: Reflog (`refs/heads/<name>` reflog)

`git branch -d` / `-D` writes a reflog entry. The commit remains reachable for the duration of `gc.reflogExpireUnreachable` (default 30 days) and `gc.reflogExpire` (default 90 days). Recovery:

```bash
git reflog show --all | grep <name>
git branch <name> <sha-from-reflog>
```

Time-bounded; the skill treats it as the weakest layer. Layers 1–4 are the durable chain; reflog is the last-resort fallback.

### Layer Independence

| Action affecting Layer 1 | Affects Layer 2? | Affects Layers 3-4? |
|--------------------------|------------------|---------------------|
| `git branch -d <name>` | No | No |
| `git branch -D <name>` | No | No |
| `git gc --prune=now` | No | No |
| `git update-ref -d refs/branch-rationalization-backup/<slug>` | No | No |
| `rm -rf .git` | No (bundle is outside repo) | No |

| Action affecting Layer 2 | Affects Layer 1? | Affects Layers 3-4? |
|--------------------------|------------------|---------------------|
| `rm -rf <bundle>` | No (refs are in `.git/refs/`) | Yes (siblings in same bundle dir) |
| `mv <bundle>/object-bundle.pack /tmp/` | No | No (peers in `branches/`) |

A single command never destroys two independent layers.

---

## Reversibility Chain — Worktree Removal

`git worktree remove <path>` deletes the directory at `<path>` AND removes `.git/worktrees/<id>/` admin metadata. The branch the worktree was checked out on is unaffected by this operation — it's still at `refs/heads/<name>`. The dirty state IS lost unless captured first.

The branch's content is preserved by the **branch-deletion** layers above (the worktree was checked out from a branch). The worktree-specific reversibility chain is for the **dirty state** that was in the worktree at the moment of capture.

### Layer 1: Per-Worktree Staged Diff (`<bundle>/worktrees/<wt-slug>/staged.diff`)

Created by `⬡ BUNDLE` in Phase 3:

```bash
(cd <wt-path> && git diff --binary --cached) > <bundle>/worktrees/<wt-slug>/staged.diff
```

Captures everything in the worktree's index. Survives `git worktree remove`, `git worktree prune`, `rm -rf <wt-path>`, etc., because it lives outside the worktree (and outside the repo).

### Layer 2: Per-Worktree Unstaged Diff (`<bundle>/worktrees/<wt-slug>/unstaged.diff`)

Created by `⬡ BUNDLE` in Phase 3:

```bash
(cd <wt-path> && git diff --binary) > <bundle>/worktrees/<wt-slug>/unstaged.diff
```

Captures everything in the worktree's working tree that's not yet staged. Same survival properties as Layer 1.

### Layer 3: Per-Worktree Untracked Tarball (`<bundle>/worktrees/<wt-slug>/untracked.tar.gz`)

Created by `⬡ BUNDLE` in Phase 3, only when untracked content exists:

```bash
git -C <wt-path> ls-files --others --exclude-standard -z \
  > <bundle>/worktrees/<wt-slug>/.untracked.list
tar --null -czf <bundle>/worktrees/<wt-slug>/untracked.tar.gz \
  -C <wt-path> \
  -T <bundle>/worktrees/<wt-slug>/.untracked.list
```

Captures every untracked-but-not-ignored file. Same survival properties.

### Layer 4: Per-Worktree Status Snapshot (`<bundle>/worktrees/<wt-slug>/status.txt`)

Created by `⬡ BUNDLE` in Phase 3:

```bash
(cd <wt-path> && git status --porcelain=v2) > <bundle>/worktrees/<wt-slug>/status.txt
```

The diagnostic record: which files were modified, added, deleted, untracked. Doesn't *contain* the file content (Layers 1–3 do that), but it tells the recoverer what to expect. Same survival properties.

### Underlying-Branch Preservation

The worktree's underlying branch (the one it was checked out on) is NOT removed by `git worktree remove`. If the user wants to restore the worktree's full state:

```bash
# Step 1: Restore the underlying branch (if it was deleted in Phase 10)
git branch <branch-name> refs/branch-rationalization-backup/<branch-slug>

# Step 2: Recreate the worktree
git worktree add /data/projects/foo-wt-recovered <branch-name>

# Step 3: Restore the dirty state from the worktree bundle
cd /data/projects/foo-wt-recovered
git apply <bundle>/worktrees/<wt-slug>/staged.diff
git apply --cached <bundle>/worktrees/<wt-slug>/staged.diff   # re-stage what was staged
git apply <bundle>/worktrees/<wt-slug>/unstaged.diff
tar --null -xzf <bundle>/worktrees/<wt-slug>/untracked.tar.gz \
  -C / \
  -T <bundle>/worktrees/<wt-slug>/.untracked.list
```

The branch-deletion chain (Layers 1–5 above) and the worktree-removal chain (Layers 1–4 here) are independent and additive. A worktree's full state = its branch's full content + its dirty diffs + its untracked files.

### Admin Metadata (`.git/worktrees/<id>/`)

`git worktree remove <path>` removes both the directory at `<path>` AND `.git/worktrees/<id>/`. If the worktree's directory was deleted out-of-band (e.g., `rm -rf <path>` outside the skill, or filesystem cleanup), the admin metadata persists until `git worktree prune` runs. Phase 10 runs `git worktree prune` AFTER the explicit `git worktree remove` invocations to clean any residual metadata.

> **Why:** [SKILL.md Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Never run `git worktree prune` as a substitute for explicit `git worktree remove`. `prune` only cleans up admin metadata for worktrees already deleted out-of-band."

---

## Force-Removal (`git worktree remove --force`)

`git worktree remove` refuses on dirty worktrees by default. **That refusal is a feature.** Force-removal (`--force`) only runs when:

1. The worktree's staged.diff + unstaged.diff + `.untracked.list` + untracked.tar.gz are confirmed present in the bundle (Layer-1/2/3 verification).
2. The user has explicitly OK'd that the dirty state may be lost — the bundle still has it, but the worktree itself goes away with no in-tree recovery.

The verbatim authorization request for a dirty-worktree force-removal is *separate* from the main Phase 10 plan-level authorization:

```
This worktree has uncommitted changes:
  /data/projects/foo-wt-cc-12   (3 tracked-changed, 1 staged, 2 untracked)

The dirty state IS captured in the bundle at:
  <bundle>/worktrees/_data_projects_foo-wt-cc-12/{staged.diff,unstaged.diff,.untracked.list,untracked.tar.gz}

About to run: git worktree remove --force /data/projects/foo-wt-cc-12

This loses the in-tree dirty state but preserves it in the bundle. To proceed, paste this verbatim:
  yes I understand the dirty state is captured in the bundle and I want to force-remove this worktree
```

> **Why:** [SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms) — "`rm -rf <worktree-path>` is forbidden; `git worktree remove` is the structured operation. Force-remove only when the dirty state has been archived in the bundle AND the user has explicitly OK'd losing it."

---

## Cross-Cutting Layers (Apply to Both Branches and Worktrees)

These layers mediate the destructive operations regardless of which kind of entity is being removed:

### Layer X1: Per-Action Authorization

Every destructive action requires explicit user OK with a verbatim phrase per AGENTS.md "Mandatory explicit plan":

```
Phase 6 gate:  user OK to proceed past triage (no destructive actions yet, but it's the
               authorization to start applying keepers in Phase 8)
Phase 7 gate:  user OK on the harmonization plan
Phase 8 gate:  user OK on each manual conflict resolution
Phase 10 gate: user pastes the verbatim authorization phrase for the cleanup plan
Phase 10 sub:  per-dirty-worktree force-remove authorization
```

The phrase is recorded with timestamp in `cleanup_authorization.txt` (or analogous file for other gates).

> **Why:** [SKILL.md Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms) — "If that file doesn't exist, the action did not happen." This is a load-bearing rule.

### Layer X2: Per-Apply Quality Gates

Every Phase 8 commit goes through `⊕ RECOVER`:

```
{test_command}
{typecheck_command}
{lint_command}
ubs .   # if available
```

All must exit 0 BEFORE commit. If any fail, the apply is rolled back via `git reset --soft HEAD~1` or `git apply -R` (no DCG-blocked operations). The keeper can then be:

- Skipped (`conflict-skipped`)
- Adapted via Edit tool and re-tried
- Surfaced to user

### Layer X3: Phase Gates

| Phase | Gate |
|-------|------|
| 3 | Byte-equality + bundle round-trip verified for every backup ref AND every diff AND every format-patch series |
| 4 | User explicitly confirmed protection list |
| 6 | User explicitly typed approval of triage decision |
| 7 | User explicitly OK'd the harmonization plan (or edited it) |
| 8 | Quality gates passed for every applied keeper (per-apply, not at end) |
| 9 | Two consecutive clean fresh-eyes rounds |
| 10 | User typed the verbatim authorization phrase |

A failure at any gate halts the run. The user investigates.

### Layer X4: Rationalization-Branch Isolation

Phase 8 commits land on `branch-rationalization-<DATE>`, not on canonical. Even if every gate passed wrong, the user can:

```bash
git branch -D branch-rationalization-<DATE>   # only after explicit user confirmation
```

Canonical is untouched. The bundle and backup refs are untouched.

> **Why:** [SKILL.md Axiom 6](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Land on a rationalization branch, not on canonical."

### Layer X5: Verbatim-Plan Restatement Per Item

Even after the plan-level authorization, every individual `git worktree remove` and `git branch -d`/`-D` invocation is restated verbatim before execution:

```
About to run: git worktree remove /data/projects/foo-wt-cc-12
About to run: git branch -d agent-cc-12-feat-parser
…
```

This guarantees the user can audit the exact ref/path being affected at the moment of operation, even if the plan list shifted between authorization and execution.

> **Why:** AGENTS.md "Mandatory explicit plan": "even after explicit user authorization, restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct."

---

## Per-Action Mapping

| Action | Branch L1 (backup ref) | Branch L2 (bundle pack) | Branch L3 (diff) | Branch L4 (format-patch) | Branch L5 (reflog) | Worktree L1 (staged) | Worktree L2 (unstaged) | Worktree L3 (untracked) | X1 auth | X2 gates | X3 phase | X4 isol | X5 verbatim |
|--------|------------------------|-------------------------|------------------|--------------------------|--------------------|----------------------|------------------------|--------------------------|---------|----------|----------|---------|--------------|
| Phase 3 backup ref creation | ✓ | — | — | — | — | — | — | — | — | — | ✓ | — | — |
| Phase 3 bundle creation | — | ✓ | ✓ | ✓ | — | ✓ | ✓ | ✓ | — | — | ✓ | — | — |
| Phase 8 cherry-pick / squash / rebase / harmonized-synthesis | ✓ | ✓ | ✓ | ✓ | — | n/a | n/a | n/a | ✓ | ✓ | ✓ | ✓ | — |
| Phase 8 manual conflict resolution | ✓ | ✓ | ✓ | ✓ | — | n/a | n/a | n/a | ✓ | ✓ | — | ✓ | — |
| Phase 10 `git worktree remove` (clean) | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ | — | ✓ | — | ✓ |
| Phase 10 `git worktree remove --force` (dirty) | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ + sub-auth | — | ✓ | — | ✓ |
| Phase 10 `git worktree prune` (residual metadata) | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | ✓ | — | ✓ | — | ✓ |
| Phase 10 `git branch -d` (merged) | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a | n/a | ✓ | — | ✓ | — | ✓ |
| Phase 10 `git branch -D` (unmerged, user-acknowledged) | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a | n/a | ✓ | — | ✓ | — | ✓ |

Every destructive operation has at least **two independent durable recovery paths** (backup ref + bundle), plus the human-readable backstop (diff + format-patch), plus the time-bounded reflog. The five layers tell the same story; if Phase 3 byte-equality disagrees on even one entry, the run halts.

---

## What's NOT Recoverable

To set expectations: the skill is robust against typical agent / human errors, but not invulnerable.

| Catastrophe | Recoverable? |
|-------------|--------------|
| User runs `git branch -D <name>` after Phase 10 (post-cleanup) on a backed-up branch | Yes (backup ref still exists; bundle still exists) |
| User runs `git worktree remove <path>` after Phase 10 on a worktree the skill kept | Dirty state would be lost, but if it was clean: branch is fine; if it was dirty: the user did this outside the skill, no bundle entry |
| User runs `rm -rf .git` | No (catastrophic; only the bundle survives, but `.git` includes refs) |
| User runs `rm -rf <bundle>` | Layer 1 still works; recovery via backup refs |
| User runs `rm -rf .git AND <bundle>` | NOT RECOVERABLE — the user explicitly destroyed both safety nets |
| Disk failure | Recoverable from off-skill backups |
| `git gc --prune=now` after manual `git update-ref -d refs/branch-rationalization-backup/*` | Layer 1 gone; Layer 2/3/4 still works |
| `git gc --prune=now` after `rm -rf <bundle>` | Layer 2/3/4 gone; Layer 1 still works |
| Both refs deleted AND bundle deleted AND `git gc --prune=now` | NOT RECOVERABLE |
| Force-remove a worktree without prior bundle capture (the skill never does this; the user might) | Dirty state lost; underlying branch fine |

The skill never destroys both layers. Layer 1 lives in `.git/refs/`; the skill never deletes anything under `.git/` except via specifically-authorized `git branch -d`/`-D` commands (which only affect `refs/heads/`, not `refs/branch-rationalization-backup/`). Layer 2 lives outside the repo; the skill never deletes the bundle.

> **Why:** [SKILL.md Axiom 18](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Drop the bundle only at the user's pace. The skill is *designed* never to need this command."

---

## Layer-Independence Properties

A key design property: Layer 1 (backup refs in `.git/`) and Layer 2 (bundle pack outside `.git/`) are independent. Damage to one doesn't damage the other.

| Action affecting Layer 1 | Affects Layer 2? |
|--------------------------|------------------|
| `git branch -d <name>` | No (bundle is on disk outside `.git/`) |
| `git branch -D <name>` | No |
| `git gc --prune=now` | No |
| `git update-ref -d refs/branch-rationalization-backup/<slug>` | No |
| `git worktree remove <path>` | No (bundle is outside both `.git/` and `<path>`) |
| `rm -rf .git` | No |

| Action affecting Layer 2 | Affects Layer 1? |
|--------------------------|------------------|
| `rm -rf <bundle>` | No (refs are in `.git/refs/`) |
| `mv <bundle> /tmp/` | No |
| Filesystem corruption on `<bundle>`'s parent | No |

The branch-deletion layers (1–5) and the worktree-removal layers (1–4) are *also* independent. Removing a worktree never affects the branch's backup ref or bundle entry; deleting a branch never affects the worktree's per-worktree dirty-state captures.

---

## Security Properties

**Confidentiality:** the bundle contains the full content of every non-protected branch + every worktree's dirty state. If the repo's branches/worktrees have secrets (API keys, passwords) — which they shouldn't, but might — the bundle inherits them. The bundle's path should not be world-readable on shared systems. The skill writes the bundle with default umask permissions; the user controls the parent directory's permissions.

**Integrity:** the bundle's `index.tsv` records SHA + merge-base + verdict + bundle-paths for every entry. If a malicious actor modifies a diff in the bundle, byte-equality verification (Phase 3) catches it on a re-run. The bundle's `README.md` documents this property so the user can re-verify after the run completes.

**Availability:** the recovery story works as long as either Layer 1 or Layer 2 survives for branches; for worktree dirty state, the recovery requires the bundle (Layer 1 only exists for branches, not worktrees). The skill leaves both intact at end-of-run.

---

## Verbatim-Authorization Audit Trail

Per AGENTS.md "Document the confirmation": "When running any approved destructive command, record (in the session notes / final response) the exact user text that authorized it, the command actually run, and the execution time. If that record is absent, the operation did not happen."

The skill's audit trail:

- `cleanup_authorization.txt` — the verbatim user-typed phrase + UTC timestamp authorizing the Phase 10 plan.
- `cleanup_log.tsv` — one row per destructive command with: phase, kind, name, command_run, timestamp_utc.
- `apply_log.tsv` — one row per Phase 8 commit with: kind, name, new_commit_sha, files_changed, gates_status, strategy, duration_s.
- `partial_split_log.tsv` — one row per Phase 8b split-apply.

If `cleanup_authorization.txt` doesn't exist, no destructive command ran. If `cleanup_log.tsv` shows a row whose `command_run` doesn't appear in the verbatim-authorization request from `cleanup_authorization.txt`, that's an audit-trail violation; the run is unsafe; the operator must investigate.

---

## Failure Recovery Sequence

If the skill detects an inconsistency at any point:

1. **HALT.** Do not proceed.
2. **Surface.** Tell the user what was detected and what state the run is in.
3. **Document.** Write the failure to `<workspace>/halt_reason.txt`.
4. **Wait.** Don't ask "should I continue anyway?" — the user investigates first.

Examples:

- Phase 3 byte-equality mismatch → halt; tell user to investigate `bundle_verification.log`.
- Phase 3 `git bundle list-heads` round-trip mismatch → halt; the bundle is malformed; re-run Phase 3 from scratch.
- Phase 10 list-shift detected (a worktree's branch field doesn't match `worktrees.tsv`) → halt; tell user a concurrent agent may have changed the worktree list.
- Phase 8 apply succeeds but `cargo test` fails AND the failure isn't a known pre-existing one → halt; surface the test output; ask user direction.
- Phase 10 worktree refuses removal AND user has not OK'd `--force` → halt; surface to user.

The skill always errs toward not-doing, not toward proceeding-and-hoping.

---

## Concurrent-Agent Safety

Per AGENTS.md "Note for Codex/GPT-5.5":

> "you NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents. Just treat those changes identically to changes that you yourself made."

The skill's discipline:

- **Phase 0** snapshots every worktree's status into `wt_phase0.txt`.
- **Phase 8** re-snapshots every active worktree before each apply (`↺ WORKING-TREE-DRIFT`).
- If new files / changes appear that this run did not author: they are concurrent agents' work; treat as if you authored them; never stash, revert, or overwrite.
- The skill never runs `git checkout -- .`, `git clean -fd`, `git reset --hard`, `git stash`, or any other working-tree-mutating command outside the explicit Phase 8 apply path.

> **Why:** [SKILL.md Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Concurrent agents' working-tree changes in any worktree are normal. Snapshot once at Phase 0; re-snapshot before each destructive operation; never stash, revert, or overwrite a parallel agent's work. Do not surprise the user with prompts about drift you didn't cause."

---

## Order-of-Cleanup Safety

Phase 10 enforces a strict ordering: **worktrees first, branches second**. Within branches: **garbage → superseded → already-merged → novel-stale → divergent-refactor (opt-in) → applied-keepers**.

> **Why:** [SKILL.md Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms) — "A worktree pinned to a branch protects that branch from `git branch -d` (the branch is 'checked out' elsewhere). Removing the worktree first frees the branch."

If the order is violated:

- `git branch -d <name>` will refuse if a worktree still has `<name>` checked out. Good — built-in safety check.
- The user might force `git branch -D <name>` and lose the branch's `refs/heads/` entry while a worktree still pins the same SHA via its checkout. The branch's content is still recoverable from the backup ref + bundle, but the worktree is now in a "headless" state until pruned.

The skill never violates the order. The cleanup plan groups by phase (A through G) and refuses to begin Phase B (branch deletion) until Phase A (worktree removal + prune) completes.

---

## Remote Cleanup Out of Scope

The skill never runs `git push --delete`, `git push --force`, `git push --force-with-lease`, or any remote-mutating command.

> **Why:** [SKILL.md Axiom 15](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Remote cleanup is out of scope by default. The skill never runs `git push --delete`, `git push --force`, or any remote-mutating command. Remote tracking refs are advisory inputs, not targets."

If the user opts in via `--prepare-remote-list`, the skill emits a list of `git push --delete origin <branch>` commands the user runs themselves. The skill at most prepares the list; the user is the one who runs it.

This is because remote operations are reversible only via remote reflog access (which the user usually doesn't have on a SaaS git host), so the safety story breaks down for remote refs.
