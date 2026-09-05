# Worked Examples (Extended) — Seven End-to-End Scenarios

[WORKED-EXAMPLES.md](WORKED-EXAMPLES.md) covers the canonical asupersync 47-worktree+213-branch session as a single unbroken narrative. This file walks seven *additional* scenarios, each picked to stress a different axis of the skill: solo-developer minimums, swarm aftermath, long-running development lines, security-sensitive Council mode, many-worktrees-per-PR workflows, monorepo-with-submodule entanglement, and resumability of half-finished prior runs.

Operator glyphs annotate every cognitive move. The annotations are how the cards in [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) become memorable. DCG-block events are rendered as `⚠ DCG: <command> blocked → use <structured alternative>` so they stand out as *expected* rails, not surprises.

Every excerpt is illustrative (recast for the scenario); the formats follow [PHASES.md](PHASES.md) exit criteria and [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) layout.

---

## A. Solo-Developer / Quick Mode — Small Rust CLI

**Setup.** `~/code/zfsutil` is a single-author Rust CLI for ZFS snapshot grooming. The user prototyped 8 features over a year, none merged, plus 2 worktrees from a debugging detour two months ago. They want to clean up before publishing 1.0.

**Counts up front.**

```
$ git -C ~/code/zfsutil worktree list | wc -l
3                                # main + 2 linked
$ git -C ~/code/zfsutil branch | wc -l
9                                # main + 8 features
```

W=2, B=8 → **Quick mode** per the decision tree. No harmonization expected (single author, low collision likelihood).

### A.1 Intake confirmations

```
USER: rationalize my branches and worktrees in ~/code/zfsutil

AGENT: Reading repo health and counts.
  - 2 linked worktrees, 8 non-canonical branches.
  - Canonical: master (per `git symbolic-ref refs/remotes/origin/HEAD`).
  - Mode: Quick (single agent, ~15-30 min).
  - Tests: `cargo test`. Lint: `cargo clippy -- -D warnings`. Format: `cargo fmt --check`.
  - No CI (no `.github/workflows/`, no `Makefile`).
  - GitHub: gh authenticated; 0 open PRs.

  Initial protected list (auto): [master, currently-checked-out=feat/snapshot-pruning].
  Anything else to protect? Bundle path default: ~/code/zfsutil-branch-worktree-archive-2026-05-07/.

USER: that's fine. proceed.
```

### A.2 Phase 0.5 + 1 + 2 — Bootstrap

```
[★ INVENTORY (counts only, see below for full)]
$ ./scripts/git-doctor.sh ~/code/zfsutil
  ✓ git work tree, not bare; clean active worktree; git 2.42.
  ⚠ 1 branch with [gone] upstream: feat/old-prototype.

[Phase 1 — discover-project.sh]
  → project_profile.json:
       canonical: master
       merge_style: rebase-and-merge       # detected from git log on master (linear history)
       archetypes: [solo, rust-cli, no-ci]
       quality_gates: cargo test / cargo clippy / cargo fmt --check
       hooks: none

[Phase 2 — ★ INVENTORY full]
$ ./scripts/discover-branches-worktrees.sh ~/code/zfsutil
  → branches.tsv (8 rows): name, sha, ahead, behind, cherry_plus, cherry_minus, ...
  → worktrees.tsv (2 rows): path, branch, dirty, locked, prunable
  → inventory_grouped.md:
      family feat/* — 5 branches (~6 weeks old to ~10 months old)
      family wip/* — 2 branches
      family fix/* — 1 branch (feat/old-prototype)

  Worktree inventory:
    /tmp/zfsutil-debug-2026-03/   on detached HEAD@a1b2c3d   dirty: 47 lines staged + untracked tarball worth 2.1 MB
    /home/user/code/zfsutil-zfs-perf/   on feat/zfs-perf       clean

USER: hmm, /tmp/zfsutil-debug-2026-03/ — I forgot about that one. What's in it?

AGENT: 47 lines staged, all in src/snapshot.rs. Untracked: 2.1 MB of perf-trace dumps under
  perf-traces/ (tarball captured for the bundle). Branch is detached HEAD; commit on it
  has been on master for 8 weeks (cherry equivalent). The dirty content is a quick
  `dbg!` instrumentation patch you forgot to revert.

USER: yeah toss it.
```

### A.3 Phase 3 — Bundle (⬡ BUNDLE)

```
[⬡ BUNDLE — irreversibility gate before any destructive logic]
$ ./scripts/build-bundle.sh ~/code/zfsutil

  Backing up 8 branches as refs/branch-rationalization-backup/<slug> ...
  Capturing 2 worktrees' staged + unstaged + untracked state ...
  Writing object-bundle.pack via `git bundle create --all` ...
  Writing index.tsv, README.md ...

[verify-bundle.sh — byte-equality + git bundle list-heads round-trip]
  ✓ all 8 branch backup refs byte-equal to live branch refs
  ✓ all 2 worktree staged/unstaged diff hashes match
  ✓ untracked tarball SHA-256 matches the live capture
  ✓ git bundle list-heads round-trip clean

  → bundle_verification.log: 0 MISMATCH lines.
  → ~/code/zfsutil-branch-worktree-archive-2026-05-07/ (53 MB, dominated by the perf-trace tarball)

AGENT to USER: Bundle complete; every removal from here is reversible.
```

### A.4 Phase 5 — Triage (single agent, no fan-out)

```
[✦ FINGERPRINT, ◐ VERIFY-ON-CANONICAL — per branch]

feat/snapshot-pruning (currently checked out — auto-protected; skip triage):
  🔒 PROTECT — skipped

feat/zfs-perf:
  fingerprint: { fns: [bench_zfs_send, parallel_send_loop], tests: [test_send_throughput] }
  verify on canonical: NONE FOUND
  cherry_plus=14, cherry_minus=0 → all novel
  → novel-and-accretive, conf 0.93

feat/old-prototype ([gone] upstream):
  fingerprint: { fns: [list_snapshots_legacy] }
  verify on canonical: list_snapshots resolves at src/list.rs:212 with same signature; legacy variant deleted in PR #14
  → superseded, conf 0.97

feat/argmatch-overhaul:
  fingerprint: { fns: [parse_args_v2, ArgKind] }
  verify on canonical: parse_args at src/cli.rs:83 has signature `(env: &Env) -> Result<Args>`; v2 has `(env: &Env, locale: &str) -> Result<Args>`
  → divergent-refactor, conf 0.85   # signature divergence triggers Axiom 16

wip/cleanup-1, wip/cleanup-2:
  cherry_plus=0 in both cases → all changes are on master via squash-PR
  → already-merged, conf 0.99 each

feat/json-output:
  fingerprint: { fns: [json_emit, JsonOpt] }
  verify on canonical: NONE FOUND
  cherry_plus=3, cherry_minus=0
  → novel-and-accretive, conf 0.91

feat/zfs-recv:
  fingerprint: { fns: [recv_stream, parse_recv_header] }
  verify: recv_stream resolves at src/recv.rs:44 — same signature
  → superseded, conf 0.95

feat/colour-flag:
  fingerprint: { fns: [should_colorize] }
  verify on canonical: should_colorize at src/term.rs:11 — same signature
  → superseded, conf 0.96

[🌳 WORKTREE-CHECK — per worktree]

worktree:/tmp/zfsutil-debug-2026-03/   verdict dirty-worktree-only-then-discard (user OK)
worktree:.../zfsutil-zfs-perf/         verdict reuse-as-rationalization-source (the worktree's branch is the keeper)
```

