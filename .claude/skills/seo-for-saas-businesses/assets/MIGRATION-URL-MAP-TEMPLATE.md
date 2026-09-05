# Migration URL map

Schema for `analyses/migration/url-map.csv` — the authoritative record of every old-URL → new-URL decision in a migration. Drives the redirect implementation, the staging test, the launch verification, and the 30/90-day post-launch monitoring. Use with [MIGRATION-CHECKLIST](../references/MIGRATION-CHECKLIST.md). One row per old URL — no exceptions.

## Columns

| Column | Type | Required | Notes |
|---|---|---|---|
| `old_url` | absolute URL | yes | Exact pre-migration URL (post-canonical, post-trailing-slash). |
| `new_url` | absolute URL | conditional | Required unless `status_code = 410 / 404`. |
| `status_code` | enum | yes | `301 | 302 | 410 | 404 | 200-keep` |
| `reason` | string | yes | Why this fate. Cite the inventory action ([CONTENT-INVENTORY-CSV-SCHEMA](CONTENT-INVENTORY-CSV-SCHEMA.md)) and any audit ID. |
| `owner` | string | yes | Single human responsible for verifying this row in staging and prod. |
| `traffic_loss_risk` | enum | yes | `low | med | high` (high = top-100 by clicks/links) |
| `backlinks_count` | int | yes | Total backlinks at the old URL. Drives outreach priority. |
| `test_status` | enum | yes | `pending | staging-pass | staging-fail | prod-verified` |
| `launched_date` | YYYY-MM-DD | conditional | Filled when prod-verified. |
| `notes` | string | no | Edge cases, hreflang, query-string variants, redirect-chain length. |

## Status-code policy

| Status | When to use |
|---|---|
| `301` | Direct equivalent OR merged-into destination on the new site. Permanent. |
| `302` | Almost never. Only for short-lived A/B-style migrations where you'll re-evaluate. Default to 301. |
| `410` | Permanently gone, no replacement. Use when content is genuinely retired. |
| `404` | Same as 410 if your stack doesn't support 410. Acceptable but less explicit. |
| `200-keep` | Keep at the same URL post-migration. Useful for `noindex,follow` archive pages. |

**Never redirect retired pages to the homepage.** That behaves like a soft-404 storm and dilutes signal across the new site.

## Example rows

```csv
old_url,new_url,status_code,reason,owner,traffic_loss_risk,backlinks_count,test_status,launched_date,notes
https://old.example.com/pricing,https://example.com/pricing,301,Direct equivalent post-rebrand,Alice Chen,high,412,prod-verified,2026-04-15,
https://old.example.com/blog/2022-state-of-x,https://example.com/blog/state-of-x,301,Renamed; same canonical content,Dana Liu,med,140,prod-verified,2026-04-15,Original report; backlink-heavy
https://old.example.com/features/<deprecated>,https://example.com/changelog/<deprecated>-sunset,301,Sunset page explains migration path,Ben Park,low,18,staging-pass,,Sunset note links to current alternative
https://old.example.com/promo/early-2024,,410,Promo expired; not meant to outlive campaign,Alice Chen,low,2,prod-verified,2026-04-15,
https://old.example.com/internal-search?q=...,,404,Search-result URLs never indexable,Engineering,low,0,prod-verified,2026-04-15,Robots also disallows; noindex header set
```

## Pre-launch staging tests

Run these against the staging environment with the redirect map applied.

### Sample query set (minimum)

- [ ] **Top 50 by traffic** (last 90d clicks).
- [ ] **Top 50 by backlinks** (referring-domain count).
- [ ] **All `traffic_loss_risk = high` rows.**
- [ ] **Sample of every page type** (≥3 per type from `analyses/template-inventory.md`).
- [ ] **Edge cases**: trailing-slash variants, uppercase URLs, query-string variants, internationalized paths, paginated URLs (`?page=2`), faceted URLs.
- [ ] **All hreflang reciprocal pairs** (international sites).
- [ ] **Old sitemap URLs** — every URL listed in the old `sitemap.xml`.

