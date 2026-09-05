# Knowledge Base Integration

A KB inside the support flow deflects tickets and gives canonical answers for staff and customers. This file covers how to wire a KB into the ticketing system you're building.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  KB articles    │     │  Ticket draft   │     │   Customer      │
│  (MDX in repo)  │ ──► │  (autosuggest)  │ ──► │   reads link    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        ▲                       ▲                        │
        │                       │                        │
        │                ┌──────────────┐                │
        └──── feedback ──┤ kb_citations │◄───────────────┘
                         └──────────────┘
```

## Schema Additions

```ts
// src/lib/db/schema-kb.ts
export const kbArticles = pgTable("kb_articles", {
  id:          uuid().primaryKey().defaultRandom(),
  slug:        text().notNull().unique(),
  title:       text().notNull(),
  body:        text().notNull(),         // MDX
  category:    supportCategoryEnum().notNull(),
  tags:        text().array(),
  embedding:   vector("embedding", { dimensions: 1536 }),  // pgvector
  publishedAt: timestamp({ withTimezone: true }),
  retiredAt:   timestamp({ withTimezone: true }),
  views:       integer().default(0).notNull(),
  helpfulYes:  integer().default(0).notNull(),
  helpfulNo:   integer().default(0).notNull(),
  createdAt:   timestamp({ withTimezone: true }).defaultNow().notNull(),
  updatedAt:   timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("kb_category_idx").on(t.category),
  index("kb_published_idx").on(t.publishedAt),
]);

export const kbSearchLog = pgTable("kb_search_log", {
  id:          uuid().primaryKey().defaultRandom(),
  query:       text().notNull(),
  resultCount: integer().notNull(),
  userId:      uuid().references(() => users.id),
  ts:          timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("kb_search_query_idx").on(t.query),
  index("kb_search_ts_idx").on(t.ts),
]);

export const kbCitations = pgTable("kb_citations", {
  id:        uuid().primaryKey().defaultRandom(),
  ticketId:  uuid().notNull().references(() => supportTickets.id),
  articleId: uuid().notNull().references(() => kbArticles.id),
  citedAt:   timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("kb_citations_ticket_idx").on(t.ticketId),
  index("kb_citations_article_idx").on(t.articleId),
]);

// One row per "this article solved my question before I had to file a ticket"
// click on the SupportWidget. Powers the deflection metrics below.
export const kbDeflections = pgTable("kb_deflections", {
  id:        uuid().primaryKey().defaultRandom(),
  articleId: uuid().notNull().references(() => kbArticles.id),
  userId:    uuid().references(() => users.id),  // null for anonymous
  query:     text().notNull(),
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("kb_deflections_article_idx").on(t.articleId),
  index("kb_deflections_created_idx").on(t.createdAt),
]);
```

## Three Touchpoints

### 1. Pre-submit Deflection (User Side)

When a user opens the SupportWidget and types into the subject field, debounce-search the KB and show top-3 matches before they hit submit.

```tsx
// src/components/support/SupportWidget.tsx
const [subject, setSubject] = useState("");
const debouncedSubject = useDebounce(subject, 300);
const { data: suggestions } = useQuery({
  queryKey: ["kb-suggestions", debouncedSubject],
  queryFn: () => fetch(`/api/support/kb-search?q=${encodeURIComponent(debouncedSubject)}`)
                   .then(r => r.json()),
  enabled: debouncedSubject.length > 8,
});

return (
  <form>
    <input value={subject} onChange={e => setSubject(e.target.value)} />

    {suggestions && suggestions.length > 0 && (
      <aside className="kb-suggestions" role="region" aria-label="Possible answers">
        <p>Some articles may already answer your question:</p>
        <ul>
          {suggestions.map(a => (
            <li key={a.id}>
              <a href={`/help/${a.slug}`} target="_blank" rel="noreferrer">
                {a.title}
              </a>
              <button onClick={() => trackDeflection(a.id, subject)}>
                This solved it
              </button>
            </li>
          ))}
        </ul>
      </aside>
    )}

    <textarea ... />
    <button type="submit">Submit</button>
  </form>
);
```

When the user clicks "One of these solved it", call:

```ts
// POST /api/support/kb-deflection
await db.insert(kbDeflections).values({
  articleId,
  userId: session.user.id,
  query: subject,
});
```

This is the single highest-leverage feature in the ticketing system. Even 20% deflection saves significant agent time.

### 2. Agent Suggestion (Admin Side)

When an agent opens a ticket, surface top-3 KB articles by embedding similarity:

```ts
// /api/admin/support/tickets/[id]/kb-suggestions
const ticket = await getTicket(params.id);
const queryEmbedding = await embed(`${ticket.subject}\n\n${ticket.description}`);

