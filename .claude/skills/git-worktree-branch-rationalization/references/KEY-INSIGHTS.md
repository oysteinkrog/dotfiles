# Key Insights — The Quote Bank

Distilled wisdom from the asupersync 47-worktree+213-branch session, related git-internals docs, AGENTS.md, the cass-mined sessions where the user manually rationalized branches and worktrees, and the broader corpus of agentic git workflows. Each entry is a quotable, transferable insight that future runs can stand on.

Following the operationalizing-expertise pattern: the goal is *quotable invariants*, not paraphrase. When a worker is unsure about an edge case, they should be able to find the relevant quote and apply it directly.

Adapted from [git-stash-janitor's KEY-INSIGHTS.md](../../git-stash-janitor/references/KEY-INSIGHTS.md), with the 19 axioms restated verbatim plus distilled insights specific to branch-and-worktree work.

---

## §I-1 — On the bundle as the irreversibility boundary

> "The bundle is the only thing standing between the user and lost work — treat it like radiation shielding."

**Source:** [OPERATOR-LIBRARY.md § ⬡ BUNDLE](OPERATOR-LIBRARY.md), adapted from [git-stash-janitor §I-1](../../git-stash-janitor/references/KEY-INSIGHTS.md).

**Application:** Phase 3 verification is a hard gate. Don't sample — verify every entry. The cost of a per-entry byte-equality check is microseconds; the cost of a wrong bundle is irrecoverable work AND the user's trust.

---

## §I-2 — On the format-patch / stash-show distinction

> "`git format-patch` IS valid for branches; it is NOT for stashes. A branch is a normal commit chain — `git format-patch <merge-base>..<branch>` produces a clean ordered series. Don't import the stash-janitor 'format-patch is wrong' rule."

**Source:** [SKILL.md Axiom 7](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Application:** every Phase 3 bundle includes per-branch format-patch series at `<bundle>/branches/<slug>/format-patch/`. The bundle's README explicitly cross-links this so a future reader who came from git-stash-janitor doesn't reach the wrong conclusion. Recovery via `git am <bundle>/branches/<slug>/format-patch/*.patch` is supported and documented.

---

## §I-3 — On working-tree drift

> "Treat changes that appeared during the run as if you committed them yourself."

**Source:** [AGENTS.md "Note for Codex/GPT-5.5"](../../../../AGENTS.md). [SKILL.md Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Application:** never stash, revert, or overwrite concurrent agents' work in any worktree. If the apply conflicts with concurrent changes, surface — don't auto-resolve. Re-snapshot via `↺ WORKING-TREE-DRIFT` before each Phase 8 apply. The 3-way merge handles context drift; user/coordinator handles intent collision. Per the cass-mined sessions: "agents kept modifying files while I was working" is the most common friction point — treating drift as expected (not exceptional) is the only sustainable response.

---

## §I-4 — On supersession evidence

> "Same-name on canonical is not always supersession. A function `redact_secrets` on a branch and on canonical may have different signatures or different defensive checks. Sample same-signature on at least 3 introduced symbols. When ≥30% of sampled signatures diverge, flip the verdict to `divergent-refactor`."

**Source:** [SKILL.md Axiom 16](../SKILL.md#the-rationalization-kernel-universal-axioms). [TRIAGE-RUBRIC.md § Same-signature verification](TRIAGE-RUBRIC.md).

**Application:** the asupersync run's `lock_until(Instant)` vs. canonical's `lock_until(Duration)` is the canonical example. Same name, different semantics, NOT superseded. The Literal stance alone misses this; per [MODES-OF-REASONING.md § Worked Example](MODES-OF-REASONING.md#worked-example--the-same-diff-through-all-four-stances), Skeptical catches it.

---

## §I-5 — On worktree-first cleanup ordering

> "Worktrees are removed first, branches second. A worktree pinned to a branch protects that branch from `git branch -d`."

**Source:** [SKILL.md Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms). Pro Git §7.

**Application:** the Phase 10 cleanup plan groups commands as `Phase A — Worktree removal` (with `git worktree prune` as the final step of bucket A to clean residual `.git/worktrees/<id>/` admin metadata), then `Phase B–G — Branch deletion` in bucket order. Mixing the order produces `git branch -d` refusals.

---

## §I-6 — On the verbatim authorization

> "Without `cleanup_authorization.txt` containing the user's exact phrase, the action did not happen."

**Source:** [SKILL.md Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms). [AGENTS.md "Document the confirmation"](../../../../AGENTS.md).

**Application:** "yes" is too vague. "yes I understand and want to remove 44 worktrees and delete 181 branches per the plan above" is the minimum. Re-ask if the user types something shorter. The cleanup_authorization.txt is the audit trail; no audit trail = no authorization (per [INCIDENT-PLAYBOOK.md I12](INCIDENT-PLAYBOOK.md#i12)).

---

## §I-7 — On phase-8 sequencing

> "Each apply changes the 3-way base for later applies. Sequential by definition. Re-fingerprint downstream candidates between applies — some flip to `superseded` after their content lands."

**Source:** [OPERATOR-LIBRARY.md § ⊞ RE-FINGERPRINT](OPERATOR-LIBRARY.md). [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Application:** never apply two keepers that introduce the same fingerprint in parallel. Phase 8 is strictly serial. The first lands; the second now sees its content on the rationalization branch's tip; verdict flips automatically when re-fingerprinted.

---

## §I-8 — On compounding error in recovery

> "Per-apply gates aren't paranoid. Compounding errors across recoveries are an order of magnitude harder to debug than per-keeper failures. Pay the cost upfront."

**Source:** [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms). [OPERATOR-LIBRARY.md § ⊕ RECOVER](OPERATOR-LIBRARY.md).

**Application:** test + typecheck + lint + UBS after EVERY apply. `apply_log.tsv:gates_status` proves it. If any gate fails, revert the apply and surface — don't proceed to the next keeper.

---

## §I-9 — On designing around DCG

> "DCG blocks `rm -rf`. The skill is designed never to need it. Bundle lifecycle is the user's responsibility."

**Source:** [SKILL.md Axiom 18](../SKILL.md#the-rationalization-kernel-universal-axioms). [ANTI-PATTERNS.md W2](ANTI-PATTERNS.md#w2-rm--rf-worktree-path-instead-of-git-worktree-remove).

**Application:** when DCG blocks something, the skill takes that as evidence the design is correct, not as a problem to bypass. The bundle stays in place at end of run. `rm -rf <worktree-path>` is never the answer; `git worktree remove` is. Per [INCIDENT-PLAYBOOK.md I8](INCIDENT-PLAYBOOK.md#i8) for the disk-full case where DCG blocks even bundle-cleanup attempts.

---

## §I-10 — On the five-layer reversibility chain

> "Backup ref + object bundle + per-branch diff + per-branch format-patch + per-worktree dirty captures = five layers. The backup ref and bundle content are the restorable layers; meta and index make that recovery auditable. ALL five must be lost before a single removal becomes hard to recover."

**Source:** [SKILL.md Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms). [SAFETY-MODEL.md](SAFETY-MODEL.md).

**Application:** the skill never deletes any of the five layers. Any operation that would touch one is independent of the others. `git branch -D` only affects the live branch ref, not backup refs. `git worktree remove` only affects the worktree directory, not the captured dirty state.

---

## §I-11 — On branch families and supersession-by-newer

> "When 5+ branches share the same fingerprint family (e.g., `agent-cc-*-feat-parser-v*` or `wip-BACK-1742-*`), only the most recent has any chance of being canonical. Treat the rest as `superseded-by-newer-branch`."

**Source:** [BRANCH-WORKTREE-SMELLS.md Smell 1](BRANCH-WORKTREE-SMELLS.md). The asupersync session's 89 of 94 `wip-BACK-*` branches were superseded by newer branches in the same ticket family.

**Application:** before fingerprinting, group branches by name-prefix family in `inventory_grouped.md`. Within a family, sort by branch tip date desc; only the head needs full triage. The tail get `superseded-by-newer-branch` with high confidence (0.92+ unanimous on the asupersync corpus).

---

## §I-12 — On `git cherry-pick --no-commit` over `git cherry-pick`

> "`git cherry-pick` mutates state directly AND auto-commits on success. On conflict, the working tree is half-applied AND the cherry-pick is in-progress. `git cherry-pick --no-commit` stages without committing — easier to inspect, easier to abort, gates can run before commit."

**Source:** [OPERATOR-LIBRARY.md § ✧ CHERRY-PICK](OPERATOR-LIBRARY.md). The asupersync session.

**Application:** Phase 8's cherry-pick strategy uses `--no-commit` so the gates can run on the staged result before the commit lands. On clean apply, commit explicitly. On conflict, `git cherry-pick --abort` returns the working tree to clean.

---

## §I-13 — On the rationalization branch as isolation

> "Keepers land on `branch-rationalization-<DATE>`, not on canonical. The user reviews and merges. If every gate passed wrong, the user can explicitly decide to discard the rationalization branch."

**Source:** [SKILL.md Axiom 6](../SKILL.md#the-rationalization-kernel-universal-axioms). [ANTI-PATTERNS.md W5](ANTI-PATTERNS.md#w5-landing-keeper-commits-directly-on-canonical-instead-of-the-rationalization-branch).

**Application:** the rationalization branch is the run's blast-radius limit. Never push it. Never merge it from the skill. The user owns the merge decision. Per Axiom 6: "Landing 200 branches' worth of recovered content directly on canonical in one shot is exactly the kind of mass mutation that should never happen without human review."

---

## §I-14 — On the sound of silence

> "If `cleanup_log.tsv` doesn't exist, no cleanup happened — regardless of what the agent said in conversation. The artifact is the source of truth."

**Source:** [POLISH-BAR.md P10](POLISH-BAR.md). Adapted from [git-stash-janitor §I-14](../../git-stash-janitor/references/KEY-INSIGHTS.md).

**Application:** every claim in the handoff report must be backed by a workspace artifact. Counts come from `.tsv` files, not from agent memory. Phase 12 audits cross-check this. The skill cannot say "we deleted 181 branches" unless `cleanup_log.tsv` has 181 rows with verifiable timestamps.

---

## §I-15 — On the user's mistake (the motivating session)

> "The user thought `*47` in their zsh prompt meant 47 commits ahead of origin. It was 47 worktrees. Many users genuinely don't know how many worktrees they have, and `git worktree list | wc -l` is the most important Phase 0 output."

**Source:** The asupersync session. [WORKED-EXAMPLES.md](WORKED-EXAMPLES.md).

**Application:** Phase 0 reports `git worktree list | wc -l` AND `git branch | wc -l` to the user *before* asking them to commit time. The number itself is often the most important Phase 0 output — users frequently don't realize they have 47 worktrees and 213 branches until the skill tells them.

---

## §I-16 — On verdict surfacing

> "Confidence < 0.7 forces user surface. The rubric is statistical; the user is the ground truth."

**Source:** [TRIAGE-RUBRIC.md § Confidence calibration](TRIAGE-RUBRIC.md). Adapted from [git-stash-janitor §I-16](../../git-stash-janitor/references/KEY-INSIGHTS.md).

**Application:** Phase 6 sorts within each verdict bucket by confidence ascending — the most ambiguous rows are most prominent. Users typically want to see their borderlines first, not the high-confidence rows.

---

## §I-17 — On the bundle format contract

> "The bundle's `branches/<slug>/diff-vs-merge-base.diff` came from `git diff --binary <merge-base>...<sha>`. The format-patch series came from `git format-patch <merge-base>..<sha> --binary --no-renames`. The bundle README documents this contract."

**Source:** [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md). [OPERATOR-LIBRARY.md § ⬡ BUNDLE](OPERATOR-LIBRARY.md).

**Application:** `verify-bundle.sh`'s byte-equality check enforces the contract. Third-party tooling can rely on these specific git invocations producing the bundle's content. Reading the bundle's diffs / patches is reading exactly the diff git produced.

---

## §I-18 — On `git cherry -v` as the patch-id-equivalence detector

> "`git cherry -v <canonical> <branch>` detects squash-merged and rebase-landed content even when SHAs differ. If all `-` lines: the content is on canonical even though `git log` doesn't show ancestry."

**Source:** [SKILL.md Axiom 17](../SKILL.md#the-rationalization-kernel-universal-axioms). [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md).

**Application:** for every branch with non-zero ahead count, run `git cherry -v <canonical> <branch>`. If all `-` lines: classify `already-merged` with confidence 0.99. This is the most reliable verdict in the rubric — patch-id equivalence is mathematically rigorous.

---

## §I-19 — On binary blobs in branches

> "Binary fixtures don't fingerprint. Fall back to file-existence + size delta + extension heuristics. Generated artifacts (target/, dist/, *-lock.json) are always garbage; lockfiles regenerate."

**Source:** [BRANCH-WORKTREE-SMELLS.md Smell 12](BRANCH-WORKTREE-SMELLS.md). Adapted from [git-stash-janitor §I-19](../../git-stash-janitor/references/KEY-INSIGHTS.md).

**Application:** Phase 5 worker for empty fingerprint AND binary diff content → `unknown`, surface to user. Never auto-classify binary changes as novel. For LFS objects, see [INCIDENT-PLAYBOOK.md I11](INCIDENT-PLAYBOOK.md#i11).

---

## §I-20 — On idempotence as a polish-bar dimension

> "Run the skill on a clean repo. It should produce zero commits and report 'nothing to rationalize'. If it doesn't, the rubric or the inventory has a bug."

**Source:** [POLISH-BAR.md P9](POLISH-BAR.md). [PHASES.md § Idempotence & Resumability](PHASES.md#idempotence--resumability).

**Application:** the smoke test verifies this. Resumption-on-empty must return `0 entries triaged` cleanly. Phases 0–4 still run (producing skeleton artifacts); Phases 5+ short-circuit.

---

## §I-21 — On the skill's source corpus

> "Every Anti-Pattern, Failure Mode, and Operator card in this skill traces back to a real session, a verified git-internals quirk, or a sibling-skill convention. The kernel is empirical, not aspirational."

**Source:** [WORKED-EXAMPLES.md](WORKED-EXAMPLES.md). [FAILURE-MODES.md](FAILURE-MODES.md). [SKILL.md § Source Corpus](../SKILL.md#source-corpus).

**Application:** when extending the skill, every new card needs a source citation. New patterns without traceable provenance are speculation, not knowledge.

---

## §I-22 — On the user-lens review

> "After a successful run, ask: 'did this save the user time, or did it just make work for them to review?' If the answer isn't clearly the former, the rubric or operator design needs adjustment."

**Source:** Phase 12 (optional) intent. Adapted from [git-stash-janitor §I-22](../../git-stash-janitor/references/KEY-INSIGHTS.md).

**Application:** Phase 12 produces `skill_feedback.md`. Re-runs of this skill on similar projects should consume that feedback to tune the rubric, prompt modules, or default modes.

---

## §I-23 — On the difference between "the branches are gone" and "the run succeeded"

> "Success is measured by recovered commits + harmonized syntheses + verified bundle + clean handoff, not by `git branch | wc -l == 1`. A run that deletes 200 branches without recovering the genuinely useful 30 keepers + 8 harmonized syntheses is a failure."

**Source:** [POLISH-BAR.md](POLISH-BAR.md) overall framing. [SKILL.md § What This Skill Produces](../SKILL.md#what-this-skill-produces).

**Application:** the handoff report leads with **recovered commits and harmonized syntheses**, not with deletion counts. The user should leave the run knowing what was *recovered*, not just what was deleted.

---

## §I-24 — On honest revert

> "If the apply succeeded but gates failed, attempt to revert via the strategy's reverse (e.g., `git apply -R` for diff applies, `git reset --merge` for cherry-pick mid-state). If revert fails, surface the dirty state honestly — don't pretend it's clean."

**Source:** [INCIDENT-PLAYBOOK.md I3](INCIDENT-PLAYBOOK.md#i3). Adapted from [git-stash-janitor §I-24](../../git-stash-janitor/references/KEY-INSIGHTS.md).

**Application:** never silently `2>/dev/null` a revert failure. The status in `apply_log.tsv` reflects reality. Per [INCIDENT-PLAYBOOK.md I3](INCIDENT-PLAYBOOK.md#i3): "If revert fails: HALT. Surface the dirty state to the user honestly. **NEVER** silently `2>/dev/null` the failure."

---

## §I-25 — On the kernel as the audit trail

> "When you find yourself wanting to break a kernel axiom, slow down and check whether you've actually identified an exception or whether the kernel is right. The kernel was learned the hard way."

**Source:** [SKILL.md § Kernel preamble](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Application:** every exception to a kernel axiom that ships in code should be documented in [FAILURE-MODES.md](FAILURE-MODES.md) or [ANTI-PATTERNS.md](ANTI-PATTERNS.md) with the case study that drove it.

---

## §I-26 — On harmonization as the conceptual leap from stash-janitor

> "A stash is a single diff: pick or drop. Branches collide on the same files in incompatible ways. The job is NOT 'pick the right branch'; it is 'recover the strongest current implementation of every file by inspecting every variant, identifying each part's intent, and synthesizing them on top of canonical's architecture.' That is the **◇ HARMONIZE** operator and the **harmonization plan** in Phase 7. Without it, this skill is just stash-janitor with extra steps."

**Source:** [SKILL.md § "The conceptual leap from git-stash-janitor"](../SKILL.md). [SKILL.md Axiom 1](../SKILL.md#the-rationalization-kernel-universal-axioms). [HARMONIZATION.md § 1](HARMONIZATION.md).

**Application:** the symptom that you skipped harmonization is the user opening the rationalization branch's diff against canonical, recognizing one branch's hardening on a contested file, and asking "where's the redaction pattern from `feature/redact-secrets`?" If you can't answer "it was harmonized into the same file at hunk N", you needed Phase 7 and didn't run it.

---

## §I-27 — On the 8-intent taxonomy

> "Every hunk in a variant is one (or more) of: `defensive` / `refactor` / `test` / `fixture` / `type-narrowing` / `error-handling` / `performance` / `naming`. The intent determines composition rules: defensive composes additively; refactor does NOT compose; tests are always additive; fixtures are additive for new files but case-by-case for modifications; type-narrowing usually composes; error-handling composes if compatible; performance composes only when independent; naming picks one."

**Source:** [HARMONIZATION.md § 3](HARMONIZATION.md).

**Application:** Phase 7 harmonization-planner classifies each hunk per the 8-intent taxonomy. The composition rules in [HARMONIZATION.md § 4](HARMONIZATION.md) follow directly. Without intent classification, the planner can't decide whether to compose or pick — and devolves to pick-or-drop.

---

## §I-28 — On not harmonizing

> "When in doubt, flag rather than synthesize. Confidence < 0.7 forces user review before Phase 8."

**Source:** [HARMONIZATION.md § 5](HARMONIZATION.md). [SKILL.md Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Application:** divergent state machines, different storage layouts, incompatible concurrency primitives, different external dependencies, deletion-vs-extension conflicts, generated code — these are NOT harmonization material. Flag as `divergent-refactor`; surface to user; user picks one wholesale.

---

## §I-29 — On the cass-mined sessions: "branches/worktrees don't work with dozens of concurrent agents"

> "When the user has 22 Claude Max accounts, 11 GPT Pro accounts, 4 Gemini Ultra accounts, and a dozen of them are working in the same repo simultaneously, the branch-per-agent model collapses. Worktrees are filesystem-expensive; branches blow up faster than they can be cleaned. The right model: file-reservations on canonical via Agent Mail, NOT branch-per-agent."

**Source:** [AGENTS.md § "Note for Codex/GPT-5.5"](../../../../AGENTS.md). The cass-mined sessions where the user manually rationalized branches/worktrees post-swarm.

**Application:** this skill's existence is the corollary: after a swarm session that DID use branch-per-agent (or that had concurrent agents committing on the same branch), the rationalization runs to consolidate. Per [ORCHESTRATION.md § Running After (or During) a Swarm](ORCHESTRATION.md#running-after-or-during-a-swarm), the After-Swarm Mode is the specialization.

---

## §I-30 — On Pro Git §3 (branch internals)

> "`-d` (lowercase) refuses to delete branches that are not fully merged into the current `HEAD`. `-D` (uppercase) deletes regardless. After Phase 8 lands every keeper onto the rationalization branch, every 'applied-keeper' branch IS fully merged from that branch's perspective — `-d` will succeed."

**Source:** [Pro Git §3](https://git-scm.com/book/en/v2/Git-Branching-Branches-in-a-Nutshell). [SKILL.md Axiom 8](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Application:** prefer `-d` over `-D` whenever possible. The refusal is a built-in safety check. Per [INCIDENT-PLAYBOOK.md I16](INCIDENT-PLAYBOOK.md#i16), use `-D` only when the user has explicitly acknowledged the branch as unmerged-and-discardable.

---

## §I-31 — On Pro Git §7 (worktree internals)

> "`git worktree remove <path>` is the structured operation. It removes the working tree directory AND prunes the corresponding `.git/worktrees/<id>/` admin metadata. `rm -rf <worktree-path>` does the first but not the second — leaving stale admin metadata that `git worktree prune` then has to clean up."

**Source:** [Pro Git §7](https://git-scm.com/docs/git-worktree). [SKILL.md Axioms 9 + 11](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Application:** never `rm -rf <worktree-path>`. Always `git worktree remove <path>`. Run `git worktree prune` AS A FOLLOW-UP after all `git worktree remove` calls in Phase 10, never as a substitute. The `--force` flag is reserved for dirty worktrees with explicit user OK and bundle-captured dirty state.

---

## §I-32 — On the reflog gc window

> "`git branch -D` deletes the ref but commits remain reachable for ~30–90 days via reflog. The backup ref in `refs/branch-rationalization-backup/<slug>` AND the `git bundle` are the long-term safety nets; both survive reflog gc."

**Source:** Pro Git §10 (gc internals). [SKILL.md Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms). [FAILURE-MODES.md](FAILURE-MODES.md).

**Application:** the bundle is designed to be readable indefinitely after run completion. Reflog gc does not affect the bundle. Even after 90 days, recovery via the bundle's `object-bundle.pack` works (per [RECOVERY-RECIPES.md R3](RECOVERY-RECIPES.md#r3-the-object-bundles-namespace-is-also-gone-catastrophic) and [R5](RECOVERY-RECIPES.md#r5-the-whole-bundle-is-gone)).

---

## §I-33 — On `[gone]`-tracking branches

> "A branch with `[gone]` upstream tracking has the upstream ref gone but its commits are not. Don't auto-prune just because tracking is gone. Triage normally."

**Source:** [SKILL.md Failure Modes table](../SKILL.md#failure-modes-table--branch--worktree-footguns). [FAILURE-MODES.md F12](FAILURE-MODES.md).

**Application:** `[gone]` is a hint that the upstream was deleted (e.g., the remote PR was closed). It is NOT a verdict. The branch may have unique commits the upstream never saw. Phase 5 triage runs the rubric the same way as for branches with healthy upstreams.

---

## §I-34 — On AGENTS.md "RULE NUMBER 1: NO FILE DELETION"

> "YOU ARE NEVER ALLOWED TO DELETE A FILE WITHOUT EXPRESS PERMISSION. Even a new file that you yourself created."

**Source:** [AGENTS.md "RULE NUMBER 1"](../../../../AGENTS.md).

**Application:** this skill never deletes files. It deletes refs (branch deletion) and removes worktrees (which involves removing the worktree directory, but `git worktree remove` is the structured operation, not a file deletion). The bundle is never deleted by the skill. Workspace artifacts are never deleted. Per [Axiom 18](../SKILL.md#the-rationalization-kernel-universal-axioms): bundle lifecycle is the user's responsibility.

---

## §I-35 — On AGENTS.md "Mandatory explicit plan"

> "Even after explicit user authorization, restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct. Only then may you execute it."

**Source:** [AGENTS.md "Mandatory explicit plan"](../../../../AGENTS.md). [SKILL.md Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Application:** Phase 10 cleanup conductor restates each `git worktree remove` and each `git branch -d`/`-D` verbatim before executing. The verbatim restatement INCLUDES the affected entity's metadata (e.g., "agent-cc-12-feat-parser, sha=def456, applied as new commit abc789 on rationalization branch"). The user has one last chance to halt before each operation.

---

## §I-36 — On AGENTS.md "Note for Codex/GPT-5.5"

> "NEVER EVER stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents. Just treat those changes identically to changes that you yourself made."

**Source:** [AGENTS.md "Note for Codex/GPT-5.5"](../../../../AGENTS.md).

**Application:** this is the source of [Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms). The `↺ WORKING-TREE-DRIFT` operator runs before every Phase 8 apply. Concurrent-agent drift is normal; the skill is drift-tolerant. Per [INCIDENT-PLAYBOOK.md I2](INCIDENT-PLAYBOOK.md#i2): "Treat the drift as if you made it. Never stash, revert, or overwrite."

---

## §I-37 — On AGENTS.md "No Script-Based Changes"

> "NEVER run a script that processes/changes code files in this repo. Brittle regex-based transformations create far more problems than they solve. Always make code changes manually, even when there are many instances."

**Source:** [AGENTS.md "No Script-Based Changes"](../../../../AGENTS.md).

**Application:** Phase 7 harmonization syntheses are authored by the Edit tool, NEVER sed/awk/regex. Phase 8 conflict resolutions are Edit-tool only. Phase 8b's split-apply uses `git cherry-pick` of the novel commit subset (driven by `subagents/partial-splitter.md`); no source-mutating script exists or is needed. Per [ANTI-PATTERNS.md W11](ANTI-PATTERNS.md#w11-script-based-source-mutation-sedawk-for-conflict-resolution).

---

## §I-38 — On the cass-mined sessions: "autostash resulted in merge conflicts requiring manual resolution"

> "When `git rebase` autostashes the working tree to make room for the rebase, and the rebased commits collide with the autostashed changes, the user gets unmerged paths and is in the middle of a rebase that's hard to abort cleanly. The skill never autostashes. Per Axiom 12, working-tree drift is captured and surfaced, not stashed."

**Source:** The cass-mined sessions where the user manually rationalized branches/worktrees. [SKILL.md Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Application:** Phase 8 NEVER runs `git pull --rebase` or any rebase that could trigger autostash. The rationalization branch is cut from canonical's tip and never rebased onto a moving canonical tip mid-run (per [INCIDENT-PLAYBOOK.md I6](INCIDENT-PLAYBOOK.md#i6) for the canonical-moved case).

---

## §I-39 — On the cass-mined sessions: "agents kept modifying files while I was working"

> "The right response is file-reservations on canonical via Agent Mail, not panic. Other agents will continue to commit; the rationalization run uses advisory reservations on `.git/refs/heads/**` and `.git/worktrees/**` to advertise its presence; concurrent agents can choose to delay destructive operations."

**Source:** The cass-mined sessions. [ORCHESTRATION.md § Coordination Discipline](ORCHESTRATION.md#coordination-discipline-agent-mail).

**Application:** the orchestrator holds advisory (non-exclusive) reservations on the high-traffic surfaces for the duration of the run. These don't block other agents — they advertise that this run is in progress. Concurrent agents continue their work; the skill stays drift-tolerant.

---

## §I-40 — On harmonization commit messages

> "A synthesis commit's message is *not* 'harmonize logger.rs'. It explicitly names every source and every intent. The user reading `git log` on the rationalization branch should be able to answer 'where did this hunk come from?' without leaving the commit message."

**Source:** [HARMONIZATION.md § 6.2](HARMONIZATION.md). [POLISH-BAR.md "Focused commit messages"](POLISH-BAR.md).

**Application:** every harmonized-synthesis commit cites ≥2 source branches (it wouldn't be a synthesis with 1) and identifies each cited hunk's intent. The Junior reading-stance check (per [MODES-OF-REASONING.md § Mode 3](MODES-OF-REASONING.md#mode-3--junior)) reads the commit message standalone and confirms the source attribution is complete.

---

## §I-41 — On the Phase 9 fresh-eyes Adversarial round

> "The harmonized-synthesis commits are the most likely place for subtle integration bugs (a defensive check that assumes a type the refactor didn't preserve, a fixture that the test no longer covers, etc.). Phase 9 round 3 in Comprehensive+ uses Adversarial stance specifically to stress-test these."

**Source:** [MODES-OF-REASONING.md § Mode 5 — ADVERSARIAL](MODES-OF-REASONING.md#mode-5--adversarial). [PHASES.md § Phase 9](PHASES.md).

**Application:** the Adversarial reader pays particular attention to harmonized-synthesis commits. It asks: "Does the synthesis preserve invariants that any single variant relied on?" Per [HARMONIZATION.md § 6](HARMONIZATION.md) for the synthesis discipline.

---

## §I-42 — On the bundle-on-disk durability

> "The bundle lives outside the repo. It survives `git clean -fdx` (which the skill never runs but the user might). It doesn't pollute `git status` while running. It's trivially shareable via `tar`."

**Source:** [SKILL.md § Workspace Layout](../SKILL.md#workspace-layout).

**Application:** bundle path defaults to `<project-parent>/<basename>-branch-worktree-archive-<YYYY-MM-DD>/`. Never inside the repo. Never inside `.git/`. The user can `tar -czf bundle.tar.gz <bundle-path>` to share it with a teammate or move it to long-term storage.

---

## How to Use This Quote Bank

- When writing a new operator card, anchor it to one or more of these quotes.
- When a phase gate fails, find the relevant quote and reference it in the user-facing message.
- When a user pushes back on a polish-bar dimension, point at the quote that justifies it.
- When extending the skill, propose new quotes — they're how this skill propagates wisdom.
- When a parallel subagent gets a borderline triage row, the quotes give it the priors to decide without re-deriving them from first principles.

---

## Cross-References

- The 19 axioms (the kernel itself): [SKILL.md § Kernel](../SKILL.md#the-rationalization-kernel-universal-axioms)
- AGENTS.md rules quoted above: [AGENTS.md](../../../../AGENTS.md)
- Operator cards each anchored to one or more quotes: [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md)
- Failure modes paired with relevant quotes: [FAILURE-MODES.md](FAILURE-MODES.md)
- Anti-patterns paired with relevant quotes: [ANTI-PATTERNS.md](ANTI-PATTERNS.md)
- Reading stances each have a "best applied to" anchored in these quotes: [MODES-OF-REASONING.md](MODES-OF-REASONING.md)
- The harmonization methodology that the synthesis-related quotes support: [HARMONIZATION.md](HARMONIZATION.md)
- The recovery recipes that the layered-reversibility quotes underpin: [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md)
