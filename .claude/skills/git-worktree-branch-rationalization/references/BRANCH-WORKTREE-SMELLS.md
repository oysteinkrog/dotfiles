# Branch + Worktree Smells — Taxonomy of Common Categories

A "smell" is a recognizable name/path/state pattern that lets you predict the verdict before doing the full FINGERPRINT + VERIFY-ON-CANONICAL pass. The Phase 5 triage rubric uses these as priors with confidence ~0.7; the user can always override.

This file has two parts:

- **Part A — Branch smells** (refs in `refs/heads/*` and their tracking state).
- **Part B — Worktree smells** (filesystem checkouts under `.git/worktrees/<id>/`).

Branches and worktrees correlate but are not the same: a worktree is pinned to a branch (or detached HEAD), but a branch may live without a worktree. Triage them separately, then reconcile in Phase 6.

> Why two parts? Per [SKILL.md Axiom 0](../SKILL.md), worktrees and branches are two units of management, one safety story. They share a bundle but have different smells, different inventories, and different removal mechanics.

---

## Part A — Branch Smells

### Smell B1: `agent-<task>-<date>-attempt-N` — Almost Always Garbage

**Pattern:** `^agent-.+-(?:\d{4}-\d{2}-\d{2}|\d{8})-(?:attempt|try|run|pass)-?\d+$`

Examples: `agent-mysql-fix-2026-04-29-attempt-3`, `agent-cleanup-2026-05-01-try2`, `agent-refactor-tokio-20260428-pass-7`.

**Why it appears:** Agent swarm spawned N parallel attempts at the same task; one (or none) of them landed; the others are abandoned half-states. Common in NTM/multi-agent setups where panes are encouraged to branch per attempt.

**Default verdict:** `garbage` when ≥1 sibling-attempt for the same `<task>` already landed on canonical (verify via `git cherry -v`); `superseded-by-newer-branch` when only the highest `-attempt-N` is meaningful; `novel-but-stale` rare exception when none of the attempts ever landed.

**Common variations:**
- `agent-cc-<task>-<date>` — Claude Code agent
- `agent-cod-<task>-<date>` — Codex agent
- `agent-gmi-<task>-<date>` — Gemini agent
- `agent-<model>-<task>-<date>` — model-prefixed
- `agent-pane-N-<task>` — NTM pane-id-prefixed

**Heuristic:** if 5+ attempts exist for the same `<task>` and one of them is on canonical, the rest are garbage. If none is on canonical, sample the latest one's fingerprint against canonical first; the rest follow.

