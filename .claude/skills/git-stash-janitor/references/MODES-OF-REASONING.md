# Modes of Reasoning — Reading Stances for Triage and Review

A *mode of reasoning* is a deliberate reading stance the agent adopts. Same diff, same bundle, different lens. Modes are composable with each other and with the operator library.

Adapted from documentation-website's "literal/skeptical/junior/expert/adversarial" modes.

---

## Why modes matter

The same triage worker, given the same stash, can produce wildly different verdicts depending on what it's *looking for*. The rubric provides the procedure; the reading stance provides the prior. Combining well-defined modes with the rubric improves verdict quality without adding new agents.

For Phase 4 (triage), the default mode is **Literal + Forensic**. For Phase 8 (fresh-eyes), the rounds use **Literal → Forensic → Adversarial** in sequence.

---

## Mode 1 — LITERAL

**Definition:** Read the diff as a textual pattern. Don't interpret intent. Don't speculate about what the developer wanted.

**Triggers:**
- Phase 4 default for high-fingerprint-coverage rows (the rubric is enough)
- Phase 8 round 1 ("read what's there, look for obvious bugs")

**Reading prompt template:**
```
[MODE: Literal]

Read the diff at {DIFF_PATH}. Do not infer intent. Answer ONLY:

1. What identifiers (functions, types, tests) are introduced (in `+` lines NOT
   matched by a `-` line)?
2. What identifiers are removed (in `-` lines NOT matched by a `+` line)?
3. What files are touched? Which are new?
4. Is the diff binary-only, whitespace-only, or comment-only?

Output the answers in the fingerprint JSON format. No prose. No interpretation.
```

**Strengths:** fast, deterministic, low false-positive rate.

**Weaknesses:** misses semantic equivalence (rename, refactor); misses architecture-level "is this still the right approach" questions.

---

## Mode 2 — SKEPTICAL

**Definition:** Assume the rubric's classification is wrong. What evidence would prove it wrong?

**Triggers:**
- Phase 4 for rows with confidence ≥ 0.85 (sanity-check the high-confidence verdicts)
- Phase 5 borderline review
- Phase 8 round 2 of Comprehensive mode

**Reading prompt template:**
```
[MODE: Skeptical]

The rubric classified stash@{N} as {VERDICT} with confidence {CONF}.
Suspend agreement. Find evidence that this verdict is wrong.

Specifically:
1. If 'superseded': can you find a fingerprint symbol that's NOT on main with
   the same signature?
2. If 'novel-and-accretive': can you find a function on main with similar
   semantics that supersedes this in spirit even if not in name?
3. If 'garbage': can you find ANY hunk that adds defensive code, a bug fix,
   or a test that the polished version missed?
4. If 'novel-but-stale': could the stash's intent be ported to current main,
   even if the surface form is unportable?

Output: counter-evidence, OR confirmation that the verdict holds.
```

**Strengths:** catches mis-classifications the rubric misses; especially good at finding `superseded` rows that are actually `partially-novel`.

**Weaknesses:** can produce paranoid "what if?" findings that aren't actionable. Pair with a decision-rule (e.g., "if counter-evidence exists, downgrade confidence by 0.10").

---

## Mode 3 — JUNIOR

**Definition:** Read as if you're new to this codebase. What would you NOT understand about this diff?

**Triggers:**
- Phase 6 conflict resolution (catches assumed context)
- Phase 7 split-apply review
- Phase 10 handoff report draft (does the report stand alone?)

**Reading prompt template:**
```
[MODE: Junior]

You're a developer new to this codebase. Read the proposed conflict resolution
at {PATH}. Answer:

1. What identifiers, file paths, or domain terms do you NOT recognize?
2. What context (linked tickets, prior PRs, side-channel discussions) would you
   need to understand WHY this resolution is correct?
3. What invariants does the resolution rely on? Are they documented?
4. If you were reviewing this PR, what questions would you ask?

Output: list of unmet context needs.
```

**Strengths:** surfaces invisible knowledge; catches resolutions that "make sense to the agent who wrote them" but aren't reproducible.

**Weaknesses:** can be over-cautious. Use the output to *augment* the commit message and PR description, not to block the apply.

---

## Mode 4 — EXPERT

**Definition:** Read with deep language and architecture knowledge. What language-specific idioms does this introduce or violate?

**Triggers:**
- Phase 6 commit message authoring
- Phase 8 round 1 ("look for obvious bugs the project's idioms would catch")
- Per-language fingerprinting (when the worker is a language-specialist subagent)

**Reading prompt template:**
```
[MODE: Expert in {LANGUAGE}]

Read the diff at {DIFF_PATH}. As a senior {LANGUAGE} engineer, answer:

1. Are the introduced symbols idiomatic for this language? (e.g., Rust: are
   `Result` returns used appropriately? Is `unwrap()` justified? Are lifetimes
   explicit only when necessary?)
2. Are there language-specific anti-patterns? (e.g., TS: missing `await` on a
   Promise; Python: mutable default argument; Go: ignored errors)
3. Are concurrency / safety primitives used correctly?
4. Are there test patterns the project uses that this diff fails to follow?

Output: per-hunk technical assessment.
```

**Strengths:** catches issues the rubric's textual fingerprinting misses entirely.

**Weaknesses:** opinion-heavy; pair with project-specific style guide if available.

---

## Mode 5 — ADVERSARIAL

**Definition:** What could go wrong if this stash were applied? Compounding errors? Hidden dependencies? Latent invariant violations?

