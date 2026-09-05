# KB Feedback Loop — Tickets → Articles → Deflection

The single highest-leverage activity in support is converting recurring tickets into self-serve content. This file describes the closed loop: tickets generate signals → signals become articles → articles deflect tickets → measure the deflection.

## The Loop

```
   ┌────────────────┐
   │   Tickets      │ ──────► [Pattern detection] ──────► [Article gap]
   └────────────────┘                                            │
         ▲                                                       ▼
         │                                                  [Article draft]
         │                                                       │
         │                                                       ▼
         │                                                 [Owner review]
         │                                                       │
         │                                                       ▼
         │                                                  [Publish + link]
         │                                                       │
         │                                                       ▼
         └─────[Article cited in replies / found via search]─────┘
                              │
                              ▼
                       [Deflection metrics]
```

## Stage 1: Pattern Detection

A ticket pattern emerges when:

| Signal | Threshold | Source |
|---|---|---|
| Same root cause | 3+ tickets in 30 days | Manual tagging or LLM clustering |
| Same KB-search term with 0 results | 5+ in 14 days | KB search analytics |
| Same in-app error code | 5+ tickets | Error tracking + ticket cross-reference |
| Top-N category trending up | 2x baseline 2 weeks | Category dashboards |

Use a `kb-gap` bead label per pattern. When the bead reaches threshold, promote to "needs article."

## Stage 2: Article Drafting

The agent who triaged a representative ticket drafts the article. **They saw the user's actual question, error, and confusion** — they're best positioned.

Drafting checklist (from `KNOWLEDGE-BASE.md` Tier-2 recipe shape):
- Title: "How to <verb> <noun>" using the customer's word
- Goal (1 sentence)
- Prerequisites (bulleted)
- Steps (numbered, with screenshots/CLI)
- How to verify it worked
- Common errors + fixes
- Related: 1-2 adjacent recipes

Draft turnaround target: 2 days from "needs article" trigger to first draft.

## Stage 3: Owner Review

Owner reviews:
- Accuracy against current code/UX
- Voice match (`08-voice.md`)
- Searchable-title check
- Screenshots / CLI blocks present
- Tagged for the search index

Approve, edit, or reject. If rejected, the bead returns to "draft" with comments.

## Stage 4: Publish + Link

When published:
- Article goes live in the KB.
- Reply templates that addressed this gap are updated to link the new article.
- The original tickets get a comment: "We've published an article that addresses this: <link>" — closes the loop with the customers who first surfaced the gap.
- The bead is marked resolved with the article URL.

## Stage 5: Deflection Measurement

For 30 days after publish:

| Metric | Target | Read |
|---|---|---|
| Article views | >100 in 30 days | Is it indexed / discoverable? |
| Ticket volume on the same root cause | ↓ 30%+ vs prior 30 days | Is it deflecting? |
| "Was this helpful?" thumbs-up rate | >70% | Is it answering the question? |
| Cite rate in subsequent replies | Consistent | Are agents using it? |

If after 30 days there's no measurable deflection:
- The article isn't being found → search/SEO problem
- The article doesn't answer the actual question → revise
- The pattern was overstated → archive

## Reverse Loop: Article → Ticket

A KB article can also create tickets:
- "I followed your article and step 4 didn't work"
- "Your article says X but the UI shows Y"

These are gold. They surface stale articles AND product/UX issues. Tag them `kb-feedback` and route to:
- KB editor (article fix)
- Eng (if it's a real bug)
- Product (if step 4 is genuinely confusing)

## LLM-Powered Pattern Detection

If the project has analytics infrastructure:

```sql
-- Cluster tickets by embedding similarity
SELECT
  cluster_id,
  COUNT(*) AS ticket_count,
  array_agg(subject) AS sample_subjects
FROM tickets
LEFT JOIN ticket_embeddings USING (id)
GROUP BY cluster_id
HAVING COUNT(*) >= 3
   AND MAX(created_at) > NOW() - INTERVAL '30 days'
ORDER BY ticket_count DESC;
```

For each cluster: read 3-5 representative tickets, decide if a KB article would deflect, mint a `kb-gap` bead.

LLM prompt for clustering audit:

```
You are reviewing recent support tickets to find KB-article opportunities.

INPUT: <list of 20-50 ticket subjects + first message snippets>

TASK: Group these into clusters of related issues. For each cluster:
1. Name the cluster (the underlying user need)
2. Estimate how many tickets fall into the cluster
3. Suggest a 1-line article title in user-facing language
4. Note if the cluster represents a product issue (vs a docs gap)

Return JSON.
```

Output ranks article candidates by frequency.

## Search-Log Mining

The KB search log is the most underused signal in support. Weekly:

1. Pull last-7-day search queries with 0 results.
2. For each: is there an article that *should* match this query? If yes, the article needs better titling/tags. If no, it's a gap.
3. Of the gaps, prioritize by frequency.

```sql
SELECT query, COUNT(*) AS searches, ARRAY_AGG(DISTINCT user_id) AS distinct_users
FROM kb_search_log
WHERE result_count = 0
  AND ts > NOW() - INTERVAL '7 days'
GROUP BY query
HAVING COUNT(*) >= 3
ORDER BY searches DESC;
```

A query with 0 results AND ≥3 distinct users = a top priority gap.

## Article Decay Detection

Articles rot. Detect:

| Signal | Action |
|---|---|
| "Was this helpful?" thumbs-down spike | Re-read the article against current product |
| `kb-feedback` tickets citing the article | Edit the article in same week |
| Article last-updated > 6 months AND >100 views | Audit |
| Article cites a deprecated feature/API | Update or redirect |

## Linking To Tickets

In every reply that pastes a KB link, log it:

```typescript
await db.insert(ticket_kb_citations).values({
  ticket_id,
  article_id,
  cited_at: new Date(),
});
```

Reports:
- Most-cited articles per week → these need extra love.
- Articles cited in tickets but with a poor "helpful" rate → revisit.
- Tickets citing 3+ articles before resolution → too fragmented; needs a single combined article.

## Anti-Patterns

| Don't | Why |
|---|---|
| Wait for "we have time" to write articles | The ticket spike is now; time matters |
| Have engineers write articles solo | They miss the customer's mental model |
| Skip the cite-back to original tickets | Customers don't see closure; the loop never closes for them |
| Measure articles by views only | Views without deflection ≠ value |
| Let articles age without audit | Stale > missing |
| Block on owner review for >5 days | Backlog grows; agents stop drafting |
| Give the article a "perfect" title at the cost of searchability | Use the customer's word |

## Cadence

| Action | Frequency |
|---|---|
| Pattern-detection sweep | Weekly |
| 0-result search-log review | Weekly |
| Article publishes (target) | 2-3 / week early; 1 / week steady-state |
| Article-decay audit | Quarterly |
| Tickets-per-article retrospective | Monthly |

## Companion Refs

- [KNOWLEDGE-BASE.md](KNOWLEDGE-BASE.md) — KB structure, lifecycle
- [METRICS-AND-DASHBOARDS.md](METRICS-AND-DASHBOARDS.md) — measuring deflection
- [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md) — KB voice
- `/cass` — mining session history for patterns
- `/codebase-pattern-extraction` — when patterns span multiple projects
