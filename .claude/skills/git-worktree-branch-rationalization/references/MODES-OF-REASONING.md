# Modes of Reasoning — Reading Stances for Triage, Harmonization, and Review

A *mode of reasoning* is a deliberate reading stance the agent adopts. Same diff, same bundle, different lens. Modes are composable with each other and with the operator library.

Adapted from [git-stash-janitor's MODES-OF-REASONING.md](../../git-stash-janitor/references/MODES-OF-REASONING.md), with one important addition specific to this skill: **harmonization (Phase 7) is the only phase where the wrong stance can produce content loss rather than just verdict noise.** Forensic gets intent-attribution right; Adversarial stress-tests the synthesis. Both are mandatory for any non-trivial harmonization. The other phases tolerate stance mismatch better.

---

## Why Modes Matter

The same triage worker, given the same branch, can produce wildly different verdicts depending on what it's *looking for*. The rubric provides the procedure; the reading stance provides the prior. Combining well-defined modes with the rubric improves verdict quality without adding new agents.

For the harmonization-planner subagent (Phase 7), modes matter even more: the planner must identify the *intent* of every hunk before deciding how to synthesize. A Literal stance reads "this branch added a length-cap" but doesn't ask "why 4 KiB?" — Forensic does. Adversarial then asks "what could go wrong if we composed this length-cap with the other branch's null-arg guard?" — those two stances together produce the rigorous synthesis that distinguishes this skill from pick-or-drop.

| Phase | Default mode | Why |
|---|---|---|
| 1 (profile) | Literal + Expert | Pattern detection on conventional config files |
| 2 (inventory) | Literal | TSV is mechanical; no interpretation |
| 3 (bundle) | Literal | Verification is byte-equality; no interpretation |
| 4 (protection) | Literal + Skeptical | Skeptical sanity-checks the auto-protected list against actual user intent |
| 5 (triage) | Literal + Forensic | Literal for high-fingerprint-coverage rows; Forensic for novel-but-stale |
| 6 (merge) | Literal | The decision table is mechanical |
| 7 (harmonization) | **Forensic + Adversarial** | Forensic for intent attribution; Adversarial for synthesis robustness — both mandatory |
| 8 (apply, commit msg) | Forensic | The commit message answers "where did this hunk come from?" — Forensic is the rubric |
| 8 (apply, conflict resolution) | Junior + Expert | Junior surfaces context needs; Expert proposes resolutions |
| 8b (split) | Forensic + Expert | Identifying which commits are novel requires forensic reading |
| 9 round 1 | Literal | Catches overt bugs |
| 9 round 2 | Forensic (Standard) / Adversarial (Comprehensive+) | Asks "what was the intent?" / "what could break?" |
| 9 round 3 | **Adversarial** | Stress-test the harmonized syntheses (most likely place for integration bugs) |
| 10 (cleanup) | Literal | Verbatim authorization is mechanical; no interpretation |
| 11 (handoff) | Junior | Does the report stand alone for someone who wasn't in the run? |
| 12 (user-lens) | Forensic + Adversarial | Reconstruct the user's experience; stress-test it |

---

## Mode 1 — LITERAL

**Definition:** Read the diff as a textual pattern. Don't interpret intent. Don't speculate about what the developer wanted.

**Triggers:**
- Phase 5 default for high-fingerprint-coverage rows (the rubric is enough)
- Phase 9 round 1 ("read what's there, look for obvious bugs")
- Phase 10 (verbatim authorization is read literally)

**Reading prompt template:**
```
[MODE: Literal]

Read the diff at {DIFF_PATH}. Do not infer intent. Answer ONLY:

1. What identifiers (functions, types, tests) are introduced (in `+` lines NOT
   matched by a `-` line)?
2. What identifiers are removed (in `-` lines NOT matched by a `+` line)?
3. What files are touched? Which are new? Which are deleted?
4. Is the diff binary-only, whitespace-only, or comment-only?
5. For each changed function: did the signature change? (parameter list, return
   type, generic bounds, async-ness). If yes, this is a `divergent-refactor`
   candidate per Axiom 16, not a simple `superseded`.

Output the answers in the fingerprint JSON format. No prose. No interpretation.
```

**Strengths:** fast, deterministic, low false-positive rate. The literal stance is the rubric's "is this symbol on canonical?" check.

**Weaknesses:** misses semantic equivalence (rename, refactor); misses architecture-level "is this still the right approach" questions; misses subtle defensive-check ordering issues.

---

## Mode 2 — SKEPTICAL

**Definition:** Assume the rubric's classification or the harmonization planner's proposal is wrong. What evidence would prove it wrong?

**Triggers:**
- Phase 5 for rows with confidence ≥ 0.85 (sanity-check the high-confidence verdicts)
- Phase 6 borderline review
- Phase 9 round 2 of Comprehensive mode (alternated with Forensic)

**Reading prompt template:**
```
[MODE: Skeptical]

The rubric classified <branch> as {VERDICT} with confidence {CONF}.
Suspend agreement. Find evidence that this verdict is wrong.

Specifically:
1. If 'superseded': can you find a fingerprint symbol that's NOT on canonical with
   the same signature? Per Axiom 16, sample at least 3 introduced symbols.
2. If 'novel-and-accretive': can you find a function on canonical with similar
   semantics that supersedes this in spirit even if not in name?
3. If 'garbage': can you find ANY hunk that adds defensive code, a bug fix,
   or a test that the polished version missed?
4. If 'novel-but-stale': could the branch's intent be ported to current canonical,
   even if the surface form is unportable? (Forensic stance is better for this
   one — switch if you're going deep.)
5. If 'already-merged' (cherry -v all `-`): can the patch-id check be wrong? (very
   rare; only if the squash-merge introduced subtle textual changes.)

Output: counter-evidence, OR confirmation that the verdict holds.
```

**Strengths:** catches mis-classifications the rubric misses; especially good at finding `superseded` rows that are actually `partially-novel` because of signature divergence.

**Weaknesses:** can produce paranoid "what if?" findings that aren't actionable. Pair with a decision-rule (e.g., "if counter-evidence exists, downgrade confidence by 0.10 and surface").

---

## Mode 3 — JUNIOR

**Definition:** Read as if you're new to this codebase. What would you NOT understand about this diff or this synthesis?

**Triggers:**
- Phase 8 conflict resolution (catches assumed context)
- Phase 8b split-apply review
- Phase 11 handoff report draft (does the report stand alone?)

**Reading prompt template:**
```
[MODE: Junior]

You're a developer new to this codebase. Read the proposed conflict resolution
or harmonized synthesis at {PATH}. Answer:

1. What identifiers, file paths, or domain terms do you NOT recognize?
2. What context (linked tickets, prior PRs, side-channel discussions) would you
   need to understand WHY this resolution is correct?
3. What invariants does the resolution rely on? Are they documented?
4. If you were reviewing this PR, what questions would you ask?
5. For harmonized syntheses: does the commit message let you trace each hunk
   back to its source branch and intent? If not, what's missing?

Output: list of unmet context needs.
```

**Strengths:** surfaces invisible knowledge; catches resolutions that "make sense to the agent who wrote them" but aren't reproducible.

**Weaknesses:** can be over-cautious. Use the output to *augment* the commit message and the harmonization plan's "risks" column, not to block the apply.

---

## Mode 4 — EXPERT

**Definition:** Read with deep language and architecture knowledge. What language-specific idioms does this introduce or violate?

**Triggers:**
- Phase 8 commit message authoring
- Phase 9 round 1 ("look for obvious bugs the project's idioms would catch")
- Per-language fingerprinting (when the worker is a language-specialist subagent)

**Reading prompt template:**
```
[MODE: Expert in {LANGUAGE}]

Read the diff or synthesis at {PATH}. As a senior {LANGUAGE} engineer, answer:

1. Are the introduced symbols idiomatic for this language? (e.g., Rust: are
   `Result` returns used appropriately? Is `unwrap()` justified? Are lifetimes
   explicit only when necessary?)
2. Are there language-specific anti-patterns? (e.g., TS: missing `await` on a
   Promise; Python: mutable default argument; Go: ignored errors)
3. Are concurrency / safety primitives used correctly?
4. Are there test patterns the project uses that this diff fails to follow?
5. For harmonized syntheses: does the composition order respect language idioms?
   (e.g., in Rust, ordering `?` propagation vs. defensive returns matters; in TS,
   ordering type narrowings vs. value checks matters.)

Output: per-hunk technical assessment.
```

**Strengths:** catches issues the rubric's textual fingerprinting misses entirely.

**Weaknesses:** opinion-heavy; pair with project-specific style guide if available.

---

## Mode 5 — ADVERSARIAL

**Definition:** What could go wrong if this branch were applied or this synthesis landed? Compounding errors? Hidden dependencies? Latent invariant violations?

**Triggers:**
- **Phase 7 harmonization synthesis stress-test** (mandatory for Comprehensive+)
- Phase 9 round 2 default (Standard mode) or round 3 default (Comprehensive+)
- Pre-Phase-10 final sanity check before destructive cleanup

**Reading prompt template:**
```
[MODE: Adversarial]

Assume this branch will be applied OR this synthesis will land. What could go
wrong, in production?

Specifically:
1. Does the introduced code have a failure mode that's silent in tests but
   visible in production? (rate limits, time-of-day, scale, locale, network)
2. Does it introduce a security surface? (input parsing, auth bypass, untrusted
   data, deserialization)
3. Does it interact with concurrent code in non-obvious ways?
4. Does it have a hidden dependency on a config or env var that's not
   documented?
5. For harmonized syntheses: is the composition order safe? Could a defensive
   check from branch A make a check from branch B unreachable? Could a type
   narrowing from branch A break the call site that branch B introduced?
6. For harmonized syntheses: does the synthesis preserve invariants that any
   single variant relied on? (e.g., variant A assumed the input was non-empty
   because variant A added an emptiness check at the call site, but variant B's
   refactor removed that call site)
7. If this code crashed at 3am on a Sunday, what would the on-call see in
   the logs?

Output: ranked list of risks with severity (low/medium/high) and mitigation.
```

**Strengths:** catches issues that pass tests but break in production. **The mandatory stance for Phase 7 synthesis stress-testing.**

**Weaknesses:** generates work — every risk needs triage. Use the output to gate Phase 9 (don't drop until risks are resolved or accepted).

---

## Mode 6 — FORENSIC

**Definition:** Reconstruct the developer's intent from the diff and surrounding context (commit history, message, branch name, related branches). What were they trying to accomplish?

**Triggers:**
- Phase 5 for `novel-but-stale` rows (decide whether to rewrite vs. drop)
- **Phase 7 intent-attribution** (mandatory for the harmonization-planner)
- Phase 8 commit message authoring (the why is forensic)
- Phase 9 round 2 of Comprehensive mode

**Reading prompt template:**
```
[MODE: Forensic]

Reconstruct the developer's intent from these artifacts:

- Branch diff: {BUNDLE}/branches/<slug>/diff-vs-merge-base.diff
- Branch's per-commit history: {BUNDLE}/branches/<slug>/commits.tsv
- Branch name: <name> (does the prefix family suggest intent? e.g., `agent-cc-*`
  is an agent run; `feature/*` is human-authored; `wip-*` is unfinished)
- Author: from commits.tsv
- Branch tip date: from commits.tsv (recent = more relevant; old = abandoned signal)
- Surrounding commits on canonical (±1 week of branch tip): git log --since=...
  --until=... canonical
- Linked beads issue (if branch name or commit message contains a ticket id):
  br show <id>

Answer:
1. What was the developer trying to accomplish?
2. Did the work continue elsewhere (a polished landing on canonical) or get
   abandoned?
3. If kept, what's the smallest scope that preserves the intent?
4. For harmonization: which hunks express which intents from the 8-intent
   taxonomy (defensive / refactor / test / fixture / type-narrowing /
   error-handling / performance / naming)? Per HARMONIZATION.md § 3.
5. What's the proposed commit message (with `Recovers <intent> from <branch>;
   originally drafted on <date>; supersedes nothing | superseded by commit <sha>`)?

Output: forensic report with intent + recommended action.
```

**Strengths:** turns ambiguous diffs into actionable decisions; produces high-quality commit messages; **the mandatory stance for Phase 7 intent attribution.**

**Weaknesses:** time-consuming. Use only on `novel-but-stale` and `partially-novel` rows in Phase 5; use universally in Phase 7.

---

## Mode 7 — TIMELINE

**Definition:** Reconstruct the sequence of operations that produced this branch's current state. Use reflog, commit graph, and the bundle's index.

**Triggers:**
- Branches with unreachable parents
- Branches that postdate a force-push (origin history rewritten)
- Branches whose merge-base is suspiciously old (months back)

**Reading prompt template:**
```
[MODE: Timeline]

Reconstruct the timeline for branch <name>.

Inputs:
- Bundle meta: {BUNDLE}/branches/<slug>/meta.txt (sha, parent, date, author)
- Bundle commits.tsv: {BUNDLE}/branches/<slug>/commits.tsv (the per-commit list
  back to merge-base)
- git reflog show <branch>  (the branch's reflog if available)
- git log --all --reflog --oneline | head -200  (commits including unreachable)
- Other branches that share the merge-base: git branch --contains <merge-base>
- Force-push detection: any reflog entry of the form "update by push" with
  divergent-history hint

Output a timeline:
1. T-N: branch <X> created at <sha> from <merge-base>
2. T-(N-1): developer made <commit-1> (subject: ...)
3. T-(N-2): developer made <commit-2> (subject: ...)
4. T-(N-3): branch <X> may have been force-pushed (if reflog suggests)
5. T-(N-4): branch <Y> branched off <X> at <sha-Y>
6. T-now: branch <X> is in the local list with <ahead>/<behind> vs canonical

This timeline informs whether the branch is recoverable, whether its content is
already represented elsewhere, and whether dropping it loses history.
```

**Strengths:** invaluable for `novel-but-stale` rows where you can't tell if the work was abandoned or moved; also for branches with downstream branches built on top (`agent-cc-12-feat-parser-v2` built on `agent-cc-12-feat-parser`).

**Weaknesses:** requires repo with healthy reflog; older branches may have lost reflog history (default 90-day expiry). The bundle's `commits.tsv` is the backstop — it captures the per-commit list at run time so even reflog gc doesn't lose it.

---

## Composition Rules

| Phase | Default mode | Best alternates |
|---|---|---|
| 1 (profile) | Literal + Expert | — |
| 2 (inventory) | Literal | — |
| 3 (bundle) | Literal (verification is the gate) | — |
| 4 (protection) | Literal + Skeptical | Forensic for ambiguous candidates |
| 5 (triage) | Literal + Forensic | Skeptical for high-confidence rows; Expert for language-heavy diffs; Timeline for branches with unreachable parents |
| 6 (merge) | Literal | Skeptical (sanity-check rubric) |
| 7 (harmonization) | **Forensic + Adversarial** (mandatory pair) | Expert for language-specific composition rules |
| 8 (apply) | Expert + Adversarial | Junior (for conflict resolutions); Forensic (for commit messages) |
| 8b (split) | Forensic + Expert | Timeline (for non-linear histories) |
| 9 round 1 | Literal | — |
| 9 round 2 | Forensic | Adversarial for Comprehensive+ |
| 9 round 3 | Adversarial | Skeptical for max paranoia |
| 10 (cleanup) | Literal (verbatim authorization) | — |
| 11 (handoff) | Junior (does the report stand alone?) | — |
| 12 (user-lens) | Forensic + Adversarial | — |

The mode is **named** in the agent prompt (e.g., `[MODE: Adversarial]`). Different modes can be composed in the same session — the mode tag tells future readers what stance produced which finding.

---

## Worked Example — The Same Diff Through All Four Stances

**Scenario:** branch `agent-cc-12-feat-parser` introduces a new `Parser::parse_v3` function with this diff:

```diff
--- a/src/parser.rs
+++ b/src/parser.rs
@@ -100,6 +100,28 @@ impl Parser {
+    pub fn parse_v3(input: &str) -> Result<Ast, ParseError> {
+        if input.is_empty() {
+            return Err(ParseError::EmptyInput);
+        }
+        // ... v3 implementation using new error type
+    }
```

Canonical's `Parser::parse` takes `&[u8]` (not `&str`) and returns `Result<Ast, anyhow::Error>` (not `ParseError`).

### Reading 1 — LITERAL stance produces

> Branch introduces:
> - Function: `parse_v3(input: &str) -> Result<Ast, ParseError>`
> - Adds emptiness check at function entry
>
> Canonical has: `parse(input: &[u8]) -> Result<Ast, anyhow::Error>`.
>
> The introduced symbol `parse_v3` does NOT appear on canonical.
> Verdict candidate: `novel-and-accretive`. Confidence 0.88.

### Reading 2 — SKEPTICAL stance produces

> The Literal verdict is `novel-and-accretive`. Suspend agreement.
>
> Counter-evidence search:
> - Is there a function on canonical with similar semantics? Yes: `parse(&[u8])`.
>   It has the same purpose (parse input → Ast), just different signature.
> - Is `parse_v3` an upgrade or a parallel implementation?
>   - Different signature: `&str` vs. `&[u8]` (parse_v3 narrows the input domain).
>   - Different error type: `ParseError` vs. `anyhow::Error` (parse_v3 introduces a typed enum).
>
> This is `divergent-refactor`, not `novel-and-accretive`. Per Axiom 16:
> "Same-name on canonical is not always supersession" — and the converse:
> different-name on canonical may be the same intent. Surface to user OR
> include in Phase 7 harmonization (the file is touched by ≥2 branches).
>
> Verdict counter-evidence: divergent-refactor candidate. Confidence 0.75.

### Reading 3 — FORENSIC stance produces

> Reconstruct intent.
>
> Branch name: `agent-cc-12-feat-parser`. Family: agent run.
> Branch tip date: 2026-04-22. Branch is recent (16 days old at run time).
> Branch's per-commit list:
>   - 8e3f1c "feat(parser): introduce parse_v3 with typed errors"
>   - 9a2b1d "feat(parser): add NonEmptyStr narrowing on input"
>   - aabbcc "test: parse_v3 corpus"
>
> Surrounding commits on canonical (±1 week of branch tip):
>   - canonical's last touch to src/parser.rs was 2025-11-12 (5 months ago).
>     Canonical hasn't been actively developed in this area.
>
> Inferred intent:
>   - The branch is an agent's attempt to modernize the parser:
>     - Switch from `&[u8]` to `&str` (utf8-validity precondition)
>     - Switch from `anyhow::Error` to typed `ParseError` enum (stronger guarantees)
>     - Add an emptiness check (defensive)
>     - Add a typed-narrowing on input (`NonEmptyStr` per commit 9a2b1d)
>     - Add a regression test corpus
>
> The intent expresses 4 of the 8 intent categories from HARMONIZATION.md § 3:
>   - refactor (signature change)
>   - error-handling (typed enum)
>   - defensive (emptiness check)
>   - test (corpus)
>   - type-narrowing (NonEmptyStr — depending how it lands)
>
> Per HARMONIZATION.md § 3, refactors do NOT compose. This branch is a
> wholesale refactor of `Parser::parse`. If another branch also touches
> Parser::parse with a different refactor direction, this is `divergent-refactor`
> and Phase 7 must surface to user.
>
> Per HARMONIZATION.md § 4.7, error-handling composes if compatible. ParseError
> (typed enum) > anyhow::Error (untyped). The synthesis (if no other refactor
> conflicts) should adopt the typed enum.
>
> Verdict: depends on whether other branches also touched src/parser.rs.
> If yes → harmonization candidate. If no → novel-and-accretive (the refactor is
> the only one in flight; user can decide whether to land it).

### Reading 4 — ADVERSARIAL stance produces

> Stress-test: assume this branch were applied. What could go wrong?
>
> 1. Call sites for `parse(&[u8])` are not updated. Adding `parse_v3(&str)` is
>    additive (the old `parse` still exists), but the project may not have
>    transitioned. The two functions coexist with subtly different behaviors:
>    `parse` accepts arbitrary bytes including invalid UTF-8; `parse_v3`
>    requires valid UTF-8. A caller passing arbitrary bytes to `parse` is
>    correct today; a future caller migrating to `parse_v3` may panic on
>    UTF-8 conversion.
> 2. The `EmptyInput` variant of `ParseError` is good defensive code, but does
>    the typed enum have OTHER variants? If only `EmptyInput`, the typed enum
>    is weaker than `anyhow::Error` (which can carry any error). Need to see
>    the full ParseError definition.
> 3. The `NonEmptyStr` type narrowing (commit 9a2b1d) implies a constructor
>    that returns `Result<NonEmptyStr, EmptyError>`. The constructor's call
>    sites must be added to every place that currently constructs a `&str`
>    for parsing. This is a non-trivial migration. If the branch landed
>    without migrating call sites, the new `NonEmptyStr` is unused — dead code.
>
> Risk severity:
> - call-site coexistence (UTF-8 vs. bytes): MEDIUM (silent semantic difference)
> - typed-enum variant coverage: LOW (easy to verify; just read the enum)
> - NonEmptyStr unused: HIGH if true (dead code that's expensive to maintain)
>
> Recommended action:
>   - Phase 5: classify as `divergent-refactor` if any other branch touches
>     src/parser.rs OR `novel-and-accretive-with-migration-required` otherwise
>   - Phase 7 (if harmonized with other parser branches): preserve the typed
>     enum + emptiness check; surface the call-site coexistence issue to user
>   - Phase 8: per-apply gates MUST include UBS or equivalent dead-code
>     detection to catch a NonEmptyStr that's unused

### Reconciling Across Stances

The four readings produce three different verdicts (`novel-and-accretive`, `divergent-refactor`, `divergent-refactor` again, plus a list of risks). The reconciliation:

1. **Literal alone is wrong** because it didn't catch the same-purpose-different-name pattern (Axiom 16).
2. **Skeptical** correctly flipped the verdict to `divergent-refactor` candidate.
3. **Forensic** identified the intent set (4 of 8 from the harmonization taxonomy) and surfaced the dependency on whether other branches touch the same file.
4. **Adversarial** identified concrete production risks the user must adjudicate.

The final verdict is `divergent-refactor` IF another branch touches src/parser.rs (which is likely in agent-swarm aftermath); otherwise `novel-and-accretive` with a high-priority migration-required note. The Phase 7 harmonization plan, if invoked, will use the **Forensic + Adversarial** pair to build the variant matrix and stress-test the synthesis.

This is why **Phase 7 mandates Forensic + Adversarial as a pair**: Forensic alone misses the production-risk surface; Adversarial alone misses the intent attribution that lets the synthesis do better than pick-or-drop.

---

## Anti-Patterns in Mode Selection

| ✗ | Why |
|---|---|
| Always running Adversarial in Phase 5 | Generates noise; rubric is sufficient for high-confidence rows |
| Skipping Forensic on `novel-but-stale` | The verdict requires intent-reconstruction — Forensic IS the rubric for this verdict |
| Skipping Forensic in Phase 7 intent-attribution | The 8-intent taxonomy can't be applied without it; harmonization devolves to pick-or-drop |
| Skipping Adversarial in Phase 7 synthesis stress-test | Composition errors only show up under adversarial reading; landing them is exactly what makes harmonization "stash-janitor with extra steps" |
| Using Junior for conflict-resolution proposals | Right tool, wrong direction — Junior surfaces context needs, doesn't propose resolutions |
| Mixing modes mid-prompt | One stance per prompt; switch by tag |
| Not naming the mode in the prompt | Future readers can't tell why a finding has a particular shape |
| Using Skeptical to question the harmonization plan after Forensic + Adversarial already passed | Diminishing returns; Skeptical's value is on the rubric's high-confidence rows, not on a Phase 7 plan that's already been multi-stance reviewed |
| Using Adversarial in Phase 10 cleanup authorization | Cleanup is mechanical (verbatim authorization); Adversarial generates spurious risks at this point |

---

## Cross-References

- Phase-by-phase default modes are summarized in [PHASES.md](PHASES.md) per phase.
- The Forensic + Adversarial pair for Phase 7 is mandated by [HARMONIZATION.md § 4](HARMONIZATION.md) and [HARMONIZATION.md § 6](HARMONIZATION.md).
- Multi-model triangulation uses these stances on a single model as Path B per [MULTI-MODEL-TRIANGULATION.md § Path B](MULTI-MODEL-TRIANGULATION.md#path-b-fallback--same-session-multi-stance-task-subagents).
- The agent-prompt templates that consume mode tags are in [AGENT-PROMPTS.md](AGENT-PROMPTS.md).
- The intent taxonomy that Forensic uses to classify hunks is in [HARMONIZATION.md § 3](HARMONIZATION.md).
- Axiom 16 (same-name not always supersession) — the canonical example for why Literal alone is insufficient: [SKILL.md § Kernel](../SKILL.md#the-rationalization-kernel-universal-axioms).