### Per-URL checks

- [ ] Status code matches `status_code` column.
- [ ] Single hop (no redirect chain > 1).
- [ ] Destination returns 200.
- [ ] Destination canonical = destination URL (not the old URL).
- [ ] HTTPS preserved end-to-end.
- [ ] No mixed-content warnings.
- [ ] Schema valid on destination per [SCHEMA-POLICY](../references/SCHEMA-POLICY.md).
- [ ] hreflang reciprocity intact (if applicable).

Tests pass → set `test_status = staging-pass`.

## Launch-day verification

- [ ] Sample 20 high-risk URLs in production within 1 hour of cutover.
- [ ] Verify `Location:` header points to expected `new_url`.
- [ ] Submit new sitemap in GSC; resubmit Bing.
- [ ] Annotate GSC + GA4 + `seo-changelog.md` with launch timestamp.
- [ ] Set `launched_date` for verified rows.

## Post-launch monitoring

### Daily (first 14 days)

- [ ] GSC URL inspection on 20 highest-traffic redirected URLs — confirm Google fetched and recognized the redirect.
- [ ] 5xx / 4xx spike check filtered by verified Googlebot.
- [ ] Verified-Googlebot crawl logs on the new domain — is it crawling the new URLs?
- [ ] Branded-search baseline holding (≥95 % of pre-launch).

### Weekly (first 30 days)

- [ ] Traffic comparison vs pre-launch baseline by segment (page type, cluster, locale).
- [ ] Top losing pages — are they on the map? Any URLs that were missed?
- [ ] Backlink owners notified for the top 50 by backlink count.
- [ ] Sitemap submitted vs indexed delta — should approach pre-launch baseline.

### 30–90 days

- [ ] CrUX delta neutral or better per template.
- [ ] GSC enhancement reports clean.
- [ ] Branded recovery within 14 days; non-branded may take 30–60 days.

## Completion criteria

- [ ] Indexed page count within 5 % of pre-launch.
- [ ] Organic traffic within 10 % of pre-launch baseline (after seasonality).
- [ ] No outstanding redirect / canonical / schema regressions.
- [ ] Every row has `test_status = prod-verified` or has an explicit retire/dispose note.
- [ ] [MIGRATION-CHECKLIST](../references/MIGRATION-CHECKLIST.md) post-launch section all green.

## Anti-patterns

- **All-to-homepage redirects.** Soft-404 storm; punishes the homepage signal and drops the equity of every redirected URL.
- **Redirect chains.** Every chain hop drops a fraction of signal and adds latency. One hop, every time.
- **Decommissioning the old sitemap immediately.** Keep it accessible until Google has re-crawled the redirects (often 30–60 days). Otherwise Google retries old URLs at the old location.
- **Skipping the staging crawl.** The map looks right in a spreadsheet; the staging crawl is the only ground truth.
- **Forgetting query-string + faceted URLs.** They have backlinks too. Audit URL parameters explicitly.
- **Treating launch day as "done".** The map is verified at 30 days post-launch, not at launch.
- **No owner per row.** "Engineering" doesn't verify rows. One human does.

## Cross-references

- [MIGRATION-CHECKLIST](../references/MIGRATION-CHECKLIST.md), [TRAFFIC-DROP-PLAYBOOK](../references/TRAFFIC-DROP-PLAYBOOK.md), [PHASE-12-VERIFICATION](../references/PHASE-12-VERIFICATION.md)
- [CONTENT-INVENTORY-CSV-SCHEMA](CONTENT-INVENTORY-CSV-SCHEMA.md), [DECISION-CARD](DECISION-CARD.md), [PR-DESCRIPTION-TEMPLATE](PR-DESCRIPTION-TEMPLATE.md)
