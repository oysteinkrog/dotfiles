# PHASE 2 — KEYWORD & INTENT RESEARCH

Goal: a target query universe with intent classification, SERP-feature mapping, and pillar/cluster topology — every cluster mapped to a canonical owner page.

## Inputs

- Phase 1 baseline + IA + GSC last-90-days top queries.
- Product surface area (read `app/`, `lib/`, customer-facing copy, sales / marketing materials).
- Customer ICP (from user; sales transcripts where available).
- Competitor list (3–5 named).

## Activities (parallelizable)

| Task | Subagent | Output |
|---|---|---|
| JTBD inventory | (orchestrator) | `analyses/jtbd.md` |
| Per-competitor gap | competitor-researcher (one per competitor) | `analyses/competitors/<name>.md` |
| Per-cluster intent + SERP feature map | cluster-researcher (one per cluster) | `analyses/clusters/<cluster>.md` |
| Anti-cannibalization map | (orchestrator) | `analyses/cannibalization-map.md` |
| Cluster ownership | (orchestrator) | `analyses/cluster-owners.md` |

## Per-cluster output

```md
# Cluster: <name>

## Intent and audience
- Pillar query: <e.g. "soc 2 compliance">
- Audience: <ICP>
- Funnel stage: <awareness / evaluation / decision>
- Intent: <informational / commercial / transactional / navigational>

## Seed queries (with monthly volume estimates and current rank)
- query | volume | intent | current rank | owner URL | SERP features

## Subtopics (cluster pages)
- <topic> | intent | format | owner URL (existing or planned) | SERP features

## SERP feature inventory
- AIO present? Coverage breadth?
- PAA dominant questions?
- Video / image / product / local / forum / news?
- Top 10 competitors per query (table)

## Conversion path
- Cluster → primary CTA (signup / demo / docs / pricing)
- Internal links from this cluster to commercial pages

## Proof requirements
- What data / screenshots / first-hand evidence does this cluster need to win?

## Decision
- Build new pages? Refresh existing? Merge?
- Owner human / writer
- Refresh cadence
```

## Cluster ownership rule

For every query family, exactly one canonical URL owns it. Other URLs in the cluster are *support* (link to the owner; do not compete for the same intent).

If two existing URLs target the same query family with the same intent, decide:
- Merge (preferred) — redirect lower-traffic to higher-traffic; consolidate content.
- Differentiate intent — make one informational and the other commercial; titles, H1, internal links, CTAs all change.
- Noindex one — only when one URL serves users but should not be a search result.

## SERP-feature → format mapping

Use the [search-surface planning matrix from the guide §7] to choose page format per query:

| Dominant SERP feature | Format requirement |
|---|---|
| Standard web result | Crawlable HTML, clear title, useful snippet source, internal links |
| Featured snippet | Concise direct answer near matching heading, then depth |
| Image result | Original crawlable image on relevant landing page with surrounding text |
| Video result | Embedded crawlable video, transcript, `VideoObject` |
| Product / merchant | Accurate price / availability / shipping / returns; product identifiers |
| Local result | Real local presence; LocalBusiness; reviews |
| Discussion / forum | First-hand experience; named author; community signals |
| News / Top Stories | Fresh reporting / analysis; dates; original sourcing |
| AI answer citation | Extractable passages, original evidence, three+ unique data points |

## Anti-patterns

- Keyword research that ignores intent and just sorts by volume.
- Picking keywords for which the SaaS has no proof or no path to conversion.
- Building a cluster around a query family the SERP shows wants product / video / forum / local — but writing an article instead.
- Two URLs targeting the same query with the same intent and shipping anyway.
- Building "topic clusters" to *simulate* authority on subjects the product doesn't actually serve.
