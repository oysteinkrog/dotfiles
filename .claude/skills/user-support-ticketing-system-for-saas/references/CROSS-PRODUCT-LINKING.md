# Cross-Product Linking

Tickets connect to engineering issues (covered in [TICKET-LINKING-AND-RELATIONSHIPS.md](TICKET-LINKING-AND-RELATIONSHIPS.md)). They also connect to product roadmap items, changelog entries, releases, KB articles, status-page incidents, and feature flags. This file is the architectural pattern for the *broader* set of cross-product links — turning the support system into a hub that ties customer experience to product evolution.

## The Linkable Entities

| Entity | Connection point | Relationship |
|---|---|---|
| Engineering issues | tracker (Linear/GitHub/Jira) | Cause / fix |
| Roadmap items | product roadmap tool | Wanted feature / promised feature |
| Changelog entries | versioned changelog | Feature shipped that mentions this ticket's issue |
| Release notes | per-version release notes | "Fixed in v2.4.1" |
| Status-page incidents | status page | Incident this ticket relates to |
| KB articles | docs site | Self-help content for this question |
| Feature flags | feature-flag system | Behavior cohort affecting this customer |
| Discord / community threads | community forum | Discussion of this issue |
| Sales opportunities | CRM | Open deal this customer is part of |
| Public X / HackerNews threads | external mentions | Customer also discussed publicly |

The schema generalizes from [TICKET-LINKING-AND-RELATIONSHIPS.md](TICKET-LINKING-AND-RELATIONSHIPS.md) by extending the `externalRefKind` to cover all of these:

```ts
export const externalRefKindEnum = pgEnum("external_ref_kind", [
  "github", "linear", "jira",                // engineering trackers
  "roadmap_item",                            // product roadmap
  "changelog_entry",                         // versioned changelog
  "release_note", "release_version",         // release / version
  "incident",                                // status page
  "kb_article",                              // documentation
  "feature_flag",                            // flag cohort membership
  "discord_thread", "slack_thread",          // community / chat
  "sales_opportunity",                       // CRM
  "public_mention",                          // external public mention (X, HN, etc.)
  "blog_post",                               // related blog post
]);
```

## Outbound Loops (Customer-Facing)

### "Fixed in v2.4.1" Notification

When a release ships that addresses a linked engineering issue, fan out:

```ts
async function onReleaseShipped(version: string) {
  // From release notes, extract the engineering-issue ids that shipped
  const fixedIssueIds = parseChangelogForFixes(version);
  for (const issueId of fixedIssueIds) {
    const linkedTickets = await listTicketsLinkedToEngineering(issueId);
    for (const ticket of linkedTickets) {
      // Add a system note (admin reviews before customer-visible reply)
      await addInternalNote({
        ticketId: ticket.id,
        message: `🚀 Engineering fix shipped in ${version}. Customer should now see [behavior]. Verify before notifying.`,
      });
      // Surface in admin "ready to verify" queue
    }
  }
}
```

Admin verifies the fix actually addresses the customer's symptoms (not just the underlying bug), then sends a customer-facing reply. Per the always-on rule: *engineering ships; admin confirms*.

### Roadmap Promise Tracking

When a customer requests a feature, link to the roadmap item:

```ts
await createTicketLink({
  fromTicketId,
  externalRefKind: "roadmap_item",
  externalRefId: "ROADMAP-INTEGRATIONS-2026-Q2",
  kind: "linked_to_roadmap",
  reason: "Customer requested SAML SSO; on Q2 roadmap",
});
```

When the roadmap item ships:

```
"Hi [name], remember when you asked about SAML SSO last quarter?
We shipped it yesterday — here's how to set it up: [link]"
```

Proactive customer-success motion. Customer feels heard.

### KB Article Suggested-To-Send

When admin replying to a ticket, the AI-assist (per [AI-ASSIST.md](AI-ASSIST.md)) surfaces:

```
📚 Relevant KB articles:
  • How to export skills (95% match)
  • Export troubleshooting (78% match)
  [Insert link in reply]  [Open article]
```

Admin clicks "Insert link" → reply textarea gets the link inserted. Customer reads → KB ROI per [COST-OF-SUPPORT.md](COST-OF-SUPPORT.md).

## Inbound Loops (Engineering-Facing)

### "47 Customers Affected By This Bug"

When engineering opens an issue, find affected support tickets:

```ts
async function findAffectedTicketsForBug(issueDescription: string): Promise<TicketAffinityScore[]> {
  const issueEmbedding = await embedText(issueDescription);
  const tickets = await db.query.supportTickets.findMany({
    where: gte(supportTickets.createdAt, sinceDate(90)),
    columns: { id: true, subject: true, description: true, userId: true },
  });
  const ticketEmbeddings = await Promise.all(tickets.map(t => embedText(`${t.subject}\n${t.description.slice(0, 1000)}`)));
  return tickets
    .map((t, i) => ({ ticket: t, score: cosineSimilarity(issueEmbedding, ticketEmbeddings[i]) }))
    .filter(s => s.score > 0.75)
    .sort((a, b) => b.score - a.score);
}
```

Engineering issue body auto-includes:

```
Affected customers (estimated, based on support tickets):
  47 tickets in last 90d match this issue (similarity > 0.75)
  Top 3 most-affected:
    - Acme Corp (12 tickets, $5K/mo)
    - Beta Inc (8 tickets, $2K/mo)
    - Gamma Co (5 tickets, $500/mo)
  Recent quotes:
    "When I click export, nothing happens"
    "Export silently fails for files over 10MB"
```

Engineering prioritizes with customer impact in view, not just internal-engineer-priority guess.

### Postmortem Cross-Reference

