# Commit Message Craft — Writing Phase 6 Recovery Commits

A recovery commit is a small story. It says: *what was lost, why it matters, how it was recovered, and what to know about it later*. This file is the craft guide.

---

## The contract

Every Phase 6 / Phase 7 commit message must satisfy:

1. **Subject** (first line, ≤72 chars): present-tense verb + concrete object
2. **Body**: explains the *why*, the original context, and the recovery path
3. **Citation**: stash ref, original SHA, original date, bundle diff path
4. **No `Co-Authored-By` lines** unless the user explicitly asks
5. **Convention compliance**: follows `project_profile.json:commit_message_convention` (Conventional Commits, ticket-id prefix, gitmoji, or freeform)

---

## Subject line patterns

The subject names the unit of recovered work, not the source of recovery. "recover safe_div fn from WIP" is better than "apply stash@{34}".

| Pattern | Example |
|---------|---------|
| `recover <thing> from <where>` | `recover defensive MySQL OK-packet length-cap from WIP stash` |
| `restore <thing> ahead of <event>` | `restore parser fuzz corpus ahead of v1.2 release` |
| `reapply <thing> after <reason>` | `reapply migration retry-loop after refactor superseded the original` |
| `recover novel hunks from partial stash@{N}` (split-apply) | `recover novel test_overflow case from partial stash` |

For Conventional Commits projects, use the appropriate type:
- `feat: ` — new functionality recovered
- `fix: ` — bug fix recovered
- `test: ` — test-only recovery
- `perf: ` — performance improvement recovered
- `refactor: ` — refactor recovered (rare; usually superseded)
- `chore: ` — maintenance / config recovery

For ticket-id projects, prefix with the ticket the original stash referenced (if any):
- `BACK-1742: recover defensive OK-packet length-cap from WIP`

---

## Body structure

The body has three required sections (separated by blank lines), in order:

### Section 1: Context

```
Originally drafted in stash@{34} (sha 8a3d2c9, dated 2026-04-29).
The fail-closed guard caps OK-packet payload length to MAX_PAYLOAD before
the consumer reads it; without the cap, a malformed packet from an upstream
proxy could trigger a panic in the framing parser.
```

State the source (stash + sha + date) and the *why this matters* (the problem the change solves) in 2–4 sentences.

### Section 2: Why it didn't already land

```
The polished version of this stash never landed because the agent that
authored it crashed before pushing. The defensive guard is genuinely useful;
the rest of the agent's work (mostly trace-logging) was redundant with what
landed via PR #234.
```

This section is what makes a recovery commit different from a regular feat: commit. It explains *why* this was unfinished work and *why now* is the right time to recover it.

If the original was abandoned for a reason: surface that reason. The user reviewing the recovery PR shouldn't have to guess.

### Section 3: How it was recovered

```
Recovered via: git apply --3way <bundle>/diffs/034.diff
(with manual resolution for the `if/else if` → `match` refactor on main)

Hunks: 2 of 2 applied; no superseded hunks.
Tests: cargo test --workspace passed; cargo clippy clean.
```

State the recovery mechanism (`git apply --3way` vs. `git cherry-pick -m 1 refs/stash-backup/*` vs. manual port). Note any conflict resolution. State which hunks made it (relevant for split-apply).

---

## Full example (asupersync stash@{34})

```
recover defensive MySQL OK-packet length-cap from stashed WIP

Originally drafted in stash@{34} (sha 8a3d2c9, dated 2026-04-29).
The fail-closed guard caps OK-packet payload length to MAX_PAYLOAD before
the consumer reads it; without the cap, a malformed packet from an upstream
proxy could trigger a panic in the framing parser.

The polished version of this stash never landed because the agent that
authored it crashed before pushing. The defensive guard is genuinely useful
on its own; the rest of the agent's work was superseded by PR #234.

The original stash predated the if/else if → match refactor on main; this
commit preserves the stash's intent (the length cap and fail-closed test)
inside main's current match-expression structure. Manual resolution applied
via the Edit tool; no sed/awk transformations.

Recovered via: git apply --3way <bundle>/diffs/034.diff
Hunks: 2 of 2 applied. Tests: cargo test --workspace passed.
```

That's 13 lines, ~150 words. Stand-alone readable. Future-you reading the git log will know exactly what happened and why.

---

## What NOT to write

