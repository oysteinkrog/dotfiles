# Exemplars — World-Class Git Workflows To Aspire To

A quote bank from real-world projects, post-mortems, and engineering blogs whose discipline informs this skill. Each entry is an aspirational example with three parts: **what they do well**, **what we steal**, and **where this skill diverges**.

Adapted from [git-stash-janitor's EXEMPLARS.md](../../git-stash-janitor/references/EXEMPLARS.md). The skill we're building is the branch-and-worktree analogue, so most of stash-janitor's exemplars apply with one twist: where stash-janitor borrows *recovery discipline*, this skill borrows *integration discipline* — the practices these projects use to land contributions cleanly across many branches and many submitters.

---

## §EX-1 — Linus on the reflog as the safety net

> "If you have not run `git gc`, the commits are still there. Most things in git are recoverable. The reflog is your friend."
>
> — Linus Torvalds, various git mailing-list posts

**What they do well:** the kernel community treats reflog as the *first* line of defense, but assumes nothing about its lifetime.

**What we steal:** the skill's Layer 1 (backup refs in `refs/branch-rationalization-backup/<slug>`) is a deliberate version of this insight. Reflog default expiry is finite (90 days reachable, 30 days unreachable); we create permanent refs that survive any normal git operation, including `git gc --prune=now`.

**Where we diverge:** Linus's audience is patch authors who already understand `git fsck --lost-found`. Our audience is users who shouldn't *have* to understand recovery internals. The bundle (Layer 2) plus `RECOVERY-RECIPES.md` provide a recipe-card path that doesn't require fsck literacy.

**Why:** [SKILL.md](../SKILL.md) Axiom 3 ("Plan for irreversibility first, classification second") + [SAFETY-MODEL.md](SAFETY-MODEL.md).

---

## §EX-2 — Linux kernel's `git format-patch` series convention

> "Patches are submitted as a numbered series: `0001-...`, `0002-...`, etc. The series is reviewed as a unit; each patch in the series is a coherent atomic change."
>
> — Linux kernel `Documentation/process/submitting-patches.rst`

**What they do well:** the kernel's mailing-list flow forces every contribution to be a clean, ordered, reviewable commit series before it lands. `git format-patch` is the canonical export format; `git am` is the canonical import.

**What we steal directly:** the bundle's `branches/<slug>/format-patch/` directory uses *exactly* the kernel's numbered-series convention. Per [SKILL.md Axiom 7](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git format-patch` IS valid for branches; it is NOT for stashes." When a branch's content needs to be re-applied without the bundle's object pack (e.g., the user shipped the bundle to a colleague who can't pull the pack), `git am 0001-*.patch` reproduces the branch commit-by-commit.

**Where we diverge:** the kernel's flow is a *human review* mechanism — every patch is read by maintainers on lkml. Our flow is a *recovery* mechanism — the format-patch series is a backstop, not a primary submission path. We don't ask the user to review the patches one-by-one; we ask them to review the harmonization plan, which is a higher-level artifact.

**What wouldn't translate:** the kernel's mailing-list discussion threads, the `Reviewed-by:` / `Tested-by:` trailers, the `linux-next` integration tree as a staging area for in-flight patches. Our equivalent of "staging area" is the rationalization branch itself ([SKILL.md Axiom 6](../SKILL.md#the-rationalization-kernel-universal-axioms)).

**Why:** [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) §"format-patch series" cites this exemplar by name as the convention's source.

---

## §EX-3 — Chromium's many-bot worktree pattern

> "Each presubmit bot operates in its own worktree of the chromium/src checkout, so concurrent CL trybots don't stomp each other's working tree."
>
> — paraphrased from Chromium developer documentation

**What they do well:** the Chromium build infrastructure uses `git worktree` *intentionally* as a parallelism primitive. Bots run in dedicated worktrees so the main checkout stays consistent; worktrees are created fresh per CL, used, and removed when the CL closes.

**What we steal:** the worktree-as-parallel-workspace mental model. When a user has 20+ worktrees, they may be doing exactly what Chromium's bots do — running parallel work on the same repo without stomping. Phase 4's protection-confirmation step explicitly asks "are any of these worktrees pinned to open PRs you're still working on?" Per [SKILL.md "When NOT to Use This Skill"](../SKILL.md#when-not-to-use-this-skill): "Some teams use `git worktree` deliberately as a parallel-review pattern (one worktree per open PR). Don't prune their workflow out from under them — ask first."

**Where we diverge:** Chromium has *infrastructure* that knows when a worktree's purpose is over (the CL closed, the bot finished). The user invoking this skill usually doesn't, which is why the worktree pile accumulated in the first place. We compensate by inventorying every worktree's branch + dirty-state + last-activity timestamp ([WORKTREE-STATE.md](WORKTREE-STATE.md)) and surfacing all of it before any removal.

**What wouldn't translate:** Chromium's bot-orchestration layer (Recipe Engine, Buildbucket). We're a single-shot tool; their flow is a continuous-integration platform.

**Why:** the asupersync 47-worktree+213-branch motivating scenario per [SKILL.md "Source Corpus"](../SKILL.md#source-corpus) is structurally identical to a Chromium worktree-bot pile after a long bot run with no cleanup.

---

## §EX-4 — Mozilla's branch-protection + Dependabot conventions

> "`release/*` branches are auto-protected by branch-protection rules. Dependabot branches are short-lived; they get merged or closed within 7 days. Anything else is a feature branch and follows the standard PR flow."
>
> — paraphrased from Mozilla GitHub repo conventions (Firefox, gecko-dev mirrors)

**What they do well:** Mozilla codifies branch *categories* in branch-protection rules so the right branches get the right treatment automatically. Release branches can't be force-pushed; Dependabot branches don't need code review (they're auto-tested).

**What we steal:** the auto-protected pattern list in `project_profile.json:protected_by_convention_patterns` — `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages` — comes directly from this kind of convention. Per [SKILL.md "Inputs"](../SKILL.md#inputs): "Initial protection list — branches/worktrees the user already knows they want to keep beyond the auto-protected defaults. (Defaults: canonical, currently-checked-out branch, anything matching `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`, plus anything with branch-protection rules in the project config.)"

**Where we diverge:** Mozilla's enforcement is *server-side* via GitHub branch-protection rules. We're operating *client-side* on a local clone. We can read the user's local conventions but we can't read remote branch-protection rules without `gh api`; even then, we treat them as advisory because the user's local notion of "protected" may differ from the remote enforcement.

**What wouldn't translate:** the auto-merge tooling that Dependabot integrates with (e.g., bors-style queues for dependency PRs). The skill never auto-merges anything; everything lands on the rationalization branch for the user to review.

**Why:** the protection list's defaults are not arbitrary; they trace to the conventions that real projects actually use. See [SAFETY-MODEL.md](SAFETY-MODEL.md) §"Why these defaults?".

---

## §EX-5 — Rust's bors / homu merge queue

> "Every PR enters a queue. Each PR is rebased on top of the queue's tip, runs the full CI matrix, and either lands or is rejected. There is exactly one merge order; there is no race."
>
> — bors / homu / rust-lang merge-queue docs

**What they do well:** bors solves the "two PRs each pass CI individually but conflict when both land" problem by *serializing* merge attempts and re-running CI on the rebased combination. Every commit on master has been tested against the *exact* state it will land into.

**What we steal:** the merge-strategy-detection pattern. `project_profile.json:merge_style` is detected from the project's history (squash-merge / rebase-and-merge / cherry-pick / true-merge) so Phase 8 applies use the project's *actual* style — see [PHASES.md Phase 8](PHASES.md#phase-8-rationalization--apply-sequential-60240-min). Bors-style projects use squash-merge or rebase-and-merge; the apply strategy follows. Also: the per-apply gate discipline (Axiom 13) is bors's CI-on-every-rebase, applied to recovered keepers instead of incoming PRs.

**Where we diverge:** bors is a *merge gate* — its job is to prevent broken main. We're a *recovery* tool — our job is to fold abandoned work onto a rationalization branch for the user to gate. Same per-commit CI discipline, different commit destination.

**What wouldn't translate:** bors's queue-and-batch optimization (rolling up multiple PRs into one CI run). We apply keepers one-at-a-time on purpose because each apply changes the 3-way base for later applies and can flip downstream verdicts via [`⊞ RE-FINGERPRINT`](OPERATOR-LIBRARY.md). Batching would defeat that.

**Why:** [OPERATOR-LIBRARY.md `⊕ RECOVER`](OPERATOR-LIBRARY.md) cites bors-style discipline directly. [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms): "Per-apply gates are non-negotiable."

---

## §EX-6 — LLVM's release/* branch line

> "Each major release gets a long-lived `release/N.x` branch. Bug fixes are cherry-picked from main onto active release lines; release branches never accept new features."
>
> — LLVM release-management docs

**What they do well:** LLVM maintains *multiple* protected lines simultaneously (`release/14.x`, `release/15.x`, `release/16.x`, ...) with explicit cherry-pick discipline. The release lines are sacrosanct; the rationalization happens on `main`.

**What we steal:** the auto-protect-every-`release/*` rule and the per-line cherry-pick guidance. When the user's repo follows this archetype (see [REPO-ARCHETYPES.md §A4 Release-train](REPO-ARCHETYPES.md#a4--release-train-long-lived-releasenx-branches)), Phase 5 triages only feature branches; every `release/*` is protected automatically.

**Where we diverge:** LLVM has explicit *release managers* who curate which fixes get backported. The skill doesn't take a position on which keepers should also land on `release/*` — that's out of scope. The handoff report names the rationalization-branch tip and tells the user "if any of these recoveries belong on `release/N.x`, that's a separate cherry-pick you run yourself."

**What wouldn't translate:** LLVM's contributor-license-agreement workflow, the GitHub release artifacts, the multi-month release cycles. We're operating against a local clone snapshot, not running a release process.

**Why:** [REPO-ARCHETYPES.md](REPO-ARCHETYPES.md) §"Release-train" cites this exemplar as the canonical example.

---

## §EX-7 — Tor's hardened-release-line discipline

> "Every commit on `release/0.4.x` is signed; every commit's source patch is reviewed by ≥2 people; tags are signed by the release manager's hardware-token key."
>
> — Tor Project release engineering practices

**What they do well:** Tor treats release lines as *adversarial-resistant* artifacts. Signing chain, multi-reviewer requirement, hardware-token tags. The bar for landing on a release line is significantly higher than for landing on `main`.

**What we steal:** the *protection asymmetry* — different branches deserve different rigor. The skill's protection list isn't binary (protected/not); the auto-protected categories are *strongly* protected (never enter the pipeline at all), but `[gone]`-tracking branches and stale-locked worktrees are *softly* protected (surfaced to user, default-skip, but not auto-pruned). See [SAFETY-MODEL.md](SAFETY-MODEL.md) §"Layered protection".

**Where we diverge:** Tor's enforcement is a *signed-commits* discipline backed by a key-management infrastructure. The skill operates on what's locally available; if `commit.gpgsign=true`, we preserve signatures across cherry-picks (Phase 8 doesn't strip them), but we don't *require* signing — the user's project sets that policy.

**What wouldn't translate:** Tor's hardware-token requirement, the multi-jurisdiction reviewer pool. The skill is single-user; "second opinion" is via [multi-model triangulation](../../multi-model-triangulation/SKILL.md), not via human reviewers.

**Why:** the asymmetric-protection idea is foundational to Phase 4's confirmation flow.

---

## §EX-8 — GitHub's `gh pr merge` strategy detection

> "`gh pr merge` reads the repository's default merge method (squash / rebase / merge) from the GitHub API and uses it; the user can override per-PR but the default reflects the project's convention."
>
> — `gh-cli` PR-merge implementation

**What they do well:** the tool reads the project's preferred merge style from authoritative metadata, then applies it. Defaults follow the project; overrides are explicit.

**What we steal:** `scripts/discover-project.sh` detects the project's preferred merge style by analyzing commit-graph patterns (squash-merges produce one-parent commits with PR-style messages; rebase-and-merge produces linear history with author distinct from committer; true-merge produces explicit `Merge pull request` commits). The detected style goes into `project_profile.json:merge_style` and Phase 8's apply strategy follows. See [PHASES.md Phase 1](PHASES.md#phase-1-project-reconnaissance-520-min-single-subagent).

**Where we diverge:** `gh pr merge` reads metadata directly from the GitHub API. We can't always assume `gh` is authenticated against this repo's remote, so we infer from the local commit graph. The inference is high-confidence but never 100%; the user reviews and overrides at Phase 1.

**What wouldn't translate:** the GitHub-side branch-protection-rule enforcement that prevents non-default merge styles from succeeding. We're client-side; we ask the user to confirm.

**Why:** [OPERATOR-LIBRARY.md `⊟ SQUASH-MERGE` / `⊠ REBASE-AND-MERGE` / `✧ CHERRY-PICK`](OPERATOR-LIBRARY.md) — three operators because three project styles, not one.

---

## §EX-9 — Atlassian's "stash recovery" guide

> "If you accidentally drop a stash, you can recover it by finding the SHA in the reflog within the gc window."

**What they do well:** Atlassian documents the recovery path explicitly with copy-paste commands. The user doesn't need to derive the recovery from first principles.

**What we steal:** every cleanup_log row points at a specific recovery recipe in `RECOVERY-RECIPES.md`. The handoff report includes verbatim recovery commands per recovered branch and per removed worktree. The user copy-pastes; they don't derive.

**Where we diverge:** the skill's recovery doesn't require the reflog gc window. The backup ref + bundle survive `git gc --prune=now` and `git reflog expire --expire=now`. Atlassian's path works while reflog is alive; ours works permanently.

**Why:** [SKILL.md Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms) — five reversibility layers; reflog is the weakest, refs + bundle are the strongest.

---

## §EX-10 — Cloudflare's "feature flag rollback" post-mortem

> "We rolled back a feature that had been deployed to 1% of traffic. The rollback worked because every change is reversible by construction."
>
> — Cloudflare engineering blog (paraphrased)

**What they do well:** the rollback wasn't a *plan*; it was a *capability*. The system was designed so that any change *could* be rolled back at any moment without coordination.

**What we steal:** every Phase 8 apply produces a commit with full provenance — source branches cited in the message, source SHAs in the body, a row in `apply_log.tsv`. Rollback of any one keeper is `git revert <sha>` plus a row in the audit log. We don't promise rollback; we make it trivially possible.

**Where we diverge:** Cloudflare's reversibility is at the deployment layer (traffic routing). Ours is at the commit layer. Different abstraction, same discipline.

**Why:** [POLISH-BAR.md](POLISH-BAR.md) §"Recovery completeness".

---

## §EX-11 — Linus on bisect-friendly commits

> "If you can't bisect a bug, your commit history is wrong. Make commits that are atomic, focused, and individually testable."
>
> — Linus Torvalds, lkml

**What they do well:** the kernel commits are *bisectable by construction* — each commit compiles, each commit's tests pass, each commit is logically self-contained.

**What we steal:** Phase 8's apply strategy keeps commits focused. A 3-branch harmonized synthesis is *one* commit, not three; the synthesis is the unit. Phase 8b's split-apply produces atomic commits per novel hunk. Per-apply gates ensure each commit compiles and tests. The rationalization branch is bisectable end-to-end.

**Where we diverge:** the kernel author writes the commit; Linus reviews the bisectability. Here, the skill *generates* the commit and the harmonization plan documents the per-source-variant attribution. The user's code reviewer in PR review takes Linus's role.

**Why:** [POLISH-BAR.md](POLISH-BAR.md) §"Focused commit messages" + [COMMIT-MESSAGE-CRAFT.md](COMMIT-MESSAGE-CRAFT.md).

---

## §EX-12 — A Go team's "recovered code needs the same review" retrospective

> "We pushed a recovered fix that broke staging. We learned: even 'recovered' code needs the same review as new code. There is no shortcut."

**What they do well:** they treat *the act of recovery* as not implying any quality guarantee about *the recovered code*. The recovery proves "this content existed and was thought useful at one point"; it does not prove "this content is correct today."

**What we steal:** Phase 9 fresh-eyes runs ≥2 rounds on recovered content with the same rigor as on net-new code. Phase 8 per-apply gates run the project's actual test/typecheck/lint/UBS suite on every keeper; no exceptions. See [POLISH-BAR.md §"Per-apply gates"](POLISH-BAR.md#per-apply-gates).

**Where we diverge:** the Go team's review was *human PR review*. Ours is automated gates plus fresh-eyes prompts. We don't replace human review; the rationalization branch is the user's PR-equivalent for human review.

**Why:** [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms): "Per-apply gates are non-negotiable."

---

## §EX-13 — Stripe's safety-culture trio

> "Every destructive operation has: an explicit confirmation, a verbatim audit trail, and a recovery path. Without all three, the operation does not happen."
>
> — Stripe engineering blog (paraphrased)

**What they do well:** the three-part rule is a *gate*, not a guideline. Operations missing any of the three don't happen at all; they're refused at the wrapper.

**What we steal directly:** Phase 10 has all three: `⚠ CONFIRM` is the explicit confirmation, `cleanup_authorization.txt` is the verbatim audit trail, `refs/branch-rationalization-backup/*` + bundle is the recovery path. If any of the three is missing, Phase 10 refuses to run.

**Where we diverge:** Stripe enforces the trio at the *infrastructure* layer (every API call has authentication, audit logging, and reversibility). We enforce it at the *script* layer — `scripts/drop-retire-confirmed.sh` checks for the authorization file before running.

**Why:** [SKILL.md Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms): "Authorization is per-plan, verbatim, recorded."

---

## §EX-14 — Daniel Stenberg (curl) on triage discipline

> "Every reported issue has three possible verdicts: known, novel, or unfixable. The discipline is to classify quickly and act accordingly."

**What they do well:** rapid classification with a small, well-defined verdict set. Every incoming bug report exits triage with one of three labels in under a minute.

**What we steal:** the 11-verdict taxonomy ([TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md)) is similarly small and exclusive. Every branch and every worktree exits Phase 5 with exactly one verdict; ambiguity is captured in `unknown` and surfaced. No "kinda novel" — either there's evidence for novel-and-accretive or it's `unknown` and the user decides.

**Where we diverge:** curl's verdicts are *triage-only*; the action taken depends on the verdict but is decided per-issue. Ours has a per-verdict action mapped in the rubric (`already-merged` → `git branch -d`; `garbage` → `git branch -D` after authorization; `novel-and-accretive` → cherry-pick / squash-merge / rebase-and-merge per project style; etc.). Closer coupling between verdict and action because the action set is finite.

**Why:** [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) §"Verdicts".

---

## §EX-15 — Postgres committer discipline on irreversibility

> "Schema changes are forever. Every migration is reviewed five times before merge. The cost of a wrong migration vastly exceeds the cost of slow review."

**What they do well:** treat irreversible operations with proportionally more rigor. Reversible changes go through normal review; irreversible changes go through five rounds.

**What we steal:** Phase 10 (cleanup) is the only fully-irreversible-without-the-bundle phase, and it has the most gates: verbatim authorization, ordering by bucket, per-entry restate-before-execute, the bundle-must-exist precondition. Everything before Phase 10 lands on the rationalization branch — fully reversible by `git reset` or by re-running the skill.

**Where we diverge:** Postgres's "five reviews" is human reviewers. Ours is "five reversibility layers" (backup ref + object bundle + per-branch diff + per-branch format-patch + per-worktree dirty captures). Five-times-anything is the discipline; the something is what each project can practically deliver.

**Why:** [SAFETY-MODEL.md](SAFETY-MODEL.md) §"Five layers".

---

## §EX-16 — A Rust core team's commit policy

> "Every commit must explain why. The PR description explains the feature; the commit message explains the change."

**What they do well:** the *why* is non-negotiable. A commit message that only says *what* (which the diff already shows) is rejected.

**What we steal:** [COMMIT-MESSAGE-CRAFT.md](COMMIT-MESSAGE-CRAFT.md) requires every recovery commit to have three sections: context, why-it-didn't-already-land, how-it-was-recovered. Section 2 is the *why* in this skill's specific shape — the explanation of why this particular content is being folded onto the rationalization branch *now* rather than at the time it was originally branched.

**Where we diverge:** Rust's policy is enforced by reviewers at PR-time. Ours is enforced by the commit-message-author subagent at apply-time, with the rationalization branch as the user's review surface afterward.

**Why:** [COMMIT-MESSAGE-CRAFT.md](COMMIT-MESSAGE-CRAFT.md) §"Body structure".

---

## §EX-17 — Joe Armstrong on staged correctness

> "Make it work, make it right, make it fast — in that order. Anything else is premature."
>
> — Joe Armstrong (Erlang)

**What they do well:** the explicit ordering. Don't optimize before correctness; don't beautify before functionality.

**What we steal:** the phase ordering. Phase 1 makes it work (basic profile + inventory). Phases 3–8 make it right (bundle, triage, harmonization, per-apply gates). Phase 9 is the verification gate. Phase 10 is the cleanup. There is no "Phase 11 — make it faster" because correctness over speed for irreversible work; the skill's wall-time targets are documented but not optimized.

**Where we diverge:** Armstrong was talking about software in general; we apply the discipline to the skill's own pipeline.

**Why:** [PHASES.md](PHASES.md) phase ordering.

---

## §EX-18 — Anthropic's coding-agent guidance

> "Tools should fail loudly, never silently. A revert that didn't actually revert should be reported as such, not concealed."

**What they do well:** the failure mode is *visibility*. A tool that silently fails to do its job is worse than a tool that loudly refuses.

**What we steal:** every script in `scripts/` exits non-zero on any irreversible failure. Every Phase 8 apply that fails the per-apply gate is *reported* in `apply_log.tsv:gates_status`; nothing is silently skipped. Every conflict surface is written to `conflicts/branch_<slug>.context.md` with the reject path explicitly named. See [PHASES.md Phase 8](PHASES.md#phase-8-rationalization--apply-sequential-60240-min).

**Where we diverge:** the failure-loud principle is universal; the surface is skill-specific (TSV columns, conflict-context files, the handoff report).

**Why:** [SKILL.md "Anti-Patterns"](../SKILL.md#anti-patterns-never-do): refusing to silently bypass is a non-negotiable.

---

## §EX-19 — A Postgres committer on `EXPLAIN` discipline

> "If you don't `EXPLAIN` your query plan before optimizing, you're guessing. Measurement before action."

**What they do well:** measure first, decide second. The cost of a wrong optimization decision is high; the cost of running `EXPLAIN` is trivial.

**What we steal:** Phase 5 triage *measures* before classifying. FINGERPRINT extracts evidence; VERIFY-ON-CANONICAL searches for it. The verdict comes after the measurement, never before. "It looks superseded" is never an acceptable evidence string ([POLISH-BAR.md §"No phantom keepers"](POLISH-BAR.md#no-phantom-keepers)).

**Where we diverge:** Postgres's `EXPLAIN` is a single command. Ours is a chain (FINGERPRINT → APPLY-CHECK → VERIFY-ON-CANONICAL → optional same-signature sample → verdict). More steps because the unit of management is more complex.

**Why:** [EVIDENCE-CITATIONS.md](EVIDENCE-CITATIONS.md) §"Per-verdict required citations".

---

## §EX-20 — Brendan Gregg on observability

> "If you can't measure it, you can't improve it. Every system should have per-component metrics, not just overall health."

**What they do well:** observability is built in, not bolted on. Per-subsystem metrics tell you *where* the problem is, not just *that* there is one.

**What we steal:** the handoff report (Phase 11) emits per-bucket counts, per-verdict counts, per-source-branch keeper-attribution, harmonization-synthesis counts per file. Not just "X branches deleted" — "5 garbage, 12 already-merged, 8 superseded, 3 novel-and-accretive, 1 partially-novel, 2 dirty-worktree-only."

**Where we diverge:** Gregg's metrics are runtime (latency, throughput, error rate). Ours are run-summary (counts, attributions, timings). Different domain, same instrumentation discipline.

**Why:** [PHASES.md Phase 11](PHASES.md#phase-11-handoff--follow-ups-1020-min) — handoff report structure.

---

## How to use this exemplar bank

When designing a new operator card, a new failure-mode entry, or a tradeoff decision, find the closest exemplar and use its discipline as the prior. When the skill's behavior diverges, document why (the divergence is data, not noise).

When extending the skill, propose new exemplars from sources you trust. The exemplar bank should grow with the field.

The most-cited exemplars in this file are §EX-2 (kernel format-patch series — informs the bundle format), §EX-5 (Rust bors — informs merge-strategy detection and per-apply gates), §EX-8 (GitHub gh pr merge — informs project-style detection), and §EX-13 (Stripe trio — informs every destructive operation). Read those four most carefully; they are load-bearing for the skill's structure.