// Use cosine distance (<=>) consistently across the system so threshold
// values transfer between dedup and KB suggestion code paths.
const matches = await db
  .select()
  .from(kbArticles)
  .where(isNull(kbArticles.retiredAt))
  .orderBy(sql`embedding <=> ${queryEmbedding}::vector`)
  .limit(3);

return Response.json(matches);
```

In the admin reply composer:

```tsx
<aside>
  <h3>Suggested KB articles</h3>
  {suggestions.map(a => (
    <button onClick={() => insertCitation(a)}>
      Insert: "{a.title}" →
    </button>
  ))}
</aside>
```

Inserting a citation adds the link to the reply AND records to `kbCitations`.

### 3. Post-resolve KB Surfacing

When a ticket is resolved, the user's resolution email includes:
- The actual reply
- A "for next time" KB link if the resolution path matches a KB article

```ts
// Wraps the same embedding-search shown above (Option B). Returns the top
// match only when similarity exceeds a confidence threshold; a weak match
// in a resolved-email feels worse than no link at all.
async function findBestMatchingArticle(ticket: Ticket) {
  const queryEmbedding = await embed(`${ticket.subject}\n${ticket.description}`);
  const rows = await db.execute(sql`
    SELECT id, slug, title, 1 - (embedding <=> ${queryEmbedding}::vector) AS sim
    FROM kb_articles
    WHERE retired_at IS NULL
    ORDER BY embedding <=> ${queryEmbedding}::vector
    LIMIT 1
  `);
  const top = rows[0];
  return top && (top.sim as number) >= 0.78 ? top : null;
}

const matchedArticle = await findBestMatchingArticle(ticket);
await sendTicketResolvedEmail({
  to: user.email,
  ticket,
  resolutionMessage: lastSupportMessage,
  followUpArticle: matchedArticle, // null when below threshold
});
```

## Search Implementation

Three options, in order of complexity:

### Option A: Postgres Full-Text Search (Simple, Free)

```sql
ALTER TABLE kb_articles ADD COLUMN search_tsv tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('english', title), 'A') ||
    setweight(to_tsvector('english', body),  'B')
  ) STORED;

CREATE INDEX kb_search_idx ON kb_articles USING GIN (search_tsv);
```

```ts
const results = await db.execute(sql`
  SELECT id, slug, title, ts_rank(search_tsv, plainto_tsquery('english', ${query})) AS rank
  FROM kb_articles
  WHERE search_tsv @@ plainto_tsquery('english', ${query})
    AND retired_at IS NULL
  ORDER BY rank DESC
  LIMIT 5
`);
```

Good for ≤ 1000 articles. Stems, ranks, free.

### Option B: pgvector Embedding Search (Better, Same DB)

```ts
import { OpenAI } from "openai";
const openai = new OpenAI();

async function embed(text: string): Promise<number[]> {
  // text-embedding-3-small caps at 8191 tokens. Slicing the raw string to
  // ~24k chars (~6k tokens) avoids the API rejecting oversize inputs while
  // still capturing the leading paragraphs that carry the topic signal.
  const r = await openai.embeddings.create({
    model: "text-embedding-3-small",
    input: text.slice(0, 24_000),
  });
  return r.data[0].embedding;
}

// On article publish/edit:
const embedding = await embed(`${article.title}\n${article.body}`);
await db.update(kbArticles).set({ embedding }).where(eq(kbArticles.id, article.id));