Per [POSTMORTEM-AND-LEARNING-LOOPS.md](POSTMORTEM-AND-LEARNING-LOOPS.md), each postmortem links to the tickets that triggered it. Postmortem doc has a "Customer Impact" section auto-populated:

```
This incident is linked to:
  - 18 customer tickets (12 P1, 6 P2)
  - 1 status-page incident
  - 1 changelog entry: v2.4.0 export-pipeline regression

Total support cost: $850 (per cost-of-support computation)
```

## The Cross-Product Map (Admin View)

Admin opening a ticket sees a **unified panel** showing all cross-product links:

```
┌─────── Ticket: Cannot export skills ────────────┐
│                                                  │
│ Customer journey: ↗                              │
│                                                  │
│ 🔧 Engineering: ENG-1234 (in review)            │
│ 🗺️ Roadmap: Q2 export-pipeline overhaul         │
│ 📦 Changelog: not yet shipped                    │
│ 📍 Incident: API latency 2026-04-12 (resolved)   │
│ 📚 KB: How to export (3 customers viewed)        │
│ 🚩 Flags: new_export_pipeline (cohort B)         │
│ 💬 Community: 1 Discord thread                   │
│ 💼 Sales: $50K opp closing this Q (Acme Corp)    │
└──────────────────────────────────────────────────┘
```

This is what makes the support cockpit a *strategic* surface, not just a queue. Admin sees the customer in their full context.

## Adding A New Link Type

When a new external system is added (e.g., new community forum, new analytics tool), the schema enumeration grows. Migration path:

1. Add value to `externalRefKindEnum`
2. Implement `linkAdapter` for the new system (lookup by ID, render display name, fetch URL)
3. Add UI affordances in the cross-product map
4. (Optional) Add inbound webhook from the new system to update linked tickets

Compile-time: TypeScript ensures every consumer of the enum handles the new case (use exhaustive switches with `assertUnreachable`).

## Bidirectional Sync Patterns

The link is bidirectional in *concept* but not always in *implementation*:

- Ticket → engineering issue: implemented by ticketRelations row
- Engineering issue → ticket: implemented by webhook to engineering tracker that posts a comment "Linked from support ticket: <link>"

Customers don't see engineering-tracker comments, but engineers see the bidirectional link. Reduces "where did this come from?" questions.

## Single-Click Side Effects

In the admin panel, each cross-product link has a one-click action:

```
🔧 Engineering: ENG-1234 (in review)        [View in Linear]  [Add comment]
🗺️ Roadmap: Q2 export-pipeline overhaul    [Add ticket as customer demand]
📚 KB: How to export                         [Insert link in reply]
💬 Community: 1 Discord thread               [Open thread]
```

The actions audit-trace:

```ts
{
  actionType: "support_external_action",
  metadata: {
    target: "linear:ENG-1234",
    operation: "add_comment",
    body: "Customer @ Acme Corp also affected by this; ticket #ABC12345"
  }
}
```

## Roll-Up Per-Engineering-Issue

For engineering reviewing a ticket, see all linked support data:

```
ENG-1234: Export pipeline silent failure
─────────────────────────────────────────
Linked tickets (47):
  Past 7 days:    23 tickets
  Past 30 days:   38 tickets
  Past 90 days:   47 tickets
Customer tiers:
  Enterprise: 12
  Individual: 28
  Free:       7
Total support cost: $1,840
P95 customer wait: 18.4h
Most-frequent quote: "click export, nothing happens"
```

This roll-up is the engineering case for prioritizing the bug.

## Privacy Filters

Cross-product links may surface customer info to systems with different access controls. Apply principle:

- Engineering tracker: company name + ticket reference (no PII in body unless investigation requires; redact)
- Public changelog: NO customer info (customer mentions allowed only with consent per [VOICE-OF-CUSTOMER-EXTRACTION.md](VOICE-OF-CUSTOMER-EXTRACTION.md))
- Internal tools (CRM, BI): full data ok

The `linkAdapter` per system is responsible for the redaction layer.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Auto-resolving support tickets when engineering issue closes | Engineering "fix" isn't always customer-facing fix |
| Posting customer name to public engineering-tracker comments | Privacy regression |
| Linking every ticket to a feature flag | Noise; flags are about cohort, not necessarily about cause |
| No bidirectional comment from engineering issue | Engineers re-discover support links manually |
| Cross-product map slow on every ticket open | Lazy-load (per [PERFORMANCE-BUDGETS.md](PERFORMANCE-BUDGETS.md)) |
| One-click actions without audit | Privileged-action audit gap |
| Engineering roll-up not refreshed | Stale data; engineering loses trust |
| Roadmap-promise notification sent without admin review | Customer reads "we shipped X" when actually we shipped a related-but-different thing |
| KB suggestions inserted without de-slopify | Slop creeps in via auto-template |
| Releases shipping without scanning for linked tickets | "We fixed your bug, but didn't tell you" frustration |

## Wire Points Checklist

- [ ] `externalRefKindEnum` covers all integration points
- [ ] Per-system `linkAdapter` (lookup, render, fetch URL, redact)
- [ ] Cross-product map UI on admin ticket detail
- [ ] One-click actions audited with `support_external_action`
- [ ] Release-shipped → scan linked tickets, post internal notes
- [ ] Roadmap-promise → notify on shipping (with admin review)
- [ ] KB-suggested in reply textarea, with insert button
- [ ] Engineering-issue inbound (webhook) → comment back to support tickets
- [ ] Find-affected-tickets-for-bug query for engineering tooling
- [ ] Per-engineering-issue roll-up endpoint with metrics
- [ ] Privacy filters: no PII in public-facing systems without consent
- [ ] Cross-product map lazy-loaded
- [ ] Test: engineering issue resolves → linked tickets get internal notes (not customer-visible)
- [ ] Test: customer requests feature → roadmap link appears → ships → admin notified
