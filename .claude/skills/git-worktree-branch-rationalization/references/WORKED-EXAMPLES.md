# Worked Examples — Placeholder Until First Real Run

This file is the canonical worked-example anchor for `git-worktree-branch-rationalization`. Per the skill's design and the user's spec, the **real** canonical worked example is intentionally deferred until the skill has been run end-to-end against a real messy project. The current top candidate is asupersync's branch+worktree pile (`/data/projects/asupersync` — the same project the sibling skill's [WORKED-EXAMPLES.md](../../git-stash-janitor/references/WORKED-EXAMPLES.md) used for its 127-stash run).

Until that real run lands, this file contains:

1. The **format and conventions** the canonical example will follow when written.
2. A short **synthetic stub** based on [SELF-TEST.md](../SELF-TEST.md)'s 8-branch test scenario — purely illustrative; clearly marked synthetic — so future readers have something concrete to learn from until the real run lands.
3. **Conventions for adding the real worked example later** (PR-style, edit this file in place).

> **Why a placeholder?** The sibling skill's [WORKED-EXAMPLES.md](../../git-stash-janitor/references/WORKED-EXAMPLES.md) demonstrates how a real run becomes the load-bearing teaching artifact. Writing one before the skill has actually run end-to-end on a non-trivial project produces aspirational fiction; writing it after produces operationalized knowledge. We choose the latter.

---

## Format & Conventions for the Canonical Worked Example

Every section of the eventual canonical worked example follows the sibling skill's pattern:

### 1. Verbatim agent dialogue

The example reproduces the actual session transcript: user prompts, agent responses, tool outputs, all interleaved as they occurred. No summary-mode rewriting — the raw exchange teaches more than a curated abstract.

### 2. Per-cognitive-move operator annotation

Each cognitive move is annotated inline with its operator glyph, so future readers can map session events back to the [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) cards. The full set of operators that should appear in a complete run, with the phase each typically appears in:

| Glyph | Operator | Phase | What it marks in the transcript |
|-------|----------|-------|----------------------------------|
| `★` | INVENTORY | Phase 2 | Two-pass capture → `worktrees.tsv` + `branches.tsv` |
| `🔒` | PROTECT | Phases 0, 4 | Auto-protected items + user-flagged keep-forever |
| `🌳` | WORKTREE-CHECK | Phase 3, then Phase 10 | Pre-removal dirty-state verification |
| `✦` | FINGERPRINT | Phase 5 | Symbol/test/file extraction per branch |
| `◐` | VERIFY-ON-CANONICAL | Phase 5 | Grep / ast-grep / `git cherry -v` against canonical |
| `⬡` | BUNDLE | Phase 3 | Backup refs + object bundle + diffs + meta + index — the irreversibility gate |
| `⚠` | CONFIRM | Phases 6, 7, 10 | Verbatim user authorization captured |
| `◇` | HARMONIZE | Phase 7 | Per-file variant matrix + best-of-all-worlds synthesis |
| `✧` | CHERRY-PICK | Phase 8 | Single-commit / small-coherent applies |
| `⊟` | SQUASH-MERGE | Phase 8 | Squash applies (when project_profile says squash) |
| `⊠` | REBASE-AND-MERGE | Phase 8 | Replay large branch commit sequences without mutating source branches |
| `⇄` | SPLIT-COMMITS-HUNKS | Phase 8b | Partially-novel branch subset cherry-picks |
| `⊕` | RECOVER | Phase 8 | Project's actual quality gates after each apply |
| `⊞` | RE-FINGERPRINT | Phase 8 | Downstream candidate re-checks after each apply |
| `↺` | WORKING-TREE-DRIFT | Phase 8 | Concurrent-agent change detection without disturbance |
| `⊙` | PRUNE-WORKTREE | Phase 10 | `git worktree remove <path>` (worktrees first) |
| `⊘` | DELETE-BRANCH | Phase 10 | `git branch -d`/`-D` (branches second, after worktrees) |
| `⌘` | HANDOFF | Phase 11 | Final report + recovery recipes + push instructions |