**Why:** matches the asupersync-style 47-worktree+213-branch motivating scenario per [SKILL.md "Source Corpus"](../SKILL.md#source-corpus). Also see [PHASES.md](PHASES.md) Phase 5 fingerprint methodology.

**Exceptions:** an `agent-<task>-finalist` or `agent-<task>-final` branch may be the polished version that didn't get pushed. Always FINGERPRINT before classifying garbage.

---

### Smell B2: `wip-<ticket>-take-N` / `wip-<ticket>` — Usually Superseded

**Pattern:** `^wip[-/](BACK|JIRA|ENG|PROJ|[A-Z]+)-?\d+(-take-?\d+)?`

Examples: `wip-BACK-1742`, `wip-BACK-1742-take-3`, `wip/JIRA-567`, `wip-proj-42-attempt-2`.

**Why it appears:** Developer or agent commits WIP via branch instead of stash; later finishes work cleanly via PR with a different branch name. The wip branch sits unmerged.

**Default verdict:** `superseded` (when fingerprint resolves on canonical) — most common — or `novel-and-accretive` (rare, when nobody finished the work). When 5+ `wip-<same-ticket>` branches exist, only the most recent has any chance of being the canonical WIP; the rest are `superseded-by-newer-branch`.

**Heuristic:** check if the ticket number appears in any commit message on canonical (`git log --grep "BACK-1742"`). If yes, the work landed under a different branch name and this wip branch is superseded.

**Why:** parallels [STASH-SMELLS.md Smell 1 wip-<ticket>](../../git-stash-janitor/references/STASH-SMELLS.md). The branch analogue follows the same pattern but with a 30-90 day reflog gc window instead of stash's permanent staleness.

**Exceptions:** `wip-<ticket>` with substantive uncommitted-on-canonical content can be `novel-but-stale` if the surrounding code drifted. FINGERPRINT before defaulting.

---

### Smell B3: `cc-*`, `cod-*`, `gmi-*` — Agent CLI Naming Patterns

**Pattern:** `^(?:cc|cod|gmi|claude|codex|gemini|grok)[-/].*`

Examples: `cc-fix-deadlock`, `cod/refactor-mysql`, `gmi-test-coverage`, `claude-23-pane-7-attempt-2`.

**Why it appears:** NTM panes spawn `cc`, `cod`, `gmi` sessions and many configurations auto-prefix branches with the CLI name. Users running 2+ agent CLIs in the same repo accumulate one of these per parallel session.

**Default verdict:** `superseded` when fingerprint resolves on canonical; `garbage` when explicitly an attempt that was abandoned (often surfaces via empty `git diff <merge-base>...<branch>`); rarely `novel-and-accretive` when the agent's work was genuinely useful but never PR'd.

**Common variations:**
- `cc-<short-desc>` — most casual
- `cc-<ticket>-<desc>` — ticketed
- `cc-<pane-id>-<desc>` — NTM-pane-prefixed
- `cc-<UTC-stamp>-<desc>` — timestamp-prefixed
- `cod-rich-loop-<n>` — Codex rich-loop branches

**Why:** SKILL.md description triggers explicitly mention "agent-swarm aftermath" and "consolidate all agent branches into master." See `multi-agent-swarm-workflow` skill for the spawning side.

**Exceptions:** if the user uses a CLI prefix as an *intentional* convention for their personal feature work (rare but happens), they should add the pattern to their initial protection list at Phase 0.

---

### Smell B4: `pre-deploy-*` / `pre-release-*` / `before-*` — Often Garbage

**Pattern:** `^(?:pre|before)[-/](?:deploy|release|merge|push|migration|cutover|refactor|risky-op).*`

Examples: `pre-deploy-2026-04-29`, `before-tokio-bump`, `pre-release-v1.4-snapshot`, `before-refactor-mysql-protocol`.

**Why it appears:** Paranoid save before a risky operation. The branch is created as a "just in case I need to roll back" reference. The risky op succeeds, and the snapshot sits unused.

**Default verdict:** `superseded` if the deploy/release/refactor succeeded (the polished version is on canonical); `garbage` if the save's content diverged from what landed; rarely `novel-but-stale` if the snapshot was the only place a defensive guard lived.

**Heuristic:** `git log --since=<branch-creation-date> --first-parent canonical | wc -l` — if there are commits on canonical since the snapshot was made AND the snapshot's tip predates canonical's tip by >2 weeks, classify `superseded`.

**Why:** parallels [STASH-SMELLS.md Smell 2 pre-<refactor>-stash](../../git-stash-janitor/references/STASH-SMELLS.md). The "deliberate save" motivation is the same.

**Exceptions:** `pre-deploy-PROD-<date>` branches some teams use as actual deploy markers. Treat as PROTECTED if confirmed in Phase 4.

---

### Smell B5: `release/*` — PROTECTED

**Pattern:** `^release[-/].*` or `^releases[-/].*`

Examples: `release/2.x`, `release/v1.4`, `release/2026-Q1`, `releases/0.13`.

**Why it appears:** Long-lived release branches the team uses for hotfixes against shipped versions. Industry-standard branching model.

**Default verdict:** **PROTECTED** — auto-protected by the skill at Phase 0; never enters the rationalization pipeline.

**Why:** [SKILL.md Quickref](../SKILL.md#quickref) lists `release/*` as auto-protected: "auto-protects `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`, the canonical branch, the currently-checked-out branch."

**Exceptions:** none — never auto-classify a `release/*` branch. If the user's project explicitly says "we use `release/wip-*` as throwaway space and only `release/v*` is real," they must say so in Phase 0; only the user can override the protection.

---

### Smell B6: `hotfix/*` — PROTECTED

**Pattern:** `^hotfix[-/].*`

Examples: `hotfix/CVE-2026-1234`, `hotfix/2.1.x-leak-fix`, `hotfix/auth-bypass`.

**Why it appears:** Short-lived urgent fixes against production. Often merged then the branch is left as a deployment trace.

**Default verdict:** **PROTECTED** — even after the fix lands, the branch frequently serves as documentation of "what shipped in the urgent patch on <date>." Never auto-delete.

**Why:** mirrors B5; auto-protected per [SKILL.md Quickref](../SKILL.md#quickref).

**Exceptions:** if a `hotfix/<ticket>` branch is clearly a developer's mis-prefixed feature branch (no actual production deploy associated), the user can opt it out of protection in Phase 4. Never the skill's call.

---

### Smell B7: `dependabot/*` / `renovate/*` — PROTECTED, Auto-Managed

**Pattern:** `^(?:dependabot|renovate)[-/].*`

Examples: `dependabot/cargo/tokio-1.41`, `dependabot/github_actions/actions/checkout-5`, `renovate/lockfile`, `renovate/major-deps`.

**Why it appears:** Automated dependency-update bots open PRs from these branches. The branches exist as PR sources, not as work products.

**Default verdict:** **PROTECTED** — even if seemingly stale, the bot will reuse or recreate the branch. Touching it can confuse the bot's state machine. Per [AGENTS.md](../../../../AGENTS.md) "Dependabot" section, asupersync uses dependabot weekly; the workflow expects these branches to be auto-managed.

**Why:** auto-protected per [SKILL.md Quickref](../SKILL.md#quickref). Bot-owned branches are not the user's branches.

**Exceptions:** none from the skill. The user can manually delete a stuck `dependabot/*` branch via the GitHub UI — but the skill doesn't.

---

### Smell B8: `<ticket-id>-*` — Usually Already-Merged

**Pattern:** `^(?:BACK|JIRA|ENG|PROJ|[A-Z]{2,})-?\d+([-/].*)?$` and ticket number appears in canonical's `git log`.

Examples: `BACK-1234-fix-leak`, `JIRA-567`, `ENG-42-add-metric`, `PROJ-89-refactor`.

**Why it appears:** Standard ticket-prefixed branching workflow. After PR merges, the source branch often persists locally for weeks before cleanup.

**Default verdict:** `already-merged` when patch-id equivalence holds (`git cherry -v <canonical> <branch>` shows all `-` lines per [SKILL.md Axiom 17](../SKILL.md#the-rationalization-kernel-universal-axioms)); `superseded` when the ticket landed under a different name; `novel-and-accretive` rare exception.

**Heuristic:** `git log <canonical> --grep "BACK-1234"` — if the ticket appears in a merge commit or feature commit message, the work is on canonical. Trust `git cherry -v` over `git log --grep` for the verdict.

**Why:** Axiom 17 — patch-id equivalence detects squash-merged and rebase-landed content even when SHAs differ. SHA divergence does NOT imply novel content.

**Exceptions:** if the ticket exists on canonical but the branch has additional uncommitted-on-canonical commits (followups, polish), classify `partially-novel` and let SPLIT-COMMITS-HUNKS handle it in Phase 8b.

---

### Smell B9: `<user>/sandbox-*` / `<user>/scratch-*` — Skip; User Owns

**Pattern:** `^[a-z][\w-]*/(?:sandbox|scratch|exp|experiment|playground)[-/]?.*`

Examples: `alice/sandbox-bench`, `bob/scratch-poc`, `cinthi/exp-tokio-rich`, `agent/playground`.

**Why it appears:** Conventional namespace for developer's personal experiments. Many teams adopt this pattern explicitly so a glance at `git branch` separates "shared work" from "individual tinkering."

**Default verdict:** **SKIP** — flag in `triage.tsv` with verdict `user-owned-sandbox`; do NOT auto-classify, do NOT propose for cleanup. Surface the count to the user in Phase 6 so they can decide.

**Why:** the `<user>/...` namespace is a social convention that the skill should respect by default. Mass-deleting another developer's scratch space is exactly the kind of mistake that erodes trust.

**Exceptions:** the user explicitly says "yes, clean up the sandbox space too." Even then, surface them in Phase 6 individually.

---

### Smell B10: `feature/<name>` — Real Work; Verify Against Canonical

**Pattern:** `^feature[-/].*` or `^feat[-/].*`

Examples: `feature/parse-hardening`, `feature/oauth-flow`, `feat/admin-dashboard`.

**Why it appears:** Standard feature-branch workflow. These are the legitimate work product the user expects to triage carefully.

**Default verdict:** triage normally — no fast prior. Build the full FINGERPRINT + VERIFY-ON-CANONICAL evidence before deciding `superseded` / `already-merged` / `novel-and-accretive` / `partially-novel` / `divergent-refactor`.

**Heuristic for harmonization candidates:** `feature/*` branches that touch the same file as another non-protected branch are prime [HARMONIZATION.md](HARMONIZATION.md) inputs; flag them in Phase 7's variant-matrix builder.

**Why:** feature branches embody real intent and often have the highest yield rate for `novel-and-accretive` keepers. Don't shortcut the analysis.

**Exceptions:** none. Resist the temptation to bias toward "must be useful" — verify.

---

### Smell B11: Integration Branches (`develop`, `staging`, `next`) — Verify and Protect by Convention

**Pattern:** literal names: `develop`, `staging`, `next`, `qa`, `uat`, `integration`.

**Why it appears:** Trunk-based-development teams often have one of these as a long-lived integration target. Some projects merge feature branches into `develop` and only periodically merge `develop` into `main`.

**Default verdict:** **PROTECTED by convention** when present in `project_profile.json`'s detected branching model. The skill's Phase 1 reconnaissance should detect git-flow vs trunk-based vs custom and flag these accordingly.

**Why:** [SKILL.md Phase 1](../SKILL.md#the-phase-loop-mandatory) detects "branching model, merge style, protected-by-convention patterns" as part of `project_profile.json`. Names like `develop` and `staging` are the canonical signals.

**Exceptions:** rarely, a project has an old abandoned `develop` branch from a workflow they migrated away from. Surface to user in Phase 4 protection-confirmation; let them opt out of protection if they're sure.

---

### Smell B12: Train Branches (`train-2026-Q1`) — Usually Protected

**Pattern:** `^train[-/].*` or `^trains[-/].*`

Examples: `train-2026-Q1`, `train/v3.0`, `trains/2026-04-shipping`.

**Why it appears:** Some teams use "release trains" — periodically-cut branches that bundle a quarter or month of features for shipping together. They're long-lived.

**Default verdict:** **PROTECTED** — auto-protect when any `train-*` branch has a recent commit (<90 days) and corresponds to a still-active release window. Surface to user in Phase 4.

**Why:** train branches are infrastructure; deleting one mid-cycle breaks the team's release process.

**Exceptions:** an old `train-2024-Q3` from years ago is likely safe to remove if all its content is on canonical. User decides in Phase 4.

---

### Smell B13: `cherry-pick-*` / `cherry-*` — Usually Transient

**Pattern:** `^cherry-?(?:pick)?[-/].*`

Examples: `cherry-pick-abc123-into-release`, `cherry-fix-leak`, `cherry-pick-PR-456`.

**Why it appears:** Developer or tool created a temporary branch to perform a cross-branch cherry-pick. After the cherry-pick lands on the target, the source branch is residue.

**Default verdict:** `garbage` when the cherry-picked content is on canonical (`git cherry -v` confirms patch-id equivalence). Sometimes `superseded`. Rarely `partially-novel` when the cherry-pick was abandoned.

**Heuristic:** if the cherry-pick's target branch (extractable from the name, e.g., `cherry-pick-abc123-into-release`) shows the patch-id, classify `already-merged-into-target` and surface; default-protect the target branch only if it matches B5/B6.

**Why:** cherry-pick branches are by definition transient — they exist to land a specific patch and then aren't needed. The patch's home is the target.

**Exceptions:** `cherry-pick-*` containing genuinely novel pre-cherry-pick fixups are rare but possible. FINGERPRINT before defaulting to garbage.

---

### Smell B14: `revert-*` — Usually Transient; Verify the Revert Is Still Wanted

**Pattern:** `^revert-.*` (note: this is also GitHub's auto-generated revert-PR branch prefix).

Examples: `revert-abc123`, `revert-PR-456`, `revert-broken-deploy-2026-04-29`.

**Why it appears:** A revert PR was opened (manually or via GitHub's "Revert" button), and the branch served as the PR source. After merging, the branch is residue.

**Default verdict:** `already-merged` when the revert landed on canonical. `garbage` if the revert was abandoned (the broken commit is still on canonical) — but FIRST surface to user, because an abandoned revert may indicate a still-broken-on-canonical state worth investigating.

**Heuristic:** `git log <canonical> --grep "Revert "` — if the revert message appears, the revert landed.

**Why:** reverts have unusual triage semantics: they're additive to canonical's history (adding a "Revert <commit>" commit) so `git cherry -v` is the right detector, not "is the original commit still there."

**Exceptions:** if the revert is intentionally pending (the team is debating whether to actually revert), the branch should be PROTECTED. Surface to user in Phase 4.

---

### Smell B15: Branches with `[gone]` Upstream Tracking — Have Unique Commits

**Pattern:** `git branch -vv` shows `[origin/<branch>: gone]` — the tracking ref is gone but the branch is still local.

Examples: any local branch whose upstream was deleted on the remote (e.g., after a PR merge that deletes the remote branch, but the developer didn't delete locally).

**Why it appears:** GitHub auto-deletes head branches after PR merges by default. The local copy survives.

**Default verdict:** triage normally — `[gone]` is a hint, not a verdict. Frequently the branch's content IS on canonical (the PR merged), so `git cherry -v` will show `-` lines and the verdict is `already-merged`. But sometimes the branch has unique commits the upstream never saw (last-minute fixes the developer didn't push), and those are `novel-and-accretive`.

**Why:** [SKILL.md Failure Modes](../SKILL.md#failure-modes-table--branch--worktree-footguns): "A branch with `[gone]` upstream tracking has unique commits — The tracking ref is gone but the commits aren't. Don't auto-delete just because tracking is gone. Triage normally."

**Exceptions:** none — never auto-delete a `[gone]` branch without FINGERPRINT.

---

### Smell B16: `merge-<x>-into-<y>` — Integration Branches; Verify Intent

**Pattern:** `^merge-.+-into-.+$` or `^integrate-.+-into-.+$`

Examples: `merge-feature-foo-into-develop`, `merge-release-2-into-main`, `integrate-bugfixes-into-staging`.

**Why it appears:** Some teams use named branches to perform tested integration before merging into the real target. The branch is the integration scratchpad.

**Default verdict:** triage normally; verify whether the integration landed via `git cherry -v <target> <merge-branch>`. If yes, `already-merged`. If not, the branch may be a still-pending integration the user wants to keep — surface to user.

**Why:** `merge-*` branches are intentional infrastructure for some workflows. Deleting one mid-flight is destructive.

**Exceptions:** old (>90 days) `merge-*` branches are usually safe to remove if their content is on canonical — but always surface in Phase 6 because the naming explicitly signals intent.

---

### Smell B17: Tag-Equivalent Branches (`v1.2.3`) — Usually Frozen Release Pointers

**Pattern:** `^v?\d+\.\d+(\.\d+)?(-[a-z0-9.]+)?$`

Examples: `v1.2.3`, `v0.13.0-rc1`, `1.4`, `v3.0.0-alpha`.

**Why it appears:** Some workflows use branches as release pointers in addition to (or instead of) tags. Once cut, they're frozen.

**Default verdict:** **PROTECTED** unless the user explicitly says they migrated to tags-only. Treat like a release branch.

**Why:** version-numbered branches usually mean "this is the immutable code that shipped as <version>." Deleting it removes the project's release history at the ref level.

**Exceptions:** if the project also has matching tags AND the user confirms "we only use tags now, the branches are residue," classify `superseded-by-tag` and propose for cleanup with explicit user OK in Phase 6.

---

### Branch-Smell Summary Matrix

| Smell | Pattern | Default Verdict | Auto-Protected? |
|-------|---------|----------------|-----------------|
| B1 agent-attempt-N | `^agent-.+-attempt-?\d+` | garbage | No |
| B2 wip-ticket | `^wip[-/]\w+-\d+` | superseded | No |
| B3 cc/cod/gmi | `^(cc|cod|gmi|claude|codex|gemini)[-/]` | superseded | No |
| B4 pre-deploy | `^(pre|before)[-/].*` | superseded | No |
| B5 release/* | `^release[-/].*` | PROTECTED | **Yes** |
| B6 hotfix/* | `^hotfix[-/].*` | PROTECTED | **Yes** |
| B7 dependabot/renovate | `^(dependabot|renovate)[-/].*` | PROTECTED | **Yes** |
| B8 ticket-id-* | `^[A-Z]+-\d+` | already-merged | No |
| B9 user/sandbox | `^[a-z]+/(sandbox|scratch|exp)` | SKIP | **Yes (skip)** |
| B10 feature/* | `^feature?[-/].*` | triage normally | No |
| B11 develop/staging | literal `develop`/`staging`/`next` | PROTECTED by convention | Phase 1 detection |
| B12 train-* | `^train[-/].*` | PROTECTED | Phase 1 detection |
| B13 cherry-pick-* | `^cherry-?(pick)?[-/]` | garbage | No |
| B14 revert-* | `^revert-` | already-merged | No |
| B15 [gone] upstream | tracking ref gone | triage normally | No |
| B16 merge-x-into-y | `^merge-.+-into-` | triage normally | No |
| B17 v1.2.3 | `^v?\d+\.\d+` | PROTECTED | **Yes** |

---

## Part B — Worktree Smells

### Smell W1: `/tmp/foo-experiment-<date>` — Usually Abandoned

**Pattern:** worktree path under `/tmp/...`, or matching `*-experiment-*`, `*-poc-*`, `*-spike-*`.

Examples: `/tmp/asupersync-tokio-rich`, `/tmp/foo-poc-2026-04-29`, `/tmp/spike-graphql`.

**Why it appears:** Quick spike — `git worktree add /tmp/<basename>-<idea>` to play with an idea outside the main checkout. Often abandoned without ceremony; `/tmp` survives reboots on some systems but is treated as ephemeral.

**Default verdict:** if the worktree's branch matches a B1/B3/B4 garbage smell, propose for `⊙ PRUNE-WORKTREE` after the dirty state is captured in the bundle. If the branch is a `feature/*` or `<ticket>/*` branch with novel content, the worktree is removable but the branch needs full triage.

**Heuristic:** `/tmp/...` paths AND last-commit > 14 days = high garbage probability.

**Why:** [SKILL.md "WHEN-NOT-TO-USE.md"](WHEN-NOT-TO-USE.md) flags `/tmp/...` paths as ephemeral; the worktree is the moral equivalent of a stash made in detached-HEAD state.

**Exceptions:** `/tmp/<basename>` worktrees that the user is actively using as their working directory (rare but possible — user is mid-spike). The currently-active worktree is auto-protected per [SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms); the skill never removes the user's CWD.

---

### Smell W2: `/data/projects/<basename>-wt-<branch>` — Conventional Pattern

**Pattern:** sibling-of-repo paths matching `<repo>-wt-<branch>` or `<repo>.<branch>` or `<repo>-<branch>`.

Examples: `/data/projects/asupersync-wt-feature-x`, `/data/projects/dcg-wt-deadlock-fix`, `/data/projects/foo.feature-bar`.

**Why it appears:** Conventional pattern for parallel work on a sibling worktree without polluting the main checkout. Matches the [`flywheel-with-two-agents-per-repo`](https://example.invalid) skill's spawning convention and many manual workflows.

**Default verdict:** safe to remove via `⊙ PRUNE-WORKTREE` IF the worktree's branch is in the rationalize list (verdict `superseded` / `garbage` / `already-merged` / `applied-keeper`). If the branch is PROTECTED, the worktree stays.

**Heuristic:** for a `<repo>-wt-<branch>` worktree, branch's verdict drives the worktree's verdict (since the worktree exists *because of* the branch).

**Why:** parallels the conventional pattern; the worktree is infrastructure for working on the branch and has no value once the branch is gone or the work is integrated.

**Exceptions:** if the worktree has substantial uncommitted state (untracked files representing in-progress work, staged diffs that aren't yet committed), capture in the bundle FIRST per [WORKTREE-STATE.md](WORKTREE-STATE.md), then remove.

---

### Smell W3: `~/scratch/*` — Almost Always Abandoned

**Pattern:** worktree path under `$HOME/scratch/...`, `$HOME/tmp/...`, `$HOME/playground/...`.

Examples: `/home/ubuntu/scratch/asupersync-test`, `/root/playground/foo-experiment`.

**Why it appears:** Personal scratch directory. Like `/tmp` but persistent across reboots. Often where users put "I'll come back to this" experiments.

**Default verdict:** `⊙ PRUNE-WORKTREE` candidate after dirty-state capture; the path naming is a strong signal of "abandoned exploration."

**Heuristic:** scratch paths AND last-commit > 7 days = nearly always abandoned. The user can override.

**Why:** scratch directories are by convention disposable. Even users who care about their projects don't usually expect their scratch worktrees to survive cleanup.

**Exceptions:** the user explicitly says "I keep my real work in `~/scratch/` because <reason>." Honor that; treat as B10/feature.

---

### Smell W4: Worktrees with No Commit in >30 Days — Stale

**Pattern:** `git -C <worktree> log -1 --format=%cI` shows date >30 days old; combined with no recent file modifications in the worktree.

**Why it appears:** Worktree was created for an active project, then forgotten. Common after the user moved on to other work.

**Default verdict:** triage the branch normally; if the branch verdict is anything except PROTECTED, the worktree is `⊙ PRUNE-WORKTREE`. Surface stale worktrees prominently in the Phase 6 decision table so the user can confirm they're truly abandoned.

**Heuristic:** date threshold is configurable via `project_profile.json`; default 30 days.

**Why:** a worktree's filesystem footprint is significant (often 1–10 GB per worktree). Stale worktrees are the primary disk-pressure source the skill is designed to address — see SKILL.md trigger phrase "I'm out of disk because of worktrees."

**Exceptions:** worktrees pinned to release branches or train branches (B5, B6, B12) that are intentionally long-lived. Auto-protected.

---

### Smell W5: Worktrees on Branches Deleted Upstream

**Pattern:** worktree's branch has `[gone]` upstream tracking (parallels B15) AND no recent commits in the worktree.

**Why it appears:** PR merged on remote, remote branch auto-deleted, worktree was the developer's working copy. Now the worktree is residue.

**Default verdict:** triage the branch first (per B15 — has unique commits or not?); if the branch is `already-merged` or `garbage`, prune the worktree.

**Heuristic:** the `[gone]` upstream is only a signal — verify with `git cherry -v` that content is on canonical before classifying.

**Why:** these worktrees often hold the developer's last-minute uncommitted work that never made it to the merged PR. Capture dirty state in the bundle before pruning.

**Exceptions:** branches with substantial uncommitted state — never prune without bundle-archive of the dirty state.

---

### Smell W6: Locked Worktrees on Stale Paths

**Pattern:** `git worktree list --porcelain` shows `locked` entry AND the path either doesn't exist or hasn't been touched in months.

**Why it appears:** `git worktree lock <path>` was run (often automatically by tooling like NTM that pins worktrees during sessions) and never unlocked. The lock survives even if the working directory is cleaned up out-of-band.

**Default verdict:** surface to user with the lock reason (if any) and the path. Default-recommend `git worktree unlock <path>` followed by normal triage. Never force-remove a locked worktree.

**Heuristic:** parse `--porcelain` output explicitly; never rely on the human-readable `git worktree list`. Per [SKILL.md Failure Modes](../SKILL.md#failure-modes-table--branch--worktree-footguns): "git worktree list doesn't reliably show locked worktrees on stale paths — Always parse --porcelain and check the locked field explicitly."

**Why:** locks are intent signals from past tooling. Ignoring them risks deleting something a sleeping daemon expected to find.

**Exceptions:** if the lock reason explicitly says "abandoned by <tool> on <date>" and the date is >90 days, propose `git worktree unlock` then prune. User OK first.

---

### Smell W7: Worktrees with Substantial Uncommitted State — NEVER Remove Without Bundle-Archive

**Pattern:** `git -C <worktree> status --porcelain` shows >0 lines (staged, unstaged, or untracked).

**Why it appears:** Active work in progress. Common when a developer has multiple worktrees with different in-progress experiments.

**Default verdict:** **NEVER auto-remove**. The dirty state must be captured in the bundle's `worktrees/<sanitized-path>/{staged.diff,unstaged.diff,.untracked.list,untracked.tar.gz}` per [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) BEFORE the worktree is pruned. Force-remove (`--force`) only after explicit user OK on a per-worktree basis.

**Heuristic:** any `--porcelain` output triggers the dirty-state-capture path; even a single untracked file qualifies.

**Why:** [SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms): "git worktree remove <path> refuses on dirty worktrees — that refusal is a feature." The bundle-then-confirm flow is non-negotiable.

**Exceptions:** none — even "trivial" untracked files (a single `.scratch/notes.txt`) get captured. Better to over-archive than to lose work.

---

### Smell W8: Worktrees on Already-Merged Branches — Safe to Remove

**Pattern:** worktree's branch verdict is `already-merged` (B8/B14 typical) AND no dirty state.

**Why it appears:** post-PR-merge residue. The branch's content is on canonical; the worktree is just the filesystem checkout.

**Default verdict:** `⊙ PRUNE-WORKTREE` after the branch's deletion is queued. Order per [SKILL.md Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms): worktrees first, branches second.

**Why:** the worktree is by definition stale once the branch is merged; nothing is lost.

**Exceptions:** if the worktree has dirty state (W7), capture-then-confirm regardless of the branch's merge status.

---

### Smell W9: The Currently-Active Worktree — Auto-Protected

**Pattern:** the worktree containing the user's current `pwd` (the skill's CWD).

**Why it appears:** the user runs the skill from their working directory; that directory is by definition not for removal.

**Default verdict:** **AUTO-PROTECTED** — never proposed for removal. The handoff report at Phase 11 tells the user how to remove the active worktree themselves (from a different working directory) if they want to.

**Why:** [SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms): "The currently-active worktree (the user's CWD) is NEVER removed by the skill; the user removes that one themselves from a different working directory after the run completes."

**Exceptions:** none — non-negotiable. Even if the user explicitly asks "remove this one too," the skill refuses politely and explains.

---

### Smell W10: Worktrees Pinned to a Release Branch — Protected

**Pattern:** worktree's branch matches B5 (`release/*`), B6 (`hotfix/*`), B12 (`train-*`), or B17 (`v1.2.3`).

**Why it appears:** team has a worktree pinned to a long-lived release branch for hotfix work.

**Default verdict:** **PROTECTED** — auto-protected because the branch is auto-protected. The worktree is the operational tool for working on that protected branch.

**Why:** parallels B5/B6/B12/B17. Removing a release-branch worktree would require recreating it next time the team needs to ship a hotfix.

**Exceptions:** none from the skill. User can manually remove via `git worktree remove` outside the skill if they're sure.

---

### Smell W11: Sub-Checkouts vs External Worktrees — Different Cleanup Ergonomics

**Pattern:** worktree path is *inside* the main repo (`<repo>/worktrees/foo`, `<repo>/.worktrees/foo`) vs. *outside* (`/data/projects/<basename>-wt-foo`).

**Why it appears:** two different conventions. Inside-the-repo worktrees are usually `.gitignore`d to avoid recursion confusion; outside-the-repo worktrees are the more common pattern.

**Default verdict:** triage independently of the path-shape, but flag the location in `worktrees.tsv` because:

- **Inside-the-repo:** removal is a single `git worktree remove` and the directory disappears within the repo. Easier on disk-pressure analysis (the worktree's bytes count toward the repo's directory size).
- **Outside-the-repo:** removal frees disk in a different directory. Surface this to the user in the handoff so they understand where the disk reclaims.

**Heuristic:** detect via path prefix matching. Both shapes are valid; the smell is informational, not directive.

**Why:** worktree placement affects disk reclamation reports and the user's mental model. Mention it; don't decide based on it.

**Exceptions:** none. This is metadata, not a verdict.

---

### Worktree-Smell Summary Matrix

| Smell | Pattern | Default Verdict | Auto-Protected? |
|-------|---------|----------------|-----------------|
| W1 /tmp/* | path under `/tmp/` | PRUNE if branch verdict allows | No |
| W2 sibling-wt-* | `<repo>-wt-<branch>` pattern | PRUNE if branch in rationalize list | No |
| W3 ~/scratch/* | `$HOME/scratch/...` | PRUNE if abandoned | No |
| W4 stale (>30 d) | last-commit >30 d | PRUNE if branch verdict allows | No |
| W5 [gone] upstream | branch tracking gone | PRUNE if branch already-merged/garbage | No |
| W6 locked stale | `--porcelain` shows `locked` + stale path | Surface; manual unlock first | **Yes (surface)** |
| W7 dirty | `--porcelain` non-empty | NEVER auto; capture-then-confirm | **Yes (until archived)** |
| W8 on merged branch | branch is `already-merged` | PRUNE | No |
| W9 active CWD | user's `pwd` | NEVER REMOVE | **Yes** |
| W10 release-pinned | branch is B5/B6/B12/B17 | PROTECTED | **Yes** |
| W11 inside vs outside | path shape | informational | No |

---

## Using Smells in Triage

The Phase 5 triage worker uses smell detection as a fast prior. The decision flow per [PHASES.md](PHASES.md):

```
1. Smell match → seed prior verdict (with confidence ~0.7)
2. Run ✦ FINGERPRINT
3. Run ◐ VERIFY-ON-CANONICAL
4. Run `git cherry -v <canonical> <branch>` for branches; per-worktree dirty-state capture for worktrees
5. If signals agree with prior: confirm verdict, raise confidence to ~0.95
6. If signals disagree with prior: trust the signals, lower confidence,
   surface to user in Phase 6 decision table even if confidence ≥ 0.7
7. For files touched by ≥2 non-protected branches, queue for ◇ HARMONIZE in Phase 7
```

Smell-prior + signal agreement = high confidence. Smell-prior + signal disagreement = surface to user. The smells are priors, not verdicts — see [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) for the full evidence/confidence model.

---

## Cross-References

- Branch + worktree triage rubric: [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md)
- Working-tree-state guidance during the run: [WORKTREE-STATE.md](WORKTREE-STATE.md)
- Bundle layout for tooling that consumes the bundle: [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md)
- When NOT to use this skill: [WHEN-NOT-TO-USE.md](WHEN-NOT-TO-USE.md)
- Sibling skill stash smells (the conceptual ancestor): [STASH-SMELLS.md](../../git-stash-janitor/references/STASH-SMELLS.md)
- The 19-axiom kernel: [SKILL.md "THE RATIONALIZATION KERNEL"](../SKILL.md#the-rationalization-kernel-universal-axioms)
