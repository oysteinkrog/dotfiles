# Fresh-Eyes Prompts — Extended Library for Phase 9

The three calibrated prompts in [PHASES.md § Phase 9](PHASES.md) are the default rotation. This file extends them with mode-specific variants, harmonization-specific deepenings, cleanup-specific verifications, and adversarial third rounds.

Adapted from [git-stash-janitor's FRESH-EYES-PROMPTS.md](../../git-stash-janitor/references/FRESH-EYES-PROMPTS.md). Two additions vs. stash-janitor:

1. **Phase 9 harmonization-specific prompt.** Stash-janitor doesn't synthesize — there's nothing to verify. Branch-rationalization's Phase 7 produces harmonized syntheses, and Phase 9 has to verify each one preserves every cited intent.
2. **Phase 9 cleanup-specific prompt.** The skill's safety guarantees (Axioms 3, 4) require verifying that backup refs and the bundle survived Phase 8 untouched and that the rationalization-branch tip is clean before Phase 10 unlocks.

The prompts are versioned. Use the version number in `fresh_eyes_log.md` so future runs can be compared.

> **Why verbatim prompts?** Per AGENTS.md "No Script-Based Changes" and the broader documentation-website-for-software-project methodology: the three default prompts are *calibrated* — small wording changes shift the reading stance and degrade the convergence guarantees. Use the augmentations in Sections 4–6, not paraphrase.

---

## 1. Default rotation (use verbatim)

These three prompts come from documentation-website-for-software-project and are used unchanged. They constitute Phase 9's spine for every mode.

### Round 1 — Read what you wrote (v1.0)

> Carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.

**Reading stance:** Literal
**Looks for:** typos, off-by-one errors, missing null checks, leftover debug prints, copy-paste errors

### Round 2 — Random walk the codebase (v1.0)

> Sort of randomly explore the code files in this project, choosing code files to deeply investigate and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes. Comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in AGENTS.md.

**Reading stance:** Forensic
**Looks for:** integration bugs, broken invariants, hidden dependencies, mismatched assumptions

### Round 3 — Adversarial review (v1.0)

> Turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep.

**Reading stance:** Adversarial
**Looks for:** security issues, race conditions, error-handling gaps, scaling problems

---

## 2. Mode-specific termination rules

| Mode | Min rounds | Termination condition | Notes |
|---|---|---|---|
| Quick | 1 | After Round 1, the gates (test/typecheck/lint/ubs) all exit 0 AND the round produced only trivial findings | Single-pass — assumes the recovered content is small and bounded |
| Standard | ≥2 | Round 1 + Round 2 each produce only trivial findings AND gates green at the end of each | The default for most production repos |
| Comprehensive | ≥3 | Round 1 + Round 2 + Round 3 each produce only trivial findings AND two consecutive trivial-only rounds at the end AND gates green throughout | The asupersync-scenario default |
| Council | ≥3 multi-model | Round 1 (Claude) + Round 2 (Codex + Claude triangulated) + Round 3 (Codex + Claude + Gemini triangulated) all converge on the same trivial-or-empty finding set AND gates green throughout | Production-critical / security-sensitive |

> **Why "≥" for Standard and above?** Per [SKILL.md "The Phase Loop"](../SKILL.md#the-phase-loop-mandatory): "Phases 5 and 9 are reapply-until-quiet — keep spawning passes until an entire pass produces only trivial findings." If round N+1 still finds substantive issues, run round N+2; the minimum is a *floor*, not a ceiling.

### What counts as "trivial"

| Trivial | Substantive |
|---|---|
| Typo in a comment | Wrong constant in production code (1024 vs 1000) |
| Inconsistent indentation | Off-by-one in a loop |
| Misnamed local variable | Missing null-check on user input |
| Unused import | Race condition in concurrent code |
| Comment phrasing | Resource leak (no `Drop` impl, no `with`) |
| Single missing trailing newline | Wrong error type propagated |
| Whitespace in a test fixture | Test doesn't actually exercise the code path it claims |

The rule of thumb: **if the finding could only be detected by reading and would not surface as a runtime failure, log/security issue, or test break, it's trivial.** Substantive findings extend the round count.

### What counts as "blocking-unresolvable"

If the same finding appears across 3 consecutive rounds without resolution, escalate as blocking-unresolvable. The skill does NOT terminate Phase 9; instead, the fresh-eyes subagent surfaces the finding to the user with full context (file:line, what was tried, why each attempt failed). The user decides: skip the keeper, manually intervene, or accept the issue.

> **Why escalate rather than auto-fix?** Per AGENTS.md "Mandatory explicit plan": ambiguity is escalated, not guessed. A repeat-3 finding is by definition ambiguous (the agent has tried and failed to resolve it twice).

---

## 3. Mode-specific compressions

### Quick mode — single round

For Quick mode (W<5, B<30), the rotation is compressed:

> The rationalization branch has just been authored — N keeper commits over canonical, S of which are harmonized syntheses. Read the new commits with fresh eyes; look for obvious bugs (typos, missing null checks, copy-paste errors), then verify tests still pass. For each harmonized synthesis, briefly verify the synthesis preserves each cited intent. Fix any obvious bugs in place.

### Standard mode — 2 rounds

Use Round 1 + Round 2 from the default rotation. Skip Round 3 unless any keeper touches security-sensitive code (auth, secrets, payment, persistence layer, network boundary). When in doubt, run Round 3.

### Comprehensive mode — 3 rounds + triangulation

Use the full default rotation. For Comprehensive, triangulate Round 2 across Codex + Claude (independent runs of the same prompt). Triangulate Round 3 across Codex + Claude + Gemini. Convergence: same finding set across models is high-confidence; per-model unique findings are lower-confidence and surface to user.

### Council mode — multi-model adjudicated

Round 1 stays single-model (the rationalization branch's own author). Rounds 2 and 3 run on Codex + Claude + Gemini in parallel; an adjudication pass at the end of each round merges findings, classifies by `multi-model-consensus`, `claude-only`, `codex-only`, `gemini-only`, and emits a single round-summary in `fresh_eyes_log.md`.

---

## 4. Phase 9 harmonization-specific prompt

For every harmonized synthesis commit on the rationalization branch, run this verification prompt as an extension to whichever round currently applies:

> For every commit on the rationalization branch tagged `harmonized-synthesis` (look for the commit message marker `Synthesis-Of:` listing source branches), do the following:
>
> 1. Open the commit's diff. Identify each hunk.
> 2. Open `harmonization_plan.md` for the affected file. Find the variant matrix.
> 3. For each cited intent in the variant matrix, verify the synthesis preserves it. The check is: does the synthesized code contain the substantive content (not just a comment) that implements that intent?
>    - **Defensive intent**: the synthesis adds the input check / null guard / length cap / redaction.
>    - **Type-narrowing intent**: the synthesis adopts the tighter type signature.
>    - **Test intent**: the synthesis lifts the new test file or test function.
>    - **Fixture intent**: the synthesis includes the new fixture file.
>    - **Error-handling intent**: the synthesis uses the stronger error type.
>    - **Performance intent**: the synthesis preserves the optimization.
>    - **Refactor intent**: the synthesis adopts the picked refactor's shape.
>    - **Naming intent**: the synthesis uses the picked name.
> 4. For each intent, verify the synthesis does NOT introduce a regression in any of them. The check is: does any new layer of synthesis weaken or invalidate a layer added below it?
>    - Common regression: a defensive null-check added by branch A is silently bypassed because branch B's refactor changed the call shape; the null-check is now in dead code.
>    - Common regression: a type-narrowing from branch C is undermined because branch D's error-handling now constructs the narrowed type from an unchecked source.
> 5. For each cited intent that is NOT preserved, file a finding: `harmonization-regression: <file>:<line> intent <intent-tag> from <source-branch> not preserved in synthesis`.
> 6. For each regression detected, file a finding: `harmonization-conflict: <file>:<line> <intent-A from branch X> regressed by <intent-B from branch Y>`.
>
> The check is **fidelity**, not stylistic preference. The harmonization plan was the user-reviewed contract; deviations from it are bugs.

**Reading stance:** Forensic + Skeptical
**Where in the rotation:** runs as a parallel deepening of Round 2 (Standard mode) or as a dedicated sub-round between Round 2 and Round 3 (Comprehensive / Council).

> **Why this is mandatory:** Per [SKILL.md Axiom 1](../SKILL.md#the-rationalization-kernel-universal-axioms): "Harmonize, don't pick. The job is to ... synthesize the strongest current implementation on top of canonical's architecture." If the synthesis silently drops an intent, the run has failed its conceptual centerpiece. Without this prompt, fresh-eyes might focus on Rust-idiom polish and miss that the redaction regex got dropped.

---

## 5. Phase 9 cleanup-specific prompt

After Round 2 (Standard / Comprehensive) and before unlocking Phase 10, run this verification prompt to confirm the safety net is still intact:

> Verify the safety preconditions for Phase 10 destructive cleanup. The safety net is fivefold per [SAFETY-MODEL.md](SAFETY-MODEL.md):
>
> 1. **Backup refs intact.** Run:
>    ```bash
>    bundle_count=$(awk -F'\t' '$1=="branch" {print}' "<bundle>/index.tsv" | wc -l)
>    live_count=$(git for-each-ref refs/branch-rationalization-backup/ | wc -l)
>    [ "$bundle_count" = "$live_count" ] && echo "OK: $bundle_count backup refs match index.tsv" || echo "FAIL: $bundle_count expected, $live_count live"
>    ```
>    Fail = halt; spawn incident-responder I1 (bundle byte-equality mismatch).
>
> 2. **Object bundle round-trips cleanly.** Run:
>    ```bash
>    git bundle list-heads "<bundle>/object-bundle.pack" > /dev/null && echo "OK" || echo "FAIL: bundle does not list-heads"
>    bash scripts/verify-bundle.sh "<bundle>" --quiet && echo "OK" || echo "FAIL"
>    ```
>    Fail = halt; recovery via [ADVANCED-RECOVERY.md AR1](ADVANCED-RECOVERY.md#ar1-git-gc---prunenow-ran-after-the-backup-refs-were-deleted).
>
> 3. **Per-branch diff + format-patch present for every applied keeper's source branches.** For every row in `apply_log.tsv` and `partial_split_log.tsv`, verify:
>    ```bash
>    [ -f "<bundle>/branches/<slug>/diff-vs-merge-base.diff" ]
>    [ -d "<bundle>/branches/<slug>/format-patch/" ] && [ "$(ls "<bundle>/branches/<slug>/format-patch/" | wc -l)" -gt 0 ]
>    ```
>    Fail = halt; recovery requires re-bundling.
>
> 4. **Per-worktree dirty-state captures present for every worktree the cleanup plan will remove.** For each worktree-removal entry in the planned `cleanup_log.tsv`:
>    ```bash
>    wt_slug="<sanitized>"
>    [ -f "<bundle>/worktrees/$wt_slug/staged.diff" ]
>    [ -f "<bundle>/worktrees/$wt_slug/unstaged.diff" ]
>    # If the worktree had untracked content, verify the tarball:
>    if grep -q "^untracked.tar.gz$" "<bundle>/worktrees/$wt_slug/.untracked.list" 2>/dev/null; then
>      [ -f "<bundle>/worktrees/$wt_slug/untracked.tar.gz" ]
>    fi
>    ```
>    Fail = halt; missing dirty-state captures mean the worktree's uncommitted work is unrecoverable.
>
> 5. **Rationalization-branch tip is clean.** Run:
>    ```bash
>    git -C <project> status --porcelain        # must be empty
>    git -C <project> rev-parse --abbrev-ref HEAD  # must be the rationalization branch
>    cargo test  # or the project's actual test command from project_profile.json
>    cargo check  # or the project's actual typecheck
>    cargo clippy -- -D warnings  # or the project's lint
>    ubs .  # if available
>    ```
>    All exit 0 = OK. Any failure = halt; do NOT unlock Phase 10 with a broken rationalization branch.
>
> If any of these checks fail, file a `cleanup-precondition-broken: <check-id> <details>` finding. Halt the round; do not proceed to Phase 10.

**Reading stance:** Verifying (read-only checks; never destructive)
**Where in the rotation:** runs *after* Round 2 (Standard) or *after* Round 3 (Comprehensive / Council) as a non-negotiable termination condition. Phase 10 must NOT unlock unless this check passes.

> **Why this is at Round-end, not Round-1:** the rationalization-branch tip might fail gates mid-Phase-8 and be fixed in Round 1 of fresh-eyes; the safety-precondition check is the *final* clearance, run once everything else has converged.

---

## 6. Round 3 adversarial deepening (Comprehensive / Council)

For Round 3 in Comprehensive and Council modes, append this adversarial deepening to the default Round 3 prompt:

> Additionally, assume the rationalization branch will be merged tomorrow and shipped to production by end of week. What could go wrong? Reason from first principles:
>
> - **Rollback story:** if the rationalization branch causes a production incident, can the user revert cleanly? `git revert -m 1 <merge-commit>` should produce a clean inverse. Are there commits that depend on each other in a way that prevents partial revert?
> - **Compounding effects across keepers:** if keeper A introduces a defensive check and keeper B (also harmonized) refactors the call site, does the combination still defend? Run mental simulation on the canonical hot paths.
> - **New attack surfaces:** harmonized syntheses lift code from N branches and combine them. Does the combination introduce a new attack surface (e.g., parser branch X allowed input format A; branch Y allowed format B; the synthesis supports both, expanding the parser's grammar)?
> - **Hidden state:** any keeper that introduces or modifies module-level statics, lazy_statics, OnceCell, or module init? Verify init order is sound under the rationalization branch's commit graph.
> - **Test coverage gaps:** for every recovered keeper, find a corresponding test that exercises the new behavior. If a keeper added a defensive check but no test exercises the failure path, file a finding.
> - **Breaking changes:** any keeper that changes a public function signature? If yes, the rationalization branch has a breaking-change implication; flag for the user.
>
> Output: severity-labeled findings (low/medium/high), each with a proposed mitigation OR an acceptance rationale.

> **Why adversarial:** the rationalization branch consolidates 200+ branches' worth of work in one commit cluster; standard tests + lint + UBS only catch what they were written to catch. Adversarial review catches *the gap between what the tests cover and what the production scenario will exercise*.

---

## 7. Language-specific augmentations

Append the language-specific concerns to the round prompt as additional bullets, after the harmonization and adversarial extensions.

### Rust

> Additionally:
> - Check for `unwrap()` / `expect()` without justification — these panic in production
> - Check for `clone()` in hot paths (allocation cost)
> - Verify any new `unsafe` blocks have safety invariants documented in comments
> - Check that `?` propagation makes sense (don't swallow errors that should be handled)
> - Verify lifetime annotations are correct and minimal
> - For harmonized syntheses: verify trait implementations don't have conflicting `impl` blocks across the synthesized variants

### TypeScript / JavaScript

> Additionally:
> - Check for missing `await` on Promise-returning calls
> - Check for `any` types where specific types should be inferred
> - Verify error handling on every `fetch` / external call
> - Check for memory leaks: event listeners added without removal, subscriptions without cleanup
> - For React: verify hooks are called unconditionally; verify `useEffect` deps are complete
> - For harmonized syntheses: verify type narrowings don't conflict across composed variants

### Python

> Additionally:
> - Check for mutable default arguments (`def foo(x=[])` is almost always a bug)
> - Check for bare `except:` clauses (catches too much)
> - Verify `async def` functions are awaited at call sites
> - Check for resource leaks: `open()` without `with`; sessions without `close()`
> - Verify type hints match runtime behavior (especially Optional vs. None)
> - For harmonized syntheses: verify `__init__` ordering preserves invariants from each composed defensive layer

### Go

> Additionally:
> - Check for ignored errors (`_, err := ...; <unused>`)
> - Verify goroutines have a clear lifecycle (cancellation context or wait group)
> - Check for `panic` instead of error return
> - Verify channel sends don't block indefinitely (unbuffered channels in error paths)
> - Check for race conditions: `go test -race` should be in the gates

---

## 8. Reading-stance variants

For when the rotation needs a different stance.

### Literal stance (variant)

> Read the recovered keepers as text. Don't infer intent. Look for:
> - Misspelled identifiers in error messages
> - Wrong constants (e.g., 1024 where 1000 was intended, or vice-versa)
> - Off-by-one in loops
> - Hardcoded paths that should be config
> - Magic numbers without named constants
>
> Do not propose architectural changes. Do not propose refactors. Just read and find textual bugs.

### Skeptical stance (variant — branch-rationalization-specific)

> The triage rubric classified these branches as `novel-and-accretive` or `novel-and-accretive-via-harmonization`. Suspend agreement.
> For each recovered keeper:
> - Find evidence the rubric was wrong: a function on canonical with similar semantics under a different name; a fix already landed via a different code path; a deprecated approach the project lead rejected (cross-reference `cass_findings.md` if present).
> - If you can't find counter-evidence, state that explicitly.
> - For evidence found, downgrade your confidence in the recovery and surface to user.

### Junior stance (variant)

> You're new to this codebase. Read the recovered keepers and the surrounding code.
> For each commit:
> - List domain terms / file paths / identifiers you don't recognize.
> - List context (linked issues, prior PRs, side discussions) you'd need to understand it.
> - Note any invariants the commit assumes but doesn't document.
> - Propose questions you'd ask in PR review.

This stance produces context for the commit message — it doesn't propose code changes.

### Expert stance (variant)

> Apply your senior-engineer judgment for {LANGUAGE}. For each recovered keeper:
> - Are the introduced patterns idiomatic for this language and this codebase's conventions?
> - Are there {LANGUAGE}-specific anti-patterns?
> - Are concurrency / safety primitives used correctly?
> - Would a code review at a senior org block this commit? On what grounds?
>
> Output: per-keeper technical assessment with severity.

### Adversarial stance (variant)

See Section 6 above (the Round 3 deepening).

### Forensic stance (variant)

> For each recovered keeper, reconstruct the developer's intent:
> - What was the original problem they were solving? (Consult `cass_findings.md` for prior-session evidence.)
> - Why was the work in a branch instead of merged?
> - Did the polished version land elsewhere on canonical?
> - What's the smallest scope that preserves the intent?
> - Propose a commit-message rewrite (if the current message can be improved).

---

## 9. Convergence detection prompt

Used between rounds to assess whether to terminate Phase 9:

> Compare the findings from the latest round to the previous round.
> - Are there findings repeated across rounds without resolution?
> - Are findings dropping in severity (round N had bugs; round N+1 has only nits)?
> - Are findings dropping in count?
> - Are harmonization-specific findings resolved (no remaining `harmonization-regression` or `harmonization-conflict`)?
> - Are cleanup-precondition findings resolved (the bundle + backup refs intact, gates green)?
>
> Decision:
> - "Terminate": last 2 rounds had only trivial findings, gates green, no harmonization or cleanup-precondition issues outstanding
> - "One more round": last round still found substantive issues
> - "Escalate": same finding appears 3+ rounds; user decision needed (per Section 2 "blocking-unresolvable")

---

## 10. Anti-Patterns in Fresh-Eyes Prompts

| Why |
|---|
| Modifying the verbatim default rotation | The prompts are calibrated; small changes break the calibration. Use augmentations (Sections 4–7) instead |
| Running all 3 rounds before any gate check | If round 1's findings break the build, rounds 2/3 are reading broken code. Run gates between rounds |
| Skipping the gates between rounds | Gates are the convergence signal. Without them, rounds repeat indefinitely |
| Multi-stance prompts in one round | One stance per round; the stance affects what's seen |
| Using fresh-eyes to fix the recovery rubric | If a finding is "this branch shouldn't have been recovered", that's a Phase 5/6 rubric issue, not a Phase 9 fix. Roll back via the bundle and re-triage |
| Skipping the harmonization-specific prompt when there are harmonized syntheses | The harmonization plan is the user-reviewed contract; verifying fidelity is the only way to know the synthesis honors it |
| Skipping the cleanup-specific prompt before Phase 10 | Phase 10 is destructive; the cleanup-specific prompt is the final precondition check. Skipping it means destroying work whose backup story isn't verified |
| Letting trivial findings extend the round count | The termination condition is "trivial-only rounds", not "zero-finding rounds". Trivial findings (typos, comment phrasing) DO terminate; substantive findings DON'T |
| Auto-fixing a `blocking-unresolvable` finding | Per Section 2: blocking-unresolvable means escalate, never auto-fix |