### 3. DCG-block annotations

Per [SKILL.md Anti-Patterns](../SKILL.md#anti-patterns-never-do), every `rm -rf` attempt — including any the agent considered and abandoned — is annotated as `[DCG block]` so future readers see the "design around the guard, don't fight it" pattern in action. The sibling skill's worked example has a canonical instance: the agent considered cleaning up the bundle's working files with `rm -rf`, DCG blocked it, and the agent didn't fight the block.

### 4. Failure-then-recovery moments

Where applicable, the example shows where a Phase 8 apply failed (apply-check refused, conflict surfaced, gates went red) and how the agent recovered (Edit-tool manual resolution, escalation to user, re-running gates after fix). These are the highest-value teaching moments — successful happy-path cherry-picks teach less than a single conflict resolution done right.

### 5. Verdict-distribution table

End-of-run table summarizing how the inputs distributed across verdicts:

| Verdict | Count | Examples |
|---------|-------|----------|
| protected | M | release/2.x, hotfix/CVE-2026-1234, dependabot/cargo/tokio-1.41 |
| already-merged | M | BACK-1742-fix, BACK-1801-test |
| superseded | M | wip-BACK-1742-take-3, agent-cleanup-2026-04-29-attempt-1 |
| superseded-by-newer-branch | M | (per-pair attribution: superseded by which sibling) |
| novel-and-accretive | M | feature/parse-hardening |
| partially-novel | M | feature/oauth-flow (subset commits applied) |
| novel-but-stale | M | (surfaced to user; not auto-applied) |
| divergent-refactor | M | (harmonization candidate) |
| dirty-worktree-only | M | per-worktree-path |
| garbage | M | full-tree-reset-stash branches, agent-attempt-N siblings |
| user-owned-sandbox | M | alice/sandbox-bench |

Plus per-worktree counts: `pruned`, `protected`, `had-dirty-state-archived`.

### 6. Operator usage table

Like the sibling skill's "Operator usage table (this session)" — which operators were invoked, in which phases, and how many times. This makes operator coverage a measurable property of the run.

### 7. "What this run taught us" section

End-of-example list of concrete lessons codified into the skill (anti-patterns, failure modes, new operator cards, prompt refinements). This is the link from "the run happened" to "the skill is better next time" — the sibling skill's section 7 ("What this run taught us") is the model.

---

## Synthetic Stub — SELF-TEST 8-Branch Scenario

> **MARKED SYNTHETIC.** This stub is illustrative only — it does NOT represent a real run. It exists so future readers have a concrete walkthrough until the real worked example lands. When the real example is added, this stub stays in place but is clearly demoted ("synthetic stub, kept for illustrative purposes"). See "Conventions for adding the real worked example" below.

The synthetic test scenario in [SELF-TEST.md](../SELF-TEST.md) uses 8 branches and 3 worktrees in a fixture repo:

**Branches:**

1. `main` — canonical (5 commits)
2. `release/v0.1` — protected
3. `feature/parser-hardening` — novel-and-accretive (2 commits, no overlap with main)
4. `feature/auth-rework` — partially-novel (3 commits; 1st is on main, 2nd-3rd are novel)
5. `agent-fix-deadlock-2026-04-29-attempt-1` — superseded (canonical has the patch-id-equivalent fix)
6. `agent-fix-deadlock-2026-04-29-attempt-2` — superseded-by-newer-branch (same fingerprint as -attempt-1, older commit date)
7. `wip-BACK-1742-take-3` — already-merged (ticket landed under different branch name)
8. `feature/parser-improvements` — divergent-refactor (touches the same parser.rs as `feature/parser-hardening`; harmonization candidate)

**Worktrees:**

1. `<repo>` (active, on `main`) — auto-protected
2. `<repo>-wt-auth-rework` (on `feature/auth-rework`) — clean
3. `/tmp/<repo>-spike-parser` (on `feature/parser-improvements`) — dirty (3 untracked files representing experimental fixtures)

### Walkthrough — Successful Run

**Phase 0 INTAKE.** Agent runs `git worktree list | wc -l` and `git branch | wc -l`, reports counts to user.

```
Worktrees: 3 total (1 active, 2 linked)
Branches: 8 total (1 canonical, 1 release-protected, 6 to triage)
Detected canonical: main
Mode: Standard (5 ≤ W < 20 OR 5 ≤ B < 30)
Bundle path: /tmp/synthetic-fixture-branch-worktree-archive-2026-05-07/
Initial protection: release/v0.1 (auto), main (auto), active worktree (auto)
Confirmed by user: yes
```

**Phase 1 PROFILE.** Agent reads `AGENTS.md`, detects `cargo test` / `cargo clippy` / etc.; writes `project_profile.json`.

**Phase 2 INVENTORY.** [★ INVENTORY] Two-pass capture produces `worktrees.tsv` (3 rows) and `branches.tsv` (8 rows).

**Phase 3 BUNDLE.** [⬡ BUNDLE — the irreversibility gate] Agent creates backup refs for the 6 non-protected branches, captures per-branch diffs and format-patches, captures the dirty-worktree's staged + unstaged + untracked-tarball, runs the 6-step verification protocol from [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md). All checks pass.

```
Bundle complete:
  branches/feature_parser-hardening/{meta,commits.tsv,diff-vs-merge-base.diff,format-patch/{0001,0002}}
  branches/feature_auth-rework/{...}
  branches/feature_parser-improvements/{...}
  branches/agent-fix-deadlock-2026-04-29-attempt-1/{...}
  branches/agent-fix-deadlock-2026-04-29-attempt-2/{...}
  branches/wip-BACK-1742-take-3/{...}
  worktrees/_tmp_synthetic-fixture-spike-parser/{meta,status,staged.diff,unstaged.diff,.untracked.list,untracked.tar.gz}
  object-bundle.pack    18.7 MB
  index.tsv             9 rows (header + 6 branches + 3 worktrees including the protected ones)
  README.md             4.3 KB

Verification:
  ✓ Per-entry artifact presence
  ✓ Backup ref byte-equality (6/6)
  ✓ git bundle list-heads round-trip
  ✓ Per-branch diff sha256 round-trip (6/6)
  ✓ Per-branch format-patch series count match (6/6)
  ✓ Per-worktree dirty re-snapshot (1/1; no drift since Phase 0)
```

**Phase 4 PROTECTION CONFIRMATION.** [🔒 PROTECT] Agent shows the auto-protected list, asks user to add or remove items. User adds nothing; confirms.

**Phase 5 TRIAGE FAN-OUT.** [✦ FINGERPRINT, ◐ VERIFY-ON-CANONICAL] Two parallel triage workers (Standard mode = Pair tier) classify the 6 non-protected branches:

```
feature/parser-hardening:
  fingerprint: { fns: [parse_strict_header, validate_payload], tests: [test_parser_strict_header_overflow] }
  verify_on_canonical: NONE FOUND
  cherry -v: 2 + lines (2 novel commits)
  → novel-and-accretive, conf 0.92

feature/auth-rework:
  fingerprint: { fns: [build_jwt_claims, refresh_token_rotation], tests: [test_token_rotation_after_grace] }
  verify_on_canonical: build_jwt_claims at src/auth/mod.rs:42 ✓ (1st commit landed)
                       refresh_token_rotation: NOT FOUND (2nd-3rd commits are novel)
  cherry -v: 1 -, 2 + (1 already-merged, 2 novel)
  → partially-novel, conf 0.88

feature/parser-improvements:
  fingerprint: { fns: [parse_strict_header (different signature!), parse_with_recovery], tests: [...] }
  verify_on_canonical: NONE FOUND on main
                       parse_strict_header collides with feature/parser-hardening (same name, divergent body)
  cherry -v: 1 + (1 commit unique vs main)
  → divergent-refactor, conf 0.85; HARMONIZATION CANDIDATE with feature/parser-hardening

agent-fix-deadlock-2026-04-29-attempt-1:
  fingerprint: { fns: [reclaim_deadlock_via_timeout] }
  verify_on_canonical: src/mutex.rs:218 ✓ same signature, same body (patch-id matches via git cherry -v)
  cherry -v: all - lines
  → superseded, conf 0.97

agent-fix-deadlock-2026-04-29-attempt-2:
  fingerprint: { fns: [reclaim_deadlock_via_timeout] }   # same!
  verify_on_canonical: ... (same as -attempt-1)
  AND: same fingerprint as agent-fix-deadlock-2026-04-29-attempt-1, older commit date
  → superseded-by-newer-branch, conf 0.95

wip-BACK-1742-take-3:
  fingerprint: { fns: [validate_backend_url, parse_backend_response], tests: [test_BACK_1742_url_format] }
  verify_on_canonical: src/backend/mod.rs ✓ patch-id matches via git cherry -v
                       BACK-1742 appears in commit message on main
  → already-merged, conf 0.98
```

The triage merger merges the 2 batch tsvs into `triage.tsv`.

**Phase 6 TRIAGE MERGE & CONFIRM.** [⚠ CONFIRM] Decision table presented to user:

```
KEEP — novel-and-accretive (1):  feature/parser-hardening
KEEP — partially-novel (1):      feature/auth-rework (2 of 3 commits)
HARMONIZE — divergent-refactor (1): feature/parser-improvements (with feature/parser-hardening)
DROP — already-merged (1):       wip-BACK-1742-take-3
DROP — superseded (1):           agent-fix-deadlock-2026-04-29-attempt-1
DROP — superseded-by-newer-branch (1):  agent-fix-deadlock-2026-04-29-attempt-2
PROTECT (2):                     main, release/v0.1
PRUNE — worktrees:               2 linked + 1 dirty (capture-then-confirm)
                                 active worktree auto-protected (skill never removes CWD)

Total: 6 non-protected branches → 1 keeper + 1 partial + 1 harmonization synth + 3 drops
       3 worktrees → 0 protected (just CWD) + 2 prune candidates + 1 dirty (capture-then-confirm)

Proceed to Phase 7 harmonization plan?

USER: yes
```

**Phase 7 HARMONIZATION PLAN.** [◇ HARMONIZE] Agent builds the variant matrix for `src/parser.rs` (the file touched by both `feature/parser-hardening` and `feature/parser-improvements`):

```
File: src/parser.rs
Variants:
  - main (current canonical structure: legacy parser, no strict-header)
  - feature/parser-hardening: adds parse_strict_header (defensive bounds checking,
    explicit error type StrictHeaderError, test coverage for overflow)
  - feature/parser-improvements: refactors parse_strict_header into parse_with_recovery
    (different signature, returns Result<Parsed, RecoveryHint>) and adds streaming-parse path

Synthesis (proposed best-of-all-worlds):
  1. Adopt parser-hardening's strict-header validation as the default safe path
  2. Adopt parser-improvements's RecoveryHint enum as the error-info channel
     (richer than parser-hardening's plain StrictHeaderError)
  3. Keep parser-improvements's streaming-parse path as a separate function
     (parse_streaming) — orthogonal feature, no collision
  4. Tests: union of both branches' test sets, deduplicated

→ harmonization_plan.md written; user reviews
```

User reviews and approves the plan.

**Phase 8 RATIONALIZATION + APPLY.** Agent cuts `branch-rationalization-2026-05-07` from `main`'s tip in the active worktree.

```
[↺ WORKING-TREE-DRIFT] git status --porcelain=v2 shows clean active worktree (no concurrent drift this run)

[✧ CHERRY-PICK] feature/parser-hardening
  git cherry-pick --no-commit feature/parser-hardening~..feature/parser-hardening
  → 2 commits picked, dry-run clean → cherry-pick for real
  [⊕ RECOVER] cargo test → green; cargo clippy → green; cargo fmt → clean
  Commit: "recover defensive parser-strict-header from feature/parser-hardening"

[⊞ RE-FINGERPRINT] downstream candidates re-checked
  → feature/parser-improvements still HARMONIZE (parser-hardening's contribution is now on rationalization branch)

[◇ HARMONIZE — Edit-tool synthesis] feature/parser-improvements ◇ feature/parser-hardening
  Edit src/parser.rs to add RecoveryHint enum (from parser-improvements)
  Edit src/parser.rs to wire RecoveryHint as parse_strict_header's error type (synthesis)
  Edit src/parser.rs to add parse_streaming (orthogonal, from parser-improvements)
  Edit tests/parser_test.rs to add union of test sets
  [⊕ RECOVER] cargo test → green; cargo clippy → green
  Commit: "harmonize parser improvements: RecoveryHint + streaming on top of strict-header

  Combines feature/parser-improvements's RecoveryHint enum and streaming
  parse path with feature/parser-hardening's strict-header validation. The
  synthesis preserves parser-improvements's richer error channel while
  retaining parser-hardening's defensive bounds checking."

[⇄ SPLIT-COMMITS-HUNKS] feature/auth-rework (partially-novel — apply 2 of 3 commits)
  Identify novel commits: 2nd and 3rd (1st is already on main per Phase 5)
  git cherry-pick --no-commit <2nd-sha> <3rd-sha>
  [⊕ RECOVER] cargo test → green; cargo clippy → green
  Commit: "recover refresh_token_rotation + grace-period handling from feature/auth-rework

  Applies the 2 novel commits from feature/auth-rework. The 1st commit
  (build_jwt_claims) was already on main; this commit applies only the
  refresh_token_rotation logic and grace-period test added afterward."

apply_log.tsv:
  feature/parser-hardening    cherry-pick    abc123  passed   72s
  feature/parser-improvements harmonize      def456  passed  148s
  feature/auth-rework         split-commit   ghi789  passed   89s
```

**Phase 9 FRESH-EYES.** Three parallel review prompts × 2 rounds. Round 1 finds one minor issue (a missing `pub` modifier on the harmonized RecoveryHint; fixed). Round 2: clean. Termination condition met.

**Phase 10 DESTRUCTIVE CLEANUP.** [⚠ CONFIRM] Agent presents the cleanup plan in [SKILL.md Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms) order: worktrees first, then branches.

```
Worktrees (in this order):
  ⊙ git worktree remove /data/projects/synthetic-fixture-wt-auth-rework
  ⊙ [DCG considered] rm -rf /tmp/synthetic-fixture-spike-parser
     [DCG blocked — design around it, use git worktree remove --force after dirty-state archived]
  ⊙ git worktree remove --force /tmp/synthetic-fixture-spike-parser
     (dirty state captured at Phase 3 + re-verified at Phase 10; user OK'd loss)

Branches (in this order, garbage → superseded → already-merged → applied-keepers):
  ⊘ git branch -D agent-fix-deadlock-2026-04-29-attempt-1   (garbage; -D because explicit)
  ⊘ git branch -D agent-fix-deadlock-2026-04-29-attempt-2   (superseded-by-newer-branch; -D)
  ⊘ git branch -d wip-BACK-1742-take-3                       (already-merged; -d works)
  ⊘ git branch -d feature/parser-hardening                   (applied-keeper, fully merged into rationalization branch; -d works)
  ⊘ git branch -d feature/parser-improvements                (applied-via-harmonization; -d works since rationalization branch contains the harmonized commit)
  ⊘ git branch -d feature/auth-rework                        (applied-via-split; -d works for the merged subset; user explicitly OK'd discarding the 1 already-on-main commit since it was redundant)

To proceed, paste this verbatim:
  yes I understand and want to remove 2 worktrees and delete 6 branches per the plan above

USER: yes I understand and want to remove 2 worktrees and delete 6 branches per the plan above
       (recorded to cleanup_authorization.txt with timestamp 2026-05-07T17:42:11Z)

Agent executes one operation at a time, restating verbatim:
  About to run: git worktree remove /data/projects/synthetic-fixture-wt-auth-rework
  $ git worktree remove /data/projects/synthetic-fixture-wt-auth-rework
  → cleanup_log.tsv: kind=worktree, path=..., verdict=auto-after-merge, ok=true
  ... (continues, one per row)

Final state:
  $ git worktree list | wc -l
  1   # active worktree only
  $ git branch | wc -l
  3   # main, release/v0.1, branch-rationalization-2026-05-07
  $ ls .git/refs/branch-rationalization-backup/ | wc -l
  6   # all backup refs intact
```

**Phase 11 HANDOFF.** [⌘ HANDOFF] Final report `handoff_report.md` summarizes counts, recovered SHAs, harmonization summary, rationalization-branch tip, bundle path, push instructions, recovery recipes. Pinned beads issue created. The skill stops; the user pushes manually.

### Synthetic Stub — Operator Usage Table

| Operator | Used | Where |
|----------|------|-------|
| `★ INVENTORY` | Phase 0 (count check), Phase 2 (full inventory) |
| `🔒 PROTECT` | Phase 0 (auto), Phase 4 (user confirm) |
| `🌳 WORKTREE-CHECK` | Phase 3 (capture), Phase 10 (re-verify) |
| `✦ FINGERPRINT` | Phase 5, every non-protected branch |
| `◐ VERIFY-ON-CANONICAL` | Phase 5, every non-protected branch |
| `⬡ BUNDLE` | Phase 3, the irreversibility gate |
| `⚠ CONFIRM` | Phase 4 (protection), Phase 6 (triage), Phase 7 (harmonization plan), Phase 10 (cleanup) |
| `◇ HARMONIZE` | Phase 7, src/parser.rs variant matrix |
| `✧ CHERRY-PICK` | Phase 8, feature/parser-hardening |
| `⊟ SQUASH-MERGE` | Not used (project_profile says merge-with-no-ff for keepers; harmonization synthesizes via Edit) |
| `⊠ REBASE-AND-MERGE` | Not used (no large-and-meaningful branches in this scenario) |
| `⇄ SPLIT-COMMITS-HUNKS` | Phase 8b, feature/auth-rework (2 of 3 commits) |
| `⊕ RECOVER` | Phase 8, after every successful apply (3 times) |
| `⊞ RE-FINGERPRINT` | Phase 8, after parser-hardening apply |
| `↺ WORKING-TREE-DRIFT` | Phase 8, before each apply (no drift this synthetic run) |
| `⊙ PRUNE-WORKTREE` | Phase 10, 2 worktrees (one with `--force` after dirty-state archival) |
| `⊘ DELETE-BRANCH` | Phase 10, 6 branches (3× `-d`, 3× `-D` per Axiom 8) |
| `⌘ HANDOFF` | Phase 11 |
| `[DCG block]` | Phase 10, agent considered `rm -rf` on dirty worktree, DCG blocked, agent used `git worktree remove --force` instead |

### Synthetic Stub — Lessons Codified

This synthetic stub is too contrived to teach much, but two lessons are worth flagging now and verifying in the real worked example:

1. **Worktree-first ordering matters operationally.** Removing the linked worktree pinned to `feature/auth-rework` before running `git branch -d feature/auth-rework` is the only ordering that works — the branch is "checked out elsewhere" until the worktree is gone. Per [SKILL.md Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms).
2. **Harmonization is a separate cognitive move from cherry-pick / squash-merge / rebase.** The [◇ HARMONIZE] for `src/parser.rs` produces a commit that is NEITHER a cherry-pick nor a squash — it's an Edit-tool-authored synthesis on top of the rationalization branch's current state. The variant matrix is the methodology; the commit is the artifact. Without [HARMONIZATION.md](HARMONIZATION.md) (the dedicated reference), this skill is just stash-janitor with extra steps.

> Synthetic-stub status: **Illustrative only.** When the real run lands on asupersync (or another candidate), this stub stays in place but is clearly demoted, and the real run becomes the load-bearing teaching artifact.

---

## Conventions for Adding the Real Worked Example Later

When the skill runs end-to-end against a real messy project, add the real walkthrough by:

### 1. Edit this file in place

Do NOT create a new file. Per AGENTS.md "No File Proliferation": "If you want to change something or add a feature, revise existing code files in place."

### 2. Demote the synthetic stub

Move the synthetic stub section above to a clearly labeled subsection like:

```
## Synthetic Stub (Kept for Illustrative Purposes)

> **Synthetic stub from before the first real run.** Kept for the operator-coverage walkthrough; superseded by the asupersync 2026-XX-XX run below.

[existing synthetic content, unchanged]
```

### 3. Add the real walkthrough as the new primary section

The real walkthrough goes ABOVE the synthetic stub, with a section header like:

```
## Asupersync 2026-XX-XX Run — N Worktrees, M Branches

[verbatim agent dialogue, operator-annotated]
```

### 4. Follow the format conventions described above

- Verbatim dialogue (not summarized)
- Per-cognitive-move operator annotations
- DCG-block annotations on every `rm -rf` consideration
- Failure-then-recovery moments highlighted
- Verdict-distribution table at the end
- Operator usage table
- "What this run taught us" section linking to specific anti-patterns / failure modes / operator cards updated as a result

### 5. PR-style commit message

When committing the real worked example, the commit message should:

- Reference the source run (project, date, run-id from beads if applicable)
- Mention which anti-patterns / failure modes / operator cards were updated as a result
- Include "Co-Authored-By:" the agent that authored the run, if applicable

### 6. Update cross-references

After adding the real example:

- [SKILL.md "Source Corpus"](../SKILL.md#source-corpus) entry for "Hypothetical asupersync 47-worktree+213-branch session" can be updated from "hypothetical" to "real, 2026-XX-XX"
- Any other reference to "the canonical worked example" should still resolve to this file via [WORKED-EXAMPLES.md](WORKED-EXAMPLES.md)

### 7. Cross-link to the sibling skill

Keep the cross-reference to git-stash-janitor's [WORKED-EXAMPLES.md](../../git-stash-janitor/references/WORKED-EXAMPLES.md) — that file is the load-bearing format ancestor and should remain the comparison point. The branch-and-worktree run will inevitably produce structures and lessons the stash run didn't have (harmonization plan, worktree-first ordering, dirty-state-capture-before-force-remove); calling these out explicitly cross-pollinates both skills.

---

## Cross-References

- The format ancestor: [git-stash-janitor's WORKED-EXAMPLES.md](../../git-stash-janitor/references/WORKED-EXAMPLES.md) — the load-bearing example that this file's eventual real walkthrough should match in shape
- Operator cards (the glyph definitions referenced inline above): [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md)
- Per-phase playbook with exit criteria: [PHASES.md](PHASES.md)
- The synthetic 8-branch test scenario this stub is based on: [SELF-TEST.md](../SELF-TEST.md)
- The 19-axiom kernel that the worked example demonstrates in action: [SKILL.md "THE RATIONALIZATION KERNEL"](../SKILL.md#the-rationalization-kernel-universal-axioms)
- The anti-patterns + failure modes the worked example will cite: [ANTI-PATTERNS.md](ANTI-PATTERNS.md), [FAILURE-MODES.md](FAILURE-MODES.md)
- The harmonization methodology that distinguishes this skill from stash-janitor: [HARMONIZATION.md](HARMONIZATION.md)