| ✗ | Why |
|---|-----|
| `apply stash@{34}` | Reader has no idea what this changes |
| `WIP recovery` | Same problem; "WIP" is invisible after merge |
| `recover stash content` | Generic; says nothing |
| `Recovered via stash janitor` | The tool is irrelevant; the change is what matters |
| Co-Authored-By: Claude <noreply@anthropic.com> (without user request) | Many projects have specific commit-style policies; don't add trailers proactively |
| Multi-paragraph philosophical preamble | Body should be 100–200 words, not 800 |

---

## Special cases

### Split-apply commits (Phase 7)

Add a per-hunk audit trail in the body:

```
recover novel parser_fuzz_corpus from partial stash@{47}

Originally stash@{47} mixed a parser refactor (now landed via PR #234)
with new fuzz corpus entries. This commit recovers only the corpus entries;
the refactor portion was dropped as superseded.

Hunks recovered: 3 of 8 (see <bundle>/diffs/047.split.diff for the
filtered diff). Hunks dropped: 1, 2, 5, 6, 7 (parser refactor; superseded
by main:src/parser.rs:120). Hunks kept: 3 (test_parser_v2_overflow), 4
(corpus entries 1-100), 8 (corpus entries 101-200).

Recovered via: split copy of <bundle>/diffs/047.diff with superseded
hunks removed; verified clean via git apply --3way --check.
```

### Conflict-resolved commits (Phase 6 with manual port)

Note the conflict and the resolution philosophy:

```
recover defensive guard ported through main's refactor

Originally stash@{34}'s diff modifies an `if let Ok(payload_len) = ...`
block at src/mysql/protocol.rs:218. On main today, that block has been
refactored into a `match buf[4] { ... }` expression at the same path.

The 3-way apply could have produced syntactically broken code (an `if let`
inside a match arm). Instead, the stash's *intent* (the length cap) was
ported into main's `match` arm for OK_BYTE via the Edit tool.

Recovered via: manual resolution; see <workspace>/conflicts/stash_034.context.md
for the full surface diff. Tests: cargo test --workspace passed; cargo
clippy --workspace -- -D warnings clean.
```

The "intent vs. surface form" framing is a useful lens. The stash's surface form may be obsolete; its intent often isn't.

### Bug-fix recovery

When the recovered content is fixing a bug:

```
fix: recover null-pointer guard in webhook signature verification

Originally stash@{12} (sha def4567, dated 2026-04-22). Discovered while
investigating a 500 from /api/webhooks: an unverified signature can be
empty bytes, which crashes `verifyHmac()` because it doesn't null-check.

The polished version of this fix landed in PR #198, but only for Stripe;
PayPal's verifier wasn't patched. This commit applies the same guard to
PayPal's path.

Recovered via: git apply --3way <bundle>/diffs/012.diff (clean apply).
Hunks: 1 of 1. Tests: pnpm test:webhooks passed.
```

The "x had it but y didn't" pattern is common — agents often patch one path and stash the analogous fix for the other.

---

## How to author the message

1. **Re-read the diff.** What identifiers does it introduce? What problem do they solve?
2. **Check the stash message.** Is it a ticket id (`BACK-1742`)? Use that as the prefix or in the body.
3. **Check the date.** Is the stash old? Note that the original work predates a refactor, etc.
4. **Check `apply_log.tsv:pre_apply_drift`.** Did the apply require manual conflict resolution? Note it.
5. **Check related beads issues.** `br show <ticket-id>` may have context worth quoting.
6. **Draft.** First pass: 3 sections, ~150 words.
7. **Tighten.** Remove redundancy with the diff. The diff shows *what*; the message says *why*.
8. **Verify.** Does the message stand alone? Could a reader on PR review six months from now make sense of it without context from this run?

---

## The skill's enforcement

The Phase 6 commit-message-author subagent reads:
- The diff
- The stash metadata
- `project_profile.json:commit_message_convention`
- Any beads issue linked from the stash message
- `apply_log.tsv:pre_apply_drift` (whether there was manual conflict resolution)

And produces a message conforming to the contract. The message is then `git commit --amend` applied (the only `--amend` use in this skill, and only on the recovery branch's tip while not yet pushed).

For Comprehensive runs, a triangulator subagent reviews the message:
- Does it explain the *why*?
- Is the citation complete?
- Does it follow the project's commit-message convention?

If any check fails, regenerate.
