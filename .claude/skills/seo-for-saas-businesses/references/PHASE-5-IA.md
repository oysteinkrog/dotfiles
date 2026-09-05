# PHASE 5 — INFORMATION ARCHITECTURE & INTERNAL LINKING

Goal: turn isolated pages into a graph search systems and users can navigate. Output is an IA target document and a concrete linking PR.

## Inputs

- Phase 1 `analyses/ia-current.md` (reverse-engineered from existing site).
- Phase 2 cluster ownership map.
- Phase 3 internal-link audit (orphans, redirected internal links, anchor distribution).

## Activities

### Pillar / cluster topology

For each pillar:
- Pillar page: explains the topic, audience, choices, next actions.
- Cluster pages: narrow subtopic depth.
- Bidirectional links: pillar ↔ each cluster page; sibling links only when genuinely useful.
- Anchor text: descriptive, names destination naturally; not "click here"; not over-optimized commercial anchors on every link.

### Hub pages

Where multiple page types share a topic surface:
- Product hub
- Use-case hub
- Industry hub
- Integration hub
- Resources hub

Hub explains why child pages belong together and which to read in what order.

### Breadcrumbs

Reflect actual hierarchy (parent → child), not navigation menus. Every breadcrumbed page emits `BreadcrumbList` schema mirroring visible breadcrumb. See [SCHEMA-POLICY](SCHEMA-POLICY.md).

### Footer

Trust + support + legal + important evergreen pages. Not a link dump. Common SaaS footer: pricing, security, privacy, terms, status, changelog, careers, blog, docs, contact.

### Internal linking rules

- Link from high-authority pages to important commercial and trust pages where relevant.
- Link from supporting articles back to the canonical hub.
- Use descriptive anchors (name destination naturally).
- Do not `nofollow` normal internal links.
- Fix internal links that route through redirects (audit via `scripts/internal-links.ts`).
- Make orphan pages a regular maintenance report.
- Put important links in crawlable HTML, not only in scripts, buttons, or search widgets.

### Anchor text distribution

Avoid over-optimization on commercial pages — too many internal links with anchor "best CRM software" pointing at one URL is a footprint. Mix:
- Brand anchors ("Acme")
- Naked URLs
- Generic anchors ("learn more", "see the docs")
- Descriptive long-tail ("how Acme's audit log works")
- Exact-match (small share)

Per cluster:
| Anchor type | % of internal links to commercial owner |
|---|---|
| Branded | 30–40% |
| Descriptive (mentions topic naturally) | 30–40% |
| Generic | 10–15% |
| Naked / partial-match | 10–15% |
| Exact-match | < 10% |

### Programmatic templates

Only where the dataset has real per-page differentiation. Gate via [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md). The IA decides:
- Is this template a child of a cluster (links up to pillar)?
- Is the template its own hub?
- How do users move between programmatic siblings?

### Sitemap topology

Split sitemap by page type and freshness class:
- `app/sitemap.ts` returns the index.
- `app/(marketing)/sitemap.ts`, `app/(blog)/sitemap.ts`, `app/(docs)/sitemap.ts`, `app/(integrations)/sitemap.ts` — per-segment sitemaps.
- Each segment ≤ 50k URLs.
- `lastmod` honest per page; not regenerated on every build.
- Only canonical indexable URLs.
- Submit each segment in GSC for diagnostic visibility (submitted vs indexed per segment).

## Outputs

- `analyses/ia-target.md` — the proposed IA with rationale.
- `deliverables/internal-link-pr.md` — concrete files to edit, anchor distribution, expected impact.
- `deliverables/sitemap-plan.md` — segment plan and rollout order.

## Anti-patterns

- Footer-link dump (50+ links pointing everywhere).
- Hub pages that are link lists with no context.
- Cluster pages that link to siblings but never back to pillar.
- Anchor text monoculture (every internal link to pricing reads "pricing").
- `nofollow` on internal navigation.
- Important links rendered only by client-side JavaScript.
- Sitemap that includes every URL the CMS can generate.
