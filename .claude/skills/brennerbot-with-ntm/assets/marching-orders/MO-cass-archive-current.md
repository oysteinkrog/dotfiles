# MO-cass-archive-current.md — Tag Current Session for Future cass Mining

**Phase:** 8 (post-freeze) or 10 (post-drift)
**Operators activated:** none (operational discipline)
**Parameters:** `<SESSION_ID>`, `<WORKSPACE_PATH>`, `<SKILL_SCRIPTS>`, `<ARCHETYPE>` (per QUESTION-ARCHETYPES.md), `<TIER>` (T1-T5), `<VERDICT>` (the session's main finding, ≤2 sentences)

---

After Phase 8 freeze (or Phase 10 drift completion), produce a cass-friendly summary so future sessions can find this work via cass mining.

`cass` indexes everything automatically, but a deliberate summary makes the session more discoverable. Without it, future cass queries find raw chat content; with it, they find a curated summary.

---

**Step 1 — Read session artifacts.**

```bash
cat <WORKSPACE_PATH>/intake/question_of_record.md
cat <WORKSPACE_PATH>/deliverables/HANDBACK.md
cat <WORKSPACE_PATH>/deliverables/DRIFT-CHECK.md 2>/dev/null
br list --label=hypothesis --json | jq '.issues[]? | {id, state: (((.description // "") | capture("state: (?<state>\\w+)")? | .state) // "unknown")}'
```

**Step 2 — Write cass-summary.md.**

Save to `<WORKSPACE_PATH>/cass-summary.md`. Format optimized for cass-search hits:

```markdown
# brennerbot session summary — <SESSION_ID>

**Date:** <YYYY-MM-DD>
**Archetype:** <ARCHETYPE> (per QUESTION-ARCHETYPES.md)
**Tier:** <TIER>
**Wall time:** <H>h

## TL;DR

<VERDICT — 2 sentences>

## Question of record

<one-sentence question>

## Hypotheses tested

- H-001: <claim summary> — <state>
- H-002: <claim summary> — <state>
- H-003 (third-alternative): <claim summary> — <state>
...

## Load-bearing evidence

- EV-NNN: <verbatim quote> (source: <S-NNN>:§<N>)
- EV-NNN: <verbatim quote> (source: <S-NNN>:§<N>)
(top 3-5 EVs only)

## Operators applied

(Cite which of the 15 fired; useful for cass mining "sessions where ⊕ Cross-Domain was applied to <topic>")
- ◊ Paradox-Hunt: <one-line how>
- ⊘ Level-Split: <how>
- (etc — only the operators that fired)

## Disagreements registered

- D-001: <subject> (between cc and cod readings)
- D-002: ...

## Drift verdict

<convergent | divergent-improvement | divergent-regression | mixed>

## Open threads

- H-NNN (state: deferred): <next-action>
- AF-NNN (severity: medium): <recommendation>

## Keywords for cass-search

archetype:<ARCHETYPE>
tier:<TIER>
domain:<one-or-two-domain-keywords>
verdict:<convergent | mixed>
operators:<comma-separated glyphs that fired>
key-claim:<one-line load-bearing claim>
key-counter:<one-line load-bearing counter-claim if any>

## Lineage

- Spawned from: <prior session id if applicable>
- Resumes: <prior RESUME.md if applicable>
- Recommended next session: <link or reframe>

## Resume

To resume this session:
  <SKILL_SCRIPTS>/resume-session.sh --resume <WORKSPACE_PATH>/deliverables/RESUME.md

To launch a follow-up session on the deferred H or open audit findings, see deliverables/HANDBACK.md § Recommended next loop.

---

This summary is intended to be cass-discoverable. Future brennerbot sessions investigating similar archetypes / domains / questions may surface this as a prior session via subagents/cass-miner.md.
```

**Step 3 — Commit.**

```bash
cd <WORKSPACE_PATH>
git add cass-summary.md
git commit -m "Add cass-discoverable summary for <SESSION_ID>"
```

**Step 4 — Verify discoverability.**

If `cass` is configured locally:

```bash
cass search "<one keyword from this session's domain>" --robot --limit 5
```

Confirm the new summary appears in results within ~5 min (cass indexing latency).

If cass not configured, skip verification but the file is still readable.

---

**Anti-patterns:**

- ✗ Skip the keyword tags — future cass queries can't find by archetype/tier/operator
- ✗ Make the summary too long (>2 pages) — cass excerpts will be unrepresentative
- ✗ Include the entire HANDBACK as summary — cass already indexes HANDBACK; the summary should be *more curated*
- ✗ Forget to commit — file exists locally but cass indexer may not pick up uncommitted files

**Ship-or-Surface SLA:** within 15 min, summary written + committed.

---

## When to skip

- T1 sessions on questions unlikely to recur (low cass-mining payoff)
- Sessions whose verdict was already covered in prior sessions (would clutter cass index)
- Sessions where the user explicitly asked for privacy (don't archive)

In all other cases, archive. Cross-session learning compounds — see CROSS-SESSION-LEARNING.md.