### A.5 Phase 6 — User confirms, no overrides

Single keeper (`feat/zfs-perf`) plus optional `feat/json-output`; one divergent-refactor surfaced; rest are clean drops. No collisions across branches → **no Phase 7 harmonization** (Quick mode skips Phase 7 unless the variant matrix has rows).

### A.6 Phase 8 — Apply

```
[Cut rationalization branch from canonical's tip]
$ git checkout -b branch-rationalization-2026-05-07 master

[✧ CHERRY-PICK feat/json-output (3 commits)]
$ git cherry-pick c1..c3              # all clean
[⊕ RECOVER]
$ cargo test && cargo clippy -- -D warnings && cargo fmt --check    # ✓

[⊠ REBASE-AND-MERGE feat/zfs-perf (14 commits)]   # project's merge style is rebase-and-merge
$ git rebase --onto branch-rationalization-2026-05-07 master feat/zfs-perf
   # zero conflicts (it was independent of canonical's recent moves)
$ git checkout branch-rationalization-2026-05-07
$ git merge --ff-only feat/zfs-perf
[⊕ RECOVER]
$ cargo test && cargo clippy -- -D warnings        # ✓

[apply_log.tsv]
  feat/json-output → squash-merge → commit f0a1b2c → ✓ gates green
  feat/zfs-perf    → rebase-and-merge → commit g3d4e5f → ✓ gates green
```

`feat/argmatch-overhaul` (divergent-refactor) is not applied — surfaced to user; user defers ("I'll come back to that one"); branch stays on the rationalization branch list as `deferred`.

### A.7 Phase 9 — Fresh eyes (single round, Quick mode)

Round 1: clean. Quick mode requires only one round. ✓

### A.8 Phase 10 — Cleanup (gated)

```
[⚠ CONFIRM — restate verbatim]

AGENT: To proceed I'll run, in order:
  Worktree pruning:
    git worktree remove /tmp/zfsutil-debug-2026-03/ --force         # dirty; archived in bundle
    git worktree remove ~/code/zfsutil-zfs-perf/                    # clean
  Branch deletion (worktree-first per Axiom 9):
    git branch -d feat/old-prototype                                # superseded → -d works
    git branch -d feat/zfs-recv                                     # superseded
    git branch -d feat/colour-flag                                  # superseded
    git branch -d wip/cleanup-1                                     # already-merged
    git branch -d wip/cleanup-2                                     # already-merged
    git branch -d feat/json-output                                  # applied → fully merged on rat-branch
    git branch -d feat/zfs-perf                                     # applied → fully merged on rat-branch
  (feat/argmatch-overhaul DEFERRED, NOT deleted; user marked divergent-refactor)
  (feat/snapshot-pruning PROTECTED, NOT deleted; user is on it)

  Type verbatim: "yes proceed with cleanup as described above"

USER: yes proceed with cleanup as described above
       (recorded to cleanup_authorization.txt with timestamp)

⚠ DCG considered: rm -rf /tmp/zfsutil-debug-2026-03/ blocked → use git worktree remove instead.
   (The skill never tries; the structured operation is the right tool.)

[⊙ PRUNE-WORKTREE — worktree-first]
$ git worktree remove /tmp/zfsutil-debug-2026-03/ --force            ✓ removed
$ git worktree remove ~/code/zfsutil-zfs-perf/                       ✓ removed
$ git worktree prune                                                  ✓ residual metadata cleaned

[⊘ DELETE-BRANCH — branches second; -d preferred over -D]
$ git branch -d feat/old-prototype       Deleted branch feat/old-prototype
$ git branch -d feat/zfs-recv            Deleted branch feat/zfs-recv
... (5 more)
```

### A.9 Phase 11 — Handoff (⌘ HANDOFF)

```
# Branch + Worktree Rationalization — Handoff Report
Project:  ~/code/zfsutil
Mode:     Quick
Bundle:   ~/code/zfsutil-branch-worktree-archive-2026-05-07/  (53 MB)

## Counts
  Worktrees: 2 → 0
  Branches:  9 → 2 (master + branch-rationalization-2026-05-07; feat/argmatch-overhaul deferred)

## Recovered keepers
  | sha     | source                    | strategy           | gates |
  |---------|---------------------------|--------------------|-------|
  | f0a1b2c | feat/json-output          | squash-merge       | ✓     |
  | g3d4e5f | feat/zfs-perf             | rebase-and-merge   | ✓     |

## Push
  git push origin branch-rationalization-2026-05-07
  # Then open PR against master.

## Disk reclaimed
  ~2.4 GB (the /tmp worktree was holding 2.1 GB of perf traces).

## Bundle lifecycle
  Keep ~/code/zfsutil-branch-worktree-archive-2026-05-07/ for 1-4 weeks.
  ⚠ DCG: rm -rf <bundle> blocked → mv it to a trash location when ready.
```

**Operator-usage table for scenario A:** ★ ⬡ ✦ ◐ 🌳 🔒 ⚠ ✧ ⊠ ⊕ ⊙ ⊘ ⌘. Phases 7 (◇), 8b (⇄), and 12 not used (no collisions, no partial-novel rows, no user-lens review requested).

---

## B. Agent-Swarm Aftermath / Standard Mode — 47 Branches, 4 Colliders

**Setup.** A 3-day NTM swarm on `/data/projects/asupersync-fcp` left 47 `agent-cc-*` and `agent-cod-*` branches plus 6 worktrees. Four files were touched by ≥2 branches. The user wants to land what's worth landing and clean up; the swarm has stopped.

