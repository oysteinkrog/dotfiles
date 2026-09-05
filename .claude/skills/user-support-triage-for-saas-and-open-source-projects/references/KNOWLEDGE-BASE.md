# Knowledge Base — Building, Maintaining, Wielding

A KB exists to deflect tickets and to give agents canonical answers. A bad KB does the opposite: stale articles erode trust, missing articles waste agent cycles re-explaining, and an unstructured KB hides answers under a pile of "related links."

This ref covers: structure, lifecycle, how to wield it during triage, and the feedback loop with `KB-FEEDBACK-LOOP.md`.

## Structure

A useful KB has three tiers:

### Tier 1: Quickstart / Onboarding

Walks a new user from zero to first success. **2-7 articles, no more.** Optimize ruthlessly for the median new-user path. Every "advanced" branch goes to a deeper tier.

```
- Get started in 5 minutes
- Connect your first <thing>
- Run your first <core action>
- Common gotchas (top 3 only)
- Where to go next
```

### Tier 2: How-To (Recipes)

Task-oriented. **One task per article, in the user's language, not yours.**

Title format: `How to <verb> <noun>` ("How to invite a teammate", not "Team management overview").

Body shape:
1. Goal (one sentence)
2. Prerequisites (bulleted)
3. Steps (numbered, screenshots/CLI for each)
4. How to verify it worked
5. Common errors + fixes
6. Related: links to 1-2 adjacent recipes

A recipe is "done" when a brand-new user can complete the task without a ticket.

### Tier 3: Reference / Concept

Explains what something *is*, not how to do it. Use sparingly.

- API reference (per endpoint)
- Plan/pricing details (canonical)
- Architecture / data model (only if customers ask)
- Troubleshooting flowcharts for non-trivial multi-system issues

## Naming Articles

The single best lever for findability is title quality.

| Bad | Good |
|---|---|
| Authentication | How to set up SSO with Okta |
| Billing | How to update your payment method |
| Errors | Why does my deploy fail with `ENOENT`? |
| FAQ | (delete; FAQ is a graveyard) |

**Use the customer's word, not yours.** If they search "team mate", "teammate", "team member", "user", "seat" — the article needs to mention all of them. Run a 90-day search-log analysis quarterly to find the gap between what they search and what your titles say.

## Lifecycle

| Stage | Trigger | Owner | Validator |
|---|---|---|---|
| **Draft** | New ticket pattern emerges (3+ tickets in 30 days on same topic) | Triage agent | Owner approval before publish |
| **Publish** | Article passes review | Owner | Linked from at least 1 recipe + sitemap |
| **Maintain** | Code or pricing change | Engineer who shipped | Article updated in same PR or within 7 days |
| **Audit** | Quarterly or upon ticket-volume spike on covered topic | Owner | Articles read end-to-end; broken stuff fixed |
| **Retire** | <5 views in 90 days OR redirected by a better article | Owner | Redirect set up; backlinks fixed |

**Stale > missing.** A wrong article actively damages trust. If you don't have time to maintain an article, delete it (with redirect).

## Writing Style

- Second person ("you click", not "the user clicks").
- Short sentences. One idea per sentence.
- Active voice.
- Show, don't only tell — every recipe has at least one screenshot or CLI block.
- Avoid jargon unless it's the customer's jargon.
- Don't link out to vendor docs for things you can answer in 3 sentences.

## Wielding The KB During Triage

When a ticket arrives, before drafting a reply:

1. **Search the KB for the user's actual phrasing.** Not your interpretation — their words.
2. **If an article exists**:
   - Skim it; verify it's still accurate against current code.
   - Reply with the article link + 1-2 sentences of personalization (why this article fits their case).
   - Do NOT just paste the link — that feels dismissive.
3. **If no article exists but should**:
   - Reply normally; note `kb-gap: <topic>` in the bead.
   - When 3 tickets accumulate on the same gap, create the article.
4. **If an article exists but is wrong**:
   - Don't link to the wrong article. Reply with the correct answer.
   - Open a `kb-fix` bead.

## KB-Backed Reply Pattern

```
Hey <name>,

This is a known one — short answer is <X>.

Full walkthrough here: <kb-article-link>

The bit that catches most people is <step that fails most often>. If
you hit that, ping back and I'll dig in.

— <agent>
```

This is faster than re-explaining AND directs them to a maintained source.

## Customer-Facing Search

Most modern KBs need:
- Full-text search (Postgres FTS, Algolia, MeiliSearch, Typesense)
- Search analytics (what did they search? What returned 0 results?)
- "Was this helpful? Y/N" with optional verbatim
- Last-updated timestamp visible (builds trust)

The 0-result-search log is the single most valuable artifact for KB growth. **Read it weekly.**

## In-App KB

If your product has an in-app help drawer:
- Surface 3-5 articles based on the current page (context-aware).
- Don't auto-open it; respect attention.
- Make "still need help? open a ticket" prominent — KB is for deflection, not abandonment.

## Connecting To Tickets

For tickets that are answered by a KB article:
- Track `resolved_via_kb_link: true` in the ticket record.
- Aggregate weekly: which articles are getting cited most? Those need extra love.
- If a ticket cites article X 5+ times in a week, the article is missing something specific. Investigate.

## Anti-Patterns

| Don't | Why |
|---|---|
| FAQ pages | Become an unmaintainable graveyard; the format encourages adding without removing |
| One mega-article covering everything about a feature | Customers can't find their specific question; bounce back to ticket |
| "Coming soon" placeholders | Worse than nothing; visitor confidence drops |
| KB hidden behind login | Search engines can't index it; users hit support instead |
| KB without screenshots / examples | Customer can't verify they're in the right state |
| KB authored without an editor | Style drifts; agent voice differs from KB voice = jarring |
| KB articles not version-pinned to product version | After a UI change, every screenshot is wrong |
| Stale "last updated 2 years ago" timestamps | Customer assumes whole KB is stale; bounce |

## Voice For KB

Match `08-voice.md` closely but slightly more formal. KB outlives any single ticket; readers may not have context. Avoid time-bound references ("we recently shipped...") that age poorly.

## Tooling

Common stacks:
- **Static**: Nextra, Docusaurus, MkDocs — fast, indexable, version-controlled.
- **Hosted**: Intercom Articles, HelpScout Docs, Zendesk Guide — built-in analytics, less control.
- **Custom**: Headless CMS (Contentful, Sanity) + Next.js — most flexible, most overhead.

Default for SaaS: a `/help` route in your Next.js app, MDX articles, full-text search via Postgres FTS.

## Companion Refs

- [KB-FEEDBACK-LOOP.md](KB-FEEDBACK-LOOP.md) — turning ticket data into KB articles
- [METRICS-AND-DASHBOARDS.md](METRICS-AND-DASHBOARDS.md) — measuring deflection
- [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md) — KB voice vs ticket voice
- `/readme-writing` — adjacent skill for OSS README quality
