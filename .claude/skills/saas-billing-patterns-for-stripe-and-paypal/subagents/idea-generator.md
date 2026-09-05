---
name: billing-idea-generator
description: Phase 11 (post-baseline) — uses /idea-wizard to surface improvement opportunities from the polished system
---

# Billing Idea Generator

For Phase 11 (post-baseline), or when the user explicitly asks for "what could we do better?". Uses `/idea-wizard` skill if available.

## When to use

- After Phase 10 ops handoff is complete and the system is operating.
- Annual review / strategic planning.
- After a tier escalation (e.g., T2 → T3 — what new features should the new tier enable?).
- When the user is between sprints and wants forward-looking ideas.

## Inputs

- The completed `.billing_workspace/` from a prior `audit-and-fix` run.
- The pattern bundles + Polish Bar status.
- Recent customer support tickets (the user provides anonymized samples).
- Recent postmortems.
- `/idea-wizard` skill if available.

## Output

`.billing_workspace/phase11_improvement_ideas.md`:

```markdown
# Improvement Ideas — Phase 11

## Tier-bump readiness
[The user is at T<N>; what would T<N+1> require? Surface the key bundles to add.]

## Feature ideas (from customer-side signal)
- Idea 1: <name>
  - Source: <X support tickets in last 90d>
  - Effort: <day-equivalents>
  - Impact: <customer-trust / revenue / operations>
  - Bundle(s) affected: <list>
  - Recommended mode: add-feature

## Reliability ideas (from postmortem / drift signals)
- Idea 1: <name>
  - Source: <postmortem class XYZ>
  - Effort: <day-equivalents>
  - Impact: <reliability dimension>
  - Bundle(s) affected: <list>

## Reporting ideas (from analytics gaps)
- Idea 1: <name>
  - Source: <observed analytics gap>
  - Effort: <day-equivalents>
  - Impact: <decision-quality>

## Polish ideas (from de-slopify / ui-polish lens)
- Idea 1: <name>
  - Source: <UX observation>
  - Effort: <hours>
  - Impact: <customer-trust>

## Priority recommendation
[Top 3 ideas with explicit reasoning; suggest next mode for each]
```

## Procedure

1. Load `/idea-wizard` if available; otherwise use the inline prompts below.
2. Read recent support-ticket sample (user provides).
3. Read postmortem index.
4. Read drift-guard CI history (recurring drift = systemic gap).
5. Read coverage-matrix gaps with score 1-2 (deferred Trivials may now be worth doing).
6. Brainstorm per category.
7. Prioritize: top 3 with explicit reasoning.

## Inline prompts (when /idea-wizard missing)

For each category, ask:

**Customer-side**: "What feature would have prevented the most-recurring support ticket class? What feature would have generated the most upsell signal in support tickets?"

**Reliability**: "Which postmortem class has the highest probability of recurrence? What detection / containment improvement would close it?"

**Reporting**: "What metric did you wish existed during the last incident / quarterly review? What slice / segment was missing?"

**Polish**: "What does the customer Portal feel clunky for? What does the dunning email look like to a customer who got it for the wrong reason?"

## Discipline

- Bias toward small wins. T3 systems can absorb feature work; T2 systems can't (focus on reliability).
- Bias toward customer-trust-building (refund-process clarity, status page, proactive comms) over engineering elegance.
- Ideas with no source signal are usually wrong; require evidence.
- Don't bury good ideas in giant lists; top 3 is the recommendation.
- Stay inside billing. Generic product, support, analytics, agent-orchestration, or CI ideas are out of scope unless the billing scope decision activates them.

## Integration

- Optional Phase 11 (post-Phase 10).
- Used in T3 / T4 quarterly planning.
- Hands off to `add-feature` mode for ideas approved for build.

## When idea-wizard is missing

Inline fallback: the `Inline prompts` above. Less structured but functional.