**Counts.** W=6 (incl. 4 NTM panes' worktrees), B=47 → **Standard mode**. After-swarm kickoff variant per [KICKOFF-PROMPTS.md § After-Swarm Mode](KICKOFF-PROMPTS.md#after-swarm-mode).

### B.1 Cass-mining flows in (Phase 0.5)

```
[Phase 0.5 — cass-mine.sh]
$ cass search "asupersync-fcp" --window 7d
  → 312 sessions, 49 unique panes
  → 11 sessions where an agent file-reservation conflicted with another
  → cass_findings.md flags collision-hot-zone: src/fcp/handler.rs touched by 12 sessions

[After-swarm mode auto-detected per cass + agent-mail.list_active_agents]
  → kickoff prompt tightens Phase 5 batch size 10 → 6
  → Phase 7 harmonization preemptively assumed
  → Phase 9 fresh-eyes adds 1 adversarial round (4 rounds total)

[Cass-mined per-branch annotation lands in inventory_grouped.md]
  agent-cc-7-fcp-handler-redact   prior session 2026-05-04T11:42 ended in autostash conflict on src/fcp/handler.rs
  agent-cod-3-fcp-handler-cap     prior session 2026-05-05T09:15 — author crashed before pushing; 4 commits orphan
```

### B.2 Phase 4 — Auto-protections

```
[🔒 PROTECT — auto-protections]
  master                                  (canonical)
  currently-checked-out: agent-cc-12-feat-fcp-tests  (the user's own active agent)
  release/2.x, release/3.x                (workflow protection per A4)
  4 worktrees pinned to active NTM panes  (per ORCHESTRATION.md heuristic)
  dependabot/cargo/serde-1.0.180          (per A14 conventions)

USER: also protect agent-cc-12-* (the family) — that's my active swarm.
USER: yes proceed.

  → protected.tsv: 7 branches, 4 worktrees flagged 🔒
```

### B.3 Phase 5 — Standard mode parallelism (4 triage workers)

```
[Pair tier scaling up to Squad: 4 parallel triage subagents]

  triage-worker-1  → batch_001.tsv  (12 rows: agent-cc-* batch 1)
  triage-worker-2  → batch_002.tsv  (12 rows: agent-cc-* batch 2)
  triage-worker-3  → batch_003.tsv  (12 rows: agent-cod-* batch 1)
  triage-worker-4  → batch_004.tsv  (11 rows: agent-cod-* + 6 worktrees)

[All four workers see the cass annotation and weight verdict accordingly]

  agent-cc-7-fcp-handler-redact: cass shows authoring-session conflict; cherry_plus=2, cherry_minus=0
    → novel-and-accretive (handler-redact intent), conf 0.88

  agent-cod-3-fcp-handler-cap: cass shows author crashed pre-push; cherry_plus=4, cherry_minus=1
    → partially-novel (cap intent + 1 already-on-canonical), conf 0.83 → split-apply

[Collision detection — Phase 5 emits collisions_preview.tsv]
  src/fcp/handler.rs touched by 5 branches → file goes to harmonization
  src/fcp/parser.rs touched by 3 branches → harmonization
  src/util/log.rs touched by 4 branches → harmonization
  src/cfg/load.rs touched by 2 branches → harmonization
```

### B.4 Phase 7 — Harmonization plan (◇ HARMONIZE)

For `src/fcp/handler.rs` (5 variants), the planner subagent produces:

```
file: src/fcp/handler.rs

variant                       | head sha   | hunks                          | intent       | proposed
------------------------------|------------|--------------------------------|--------------|---------
canonical                     | a1b2c3...  | (baseline; route() at line 84) | (baseline)   | base
agent-cc-1-handler-cleanup    | b3c4d5...  | + null-payload guard           | defensive    | adopt
agent-cc-7-fcp-handler-redact | c5d6e7...  | + redact_secrets() pre-write   | defensive    | adopt; compose with cc-1
agent-cod-3-fcp-handler-cap   | d7e8f9...  | + len-cap + 1 already-on-cn    | defensive    | adopt cap; skip already-on-cn commit
agent-cc-9-handler-rewrite    | e9f1a2...  | refactor: route() → match-arms | refactor     | adopt as new structure
agent-cod-7-handler-trace     | f1b2c3...  | + tracing instrumentation      | refactor     | compose; fold into cc-9's match-arms

  → synthesis: cc-9's match-arm structure as the spine; cc-1's null-guard at the entry;
                cc-7's redact_secrets in the OK arm; cod-3's len-cap in the OK arm;
                cod-7's tracing wrapping each arm.
                Tests lifted: 4 new test cases across the 5 branches.
                Confidence: 0.84 (high; intents are clearly orthogonal).
```

Files `parser.rs`, `log.rs`, `cfg/load.rs` get parallel matrices. The user reviews `harmonization_plan.md`; tweaks one synthesis (asks the planner to swap the cap-check before the redact, on perf grounds); approves.

### B.5 Phase 8 — Apply (⊕ + ⊞ RE-FINGERPRINT)

```
[Apply order — harmonized syntheses first, then non-colliding keepers]

1. ◇ HARMONIZED-SYNTHESIS for src/fcp/handler.rs        # uses Edit tool, not script
   → tests pass, clippy ✓, ubs clean
   → commit a1: "harmonize FCP handler defensive checks (null + cap + redact + trace) on top of match-arm refactor"
2. ◇ HARMONIZED-SYNTHESIS for src/fcp/parser.rs
3. ◇ HARMONIZED-SYNTHESIS for src/util/log.rs
4. ◇ HARMONIZED-SYNTHESIS for src/cfg/load.rs

[⊞ RE-FINGERPRINT — after each apply]
  After commit a1 lands the redact_secrets call: branch agent-cod-1-redact-helper now flips
  from novel-and-accretive to `superseded` (forensic-finding: `applied-keeper-elsewhere` —
  the branch's helper is now present in the synthesis).
  → triage.tsv updated; agent-cod-1-redact-helper moved to "drop in cleanup".

5-23. ✧ CHERRY-PICK 19 non-colliding keepers (one or two commits each; gates green per apply).
24. ⇄ SPLIT-COMMITS-HUNKS for agent-cod-3-fcp-handler-cap (3 of 4 commits novel; cherry-pick those 3).

  → 23 keeper commits + 4 harmonized syntheses on branch-rationalization-2026-05-07.
```

### B.6 Phase 9 + 10 — Adversarial fresh-eyes, gated cleanup

```
[Phase 9 — 4 rounds (Standard + after-swarm = +1 adversarial)]
  Round 1: 1 finding (a fixture path collision in 2 lifted tests); fixed.
  Round 2: 0 findings.
  Round 3: 0 findings.
  Round 4 (adversarial — looks for swarm-induced regressions): 0 findings.
  → terminate.

[Phase 10 — gated]
  ⚠ CONFIRM
  Worktree removal first (Axiom 9):
    git worktree remove /data/projects/asupersync-fcp-wt-3                       (clean)
    git worktree remove /data/projects/asupersync-fcp-wt-7                       (clean; not the active pane)
    (NTM-active-pane worktrees PROTECTED — not in the list)
  Branch deletions:
    Bucket 1 — garbage (3): ...
    Bucket 2 — already-merged (5): ...
    Bucket 3 — superseded · standard (12): ...
    Bucket 4 — superseded · forensic-finding `applied-keeper-elsewhere` (6): ...   # branches whose content was harmonized — they were the SOURCE
    Bucket 5 — applied-keeper (16): ...

  Type verbatim: yes drop these 47 branches and 2 worktrees per the plan above
USER: yes drop these 47 branches and 2 worktrees per the plan above

[⊙ + ⊘ — execute]
  ⚠ DCG: would block `git push --delete origin <branches>` if attempted — out of scope by default.
  ⚠ DCG: would block `rm -rf /data/projects/asupersync-fcp-wt-*` if attempted → use git worktree remove.
```

### B.7 Phase 11 — Handoff excerpt

```
## Counts
  Worktrees: 6 → 4 (4 NTM-active-pane worktrees preserved; 2 stale pruned)
  Branches:  47 → 8 (master + 4 release/* + 1 dependabot + currently-checked-out + rat-branch)
  Disk reclaimed: ~12 GB (mostly the 2 stale worktrees' caches)

## Recovered keepers
  4 harmonized syntheses + 19 cherry-picks + 1 split-apply (3-of-4 commits)

## Branch debt accrued
  Period: 2026-05-04 → 2026-05-07 (3 days, agent swarm)
  Branches created: 47
  Recovered as keepers (or harmonized): 23
  Branch yield: 49% — high because the swarm's collisions were genuinely productive

## Recommendations for ongoing work
  See [MULTI-AGENT-COORDINATION.md § 6 — file-reservation pattern](MULTI-AGENT-COORDINATION.md#6-the-single-canonical-with-reservations-strategy).
```

**Operators used:** ★ 🔒 🌳 ✦ ◐ ⬡ ⚠ ◇ ✧ ⇄ ⊕ ⊞ ↺ ⊙ ⊘ ⌘.

---

## C. Long-Running Development Line / Comprehensive Mode — 213 Branches, 12 Worktrees

**Setup.** `/data/projects/firmsync` is 18 months old on GitFlow. 213 local branches accumulated (mostly `feature/*` for `develop`), 12 worktrees including 2 with substantial dirty state from a 2-month-old debug session and a collision-test setup from a release post-mortem. Several `release/2.x`, `release/3.x` lines.

**Counts.** W=12, B=213 → **Comprehensive mode**, parallel triage workers (Squad tier — 6 workers), dedicated harmonization-planner subagent, multi-model triangulation enabled for ambiguous rows.

### C.1 Intake + archetype detection

```
[Phase 1 — discover-project.sh]
  archetypes: [gitflow, cargo-workspace, signed-commits, pre-commit, codeowners, beads-available]
  canonical: develop                            # GitFlow per A3 — NOT main
  rationalization branch will be cut from develop, not main
  auto-protected by convention:
    main, develop, release/2.x, release/3.x, hotfix/2.4.7, dependabot/*, renovate/*,
    gh-pages, codeowners-rule branches

USER: also protect feature/h2-redo-rebrand (still in flight — long-lived).
USER: bundle path /opt/archives/firmsync-2026-05-07/ — bigger disk.
USER: proceed Comprehensive.

  → protected.tsv: 23 branches, 4 worktrees flagged 🔒
```

### C.2 Phase 5 — Squad triage with archaeology subagent

```
[Squad tier: 6 parallel triage workers + 1 archaeologist + 1 language-specialist (Rust)]

  Workers split 213-23=190 branches into 6 batches of 31-32 each.
  Archaeologist runs against any row classified `novel-but-stale` or `divergent-refactor`.

[Verdict distribution after Phase 5]
  already-merged:           104  (54%)  — GitFlow's squash-into-develop pattern
  superseded:                38  (20%)
  garbage:                   24  (13%)  — abandoned WIP
  novel-and-accretive:       11   (6%)
  partially-novel:            4   (2%)
  novel-but-stale:            5   (3%)  — archaeologist consulted
  divergent-refactor:         3   (2%)
  dirty-worktree-only:        1   (1%)  — the 2-month-old debug worktree

[Archaeology output for novel-but-stale rows (Timeline reconstruction)]
  feature/legacy-import-path-fix:
    forensic: branched 2025-12-04, 2 commits;
              cass shows the agent crashed mid-task;
              the underlying bug *was* fixed on develop in PR #4178 (2026-01-10) but with a
              different approach. The branch's commits have a small fixture file the PR didn't pick up.
    recommendation: cherry-pick the fixture file only; archaeologist marks the rest superseded.
```

### C.3 Phase 7 — Dedicated harmonization-planner subagent

7 files have ≥2 colliding non-protected branches:

```
src/db/connection.rs     — 6 variants (defensive ×3, refactor ×2, performance ×1)
src/api/handlers.rs      — 4 variants
src/util/serde_helper.rs — 4 variants
config/runtime.toml      — 3 variants
src/cli/parse.rs         — 3 variants
src/auth/session.rs      — 3 variants
README.md                — 2 variants  (planner notes: doc-only collision; default to canonical's IA)
```

The harmonization-planner builds 7 variant matrices in parallel. For `src/db/connection.rs`:

```
file: src/db/connection.rs

variant                                | hunks                                            | intent      | proposed
---------------------------------------|--------------------------------------------------|-------------|--------
canonical                              | (baseline)                                       | base        | base
feature/db-pool-defaults               | + tightened pool defaults                        | defensive   | adopt
feature/db-tls-renegotiation           | + tls renegotiation handling                     | defensive   | adopt
feature/db-error-context               | + ConnError enum + anyhow::Context wrapping      | error-handle| adopt
feature/db-async-rewrite               | refactor: connect_sync → connect_async + traits  | refactor    | adopt as spine
feature/db-batched-pool                | refactor: BatchedPool variant                    | refactor    | DIVERGENT — surface to user
feature/db-perf-prepared-cache         | + prepared-statement cache                       | performance | adopt; fold into async spine

  → spine = feature/db-async-rewrite's async traits
  → defensive checks composed at connect entry
  → ConnError enum is the error type; anyhow::Context layered for call-site wrapping
  → prepared-statement cache lifts into the async impl
  → feature/db-batched-pool DEFERRED (user surfaces it as a separate PR — orthogonal architecture)
  Confidence: 0.81 (DIVERGENT row pulled the average down; 6 of 7 are clean)
```

User reviews; agrees on the divergent split (handle batched-pool separately); approves the rest.

### C.4 Phase 8 — Sequential apply with multi-model triangulation on contested syntheses

```
[For each of the 7 ◇ HARMONIZED-SYNTHESIS commits, multi-model triangulation runs:]
  - Claude (Opus, primary)
  - Codex (gpt-5.5)
  - Gemini (3-pro)
  Each emits its proposed synthesis; the planner adjudicates differences;
  unresolved disagreements surface to user.

[For the 11 novel-and-accretive cherry-picks: standard apply.]
[For the 4 partially-novel branches: ⇄ SPLIT-COMMITS-HUNKS.]
[For the 1 dirty-worktree-only row: capture diff, apply via ✧ on rat-branch.]

[Per-apply gates: cargo test --workspace; cargo clippy; cargo fmt; ubs; pre-commit hooks.]

[apply_log.tsv summary]
  7 harmonized-synthesis commits
  11 cherry-picks
  4 split-applies
  1 dirty-worktree-only commit
  Total: 23 commits on branch-rationalization-2026-05-07
```

### C.5 Phase 10 — Cleanup (worktree-first, then 6-bucket branch deletion)

```
[⚠ CONFIRM — verbatim plan with 213 branch lines + 12 worktree lines]
  Bucket 1 — garbage (24)
  Bucket 2 — already-merged (104)
  Bucket 3 — superseded (38)
  Bucket 4 — superseded-by-newer-branch (4 branches that re-introduced the same fingerprint
             as another branch in the same run; flagged by Phase 5 for de-dup)
  Bucket 5 — superseded · forensic-finding `applied-keeper-elsewhere` (12 — folded into harmonized syntheses; these branches were the SOURCE of the synthesized content)
  Bucket 6 — applied-keeper (8 — direct cherry-picks)
  Worktrees: prune 8 (4 are protected for active-pane usage; the 2 dirty are archived)

  Type verbatim: yes proceed with cleanup as described above
USER: yes proceed with cleanup as described above

[⊙ — worktrees pruned first]
[⊘ — branches deleted second; -d for fully-merged-on-rat-branch (162 branches)
                              -D for divergent-refactor + novel-but-stale opt-in deletions (28 branches)]
```

### C.6 Phase 11 — Handoff excerpt

```
## Counts
  Worktrees: 12 → 4
  Branches:  213 → 26 (canonical + 23 protected + rat-branch + 1 deferred)
  Recovered keepers: 23 commits (7 harmonized + 11 cherry-picks + 4 split + 1 dirty-only)

## Disk reclaimed
  ~47 GB (the 8 pruned worktrees including 2 with debug heap dumps)

## Bundle
  /opt/archives/firmsync-2026-05-07/   (12.4 GB; long-lived line → larger object pack)

## Push
  git push origin branch-rationalization-2026-05-07
  → opens a develop-targeted PR (GitFlow: rationalize → develop → main on next release)
```

**Operators used:** the full set ★ 🔒 🌳 ✦ ◐ ⬡ ⚠ ◇ ✧ ⊟ ⊠ ⇄ ⊕ ⊞ ↺ ⊙ ⊘ ⌘ — the canonical Comprehensive run.

---

## D. Production-Critical / Council Mode — 80 Branches, Payment Codebase

**Setup.** `/srv/payments/checkout-core` handles credit-card tokenization. Required signed commits, CODEOWNERS rules, mandatory PR review. 80 branches accumulated (mostly `feat/*` for hardening + 6 `agent-redact-*`). Multi-model triangulation **required** at every gate.

**Counts.** W=8, B=80 → **Council mode** because the user flags `--security-sensitive`. 12+ workers, dual-model (Claude + Codex + Gemini), council triangulation on triage AND harmonization.

### D.1 Bootstrap (signed-commits + codeowners archetypes)

```
[archetypes: [signed-commits, codeowners, gitflow, cargo-workspace, ubs-required]
[All Phase 8 commits will be GPG-signed automatically; the local key is configured]
[Pre-commit hook runs: cargo audit (no vulnerable deps), trufflehog (no secrets), tests]

[Council tier orchestration]
  - 8 parallel triage workers
  - 1 archaeologist
  - 1 language-specialist (Rust)
  - 3 triangulators (Claude, Codex, Gemini)
  - 1 harmonization-planner (consults all three triangulators)
```

### D.2 Phase 5 — Council triangulation on borderline rows

```
[Triangulation on every novel-but-stale + divergent-refactor row + every conf<0.85 row]

agent-redact-pass-2:
  Claude:  → novel-and-accretive (regex-based redaction; tests adopt)
  Codex:   → novel-and-accretive (agrees; flags the regex doesn't cover Visa BIN ranges)
  Gemini:  → divergent-refactor (the redaction approach competes with canonical's tokenizer)
  Adjudicator: Gemini's concern is real — canonical introduced PaymentTokenizer in 2026-04-12;
               the branch's regex predates it and would shadow it.
  Final: superseded-by-newer-branch (canonical's PaymentTokenizer); surface to user with cherry-pick option for the BIN-range tests only.

feature/idempotency-key-cache:
  Claude:  → novel-and-accretive (conf 0.78)
  Codex:   → novel-and-accretive (conf 0.91)
  Gemini:  → novel-and-accretive (conf 0.85)
  Final: novel-and-accretive (consensus; no triangulation surface)
```

### D.3 Phase 7 — Council harmonization

For `src/checkout/tokenize.rs` (touched by 7 branches), the harmonization-planner runs the variant matrix through all three models AND a /dueling-idea-wizards adversarial round per [DUELING-IDEA-WIZARDS-INTEGRATION.md](DUELING-IDEA-WIZARDS-INTEGRATION.md):

```
Wizard A (preserve every defensive intent): adopts all 7 variants' defensive checks
Wizard B (minimize total surface area): adopts 4 of 7; merges 2 into one helper

  → Adjudicator (third agent) reads both plans + the variant matrix:
    "Wizard A's plan is more conservative but adds 3 redundant length checks;
     Wizard B's collapsed-helper approach loses the per-vendor-network nuance.
     Recommend: take Wizard B's spine + Wizard A's per-vendor-network checks."

USER: agreed.
```

Result: `harmonization_plan_duel.md` records both plans + adjudication; the synthesis adopts the picked-of-each.

### D.4 Phase 8 — Apply with signed-commits + UBS gates

```
[Per-keeper, in addition to test/clippy/fmt:]
  cargo audit                  ← no vulnerable deps
  trufflehog filesystem .      ← no secrets
  ubs --strict src/             ← stricter than default
  git verify-commit HEAD        ← signed-commit verification

  All gates run on every harmonized-synthesis and every cherry-pick.
  If a gate fails before commit, the in-progress git operation is halted or
  aborted with the structured command for that operation (`cherry-pick --abort`,
  `merge --abort`, etc.). If a committed synthesis must be undone, use an
  explicit `git revert` plan with operator approval. The skill never uses
  `git reset --hard`, even on the rationalization branch.

[Council mode emits a per-commit triangulation note]
  commit a1b2c3: "harmonize tokenize.rs ... (council adjudicated: Wizard B spine + Wizard A per-vendor checks)"
  commit b4c5d6: "recover idempotency-key-cache (triangulator consensus; no synthesis)"
  ... 18 more
```

### D.5 Phase 9 — 3-round multi-model adjudicated fresh-eyes

```
Round 1 (Claude, security stance): 2 findings — 1 missing zeroize on PII buffer; 1 extra log statement.
Round 2 (Codex, performance stance): 0 findings.
Round 3 (Gemini, regression stance): 1 finding — a test fixture leaks a real-looking test card number.

  Council adjudicates: all 3 findings real; fix; re-run.
  Re-run: 0 findings across all three. Terminate.
```

### D.6 Phase 10 — Council-gated cleanup with peer review

```
[Council mode adds a peer-review step before Phase 10 — per /slb (Simultaneous Launch Button)]

AGENT: Cleanup plan ready. Per Council mode, requesting two-person rule per /slb.
  Peer agent (codex pane on the same project): please review the cleanup plan at
  .worktree_branch_rationalization_workspace/cleanup_plan.md and respond with
  "slb approved" if it looks right.

CODEX-PANE: slb approved (note: bucket 4 has 2 entries that look like applied-keeper rather than superseded; please reclassify before proceeding)

  → AGENT reclassifies; re-emits plan; CODEX-PANE re-approves.
USER: yes proceed with cleanup as described above

[Cleanup runs; signed-commit verifications pass on every deletion log entry; full audit trail.]
```

### D.7 Phase 11 — Council handoff with audit trail

```
## Audit-trail attestations
  - All 20 keeper commits signed by <gpg-fingerprint>
  - Multi-model triangulation log: triangulation_audit.tsv (3 models × 80 rows)
  - SLB cleanup approval log: slb_cleanup.txt (peer agent codex@2026-05-07T14:22Z)
  - Cleanup authorization recorded verbatim with UTC timestamp
  - Full bundle byte-equality + bundle round-trip verified at Phase 3 AND re-verified post-Phase-10
```

**Operators used:** the full set + duel-wizard + slb peer review.

---

## E. Many-Worktrees-Per-PR Workflow — 35 Worktrees, Mostly Protected

**Setup.** A team uses `git worktree` deliberately as their PR-review workflow: one worktree per open PR. 35 open PRs → 35 worktrees. The team also has 4 stale worktrees from PRs that merged 2 weeks ago but the cleanup hook didn't fire.

**Counts.** W=35, B=42 → would normally select Comprehensive, but `archetypes: [many-worktrees-per-pr]` (A8) triggers a different protection model: most worktrees are protected.

### E.1 Phase 0.5 — gh PR awareness lights up

```
[scripts/github-pr-awareness.sh]
  Open PRs: 35
  Each PR's head ref is a candidate PROTECT.
  Each PR's worktree is a candidate PROTECT.
  → github_state.json: 35 protected entries

[Phase 4 — protection confirmation]
AGENT: This repo matches archetype A8 (many-worktrees-per-PR). Of your 35 worktrees:
  - 35 correspond to open PRs (auto-protect candidates)
  -  4 are stale (their PRs merged ≥2 weeks ago — gh shows merged_at)
  -  0 are leftover from closed-without-merge PRs

For the 35 PR-active worktrees, please confirm per-worktree:
  (a) keep all 35 (default — full protection)
  (b) prune-but-keep-branch (worktrees gone, but the local branches stay so you can re-checkout)
  (c) prune-and-delete-branch (the PR is yours to re-create from origin if needed)

For the 4 stale worktrees:
  (default) prune; the merged content is on canonical; the worktree is dead weight.

USER: keep all 35 PR worktrees as-is. Prune the 4 stale + delete their branches.
```

### E.2 Phase 5 — Triage scoped to the 4 stale-worktree branches + 7 unaffiliated branches

The rationalization is a *subset* — only 11 branches and 4 worktrees enter the pipeline. The 35 PR-active branches and worktrees are 🔒 PROTECT and skipped after Phase 4.

```
[Triage rows: 11 branches + 4 stale worktrees]

  4 stale-worktree branches (their PRs merged 2-3 weeks ago):
    → already-merged, conf 0.99 each (cherry_plus=0; cherry_minus matches PR's commits)
  3 unaffiliated branches (no PR; agent-* leftovers):
    → 1 superseded, 2 novel-and-accretive
  4 unaffiliated wip/* branches:
    → 3 garbage, 1 superseded
```

### E.3 Phase 7 — No harmonization

11 branches, none collide on the same file. **Phase 7 skipped** — Standard mode would skip; the per-file collision threshold is what triggers harmonization, not branch count.

### E.4 Phase 8-10 — Lean apply + cleanup

```
[Phase 8]
  Two cherry-picks (the 2 novel-and-accretive branches); per-apply gates green.
  → 2 commits on branch-rationalization-2026-05-07.

[Phase 10 — cleanup]
  Worktrees: 4 stale removed (-d-eligible branches will follow).
  Branches: 4 stale (already-merged) deleted via -d.
            1 superseded deleted via -d.
            3 garbage deleted via -D (user explicitly OK'd unmerged).
            2 applied-keeper deleted via -d.

  35 PR-active branches and 35 PR-active worktrees: PROTECTED, untouched.
```

### E.5 Phase 11 — handoff with PR-workflow advice

```
## Worktrees: 35 → 31 (4 stale pruned; 31 PR-active preserved)
## Branches:  42 → 38 (35 PR + 1 canonical + 1 rat-branch + 1 deferred)

## Workflow advice
  Your 31 PR-active worktrees are healthy and preserved. To prevent stale-worktree
  drift in the future:
    - Configure your post-merge hook to auto-prune the worktree:
        if [ "$(git worktree list --porcelain | awk '/^worktree / {print $2}' | grep -- "$WORKTREE_PATH")" ]; then
          git worktree remove "$WORKTREE_PATH"
          git worktree prune
        fi
    - Alternatively, run /git-worktree-branch-rationalization in --triage-only mode
      monthly; the same skill in audit-only mode catches stale worktrees without
      mutating anything.
```

**Operators used:** ★ 🔒 🌳 ✦ ◐ ⬡ ⚠ ✧ ⊕ ⊙ ⊘ ⌘. ◇ HARMONIZE not used (no collisions). The point of this scenario: the skill is *scope-aware* — it doesn't bulldoze a healthy workflow.

---

## F. Monorepo with Submodules — Cross-Subproject Branches

**Setup.** `/data/projects/megaplatform` is a Cargo workspace with 12 crates, plus 4 git submodules (vendored upstream forks of `tokio`, `serde_json`, `clap`, `prost`). Several branches touch multiple subprojects AND advance submodule pointers. 60 branches, 4 worktrees.

**Counts.** W=4, B=60 → Standard mode escalating to Comprehensive because `archetypes: [cargo-workspace, submodules]` (A5 + A6 interactions add complexity).

### F.1 Phase 0 — submodule scope question

```
USER: rationalize this repo

AGENT: Detected:
  - Cargo workspace with 12 crates
  - 4 git submodules at: vendor/tokio, vendor/serde_json, vendor/clap, vendor/prost

Submodule scope question:
  (a) parent-repo only (default — submodules' own branches/worktrees out of scope)
  (b) parent + every submodule (recurse — heavy; rare)
  (c) parent + selected submodules (specify which)

USER: (a) parent only.
```

### F.2 Phase 2 — Worktree inventory captures submodule init state

```
[branches.tsv has touched-files; per-branch submodule-pointer-changed flag]
  feature/upgrade-tokio-1.42:
    touched: vendor/tokio (submodule pointer change), Cargo.lock
    submodule_pointer: vendor/tokio: <old-sha> → <new-sha>
  feature/serde-redo:
    touched: vendor/serde_json (submodule pointer change), src/api/encode.rs, Cargo.lock
    submodule_pointer: vendor/serde_json: <old-sha> → <new-sha>
  feature/parser-multi-crate:
    touched: crates/parser/src/lib.rs, crates/api/src/handlers.rs (cross-crate)
    submodule_pointer: (none)

[worktrees.tsv: per-worktree submodule init state]
  /data/projects/megaplatform/                 main worktree    submodules: all-init
  /data/projects/megaplatform-wt-tokio-test/   feat-tokio-test  submodules: tokio init; others uninit
  /data/projects/megaplatform-wt-debug/        debug branch     submodules: all-uninit (worktree was added without --init-submodules)
  /data/projects/megaplatform-wt-clap/         feat-clap        submodules: clap init only
```

### F.3 Phase 3 — Bundle records submodule pointers separately

```
[⬡ BUNDLE — submodule-aware]
  For each branch with a submodule pointer change:
    branches/<slug>/submodule_pointers.tsv:
      submodule_path | old_sha | new_sha
    NOTE: the submodule's *contents* are NOT in the bundle (they live in the submodule's own .git).
          The bundle preserves the parent's pointer. Restoring requires the submodule's remote to be reachable.

[bundle README.md notes]
  ## Submodule recovery caveat
  If you regret deleting feature/upgrade-tokio-1.42, the parent's pointer is restorable from
  refs/branch-rationalization-backup/<slug> + the bundle's submodule_pointers.tsv. To
  fully restore the working tree, run:
     git submodule update --init --recursive vendor/tokio
  This requires vendor/tokio's remote (git@github.com:upstream/tokio-fork) to be reachable.
```

### F.4 Phase 5 — Triage with cross-crate awareness

```
[For each branch, compute affected_packages (set of crate names from touched-files)]
  feature/parser-multi-crate: affected_packages = {parser, api}
  feature/upgrade-tokio-1.42: affected_packages = {tokio-vendor, lockfile}

[Verdict logic preserves cross-crate boundaries]
  feature/parser-multi-crate: novel-and-accretive → BUT the harmonization plan must consider that
                              both crates are touched. Per [REPO-ARCHETYPES.md A5](REPO-ARCHETYPES.md#a5--monorepo),
                              "synthesis must respect subproject boundaries."
```

### F.5 Phase 7 — Cross-crate harmonization

`crates/parser/src/lib.rs` is touched by 4 branches; `crates/api/src/handlers.rs` is touched by 5. Three branches touch both. The harmonization-planner emits TWO matrices but cross-references them:

```
file: crates/parser/src/lib.rs              file: crates/api/src/handlers.rs
  variants: 4 branches                        variants: 5 branches
  intent groups: 3 defensive + 1 refactor     intent groups: 4 defensive + 1 perf
                                              cross-link: feature/parser-multi-crate's
                                                          handler-side change depends on its
                                                          parser-side change. Apply parser-side
                                                          synthesis FIRST; api-side second.

[Phase 8 ordering respects cross-crate dependency]
  1. ◇ HARMONIZED-SYNTHESIS for crates/parser/src/lib.rs (parser-side first)
  2. cargo test -p parser     ✓
  3. ◇ HARMONIZED-SYNTHESIS for crates/api/src/handlers.rs (api-side, depends on parser)
  4. cargo test -p api        ✓
  5. cargo test --workspace   ✓ (final compose check)
```

### F.6 Phase 8 — Submodule pointer applies via cherry-pick

```
[Per-package gates (Turborepo / Cargo workspace style)]
  After each apply, run only the affected packages' tests; full workspace test at the end.

[For feature/upgrade-tokio-1.42 (submodule pointer):]
  ✧ CHERRY-PICK lifts the submodule-pointer-bump commit (and Cargo.lock).
  Then `git submodule update --init vendor/tokio`.
  cargo test -p tokio-vendor + cargo test --workspace.
  ✓ pointer landed; submodule contents fetched.

[For feature/serde-redo:]
  Two commits: the submodule pointer bump + the API change.
  ✧ CHERRY-PICK both; gates green.
```

### F.7 Phase 11 — Submodule notes in handoff

```
## Submodule pointer changes recovered
  vendor/tokio:      <old-sha> → <new-sha>      via feature/upgrade-tokio-1.42
  vendor/serde_json: <old-sha> → <new-sha>      via feature/serde-redo

## After-merge submodule init
  The rationalization branch's tip points at these new submodule SHAs.
  After merging the rat-branch into canonical, run:
    git submodule update --init --recursive
  to bring every working tree (including consumers' clones) up to date.
```

**Operators used:** the full set; A5+A6 interactions add the per-package gating + submodule-pointer recovery story.

---

## G. Recovery from a Half-Finished Prior Run — Resumability

**Setup.** A user kicked off a Comprehensive run yesterday on `/data/projects/dataframe-engine`, then their laptop ran out of battery during Phase 8 (apply). Today they're back; the workspace `.worktree_branch_rationalization_workspace/` is half-populated. `apply_log.tsv` shows 12 of 23 keepers applied successfully; the 13th was mid-cherry-pick when the session died. The bundle at `<parent>/dataframe-engine-branch-worktree-archive-2026-05-06/` is complete.

### G.1 Intake detects the prior run

```
USER: continue rationalizing /data/projects/dataframe-engine

AGENT: Detected an existing workspace at .worktree_branch_rationalization_workspace/ from
  yesterday (2026-05-06T19:42Z, ~14h ago). State summary:
    - Phase 0 / 1 / 2 / 3 / 4 / 5 / 6 / 7: complete (artifacts present + valid)
    - Phase 8: partially complete (12 of 23 keepers applied per apply_log.tsv)
    - Phase 9 / 10 / 11: not started

  Bundle at /data/projects/dataframe-engine-branch-worktree-archive-2026-05-06/ exists
  and verifies byte-equal to live refs. Recovery story is intact.

  Options:
    (a) Resume from where Phase 8 left off (preferred — all artifacts validate)
    (b) Archive the workspace and start fresh
    (c) Abort

USER: a
```

### G.2 Resume validation (Phase 8 preflight)

```
[Phase 8 resume-aware preflight]
  Read apply_log.tsv:
    Row 12: agent-cleanup-pass-3 → cherry-pick → commit 4a5b6c7d → ✓ gates green
    Row 13: feature/json-vec-encode → cherry-pick → STARTED but no commit_sha; gates_status=incomplete
    Rows 14-23: not started

  Verify the rationalization branch tip:
    branch-rationalization-2026-05-06 tip = 4a5b6c7d (matches row 12)
    No commit on rat-branch beyond row 12. ✓

  Verify the bundle still byte-equal:
    scripts/verify-bundle.sh: ✓ all 60 branches and 6 worktrees still byte-equal to backup refs.
    No drift since yesterday.

  Concurrent agent check:
    No active reservations on .git/refs/heads/**. ✓
    No new branches in `git branch | wc -l` since yesterday. ✓
    No worktree drift detected via Phase 0 baseline diff.

  Resume safe. Re-acquire Agent Mail reservations and continue.
```

### G.3 Resume Phase 8 from row 13

```
[The mid-cherry-pick from yesterday left no half-applied state on the rat-branch
 (the gates failed before commit; no partial commit landed)]

  Row 13: feature/json-vec-encode
    [↺ WORKING-TREE-DRIFT — re-snapshot before apply]
    Status clean.
    [✧ CHERRY-PICK retry]
    git cherry-pick <sha>
    Conflict: Cargo.toml (a dependency-version conflict that wasn't there yesterday because
              row 12 bumped serde to 1.0.180 and now row 13 wants 1.0.179 — STALE).
    [⊞ RE-FINGERPRINT given that row 12 changed serde version]
    The cherry-pick attempt's conflict reveals row 13's diff is actually superseded by row 12's
    bump. Reclassify row 13 as superseded; skip.
    git cherry-pick --abort.
    apply_log.tsv: row 13 marked superseded-after-re-fingerprint, gates_status=skipped-superseded.

  Row 14-23: continue normally.
    Row 14 (◇ HARMONIZED-SYNTHESIS for src/df/group_by.rs): apply via Edit tool; 4 variants composed; ✓ gates.
    Row 15-22 (cherry-picks): all clean; ✓ gates.
    Row 23 (⇄ SPLIT-COMMITS-HUNKS for feature/parser-batched): 2 of 3 commits novel; ✓ gates.

  Phase 8 complete. Resume to Phase 9.
```

### G.4 Phase 9-11 — proceed normally

```
[Phase 9 — fresh-eyes]
  3 rounds (Comprehensive); 0 findings after round 2 → terminate.

[Phase 10 — cleanup with verbatim authorization]
  ⚠ CONFIRM: 60-branch + 6-worktree plan presented.
  USER: yes proceed with cleanup as described above
  ⊙ + ⊘ executes; bundle stays.

[Phase 11 — handoff]
  Note in handoff_report.md:
    "This run was resumed from a 2026-05-06 partial run. The original Phase 0-7 artifacts
     were validated unchanged at resume; Phase 8 picked up at keeper 13 and reclassified it
     to superseded mid-run. apply_log.tsv shows the resume seam with timestamps."
```

### G.5 Resume edge cases (in scope of the demo)

| Resume scenario | Behavior |
|-----------------|----------|
| `apply_log.tsv` shows row N with no commit and gates_status=in-progress | Retry the apply; if still fails, surface to user |
| The rat-branch tip is BEYOND apply_log.tsv's last row (concurrent agent committed during yesterday's run) | Halt; surface to user; force-branch-tip mismatch is an incident I5 |
| Bundle has drifted (verify-bundle.sh fails) | Halt; this is incident I1 — refuse to resume |
| Concurrent agent created/deleted a branch since yesterday | Re-run Phase 2, keep Phase 3 if bundle still byte-equal, redo Phases 5-7 only for changed rows |
| User wants to skip the rest of Phase 8 and go straight to Phase 10 | Refuse; per Polish Bar, Phase 8 must complete before Phase 9; per Phase 9, ≥2 clean rounds before Phase 10 |

