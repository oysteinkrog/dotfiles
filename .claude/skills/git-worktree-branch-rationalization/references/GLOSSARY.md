# Glossary

Terms used by the skill, with their precise meanings. When in doubt, defer to this file.

Adapted from [git-stash-janitor's GLOSSARY.md](../../git-stash-janitor/references/GLOSSARY.md). Many terms are shared (bundle, backup ref, kernel); the new and renamed terms reflect this skill's branch-and-worktree-specific concerns.

---

## A

**Accretive** — Of a recovered keeper, one that strictly adds capability without breaking, removing, or contradicting any existing functionality. The opposite is *destructive* (which the skill never auto-applies).

**Already-merged** — A verdict for branches whose every commit is on canonical (whether by SHA-equivalence OR patch-id-equivalence per `git cherry -v`). Disposition: skip in Phase 8; `git branch -d` in Phase 10. See [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts).

**Apply-check** — `git cherry-pick --no-commit -X theirs <sha>` on a throwaway branch from canonical's tip — a dry-run that returns 0 if the branch's content would apply cleanly, non-zero otherwise. Used in Phase 5 (probe) and Phase 8 (gate before actual apply). Distinct from stash-janitor's `git apply --3way --check`; for branches we use cherry-pick because branches are commit chains, not single diffs.

**Applied-keeper** — A branch (or worktree) that produced a commit on the rationalization branch in Phase 8. Its content is now on the rationalization branch AND in the backup ref AND in the bundle; it can be deleted in Phase 10's Phase G bucket without losing content. See [PHASES.md Phase 10](PHASES.md#phase-10-destructive-cleanup-gated).

**Applied-keeper-elsewhere** — A *forensic-finding label* (NOT a peer of the canonical 11 verdicts), attached to a `superseded` row when reflog evidence shows the branch was the SOURCE of content now on canonical (e.g., the canonical commits were squash-merged or cherry-picked from this branch), not a duplicate of it. Recorded in the evidence column or `apply_log.tsv` row so attribution stays correct even though the cleanup decision is still "drop the branch." Detected by `subagents/reflog-archaeologist.md`. The verdict remains `superseded`; the label is metadata.

**Archaeology-then-rewrite** — A meta-strategy emitted by the `archaeologist` subagent in Phase 5 for `novel-but-stale` rows that need forensic intent reconstruction before any apply. The keeper-applier does NOT auto-apply this strategy: the archaeologist surfaces a recommendation to the user, who either (a) accepts — the strategy is rewritten to `cherry-pick` or `harmonized-synthesis` and the keeper-applier handles it on the next pass — or (b) drops — the strategy is rewritten to `none` and the branch is deleted in Phase 10. See [`subagents/keeper-applier.md` § Choose strategy](../subagents/keeper-applier.md).

**Authorization phrase** — The verbatim text the user types to approve a destructive phase. Includes a literal command from the proposed plan. Recorded in `cleanup_authorization.txt`. Per [SKILL.md Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms).

---

## B

**Backup ref** — `refs/branch-rationalization-backup/<slug>`. A permanent ref inside `.git/refs/` that points at the branch's tip SHA at run-start. Layer 1 of the recovery chain. Survives `git branch -D` and `git gc --prune=now`. Created in Phase 3 by `scripts/build-bundle.sh`.

**Beads** — Local-first issue tracker (`br` CLI). The skill files a beads issue at run start and closes it at handoff.

**Branch slug** — A filesystem-safe encoding of a branch name (e.g., `feature/length-cap` → `feature-length-cap`). Used as directory names in the bundle (`<bundle>/branches/<slug>/...`) and as the per-branch backup-ref name (`refs/branch-rationalization-backup/<slug>`). Slug-encoding rules: replace `/` with `-`, lowercase, strip non-alphanumeric except `-` and `_`.

**Bucket** — A verdict category in Phase 10 cleanup ordering. Removals happen bucket-by-bucket per the documented ordering in [PHASES.md Phase 10](PHASES.md#phase-10-destructive-cleanup-gated): worktrees first (Phase A), then branches in order garbage (B) → superseded (C) → already-merged (D) → novel-stale (E) → divergent-refactor opt-in (F) → applied-keepers (G).

**Bundle** — The recovery archive at `<project-parent>/<basename>-branch-worktree-archive-<DATE>/`. Contains backup refs (logically), per-branch diffs + format-patch series, per-worktree dirty-state captures, meta files, an `index.tsv`, and a README. Layer 2 of the recovery chain. Persistent (lives outside the repo); never deleted by the skill.

**Bundle round-trip** — A verification step in Phase 3 that confirms `git bundle list-heads <bundle>/object-bundle.pack` returns every backup ref expected. Per [SKILL.md Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Byte-equality** — A verification step in Phase 3 that confirms each backup ref's SHA matches the live branch's SHA at the moment of bundle creation. Per [SKILL.md Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms): "five reversibility layers must all reflect the same content."

---

## C

**Canonical** — The project's primary development branch, by whatever name (`main`, `master`, `develop`, `trunk`, `default`, `release/2.x`). Detected via `git symbolic-ref refs/remotes/origin/HEAD` first, then `git config init.defaultBranch`, then heuristic. **Never assumed.** Per [SKILL.md Axiom 5](../SKILL.md#the-rationalization-kernel-universal-axioms).

**CASS** — Cross-Agent Session Search. Used in Phase 0.5 to mine prior agent sessions for context, especially for orphan `agent-*` branches whose authors are no longer running.

**Cherry-pick** — `git cherry-pick <sha>` — replays a single commit's changes onto the current branch as a new commit. The `✧ CHERRY-PICK` operator's mechanism. Distinct from squash-merge and rebase-and-merge (the other Phase 8 strategies). See [OPERATOR-LIBRARY.md `✧ CHERRY-PICK`](OPERATOR-LIBRARY.md).

**Cherry-summary** — Output of `git cherry -v <canonical> <branch>`. Each line is one commit on the branch; `-` means patch-id-equivalent on canonical (already-merged), `+` means novel. The canonical "is this content already on canonical?" check per [SKILL.md Axiom 17](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Cleanup plan** — Phase 10's bucket-ordered list of `git worktree remove` and `git branch -d`/`-D` commands. Materialized BEFORE execution; presented to user verbatim before authorization. See [PHASES.md Phase 10](PHASES.md#phase-10-destructive-cleanup-gated).

**Conflict-context file** — `<workspace>/conflicts/branch_<slug>.context.md`. Surface diff plus the user-readable conflict explanation; written when Phase 8's apply requires manual conflict resolution. Cited in the resulting commit message per [COMMIT-MESSAGE-CRAFT.md §"Conflict-resolved commit"](COMMIT-MESSAGE-CRAFT.md#body-structure-conflict-resolved-commit).

---

## D

**DCG** — Destructive Command Guard. A hook that blocks `rm -rf`, `git reset --hard`, `git clean -fd`, etc. The skill is *designed not to need* DCG-blocked commands. Per [SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms): "`rm -rf <worktree-path>` is forbidden; `git worktree remove` is the structured operation."

**Delete-branch** — `git branch -d <name>` (preferred) or `git branch -D <name>` (only when explicitly authorized as unmerged-and-discardable). The `⊘ DELETE-BRANCH` operator. Per [SKILL.md Axiom 8](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git branch -d` over `git branch -D` whenever possible."

**Diff-vs-merge-base** — `git diff --binary <merge-base>..<branch>` for tracked-file changes in the recovery bundle. The per-branch human-readable backstop. Distinct from format-patch (which is per-commit and ordered).

**Dirty-worktree-only** — A verdict (one of the canonical 11) for worktrees where value lives only in uncommitted staged/unstaged/untracked work, not in any committed branch (the branch itself is `already-merged` or canonical, but the worktree pinned to it has dirty state worth recovering). Phase 8 strategy: apply `<bundle>/worktrees/<sanitized-path>/staged.diff`, then `unstaged.diff`, then extract `untracked.tar.gz` after collision check — three focused commits per Axiom 13. See [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts) and [WORKTREE-STATE.md](WORKTREE-STATE.md).

**Divergent-refactor** — A verdict for branches that intentionally take a different architectural direction (different signatures, different module organization). Default action: skip; opt-in to delete in Phase 10's Phase F bucket. Often a candidate input to harmonization when other branches collide on the same files. See [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts).

---

## F

**Fingerprint** — The set of identifiers introduced by a branch: function names, type names, test names, fixture file paths. Computed by `scripts/triage-batch.sh` from `git diff <merge-base>..<branch>`. Input to VERIFY-ON-CANONICAL. Language-specific patterns in [LANGUAGE-PROFILES.md](LANGUAGE-PROFILES.md). The `✦ FINGERPRINT` operator.

**Forensic-finding (label)** — Metadata attached to a triage row that records HOW a row reached its verdict, separate from the verdict itself. Examples: `applied-keeper-elsewhere` (this `superseded` branch was the SOURCE of canonical's content, not a duplicate), `force-pushed-recently` (the upstream was force-pushed mid-window — local branch may retain pre-push history), `cherry-picked-into-canonical` (reflog shows commits were lifted into a different branch that landed on canonical). Forensic-finding labels are NEVER peers of the canonical 11 verdicts in [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts) — they live in the evidence column or `apply_log.tsv`. The 11-verdict taxonomy stays closed.

**Force-remove** — `git worktree remove --force <path>` — bypasses the dirty-state-refusal that `git worktree remove <path>` enforces by default. Only used when the dirty state has been archived in the bundle AND the user has explicitly OK'd losing it. Per [SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Format-patch series** — `git format-patch <merge-base>..<branch>` produces one numbered patch per commit. Stored in `<bundle>/branches/<slug>/format-patch/0001-...patch`. Per [SKILL.md Axiom 7](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git format-patch` IS valid for branches; it is NOT for stashes." Patterned after the [Linux kernel patch-series convention](EXEMPLARS.md#ex-2--linux-kernels-git-format-patch-series-convention).

**Fresh-eyes** — Phase 9. Three review prompts × ≥2 rounds, each round increasing the depth of examination. The explicit termination gate before Phase 10 may run.

---

## G

**Garbage** — A verdict for branches whose name matches a known-noise prefix (`other-agent-broken`, `temp-pre-push`, etc.) AND whose content adds nothing novel; OR whose only diff is lockfile-style churn; OR whose content is a revert of still-needed commits. See [BRANCH-WORKTREE-SMELLS.md](BRANCH-WORKTREE-SMELLS.md) and [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts).

**Gate (Phase)** — A phase that must complete before the next can start. Phases 3 (byte-equality + bundle round-trip), 6 (user OK on triage), 7 (user OK on harmonization plan), 10 (verbatim authorization).

**Gates (quality)** — `test`, `typecheck`, `lint`, `ubs`. Run after every Phase 8 apply. Per [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms): "Per-apply gates are non-negotiable."

**`[gone]`-upstream** — Branch tracking state shown by `git branch -vv` when the upstream ref no longer exists on the remote. The branch may have unique commits the upstream never saw; triage normally, don't auto-prune. Per [SKILL.md "Failure Modes"](../SKILL.md#failure-modes-table--branch--worktree-footguns).

---

## H

**Handoff** — Phase 11. Final report + beads close + push instructions + recovery recipes. The skill never pushes.

**Harmonization** — The Phase 7 process of synthesizing the strongest current implementation of every contested file by inspecting every variant, identifying each piece's intent, and composing on top of canonical's architecture. The conceptual centerpiece of the skill. The `◇ HARMONIZE` operator. Per [SKILL.md Axiom 1](../SKILL.md#the-rationalization-kernel-universal-axioms): "Harmonize, don't pick." See [HARMONIZATION.md](HARMONIZATION.md).

**Harmonization plan** — `<workspace>/harmonization_plan.md`. The per-file variant matrix the user reviews BEFORE Phase 8 mutates anything. Each entry has a unique id (`§H-<N>`) cited from the resulting commit message.

**Harmonized-synthesis** — A Phase 8 apply *strategy* (NOT a verdict). When the harmonization plan calls for synthesis, the keeper-applier does NOT cherry-pick — it hand-authors a new commit on the rationalization branch using the **Edit** tool, following the variant matrix in `harmonization_plan.md` and citing source branches and `§H-<N>` ids in the commit message. Per AGENTS.md "No Script-Based Changes" — synthesis is manual Edit, never sed/awk/regex. See [`subagents/keeper-applier.md` § Choose strategy](../subagents/keeper-applier.md) and [HARMONIZATION.md § 6](HARMONIZATION.md).

---

## I

**Idempotent** — Re-running the skill on a clean repo (or on a previously-completed run) produces no new commits and reports "nothing to rationalize." Polish Bar dimension per [POLISH-BAR.md](POLISH-BAR.md).

**Index** (in inventory) — A row number in `branches.tsv` or `worktrees.tsv`. NOT a stable id (the same branch may end up on different rows across runs); the stable id is the branch slug or the worktree's sanitized path.

**Intent** (harmonization) — One of eight categories: `defensive` / `refactor` / `test` / `fixture` / `type-narrowing` / `error-handling` / `performance` / `naming`. Determines composition rules in the variant matrix. See [HARMONIZATION.md §"Intent taxonomy"](HARMONIZATION.md#3-intent-taxonomy).

**Inventory** — Phase 2. Two passes producing `worktrees.tsv` (one row per worktree) and `branches.tsv` (one row per local branch). The `★ INVENTORY` operator. Per [SKILL.md Axiom 0](../SKILL.md#the-rationalization-kernel-universal-axioms): "Two units of management, one safety story. Inventory each separately."

---

## K

**Keeper** — A branch or worktree classified as `novel-and-accretive`, `partially-novel`, or `dirty-worktree-only` that gets applied as a recovery commit (or set of commits) in Phase 8. Distinct from a *protected-preserve* (never enters the pipeline) and from `superseded`/`garbage` (skipped in Phase 8, deleted in Phase 10).

**Kernel** — The 19 universal axioms in [SKILL.md "THE RATIONALIZATION KERNEL"](../SKILL.md#the-rationalization-kernel-universal-axioms). Stress-test every decision against the kernel.

---

## L

**LFS** — Git Large File Storage. Branches containing LFS-tracked files have pointer text in the diff; recovery requires `git lfs fetch` to be functional against the LFS server. See [REPO-ARCHETYPES.md §A7](REPO-ARCHETYPES.md#a7--lfs-managed-binaries).

---

## M

**Merge-base** — `git merge-base <canonical> <branch>` — the most recent common ancestor commit. The starting point for `git diff <merge-base>..<branch>` and for the format-patch series. Captured per-branch in `<bundle>/branches/<slug>/meta.txt` (NOT in `branches.tsv` — `discover-branches-worktrees.sh` computes the merge-base internally for diffstats but does not persist it as a TSV column; if you need it post-Phase-3, read it from the bundle's per-slug `meta.txt`).

**Meta** — Per-branch or per-worktree metadata file at `<bundle>/branches/<slug>/meta.txt` or `<bundle>/worktrees/<sanitized-path>/meta.txt`. Contains head sha, merge-base, ahead/behind, locked/prunable flags, last-activity timestamp, original path (for worktrees), branch name (for worktrees).

**Mode (run)** — Quick / Standard / Comprehensive / Council. Determined by worktree count, branch count, and project complexity. See [SKILL.md "Decision Tree"](../SKILL.md#decision-tree--should-the-skill-run) and [SKILL.md "Mode Variants"](../SKILL.md#mode-variants).

---

## N

**Novel-and-accretive** — A verdict for branches whose introduced symbols don't appear on canonical AND whose apply-check is clean AND content is focused/defensive/test-only. The most common keeper verdict. See [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts).

**Novel-but-stale** — A verdict for branches whose introduced symbols don't appear on canonical BUT files referenced no longer exist OR apply-check fails on every hunk because canonical drifted. Default action: skip with note; the user may opt to recover after manual porting. See [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts).

**NTM** — Multi-agent tmux orchestration tool. **Optional** — used only when the user is already running NTM panes; the skill's default execution is single-session with parallel Task subagents. See [SKILL.md "Parallelism Model"](../SKILL.md#parallelism-model).

---

## O

**Object bundle** — `<bundle>/object-bundle.pack`, output of `git bundle create --all` over the backup-ref namespace. Self-contained pack file that can be `git fetch`-ed back into a fresh repo to restore every backup ref. Layer 2's authoritative artifact.

**Operator** — A reusable cognitive move with explicit triggers, prompt module, and exit criteria. The skill has 18 operators (★ 🔒 🌳 ✦ ◐ ⬡ ⚠ ◇ ✧ ⊟ ⊠ ⇄ ⊕ ⊞ ↺ ⊙ ⊘ ⌘). Listed in [SKILL.md "Operator Library"](../SKILL.md#operator-library--the-cognitive-moves); full cards in [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md).

**Orchestration tier** — Solo / Pair / Squad / Swarm / Council. Determined by branch+worktree count + stakes. Higher tiers consume more compute but produce stronger triage. See [SKILL.md "Parallelism Model"](../SKILL.md#parallelism-model).

---

## P

**Partially-novel** — A verdict for branches where some commits/hunks are on canonical (patch-id-equivalent) but others are not. Phase 8b split-applies the novel subset. See [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts).

**Phase gate** — See "Gate (Phase)".

**Polish Bar** — The 10 dimensions a successful run must satisfy (recovery completeness, verdict evidence, no phantom keepers, harmonization fidelity, per-apply gates, focused commit messages, order of cleanup, verbatim authorization, idempotent on clean repo, resumable). Enforced by `scripts/polish-bar-check.sh`. See [POLISH-BAR.md](POLISH-BAR.md).

**Protected-preserve** — A verdict (and disposition) for branches/worktrees the user has flagged as keep-forever. Auto-protected categories (canonical, currently-checked-out, `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`) plus user-flagged additions. Never enters the rationalization pipeline. The `🔒 PROTECT` operator.

**Prune-worktree** — `git worktree remove <path>` — the structured operation that removes a worktree directory and prunes its admin metadata at `.git/worktrees/<id>/`. The `⊙ PRUNE-WORKTREE` operator. Per [SKILL.md Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms): worktrees removed first, branches second.

---

## R

**Rationalization branch** — `branch-rationalization-<YYYY-MM-DD>` (default name). The branch where Phase 8 keepers land. Created off canonical's tip; never merged by the skill. The user merges, cherry-picks, or pushes from there at their own pace. Per [SKILL.md Axiom 6](../SKILL.md#the-rationalization-kernel-universal-axioms): "Land on a rationalization branch, not on canonical."

**Rebase-and-merge** — `git rebase <branch> --onto <rationalization-branch>` — replays the branch's commits onto the rationalization-branch tip without mutating the source branch. The `⊠ REBASE-AND-MERGE` operator. Used when the project's `merge_style` is rebase-and-merge.

**Re-fingerprint** — `⊞ RE-FINGERPRINT`. After every successful Phase 8 apply, re-run FINGERPRINT/VERIFY-ON-CANONICAL on downstream keep candidates; some now flip to `superseded` because the just-applied keeper put their content on canonical.

**Reflog** — `git reflog`. The chronological history of ref movements. Used in [TIMELINE-RECONSTRUCTION.md](TIMELINE-RECONSTRUCTION.md) for forensic intent reconstruction. Default expiry: 90 days reachable, 30 days unreachable. Backup refs survive expiry; the reflog itself doesn't.

**Resumable** — A run interrupted mid-phase can be resumed. Phase 8 reads `apply_log.tsv` and skips already-applied keepers. Polish Bar dimension per [POLISH-BAR.md](POLISH-BAR.md).

---

## S

**Same-name on canonical** — A function or type with the same name as one introduced by a branch but with potentially different signatures. Per [SKILL.md Axiom 16](../SKILL.md#the-rationalization-kernel-universal-axioms): "Same-name on canonical is not always supersession" — sample signatures before classifying.

**Same-signature** — A check that an introduced symbol on canonical has the SAME parameter list and return type as the branch's version. Required citation form (Form G per [EVIDENCE-CITATIONS.md](EVIDENCE-CITATIONS.md#form-g-same-signature-validates-superseded)) for `superseded` verdicts.

**Sequential (Phase 8)** — Each apply changes the 3-way base for later applies and can flip downstream verdicts via `⊞ RE-FINGERPRINT`. Single applier worker; never parallel.

**Slug** — See "Branch slug".

**Split-apply** — Phase 8b. For partially-novel branches, cherry-pick only the novel subset of commits. The `⇄ SPLIT-COMMITS-HUNKS` operator.

**Squash-merge** — `git merge --squash <branch>` followed by one focused commit. The `⊟ SQUASH-MERGE` operator. Used when the project's `merge_style` is squash-merge.

**Stale-locked worktree** — A worktree marked `locked` in `git worktree list --porcelain` but whose lock-reason is empty or stale. Often a leftover from a debug session. Don't auto-remove; surface to user.

**Superseded** — A verdict for branches whose introduced symbols already exist on canonical with same signatures (validated via FINGERPRINT + VERIFY-ON-CANONICAL + same-signature sample). Default action: skip in Phase 8; `git branch -d` if fully merged into rationalization branch (else `-D`) in Phase 10's Phase C bucket. See [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts).

**Superseded-by-newer-branch** — Same-family supersession: when 5+ branches share the same name-prefix family (e.g., `agent-cc-*-feat-parser-v*`, `wip-BACK-1742-attempt-N`), only the most recent has any chance of being canonical; the rest get `superseded-by-newer-branch` (a sub-shape of the canonical `superseded` verdict) with high confidence (0.92+ on the asupersync corpus). Detected pre-fingerprinting by `scripts/prefix-classifier.sh` after grouping in `inventory_grouped.md`. See [BRANCH-WORKTREE-SMELLS.md](BRANCH-WORKTREE-SMELLS.md), [FAILURE-MODES.md](FAILURE-MODES.md), and [KEY-INSIGHTS.md §I-11](KEY-INSIGHTS.md).

**Synthesis intent categories** — The eight intent categories used in the harmonization variant matrix: `defensive`, `refactor`, `test`, `fixture`, `type-narrowing`, `error-handling`, `performance`, `naming`. Each has different composition rules. See [HARMONIZATION.md §"Intent taxonomy"](HARMONIZATION.md#3-intent-taxonomy).

---

## T

**Tier** — See "Orchestration tier".

**Triage** — Phase 5. Classify each non-protected branch and each non-clean worktree into one of the 11 verdicts: `canonical`, `protected-preserve`, `already-merged`, `superseded`, `novel-and-accretive`, `partially-novel`, `novel-but-stale`, `divergent-refactor`, `dirty-worktree-only`, `garbage`, `unknown`.

**Triangulation** — Multi-model independent triage (Claude + Codex + Gemini, or any subset). Same prompt, different models. Intersection is high-confidence; disagreement surfaces to user. Required for Council mode.

**Trunk** — A canonical-branch name used by some workflows. Detected like any canonical branch.

---

## U

**UBS** — Ultimate Bug Scanner. A project-specific static analyzer that runs on changed files. Optional gate.

**Unknown** (verdict) — A branch the rubric couldn't classify with confidence ≥ 0.7. Forces user surface in Phase 6. See [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts).

---

## V

**Variant matrix** — The per-file table in `harmonization_plan.md` that lists every variant (canonical + each branch + each dirty worktree) of a contested file with its signatures, hunks, intent, and proposed synthesis. See [HARMONIZATION.md §"The variant matrix structure"](HARMONIZATION.md#2-the-variant-matrix-structure).

**Verbatim** — Word-for-word, no paraphrase. Authorization phrases must include verbatim commands. Operator prompt modules are used verbatim. Per AGENTS.md "Mandatory explicit plan."

**Verdict** — The classification of a branch or worktree. One of 11: `canonical`, `protected-preserve`, `already-merged`, `superseded`, `novel-and-accretive`, `partially-novel`, `novel-but-stale`, `divergent-refactor`, `dirty-worktree-only`, `garbage`, `unknown`. See [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts).

**Verify-on-canonical** — `◐ VERIFY-ON-CANONICAL`. For each fingerprint symbol, search canonical via `git grep` or `ast-grep`. Compute fingerprint coverage. The second step in the FINGERPRINT → VERIFY chain that produces evidence for the verdict.

---

## W

**Working tree** — The actual files on disk in a worktree's directory (vs. the index or HEAD). Snapshotted at Phase 0 for every worktree, re-snapshotted before each Phase 8 apply (per Axiom 12).

**Working-tree drift** — Changes that appear in any worktree's working tree from concurrent agents during the run. Per [AGENTS.md "Note for Codex/GPT-5.5"](../../../../AGENTS.md), treat as if the agent committed them; never stash, revert, or overwrite.

**Worktree** — A `git worktree` — a separate working directory pinned to a branch (or detached HEAD), with admin metadata at `.git/worktrees/<id>/`. Distinct unit of management from a branch. Per [SKILL.md Axiom 0](../SKILL.md#the-rationalization-kernel-universal-axioms): "Two units of management, one safety story."

---

## Y

**Yield** — The fraction of triaged entries (branches + worktrees) that produce keeper commits. Healthy: 1%–10%. Higher means the project's branches were genuinely additive; lower means the swarm is exploration-heavy and most branches were experimental dead-ends.
