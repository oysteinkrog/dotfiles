---
name: git-worktree-branch-rationalization
description: >-
  Rationalize a repo's accumulated git worktrees and local branches down to a
  canonical line plus protected branches, harmonizing the strongest content from
  every variant onto a staging branch before any destructive cleanup. Use when
  a project has piled up local branches or linked worktrees ("213 branches, 47
  worktrees", agent-swarm aftermath, "rationalize my branches", "kill all
  worktrees save what's worth saving", "merge what's worth merging and delete
  the rest", or "branch archaeology").
---

<!-- TOC: Quickref | Inputs | What This Produces | Workspace Layout | Up-Front Confirmations | Skill Bootstrap | The Phase Loop | Mode Variants | Parallelism | Operator Library | The Polish Bar | Failure Modes | Anti-Patterns | When NOT to Use | Pre-Flight Checklist | Reference Index | Scripts | Subagents | Self-Test -->

# Git Worktree + Branch Rationalization — Inventory, Harmonize, Land, Prune

> **First action for a fresh agent.** If you have NOT yet introduced the run to the user, jump to [Up-Front Confirmations](#up-front-confirmations-ask-before-starting) and read [`assets/intake-prompt.md`](assets/intake-prompt.md) verbatim. If the user has already authorized inputs and the workspace `.worktree_branch_rationalization_workspace/` exists, look at the artifacts present (`project_profile.json` → Phase 1 done; `branches.tsv`+`worktrees.tsv` → Phase 2 done; `bundle_verification.log` clean → Phase 3 done; `triage.tsv` frozen → Phase 6 done; `harmonization_plan.md` reviewed → Phase 7 done; `apply_log.tsv` populated → Phase 8 in progress; `cleanup_authorization.txt` present → Phase 10 authorized) and resume from the next phase using [PHASES.md](references/PHASES.md). When in doubt: re-running Phase 0/1/2 is idempotent (within ~7 days) and safe; Phase 3 reuses an existing valid bundle; Phases 5–9 are reapply-until-quiet; Phases 6, 7, 7.5, 9.5, and 10 are user-gated and must NEVER be auto-advanced past their gate.

> **The One Rule.** Every worktree removal and every local branch deletion must be reversible **byte-for-byte** at the moment it's authorized. Backup refs in `refs/branch-rationalization-backup/*` plus a `git bundle` over the whole namespace plus per-worktree dirty-state captures are the gold standard; per-branch unified diffs and `format-patch` series and untracked-file tarballs are the human-readable backstop. If the bundle isn't in place and verified, nothing destructive runs. Period.

> **Scope.** A repo with two simultaneously-bloated namespaces — a stack of `git worktree` checkouts (typically 5–80 of them, often gigabytes each) and a list of local branches (typically 30–500), accumulated by an agent swarm or a long-running development line — needs to be triaged into `protected | already-merged | superseded | novel-and-accretive | partially-novel | novel-but-stale | divergent-refactor | dirty-worktree-only | garbage`, the genuinely useful pieces folded into a *rationalization branch* cut from canonical (NOT directly into canonical), competing variants of the same files **harmonized into a best-of-all-worlds synthesis** rather than picked-or-dropped, and the rest pruned only after explicit verbatim user authorization.

> **The conceptual leap from git-stash-janitor.** A stash is a single diff: pick or drop. Branches collide on the same files in incompatible ways. The job of this skill is NOT "pick the right branch"; it is "recover the strongest current implementation of every file by inspecting every variant, identifying each part's intent, and synthesizing them on top of canonical's architecture." That is the **◇ HARMONIZE** operator and the **harmonization plan** in Phase 7. Without it, this skill is just stash-janitor with extra steps.

---

## THE RATIONALIZATION KERNEL (Universal Axioms)

<!-- KERNEL_START v1.0 -->

Almost every serious branch-and-worktree-rationalization decision should be stress-tested against these axioms. They are default truths, not mindless scripts: if an edge case seems to break one, explain why before treating it as an exception.

**Axiom 0 — Two units of management, one safety story.**
Worktrees are filesystem checkouts; branches are refs. They have different smells, different inventories, different removal mechanics, and different failure modes — but they share a single recovery bundle and a single verbatim-authorization gate. Inventory each separately (Phase 2 produces *both* `worktrees.tsv` and `branches.tsv`); reconcile them in one bundle (Phase 3); destroy them in one gated cleanup (Phase 10).

**Axiom 1 — Harmonize, don't pick.**
For any file touched by more than one non-protected branch, the job is NOT to choose between competing variants. The job is to inspect every variant (canonical's, each branch's, each dirty worktree's), reason about each part's intent, and synthesize the strongest current implementation on top of canonical's architecture. Output: best-of-all-worlds. This is the cognitive move stash-janitor doesn't have to make. The harmonization plan (Phase 7, `harmonization_plan.md`) names which hunks come from which branch and why.

**Axiom 2 — One coherent recovery story is told by every artifact.**
Backup refs (`refs/branch-rationalization-backup/<slug>`) + the git object bundle (`<bundle>/object-bundle.pack`) + per-branch diffs + per-branch format-patch series + per-worktree dirty-state captures + meta files + index TSV + README must point at the same SHAs and the same paths, in the same order, with byte-equality verified AND a `git bundle list-heads` round-trip verified. Silos produce the deepest failures.

**Axiom 3 — Plan for irreversibility first, classification second.**
The `⬡ BUNDLE` operator (Phase 3) is a hard gate before any destructive logic runs. An incorrect verdict is recoverable; an unrecorded removal is not. Build the safety net first — backup refs, object bundle, per-worktree dirty-state captures — *then* triage.

**Axiom 4 — Beneficiary-style coherence: all five layers tell the same story.**
The five reversibility layers (backup ref + object bundle + per-branch diff/format-patch + per-worktree dirty-state archive + meta + index entry) must all reflect the same content. If a Phase 3 byte-equality check disagrees on even one entry, the run is unsafe — halt.

**Axiom 5 — `main` is not the universal default.**
Many projects use `master`, `develop`, `trunk`, `default`, `release/2.x`. Detect canonical via `git symbolic-ref refs/remotes/origin/HEAD` first, then `git config init.defaultBranch`, then a heuristic against the actual ref list. **Never** assume.

**Axiom 6 — Land on a rationalization branch, not on canonical.**
All Phase 8 applies land on `branch-rationalization-<YYYY-MM-DD>` cut from canonical's tip. The user merges or cherry-picks from there at their own pace. Landing 200 branches' worth of recovered content directly on canonical in one shot is exactly the kind of mass mutation that should never happen without human review.

**Axiom 7 — `git format-patch` IS valid for branches; it is NOT for stashes.**
A branch is a normal commit chain — `git format-patch <merge-base>..<branch>` produces a clean ordered series. If you came from git-stash-janitor, do not generalize the "format-patch is wrong" rule. The bundle's `format-patch/*.patch` files are part of the recovery story for branches and have no analogue for stashes. The `BUNDLE-FORMAT-SPEC.md` README cross-links this so future readers don't reach the wrong conclusion.

**Axiom 8 — `git branch -d` over `git branch -D` whenever possible.**
Lowercase `-d` refuses to delete branches that are not fully merged into the current `HEAD`. After Phase 8 lands every keeper onto the rationalization branch, every "applied-keeper" branch IS fully merged from that branch's perspective — `-d` will succeed. Branches the user explicitly acknowledges as unmerged-and-discardable use `-D`. Mixing them up in a script is forbidden; the refusal is a built-in safety check.

**Axiom 9 — Worktrees are removed first, branches second.**
A worktree pinned to a branch protects that branch from `git branch -d` (the branch is "checked out" elsewhere). Removing the worktree first frees the branch. Order: prune non-protected worktrees → free their branches → run `git branch -d`/`-D` per the cleanup plan. Never run `git worktree prune` as a substitute for explicit `git worktree remove` — `prune` only cleans up admin metadata for worktrees already deleted out-of-band.

**Axiom 10 — Mass-delete primitives are forbidden.**
No `git branch | xargs git branch -D`. No `git for-each-ref refs/heads | … -D`. No `find /data/projects -name "*-wt-*" -exec rm -rf`. Every removal is individual, restated verbatim before execution, and logged. The only acceptable batching is: build the list, present it, get verbatim authorization for the *plan*, then iterate the list one entry at a time with the verbatim ref restated for each.

**Axiom 11 — `rm -rf <worktree-path>` is forbidden; `git worktree remove` is the structured operation.**
DCG blocks `rm -rf` and we don't fight it. `git worktree remove <path>` refuses on dirty worktrees — that refusal is a feature. Force-remove (`--force`) only when the dirty state has been archived in the bundle AND the user has explicitly OK'd losing it. The currently-active worktree (the user's CWD) is NEVER removed by the skill; the user removes that one themselves from a different working directory after the run completes.

**Axiom 12 — Concurrent agents' working-tree changes in any worktree are normal.**
Per AGENTS.md "Note for Codex/GPT-5.5", treat working-tree drift in any worktree as if you made it. Snapshot once at Phase 0; re-snapshot before each destructive operation; never stash, revert, or overwrite a parallel agent's work. Do not surprise the user with prompts about drift you didn't cause.

**Axiom 13 — Per-apply gates are non-negotiable.**
Run the project's actual `test`, `typecheck`, `lint`, `ubs` after every Phase 8 apply (cherry-pick, squash-merge, rebase-and-merge, harmonized-synthesis), not just at the end. Compounding errors across recoveries are an order of magnitude harder to debug than per-keeper failures.

**Axiom 14 — Authorization is per-plan, verbatim, recorded.**
Every destructive phase requires the user to type a phrase that quotes a literal command from the plan (per AGENTS.md "Mandatory explicit plan"). The verbatim text is recorded in `cleanup_authorization.txt` with a UTC timestamp. If that file doesn't exist, the action did not happen.

**Axiom 15 — Remote cleanup is out of scope by default.**
The skill never runs `git push --delete`, `git push --force`, or any remote-mutating command. Remote tracking refs are advisory inputs, not targets. If the user wants remote cleanup, they type the `git push --delete origin <branch>` commands themselves; the skill at most prepares the list for them to review.

**Axiom 16 — Same-name on canonical is not always supersession.**
A function `redact_secrets` on a branch and on canonical may have different signatures or different defensive checks. Always sample same-signature on a few introduced symbols before classifying `superseded`. When ≥30% of sampled signatures diverge, flip the verdict to `divergent-refactor` (a candidate input to harmonization) and surface to user.

**Axiom 17 — `git cherry -v` is the canonical "is this content already on canonical" check.**
Patch-id equivalence detects squash-merged and rebase-landed content even when SHAs differ. If `git cherry -v <canonical> <branch>` shows all `-` lines, the content is on canonical even though the commit graph doesn't show ancestry. Don't be fooled by SHA divergence into thinking content is novel when it isn't.

**Axiom 18 — Drop the bundle only at the user's pace.**
DCG correctly blocks `rm -rf` on the bundle. The skill is *designed* never to need this command. Bundle deletion is a manual decision after the user is sure nothing was lost (typically 1–4 weeks).

<!-- KERNEL_END v1.0 -->

These 19 axioms compose: Axiom 3 + Axiom 4 produce the byte-equality + bundle-round-trip gate; Axiom 9 + Axiom 11 produce the worktree-first ordering of cleanup; Axiom 7 + Axiom 17 produce the "use cherry, not log" rule for already-merged detection; Axiom 1 + Axiom 6 produce the rationalization-branch-as-staging-area pattern that lets harmonization happen without touching canonical. When you find yourself wanting to break one, slow down and check whether you've actually identified an exception or whether the kernel is right.

---

## Decision Tree — Should the Skill Run?

```
W = git worktree list | wc -l   (excluding the main repo entry)
B = git branch | wc -l           (local branches, excluding canonical)

├── W < 2 AND B < 5
│     └── Suggest manual inspection (`git branch -vv` + `git worktree list`); skill is overkill
│
├── 2 ≤ W < 5 AND/OR 5 ≤ B < 30
│     └── Quick mode (single-agent, ~15-30 min)
│
├── 5 ≤ W < 20 AND/OR 30 ≤ B < 100
│     └── Standard mode (Pair or Squad tier; ~30-90 min)
│
├── 20 ≤ W AND/OR 100 ≤ B
│     └── Comprehensive mode (Squad/Swarm; ~2-6 h)
│
└── B ≥ 200 AND/OR file collisions across ≥10 branches
      └── Comprehensive + Council tier (12+ workers, multi-model triangulation,
          dedicated harmonization-planner subagent)

Pre-conditions (refuse if any fail):
  - git work tree (not bare)
  - has commits on canonical
  - not mid-rebase / merge / cherry-pick / revert / bisect on the active worktree
  - writable filesystem

Soft-warnings (proceed but flag):
  - detached HEAD on the active worktree (need rationalization-branch base)
  - working tree non-empty in any worktree (concurrent agents per AGENTS.md — don't disturb)
  - no remote (push instructions degrade gracefully)
  - very old git (<2.20 — `git worktree` semantics changed)
  - locked worktrees on stale paths
  - branches with `[gone]` upstream (have unique commits — don't auto-prune)
```

See [WHEN-NOT-TO-USE.md](references/WHEN-NOT-TO-USE.md) for the full refusal matrix.

---

## Quickref

| Input | Effect | Guarantees |
|-------|--------|------------|
| **Project path** (cwd, absolute path, or git URL → clone to `/tmp/`) | Skill reads `AGENTS.md` / `CLAUDE.md` / `README.md`, detects canonical branch, build/test/lint commands, branching model, merge style, protected-by-convention patterns; written to `project_profile.json` | No assumptions — `main` is **not** assumed; canonical is detected from `git symbolic-ref refs/remotes/origin/HEAD` first, then heuristics |
| **Worktree count + branch count** reported up front | User confirms before any work; mode auto-selects | The user always knows the magnitude before the run starts |
| **Initial protection list** (Phase 0) **+ inventory-aware confirmation** (Phase 4) | User flags keep-forever items pre-inventory and reconfirms post-inventory; auto-protects `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`, the canonical branch, the currently-checked-out branch | No protected branch ever enters the rationalization pipeline |
| **Recovery bundle** at `<project-parent>/<basename>-branch-worktree-archive-<YYYY-MM-DD>/` | `refs/branch-rationalization-backup/<slug>` per branch, `object-bundle.pack` over the whole backup namespace, per-branch diffs + format-patch series, per-worktree staged/unstaged/untracked captures, meta files, `index.tsv`, README | After Phase 3 every removal is reversible via `git branch <name> refs/branch-rationalization-backup/<slug>` OR `git fetch <bundle>/object-bundle.pack <slug>` OR `git apply <bundle>/branches/<slug>/diff-vs-merge-base.diff` OR `git am <bundle>/branches/<slug>/format-patch/*.patch`; worktree dirty state recoverable via the captured staged/unstaged diffs + untracked tarball |
| **Triage TSV** (`triage.tsv`) — one row per branch and per worktree | User reviews, may override individual verdicts; only then does Phase 7 run | No branch is deleted, no worktree is removed, without the user signing off on its verdict |
| **Harmonization plan** (`harmonization_plan.md`) — per-file variant matrix for files touched by ≥2 branches | User reviews BEFORE Phase 8 mutates anything; the plan explicitly cites which hunks come from which branch and why each one was chosen (or why a synthesis combines hunks from multiple variants) | Best-of-all-worlds synthesis instead of pick-or-drop |
| **Rationalization branch** `branch-rationalization-<YYYY-MM-DD>` cut from canonical's tip | All Phase 8 applies land here — never directly on canonical unless `--land-on-canonical` was explicitly requested | The user gets a reviewable integration branch they can gate-check, merge, or cherry-pick from at their own pace |
| **Per-keeper apply** — cherry-pick / squash-merge / rebase-and-merge / harmonized-synthesis-via-Edit → run real project gates → focused commit | Quality gates run on **every** apply; reapplied keepers re-fingerprint downstream candidates so already-superseded ones flip verdict | Compounding errors are caught per-apply, not at the end |
| **Destructive cleanup** (gated on explicit verbatim authorization) | Worktree removal first (`git worktree remove <path>`, then `git worktree prune` for residual metadata), then `git branch -d`/`-D` per branch in order garbage → superseded → already-merged → novel-stale → divergent-refactor (opt-in) → applied-keepers | No `git branch -D` on protected branches, no `git push --delete`, no `rm -rf`, no `git update-ref -d`. `refs/branch-rationalization-backup/*` and the bundle survive. |
| **Handoff** — counts, recovered SHAs, harmonization summary, rationalization-branch tip, bundle path, recovery recipes | Skill never pushes; user pushes | Complete recovery story even after a clean run |

---

## What This Skill Produces

Either:

1. **A clean rationalized repo** — canonical + the explicitly-protected branches + the rationalization branch with N focused keeper commits (some of which are harmonized syntheses), every keeper traceable to one or more source branches via `refs/branch-rationalization-backup/*`, every removed worktree's dirty state archived in the bundle, every deleted branch backed up in the bundle, and a final report showing what landed and what didn't.
2. **An audit report only** (when run in `triage-only` mode) — the recovery bundle plus `triage.tsv` plus `harmonization_plan.md` plus a markdown decision table; no commits, no removals, no deletions.

Concretely, after a successful run the user has:

- `branch-rationalization-<YYYY-MM-DD>` branch ready to push (the user pushes; the skill never does)
- Canonical branch unchanged
- Protected branches unchanged
- Disk space reclaimed from removed worktrees (often gigabytes — the dominant motivator for users with many `git worktree` checkouts)
- A bundle directory outside the repo, byte-equality-verified, surviving DCG and `git clean -fdx`
- A handoff report with copy-paste recovery recipes for every removal and deletion
- A beads issue summarizing the run with status `closed`
- Optionally: a `bv --robot-triage` output surfacing follow-up items the recovered commits unblock

The skill **never**:

- Runs `git branch -D` on a protected branch
- Runs `git branch | xargs git branch -D` or any other mass-delete primitive
- Runs `git worktree prune` as a substitute for explicit `git worktree remove`
- Runs `git push --delete`, `git push --force`, or any other remote-mutating command
- Runs `rm -rf` (DCG would block it; the skill is designed not to need it)
- Runs `git reset --hard`, `git clean -fd`, `git update-ref -d`
- Pushes the rationalization branch — that's the user's call
- Modifies `.git/` directly outside `update-ref` for backup refs and `git bundle create`
- Stashes, reverts, or overwrites changes from other agents in any worktree (per AGENTS.md "Note for Codex/GPT-5.5")
- Removes the currently-active worktree (the user's CWD)

---

## Inputs

- **Target path** (default: cwd) — absolute path to a git repo, OR a git URL we clone into `/tmp/<basename>` and operate against.
- **Mode** — auto-detected from worktree + branch counts (Quick / Standard / Comprehensive); user-overridable.
- **Output mode** — `full` (default: triage + harmonize + apply keepers + gated cleanup) | `triage-only` (Phases 1–6 then stop) | `apply-only` (skip Phase 10 cleanup; leave worktrees and branches intact).
- **Rationalization branch name** — default `branch-rationalization-<YYYY-MM-DD>`. The skill creates this branch from canonical's tip and lands keeper commits there. NEVER lands directly on canonical unless the user explicitly passes `--land-on-canonical` AND types a separate verbatim authorization for that override.
- **Initial protection list** — branches/worktrees the user already knows they want to keep beyond the auto-protected defaults. (Defaults: canonical, currently-checked-out branch, anything matching `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`, plus anything with branch-protection rules in the project config.)
- **Remote-cleanup scope** — default `out-of-scope`. Opt-in with `--prepare-remote-list` to have the skill emit a list of `git push --delete` commands the user runs themselves; the skill never runs them.
- **Bundle directory** — default `<project-parent>/<basename>-branch-worktree-archive-<YYYY-MM-DD>/` (placed next to the repo, not inside it).

---

## Workspace Layout

A single run creates two directories: the workspace inside the repo (transient, .gitignored) and the recovery bundle outside the repo (persistent, user-managed).

```
<project-root>/
└── .worktree_branch_rationalization_workspace/   ← transient, in repo, .gitignored
    ├── project_profile.json                       ← Phase 1 output
    ├── worktrees.tsv                              ← Phase 2 output (worktree inventory)
    ├── branches.tsv                               ← Phase 2 output (branch inventory)
    ├── inventory_grouped.md                       ← Phase 2 — grouped by name-prefix family
    ├── wt_phase0.txt                              ← Phase 0 baseline working-tree snapshots
    ├── bundle_path.txt                            ← absolute path to recovery bundle
    ├── bundle_verification.log                    ← Phase 3 byte-equality + round-trip results
    ├── protected.tsv                              ← Phase 4 — confirmed protected items
    ├── triage/
    │   ├── batch_001.tsv                          ← Phase 5 worker output
    │   └── ...
    ├── triage.tsv                                 ← Phase 5/6 merged decision table
    ├── triage_decision.md                         ← Phase 6 — user-facing markdown table
    ├── user_overrides.tsv                         ← Phase 6 — verdicts the user overrode
    ├── harmonization_plan.md                      ← Phase 7 — per-file variant matrix
    ├── apply_log.tsv                              ← Phase 8 — what landed, with SHA + strategy
    ├── conflicts/
    │   └── branch_<slug>.context.md               ← Phase 8 — surfaced conflict context
    ├── partial_split_log.tsv                      ← Phase 8b — split-apply outcomes
    ├── fresh_eyes_log.md                          ← Phase 9 — review rounds
    ├── cleanup_authorization.txt                  ← Phase 10 — verbatim user authorization
    ├── cleanup_log.tsv                            ← Phase 10 — what got removed/deleted
    ├── handoff_report.md                          ← Phase 11 — final report
    └── skill_feedback.md                          ← Phase 12 (optional)

<project-parent>/<basename>-branch-worktree-archive-<YYYY-MM-DD>/   ← persistent recovery bundle
├── README.md                                      ← recovery recipes + footgun warnings
├── object-bundle.pack                             ← `git bundle create --all` over backup namespace
├── index.tsv                                      ← kind|name_or_path|slug|head_sha|merge_base|ahead|behind|smell|intake_protected|verdict|bundle_paths
├── branches/
│   └── <slug>/
│       ├── meta.txt                               ← head SHA, merge-base, ahead/behind, …
│       ├── commits.tsv                            ← one row per commit not on canonical
│       ├── diff-vs-merge-base.diff                ← `git diff --binary <merge-base>...<branch>`
│       └── format-patch/
│           ├── 0001-...patch                      ← `git format-patch <merge-base>..<branch>`
│           └── ...
└── worktrees/
    └── <sanitized-path>/
        ├── meta.txt                               ← original path, branch, last commit, locks
        ├── status.txt                             ← `git status --porcelain=v2` snapshot
        ├── staged.diff                            ← `git diff --binary --cached` snapshot
        ├── unstaged.diff                          ← `git diff --binary` snapshot
        ├── .untracked.list                        ← NUL path manifest, only with untracked content
        ├── .untracked.sha256                      ← NUL byte manifest hash input, only with untracked content
        └── untracked.tar.gz                       ← only present if untracked content existed
```

Backup refs live inside `.git/`:

```
.git/refs/branch-rationalization-backup/<slug>    ← byte-identical to live branch (verified Phase 3)
```

The bundle is **outside** the repo on purpose: it survives `git clean -fdx` (which the skill never runs but the user might), it doesn't pollute `git status` while running, and it's trivially shareable via `tar`.

---

## Up-Front Confirmations (Ask Before Starting)

Use the intake template at `assets/intake-prompt.md` verbatim. The summary:

1. **Target path?** Confirm absolute path. If a git URL, ask whether to clone to `/tmp/<basename>`. Refuse to operate on a path that isn't a git work tree.
2. **Counts up front.** Run `git -C <path> worktree list | wc -l` AND `git -C <path> branch | wc -l` and tell the user the magnitudes *before* asking them to commit time. >20 worktrees or >100 branches is rare enough that users genuinely don't know they have that many.
3. **Canonical branch detected.** Tell the user the detected canonical name (NOT assuming `main`).
4. **Mode?** Auto-detect from counts; user can override.
5. **Output mode?** `full` | `triage-only` | `apply-only`. Default `full`.
6. **Initial protection list?** What does the user already know they want to keep? (Auto-protected defaults are listed; user can add or remove.)
7. **Rationalization branch name?** Default `branch-rationalization-<YYYY-MM-DD>`. Confirm.
8. **Remote cleanup?** Default `out-of-scope`. Opt-in to `--prepare-remote-list`.
9. **Bundle path?** Default `<project-parent>/<basename>-branch-worktree-archive-<YYYY-MM-DD>/`. Confirm.
10. **Resuming a prior run?** If `.worktree_branch_rationalization_workspace/` exists, offer (a) resume from saved state, (b) archive old workspace under a timestamped suffix and start fresh, or (c) abort.
11. **Concurrent agents?** Ask whether other agents are working in this repo or its worktrees right now. If yes, run `agent-mail file_reservation_paths(... [".git/worktrees/**", ".git/refs/heads/**"], reason="branch-rationalization-<run-id>")` advisory-only.
12. **Quality gates?** Confirm the auto-detected `cargo test` / `bun tsc --noEmit` / `pytest` / `go test ./...` etc. is correct. Default: run them on every Phase 8 apply.

If any helper skill is missing (`/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/agent-mail`, `/beads-br`, `/beads-bv`, `/ubs`, `/idea-wizard`, `/multi-pass-bug-hunting`, `/multi-model-triangulation`, `/dcg`): if `jsm` is installed and authenticated, offer `jsm install <name>` for each missing one. Don't block a phase if a polish skill is missing — note it and proceed with the inline fallback.

---

## Skill Bootstrap (Phase 0.5 — right after inputs, before inventory)

Phase 0.5 is fast (≤2 min). It establishes the project profile, detects helper skills, mines prior context, and registers the run with multi-agent coordination infrastructure. Every script here is resume-aware — re-running picks up cached results within ~7 days.

```bash
# 1. Pre-flight repo health check (refusals + soft warnings).
./scripts/git-doctor.sh <project-path>
# Refuses: not git work tree, bare repo, mid-rebase/merge/cherry-pick/revert/bisect,
# git<2.20, unwritable filesystem. Warns: detached HEAD, dirty worktree (concurrent
# agents — don't disturb), no remote, [gone]-upstream branches, locked stale worktrees.

# 2. Project reconnaissance (canonical detection — NEVER assumes 'main').
./scripts/discover-project.sh <project-path>
# Detects: canonical branch (via git symbolic-ref refs/remotes/origin/HEAD, then
# heuristic), build/test/lint/format commands, branching model, merge style
# (squash / rebase-and-merge / merge — drives Phase 8 strategy), protected-by-
# convention patterns (release/*, hotfix/*, dependabot/*, renovate/*, gh-pages,
# CODEOWNERS rules); writes project_profile.json.

# 3. Detect helper skills + jsm state.
./scripts/check-skills.sh <project-path>
# Probes /operationalizing-expertise, /codebase-archaeology,
# /codebase-report, /agent-mail, /beads-br, /beads-bv, /ubs, /idea-wizard,
# /multi-pass-bug-hunting, /multi-model-triangulation, /dcg, /cass, /slb;
# emits phase0_skill_inventory.json. Optional: ./scripts/install-referenced-skills.sh
# bulk-installs missing ones via jsm.

# 4. Mine prior agent sessions for context (optional but recommended).
./scripts/cass-mine.sh <project-path>
# Runs `cass search` on the project basename, "branch rationalization", "git worktree",
# "git branch -D", "harmonize branches" — 90-day window. Captures into cass_findings.md
# for: prior runs of THIS skill on THIS project, prior manual rationalization sessions,
# past file-collision hotspots that inform Phase 7 harmonization. Skips silently if
# cass not installed.

# 5. GitHub PR awareness (if applicable).
./scripts/github-pr-awareness.sh <project-path>
# If gh is authenticated and the repo has a GitHub remote: queries open PRs (head/base
# refs become PROTECTED candidates — don't auto-classify a branch with an open PR as
# garbage), queries branch protection rules. Writes github_state.json. Skips silently
# otherwise.

# 6. Multi-agent coordination handshake (if /agent-mail available).
# Per references/MULTI-AGENT-COORDINATION.md, register the run with Agent Mail,
# acquire exclusive file reservations on .git/worktrees/**, .git/refs/heads/**,
# and the workspace's triage/conflicts subdirs (TTL 3600s, refreshed every TTL/4).
# If another agent has reservations, defer or coordinate.

# 7. File a beads issue for traceability.
br create --title "branch+worktree rationalization on <basename> (B=$BRANCH_COUNT, W=$WORKTREE_COUNT)" \
          --type=task --priority=4
# The issue id becomes the run-id; Mail thread_id and file-reservation reason
# both reference it.
```

The skill **never blocks** on a missing helper skill — every reference has an inline fallback. Skip silently if `gh`, `cass`, `agent-mail`, `br`, `bv`, `jsm`, `slb`, `ubs` aren't installed; the run still produces the bundle, the triage, the harmonization plan, and the handoff report. Helper skills make the run *better* — they're never load-bearing.

**After-swarm mode.** When Phase 0.5 detects (via `cass-mine.sh` and Agent Mail's `list_active_agents`) that this project has had agent-swarm activity in the last 7 days, the kickoff prompt is automatically tailored: smaller batch sizes in Phase 5 (because triage volume is high), Phase 7 harmonization is preemptively assumed (collisions are the norm, not the exception), and Phase 9 fresh-eyes runs an extra adversarial round looking for swarm-induced regressions. See [KICKOFF-PROMPTS.md § After-Swarm Mode](references/KICKOFF-PROMPTS.md#after-swarm-mode-specialized-variant).

**Cass-mined context flows into the run.** Prior-session findings annotate `inventory_grouped.md` (each branch family carries its prior-session note: "this `agent-mysql-fix-*` family has a 2026-04-12 session that ended in autostash conflict"), `harmonization_plan.md` (intent attribution backed by the agent dialogue that authored the variant), and `handoff_report.md` ("this is the third rationalization run on this project; prior runs authored 5 keepers across 7 branches"). See [CASS-MINING.md](references/CASS-MINING.md).

---

## The Phase Loop (Mandatory)

```
Phase 0   INTAKE                    target path, canonical detection, resume vs fresh,
                                    initial protection list, remote-cleanup scope,
                                    rationalization-branch name, mode
Phase 1   PROJECT RECONNAISSANCE    AGENTS.md, README.md, /codebase-archaeology,
                                    /codebase-report → project_profile.json
Phase 2   BRANCH/WORKTREE INVENTORY two passes → worktrees.tsv + branches.tsv
                                    + inventory_grouped.md
Phase 3   RECOVERY BUNDLE           backup refs + object-bundle.pack + per-branch diffs +
                                    per-branch format-patch + per-worktree dirty captures +
                                    index + README; byte-equality + bundle-round-trip verify
Phase 4   PROTECTION CONFIRMATION   show full inventory; confirm auto-protected defaults;
                                    capture user additions/removals; write protected.tsv
Phase 5   TRIAGE FAN-OUT            parallel batches; emit triage.tsv with verdict +
                                    evidence + strategy + touched-files
Phase 6   TRIAGE MERGE & CONFIRM    decision table; user overrides; freeze the triage
Phase 7   HARMONIZATION PLAN        per-file variant matrix for files touched by ≥2
                                    non-protected branches; write harmonization_plan.md;
                                    user reviews BEFORE Phase 8 mutates anything
Phase 7.5 DRY-RUN PREVIEW           (optional, --dry-run mode OR Comprehensive/Council
                                    default) generate `dry_run_report.md` previewing every
                                    Phase 8 + Phase 10 action; user reviews; Phase 8
                                    detects divergence vs `expected_outcomes.json` and halts
Phase 8   RATIONALIZATION + APPLY   cut branch-rationalization-<DATE> from canonical;
                                    sequential apply (cherry-pick / squash-merge /
                                    rebase-and-merge / harmonized synthesis / split-commits /
                                    dirty-state diffs); per-apply quality gates;
                                    ⊞ RE-FINGERPRINT after each
Phase 9   FRESH-EYES VERIFICATION   three review prompts × ≥2 rounds; full test suite +
                                    linters + UBS green
Phase 9.5 POST-RUN AUDIT            🛡 codebase-audit on the rationalization branch's tip
                                    (security, performance, correctness, API consistency,
                                    test coverage, commit-message quality); MR-4 intent-
                                    preservation on harmonized commits; HARD GATE — Phase 10
                                    BLOCKED until audit passes
Phase 10  DESTRUCTIVE CLEANUP       gated; verbatim authorization; worktree removal first
                                    (git worktree remove, then prune residual metadata),
                                    then git branch -d/-D in correct order; remote
                                    cleanup out of scope by default
Phase 11  HANDOFF & FOLLOW-UPS      final report; recovery recipes; rationalization-branch
                                    push instructions; beads/Mail update; bv triage;
                                    🆔 UNBLOCK detection of newly-actionable beads
Phase 12  USER-LENS REVIEW          (optional, off by default) skill self-improvement notes
```

**Phases 5 and 9 are reapply-until-quiet** — keep spawning passes until an entire pass produces only trivial findings. Phase 9's two clean rounds are the explicit termination gate before Phase 10 may run.

**Phases 3, 6, 7, 7.5 (when active), 9.5, and 10 are gates.** Phase 3 must complete with byte-equality + bundle-round-trip verified. Phase 6 must end with explicit user go-ahead. Phase 7 must end with the user's review of the harmonization plan. Phase 7.5 (when active) must end with the user's approval of `dry_run_report.md`. Phase 9.5 must end with the audit clean (BLOCKING). Phase 10 must end with explicit user-typed verbatim authorization.

**Phase 8's quality gates run on every applied commit, not at the end.**

Full per-phase playbook with exit criteria + exact subagent prompts: **[PHASES.md](references/PHASES.md)**.

### Mode Variants

| Mode | Worktrees | Branches | Wall time | Triage | Harmonization | Phase 9 |
|------|-----------|----------|-----------|--------|---------------|---------|
| **Quick** | <5 | <30 | 15–30 min | Single agent | Skipped unless ≥2 branches collide on the same file | One round |
| **Standard** | 5–20 | 30–100 | 30–90 min | 2–4 parallel triage workers | Activated when ≥2 branches collide on the same file | ≥2 rounds |
| **Comprehensive** | 20+ | 100+ OR dirty worktrees OR monorepos OR submodules OR many file conflicts | 2–6 h | 5+ parallel workers; archaeology subagent for each `novel-but-stale` candidate | Dedicated harmonization-planner subagent | ≥3 rounds, multi-model triangulation if available |
| **Council** | any | production-critical or security-sensitive content | 4–12 h | 12+ workers; multi-model triangulation on Phase 5 triage AND Phase 7 harmonization | Council triangulation on the variant matrix | ≥3 rounds, multi-model adjudicated |

Mode is recorded in `project_profile.json` at Phase 1. Phase gates (especially Phase 9 termination) adjust based on mode.

---

## Parallelism Model

Inventory and bundle creation are serial (one source of truth). Triage and harmonization are the large parallelizable phases. Apply is sequential (each apply changes the 3-way base for later applies and can flip verdicts).

```
┌─────────────────────────────────────────────────────────────┐
│  Phase 1 PROFILE  +  Phase 2 INVENTORY  +  Phase 3 BUNDLE   │ serial
└────────────────────────┬────────────────────────────────────┘
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
     ┌──────────────┐           ┌──────────────┐
     │ Triage A     │   ...     │ Triage N     │   parallel, ~10 branches each
     │ branches/wts │           │ branches/wts │
     └──────┬───────┘           └───────┬──────┘
            │                           │
            └─────────────┬─────────────┘
                          ▼
              ┌─────────────────────────┐
              │ Phase 6 MERGE & CONFIRM │   single agent
              │ (USER GATE)             │
              └──────────┬──────────────┘
                         ▼
              ┌─────────────────────────┐
              │ Phase 7 HARMONIZATION   │   1 planner OR fan-out per
              │ (USER GATE)             │   colliding-file group
              └──────────┬──────────────┘
                         ▼
              ┌─────────────────────────┐
              │ Phase 8 APPLY KEEPERS   │   sequential; per-apply gates
              └──────────┬──────────────┘
                         ▼
              ┌─────────────────────────┐
              │ Phase 9 FRESH-EYES      │   parallel review prompts
              └──────────┬──────────────┘
                         ▼
              ┌─────────────────────────┐
              │ Phase 10 CLEANUP (GATED)│
              │ Phase 11 HANDOFF        │
              └─────────────────────────┘
```

**Default execution: single Claude Code session.** The main agent uses the Task tool to spawn parallel subagents for Phase 5 (triage), Phase 7 (harmonization fan-out), and Phase 9 (fresh-eyes). No external orchestration required.

**Coordination** — when `/agent-mail` is available, use file reservations on `.worktree_branch_rationalization_workspace/triage/**` and `.git/refs/heads/**` so triage and apply workers don't stomp each other (thread id: `branch-rationalization-<run-id>`).

**Orchestration tier** — pick based on counts and stakes:

| Tier | Phase 5 workers | Default execution | When |
|------|-----------------|-------------------|------|
| Solo | 1 | Main agent only, no Task fan-out | <5 worktrees AND <30 branches |
| Pair | 2 | 2 parallel Task subagents | up to 20 worktrees / 100 branches |
| Squad | 4–6 | 4–6 parallel Task subagents | 100–200 branches |
| Swarm | 8–12 | 8–12 parallel Task subagents | 200+ branches OR many file conflicts |
| Council | 12+ | Task subagents + multi-model triangulation | production-critical, security-sensitive, or B≥300 |

Multi-model triangulation (Codex / Gemini in addition to Claude) is opt-in at any tier and required for Council; on Phase 5 triage AND Phase 7 harmonization. NTM swarm panes are an optional alternative orchestration topology if the user already runs NTM. The skill never *requires* multiple models; high-confidence single-model verdicts proceed without triangulation.

---

## Multi-Agent Coordination — When Other Agents Are Active

The motivating case for this skill is the *aftermath* of multi-agent work: a swarm of agents produced 200 branches and 47 worktrees, and now someone needs to rationalize. But the skill also has to handle the case where the swarm is *still running* — concurrent agents may be modifying worktrees, creating new branches, or holding file reservations.

The hard-won insight from cass-mined sessions ("Why branches/worktrees don't work with dozens of concurrent agents", "autostash resulted in merge conflicts requiring manual resolution", "Active agents kept modifying files while I was working") drives several specific behaviors:

| Situation | Skill's behavior |
|-----------|-----------------|
| Phase 0.5 detects active reservations on `.git/worktrees/**` or `.git/refs/heads/**` | Defer or coordinate via Agent Mail; don't kick off a competing run |
| Working tree of a non-active worktree changes mid-Phase-8 | Treat as if you made it (per AGENTS.md "Note for Codex/GPT-5.5"); never stash/revert/overwrite; re-snapshot before the next apply |
| Canonical's tip moves mid-run (force-push or fast-forward) | Halt and surface to user; the rationalization branch's parent assumption may now be invalid; recover via Phase 3's snapshot of canonical's tip |
| New branch appears mid-run that wasn't in `branches.tsv` | Halt; the inventory was torn; re-run Phase 2 |
| Agent Mail server unreachable | Log "coordination skipped"; proceed without reservations; the skill's own bundle + verbatim-authorization gates still apply |
| User invokes the skill while a swarm is actively spawning new branches | Auto-select after-swarm mode (detected via cass-mine); tighter Phase 5 batch size; aggressive Phase 9 adversarial round; recommend the user pause the swarm before Phase 10 |

The skill registers exclusive Agent Mail file reservations on `.git/worktrees/**`, `.git/refs/heads/**`, and the workspace's triage/conflicts subdirs at Phase 0.5 with TTL 3600s, refreshed every TTL/4. It releases all reservations at Phase 11 handoff. Every phase boundary is a clean resume point — if a higher-priority agent needs to land work mid-rationalization, the skill can pause and resume.

Full coordination patterns + recipes: **[MULTI-AGENT-COORDINATION.md](references/MULTI-AGENT-COORDINATION.md)** and **[INTEGRATION.md](references/INTEGRATION.md)**.

---

## Operator Library — The Cognitive Moves

Each operator is a reusable verb with explicit triggers. These are *what to think about*, not just *what to do*.

| Glyph | Name | Question / Action | When to Apply |
|-------|------|------------------|---------------|
| `★` | **INVENTORY** | Capture every branch's ref + ahead/behind + cherry-summary + touched-files AND every worktree's path + dirty-state into two TSVs; never trust `git branch` output alone | Phase 2 — once, the source of truth |
| `🔒` | **PROTECT** | User-flagged keep-forever items; never enter the rationalization pipeline; still backed up | Phases 0 + 4 |
| `🌳` | **WORKTREE-CHECK** | Verify each worktree's dirty state (staged + unstaged + untracked) is captured in the bundle before any removal | Phase 3, then Phase 10 before each removal |
| `✦` | **FINGERPRINT** | Identify the symbols a branch introduces: function names, type names, fixture strings, test names, file paths | Phase 5, per-branch, before any "is it on canonical?" check |
| `◐` | **VERIFY-ON-CANONICAL** | Grep / ast-grep canonical for the fingerprint; if every fingerprint resolves on canonical with the same semantics, the branch is `superseded` | Phase 5, immediately after FINGERPRINT |
| `⬡` | **BUNDLE** | Materialize backup refs + object bundle + per-branch diffs/format-patch + per-worktree dirty captures + meta + index for every entry; verify byte-equality AND bundle round-trip before allowing destructive phases | Phase 3 — the irreversibility gate |
| `⚠` | **CONFIRM** | Restate the destructive command verbatim; wait for explicit user OK in the same message; record the authorization text | Phases 6, 7, 10 |
| `◇` | **HARMONIZE** | For every file touched by ≥2 branches, build the variant matrix, identify each variant's intent (defensive, refactor, test, fixture, type-narrowing, error-handling, performance, naming), propose a best-of-all-worlds synthesis on top of canonical, write it as the harmonization plan; the cognitive move that distinguishes this skill from stash-janitor | Phase 7 |
| `✧` | **CHERRY-PICK** | `git cherry-pick --no-commit` stages the candidate once; on a clean apply, commit the staged result with source credit; per-keeper gates | Phase 8, single-commit and small-coherent branches |
| `⊟` | **SQUASH-MERGE** | `git merge --squash` for small-coherent branches when the project's preferred merge style is squash; one focused commit | Phase 8, when project_profile.json says squash-merge |
| `⊠` | **REBASE-AND-MERGE** | Replay the branch's commits onto the rationalization-branch tip without mutating the source branch; surface conflicts; for large-and-meaningful branches | Phase 8, when project_profile.json says rebase-and-merge |
| `⇄` | **SPLIT-COMMITS-HUNKS** | For partially-novel branches, identify the subset of commits whose content is novel; cherry-pick that subset in dependency order | Phase 8b |
| `⊕` | **RECOVER** | Run the project's actual quality gates on every apply; catch compounding errors per-keeper, not at the end | Phase 8, after every successful apply |
| `⊞` | **RE-FINGERPRINT** | After every successful Phase 8 apply, re-run FINGERPRINT/VERIFY-ON-CANONICAL on downstream keep candidates; some now flip to `superseded` | Phase 8, between applies |
| `↺` | **WORKING-TREE-DRIFT** | Before each Phase 8 apply, re-snapshot `git status` in every active worktree; if changes appear from other agents, treat as if you made them; never stash/revert/overwrite | Phase 8, every iteration |
| `⊙` | **PRUNE-WORKTREE** | Remove worktree directory via `git worktree remove <path>`; dirty state archived first; never `--force` without explicit user OK | Phase 10, before branch deletion |
| `⊘` | **DELETE-BRANCH** | Highest-risk individual operation; gated on backup ref + verbatim authorization; prefer `git branch -d` over `-D` for merged branches | Phase 10, after worktree pruning |
| `⌘` | **HANDOFF** | Final report with: counts per verdict, recovered commit SHAs, harmonization summary, rationalization-branch tip, bundle path, verbatim recovery recipes; never push | Phase 11 |

### Round-3 operators — rigor + operational depth

These operators were added when the skill was extended with the rigor / verification / operational-depth references and subagents. They compose with the core 18 above.

| Glyph | Name | Question / Action | When to Apply |
|-------|------|------------------|---------------|
| `👁` | **DRY-RUN** | Generate the full preview of every Phase 8 + Phase 10 action without executing any of them; emit `dry_run_report.md` + `expected_outcomes.json`. The actual run later compares reality to this prediction; divergence halts. Per /saas-billing-patterns-for-stripe-and-paypal preview-before-mutate axiom | Phase 7.5 (between harmonization plan and apply) |
| `🔬` | **PROVENANCE** | Record every byte's source — which source branch, which commit, which hunk, which intent (for harmonized synthesis). Emit `provenance.json` and attach `git notes` to each rationalization-branch commit linking back to the source(s). Enables post-merge audit, regression bisection, compliance trails | Phase 8 (during apply) + Phase 11 (handoff) |
| `⏱` | **PROFILE** | Instrument every script invocation; aggregate per-phase totals + per-script breakdowns + parallelism efficiency; compare against MEASUREMENT.md SLOs; flag regressions; recommend tier adjustments for next run | Cross-phase, post-run |
| `🛡` | **AUDIT-AFTER** | Codebase-audit on the rationalization branch's tip after Phase 9. Runs UBS, lint, typecheck, formatter, security scanners, full test suite, MR-4 (intent preservation) on harmonized commits. Phase 10 BLOCKED until audit passes (HARD GATE) | Phase 9.5 |
| `🧪` | **FUZZ** | Defense-in-depth fuzzing of the bundle's recovery surface; generate transformed copies (tar/untar, fs-copy, simulated bit-flips); run `verify-bundle.sh` against each; identify "cliff edges" where recovery breaks. Per /testing-fuzzing | Phase 3 + Phase 11 |
| `📐` | **PROVE** | Verify the bundle conforms to BUNDLE-FORMAT-SPEC.md via `conformance-check.sh`. Per spec section, a check function. Emits compliance matrix; halts if any required spec invariant fails. Per /testing-conformance-harnesses | Phase 3 + Phase 11 |
| `🪞` | **METAMORPHIC** | Verify each harmonized synthesis against the 7 metamorphic relations (Identity, Commutativity, Idempotence, Intent Preservation, No Regression, Fingerprint Coverage, Dependency Closure); the oracle-blind test for synthesis correctness. Per /testing-metamorphic | Phase 9 (round 2+) on every harmonized commit |
| `🎯` | **CALIBRATE** | Bayesian update on per-branch verdict confidence: prior (from family) × likelihood (from FINGERPRINT + VERIFY-ON-CANONICAL + cherry-summary) → posterior. Conformal threshold τ=0.85 separates auto-proceed from MANUAL. Established decision-theoretic / conformal-prediction framing | Phase 5, per-branch |
| `🌐` | **SEMANTIC-COLLISION** | Use semantic search (via /frankensearch-integration if available) to find collisions that file-path matching misses: e.g., `redact_secrets` in `logger.rs` on branch A and `sanitize_log_line` in `log_filter.rs` on branch B may be different implementations of the same conceptual feature. Augments harmonization-planner | Phase 7 (Comprehensive / Council mode) |
| `🔍` | **REFLOG-DEEP** | Extended reflog mining beyond basic upstream_status: full reflog history per branch, force-push detection via non-descendant new-SHAs, interactive-rebase artifact reconstruction, soft-reset chains, cherry-pick lineage. Drives `novel-but-stale` and `divergent-refactor` re-classification | Phase 5 (forensic phase) |
| `🔁` | **DUEL** | When ≥3 branches collide on the same file with high stakes, run the harmonization plan as a duel between two idea-wizards (different system prompts: "preserve every defensive intent" vs. "minimize total surface area"). Adjudicator picks one or composes. Per /dueling-idea-wizards | Phase 7 (Council mode always; Comprehensive when ≥3-branch collision) |
| `📡` | **CI-AWARE** | Detect references to soon-to-be-deleted branches in `.github/workflows/*.yml`, README install URLs, dependabot.yml, mergify.yml, package.json, dockerfile, CHANGELOG.md. Refuse Phase 10 cleanup if updates would break CI and aren't reconciled. Cass-mined real footgun | Phase 4 |
| `🔗` | **REMOTE-TOPOLOGY** | Detect when `origin` points to a local sibling worktree (not the actual upstream). Cass-mined real footgun (`frankensqlite`'s `origin` was local). The Phase 11 push-instruction targets the correct remote, not blindly `origin` | Phase 1 |
| `✍` | **SIGN** | For projects requiring signed commits (per `project_profile.json:requires_signing`), every cherry-pick / squash-merge / rebase-and-merge / harmonized synthesis must produce a signed commit. Re-sign via `git commit --amend --no-edit -S` after explicit authorization; preserve git notes via `git notes copy`. Never disables signing | Phase 8 (post-apply) |
| `🆔` | **UNBLOCK** | Detect newly-actionable beads via `bv --robot-triage --diff-since`; closed-by-this-commit issues; PRs whose head branch was rationalized and may now be auto-mergeable; reverse-impact (recovered work invalidates an open beads). Optional /idea-wizard generates 5–10 new beads ideas with priority | Phase 11 (handoff augmentation) |
| `📦` | **EXPORT** | Bundle the entire workspace + recovery bundle into a portable `<basename>-rationalization-export-<DATE>.tar.zst` for cross-machine resume / audit / handoff to a different operator. Never deletes source — only `mv` if user explicitly opts in | Phase 11+ |
| `🪢` | **REPLAY** | Resumability primitive: when mid-Phase-8 conflict resolution captured into `<workspace>/conflicts/branch_<slug>.context.md` with the user's confirmed Edit operations, replay the resolution against fresh state on a future run. Idempotent | Resume after interruption |

Full operator cards (with prompt modules, failure modes, quote-bank anchors): **[OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md)**.

---

## The Polish Bar (Non-Negotiable)

A "successful rationalization run" is not "the branches are gone." Every keeper-commit must satisfy:

| Dimension | Test |
|-----------|------|
| **Recovery completeness** | Every branch has a backup ref AND a diff AND a format-patch series in the bundle AND an index entry; every worktree has its dirty state captured (staged + unstaged + untracked); byte-equality + bundle-round-trip verified before any destructive phase |
| **Verdict evidence** | Every triage row cites concrete evidence on canonical — `file.rs:317` showing the symbol exists, or `git cherry -v` showing patch-id equivalence, or grep-empty proving "novel" |
| **No phantom keepers** | No branch is marked "novel" without FINGERPRINT proving its symbols don't appear on canonical AND `git cherry -v` showing at least one `+` line; "I think it's novel" is never acceptable |
| **Harmonization fidelity** | Every file touched by ≥2 non-protected branches has an entry in `harmonization_plan.md` with the variant matrix; every entry cites specific source branches; every synthesis explains *why* this combination beats any single variant |
| **Per-apply gates** | Every Phase 8 commit has run the project's full test/typecheck/lint suite, and they all pass; no "we'll fix it at the end" |
| **Focused commit messages** | Each keeper-commit explains *why* this content is being recovered, naming source branches and variant intents: not "cherry-pick from agent-cleanup-pass-3" but "recover defensive null-check from agent-cleanup-pass-3 + parser-fixture from feature/parse-hardening + type-narrowing from worktree dirty-state, harmonized on top of canonical's current structure" |
| **Order of cleanup** | Worktrees pruned BEFORE branches deleted; within branches: garbage → superseded → already-merged → novel-stale → divergent-refactor (opt-in) → applied-keepers; protected branches NEVER deleted |
| **Verbatim authorization** | Phase 10 only runs after the user types the literal commands (or an authorization phrase that quotes them); recorded in `cleanup_authorization.txt` |
| **Idempotent on a clean repo** | Re-running on a freshly-cleaned repo produces no commits and reports "nothing to rationalize" |
| **Resumable** | If interrupted mid-Phase 8, re-running picks up from the last successful commit using `apply_log.tsv` + git log on the rationalization branch |

If a run can't satisfy these, it has not "completed successfully" — it has half-finished and needs to flow back through whichever phase failed.

Full rubric, per-phase checklists, verification queries: **[POLISH-BAR.md](references/POLISH-BAR.md)**.

---

## Failure Modes Table — Branch + Worktree Footguns

Every entry is a known-quantity hazard. Treat them as rails, not surprises.

| Symptom | Cause | What to do |
|---------|-------|------------|
| `git format-patch` IS valid for branches | Stash-janitor's "format-patch is index-only for stashes" rule does NOT generalize | Use it freely for branches; the bundle includes a per-branch format-patch series. Cross-link to BUNDLE-FORMAT-SPEC.md so future readers don't reach the wrong conclusion |
| `git branch -D <name>` deletes the ref but commits remain reachable for ~30–90 days via reflog | Reflog gc window is finite | The backup ref in `refs/branch-rationalization-backup/<slug>` AND the `git bundle` are the long-term safety nets; both survive reflog gc |
| `git branch -d <name>` (lowercase) refuses to delete an unmerged branch | Built-in safety check | Prefer `-d` over `-D` whenever the branch is fully merged into the rationalization branch; use `-D` only when the user has explicitly acknowledged the branch as unmerged-and-discardable |
| `git worktree remove <path>` refuses worktrees with uncommitted changes | Built-in safety check | Archive the dirty state into the bundle FIRST; only then `--force` if the user has explicitly OK'd losing it. Never `rm -rf <path>` |
| The currently-checked-out branch can't be deleted | Git refuses | Switch first or skip; the active branch is auto-protected anyway |
| The currently-active worktree (the user's CWD) can't be removed from inside | Git refuses; the skill enforces this independently | The user removes that one themselves from a different working directory after the run; the handoff report explicitly tells them how |
| A branch with `[gone]` upstream tracking has unique commits | The tracking ref is gone but the commits aren't | Don't auto-delete just because tracking is gone. Triage normally |
| Submodule init state varies per worktree | `git worktree add` doesn't auto-init submodules; some worktrees may have submodules cloned, others not | Removing a worktree leaves the submodule cache untouched; `.git/worktrees/<id>/` IS pruned. Document the per-worktree submodule state in `worktrees.tsv` |
| `git worktree list` doesn't reliably show locked worktrees on stale paths | Locked-flag detection is via `--porcelain` | Always parse `--porcelain` and check the `locked` field explicitly; never rely on the human-readable format |
| `git worktree prune` removes admin metadata for worktree directories already deleted out-of-band | Useful as a follow-up cleanup | Never run as a substitute for explicit `git worktree remove`. Run AFTER the explicit removals to clean residual metadata |
| Cherry-picking a merge commit produces an unhelpful first-parent diff | Merge commits have multiple parents | Use `-m 1` (or the appropriate parent number); document the choice in the bundle's recovery recipe |
| Cherry-picking a commit whose changes were squash-merged onto canonical produces "nothing to commit" | The diff is empty because patch-id matches | `git cherry -v` would have flagged this with `-`; classify as `already-merged` and skip. If you're already mid-cherry-pick, `git cherry-pick --skip` |
| A branch whose upstream was force-pushed has divergent rewrite history | Reflog detects the force-push | Inspect the reflog before replaying commits; never rebase or mutate the source branch during rationalization |
| Two branches collide on the same file with incompatible defensive checks | Common in agent-swarm aftermath | This is exactly when ◇ HARMONIZE applies. Build the variant matrix in Phase 7; synthesize the best-of-all-worlds via the Edit tool. Don't pick one; don't drop both |
| Working tree shows changes from other agents mid-run | Concurrent agents in the same repo (per AGENTS.md) | Treat as if you made them. Never stash, revert, or overwrite. Re-snapshot before each Phase 8 apply |
| `rm -rf <bundle>/branches/` blocked by DCG | Destructive Command Guard hook | Don't fight it. The skill **never deletes the bundle** — the user manages bundle lifecycle |
| Two branches introduce the same fingerprint at different times | Common when a feature was started, abandoned, and restarted | Mark the older one(s) `superseded-by-newer-branch`; harmonize the newer one against canonical |
| `git branch | wc -l` count differs between two runs | Concurrent agent created or deleted a branch | Re-run Phase 2; never act on a stale inventory. The bundle's `index.tsv` is authoritative for that *snapshot point* |
| Beads database unwritable during the run | `.beads/beads.db` locked by a parallel `br` process | Skip the beads-issue creation; record `beads_skipped: true` in the handoff report; the run still succeeds |
| `git push --delete origin <branch>` runs irreversibly | Remote reflog access required to recover | Out of scope by default. If the user explicitly opts into remote cleanup with `--prepare-remote-list`, the skill emits the list of commands; the user runs them themselves |
| Refusing to delete the canonical branch | The skill auto-protects it | Always; non-negotiable |

Full diagnostic playbook with reproductions: **[FAILURE-MODES.md](references/FAILURE-MODES.md)**.

---

## Anti-Patterns (Never Do)

| ✗ | Why | Fix |
|---|-----|-----|
| Run `git branch | xargs git branch -D` (or any mass-delete primitive) | Bypasses verbatim authorization, can delete protected branches, no per-deletion logging | Iterate the cleanup list one entry at a time, restate verbatim before each |
| Use `rm -rf <worktree-path>` to remove a worktree | DCG blocks it AND it doesn't prune `.git/worktrees/<id>/` admin metadata | `git worktree remove <path>`; for residual metadata after manual deletion, `git worktree prune` |
| Run `git push --delete origin <branch>` on the user's behalf | Remote operations are irreversible without remote reflog access | Out of scope by default. Emit the list with `--prepare-remote-list`; the user runs them |
| Skip the harmonization plan when ≥2 branches collide on the same file | Loses content; reduces this skill to "stash-janitor for branches" | Phase 7 is mandatory whenever the triage shows file-level collisions; build the variant matrix |
| Land keeper commits directly on canonical | Even with verification, mass-applied recoveries deserve user review | Land on `branch-rationalization-<DATE>`; user merges/cherry-picks |
| Assume `main` is canonical | Many projects use `master`, `develop`, `trunk`, `default` | Detect via `git symbolic-ref refs/remotes/origin/HEAD` first |
| Run `git worktree prune` as a substitute for `git worktree remove` | Prune only cleans admin metadata; doesn't structurally remove a working tree | Use `git worktree remove <path>`; run `prune` only as a follow-up for residual metadata |
| Use `git branch -D` when `-d` would work | `-d`'s refusal-on-unmerged is a built-in safety check | Always try `-d` first; fall back to `-D` only with explicit user acknowledgment |
| Delete an "applied-keeper" branch before its commit lands on the rationalization branch | Loses content if the apply gets rolled back | Order: apply on rationalization branch → fresh-eyes verify ≥2 clean rounds → THEN delete the source branch (its content is now on the rationalization branch AND in the backup ref AND in the bundle) |
| Skip Phase 3 byte-equality + bundle-round-trip verification | If the bundle is wrong, the entire run is unsafe | Phase 3 is a hard gate — refuse to proceed if even one ref doesn't match or the bundle doesn't `git bundle list-heads` cleanly |
| Run a script over source files to "fix up" conflicts | Brittle regex transforms create more problems (per AGENTS.md "No Script-Based Changes") | Manual Edit-tool resolution only; surface conflict context to the user |
| Stash, revert, or overwrite changes from other agents in any worktree | Per AGENTS.md "Note for Codex/GPT-5.5" — those are concurrent agents' work | Treat as if you made them; never disturb |
| Push the rationalization branch on the user's behalf | Deployment is the user's call | Print the suggested `git push` command and stop |
| Bypass pre-commit hooks (`--no-verify`) | The user's gates exist for a reason | If a hook fails, fix the underlying issue; if you can't, surface to user |
| Auto-delete a branch with `[gone]` upstream tracking | The branch may have unique commits the upstream never saw | Triage normally; `[gone]` is a hint, not a verdict |
| Force-remove a worktree without archiving its dirty state | Loses uncommitted work | `git worktree remove --force` only after the staged + unstaged + untracked content is captured in the bundle AND the user has explicitly OK'd the loss |
| Remove the currently-active worktree (the user's CWD) from inside | Git refuses; trying anyway wastes time | The active worktree is auto-protected; the handoff report tells the user how to remove it themselves |

Full anti-pattern catalogue with worked examples: **[ANTI-PATTERNS.md](references/ANTI-PATTERNS.md)**.

---

## Decision-Theoretic Rigor

Every triage verdict carries a confidence score that's a **Bayesian posterior**, not a vibe. Branch families have priors (`agent-*` → 0.7 garbage / 0.2 superseded / 0.1 novel; `feature/*` → 0.4 superseded / 0.4 novel / 0.2 partially-novel; etc.) and the FINGERPRINT + VERIFY-ON-CANONICAL + cherry-summary evidence updates the posterior. At τ=0.85 the verdict goes auto-proceed; below τ it surfaces to the user as MANUAL.

**Worst-case recovery bounds.** Every removal/deletion has a ~five-layer reversibility chain (backup ref → object bundle → per-branch diff → format-patch series → reflog). Compose: P(some-layer-survives) given typical disk-failure + DCG-blocked-deletion rates → ≥0.999 over the 30-day reflog gc window. The user can tighten the bound by copying the bundle to a second machine.

**Sequential testing for fresh-eyes termination.** "≥2 clean rounds" is approximated by SPRT (Sequential Probability Ratio Test) with α=0.01, β=0.05. Comprehensive tier bumps to ≥3 rounds because the harmonization step creates more failure surface than vanilla cherry-pick.

**Distribution-shift detection.** When the user's repo's branch-family distribution diverges from baseline by >2σ, the skill recalibrates priors mid-run via `verdict-stats.sh`.

**Metamorphic relations** verify harmonized syntheses without an oracle (per /testing-metamorphic). Seven MRs (Identity, Commutativity, Idempotence, Intent Preservation, No Regression, Fingerprint Coverage, Dependency Closure) — every Phase 9 round 2+ runs them.

Full mathematical detail: [DECISION-THEORY.md](references/DECISION-THEORY.md), [TESTING-METAMORPHIC.md](references/TESTING-METAMORPHIC.md), [TESTING-FUZZING.md](references/TESTING-FUZZING.md), [TESTING-CONFORMANCE.md](references/TESTING-CONFORMANCE.md).

---

## Dry-Run Mode (per /saas-billing-patterns-for-stripe-and-paypal)

Before any Phase 8 mutation, the user can pass `--dry-run` (or `DRY_RUN=1`) to get a complete preview of every action without execution. The dry-run synthesizes Phase 8 + Phase 10 into a single review artifact:

- Every cherry-pick with predicted resulting commit message
- Every squash-merge with predicted commit
- Every harmonized synthesis with the proposed code
- Every conflict that WOULD arise (via `git merge-tree`)
- Every worktree removal with disk freed (`du -sb`)
- Every branch deletion with backup-ref name
- The verbatim authorization phrase the user would need to type for cleanup

The skill emits `dry_run_report.md` AND `expected_outcomes.json`. The actual run later compares reality to this prediction; **divergence halts**.

This is the per /saas-billing-patterns-for-stripe-and-paypal "preview-before-mutate" axiom applied to git rationalization. Full ergonomics: [DRY-RUN-MODE.md](references/DRY-RUN-MODE.md).

---

## Post-Run Audit (per /codebase-audit + /multi-pass-bug-hunting)

After Phase 9 fresh-eyes converges, the rationalization branch's tip is audited as a hard gate before Phase 10 cleanup. Six dimensions:

| Dimension | Check |
|-----------|-------|
| Security | No new credential leaks, no SQL injection, no path traversal — UBS + cargo-audit / npm-audit / pip-audit |
| Performance | No n² loops introduced on hot paths, no allocations inside tight loops — clippy/eslint/etc. |
| Correctness | No null-pointer dereferences, no off-by-one, no race conditions — typecheck + the project's full test suite |
| API consistency | Recovered commits don't mix conventions — per /codebase-audit |
| Test coverage | Every recovered commit has a test that exercises it; harmonized commits run the source-variants' tests too (MR-4 from TESTING-METAMORPHIC) |
| Commit-message quality | Every commit cites sources per COMMIT-MESSAGE-CRAFT.md — readable in 6 months |

Per-dimension auto-fix where possible; else escalate to user. **Phase 10 BLOCKED until audit passes.**

Full audit playbook: [AUDIT-AFTER-RUN.md](references/AUDIT-AFTER-RUN.md). Run via `scripts/audit-rationalization-branch.sh`.

---

## Provenance Chain (per /lean-formal-feedback-loop)

After a successful run, every byte on the rationalization branch is traceable back to its source: which source branch, which commit, which hunk, which intent (for harmonized commits). The `provenance.json` graph + `git notes` per rationalization-branch commit answer the question "where did this byte at logger.rs:42 come from?" in O(1) — branch + commit + intent.

Use cases:
- **Post-merge audit**: which agent's work made it into the v1.4 release?
- **Regression bisection**: when this bug appeared, which source branch's harmonization caused it?
- **Compliance trails**: no "lost" attribution for legal/audit requirements.

Full graph schema: [PROVENANCE-CHAIN.md](references/PROVENANCE-CHAIN.md). Query via `scripts/provenance-trace.sh <file>:<line>`.

---

## Cass-Mined Real Footguns

These failure modes were mined from the user's actual past sessions (per /cass) — they are NOT hypothetical:

| Footgun | Detection | Reference |
|---------|-----------|-----------|
| `origin` pointing to a local sibling worktree (not the actual upstream) — pushes go to the wrong place | Phase 1 `remote-as-worktree-detector.sh`; per-worktree `git remote -v` URL classification | [REMOTE-AS-WORKTREE-FOOTGUN.md](references/REMOTE-AS-WORKTREE-FOOTGUN.md) |
| CI workflow YAML referencing a soon-to-be-deleted branch (e.g., `master` → `main` migration breaks `.github/workflows/*.yml`) | Phase 4 `ci-workflow-aware-update.sh`; refuse Phase 10 cleanup until reconciled | [CI-WORKFLOW-AWARENESS.md](references/CI-WORKFLOW-AWARENESS.md) |
| `git autostash` during a rebase causing merge conflicts in concurrent agents' working trees | Per AGENTS.md "Note for Codex/GPT-5.5"; don't disturb; the rebasing agent owns it | [Axiom 12](#the-rationalization-kernel-universal-axioms) + [WORKTREE-STATE.md](references/WORKTREE-STATE.md) |
| Two competing branch-cleanup approaches (Claude Code's `git branch -d` loop vs. NTM's pane-per-branch workflow) collide | Phase 0.5 `agent-mail` reservations; defer or coordinate | [MULTI-AGENT-COORDINATION.md](references/MULTI-AGENT-COORDINATION.md) |
| Worktree redundancy (`frankenterm` vs. `frankensqlite` worktree of compilation helper — 100% redundant) | Phase 5 triage; high-confidence `garbage` verdict via fingerprint match against the canonical sibling | [BRANCH-WORKTREE-SMELLS.md](references/BRANCH-WORKTREE-SMELLS.md) |
| Force-pushed canonical mid-run | Phase 0 `git-doctor.sh` check; halt with reflog-based recovery | [INCIDENT-PLAYBOOK.md](references/INCIDENT-PLAYBOOK.md) + [ADVANCED-RECOVERY.md](references/ADVANCED-RECOVERY.md) |

---

## When NOT to Use This Skill

- **<2 worktrees AND <5 non-protected branches.** Just `git branch -vv` and `git worktree list` and inspect manually. The bundle overhead doesn't pay off.
- **Worktrees-as-parallel-review-workflow.** Some teams use `git worktree` deliberately as a parallel-review pattern (one worktree per open PR). Don't prune their workflow out from under them — ask first; the user's protection list usually covers this.
- **CI checkout with stashes/branches.** A CI host should have minimal local state; if it has many local branches or worktrees, the residue is evidence of something else wrong (a broken hook, a leftover from a debug session). Investigate the cause, don't triage the symptom.
- **Mid-rebase / mid-merge / mid-cherry-pick on the active worktree.** `git status` shows `interactive rebase in progress` or unmerged paths — finish first; the skill needs a clean checkout state to snapshot from.
- **Detached HEAD on the active worktree with no rationalization-branch base.** The skill needs canonical as a base for the rationalization branch; if the user is in detached-HEAD state, ask them to check out canonical first.
- **Bare repository.** `git worktree` and stashes are not meaningful for bare repos; refuse.

Full conditions and rationale: **[WHEN-NOT-TO-USE.md](references/WHEN-NOT-TO-USE.md)**.

---

## Pre-Flight & End Checklist

- [ ] Target path confirmed; canonical detected (NOT assumed `main`)
- [ ] Worktree count + branch count reported to user up front; mode selected
- [ ] Output mode confirmed (full / triage-only / apply-only)
- [ ] Initial protection list captured; remote-cleanup scope confirmed
- [ ] Rationalization branch name confirmed; bundle path confirmed
- [ ] Working tree state snapshotted (`wt_phase0.txt`) for every worktree
- [ ] Phase 1 produced `project_profile.json` with canonical + quality-gate commands + merge style
- [ ] Phase 2 produced `worktrees.tsv` AND `branches.tsv` covering every entry
- [ ] Phase 3 bundle exists with backup refs + object bundle + per-branch diffs/format-patch + per-worktree dirty captures + index + README; byte-equality + bundle-round-trip verified
- [ ] Phase 4 protected.tsv reflects user's confirmed protection list
- [ ] Phase 5 triage workers all completed; `triage.tsv` is one row per branch + one row per worktree
- [ ] Phase 6 user reviewed and confirmed the verdict table (or applied overrides)
- [ ] Phase 7 harmonization_plan.md exists if any files were touched by ≥2 non-protected branches; user reviewed
- [ ] Phase 8 keeper commits all have a passing test/typecheck/lint run on top
- [ ] Phase 8b partial-split commits each apply only the novel commits/hunks
- [ ] Phase 9 fresh-eyes ran ≥2 rounds clean; full test suite green; UBS clean (if available)
- [ ] Phase 10 cleanup_authorization.txt contains the verbatim user-typed authorization
- [ ] Phase 10 worktrees removed BEFORE branches deleted; protected items untouched
- [ ] Phase 11 handoff_report.md emitted; beads issue filed; recovery recipes verified
- [ ] User informed they need to push (`git push origin branch-rationalization-<DATE>`)
- [ ] Bundle path reported; left in place; not deleted

---

## Source Corpus

Every Anti-Pattern, Failure Mode, Operator card, and Branch/Worktree Smell in this skill traces back to a real session, a verified git-internals quirk, or a sibling-skill convention. The kernel is empirical, not aspirational.

| Source | Contribution |
|--------|--------------|
| git-stash-janitor (sibling skill) | Bundle discipline, byte-equality gate, verbatim-authorization gate, fresh-eyes loop, orchestration tiers, polish bar, operator-card scaffold, per-apply gates rule |
| Hypothetical asupersync 47-worktree+213-branch session (2026-05-XX) | Motivating scenario; the harmonization conceptual leap; the worktree-first cleanup ordering; the `[gone]`-upstream footgun; the `git cherry -v` already-merged detector |
| Cass-mined manual-rationalization sessions | "autostash resulted in merge conflicts requiring manual resolution" → Axiom 12 working-tree-drift discipline; "Active agents kept modifying files while I was working" → file-reservation + heartbeat patterns; "Why branches/worktrees don't work with dozens of concurrent agents" → the single-canonical-with-file-reservations steady state described in MULTI-AGENT-COORDINATION.md; the post-swarm cleanup pattern that motivates the after-swarm mode kickoff variant |
| AGENTS.md "Note for Codex/GPT-5.5" | The working-tree-drift discipline (Axiom 12) |
| AGENTS.md "Mandatory explicit plan" | The verbatim authorization gates (Axiom 14, ⚠ CONFIRM) |
| AGENTS.md "RULE NUMBER 1: NO FILE DELETION" | The bundle-lifecycle rule (Axiom 18); the "skill never deletes" principle; the "use `mv` not `rm -rf`" pattern in `archive-workspace.sh` |
| AGENTS.md "No Script-Based Changes" | Manual Edit-tool conflict resolution; harmonization synthesis via Edit, not sed/awk; the harmonized-synthesis strategy explicitly delegates to the main agent rather than scripting source mutation |
| AGENTS.md "Irreversible Git Actions" | The "no `git push --delete` / `--force`" rule; remote-cleanup-out-of-scope by default with `--prepare-remote-list` opt-in producing a list-only file the user runs themselves |
| Pro Git §7 (worktree internals) | Axioms 9, 11 — `.git/worktrees/<id>/` admin metadata; `git worktree remove` vs `git worktree prune` distinction |
| Pro Git §3 (branch internals) | Axiom 8 — `-d` vs `-D` semantics; reflog gc window |
| Pro Git §10 (`git bundle` internals) | Axioms 2, 4 — `git bundle list-heads` round-trip as the second verification layer beyond byte-equality |
| documentation-website-for-software-project | Phase loop structure; modes-of-reasoning; fresh-eyes prompt rotation; orchestration tiers; three-prompt fresh-eyes loop |
| wills-and-estate-planning-skill | Universal-axioms kernel; verification-first overlay; per-action irreversibility chain; the "every destructive action restated verbatim before execution" pattern |
| saas-billing-patterns-for-stripe-and-paypal | Per-phase artifact manifest; polish-bar discipline; intake-prompt template; dry-run-before-mutate ergonomics; idempotent re-runnability across phases; structured triage rubric over noisy real-world data |
| operationalizing-expertise (Track A) | Operator card structure (triggers + action + prompt module + exit criteria + failure modes + quote-bank anchors); cognitive-move taxonomy; the kernel/operator-library composition pattern |
| /cass | Phase 0.5 mining of prior sessions; intent attribution from prior agent dialogue; collision-hot-zone detection for Phase 7 harmonization |
| /agent-mail | The file-reservation + thread-id + heartbeat coordination pattern in Phase 0.5 and through every phase boundary |
| /beads-br (beads) | The run-id origin (`br create` → issue id → Mail thread_id → file-reservation reason); Phase 11 `bv --robot-triage` for newly-unblocked work |
| /multi-model-triangulation | Path A for Phase 5 / Phase 7 / Phase 9 triangulation when Comprehensive or Council mode is active |
| /codebase-archaeology + /codebase-report | Phase 1 project reconnaissance opener (Brennerian style); informs `project_profile.json` with the architecture context that drives merge-style and protected-by-convention detection |
| GitHub `gh` CLI + branch-protection rules | Phase 0.5 PR awareness — branches with open PRs are PROTECTED candidates; CODEOWNERS-rule branches are auto-protected |
| Linux kernel format-patch convention | Bundle's `format-patch/*.patch` series (Axiom 7 — format-patch IS valid for branches, unlike for stashes) |
| Rust bors / homu merge queue | Merge-style detection (squash / rebase-and-merge / merge) drives Phase 8 strategy |
| Conformal-prediction / Bayesian-decision-theory literature | Bayesian posterior calibration of triage confidence; conformal prediction at τ=0.85; SPRT for fresh-eyes termination; worst-case bounds on multi-layer recovery; distribution-shift detection. See [DECISION-THEORY.md](references/DECISION-THEORY.md). |
| /testing-metamorphic | The 7 metamorphic relations for harmonized syntheses (Identity, Commutativity, Idempotence, Intent Preservation, No Regression, Fingerprint Coverage, Dependency Closure). Phase 9 round 2+ runs them. See [TESTING-METAMORPHIC.md](references/TESTING-METAMORPHIC.md). |
| /testing-fuzzing | Bundle round-trip fuzzing under transformations (tar, fs-copy, simulated bit-flips); per-branch diff fuzzing under context drift; harmonization-plan fuzzing under variant-matrix perturbation. See [TESTING-FUZZING.md](references/TESTING-FUZZING.md). |
| /testing-conformance-harnesses | The bundle format spec is a contract; the conformance harness verifies any bundle satisfies it. Per-spec-section check function; compliance matrix; cross-version compatibility. See [TESTING-CONFORMANCE.md](references/TESTING-CONFORMANCE.md). |
| /codebase-audit | Phase 9.5 post-run audit (HARD GATE between Phase 9 fresh-eyes and Phase 10 cleanup) on the rationalization branch's tip — six dimensions (security, performance, correctness, API consistency, test coverage, commit-message quality); BLOCKS Phase 10 until pass. See [AUDIT-AFTER-RUN.md](references/AUDIT-AFTER-RUN.md). |
| /multi-pass-bug-hunting | Phase 9 fresh-eyes loop's "audit-fix-rescan" cycle; Phase 11 audit's iterate-until-clean discipline. |
| /lean-formal-feedback-loop | The provenance chain — every byte traceable to source — is a formal-grade audit trail; `git notes` + GPG signatures + the bundle compose into a cryptographic provenance proof. See [PROVENANCE-CHAIN.md](references/PROVENANCE-CHAIN.md). |
| /profiling-software-performance | Per-phase + per-script wall-time profiling; parallelism-efficiency measurement; SLO comparison; self-tuning recommendations for the next run. See [PERFORMANCE-PROFILE.md](references/PERFORMANCE-PROFILE.md). |
| /dueling-idea-wizards | When ≥3 branches collide on the same file, run the harmonization plan as a duel between two idea-wizards with different system prompts; adjudicator picks one or composes. Council mode mandatory. See [DUELING-IDEA-WIZARDS-INTEGRATION.md](references/DUELING-IDEA-WIZARDS-INTEGRATION.md). |
| /frankensearch-integration-for-rust-projects | Semantic collision detection — finds collisions that file-path matching misses (e.g., `redact_secrets` in `logger.rs` on branch A vs. `sanitize_log_line` in `log_filter.rs` on branch B). Phase 7 augmentation. |
| /idea-wizard | Phase 11 unblocked-work generation: 5–10 new beads ideas with priority, drawn from the recovered commits' fingerprints. See [UNBLOCKED-WORK.md](references/UNBLOCKED-WORK.md). |
| /reality-check-for-project | Phase 11 audit dimension: does the project actually look better post-rationalization than pre-rationalization, by README/architecture-doc standards? |
| Cass-mined real footguns from the user's prior sessions | "frankensqlite's origin pointed to local worktree" → REMOTE-AS-WORKTREE-FOOTGUN.md; "CI workflow: push trigger changed from `branches: [master, main]` to `branches: [main]`; install URL changed from `master/install.sh` to `main/install.sh`" → CI-WORKFLOW-AWARENESS.md; "frankenterm/frankensqlite worktree 100% redundant" → BRANCH-WORKTREE-SMELLS.md `W2-sibling-wt`. |

When extending this skill, every new card needs a source citation. New patterns without traceable provenance are speculation, not knowledge.

---

## Reference Index

### Core playbooks
| Need | File |
|------|------|
| Phase-by-phase playbook with exit criteria | [PHASES.md](references/PHASES.md) |
| Per-branch + per-worktree triage rubric | [TRIAGE-RUBRIC.md](references/TRIAGE-RUBRIC.md) |
| Polish Bar — what "successful" means | [POLISH-BAR.md](references/POLISH-BAR.md) |
| Safety model — every destructive action's reversibility chain | [SAFETY-MODEL.md](references/SAFETY-MODEL.md) |

### Methodology
| Need | File |
|------|------|
| Cognitive moves: operator cards + prompt modules | [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md) |
| The variant-matrix methodology, intent taxonomy, synthesis principles | [HARMONIZATION.md](references/HARMONIZATION.md) |
| Anti-pattern catalogue with worked examples | [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md) |
| Failure modes & diagnostic playbook | [FAILURE-MODES.md](references/FAILURE-MODES.md) |
| Phase 9 fresh-eyes prompts: rotation, harmonization-fidelity, cleanup-precondition | [FRESH-EYES-PROMPTS.md](references/FRESH-EYES-PROMPTS.md) |
| Per-phase SLOs and quality metrics; Polish Bar coverage; resumability | [MEASUREMENT.md](references/MEASUREMENT.md) |
| Phase 8 commit message structure: standard recovery, harmonized-synthesis, split-apply, conflict-resolved, dirty-worktree-only, bug-fix | [COMMIT-MESSAGE-CRAFT.md](references/COMMIT-MESSAGE-CRAFT.md) |
| Citation forms (file:line, cherry-summary, ast-grep, grep-empty, bundle-paths, signature-divergence, reflog) and per-verdict required citations | [EVIDENCE-CITATIONS.md](references/EVIDENCE-CITATIONS.md) |
| Forensic intent reconstruction from reflog, history, beads, CASS, and `gh` for `novel-but-stale` and `divergent-refactor` verdicts | [TIMELINE-RECONSTRUCTION.md](references/TIMELINE-RECONSTRUCTION.md) |
| Verbatim subagent prompt templates (one per phase) with inputs / outputs / exit criteria | [AGENT-PROMPTS.md](references/AGENT-PROMPTS.md) |
| Reading stances (Literal / Skeptical / Forensic / Adversarial / Junior / Expert / Timeline); per-phase default and worked example | [MODES-OF-REASONING.md](references/MODES-OF-REASONING.md) |
| Multi-model triangulation paths (A: `/multi-model-triangulation`, B: same-session multi-stance, C: NTM panes); when to invoke; cost-benefit | [MULTI-MODEL-TRIANGULATION.md](references/MULTI-MODEL-TRIANGULATION.md) |
| Adversarial harmonization-plan generation via `/dueling-idea-wizards`: Wizard A (preserve every defensive intent) vs. Wizard B (minimize total surface area); adjudication; convergence vs. divergence; multi-NTM-pane setup; integration with multi-model triangulation; Council-mode default | [DUELING-IDEA-WIZARDS-INTEGRATION.md](references/DUELING-IDEA-WIZARDS-INTEGRATION.md) |
| Reflog forensics deep dive: gc window semantics; `git fsck --lost-found`; force-push detection; interactive-rebase detection; cherry-pick chain reconstruction; the "superseded vs. source" verdict flip via temporal evidence; the `agent-redact-pass-2` worked forensic | [REFLOG-DEEP-DIVE.md](references/REFLOG-DEEP-DIVE.md) |

### Branch + worktree craft
| Need | File |
|------|------|
| Taxonomy of branch and worktree smells | [BRANCH-WORKTREE-SMELLS.md](references/BRANCH-WORKTREE-SMELLS.md) |
| Working-tree-state guidance during the run (multi-worktree) | [WORKTREE-STATE.md](references/WORKTREE-STATE.md) |
| Bundle format spec (for tooling that consumes the bundle) | [BUNDLE-FORMAT-SPEC.md](references/BUNDLE-FORMAT-SPEC.md) |
| When NOT to use this skill | [WHEN-NOT-TO-USE.md](references/WHEN-NOT-TO-USE.md) |
| Per-language fingerprint patterns (Rust, TS/JS, Python, Go, Bash, C/C++, Java, SQL, Markdown, config) for Phase 5 triage | [LANGUAGE-PROFILES.md](references/LANGUAGE-PROFILES.md) |
| Per-archetype workflow adjustments (solo, trunk-based, GitFlow, release-train, monorepo, submodules, LFS, many-worktrees-per-PR, multi-remote, ...) | [REPO-ARCHETYPES.md](references/REPO-ARCHETYPES.md) |
| Difficult repo shapes beyond the 20 archetypes: sparse checkouts, shallow clones, partial clones, bare-as-worktree-hub, recursive submodules, LFS pointer caveats, git-annex, custom `core.worktree`, massive repos, stale commit-graph, mutating hooks, corporate proxies, case-insensitive FS, EOL normalization, non-UTF-8 paths, SHA-256 repos, very-long branch names, multi-FS worktrees, Docker-bind-mounted repos | [DIFFICULT-PROJECTS.md](references/DIFFICULT-PROJECTS.md) |

### Integration & coordination
| Need | File |
|------|------|
| Beads + Agent Mail + bv + dcg + slb integration recipes | [INTEGRATION.md](references/INTEGRATION.md) |
| Mining prior agent sessions via /cass for prior-run context, branch-intent attribution, per-file collision archaeology | [CASS-MINING.md](references/CASS-MINING.md) |
| Running alongside active agent swarms: pre-run handshake, during-run reservations, pause-and-resume, single-canonical-with-reservations strategy | [MULTI-AGENT-COORDINATION.md](references/MULTI-AGENT-COORDINATION.md) |
| Verbatim per-mode kickoff prompts (Quick / Standard / Comprehensive / Council / Triage-only / Apply-only / Resume / After-Swarm); decision tree | [KICKOFF-PROMPTS.md](references/KICKOFF-PROMPTS.md) |
| Orchestration tiers (Solo / Pair / Squad / Swarm / Council); fan-out diamond; parallelism boundaries; NTM topology; running after / during a swarm | [ORCHESTRATION.md](references/ORCHESTRATION.md) |
| Concurrent-agent failure modes (CA-1 .. CA-15): branch creation/deletion mid-run, canonical rebase/force-push, autostash drift, worktree drift, beads/Mail outages, NTM pane death, fetch-prune races, reservation theft, rat-branch external commits; per-failure detection / triage / recovery / prevention | [CONCURRENT-AGENT-FAILURE-MODES.md](references/CONCURRENT-AGENT-FAILURE-MODES.md) |

### Worked examples + recovery
| Need | File |
|------|------|
| The canonical worked example, annotated with operators | [WORKED-EXAMPLES.md](references/WORKED-EXAMPLES.md) |
| Seven additional end-to-end worked scenarios (A: solo Rust CLI / Quick mode; B: 47-branch swarm aftermath / Standard mode + after-swarm kickoff; C: 213-branch GitFlow long-running line / Comprehensive; D: 80-branch payment codebase / Council mode + duel-wizard + slb peer review; E: 35 PR-per-worktree project / scope-aware subset; F: monorepo-with-submodules cross-subproject; G: resumability of half-finished prior runs); per-scenario operator-glyph annotations + DCG-block markers | [WORKED-EXAMPLES-EXTENDED.md](references/WORKED-EXAMPLES-EXTENDED.md) |
| Recovery recipes — how to undo every kind of removal/deletion | [RECOVERY-RECIPES.md](references/RECOVERY-RECIPES.md) |
| Catastrophic recovery: gc-pruned commits, force-pushed canonicals, lost backups+bundles, submodule divergence, LFS gaps | [ADVANCED-RECOVERY.md](references/ADVANCED-RECOVERY.md) |
| Mid-run incident triage: byte-equality mismatch, concurrent worktree drift, cherry-pick conflict, hook fail, branch deleted out-of-band, canonical force-pushed, beads / Mail unavailable, disk full, UBS missing, submodule init fail, LFS missing, vague authorization, fresh-eyes non-convergence, force-push detected | [INCIDENT-PLAYBOOK.md](references/INCIDENT-PLAYBOOK.md) |

### Rigor & verification
| Need | File |
|------|------|
| Bayesian confidence calibration for triage verdicts; conformal acceptance threshold τ; worst-case bounds on multi-layer recovery; SPRT for fresh-eyes termination; distribution-shift detection; metamorphic relations as confidence boosters | [DECISION-THEORY.md](references/DECISION-THEORY.md) |
| The synthesis algorithm in detail: hunk dependency graph, AST-aware merge via ast-grep, semantic deduplication via canonical-form, refactor-vs-feature distinction, defensive-stage ordering, graceful failure on cycles and divergent shapes | [HARMONIZATION-DEEP-DIVE.md](references/HARMONIZATION-DEEP-DIVE.md) |
| Provenance chain — every byte on the rationalization branch traced back to a source variant; apply_log.tsv schema with provenance columns; per-line attribution; `provenance-trace.sh`; cryptographic anchors via `git notes` + GPG | [PROVENANCE-CHAIN.md](references/PROVENANCE-CHAIN.md) |
| Metamorphic relations for synthesis correctness (MR-1 through MR-7: identity, commutativity, idempotence, intent preservation, no regression, fingerprint coverage, dependency closure); per-MR test harness; Phase 9 integration | [TESTING-METAMORPHIC.md](references/TESTING-METAMORPHIC.md) |
| Fuzzing the bundle (round-trip under transformation), the per-branch diff (apply under context drift), the harmonization plan (variant matrix perturbation), and triage verdicts (input permutation); cargo-fuzz / honggfuzz / AFL++ harnesses; differential fuzzing across bundle readers | [TESTING-FUZZING.md](references/TESTING-FUZZING.md) |
| Conformance harness for the bundle format spec; per-spec-section check functions; compliance matrix (spec section × artifact × pass/fail); cross-version compatibility matrix; conformance anchor via the 40/40 integration test | [TESTING-CONFORMANCE.md](references/TESTING-CONFORMANCE.md) |

### Operational depth
| Need | File |
|------|------|
| Top-level `--dry-run` mode previews every Phase 8 + Phase 10 action in a single review artifact before any mutation; produces `dry_run_report.md` + `expected_outcomes.json` for real-run validation; per /saas-billing-patterns-for-stripe-and-paypal | [DRY-RUN-MODE.md](references/DRY-RUN-MODE.md) |
| Post-Phase-9 codebase audit on the rationalization branch (security, performance, correctness, API consistency, test coverage, commit-message quality); auto-fix + escalation; metamorphic intent-preservation check on harmonized syntheses; Phase 10 hard gate; per /codebase-audit + /multi-pass-bug-hunting | [AUDIT-AFTER-RUN.md](references/AUDIT-AFTER-RUN.md) |
| What the recovered commits unblock: newly-actionable beads via `bv --robot-triage --diff-since`; PR-state shifts via `gh`; suggested-new beads via /idea-wizard pattern matching; ready-to-close beads via keyword overlap; cumulative cross-run discovery | [UNBLOCKED-WORK.md](references/UNBLOCKED-WORK.md) |
| Per-phase profiling beyond MEASUREMENT.md SLOs; per-script + per-subagent + parallelism-efficiency timings; bottleneck callout; self-tuning suggestions for next run; cumulative baseline; per /profiling-software-performance | [PERFORMANCE-PROFILE.md](references/PERFORMANCE-PROFILE.md) |
| Detection and update of branch references in CI workflow YAML (`.github/workflows/`, `.gitlab-ci.yml`, Jenkinsfile, CircleCI), README install URLs, package.json, Dependabot, mergify, dockerfiles; refusal mode blocks Phase 10 cleanup until references are reconciled; cass-mined master→main migration session | [CI-WORKFLOW-AWARENESS.md](references/CI-WORKFLOW-AWARENESS.md) |
| Detection of confused remote topology — when a worktree's `origin` points at a local sibling instead of the canonical upstream; per-worktree remote classification; refusal of Phase 10 cleanup until acknowledged; correct push remote selection in Phase 11 handoff; cass-mined frankensqlite session | [REMOTE-AS-WORKTREE-FOOTGUN.md](references/REMOTE-AS-WORKTREE-FOOTGUN.md) |
| GPG signature handling (cherry-pick re-signs; never disable signing); `git notes` preservation via `git notes copy`; author identity (cherry-pick preserves; squash-merge does not — body citations not Co-Authored-By trailers); branch-protection rules requiring signed commits; merge-commit corner cases | [GIT-NOTES-AND-SIGNATURES.md](references/GIT-NOTES-AND-SIGNATURES.md) |

### Scope & breadth (per-language deep dives)
| Need | File |
|------|------|
| Rust-specific harmonization deep dive: Cargo.toml/.lock conflicts; `#[cfg(...)]` composition; mod.rs / use ordering; trait impls + derives; lifetime parameter changes; `unsafe` block additions; macros (`macro_rules!` and procedural); workspace member additions; build.rs caveats; rustfmt/clippy config conflicts; cherry-pick gotchas (edition mismatches, feature-unification surprises, derive-bound failures); UBS integration; `feature/redact-secrets` worked synthesis on `logger.rs` with full Rust-idiomatic code | [RUST-DEEP-DIVE.md](references/RUST-DEEP-DIVE.md) |
| TypeScript / JavaScript-specific harmonization deep dive: package.json conflicts (deps / scripts / peerDeps / workspaces); lockfile zoo (npm/pnpm/yarn/bun); tsconfig.json `compilerOptions` and `paths` mappings; `*.d.ts` augmentation; generic type-parameter conflicts; Angular/NestJS decorator order; `export` vs. `export default` divergence; JSX prop forwarding + `forwardRef` + `React.memo`; React-hooks ordering and exhaustive-deps; test files + snapshots; Storybook/MDX additivity; build-config (vite/next/webpack); ESLint/Prettier policy; `feature/auth-rework` worked synthesis on `lib/auth.ts` | [TYPESCRIPT-DEEP-DIVE.md](references/TYPESCRIPT-DEEP-DIVE.md) |

### Reference & context
| Need | File |
|------|------|
| World-class git workflows we adapt (Linux kernel, Chromium, Mozilla, Rust bors, LLVM, Tor, Stripe, GitHub) — what we steal and where we diverge | [EXEMPLARS.md](references/EXEMPLARS.md) |
| Glossary — every skill-specific term defined with cross-links to where it's defined in detail | [GLOSSARY.md](references/GLOSSARY.md) |
| Quote bank of distilled invariants (~42 entries) drawn from the 19 axioms, AGENTS.md, Pro Git §3 + §7, cass-mined sessions, harmonization-vs-picking | [KEY-INSIGHTS.md](references/KEY-INSIGHTS.md) |

---

## Scripts

### Phase 0 / 0.5 — Bootstrap

| Script | Phase | Purpose |
|--------|-------|---------|
| `scripts/git-doctor.sh` | 0 | Pre-flight repo health: refuses on bare/mid-rebase/mid-merge/mid-cherry-pick/mid-revert/mid-bisect, soft-warns on detached HEAD, dirty tree, no remote, [gone]-upstream branches, locked stale worktrees |
| `scripts/discover-project.sh` | 1 | Detect canonical, build/test/lint commands, branching model, merge style, protected-by-convention patterns; writes project_profile.json |
| `scripts/check-skills.sh` | 0.5 | Probe `~/.claude/skills/`, `~/.codex/skills/`, project-local; detect jsm install + auth; emit phase0_skill_inventory.json |
| `scripts/install-referenced-skills.sh` | 0.5 | Bulk-install missing helper skills via `jsm install`; idempotent; skips silently when jsm absent |
| `scripts/cass-mine.sh` | 0.5 | Five-query mine: project basename, "branch rationalization", "git worktree", "git branch -D", "harmonize branches" → cass_findings.md; skips silently if cass absent |
| `scripts/github-pr-awareness.sh` | 0.5 / 1 / 4 | If gh authenticated and GitHub remote: open PRs (head/base = PROTECTED candidates) + branch-protection rules → github_state.json; read-only |
| `scripts/snapshot-tree.sh` | 0 / 8 / 10 | Per-worktree status/diff/untracked snapshots; resume-aware via HEAD+status hash; used to detect concurrent-agent drift |
| `scripts/dry-run.sh` | 0 / 0.5 | Top-level `--dry-run` mode wrapper (operator 👁 DRY-RUN per [DRY-RUN-MODE.md](references/DRY-RUN-MODE.md)); routes Phases 0–9 through previewers; refuses to invoke any apply/cleanup script; prints a verbatim diff-of-intent before any state-changing run |

### Phase 2 — Inventory

| Script | Phase | Purpose |
|--------|-------|---------|
| `scripts/discover-branches-worktrees.sh` | 2 | Two-pass inventory: worktrees.tsv + branches.tsv + inventory_grouped.md (with `git cherry -v` cherry_plus / cherry_minus columns — Axiom 17 patch-id detector) |
| `scripts/prefix-classifier.sh` | 2 / 5 | Map a branch name to one of 18 canonical smell categories with default verdict prior + confidence; resume-aware via branches.tsv hash |

### Phase 3 — Bundle

| Script | Phase | Purpose |
|--------|-------|---------|
| `scripts/build-bundle.sh` | 3 | Backup refs + git object bundle + per-branch diffs + per-branch format-patch + per-worktree dirty captures + meta + index + README |
| `scripts/verify-bundle.sh` | 3 | Byte-equality + `git bundle list-heads` round-trip gate; halts on any mismatch |
| `scripts/bundle-audit.sh` | 3 / 10 / 11 | Deep cross-layer integrity audit (10 internal-coherence checks beyond byte-equality); used at three checkpoints |
| `scripts/recovery-test.sh` | 3 / 10 | Verifies recovery recipes actually work — clones repo, exercises branch restore + worktree dirty-state restore, verifies SHA + status match |
| `scripts/bundle-merge.sh` | 3 | Merge two recovery bundles into one (operator 📦 EXPORT); used when a triage-only run later resumes into an apply run, or when two parallel skill instances need their bundles unified before cleanup |
| `scripts/fuzz-bundle.sh` | 3 / 11 | Adversarial bundle integrity fuzzer (operator 🧪 FUZZ per [TESTING-FUZZING.md](references/TESTING-FUZZING.md)) — flips bytes, truncates streams, injects malformed refs; verifies that `verify-bundle.sh` halts on every corruption class; read-only against the canonical bundle |

### Phase 5–7 — Triage + Harmonization

| Script | Phase | Purpose |
|--------|-------|---------|
| `scripts/triage-batch.sh` | 5 | Worker — fingerprint + verify-on-canonical + cherry-vs-canonical + apply-check + verdict + strategy + files-touched |
| `scripts/merge-triage.sh` | 6 | Merge batch tsvs; sort by verdict then ASCENDING confidence (most-ambiguous-first surfaces user attention); build decision table |
| `scripts/verdict-stats.sh` | 6 / 11 | Per-verdict counts + mean/min/max confidence, file-collision count (Phase 7 driver), [gone] count, smell-pattern hits, SLO health flags |
| `scripts/harmonization-plan.sh` | 7 | Per-file variant matrix; identifies files touched by ≥2 non-protected branches; emits harmonization_plan.md |
| `scripts/reflog-deep-mine.sh` | 0.5 / 5 | Deep reflog mining (operator 🔍 REFLOG-DEEP per [REFLOG-DEEP-DIVE.md](references/REFLOG-DEEP-DIVE.md)) — `git reflog show`, `git log -g`, `fsck --lost-found`, cherry-pick chain detection, temporal verdict-flip; emits per-branch forensic timelines used by the `reflog-archaeologist` subagent to attach the `applied-keeper-elsewhere` forensic-finding to `superseded` rows |

### Phase 8 — Apply

| Script | Phase | Purpose |
|--------|-------|---------|
| `scripts/apply-keeper.sh` | 8 | Apply (cherry-pick / squash-merge / rebase-and-merge / harmonized-synthesis-delegate-to-main-agent / split-commits-hunks / dirty-worktree-only) → gates → commit; never bypasses pre-commit hooks |

### Phase 10–11 — Cleanup + Handoff

| Script | Phase | Purpose |
|--------|-------|---------|
| `scripts/drop-retire-confirmed.sh` | 10 | Cleanup with hard `confirm=YES_REMOVE_WT_<basename>` and `confirm=YES_DELETE_BR_<slug>` flags; worktree-first ordering; `-d` preferred over `-D`; protected items refused; never `rm -rf` |
| `scripts/handoff-report.sh` | 11 | Emit final report + recovery recipes (verbatim copy-paste); skill never pushes |
| `scripts/polish-bar-check.sh` | 11 | Verify run satisfied all 10 Polish Bar dimensions |
| `scripts/archive-workspace.sh` | 11+ | Tar workspace for resume / audit; collisions get `-1`, `-2`, ... up to 999; never deletes (Rule 1) |
| `scripts/find-unblocked-work.sh` | 11 | Post-rationalization Phase 11 helper (operator 🆔 UNBLOCK per [UNBLOCKED-WORK.md](references/UNBLOCKED-WORK.md)) — scans the apply log + beads + open PRs to surface tasks that were blocked by the now-rationalized branches; emits `unblocked_work.md` for the handoff report |

### Test + helpers

| Script | Phase | Purpose |
|--------|-------|---------|
| `scripts/integration-test.sh` | * | Synthetic-repo end-to-end smoke test (40 PASS expected) |
| `scripts/project-root.sh` | * | Shared helpers: `resolve_project_root`, `resolve_workspace`, `slugify_branch` (with sha1[0:12] suffix), `sanitize_path`, `tsv_read` |
| `scripts/performance-profile.sh` | * | Phase-timing instrumentation (operator ⏱ PROFILE per [PERFORMANCE-PROFILE.md](references/PERFORMANCE-PROFILE.md)) — wraps any phase script, records wall + CPU + IO + git-pack-size deltas; emits `<workspace>/profile/<phase>.tsv` for SLO health flags consumed by `verdict-stats.sh` |

Scripts are resume-aware, log to the workspace, and exit non-zero on any irreversible failure (the run halts; the user investigates). Recovery-bundle creation is fail-closed: a non-empty bundle is reused only after verification, or a fresh `BUNDLE_OVERRIDE` path is chosen. No script ever runs `rm -rf`, `git push --delete`, `git push --force`, `git reset --hard`, `git update-ref -d`, `git branch | xargs git branch -D`, or `--no-verify` — verified at lint time.

---

## Subagents

| Subagent | Phase | Purpose |
|----------|-------|---------|
| `subagents/project-profiler.md` | 1 | Brennerian opener; detect canonical + commands + branching/merge style + protected-by-convention patterns |
| `subagents/cass-miner.md` | 0.5 | Mine prior agent sessions via `/cass` for prior runs of this skill, prior manual rationalization sessions, past file-collision hot zones, and convention augmentations; skipped cleanly if cass is absent |
| `subagents/inventory-agent.md` | 2 | Two-pass inventory: worktrees + branches + grouping |
| `subagents/bundle-builder.md` | 3 | Backup refs + object bundle + per-branch diffs/format-patch + per-worktree dirty captures + verify |
| `subagents/audit-conductor.md` | 3 / 10 / 11 | Deep cross-layer integrity audit beyond `verify-bundle.sh`; three checkpoints (post-build, pre-cleanup, post-cleanup); halts the run on any finding |
| `subagents/conformance-checker.md` | 3 / 11 | Verify the bundle conforms to `BUNDLE-FORMAT-SPEC.md`; per-section, per-required-invariant compliance matrix; halts Phase 3 on any required-invariant failure (Phase 11 surfaces but doesn't halt) |
| `subagents/fuzzer.md` | 3 / 11 | Defense-in-depth fuzz of the bundle: tar-roundtrip, fs-copy, permission-strip, single-file-truncate, bit-flip-pack, bit-flip-diff, gz-truncate-untracked; flags cliff-edge failures where verify-bundle says healthy but recovery-test fails; never `rm -rf` fuzz copies (`mv` to `.archived`) |
| `subagents/ci-workflow-updater.md` | 4 | After PROTECTION CONFIRMATION: detect references to soon-to-be-deleted branches in `.github/workflows/*.yml`, `dependabot.yml`, `mergify.yml`, README install URLs, `package.json`, `Cargo.toml`, Dockerfiles, CHANGELOG.md; surface for user authorization; apply via Edit tool only (no sed/awk per AGENTS.md); refuses Phase 10 cleanup on unresolved will-break references |
| `subagents/triage-worker.md` | 5 | Per-batch fingerprint + verify-on-canonical + cherry-vs-canonical + verdict |
| `subagents/language-specialist.md` | 5 | Comprehensive only — language-aware re-fingerprint with ast-grep / language-AST tooling (Rust traits, TS generics, Python decorators, Go generics, C++ templates, SQL DDL); augments triage rows with same-signature evidence per Axiom 16 |
| `subagents/archaeologist.md` | 5 | Forensic intent reconstruction for `novel-but-stale` and `divergent-refactor` rows; uses git reflog + cass + beads + canonical's history; emits a recommendation that drives whether the branch enters harmonization, cherry-picks, or drops |
| `subagents/reflog-archaeologist.md` | 5 | Extended forensic reconstruction beyond `archaeologist`: full reflog walk (`git reflog show`, `git log -g`, `git fsck --lost-found`), cass session transcripts, `br history`; detects force-pushed upstreams, interactive-rebase artifacts, soft-reset chains, cherry-pick lineages; drives one of the canonical verdicts (`novel-and-accretive` / `superseded` / `divergent-refactor` / `garbage`) and, when `superseded`, attaches the forensic-finding label `applied-keeper-elsewhere` if reflog evidence shows the branch was the SOURCE of content now on canonical (the canonical 11-verdict taxonomy is unchanged; the label is metadata) |
| `subagents/triangulator.md` | 5 / 7 / 9 | Comprehensive / Council only — independent multi-model verification (Claude + Codex + Gemini, OR multi-stance Claude as Path-B fallback) on borderline triage rows, harmonization syntheses, and fresh-eyes findings; surfaces disagreements to user |
| `subagents/triage-merger.md` | 6 | Merge batches; present decision table; capture overrides |
| `subagents/harmonization-planner.md` | 7 | The per-file variant-matrix author; identifies intent groups; proposes synthesis |
| `subagents/semantic-collision-searcher.md` | 7 | Comprehensive / Council — uses semantic search (`/frankensearch-integration` if available; embedding-based ripgrep fallback) to find conceptual collisions that file-path matching misses (e.g., `redact_secrets` in `logger.rs` ≈ `sanitize_log_line` in `log_filter.rs`); augments `harmonization_plan.md` so the variant matrix doesn't miss cross-file conceptual duplicates |
| `subagents/dry-run-previewer.md` | 7.5 | Between Phase 7's user gate and Phase 8's first mutation: predict every Phase 8 + Phase 10 action without executing; uses `git merge-tree --write-tree` and `git apply --check` for no-touch previews; emits `dry_run_report.md` for user review and `expected_outcomes.json` so the actual run halts if reality diverges |
| `subagents/keeper-applier.md` | 8 | Apply each keeper via the strategy chosen in triage; run gates; commit |
| `subagents/commit-message-author.md` | 8 | Rewrite auto-generated commit messages on the rationalization branch into focused, why-explaining recovery + harmonization commit messages per `references/COMMIT-MESSAGE-CRAFT.md`; special depth for `harmonized-synthesis` (cite ALL source variants + intents + composition order) |
| `subagents/provenance-tracker.md` | 8 / 11 | Record every byte's source: source branch + commit + hunk + intent attribution (for harmonized commits); augments `apply_log.tsv`; emits `provenance.json`; writes `git notes` under `refs/notes/branch-rationalization-provenance` only when no pre-existing notes namespace conflicts |
| `subagents/partial-splitter.md` | 8b | Cherry-pick the novel subset of commits from partially-novel branches |
| `subagents/gpg-signing-handler.md` | 8 (post-apply) | When `project_profile.json:requires_signing=true`, detect unsigned commits via `git log --show-signature`, re-sign via `git commit --amend --no-edit -S` AFTER explicit verbatim user authorization; preserves git notes via `git notes copy`; propagates new SHAs across `apply_log.tsv` + `provenance.json` + `expected_outcomes.json`; skips silently when not required |
| `subagents/fresh-eyes.md` | 9 | Three review prompts × ≥2 rounds |
| `subagents/cleanup-conductor.md` | 10 | Gated removal/deletion in the worktree-first → branches-by-bucket order |
| `subagents/post-run-auditor.md` | 11 | Codebase-audit on the rationalization branch's tip: UBS + project lint + typecheck + format-check + security scanners (cargo-audit, npm-audit, pip-audit) + full test suite; for each harmonized commit, runs each source variant's tests against the synthesis (metamorphic relation MR-4 from `TESTING-METAMORPHIC.md`); blocks Phase 10 destructive cleanup on any FAIL or NEEDS-USER finding |
| `subagents/handoff-reporter.md` | 11 | Final report + beads issue + recovery recipes + push instructions |
| `subagents/unblocked-work-finder.md` | 11 | Cross-references rationalization-branch commits with beads + Agent Mail + `gh` to detect newly-actionable beads (`bv --robot-triage --diff-since`), closed-by-this-commit beads (`bv --robot-history`), open PRs whose head branch was rationalized, invalidated beads (recovery already implements the requested feature); optional `/idea-wizard` integration; appends `unblocked_work.md` to `handoff_report.md`; emits recommended `br update` + `gh pr close` script (DO NOT RUN AS-IS) |
| `subagents/performance-profiler.md` | * | Cross-phase passive observer; instruments script invocations via `time_phase` wrapper; aggregates per-phase totals, per-script breakdowns, parallelism efficiency; compares against `MEASUREMENT.md` SLOs; emits `performance_profile.md` with bottleneck callouts; self-tunes (recommends Squad tier on next run when Phase 5 is 3× SLO; recommends reducing Phase 9 round count when Phase 8 dominates and Phase 9 yields trivial findings) |
| `subagents/idea-wizard-reviewer.md` | 12 | Optional, off by default — fresh agent reviews the run from the user's perspective; files friction-point notes to `skill_feedback.md` and (optionally) opens beads issues against this skill itself; for skill maintainers, not for the end user |
| `subagents/incident-responder.md` | * | Mid-run incident triage (any phase) |

---

## Self-Test

Trigger phrases that should activate this skill:

- "rationalize my branches"
- "rationalize these branches down to main"
- "I have 200 local branches, can we clean up"
- "I have 40 worktrees, are any worth keeping?"
- "kill all my worktrees, save what's worth saving"
- "branch archaeology on /data/projects/foo"
- "I'm out of disk because of worktrees"
- "what's in all these agent-* branches?"
- "merge what's worth merging and delete the rest"
- "consolidate all agent branches into master"
- "collapse my repo down to main"
- "figure out which worktrees can be removed safely"
- "mine old branches for useful code"
- "clean up after the agent swarm"

Full trigger list + end-to-end smoke test on a synthetic repo: [SELF-TEST.md](SELF-TEST.md).
