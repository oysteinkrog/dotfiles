# Fresh-Eyes Prompts — Extended Library

The three calibrated prompts in PHASES.md § Phase 8 are the default rotation. This file extends them with mode-specific variants, language-specific variants, and adversarial deepenings.

The prompts are versioned. Use the version number in `fresh_eyes_log.md` so future runs can be compared.

---

## Default rotation (use verbatim)

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

## Mode-specific variants

### Quick mode — single round

For Quick mode, use a compressed single round:

> The recovery branch has just been authored. Read the new commits with fresh eyes; look for obvious bugs (typos, missing null checks, copy-paste errors), then verify tests still pass. Fix any obvious bugs in place.

### Standard mode — 2 rounds

Use Round 1 + Round 2 from the default rotation. Skip Round 3 unless any keeper touches security-sensitive code.

### Comprehensive mode — 3 rounds + triangulation

Use the full default rotation. Triangulate Round 2 across Codex + Claude. Triangulate Round 3 across Codex + Claude + Gemini.

---

## Language-specific augmentations

Append the language-specific concerns to the round prompt as additional bullets.

### Rust

> Additionally:
> - Check for `unwrap()` / `expect()` without justification — these panic in production
> - Check for `clone()` in hot paths (allocation cost)
> - Verify any new `unsafe` blocks have safety invariants documented in comments
> - Check that `?` propagation makes sense (don't swallow errors that should be handled)
> - Verify lifetime annotations are correct and minimal

### TypeScript / JavaScript

> Additionally:
> - Check for missing `await` on Promise-returning calls
> - Check for `any` types where specific types should be inferred
> - Verify error handling on every `fetch` / external call
> - Check for memory leaks: event listeners added without removal, subscriptions without cleanup
> - For React: verify hooks are called unconditionally; verify `useEffect` deps are complete

### Python

> Additionally:
> - Check for mutable default arguments (`def foo(x=[])` is almost always a bug)
> - Check for bare `except:` clauses (catches too much)
> - Verify `async def` functions are awaited at call sites
> - Check for resource leaks: `open()` without `with`; sessions without `close()`
> - Verify type hints match runtime behavior (especially Optional vs. None)

### Go

> Additionally:
> - Check for ignored errors (`_, err := ...; <unused>`)
> - Verify goroutines have a clear lifecycle (cancellation context or wait group)
> - Check for `panic` instead of error return
> - Verify channel sends don't block indefinitely (unbuffered channels in error paths)
> - Check for race conditions: `go test -race` should be in the gates

### Java

> Additionally:
> - Check for null-pointer paths
> - Verify checked exceptions are either handled or declared
> - Check for resource leaks: `try-with-resources` for closeables
> - Verify generic types are not raw

---

## Reading-stance variants

For when the rotation needs to specifically apply a different stance.

### Literal stance (variant)

> Read the recovered commits as text. Don't infer intent. Look for:
> - Misspelled identifiers in error messages
> - Wrong constants (e.g., 1024 where 1000 was intended, or vice-versa)
> - Off-by-one in loops
> - Hardcoded paths that should be config
> - Magic numbers without named constants
>
> Do not propose architectural changes. Do not propose refactors. Just read and find textual bugs.

### Skeptical stance (variant)

> The triage rubric classified these stashes as `novel-and-accretive`. Suspend agreement.
> For each recovered keeper:
> - Find evidence the rubric was wrong: a function on main with similar semantics under a different name; a fix already landed via a different code path
> - If you can't find counter-evidence, state that explicitly
> - For evidence found, downgrade your confidence in the recovery and surface to user

### Junior stance (variant)

> You're new to this codebase. Read the recovered commits and the surrounding code.
> For each commit:
> - List domain terms / file paths / identifiers you don't recognize
> - List context (linked issues, prior PRs, side discussions) you'd need to understand it
> - Note any invariants the commit assumes but doesn't document
> - Propose questions you'd ask in PR review

This stance produces context for the commit message — it doesn't propose code changes.

### Expert stance (variant)

> Apply your senior-engineer judgment for {LANGUAGE}. For each recovered commit:
> - Are the introduced patterns idiomatic for this language and this codebase's conventions?
> - Are there {LANGUAGE}-specific anti-patterns?
> - Are concurrency / safety primitives used correctly?
> - Would a code review at a senior org block this commit? On what grounds?
>
> Output: per-keeper technical assessment with severity.

### Adversarial stance (variant)

> Assume the recovered commits will ship. What could go wrong, in production?
> - Time-of-day failures (e.g., midnight UTC date math, timezone bugs)
> - Scale failures (works on 10 rows, breaks on 10 million)
> - Locale failures (works in en-US, breaks on Turkish 'I')
> - Concurrent failures (works single-threaded, races at scale)
> - Trust failures (assumes input is well-formed when it might not be)
> - Failure-mode silence (a bug that's silent in tests but visible in logs)
>
> For each risk, propose: severity (low/medium/high), mitigation (what to add), or acceptance (why it's ok).

### Forensic stance (variant)

> For each recovered keeper, reconstruct the developer's intent:
> - What was the original problem they were solving?
> - Why was the work stashed instead of completed?
> - Did the polished version land elsewhere? If so, what's different?
> - What's the smallest scope that preserves the intent?
> - Propose a commit-message rewrite (if the current message can be improved).

---

## Convergence detection prompt

Used between rounds to assess whether to terminate Phase 8:

> Compare the findings from the latest round to the previous round.
> - Are there findings repeated across rounds without resolution?
> - Are findings dropping in severity (round N had bugs; round N+1 has only nits)?
> - Are findings dropping in count?
>
> Decision:
> - "Terminate": last 2 rounds had only trivial findings, gates green
> - "One more round": last round still found substantive issues
> - "Escalate": same finding appears 3+ rounds; user decision needed

---

## Anti-Patterns in Fresh-Eyes Prompts

| ✗ | Why |
|---|-----|
| Modifying the verbatim default rotation | The prompts are calibrated; small changes break the calibration. Use augmentations instead. |
| Running all 3 rounds before any gate check | If round 1's findings break the build, rounds 2/3 are reading broken code |
| Skipping the gates between rounds | Gates are the convergence signal. Without them, rounds repeat indefinitely |
| Multi-stance prompts | One stance per round; the stance affects what's seen |
| Using fresh-eyes to fix the recovery rubric | If a finding is "this stash shouldn't have been recovered", that's a Phase 4 rubric issue, not a Phase 8 fix |
