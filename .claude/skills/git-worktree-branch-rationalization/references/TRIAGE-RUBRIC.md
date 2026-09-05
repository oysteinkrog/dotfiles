# Triage Rubric — How a Branch (or Worktree) Earns Its Verdict

Every branch and every worktree exits Phase 5 with exactly one verdict, an evidence string, a confidence score, a recommended apply strategy, and a list of files-touched. This document is the verdict-by-verdict rubric.

> **Why:** Per [SKILL.md "Operator Library"](../SKILL.md#operator-library--the-cognitive-moves), the FINGERPRINT → VERIFY-ON-CANONICAL chain is the load-bearing classification path. The rubric below is the decision tree that consumes their output.

---

## Verdicts

| Verdict | Meaning | Phase 8 strategy | Phase 10 disposition |
|---------|---------|------------------|----------------------|
| `canonical` | This IS the canonical branch | (skip) | NEVER DELETED |
| `protected-preserve` | Auto- or user-protected; never enters the rationalization pipeline | (skip) | NEVER DELETED |
| `already-merged` | Every commit reachable from canonical, OR `git cherry -v` shows all `-` lines | (skip) | Try `git branch -d`; if it refuses because the branch is only patch-id-equivalent (squash/rebase landed), use the explicit `BRANCH_FORCE_OK=1` Phase D path after authorization |
| `superseded` | The branch's introduced symbols already exist on canonical with equivalent semantics (verified via FINGERPRINT + VERIFY-ON-CANONICAL + same-signature sample) | (skip) | `git branch -d` if fully merged into rationalization branch, else `-D` (Phase C) |
| `novel-and-accretive` | Fingerprint absent on canonical, apply-check clean, content is a focused/defensive/test-only addition | cherry-pick / squash-merge / rebase-and-merge per project_profile.json | `git branch -d` after applied-keeper bucket (Phase G) |
| `partially-novel` | Some commits / hunks on canonical, others not | split-commits-hunks (Phase 8b) | `git branch -d` after applied-keeper bucket (Phase G) |
| `novel-but-stale` | Useful intent but predates a refactor that moved/renamed/restructured surrounding code; apply impossible without rewriting against new architecture | manual decision (default skip with note) | `git branch -D` opt-in (Phase E) — user typically drops |
| `divergent-refactor` | Intentionally incompatible direction; default-skip; a candidate input to harmonization if other branches collide on same files | manual / harmonized-synthesis (input to Phase 7) | `git branch -D` opt-in (Phase F, off by default) |
| `dirty-worktree-only` | Value exists only in uncommitted staged/unstaged/untracked work in a worktree; not in any committed branch | apply staged.diff + unstaged.diff + .untracked.list + untracked.tar.gz | (worktree removed in Phase 10 Phase A; no separate branch deletion) |
| `garbage` | Generated artifacts, failed agent scratch, lockfile-only churn, branches whose only content is a revert of still-needed commits, branches whose subject says "broken" | (skip) | `git branch -D` (Phase B) |
| `unknown` | Triage couldn't classify with confidence ≥ 0.7 | (surface to user in Phase 6) | depends on user resolution |

---

## Decision Flow

```
For each non-protected branch B (or each non-clean worktree W):

  0. If B is the canonical branch:
       → canonical, confidence 1.0
       → strategy: skip
       → evidence: "canonical branch"

  1. If B is on protected.tsv:
       → protected-preserve, confidence 1.0
       → strategy: skip
       → evidence: row reason from protected.tsv

  2. cherry_summary = git cherry -v <canonical> <B>
     IF every line is `-` (every commit's patch-id is on canonical):
       → already-merged, confidence 0.99
       → strategy: skip
       → evidence: "git cherry -v: all `-` lines (N commits, all patch-id-equivalent on canonical)"

  3. FINGERPRINT extracts (functions, types, tests, fixture_strings, file_paths)
     from B's diff vs merge-base.

     If B is a worktree's dirty state, fingerprint the staged + unstaged diffs
     plus list any untracked file paths.

  4. If fingerprint is empty AND name matches a known-garbage pattern:
       → garbage, confidence 0.99
       → strategy: skip
       → evidence: "name=<pattern>; empty fingerprint"

  5. APPLY-CHECK PROBE — `git cherry-pick --no-commit -X theirs <sha>` on a
     throwaway branch from canonical's tip; record exit code.
       - exit 0       → apply_check = clean
       - exit nonzero → apply_check = reject (capture conflict files + line ranges)
     Reset the throwaway branch with `git cherry-pick --abort` afterward.

  6. VERIFY-ON-CANONICAL:
       For each fingerprint symbol, search canonical.
       Compute fingerprint_coverage = found_with_same_signature / total.
       Compute file_existence_coverage = files_still_on_canonical / total_files.

       Sample same-signature on at least 3 introduced symbols (if available).
       If ≥30% of sampled signatures diverge: this is NOT supersession;
       flip toward novel-but-stale or divergent-refactor (Axiom 16).

  7. Classify:

     IF fingerprint_coverage ≥ 0.95 AND apply_check IN (clean, reject)
        AND same_signature ratio ≥ 0.7:
       → superseded, confidence 0.85 + 0.15*fingerprint_coverage
       → strategy: skip
       → evidence: top 3 file:line citations on canonical

     ELIF fingerprint_coverage ≤ 0.05 AND apply_check == clean:
       → novel-and-accretive, confidence 0.75 + 0.20*(1-fingerprint_coverage)
       → strategy: cherry-pick (default) | squash-merge (if project_profile says squash)
                   | rebase-and-merge (if project_profile says rebase)
       → evidence: "no symbols found on canonical; apply-check clean"

     ELIF apply_check == reject AND any rejected hunks correspond to
          superseded symbols AND non-rejected hunks correspond to absent symbols:
       → partially-novel, confidence 0.70
       → strategy: split-commits-hunks (Phase 8b)
       → evidence: per-commit / per-hunk breakdown — which are superseded, which novel

     ELIF fingerprint_coverage ≤ 0.05 AND
          (file_existence_coverage ≤ 0.5 OR apply_check fails on every hunk):
       → novel-but-stale, confidence 0.70
       → strategy: manual decision (default skip with note)
       → evidence: "files X, Y removed from canonical; apply rejects all hunks"

     ELIF apply_check == reject AND fingerprint_coverage between 0.4 and 0.9
          AND another branch in triage touches ≥1 of the same files:
       → divergent-refactor, confidence 0.75
       → strategy: input to harmonization (Phase 7) IF colliding-file group exists,
                   else skip
       → evidence: "intentionally incompatible direction on file X; collides with
                    branch Y on file X"

     ELIF B is a worktree's dirty state AND fingerprint introduces symbols
          not on canonical AND not on the underlying branch:
       → dirty-worktree-only, confidence 0.80
       → strategy: worktree-dirty-state (apply staged.diff + unstaged.diff +
                   .untracked.list + untracked.tar.gz)
       → evidence: "fingerprints in unstaged.diff not present on
                    underlying branch <name> nor on canonical"

     ELIF name matches garbage prefix AND fingerprint_coverage >= 0.5:
       → garbage (specifically: garbage-and-superseded), confidence 0.95
       → strategy: skip
       → evidence: name + supersession proof

     ELSE:
       → unknown, confidence 0.60
       → flag for user review in Phase 6
```

---

## Garbage-Name Patterns

These branch-name prefixes are presumptively garbage when they appear with empty or low-novelty fingerprint. Override only with strong novel-fingerprint evidence.

| Pattern regex | Meaning | Caveat |
|---------------|---------|--------|
| `.*-broken-attempt$` | Explicit label for known-broken state | Always garbage if fingerprint is empty or the diff is mostly `-` lines |
| `.*-other-agent-broken$` | Explicit label for known-broken state from a parallel agent | Always garbage |
| `.*-temp-pre-push$` | Paranoid save before a push | If push succeeded (cherry -v shows `-`), content is on remote — already-merged or garbage |
| `.*-full-tree-reset$` | Branch created when an agent did `git reset --hard` and tagged the prior state | Almost always garbage — the user already abandoned this work |
| `.*-autostash$` | Git's own auto-stash promoted to a branch | Recoverable from reflog; garbage in the branch list |
| `.*-pre-deadlock-fix$` | Save before a destructive deadlock fix | Often the polished version landed — likely superseded |
| `wip-deleted-during-rebase$` | Default name for rebase-aborted branches | Need fingerprint analysis; rarely garbage in itself |
| `^revert-of-\w+$` | Branch whose only content is `git revert <sha>` of a still-needed commit | Garbage if the reverted commit is still on canonical |
| `^lockfile-bump$` | Branch with only `Cargo.lock` / `package-lock.json` / `pnpm-lock.yaml` changes | Garbage; lockfile churn is not interesting standalone |

---

## Branch-Name vs Branch-Content

A branch's name is a hint, not a verdict. Always verify with FINGERPRINT + VERIFY-ON-CANONICAL. Common name-vs-content mismatches:

- A branch named `agent-cc-12-broken-attempt` whose actual content is a clean defensive null-check the agent abandoned for unrelated reasons → `novel-and-accretive`, override the garbage default.
- A branch named `feature/parser-v3` whose actual content is identical to canonical (someone branched, did nothing, never pushed) → `already-merged` (cherry -v shows nothing or all `-`).
- A branch named `autostash-from-rebase` whose actual content is a merge conflict resolution that was lost in the rebase → `novel-and-accretive`, override the garbage default.

---

## Same-Signature Verification

A symbol existing on canonical is NOT proof of supersession. The skill must verify *equivalent semantics* by sampling.

> **Why:** [SKILL.md Axiom 16](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Same-name on canonical is not always supersession. A function `redact_secrets` on a branch and on canonical may have different signatures or different defensive checks. Always sample same-signature on a few introduced symbols before classifying `superseded`."

**Quick same-signature heuristic** (per language):

```
Rust:
  Branch:  pub fn lock_until(deadline: Instant) -> Result<()>
  Canon:   pub fn lock_until(deadline: Instant) -> Result<()>
  → same_signature = true

  Branch:  pub fn lock_until(deadline: Instant) -> Result<()>
  Canon:   pub fn lock_until(deadline: Instant, retries: u32) -> Result<()>
  → same_signature = false; param list extended; the branch version may
    actually be a regression — flag for user review

TypeScript:
  Compare:
    - parameter count
    - parameter types (best-effort, parsed from the fn signature)
    - return type
  Don't compare body — that would require parsing semantics

Python:
  Compare:
    - argument count + names
    - default values
    - decorators (if @overload, fingerprint it as multiple)

Go:
  Compare:
    - parameter list (types and order)
    - return list
```

**When same_signature is false on >30% of sampled symbols**, flip the verdict:

- If the branch's version is *more restrictive* (fewer params, narrower types): likely a regression — flag for user review (verdict: `novel-but-stale` or `divergent-refactor`).
- If the branch's version is *less restrictive* (more params, broader types): likely an earlier draft — confirm `superseded` only if the broader signature exists on canonical AND covers the branch's call sites; otherwise `divergent-refactor`.
- If signatures diverge on names alone: someone renamed; treat as `superseded` if the renamed symbol exists with same body on canonical.

`scripts/triage-batch.sh` performs only a lightweight same-name heuristic. For full same-signature checks, use manual review or a language-specialist subagent with `ast-grep` where the language has a tree-sitter grammar.

---

## Confidence Calibration

| Confidence | Meaning |
|------------|---------|
| 0.95–1.00 | Multiple independent signals agree (fingerprint + apply-check + same-signature + cherry-summary + name-pattern) |
| 0.85–0.94 | Two strong signals agree (e.g., fingerprint + cherry-summary) |
| 0.70–0.84 | One strong signal + one weak (e.g., fingerprint coverage 0.95 but signatures unverified) |
| 0.60–0.69 | Surface to user — borderline |
| <0.60 | Force `unknown`; do not auto-classify |

The Phase 6 user-facing decision table groups by verdict but sorts within each group by confidence ascending — the most ambiguous rows are most prominent for the user's eye.

---

## Per-Hunk and Per-Commit Evidence (for `partially-novel`)

When a branch is `partially-novel`, Phase 6 needs per-commit-or-per-hunk detail so the user can confirm the split. The canonical `triage.tsv` keeps the standard schema (`kind`, `name`, `verdict`, `confidence`, `evidence_on_canonical`, `apply_check`, `fingerprint_summary`, `strategy`, `files_touched`). Put a compact summary in `evidence_on_canonical`; Comprehensive/manual workers may also write a sidecar `commit_breakdown` JSON artifact for Phase 8b:

```json
{
  "commits": [
    {"sha": "abc123", "verdict": "superseded", "evidence": "patch-id matches canonical commit def456 (PR #234)"},
    {"sha": "789xyz", "verdict": "superseded", "evidence": "patch-id matches canonical commit abc789"},
    {"sha": "f1e2c3", "verdict": "novel",       "evidence": "no match on canonical; introduces fuzz-corpus files"},
    {"sha": "11a22b", "verdict": "novel",       "evidence": "no match on canonical; introduces overflow test"}
  ]
}
```

Phase 8b's split-apply uses the sidecar when it exists; otherwise it re-fingerprints per commit before deciding which to cherry-pick. In the example above, cherry-pick `f1e2c3` and `11a22b`; skip `abc123` and `789xyz`.

For per-hunk splits within a single commit (rare but possible), the structure is analogous:

```json
{
  "hunks": [
    {"id": 1, "file": "src/parser.rs",          "lines": "120-145", "verdict": "superseded", "evidence": "src/parser.rs:120 same fn body on canonical"},
    {"id": 2, "file": "src/parser.rs",          "lines": "200-218", "verdict": "novel",      "evidence": "no match on canonical"},
    {"id": 3, "file": "tests/parser_corpus.rs", "lines": "1-50",    "verdict": "novel",      "evidence": "file new on branch"}
  ]
}
```

---

## Worked Examples

### Example 1: `superseded` (hypothetical asupersync session, agent-cod-3-mutex-lock-until)

```
kind: branch
name: agent-cod-3-mutex-lock-until
sha: def456
merge_base: abc12
fingerprint:
  functions: [lock_until, recover_lock]
  types: []
  tests: []
verify_on_canonical:
  - lock_until: src/mutex.rs:317 ✓ same signature
  - recover_lock: src/mutex.rs:412 ✓ same signature
cherry_summary: 2 commits, both `-` (patch-id matches canonical)
apply_check: clean (would apply but redundantly; cherry shows `-`)
verdict: superseded
confidence: 0.97
evidence: "src/mutex.rs:317,412 — both fns present with same signatures; cherry -v all `-`"
strategy: skip
```

### Example 2: `garbage` (hypothetical session, agent-cc-77-broken-attempt)

```
kind: branch
name: agent-cc-77-broken-attempt
fingerprint: { ... } # mostly `-` lines (deletions); 0 added symbols
verdict: garbage
confidence: 0.99
evidence: "name=*-broken-attempt; empty positive fingerprint"
strategy: skip
```

### Example 3: `novel-and-accretive` (hypothetical session, agent-cc-12-mysql-ok-packet-defensive)

```
kind: branch
name: agent-cc-12-mysql-ok-packet-defensive
fingerprint:
  functions: [defensive_ok_packet_length_cap, parse_ok_packet_safe]
  types: []
  tests: [test_ok_packet_length_overflow_returns_err]
  fixture_strings: ["\\x07\\x00\\x00\\x01\\xff\\xff\\xff\\xff\\xff\\xff"]
verify_on_canonical:
  - defensive_ok_packet_length_cap: NOT FOUND on canonical
  - parse_ok_packet_safe: NOT FOUND on canonical
  - test_ok_packet_length_overflow_returns_err: NOT FOUND on canonical
  - fixture string: NOT FOUND on canonical
cherry_summary: 3 commits, all `+` (no patch-id match on canonical)
apply_check: clean
verdict: novel-and-accretive
confidence: 0.92
evidence: "no symbols on canonical; cherry all `+`; apply clean; defensive guard + test"
strategy: cherry-pick
```

### Example 4: `partially-novel`

```
kind: branch
name: agent-cc-44-parser-refactor-and-fuzz-corpus
fingerprint:
  functions: [Parser::parse_v2, Parser::parse_legacy_v1]
  types: [ParserError]
  tests: [test_parser_v2_basic, test_parser_v2_overflow]
  fixture_strings: [<200 fuzz corpus entries>]
verify_on_canonical:
  - Parser::parse_v2: src/parser.rs:120 ✓ same signature (landed via PR #234)
  - Parser::parse_legacy_v1: NOT FOUND
  - ParserError: src/parser.rs:88 ✓ same enum variants
  - test_parser_v2_basic: tests/parser_test.rs:42 ✓ same body
  - test_parser_v2_overflow: NOT FOUND
  - fuzz corpus: NOT FOUND
cherry_summary: 8 commits, 3 `-` (parser refactor) + 5 `+` (legacy stub + tests + corpus)
apply_check: reject (3 of 8 commits' content rejects; the parser refactor commits)
verdict: partially-novel
confidence: 0.81
commit_breakdown:
  commits 1-3 (parser refactor): superseded
  commit 4 (parse_legacy_v1 stub): superseded (intentionally removed on canonical)
  commit 5 (test_parser_v2_overflow): novel
  commits 6-8 (fuzz corpus files): novel
evidence: "parser refactor superseded by PR #234; novel commits: overflow test + 200-entry fuzz corpus"
strategy: split-commits-hunks (cherry-pick commits 5, 6, 7, 8)
```

### Example 5: `novel-but-stale`

```
kind: branch
name: feature/old-cli-flag-handling
fingerprint:
  functions: [Cli::parse_legacy_flags]
  types: [LegacyFlagSet]
  files: [src/cli/legacy.rs, src/cli/mod.rs]
verify_on_canonical:
  - Cli::parse_legacy_flags: NOT FOUND
  - LegacyFlagSet: NOT FOUND
  - src/cli/legacy.rs: FILE NOT ON CANONICAL
file_existence_coverage: 0.5 (mod.rs exists; legacy.rs gone)
cherry_summary: 4 commits, all `+` (no patch-id match) but apply rejects all
apply_check: fail (every hunk rejects; can't find context)
verdict: novel-but-stale
confidence: 0.85
evidence: "src/cli/legacy.rs no longer exists on canonical; clearly part of an
abandoned refactor branch. Apply impossible without rewriting against new
CLI architecture in src/cli/parse.rs."
strategy: manual decision (default skip)
```

### Example 6: `divergent-refactor`

```
kind: branch
name: agent-cc-77-parser-v3-alt
fingerprint:
  functions: [Parser::parse_v3_alt]
  types: [ParserContext]
  tests: [test_parser_v3_alt_strict]
verify_on_canonical:
  - Parser::parse_v3_alt: NOT FOUND
  - ParserContext: NOT FOUND
  - test_parser_v3_alt_strict: NOT FOUND
cherry_summary: 5 commits, all `+`
apply_check: reject (conflicts with src/parser.rs at lines 120-145)
file_collisions: src/parser.rs ALSO touched by agent-cc-12-feat-parser, agent-cod-3-parser-fix
verdict: divergent-refactor
confidence: 0.78
evidence: "parses with stricter validation strategy; collides with cc-12's v3
on src/parser.rs. Useful concepts but pursued an incompatible direction.
Candidate input to harmonization (Phase 7) on src/parser.rs."
strategy: input to harmonization (Phase 7); if not harmonized, skip and Phase 10 default-skip
```

### Example 7: `dirty-worktree-only`

```
kind: worktree
name: /data/projects/foo-wt-cc-12
underlying_branch: agent-cc-12-feat-parser
underlying_branch_verdict: novel-and-accretive (already triaged separately)
fingerprint (from staged.diff + unstaged.diff):
  functions: [debug_dump_parser_state]
  files_added_in_untracked: [tests/debug_fixture_input.txt]
verify_on_canonical:
  - debug_dump_parser_state: NOT FOUND
verify_on_underlying_branch:
  - debug_dump_parser_state: NOT FOUND on agent-cc-12-feat-parser tip
apply_check: clean (against agent-cc-12-feat-parser tip)
verdict: dirty-worktree-only
confidence: 0.80
evidence: "debug instrumentation + new fixture file present only in worktree's
dirty state; not committed to underlying branch. Useful for debugging."
strategy: worktree-dirty-state (apply staged.diff + unstaged.diff to the
rationalization branch on top of agent-cc-12-feat-parser's content;
copy untracked files in)
```

### Example 8: `already-merged` (the cleanest case)

```
kind: branch
name: agent-cod-3-mysql-fix
sha: 789abc
merge_base: abc12
cherry_summary: 2 commits, both `-` (patch-ids match canonical commits abc789 and 11a22b)
fingerprint: (not even computed — cherry summary is decisive)
verdict: already-merged
confidence: 0.99
evidence: "git cherry -v: both commits show `-` (patch-id-equivalent on canonical
via squash-merge in PR #345)"
strategy: skip
```

---

## Worktree-Specific Triage Notes

A worktree's verdict often piggybacks on the underlying branch's verdict:

| Worktree state | Underlying branch verdict | Combined verdict |
|----------------|---------------------------|------------------|
| Clean (no dirty state) | already-merged | inherits already-merged; worktree is removed in Phase 10 |
| Clean | superseded | inherits superseded; worktree removed |
| Clean | novel-and-accretive | inherits; worktree removed AFTER branch is applied |
| Clean | garbage | inherits garbage; worktree removed |
| Dirty | (any) | the dirty state is triaged independently as `dirty-worktree-only`; the underlying branch keeps its own verdict |
| Locked + prunable | (any) | manual decision; surface to user — locks usually mean someone deliberately set them |
| Detached HEAD | n/a | the worktree's HEAD is a SHA, not a branch; treat as `novel-but-stale` if the SHA isn't on any branch, else inherit the branch the SHA is on |

Detached-HEAD worktrees are common when an agent ran `git worktree add --detach` for a one-off experiment. If the SHA isn't reachable from any current branch ref AND isn't on canonical, the content is still recoverable via the bundle's worktree dirty-state captures — but the user should know it was detached.

---

## When the Rubric Is Wrong

The rubric is statistical — every Phase 6 user-facing table is the human-in-the-loop check. If the user overrides a verdict:

- The override is captured in `user_overrides.tsv` with the user's stated reason.
- The merged `triage.tsv` reflects the override.
- If overrides change >5 verdicts, the merger re-asks for confirmation as a sanity check.

Common override patterns:

- "`agent-old-cli-flags` was novel-but-stale per the rubric, but I want to keep that branch protected — I'm going to revisit it next month." → flip to `protected-preserve` (post-Phase 4 protection extension).
- "`agent-cc-77-parser-v3-alt` was divergent-refactor; harmonize it into src/parser.rs after all, take the strict-validation block." → keep `divergent-refactor` verdict but include in harmonization plan.
- "Two `superseded` rows are actually different from canonical's version — same name but the canonical impl has a regression I want to fix using these." → flip to `novel-and-accretive` and let the user decide which to apply or harmonize.

If the same kind of override happens repeatedly across runs, surface it as skill feedback in Phase 12.

---

## FINGERPRINT Heuristics

The fingerprint is the input to VERIFY-ON-CANONICAL. Quality of the fingerprint determines quality of the verdict.

**For a branch's diff vs merge-base:**

- **Function/method names** — captured by language-aware regex over `+` lines:
  - Rust: `^\+\s*(pub )?(unsafe )?(async )?fn (\w+)`, `^\+\s*(pub )?(struct|enum|trait|type) (\w+)`
  - TypeScript/JS: `^\+\s*(export )?(async )?function (\w+)`, `^\+\s*(export )?(const|let) (\w+) =`, `^\+\s*(export )?(class|interface|type) (\w+)`
  - Python: `^\+\s*(async )?def (\w+)`, `^\+\s*class (\w+)`
  - Go: `^\+func (\w+)`, `^\+func \(\w+ \*?\w+\) (\w+)`, `^\+type (\w+) (struct|interface|...)`
- **Test names** — language-appropriate:
  - Rust: `^\+\s*#\[test\]` then capture next `fn (\w+)`
  - JS: `^\+\s*(it|test)\(['"]([^'"]+)`
  - Python: `^\+\s*def (test_\w+)`
- **Fixture strings** — literal strings ≥ 10 chars in `+` lines, deduplicated. Particularly load-bearing for parsing/regex/network fixtures: a 200-byte hex blob that appears nowhere else on canonical is a near-certain `novel` signal.
- **File paths added** — `^diff --git a/.* b/(.*)$` where the file is `new file mode`. A new file is a strong novel signal.
- **Test names by node text** — `ast-grep` rules where the language has a tree-sitter grammar. Slower than regex but more accurate (skips comments).

**For a worktree's dirty state**, the same heuristics apply, but run against `staged.diff + unstaged.diff` instead of `diff-vs-merge-base.diff`. Untracked files are added to `files_added_in_untracked` directly (their path manifest is `.untracked.list`; their content is in `untracked.tar.gz`).

A fingerprint that's empty (no functions, no types, no tests, no fixture strings, no new files) is a near-certain `garbage` signal — the branch added no introduceable surface, only edits to existing surface.
