# Documentation Feedback Loop

Every ticket that should-have-been-a-doc is a documentation gap. The support queue is the world's best ranked list of doc gaps, sorted by frequency × severity × customer reach. Most teams never harvest it.

This file is the architectural pattern for closing the loop: ticket → identified gap → KB article → deflection metric → fewer tickets next time.

## The Three Doc Gaps

| Gap | Symptom | Fix |
|---|---|---|
| **Missing** | No article exists for the topic | Write a new article |
| **Wrong** | Article exists but is incorrect or outdated | Update the article |
| **Unfindable** | Article exists, customer didn't find it | Improve search/discoverability |

The fix differs. The detection mechanism differs too.

## Detecting Missing Docs

When admin replies to a ticket, ask: "Did this require *new* explanation, or could a doc article have answered it?"

Add a field on admin reply:

```ts
// On admin reply form:
{
  message: text,
  kbCandidate: boolean,         // "this should be in the docs"
  kbCandidateNote: text,        // optional explanation
  kbExistingArticleId: uuid,    // if they already linked an article
}
```

Track:

```sql
SELECT
  topic_cluster_id,
  COUNT(*) AS unique_tickets,
  COUNT(DISTINCT user_id) AS unique_customers,
  AVG(time_to_resolve_minutes) AS avg_resolve_min,
  SUM(CASE WHEN kb_candidate THEN 1 ELSE 0 END) AS marked_as_kb_gap
FROM tickets_with_clusters
WHERE created_at > NOW() - INTERVAL '60 days'
GROUP BY topic_cluster_id
HAVING SUM(CASE WHEN kb_candidate THEN 1 ELSE 0 END) >= 3
ORDER BY unique_tickets DESC;
```

This is your weekly doc-gap report. Top 10 are the next 10 articles to write.

## Detecting Wrong Docs

When KB article is linked in a reply, track customer follow-up:

```ts
async function trackKbArticleEffectiveness(articleId: string, ticketId: string) {
  await db.insert(kbArticleUsageEvents).values({
    articleId,
    ticketId,
    sharedAt: new Date(),
  });

  // 24h later, check if customer replied with continued confusion
  await scheduleAfter(24 * 60 * 60 * 1000, async () => {
    const customerReplied = await didCustomerReplyAfterShare(ticketId, articleId);
    const customerSatisfied = customerReplied
      ? await analyzeCustomerSatisfaction(ticketId, articleId)
      : "unknown_no_reply";
    await db.update(kbArticleUsageEvents)
      .set({ customerOutcome: customerSatisfied })
      .where(/* ... */);
  });
}
```

Article with high "share + customer kept asking" rate is wrong, outdated, or confusing. Output:

```
KB ARTICLE EFFECTIVENESS REPORT — Last 30 days
─────────────────────────────────────────────────

Top problematic articles (high share, low resolve):
  1. "How to export data" — shared 47x, customer satisfied 12x (26%) ← review
  2. "Reset your password" — shared 89x, satisfied 81x (91%) ← OK
  3. "Two-factor authentication setup" — shared 23x, satisfied 8x (35%) ← review
```

## Detecting Unfindable Docs

Customer searched the KB, didn't find the article, opened a ticket:

```ts
// Customer's KB-search history before opening ticket
type KbSearchEvent = {
  userId: string;
  query: string;
  resultsShown: number;
  clickedResults: number;
  resultsClickedIds: string[];
  searchedAt: Date;
};

async function detectUnfindableArticles(): Promise<UnfindableArticle[]> {
  // For each ticket created in last 30d, check if user searched KB before
  const tickets = await getRecentTickets({ days: 30 });
  const unfindable: UnfindableArticle[] = [];

  for (const ticket of tickets) {
    const recentSearches = await getKbSearchesForUser({
      userId: ticket.userId,
      since: subtractMinutes(ticket.createdAt, 30),
      until: ticket.createdAt,
    });

    if (recentSearches.length === 0) continue;

    // Did one of the search queries match an existing article topic?
    const matchingArticle = await findArticleMatchingTicket(ticket);
    if (matchingArticle && !recentSearches.some(s => s.resultsClickedIds.includes(matchingArticle.id))) {
      unfindable.push({
        ticketId: ticket.id,
        articleId: matchingArticle.id,
        searchQueriesUsed: recentSearches.map(s => s.query),
      });
    }
  }
  return unfindable;
}
```

Action: improve search synonyms, rewrite article title, add tags. Don't write a new article — fix discoverability.

## Self-Service Deflection Metric

Track how often customers self-resolve via KB:

```ts
type DeflectionEvent =
  | { kind: "kb_article_viewed"; articleId: string; sessionId: string }
  | { kind: "kb_article_helpful_voted"; articleId: string; sessionId: string }
  | { kind: "ticket_created_after_kb_view"; articleId: string; sessionId: string };

async function computeDeflectionRate(period: DateRange): Promise<number> {
  const totalKbViews = await countEvents({ kind: "kb_article_viewed", period });
  const ticketsAfter = await countEvents({ kind: "ticket_created_after_kb_view", period });
  return 1 - (ticketsAfter / totalKbViews);
}
```

A deflection rate of 92% means: 92% of customers who viewed a KB article didn't open a ticket within the next session. Track per article and globally.

Industry benchmark: 60–80% deflection. Above 90% is excellent; below 50% means docs aren't useful.

## In-Reply Insertion

When admin replies, KB suggestions surface inline:

