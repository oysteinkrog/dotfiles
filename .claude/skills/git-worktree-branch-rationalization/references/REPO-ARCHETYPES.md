# Repo Archetypes — How Each Repo Shape Adjusts the Pipeline

Different repo shapes change the skill's defaults, the protection list, the harmonization risks, and the cleanup ordering. This file maps archetypes to their specific adjustments.

Adapted from [git-stash-janitor's REPO-ARCHETYPES.md](../../git-stash-janitor/references/REPO-ARCHETYPES.md). The branching workflow archetype set is *larger* than stash-janitor's because branches encode workflow conventions that stashes don't (release lines, GitFlow, trunk-based, etc.). Where stash-janitor's archetypes were mostly about *language ecosystem* (Cargo workspace, monorepo, polyrepo), this skill's archetypes are mostly about *branching model* and *deployment topology*.

> **Why:** Per [SKILL.md "Decision Tree"](../SKILL.md#decision-tree--should-the-skill-run): the skill's mode auto-selects from worktree count and branch count, but the *protection list*, *merge style*, and *harmonization rules* depend on the project's branching model. Inferring those wrong is how protected branches accidentally get triaged.

The archetype is detected at Phase 1 by `scripts/discover-project.sh`; the result lands in `project_profile.json:archetypes` (an array — a repo can be multiple archetypes simultaneously, e.g., GitFlow + monorepo + LFS).

---

## A1 — Solo project, single canonical branch

**Detection:** ≤2 contributors in `git shortlog -sn`; canonical detected as `main` or `master`; no `develop`, no `release/*` branches.

**Adjustments:** none beyond the defaults. Quick mode is usually appropriate; the user typically knows every branch they have. Phase 7 harmonization is rare (single contributor's branches usually don't collide on the same files in incompatible ways).

**Why:** the simplest case; the kernel runs as designed.

---

## A2 — Trunk-based, many short-lived branches

**Detection:** canonical is `main` or `trunk`; `git log --merges --oneline | wc -l` is small relative to total commit count (most history is linear); branches are typically <7 days old; `gh pr list --state merged` shows fast PR turnover.

**Adjustments:**
- **Most branches are already-merged.** Aggressive cleanup is safe; per [Axiom 17](../SKILL.md#the-rationalization-kernel-universal-axioms), `git cherry -v` will show all `-` lines for nearly all branches.
- The expected verdict distribution skews heavily to `already-merged` (50–80%) and `garbage` (10–20% — abandoned WIP).
- Phase 8 has fewer keeper applies because most branches were already merged via squash-PR.
- Phase 5 can run faster (the `git cherry -v` check is cheap and resolves most rows in a single comparison).

**Why:** trunk-based projects have intentional cleanup pressure already; this skill is the cleanup the user knows they should do but kept deferring. See [Rust bors EX-5](EXEMPLARS.md#ex-5--rusts-bors--homu-merge-queue) — bors-style merge queues plus trunk-based development means most merged content is patch-id-equivalent on canonical.

---

## A3 — GitFlow with `develop` + `main`

**Detection:** both `develop` and `main` (or `master`) exist as long-lived branches; `release/*` and `hotfix/*` branches present (or have existed historically); `feature/*` branches feed `develop`, not `main`.

**Adjustments:**
- **Auto-protect both `develop` AND `main`.** Per [SKILL.md "Inputs"](../SKILL.md#inputs), the canonical detection finds *one* default; for GitFlow, we add `develop` to the protection list automatically and surface this to the user at Phase 4.
- **Canonical for the rationalization branch is `develop`, not `main`.** Feature branches in GitFlow target `develop`; rationalization should land there. The user can override at Phase 0 if they're unusually rationalizing toward `main` directly.
- **Auto-protect every `release/*` and every `hotfix/*` branch.** These are workflow-protected by convention.
- `feature/*` branches are the rationalization target population.
- Phase 5 triage uses `develop` as the comparison branch for `git cherry -v`, NOT `main`.

**Why:** [Mozilla EX-4](EXEMPLARS.md#ex-4--mozillas-branch-protection--dependabot-conventions) — `release/*` is the canonical example of workflow-protected branches.

---

## A4 — Release-train (long-lived `release/N.x` branches)

**Detection:** multiple long-lived `release/*` branches with semver-style names (`release/14.x`, `release/15.x`, `release/16.x`); each has commits absent from canonical; canonical (`main`) is the active development line.

**Adjustments:**
- **Auto-protect every `release/*`.** Each one is a maintenance line.
- **Rationalize only feature branches** — `feature/*`, `wip/*`, `agent-*`, `cc-*`, etc.
- **The canonical for the rationalization branch is `main`** (the active line); release branches are out of scope for rationalization.
- The handoff report explicitly tells the user: "If any of these recoveries also belong on `release/N.x`, that's a separate cherry-pick you run yourself; the skill won't backport for you."
- Phase 5 triage uses `main` as the comparison branch; some feature branches may show "all `-` on main" (already-merged) but still have content not on `release/N.x` — that's not the skill's problem.

**Why:** [LLVM EX-6](EXEMPLARS.md#ex-6--llvms-release-branch-line) — release lines are sacrosanct; rationalization happens on the active development line.

---

## A5 — Monorepo (Turborepo / Nx / pnpm workspaces / Yarn workspaces / Cargo workspace)

**Detection:** root `package.json` with `"workspaces"`, `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, OR root `Cargo.toml` with `[workspace]` and `members = [...]`.

**Adjustments:**
- Phase 1: enumerate packages; identify which packages each branch touches (per `branches.tsv:touched-files`). A branch may touch one package, several, or all.
- Phase 5: a branch's fingerprint may span multiple packages; classify per-package and aggregate.
- **Phase 7 harmonization is per-file, but synthesis must respect subproject boundaries.** A harmonized synthesis for `packages/api/src/handler.ts` should not silently pull a refactor from `packages/web/src/page.tsx`'s branch. The harmonization plan groups variants per-file and the cross-package coherence check is on the planner.
- Phase 8 quality gates: scoped per-package when possible:
  - Turborepo: `turbo run test --filter=<package>` for the touched packages
  - Nx: `nx affected:test --base=<rationalization-branch-base>`
  - pnpm: `pnpm --filter <package> test` for each touched package
  - Cargo workspace: `cargo test -p <crate>` per touched crate
- Phase 9 fresh-eyes: scope per-package; reviewing the whole monorepo at once dilutes the signal.

**Why:** [Cargo workspace and Turborepo conventions](https://turbo.build/repo/docs) — gates that run only against affected packages catch regressions faster and let larger keeper sets land.

---

## A6 — Submodules

**Detection:** `.gitmodules` file at root, OR any directory contains a `.git` *file* (not directory) with `gitdir: ...` content.

**Adjustments:**
- Phase 0: confirm with user — operating against the *parent* repo's branches/worktrees, against a *submodule's*, or both? Default: parent only; submodules are out-of-scope unless explicitly opted-in.
- Phase 2 inventory: per-worktree submodule init state varies. `git worktree add` does NOT auto-init submodules; some worktrees may have submodules cloned, others not. Capture the submodule state in `worktrees.tsv:submodules` (`init/uninit/conflict/n-a`).
- Phase 3 bundle: back up `.gitmodules` plus the per-worktree submodule pointer state at the moment of bundle creation. The submodule's *contents* are not in the bundle (they live in the submodule's own `.git/`); the bundle preserves the parent's pointer to a specific submodule SHA.
- Phase 10 cleanup: removing a worktree leaves the submodule cache untouched; `.git/worktrees/<id>/` IS pruned. Removing a branch leaves any submodule pointer the branch added in the unreachable-objects pile (recoverable from backup ref + bundle).
- Handoff: "to update parent repo's submodule pointer after rationalization: `git -C <parent> submodule update --init` if the rationalization branch's tip points at a different submodule SHA."

**Why:** submodules add a unit-of-management mismatch (parent commits reference submodule SHAs); without explicit handling, the bundle can claim coverage it doesn't have.

---

## A7 — LFS-managed binaries

**Detection:** `git config --get-all filter.lfs.process` is non-empty, OR `.gitattributes` has `filter=lfs` lines.

**Adjustments:**
- Phase 3 bundle: per-branch diffs capture LFS *pointer files*, not the underlying blobs. The pointer-file content is small text like `version https://git-lfs.github.com/spec/v1\noid sha256:...\nsize ...`. Recovery via `git apply <bundle>/.../diff-vs-merge-base.diff` reproduces the pointer; the actual binary requires `git lfs fetch` against an accessible LFS server.
- Phase 8: applying an LFS-pointer diff requires `git lfs pull` after; the rationalization branch may have stale pointers temporarily.
- Phase 10: LFS objects are *not* deleted by `git branch -d`/`-D`; they live in the LFS server's storage and are governed by the LFS server's retention policy (typically configurable on GitHub/GitLab). The skill's cleanup doesn't touch LFS storage.
- Handoff: "ensure `git lfs fetch` works against your LFS remote before relying on recovered LFS file content; the bundle's diffs preserve the pointer hash but not the blob."

**Why:** LFS adds a *second* persistence layer the bundle can't capture without LFS-server credentials; explicit acknowledgment in the recovery story prevents silent loss.

---

## A8 — Many-worktrees-per-PR workflow

**Detection:** ≥10 worktrees AND ≥80% of worktrees are pinned to branches matching `feature/*` or `pr/*` or `<user>/*`; the user mentions "PR per worktree" or the project has a documented workflow describing this pattern.

**Adjustments:**
- **Auto-protect every PR-pinned worktree** by default; surface the list to the user at Phase 4 and ask explicit per-worktree confirmation before pruning.
- The `feature/*` worktrees may be open PRs where the user is actively pushing; pruning them would lose the working-tree state of in-flight work.
- Phase 4 confirmation prompt becomes more elaborate: "These N worktrees correspond to open PRs. For each, confirm: keep / prune-but-keep-branch / prune-and-delete-branch."
- The handoff report explicitly enumerates which PR-worktrees were preserved.

**Why:** [Chromium EX-3](EXEMPLARS.md#ex-3--chromiums-many-bot-worktree-pattern) — worktree-per-CL is a real workflow; pruning it out from under the user is a footgun.

---

## A9 — Bare-then-clone CI repo

**Detection:** path matches `/__w/<repo>/...` (GitHub Actions runner), `/cloudbuild/...` (Cloud Build), `/builds/...` (GitLab), OR `git config core.bare` is `true`.

**Adjustments:**
- **REFUSE.** Per [WHEN-NOT-TO-USE.md](WHEN-NOT-TO-USE.md): a CI host should have minimal local state; if it has many local branches or worktrees, the residue is evidence of something else wrong (a broken cleanup hook, a leftover from a debug session). Investigate the cause, don't triage the symptom.
- The skill needs a working tree to apply diffs into; bare repos have none.
- Suggest: "Clone into a working dir, run skill there, then push the rationalization branch."

**Why:** [SKILL.md "When NOT to Use"](../SKILL.md#when-not-to-use-this-skill) — bare repos are out of scope.

---

## A10 — Multi-remote (origin + github + gitlab + others)

**Detection:** `git remote -v` lists ≥2 distinct remotes; the user is mirroring or migrating between hosts.

**Adjustments:**
- **The bundle's object pack is per-local-namespace** (`refs/branch-rationalization-backup/*`). Remote tracking refs (`refs/remotes/origin/*`, `refs/remotes/gitlab/*`) are advisory inputs, not targets.
- **Remote cleanup is out of scope** by default per [Axiom 15](../SKILL.md#the-rationalization-kernel-universal-axioms); even more strictly so for multi-remote (a branch may exist on remote A but not on remote B; rationalization on local doesn't reconcile that).
- Phase 5 `git cherry -v` uses the *local* canonical, not any remote's. If the user wants to compare against `origin/main`, they specify that at Phase 0.
- Handoff: "Multi-remote detected. The skill operated against your *local* canonical. If you want to push the rationalization branch to all remotes, that's per-remote: `git push origin branch-rationalization-<DATE>; git push gitlab branch-rationalization-<DATE>; ...`."

**Why:** the skill's safety story assumes a single-remote mental model; multi-remote requires explicit acknowledgment that the bundle covers local objects only.

---

## A11 — Detached HEAD on the active worktree

**Detection:** `git status` shows `HEAD detached at <sha>` on the user's CWD.

**Adjustments:**
- Phase 0: ask user to checkout canonical (or any branch) first.
- The rationalization branch logic needs a base; detached HEAD doesn't supply one consistently.
- This is a soft-warning: if the user *insists* (rare), they pass `--detached-ok` and the skill creates the rationalization branch from canonical's tip explicitly, leaving the user's detached HEAD untouched.

**Why:** [SKILL.md "Decision Tree"](../SKILL.md#decision-tree--should-the-skill-run) lists detached HEAD as a soft-warning.

---

## A12 — Repo with pre-commit hooks (husky / lefthook / pre-commit / git native)

**Detection:** `.husky/`, `.git/hooks/pre-commit` (executable), `lefthook.yml` / `lefthook.yaml`, `.pre-commit-config.yaml`.

**Adjustments:**
- Phase 1: profile records hook framework in `project_profile.json:hooks`.
- Phase 8: NEVER bypass hooks (`--no-verify`). Per [SKILL.md "Anti-Patterns"](../SKILL.md#anti-patterns-never-do): "Bypass pre-commit hooks (`--no-verify`)."
- If a hook fails on a recovery commit, surface the failure with the hook's output; let user decide whether to fix and re-run, or skip the keeper.
- The per-apply gate (Axiom 13) effectively re-runs many of the same checks; a hook that runs `cargo fmt` is redundant with the gate but not harmful.

**Why:** [Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms) plus AGENTS.md "Mandatory explicit plan" — bypassing hooks is bypassing the user's policy.

---

## A13 — Repo with required signed commits

**Detection:** `git config commit.gpgsign` is `true`, OR repo's CI requires signed commits, OR `.gitattributes` references signing.

**Adjustments:**
- Phase 8: cherry-picks and squash-merges sign automatically if user's GPG/SSH key is configured.
- If signing fails, surface; never `--no-gpg-sign`.
- Cherry-picking a signed commit produces a signed cherry-picked commit when the local key is configured; the original signature is *not* preserved (the cherry-pick is a new commit), but the new commit is signed by the local key.

**Why:** [Tor EX-7](EXEMPLARS.md#ex-7--tors-hardened-release-line-discipline) — the signing chain is part of the project's safety culture; the skill respects it.

---

## A14 — Repo with CODEOWNERS / branch protection rules

**Detection:** `.github/CODEOWNERS` (or `docs/CODEOWNERS`, `.gitlab/CODEOWNERS`); branch-protection rules visible via `gh api`.

**Adjustments:**
- Phase 11 handoff: include "the rationalization branch will need PR approval from `<codeowners>` because it touches paths under their ownership."
- The skill never pushes; the user opens the PR.
- For Council mode, the planner can fan-out a CODEOWNERS-aware reviewer subagent that checks each Phase 8 keeper against the CODEOWNERS rules and flags expected reviewers.

**Why:** large monorepos have CODEOWNERS as the gating mechanism; surfacing the expected reviewer set helps the user plan the PR review.

---

## A15 — Repo with very-old git (<2.20)

**Detection:** `git --version` returns < 2.20.

**Adjustments:**
- Phase 0: warn; recommend upgrade.
- `git worktree` semantics changed in 2.5 (introduced) and 2.20 (porcelain output stabilized for `git worktree list --porcelain`); below 2.20 the `--porcelain` output is missing some fields the inventory relies on (`locked`, `prunable`).
- Soft-fall-back: parse the human-readable output too, but flag lower confidence on `worktrees.tsv:locked` and `prunable` columns.

**Why:** [SKILL.md "Decision Tree"](../SKILL.md#decision-tree--should-the-skill-run) lists very-old git as a soft-warning.

---

## A16 — Repo with custom merge strategies / drivers

**Detection:** `.gitattributes` has `merge=` rules (e.g., `merge=ours`, custom drivers).

**Adjustments:**
- Phase 8: the merge strategy may affect 3-way apply during cherry-pick; if applies fail unexpectedly, check `.gitattributes` for path-specific merge drivers.
- Custom drivers can resolve content the skill thinks is conflicting; surface unexpected clean-applies that match a `merge=` rule and confirm with user that the resolution is intentional.

**Why:** custom merge drivers are rare but load-bearing where they exist; the skill respects but doesn't second-guess them.

---

## A17 — Repo with sparse-checkout

**Detection:** `git config core.sparseCheckout` is `true`, OR `.git/info/sparse-checkout` exists with non-trivial content.

**Adjustments:**
- Phase 3 bundle: diffs may reference paths NOT in the current sparse-checkout cone; verification still works because we use SHA-based ref comparison.
- Phase 8: applying may fail because the file isn't materialized; surface to user with "expand sparse-checkout to include `<path>`?" suggestion.
- Worktrees can have *different* sparse-checkout configurations; capture per-worktree in `worktrees.tsv:sparse_cone` for Comprehensive mode.

**Why:** sparse-checkout adds a path-visibility layer the apply step must respect.

---

## A18 — Throwaway / scratch clone

**Detection:** path matches `/tmp/...` or user identifies it as throwaway.

**Adjustments:**
- Phase 0: warn the bundle goes to `/tmp/` too (also throwaway); if user wants persistent recovery, point at a non-`/tmp` path.
- Otherwise: run normally.

**Why:** the skill is happy to run on throwaway paths; the user just shouldn't expect the bundle to survive a reboot.

---

## A19 — Repo with CASS / NTM / agent infrastructure visible

**Detection:** `cass health` succeeds; NTM panes active; beads + Mail configured; `br` available.

**Adjustments (all optional enrichments — none required):**
- Phase 0.5: CASS mining enabled (if `cass` is healthy) — search prior agent sessions for context on individual branches, especially `agent-*` branches.
- Phase 5: NTM swarm topology *available* if user wants it; default remains in-session parallel Task subagents.
- Phase 7: harmonization-planner can consult `cass search <branch-name>` for prior agent context.
- Phase 11: post-run `bv` triage if available.
- Phase 11: file beads issue (`br create`) at run-start; close at handoff.

The skill works fine in a vanilla Claude Code session with none of these tools. They are detected and used opportunistically when present.

**Why:** the agent-swarm aftermath is precisely the scenario this skill targets; CASS mining helps reconstruct intent for orphan branches when their authoring agent is no longer running.

---

## A20 — Mid-rebase / mid-merge / mid-cherry-pick / mid-bisect on the active worktree

**Detection:** `git status` shows `interactive rebase in progress`, unmerged paths, `BISECT_LOG` exists, or `.git/CHERRY_PICK_HEAD` exists.

**Adjustments:**
- **REFUSE.** Per [WHEN-NOT-TO-USE.md](WHEN-NOT-TO-USE.md): the skill needs a clean checkout state to snapshot from on the active worktree.
- Other worktrees may have their own in-flight state — that's captured in Phase 2 inventory but the skill won't disturb them. The blocker is *only* the active worktree being mid-operation.

**Why:** [SKILL.md Phase 0](../SKILL.md#decision-tree--should-the-skill-run) — pre-conditions list this explicitly.

---

## Detection Cheat-Sheet (Phase 1)

```bash
detect_archetype() {
  local p="$1"
  local types=()

  # A2 trunk-based vs A3 GitFlow
  if git -C "$p" show-ref --verify --quiet refs/heads/develop; then
    types+=(gitflow)
  fi

  # A4 release-train
  if [[ $(git -C "$p" for-each-ref --format='%(refname:short)' refs/heads/release/ | wc -l) -ge 2 ]]; then
    types+=(release-train)
  fi

  # A5 monorepo
  jq -e '.workspaces' "$p/package.json" >/dev/null 2>&1 && types+=(npm-workspaces)
  [[ -f "$p/pnpm-workspace.yaml" ]] && types+=(pnpm-workspaces)
  [[ -f "$p/turbo.json" ]] && types+=(turborepo)
  [[ -f "$p/nx.json" ]] && types+=(nx)
  grep -q '\[workspace\]' "$p/Cargo.toml" 2>/dev/null && types+=(cargo-workspace)

  # A6 submodules
  [[ -f "$p/.gitmodules" ]] && types+=(submodules)

  # A7 LFS
  git -C "$p" config --get-all filter.lfs.process >/dev/null 2>&1 && types+=(lfs)

  # A8 many-worktrees-per-PR (heuristic)
  local wt_count
  wt_count=$(git -C "$p" worktree list --porcelain | grep -c '^worktree ')
  if (( wt_count >= 10 )); then
    local pr_pinned
    pr_pinned=$(git -C "$p" worktree list --porcelain | awk '/^branch refs\/heads\/(feature|pr)\//' | wc -l)
    if (( pr_pinned * 5 >= wt_count * 4 )); then  # >=80%
      types+=(many-worktrees-per-pr)
    fi
  fi

  # A9 CI checkout
  case "$p" in
    /__w/*|/cloudbuild/*|/builds/*) types+=(ci-checkout) ;;
  esac
  [[ "$(git -C "$p" config core.bare 2>/dev/null)" == "true" ]] && types+=(bare)

  # A10 multi-remote
  if [[ $(git -C "$p" remote | wc -l) -ge 2 ]]; then
    types+=(multi-remote)
  fi

  # A12 hooks
  [[ -d "$p/.husky" ]] && types+=(husky)
  [[ -f "$p/lefthook.yml" || -f "$p/lefthook.yaml" ]] && types+=(lefthook)
  [[ -f "$p/.pre-commit-config.yaml" ]] && types+=(pre-commit)

  # A13 signed commits
  [[ "$(git -C "$p" config commit.gpgsign 2>/dev/null)" == "true" ]] && types+=(signed-commits)

  # A14 CODEOWNERS
  [[ -f "$p/.github/CODEOWNERS" || -f "$p/docs/CODEOWNERS" || -f "$p/.gitlab/CODEOWNERS" ]] && types+=(codeowners)

  # A17 sparse-checkout
  [[ "$(git -C "$p" config core.sparseCheckout 2>/dev/null)" == "true" ]] && types+=(sparse)

  # A19 agent infra
  command -v cass >/dev/null 2>&1 && types+=(cass-available)
  command -v ntm >/dev/null 2>&1 && types+=(ntm-available)
  command -v br >/dev/null 2>&1 && types+=(beads-available)
  command -v bv >/dev/null 2>&1 && types+=(bv-available)

  printf '%s\n' "${types[@]}"
}
```

The result feeds `project_profile.json:archetypes` and informs subagent selection (Phase 1 produces the profile; Phases 4, 7, 8 read it).

---

## Multi-archetype interactions

A repo can match multiple archetypes simultaneously. Common combinations and their compounded adjustments:

| Combination | Compounded effect |
|-------------|-------------------|
| GitFlow + monorepo (A3 + A5) | Auto-protect `develop` AND `main` AND every `release/*`; rationalize toward `develop`; per-package gates |
| Release-train + LFS (A4 + A7) | Auto-protect every `release/*`; LFS-pointer-aware bundle; LFS retention warning in handoff |
| Submodules + sparse-checkout (A6 + A17) | Per-worktree submodule state; per-worktree sparse cone; the apply step may need *both* submodule init AND sparse expansion |
| Many-worktrees-per-PR + signed commits (A8 + A13) | Auto-protect every PR-worktree; per-keeper signing on the rationalization branch |
| GitFlow + codeowners + signed (A3 + A14 + A13) | Maximum protection set; handoff explicitly names the codeowners group expected to review the rationalization-branch PR |

For Comprehensive runs that match ≥3 archetypes, escalate to Council mode automatically — the harmonization complexity scales nonlinearly with archetype count.

**Why:** the asupersync 47-worktree+213-branch motivating scenario per [SKILL.md "Source Corpus"](../SKILL.md#source-corpus) is GitFlow + cargo-workspace + agent-infra (A3 + A5 + A19); the skill's design accommodates that intersection by default.