**Triggers:**
- Phase 8 round 2 default (Standard mode)
- Phase 8 round 3 (Comprehensive mode)
- Pre-Phase-9 final sanity check before destructive cleanup

**Reading prompt template:**
```
[MODE: Adversarial]

Assume this stash will be applied. What could go wrong, in production?

Specifically:
1. Does the introduced code have a failure mode that's silent in tests but
   visible in production? (rate limits, time-of-day, scale, locale, network)
2. Does it introduce a security surface? (input parsing, auth bypass, untrusted
   data, deserialization)
3. Does it interact with concurrent code in non-obvious ways?
4. Does it have a hidden dependency on a config or env var that's not
   documented?
5. If this code crashed at 3am on a Sunday, what would the on-call see in
   the logs?

Output: ranked list of risks with severity (low/medium/high) and mitigation.
```

**Strengths:** catches issues that pass tests but break in production.

**Weaknesses:** generates work — every risk needs triage. Use the output to gate Phase 9 (don't drop until risks are resolved or accepted).

---

## Mode 6 — FORENSIC

**Definition:** Reconstruct the developer's intent from the diff and surrounding context (reflog, commit history, message). What were they trying to accomplish?

**Triggers:**
- Phase 4 for novel-but-stale rows (decide whether to rewrite vs. drop)
- Phase 6 commit message authoring (the why is forensic)
- Phase 8 round 2 of Comprehensive mode

**Reading prompt template:**
```
[MODE: Forensic]

Reconstruct the developer's intent from these artifacts:

- Stash diff: {DIFF_PATH}
- Stash message: "{MESSAGE}"
- Stash date: {DATE}
- Author: {AUTHOR}
- Stash parent SHA: {PARENT_SHA}; reachable from: {git log --oneline --all --contains {PARENT_SHA} | head -3}
- Surrounding commits on the parent's branch (±1 week): {git log --since=... --until=...}
- Linked beads issue (if message contains a ticket id): {br show <id>}

Answer:
1. What was the developer trying to accomplish?
2. Why was it stashed instead of committed?
3. Did the work continue elsewhere (a polished landing) or get abandoned?
4. If kept, what's the smallest scope that preserves the intent?
5. What's the proposed commit message (with `Recovers <intent> from stash@{N}; original drafted on <date>; supersedes nothing | superseded by commit <sha>`)?

Output: forensic report with intent + recommended action.
```

**Strengths:** turns ambiguous diffs into actionable decisions; produces high-quality commit messages.

**Weaknesses:** time-consuming. Use only on novel-but-stale and partially-novel rows.

---

## Mode 7 — TIMELINE

**Definition:** Reconstruct the sequence of operations that produced this stash. Use reflog, branch history, and the bundle's index.

**Triggers:**
- Stashes with unreachable parents
- Stashes from deleted branches
- Stashes that postdate a force-push (origin history rewritten)

**Reading prompt template:**
```
[MODE: Timeline]

Reconstruct the timeline for stash@{N}.

Inputs:
- Bundle meta: {BUNDLE}/meta/{NPAD}.txt (sha, parent, date, author)
- git reflog --all  (full reflog)
- git log --all --reflog --oneline | head -200  (commits including unreachable)
- branches that ever pointed at the parent: git branch --contains {PARENT_SHA}

Output a timeline:
1. T-N: branch {X} created at {sha}
2. T-(N-1): developer made changes (visible in stash diff)
3. T-(N-2): developer ran `git stash` (this is when the stash commit was made)
4. T-(N-3): branch {X} was deleted | rebased | merged
5. T-now: stash is in the list with parent unreachable

This timeline informs whether the stash is recoverable, whether its content is
already represented elsewhere, and whether dropping it loses history.
```

**Strengths:** invaluable for novel-but-stale rows where you can't tell if the work was abandoned or moved.

**Weaknesses:** requires repo with healthy reflog; older stashes may have parents that fell out of reflog (default 90-day expiry).

---

## Composition Rules

| Phase | Default mode | Best alternates |
|-------|--------------|-----------------|
| 1 (profile) | Literal + Expert | — |
| 2 (inventory) | Literal | — |
| 3 (bundle) | Literal (verification is the gate) | — |
| 4 (triage) | Literal + Forensic | Skeptical for high-confidence rows; Expert for language-heavy diffs |
| 5 (merge) | Literal | Skeptical (sanity-check rubric) |
| 6 (apply) | Expert + Adversarial | Junior (for conflict resolutions) |
| 7 (split) | Forensic + Expert | — |
| 8 round 1 | Literal | — |
| 8 round 2 | Forensic | Adversarial for Comprehensive |
| 8 round 3 | Adversarial | Skeptical for max paranoia |
| 9 (cleanup) | Literal (verbatim authorization) | — |
| 10 (handoff) | Junior (does the report stand alone?) | — |
| 11 (user-lens) | Forensic + Adversarial | — |

The mode is **named** in the agent prompt (e.g., `[MODE: Adversarial]`). Different modes can be composed in the same session — the mode tag tells future readers what stance produced which finding.

---

## Anti-Patterns in Mode Selection

| ✗ | Why |
|---|-----|
| Always running Adversarial in Phase 4 | Generates noise; rubric is sufficient for high-confidence rows |
| Skipping Forensic on novel-but-stale | The verdict requires intent-reconstruction — Forensic is the rubric |
| Using Junior for conflict-resolution review | Right tool, wrong direction — Junior surfaces context needs, doesn't propose resolutions |
| Mixing modes mid-prompt | One stance per prompt; switch by tag |
| Not naming the mode in the prompt | Future readers can't tell why a finding has a particular shape |
