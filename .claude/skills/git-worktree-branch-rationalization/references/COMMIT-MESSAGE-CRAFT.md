# Commit Message Craft — Writing Phase 8 Recovery Commits

Every Phase 8 keeper-commit is a small story. It says: *what was recovered, where it came from, why it matters today, what its competitors looked like, and how it was integrated.* This file is the craft guide.

Adapted from [git-stash-janitor's COMMIT-MESSAGE-CRAFT.md](../../git-stash-janitor/references/COMMIT-MESSAGE-CRAFT.md). The shape is the same; the depth differs because branch rationalization commits often draw from *multiple* source branches (the harmonized synthesis case), and the body must cite *every* source variant and explain the composition order. A stash recovery's body has 1 source; a harmonization commit's body can have 5+.

> **Why:** Per [SKILL.md "Polish Bar"](../SKILL.md#the-polish-bar-non-negotiable), "Focused commit messages: each keeper-commit explains *why* this content is being recovered, naming source branches and variant intents: not 'cherry-pick from agent-cleanup-pass-3' but 'recover defensive null-check from agent-cleanup-pass-3 + parser-fixture from feature/parse-hardening + type-narrowing from worktree dirty-state, harmonized on top of canonical's current structure'." That sentence is the contract this file enforces.

See also: `assets/templates/commit-message-template.md` for fill-in-the-blank starting points.

---

## The contract

Every Phase 8 commit message must satisfy:

1. **Subject line** (≤72 chars): present-tense verb + concrete object. Names the unit of recovered work, not the source.
2. **Body** with three required sections separated by blank lines: *Context*, *Why-it-didn't-already-land*, *How-it-was-recovered* (the last expanded for harmonized syntheses to include the variant-matrix summary).
3. **Citations**: source branch slug(s), source SHA(s), bundle paths (`<bundle>/branches/<slug>/...`), the harmonization-plan entry id (when applicable).
4. **No `Co-Authored-By` lines** unless the user explicitly asks. Per [SKILL.md "Anti-Patterns"](../SKILL.md#anti-patterns-never-do): "messages that bypass `Co-Authored-By` discipline (don't add it unless user asked)."
5. **No `--no-verify` ever.** Per [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms) and AGENTS.md "Mandatory explicit plan": pre-commit hooks run on every keeper.
6. **Convention compliance**: follows `project_profile.json:commit_message_convention` (Conventional Commits, ticket-id prefix, gitmoji, or freeform).

---

## Subject line patterns by commit type

The subject names the unit of recovered work. "recover defensive null-check from agent-cleanup-pass-3" is better than "cherry-pick agent-cleanup-pass-3"; the former is meaningful in `git log --oneline`, the latter is opaque.

| Type | Pattern | Example |
|------|---------|---------|
| Single-source recovery | `recover <thing> from <branch-slug>` | `recover defensive MySQL OK-packet length-cap from wip-BACK-1742` |
| Multi-source harmonization | `harmonize <thing> from <branch-slug> + <branch-slug> [+ ...]` | `harmonize logger hardening from agent-cleanup-pass-3 + feature/length-cap + feature/redact-secrets` |
| Split-apply (Phase 8b) | `recover novel <thing> from partial <branch-slug>` | `recover novel parser_v2_overflow test from partial feature/parse-hardening` |
| Conflict-resolved | `recover <thing> ported through canonical's <refactor>` | `recover OK-packet length cap ported through main's match-expression refactor` |
| Dirty-worktree-only | `recover <thing> from worktree <sanitized-path>` | `recover scratchpad fuzz corpus from worktree data-projects-foo--wt-3` |
| Bug-fix recovery | `fix: recover <bug-fix> from <source>` | `fix: recover null-pointer guard in webhook signature verification from wip-BACK-2071` |

For Conventional Commits projects, prepend the type:
- `feat:` — new functionality recovered
- `fix:` — bug fix recovered
- `test:` — test-only recovery
- `perf:` — performance improvement recovered
- `refactor:` — refactor recovered (rare; usually superseded or divergent-refactor)
- `chore:` — maintenance / config recovery

For ticket-id projects, prefix with the ticket the original branch referenced (if any):
- `BACK-1742: recover defensive OK-packet length-cap from wip-BACK-1742`

---

## Body structure: standard recovery commit (single source)

Three required sections separated by blank lines:

### Section 1: Context

```
Originally drafted on branch `wip-BACK-1742` (sha 8a3d2c9, last commit
2026-04-29). The fail-closed guard caps OK-packet payload length to
MAX_PAYLOAD before the consumer reads it; without the cap, a malformed
packet from an upstream proxy could trigger a panic in the framing parser.
```

State the source (branch slug + sha + last-commit date) and the *why this matters* (the problem the change solves) in 2–4 sentences.

### Section 2: Why it didn't already land

```
The polished version of this branch never landed because the agent that
authored it crashed before pushing the PR. The defensive guard is genuinely
useful; the rest of the agent's work (mostly trace-logging) was redundant
with what landed via PR #234, which is why the branch shows up as
partially-novel rather than entirely-superseded.
```

This section is what makes a recovery commit different from a regular `feat:` commit. It explains *why* this was unfinished work and *why now* is the right time to recover it.

### Section 3: How it was recovered

```
Recovered via: git cherry-pick 8a3d2c9 onto branch-rationalization-2026-05-07
(clean apply against canonical's current structure).

Source: <bundle>/branches/wip-BACK-1742/diff-vs-merge-base.diff
        <bundle>/branches/wip-BACK-1742/format-patch/0001-add-payload-cap.patch

Tests: cargo test --workspace passed; cargo clippy clean; cargo fmt clean.
```

State the recovery mechanism (cherry-pick / squash-merge / rebase-and-merge / harmonized-synthesis-via-Edit). Cite the bundle path (the diff is the truth, not the agent's recall). State which gates ran.

---

## Body structure: harmonized-synthesis commit (multi-source — the important case)

For files touched by ≥2 non-protected branches, Phase 7 produces a variant matrix and Phase 8 produces a *single* synthesized commit drawing from multiple sources. The body must:

1. Name every source branch.
2. Cite the harmonization-plan entry id.
3. Explain the composition order (which intent ate which intent, who's the base, who layers on top).
4. Note divergent variants that were *not* composed and why.

Example (from the canonical worked example — `src/util/logger.rs` after a 4-branch swarm):

```
harmonize logger hardening from agent-cleanup-pass-3 + feature/length-cap
                              + feature/redact-secrets

Three branches independently hardened src/util/logger.rs against malformed
input. Each addressed a different input vector:
  - agent-cleanup-pass-3 (sha b3c4d5e): null-arg guard on msg parameter
  - feature/length-cap (sha c5d6e7f): payload length cap to 4 KiB
  - feature/redact-secrets (sha d7e8f90): redact_secrets() filter for keys

None of the three landed independently because each PR review surfaced
"why not also include the other two checks?" as feedback; the task was
implicitly waiting for harmonization. This commit composes all three onto
canonical's current Logger::log() structure, preserving each variant's
intent and lifting each variant's tests:

Composition (entry-order, most-restrictive last):
  1. null-arg guard at function entry (from agent-cleanup-pass-3)
  2. length cap with truncation-and-warn (from feature/length-cap)
  3. redact_secrets transform on the surviving message (from feature/redact-secrets)

Tests lifted (all three, no name collisions):
  - tests/log_null.rs::test_log_null_arg_returns_err (from agent-cleanup-pass-3)
  - tests/log_length.rs::test_log_length_cap_truncates (from feature/length-cap)
  - tests/log_redact.rs::test_log_redact_stripe_keys (from feature/redact-secrets)

Not composed:
  - worktree:data-projects-foo--wt-3 (dirty-state) had a divergent-refactor
    changing log() signature from log(level, msg) to log(level, msg, ctx).
    This is a real architectural choice; surfaced to user as separate decision
    in handoff_report.md §followups (issue br-2x91s).

Source branches preserved:
  <bundle>/branches/agent-cleanup-pass-3/diff-vs-merge-base.diff
  <bundle>/branches/feature-length-cap/diff-vs-merge-base.diff
  <bundle>/branches/feature-redact-secrets/diff-vs-merge-base.diff

Harmonization plan: harmonization_plan.md §H-7 (src/util/logger.rs)

Recovered via: manual Edit-tool synthesis on top of canonical's Logger
              structure; per-hunk attribution preserved as inline comments
              for the duration of PR review (will be removed before merge).

Tests: cargo test --workspace passed; cargo clippy --workspace -- -D warnings
       clean; cargo fmt --check clean; UBS clean on src/util/logger.rs.
```

That's ~40 lines, ~400 words. Long, but every line earns its place: the future reader (the user reviewing the rationalization-branch PR) needs every source attribution to verify the synthesis is correct.

> **Why:** [HARMONIZATION.md §"Variant matrix"](HARMONIZATION.md#2-the-variant-matrix-structure) — the variant matrix is the user-reviewable artifact; the commit body is its long-term archive in git history. Without the body, the matrix's reasoning is lost when `harmonization_plan.md` is eventually deleted from the workspace.

---

## Body structure: split-apply commit (Phase 8b)

For partially-novel branches, only the novel subset of commits/hunks is recovered. The body adds a per-hunk audit trail:

```
recover novel parser_v2_overflow test from partial feature/parse-hardening

Originally branch `feature/parse-hardening` (sha c5d6e7f, last commit
2026-04-22) mixed a parser refactor (now landed via PR #234) with new
fuzz corpus entries and a regression test. This commit recovers only
the regression test and corpus entries; the refactor portion was
dropped as superseded.

The branch was never finished as a unit because PR #234 superseded the
refactor mid-development; the branch's author moved on without splitting
the still-novel test/corpus hunks out.

Hunks recovered: 3 of 8.
  Kept:
    - hunk 3: tests/parser_overflow.rs::test_parser_v2_overflow (new)
    - hunk 4: tests/fixtures/corpus/v2_overflow_001..100.bin (new)
    - hunk 8: tests/fixtures/corpus/v2_overflow_101..200.bin (new)
  Dropped (superseded; landed via PR #234):
    - hunks 1, 2, 5, 6, 7: parser refactor at src/parser.rs:120-340

Recovered via: git cherry-pick --no-commit -X theirs c5d6e7f, then manual
              hunk-removal via git restore --staged for hunks 1, 2, 5, 6, 7,
              followed by git commit.

Source: <bundle>/branches/feature-parse-hardening/diff-vs-merge-base.diff
        <bundle>/branches/feature-parse-hardening/format-patch/0003-add-overflow-test.patch
        <bundle>/branches/feature-parse-hardening/format-patch/0004-add-corpus-001-100.patch
        <bundle>/branches/feature-parse-hardening/format-patch/0008-add-corpus-101-200.patch

Tests: cargo test --workspace passed (parser_v2_overflow now passes; was
       a known-fail-to-write before).
```

The "Hunks recovered: N of M" pattern is the audit trail. The user reviewing the rationalization-branch PR sees exactly what was kept and what was discarded with one-glance per-hunk citations.

---

## Body structure: conflict-resolved commit

When the recovery requires manual resolution (canonical drifted, the source diff doesn't apply cleanly):

```
recover OK-packet length cap ported through main's match-expression refactor

Originally branch `wip-BACK-1742` (sha 8a3d2c9) modified an `if let
Ok(payload_len) = ...` block at src/mysql/protocol.rs:218. On canonical
today, that block has been refactored into a `match buf[4] { ... }`
expression at the same path (introduced via PR #198, sha 9f3a2d1).

The 3-way apply could have produced syntactically broken code (an `if let`
inside a match arm). Instead, the branch's *intent* (the length cap and
fail-closed test) was ported into canonical's `match` arm for OK_BYTE via
the Edit tool. No sed/awk transformations (per AGENTS.md "No Script-Based
Changes").

Recovered via: manual resolution; see <workspace>/conflicts/branch_wip-back-1742.context.md
              for the full surface diff and the resolution rationale.

Source: <bundle>/branches/wip-back-1742/diff-vs-merge-base.diff
        <bundle>/branches/wip-back-1742/format-patch/0001-add-length-cap.patch

Tests: cargo test --workspace passed; cargo clippy --workspace -- -D warnings
       clean.
```

The "intent vs. surface form" framing is a useful lens; the branch's surface form may be obsolete, its intent often isn't.

---

## Body structure: dirty-worktree-only commit

When the value lives in uncommitted worktree state, never committed to any branch:

```
recover scratchpad fuzz corpus from worktree data-projects-foo--wt-3

Worktree at /data/projects/foo--wt-3 (pinned to branch
agent-fuzz-pass-2, last activity 2026-04-19) had uncommitted untracked
fuzz corpus entries totalling 217 files in tests/fuzz/corpus/. The
corpus was generated by a fuzzing run that crashed before the agent
committed; the entries are real test inputs that exercised previously-
unhit branches in the parser.

This commit lifts the untracked corpus into the rationalization branch.
The parent branch agent-fuzz-pass-2 itself classified as superseded (its
*committed* content is on canonical via PR #267); only the worktree's
uncommitted corpus is novel.

Recovered via: untar of <bundle>/worktrees/data-projects-foo--wt-3/untracked.tar.gz
              into tests/fuzz/corpus/, followed by git add and commit.
              No staged.diff or unstaged.diff content to apply (worktree
              had no tracked-file changes, only untracked corpus).

Source: <bundle>/worktrees/data-projects-foo--wt-3/untracked.tar.gz
        <bundle>/worktrees/data-projects-foo--wt-3/meta.txt

Tests: the corpus is data-only; project's `cargo fuzz run parser` discovers
       and uses these entries automatically. Sample run: 217 entries
       loaded, 0 crashes (the original crash was in the fuzzer harness,
       not in the corpus content; fixed via PR #267).
```

> **Why:** [WORKTREE-STATE.md](WORKTREE-STATE.md) — the dirty-worktree-only verdict is rare but exists; when it triggers, the commit message must clearly explain the worktree origin AND that the parent branch was *not* the source of the novel content.

---

## Body structure: bug-fix recovery commit

When the recovered content is fixing a bug:

```
fix: recover null-pointer guard in webhook signature verification from wip-BACK-2071

Originally branch `wip-BACK-2071` (sha def4567, last commit 2026-04-22).
Discovered while investigating a 500 from /api/webhooks: an unverified
signature can be empty bytes, which crashes verifyHmac() because it
doesn't null-check.

The polished version of this fix landed in PR #198, but only for Stripe;
PayPal's verifier was never patched (the agent that worked on the patch
was paged onto a different ticket and the partial fix was branched-and-
abandoned). This commit applies the same guard to PayPal's verifier path.

Recovered via: git cherry-pick def4567 (clean apply; PayPal's verifier
              path on canonical hasn't drifted since the branch was made).

Source: <bundle>/branches/wip-back-2071/diff-vs-merge-base.diff
        <bundle>/branches/wip-back-2071/format-patch/0001-add-paypal-null-guard.patch

Closes: BACK-2071 (file beads issue br-2x71r at handoff)

Tests: pnpm test:webhooks passed; the previously-flaky paypal-empty-sig
       integration test now consistently passes.
```

The "X had it but Y didn't" pattern is common — agents often patch one path and branch the analogous fix for the other. The commit message names both paths.

---

## Anti-patterns (NEVER DO)

| Anti-pattern | Why bad |
|--------------|---------|
| `cherry-pick from agent-cleanup-pass-3` | Says nothing the diff doesn't already say. Future reader cannot tell *what* was recovered or *why*. |
| `WIP recovery` | "WIP" is invisible after merge; gives no signal. |
| `recover branch content` | Generic; says nothing. |
| `Recovered via branch rationalization tool` | The tool is irrelevant; the change is what matters. |
| `Co-Authored-By: Claude <noreply@anthropic.com>` (without user request) | Many projects have specific commit-style policies; don't add trailers proactively. Per [SKILL.md "Anti-Patterns"](../SKILL.md#anti-patterns-never-do). |
| `--no-verify` to bypass hooks | Forbidden per AGENTS.md "Mandatory explicit plan" + Axiom 13. If a hook fails, fix it; if you can't, surface to user. |
| Multi-paragraph philosophical preamble | Body should be 100–500 words depending on synthesis complexity, not 2000. |
| Failing to cite the bundle path | Future reader can't audit the recovery without the bundle reference. Always cite `<bundle>/branches/<slug>/...`. |
| Failing to cite the harmonization-plan entry id for syntheses | The variant matrix lives in `harmonization_plan.md`; the commit body must point to it. |
| Citing only branch names without SHAs | Branch names are mutable; SHAs are immutable. Always include both. |
| Citing source branches but not their merge-base | The merge-base is what makes the diff meaningful; without it, the diff is unreadable. The format-patch series implicitly captures this, but the body should mention it for syntheses. |
| Listing every changed file in the body | The diff is right there; don't duplicate. The body is for *why*, not *what*. |

---

## How to author the message

1. **Re-read the source diff(s).** What identifiers were introduced? What problem do they solve?
2. **Re-read `harmonization_plan.md` §<entry-id>** if this is a synthesis. The variant matrix tells you which intents to cite.
3. **Check `apply_log.tsv:strategy`** — was this cherry-pick, squash-merge, rebase-and-merge, or harmonized-synthesis?
4. **Check `apply_log.tsv:pre_apply_drift`** — did the apply require manual conflict resolution? If so, link the conflict context.
5. **Check related beads issues.** `br show <ticket-id>` may have context worth quoting.
6. **Draft.** First pass: 3 sections, 100–500 words depending on complexity.
7. **Tighten.** Remove redundancy with the diff. The diff shows *what*; the message says *why*.
8. **Verify.** Does the message stand alone? Could a reviewer six months from now make sense of it without context from this run?

For Comprehensive runs, a triangulator subagent reviews each commit message:
- Does it explain the *why*?
- Are all source citations complete (every contributing branch named with SHA)?
- For syntheses: is the composition order explicit?
- For split-apply: is the per-hunk audit trail present?
- Does it follow the project's commit-message convention (Conventional Commits, ticket prefix, etc.)?

If any check fails, regenerate. Per [POLISH-BAR.md §"Focused commit messages"](POLISH-BAR.md#focused-commit-messages), commit-message quality is a Polish Bar dimension; failing here means the run hasn't completed.

---

## The skill's enforcement

The Phase 8 keeper-applier subagent (`subagents/keeper-applier.md`) reads:
- The source diff(s) (single branch for cherry-pick; multiple for synthesis)
- Branch metadata from `branches.tsv` and the bundle's `meta.txt` per source
- `project_profile.json:commit_message_convention`
- The harmonization-plan entry (when synthesis)
- Any beads issue linked from the source branch's commit messages
- `apply_log.tsv:pre_apply_drift` (whether there was manual conflict resolution)

And produces a message conforming to the contract above. The message is then `git commit -m "$(cat <<'EOF' ... EOF)"` applied to the rationalization branch (no `--amend` because each keeper is a fresh commit; amending across keepers would lose per-keeper attribution).

Templates with fill-in-the-blank starting points live in `assets/templates/commit-message-template.md` (referenced from this file at the top). When in doubt, start from the template; rarely is a from-scratch draft better than a template-customized one.
