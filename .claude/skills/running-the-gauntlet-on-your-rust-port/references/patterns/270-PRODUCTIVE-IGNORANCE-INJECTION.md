# 270-PRODUCTIVE-IGNORANCE-INJECTION

**Family:** Convergence + Orchestration. Glyph: `⊚` (per [`OPERATORS.md § Deep Review Operator Inheritance`](../methodology/OPERATORS.md); named distinctly from the existing `⊙ Debounce-False-Positive` glyph).

**When to apply:**
- The swarm has reached "consensus collapse" (every fresh-eyes reviewer / triangulator returns the same conclusion for 2+ rounds).
- A specific question has only 1-2 candidate hypotheses (the swarm is anchored to a small hypothesis space).
- A productively-ignorant pane hasn't been dispatched in the last 5 rounds (review pathology "Productive-ignorance starvation").
- Phase 14 T3+ when triangulation produces full-agreement on every finding (no disagreement signal — likely all panes reading the same context).

## The pattern

Deliberately spawn ONE pane with **minimal onboarding**:

```bash
# Standard onboarding (everyone gets this):
ntm send "$session" --pane $N --file MO-onboarding.md
# Then pane absorbs:
#   - The gauntlet workspace MEMORY.md
#   - The current round's synthesizer report
#   - The negative-ledger preamble
#   - The prior round's findings
#   - The phase-specific subagent instructions

# Productive-ignorance variant (one pane only; once every 5 rounds):
ntm send "$session" --pane $N --file MO-productive-ignorance.md
# Then pane gets ONLY:
#   - The project's spec sources (docs/spec/v1/*.md OR AGENTS.md "Hard Requirements")
#   - The immediate question (one paragraph)
#   - The current code (read-only, no annotations)
# Explicitly excluded:
#   - The negative ledger (so it doesn't inherit prior rejections)
#   - The synthesizer report (so it doesn't inherit prior framing)
#   - Other panes' work (so it doesn't echo)
```

The pane's marching order (`assets/ntm-marching-orders/MO-productive-ignorance.md`) contains:

> *Read minimally and reason from first principles. Do not let yourself be primed by what other panes have concluded. If your analysis disagrees with consensus, that disagreement IS the value you're producing. Treat your assigned question as if you'd never seen anyone else's reasoning about it.*

## Variants

### Per-trigger variant

- **Consensus-collapse trigger** — one ⊚ pane per round until disagreement signal returns.
- **Small-hypothesis-space trigger** — one ⊚ pane, focused specifically on "what hypothesis would I generate from spec + code alone, ignoring the existing N candidates?"
- **Periodic refresh trigger** — every 5 rounds, dispatch one ⊚ pane as preventive maintenance against in-phase drift.

### Per-lane variant

cc_1 (conformance) and cc_3 (surface) get ⊚ panes most often (most prone to consensus collapse on edge-case bugs). cc_2 (perf) less so (perf is more about measurable hotspot attribution, less about reasoning).

## Failure modes

- **Onboarding-creep** — someone adds "just one document" to the ⊚ pane's reading list because "they need context for X". DENY. The friction is the point; primed panes don't deliver disagreement signal.
- **The ignorant pane requesting full context** — pane reads its marching order, sees "no synthesizer report", and asks the orchestrator for one. DENY (with explanation). Direct it to first-principles reasoning.
- **Treating disagreement as "the ignorant pane is wrong"** — disagreement IS the value; investigate the disagreement, don't dismiss it. The whole point is the ignorant pane sees something everyone else missed.
- **Productive-ignorance every round** — defeats the purpose (the ignorant pane becomes the new consensus). Cap at one ⊚ pane per 5 rounds in routine mode; one per round during active stall.
- **Using ⊚ for routine work** — it's expensive (the pane often misses obvious things). Reserve for moments when consensus is suspicious.
- **Mis-applying to cc_2 (perf)** — perf has objective signal (profile counters); first-principles reasoning rarely helps. Stay in cc_1 / cc_3 for ⊚.

## Concrete example

**Round 6 of a gauntlet on a SQL-class port.** Every fresh-eyes pane has reported the same root cause for a PRAGMA divergence: *"the dispatch table is missing entry X"*. Three triangulation panes all agree. Devil's-advocate pane agrees. Consensus collapse.

**Productive-ignorance pane dispatched.** Onboarding: SQL spec (sqlite-version-3.52.0-spec.md), the failing test file, AGENTS.md. NO synthesizer report. NO ledger.

**Pane's report (lifted)**:
> *"I read the failing test and the SQL spec. The dispatch table check seems plausible, but I notice the test fixture uses `PRAGMA fk_check` — the underscore form. The reference accepts both `fk_check` and `fk-check` per spec § 4.2. Your `normalize_pragma_name()` in src/normalize.rs:34 strips both forms, but I see the dispatch table at src/dispatch.rs:101 only registers the underscore form. So either the canonicalization is wrong OR the dispatch table is right but incomplete. I'd test by trying the dash form — if it passes, the bug is in canonicalization, not dispatch."*

The wider-net finding the prior consensus missed: the bug is in canonicalization, not dispatch.

## Cross-references

- [`methodology/DEEP-HYPOTHESIS-REVIEW.md § 2 Review Operator Algebra`](../methodology/DEEP-HYPOTHESIS-REVIEW.md) — `⊚` operator.
- [`methodology/OPERATORS.md § ⊚ Productive-Ignorance`](../methodology/OPERATORS.md) — full operator card.
- [`pattern:265-DEEP-HYPOTHESIS-ESCALATION-TRIGGER`](265-DEEP-HYPOTHESIS-ESCALATION-TRIGGER.md) — when escalation invokes ⊚ panes.
- [`subagents/deep-hypothesis-reviewer.md`](../../subagents/deep-hypothesis-reviewer.md) — review pipeline that uses ⊚ panes.
- [`orchestration/AGENT-FUNGIBILITY.md`](../orchestration/AGENT-FUNGIBILITY.md) — pane fungibility doctrine.
- [`assets/ntm-marching-orders/`](../../assets/ntm-marching-orders/) — where MO-productive-ignorance.md template lives (to be authored separately; not yet shipped).
