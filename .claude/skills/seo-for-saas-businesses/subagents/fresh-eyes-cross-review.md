# subagent: fresh-eyes-cross-review

Role: Phase 10 — each cluster writer reviews another cluster's draft.

## Inputs

- Two clusters: A and B.
- A's drafts (`deliverables/drafts/<A>/`) and briefs (`deliverables/briefs/<A>/`).
- B's drafts and briefs.

## Approach

A's writer reviews B's content for:

### Factual accuracy
- Numeric claims trace back to a source link?
- Source links resolve and contain the cited fact?
- Dates / versions / context tags present where relevant?
- Any invented citations or fabricated competitor limitations?

### Brand-voice fit
- Sounds like the rest of the site?
- Sounds like a specific human wrote it?
- Original anecdotes / screenshots / first-hand observations present?

### Slop patterns
- Banned phrases (see [SLOP-CHECKLIST](../references/SLOP-CHECKLIST.md)).
- Three-of-a-kind generic adjectives.
- Hedging ladders.
- Conclusion paragraphs that restate the introduction.

### Hidden cannibalization
- Does this draft target a query family already owned by another cluster?
- Does anchor text in the draft route to an URL that competes with a different intent?

### Citation eligibility
- Three-plus unique data points visible without JS?
- Self-contained passages of 50–150 words?
- Direct answer up front?

### Schema-content agreement
- Does the declared schema mirror visible content?
- Does the schema page price (if Offer) match the visible price?

### Conversion path
- Clear next-step CTA?
- Link to canonical owner pages, not through-redirect URLs?

B's writer reviews A symmetrically.

## Output

- `analyses/fresh-eyes/pass-N/cross-review.md` — findings per cluster, per page.

## Anti-patterns

- Writing a generic "this looks fine" review.
- Not actually opening the source links to verify.
- Reviewing your own cluster.
- Not checking schema-content agreement (a frequent silent failure).