### G.6 Resume validates resumability across phase boundaries

The skill's design — every phase boundary persists a deterministic artifact set per [PHASES.md § Idempotence & Resumability](PHASES.md) — is what makes this scenario painless. The bundle is the recovery story; `apply_log.tsv` is the idempotency log; `branches.tsv` + `triage.tsv` + `harmonization_plan.md` are the decision record. Together they let any phase boundary be a clean resume point.

**Operators used in resume:** ★ ⬡ ✦ ◐ 🌳 ↺ ✧ ◇ ⊞ ⇄ ⊕ ⊙ ⊘ ⌘. The resume itself doesn't introduce new operators — it exercises the *idempotency* of every existing one.

---

## Cross-References

- Operator definitions: [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md)
- Per-phase exit criteria: [PHASES.md](PHASES.md)
- Variant matrix structure: [HARMONIZATION.md](HARMONIZATION.md)
- Multi-agent coordination: [MULTI-AGENT-COORDINATION.md](MULTI-AGENT-COORDINATION.md), [CONCURRENT-AGENT-FAILURE-MODES.md](CONCURRENT-AGENT-FAILURE-MODES.md)
- Council triangulation + duel-wizard: [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md), [DUELING-IDEA-WIZARDS-INTEGRATION.md](DUELING-IDEA-WIZARDS-INTEGRATION.md)
- Difficult repo shapes: [REPO-ARCHETYPES.md](REPO-ARCHETYPES.md), [DIFFICULT-PROJECTS.md](DIFFICULT-PROJECTS.md)
- Recovery details: [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md), [ADVANCED-RECOVERY.md](ADVANCED-RECOVERY.md)
- Resume-from-incident: [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md)
- The canonical example (asupersync 47×213): [WORKED-EXAMPLES.md](WORKED-EXAMPLES.md)