```
┌────────── New Reply ──────────────────────────┐
│                                                │
│ Hi, you can export by going to                 │
│ Settings → Data → Export.                      │
│                                                │
│ 📚 Suggested articles:                         │
│   • How to export your data (98% match) [+]    │
│   • Export file formats (87% match) [+]        │
│   • Export troubleshooting (76% match) [+]     │
│                                                │
│ ☑ Also flag this as a doc-gap candidate        │
│                                                │
│ [Cancel] [Send]                                 │
└────────────────────────────────────────────────┘
```

Click [+] inserts a link. Increases consistency of KB references and gives admin one-click contribution to deflection.

## Article Authoring Workflow

Doc-gap report → article authoring:

```
┌─── Doc Gap Triage (Weekly) ──────────────────┐
│                                                │
│ 1. "How to invite teammates"                   │
│    Tickets: 12 (last 60 days)                  │
│    Marked as gap: 8                             │
│    Sample question:                             │
│      "How do I add my designer to my account?"  │
│    [Write article] [Open existing for edit]    │
│                                                │
│ 2. "Custom domain setup"                        │
│    Tickets: 7                                   │
│    Marked as gap: 5                             │
│    [Write article] [Open existing for edit]    │
│                                                │
└────────────────────────────────────────────────┘
```

Click "Write article" → KB editor opens with: ticket samples, draft outline pre-filled, links back to source tickets.

After publishing: admin closes the linked tickets with: "Just published a guide on this — [link]. Let me know if it helps."

## Article-To-Ticket Backlinks

Each article tracks which tickets contributed to it:

```ts
export const kbArticles = pgTable("kb_articles", {
  // ...existing fields
  sourceTicketIds:   uuid().array(),   // tickets that motivated this article
  publishedAt:       timestamp({ withTimezone: true }),
  lastReviewedAt:    timestamp({ withTimezone: true }),
});
```

Use cases:
- See which tickets motivated each article (transparency)
- Notify those customers when the article publishes ("we built this guide because of you")
- Track ROI per article (deflections × seconds saved)

## Periodic Review

Articles age. Schedule a review every N days based on volume and category:

| Article topic | Review every |
|---|---|
| Pricing / billing | 30 days |
| Auth / security | 30 days |
| Core feature usage | 90 days |
| Integrations | 60 days |
| Edge cases | 180 days |

```ts
async function findStaleArticles(): Promise<KbArticle[]> {
  const articles = await getKbArticles();
  return articles.filter(a => {
    const reviewWindow = REVIEW_WINDOWS[a.category] ?? 180;
    return daysSince(a.lastReviewedAt ?? a.publishedAt) >= reviewWindow;
  });
}
```

Stale article gets banner: "🕒 Last reviewed 8 months ago — verify accuracy". Don't auto-unpublish.

## Customer-Facing Feedback

Each article has thumbs up/down + optional comment:

```
Was this helpful?  [👍 Yes]  [👎 No]

(If 👎): Tell us what's missing... [____________]
```

Negative feedback creates a doc-gap candidate automatically:

```ts
async function recordKbFeedback(articleId: string, helpful: boolean, comment?: string) {
  await db.insert(kbArticleFeedback).values({ articleId, helpful, comment });
  if (!helpful && comment) {
    // Treat as soft doc-gap signal
    await tagDocGap({ articleId, source: "kb_negative_feedback", note: comment });
  }
}
```

## In-Product Doc Surfacing

Where customers actually struggle isn't on the docs site — it's in the product. Surface relevant articles inline:

```tsx
// On settings page where customers struggle with export:
<Tooltip content={<KbArticlePreview articleId="export-data" />}>
  <Button>Export</Button>
</Tooltip>
```

When a customer hovers / clicks the tooltip, log the engagement (per [SUPPORT-PRODUCT-INTEGRATION.md](SUPPORT-PRODUCT-INTEGRATION.md)).

## Anti-Patterns

| ✗ | Why |
|---|---|
| Writing docs by guessing what customers need | Wastes time on low-impact articles |
| No metric for deflection | Can't tell if docs work |
| Article view count ≠ effectiveness | High views with high follow-up tickets means article is wrong |
| KB suggestions not used in reply UI | Missed contribution opportunity |
| Stale articles without review | Customers follow outdated steps; lose trust |
| Article-to-ticket backlinks missing | Can't compute per-article ROI |
| No way to mark "this needs a doc" | Doc gaps live in agents' heads, not the system |
| Doc team not embedded in support | Docs drift from real customer language |
| Search synonyms not maintained | Customer says "share" the docs say "invite"; never finds |
| Negative feedback not actionable | Customers complain into the void |

## Wire Points Checklist

- [ ] `kbCandidate` flag on admin reply
- [ ] Topic clustering aggregated weekly into doc-gap report
- [ ] KB article effectiveness tracking (share + follow-up)
- [ ] Unfindable-article detection (search-then-ticket pattern)
- [ ] Deflection rate metric per article and globally
- [ ] In-reply article insertion UI
- [ ] Article authoring workflow with ticket samples pre-loaded
- [ ] `sourceTicketIds` backlinks
- [ ] Stale-article review scheduler
- [ ] Customer thumbs-up/down feedback → doc-gap signal
- [ ] In-product article surfacing
- [ ] Test: 3+ tickets marked as kb_candidate → appears on weekly report
- [ ] Test: stale article shows "last reviewed" banner
- [ ] Test: shared KB article + follow-up = effectiveness flag drops