// On search.
// Use cosine distance `<=>` for consistency with the dedup and KB-suggestion
// queries elsewhere in this file. text-embedding-3-small is normalised, so
// `<->` (L2) and `<=>` (cosine) produce the same RANKING but different distance
// VALUES — picking one operator across the codebase keeps thresholds portable.
const queryEmbedding = await embed(query);
const results = await db.execute(sql`
  SELECT id, slug, title, embedding <=> ${queryEmbedding}::vector AS distance
  FROM kb_articles
  WHERE retired_at IS NULL
  ORDER BY distance ASC
  LIMIT 5
`);
```

Cost: ~$0.0001 per query. Quality: meaningfully better for semantic match (e.g., "billing issue" matches "payment problem").

### Option C: Hybrid (Best Quality)

Combine both: BM25 (FTS) for exact-keyword recall + embedding similarity for semantic recall. Re-rank the union with reciprocal rank fusion (RRF) — rank within each result set, not the concatenated list.

```ts
const K = 60;  // RRF damping constant; 60 is the canonical value
const ftsResults = await ftsSearch(query, 10);
const vecResults = await vecSearch(queryEmbedding, 10);

const combined = new Map<string, number>();
const fuse = (results: { id: string }[]) => {
  results.forEach((r, rank) => {
    const score = 1 / (K + rank);
    combined.set(r.id, (combined.get(r.id) ?? 0) + score);
  });
};
fuse(ftsResults);
fuse(vecResults);

const ranked = [...combined.entries()]
  .sort((a, b) => b[1] - a[1])
  .slice(0, 5);
```

Default for new builds: Option B (embeddings). The cost is trivial; the quality gain is real.

## Tracking Deflection

Each interaction logged:

```sql
-- Deflection rate per week.
-- Bucket both event streams to the same week, then divide. A correlated
-- subquery referencing d.created_at would fail post-GROUP BY, so we use
-- a FULL OUTER JOIN of the two pre-aggregated CTEs.
WITH deflected AS (
  SELECT date_trunc('week', created_at) AS week, COUNT(*) AS n
  FROM kb_deflections
  GROUP BY 1
),
created AS (
  SELECT date_trunc('week', created_at) AS week, COUNT(*) AS n
  FROM support_tickets
  GROUP BY 1
)
SELECT
  COALESCE(d.week, c.week)         AS week,
  COALESCE(d.n, 0)                 AS deflected,
  COALESCE(c.n, 0)                 AS tickets_created,
  COALESCE(d.n, 0)::float
    / NULLIF(COALESCE(d.n, 0) + COALESCE(c.n, 0), 0) AS deflection_pct
FROM deflected d
FULL OUTER JOIN created c USING (week)
ORDER BY 1 DESC;

-- Most-cited articles
SELECT a.title, COUNT(c.id) AS citations
FROM kb_articles a
LEFT JOIN kb_citations c ON c.article_id = a.id
WHERE c.cited_at > now() - interval '30 days'
GROUP BY a.id, a.title
ORDER BY citations DESC LIMIT 20;

-- Articles with low helpful rate
SELECT title, helpful_yes, helpful_no,
       helpful_yes::float / NULLIF(helpful_yes + helpful_no, 0) AS helpful_rate
FROM kb_articles
WHERE helpful_yes + helpful_no >= 5
ORDER BY helpful_rate ASC LIMIT 20;
```

## "Was This Helpful?" Component

```tsx
// src/components/help/Helpful.tsx
"use client";
export function Helpful({ articleId }: { articleId: string }) {
  const [voted, setVoted] = useState<"yes" | "no" | null>(null);

  const vote = async (value: "yes" | "no") => {
    await fetch(`/api/help/${articleId}/helpful`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ value }),
    });
    setVoted(value);
  };

  if (voted) return <p>Thanks for the feedback.</p>;

  return (
    <div>
      <p>Was this helpful?</p>
      <button onClick={() => vote("yes")} aria-label="Helpful">👍</button>
      <button onClick={() => vote("no")} aria-label="Not helpful">👎</button>
    </div>
  );
}
```

If they pick "No", show a textarea for verbatim feedback. Log it.

## Companion Refs

- [SCHEMA.md](SCHEMA.md) — base ticket schema
- [ADMIN-UI.md](ADMIN-UI.md) — admin reply composer with KB suggestions
- [USER-UI.md](USER-UI.md) — pre-submit deflection
- [AI-ASSIST.md](AI-ASSIST.md) — embedding-based features beyond KB
- `/user-support-triage-for-saas-and-open-source-projects` — KB-FEEDBACK-LOOP.md describes the closed loop
