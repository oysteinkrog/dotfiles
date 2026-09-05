# Glossary

Terms used by the skill, with their precise meanings. When in doubt, defer to this file.

---

## A

**Accretive** — Of a recovered keeper, one that strictly adds capability without breaking, removing, or contradicting any existing functionality. The opposite is *destructive* (which the skill never auto-applies).

**Apply-check** — `git apply --3way --check <diff>` — a dry-run that returns 0 if the patch would apply cleanly, non-zero otherwise. Used in Phase 4 (probe) and Phase 6 (gate before actual apply).

**Archaeologist (subagent)** — Subagent for `novel-but-stale` rows that need historical reconstruction (file no longer exists; refactor moved everything around).

**Authorization phrase** — The verbatim text the user types to approve a destructive phase. Includes a literal command from the proposed plan. Recorded in `cleanup_authorization.txt`.

---

## B

**Backup ref** — `refs/stash-backup/<NNN>`. A permanent ref inside `.git/refs/` that points at the stash's commit SHA. Layer 1 of the recovery chain. Survives `git stash drop` and `git gc`.

**Beads** — Local-first issue tracker (`br` CLI). The skill files a beads issue at run start and closes it at handoff.

**Bucket** — A verdict category in Phase 9 cleanup ordering. Drops happen bucket-by-bucket: `garbage` → `superseded` / `superseded-by-newer-stash` → `novel-but-stale` → `applied-keeper`.

**Bundle** — The recovery archive at `<project-parent>/<basename>-stash-archive-<DATE>/`. Contains backup refs (logically), per-stash diffs, meta files, optional untracked-files dirs, an index TSV, and a README. Layer 2 of the recovery chain.

---

## C

**CASS** — Cross-Agent Session Search. Used in Phase 0.5 to mine prior agent sessions for context.

**Cleanup plan** — Phase 9's `cleanup_plan.tsv`. Materialized BEFORE execution. Bucket-ordered, descending-by-`n` within each bucket.

**Conflict-skipped** — A keeper whose Phase 6 apply-check failed and the user chose not to manually resolve. Marked in `apply_log.tsv:gates_status`.

---

## D

**DCG** — Destructive Command Guard. A hook that blocks `rm -rf`, `git reset --hard`, `git clean -fd`, etc. The skill is *designed not to need* DCG-blocked commands.

**Diff** (in this skill) — Output of `git stash show -p --binary <inventory-sha>` for tracked/index changes in the recovery bundle. NOT `git format-patch`. Untracked files are not part of this diff; they live under `stashed-untracked/<NNN>/`.

**Drop** — `git stash drop stash@{N}`. Removes a stash from the live stash log. The backup ref at `refs/stash-backup/<NNN>` is unaffected.

---

## F

**Fingerprint** — The set of identifiers introduced by a stash: function names, type names, test names, fixture strings, file paths. Computed by `triage-batch.sh` from the bundle's diff. Input to VERIFY-ON-MAIN.

**Format-patch** — `git format-patch`. The CANONICAL FOOTGUN. `git format-patch -1 stash@{N}` is not the stash recovery diff and can be empty or wrong for stash merge commits. Use `git stash show -p --binary` for tracked/index changes and the stash commit's third parent for untracked files.

**Forensic mode** — A reading stance where the agent reconstructs the developer's intent from the diff + reflog + surrounding history.

**Fresh-eyes** — Phase 8. Three review prompts × ≥2 rounds, each round increasing the depth of examination.

---

## G

**Gate** (Phase) — A phase that must complete before the next can start. Phase 3 (byte-equality), Phase 5 (user OK), Phase 9 (verbatim authorization).

**Gates** (quality) — `test`, `typecheck`, `lint`, `ubs`. Run after every Phase 6 / Phase 7 apply.

**Garbage** — A verdict for stashes whose message matches a known-noise prefix (`other-agent-broken`, `temp-pre-push`, etc.) AND whose content adds nothing novel.

---

## H

**Handoff** — Phase 10. Final report + beads close + push instructions. The skill never pushes.

**Hijacked apply** — When `git stash pop` mid-conflict leaves the working tree dirty AND the stash still in the list AND no clean recovery path. Avoided by NEVER using `git stash pop`/`apply`.

---

## I

**Idempotent** — Re-running the skill on a clean repo (or on a previously-completed run) produces no new commits and reports "nothing to do". Polish Bar P8.

**Index** (stash list) — The position of a stash in `git stash list`. NOT a stable id. Shifts after every drop.

**Index commit** (git internals) — The second parent of a stash commit. Captures what was staged at stash time. The stash commit's first parent is the original HEAD.

---

## K

**Keeper** — A stash classified as `novel-and-accretive` that gets applied as a recovery commit in Phase 6.

**Kernel** — The 14 universal axioms in SKILL.md. Stress-test every decision against the kernel.

---

## L

**LFS** — Git Large File Storage. Stashes containing LFS-tracked files have pointer text in the diff; recovery requires `git lfs fetch` to be functional.

---

## M

**Meta** — Per-stash metadata file at `<bundle>/meta/<NNN>.txt`. Contains sha, parent_sha, date, author, has_untracked flag, and the stash message.

**Mode** (run) — Quick / Standard / Comprehensive. Determined by stash count and project complexity.

**Mode** (reading) — Literal / Skeptical / Junior / Expert / Adversarial / Forensic / Timeline. A deliberate reading stance for triage or review.

---

## N

**Novel-and-accretive** — A verdict for stashes whose fingerprint doesn't appear on the primary branch AND whose apply-check is clean AND content is focused/defensive/test-only.

**Novel-but-stale** — A verdict for stashes whose fingerprint doesn't appear on primary BUT files referenced no longer exist OR apply-check fails on every hunk because context drifted.

**NTM** — Multi-agent tmux orchestration tool. **Optional** — used only when the user is already running NTM panes; the skill's default execution is single-session with parallel Task subagents. See ORCHESTRATION.md § "Default Execution Model".

---

## O

**Operator** — A reusable cognitive move with explicit triggers, prompt module, and exit criteria. The skill has 12 operators (★ ✦ ◐ ⬡ ⚠ ✧ ⇄ ⊕ ⊙ ⌘ ⊞ ↺).

**Orchestration tier** — Solo / Pair / Squad / Swarm / Council. Determined by stash count + stakes. Higher tiers consume more compute but produce stronger triage.

---

## P

**Partially-novel** — A verdict for stashes where some hunks are superseded but others are novel. Phase 7 split-applies the novel hunks only.

**Phase gate** — See "Gate (Phase)".

**Polish Bar** — The 10 dimensions a successful run must satisfy (recovery completeness, verdict evidence, no phantom keepers, etc.). Enforced by `polish-bar-check.sh`.

**Primary branch** — The project's "main" branch, by whatever name (`main`, `master`, `develop`, `trunk`, `default`). Detected, never assumed.

---

## R

**Recovery branch** — `stash-recovery-<DATE>`. The branch where Phase 6 / Phase 7 keepers land. Created off the primary; never merged by the skill.

**Reflog** — `git reflog`. The chronological history of ref movements. Used in Forensic and Timeline reading stances.

**Resumable** — A run interrupted mid-phase can be resumed. Phase 6 reads `apply_log.tsv` and skips already-applied stashes.

---

## S

**Sequential** (Phase 6) — Each apply changes the 3-way base for later applies. Single worker only.

**Same-signature** — A check that an introduced symbol on main has the SAME parameter list and return type as the stash's version. If 30%+ of sampled symbols disagree, the verdict is forced away from `superseded`.

**Split-apply** — Phase 7. Create a split copy of the diff to keep only novel hunks; apply the smaller diff.

**Stash** — `git stash push` creates a 2-or-3-parent merge commit capturing working-tree + index state. The stash log is a stack of these commits.

**Stash family** — A group of stashes sharing a common message-prefix pattern (e.g., `wip-BACK-1742-*`). Often represents many parallel attempts at the same task.

**Stash smell** — A recognizable category of stash (wip-ticket / autostash / other-agent-broken / etc.) with default-verdict implications.

**Superseded** — A verdict for stashes whose introduced symbols already exist on the primary branch with same signatures. Default action: drop after Phase 9 authorization.

**Superseded-by-newer-stash** — A verdict for stashes whose fingerprint is duplicated by a more recent stash within the same family.

**Swarm** — A multi-agent topology with 8–12+ workers. By default, implemented via parallel Task-tool subagents in a single Claude Code session; can optionally use NTM panes if the user already runs that.

---

## T

**Tier** — See "Orchestration tier".

**Triage** — Phase 4. Classify each stash into one of the 6 verdicts.

**Triangulation** — Multi-model independent triage. Same prompt, different models (Claude + Codex + Gemini). Intersection is high-confidence; disagreement surfaces to user.

**Trunk** — A primary-branch name used by some workflows. Detected like any primary branch.

---

## U

**UBS** — Ultimate Bug Scanner. A project-specific static analyzer that runs on changed files. Optional gate.

**Unknown** (verdict) — A stash the rubric couldn't classify with confidence ≥ 0.7. Forces user surface in Phase 5.

**Untracked-files** — Stashes made with `git stash -u` capture untracked files in a third-parent commit. The bundle materializes these in `stashed-untracked/<NNN>/`.

---

## V

**Verbatim** — Word-for-word, no paraphrase. Authorization phrases must include verbatim commands. Operator prompt modules are used verbatim.

**Verdict** — The classification of a stash: `superseded` | `garbage` | `novel-and-accretive` | `partially-novel` | `novel-but-stale` | `unknown`.

**VERIFY-ON-MAIN** (operator ◐) — For each fingerprint symbol, search the primary branch. Compute fingerprint coverage.

---

## W

**Working tree** — The actual files on disk in the project directory (vs. the index or HEAD). Snapshotted before each Phase 6 apply.

**Working-tree drift** — Changes that appear in the working tree from concurrent agents during the run. Per AGENTS.md, treat as if the agent committed them.

**Worktree** — `git worktree`. A separate working directory for the same repo. Stashes are repo-wide, not per-worktree.

---

## Y

**Yield** — The fraction of triaged stashes that produce keeper commits. Healthy: 0.5%–10%. Higher means a project where stashes aren't routinely abandoned; lower means the agent swarm is exploration-heavy.
