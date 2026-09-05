# Seasonality calendar — `<saas name>`, `<year>`

Per-cluster, quarterly demand calendar used by Phase 4 editorial planning and Phase 7 authority planning. Goal: ship content into the demand window, not after it. Most B2B SaaS programs miss peak demand because they start writing when the trend already shows up in GSC — by then the buyers have already chosen.

- **Maintained by**: `<owner>`
- **Last updated**: `<YYYY-MM-DD>`
- **Recheck-by**: end of each quarter
- **Data sources**: GSC year-over-year by query family; Google Trends; conference calendars; budget cycles (FY); regulatory deadlines; product launch dates

## Per-cluster rows

For each cluster in `analyses/clusters/`, fill one row per quarter.

| Cluster | Peak demand month(s) | Demand-driver event | Content-prep window | PR moment(s) | Pricing/promo window |
|---|---|---|---|---|---|
| `<cluster>` | `<Mar / Q1 close>` | `<event: conference / FY close / regulation deadline / product update>` | `<6 weeks pre-peak: Jan 20 – Mar 1>` | `<embargoed report drop / partner co-marketing>` | `<EOQ promo / annual upgrade nudge>` |
| … | | | | | |

Content-prep window default: **4–6 weeks pre-peak** for refreshes, **8–12 weeks pre-peak** for net-new pillars (link earning needs lead time).

## B2B SaaS — generic demand drivers

| Driver | Typical window | Content implication |
|---|---|---|
| Calendar-Q4 budget close | Oct–Dec | Pricing, ROI, comparison content peaks. Annual-upgrade decision page. |
| New fiscal year (US Federal: Oct–Sep; many EU: Apr–Mar) | Pre-FY launch | Procurement-eligible page (security, SOC 2, DPA, data residency). |
| Annual planning (corporate calendar) | Nov–Jan | Strategy + framework content. |
| Industry conferences | Per-vertical | Embargoed report drop; sales-enablement page. |
| Renewal cycles | Anniversary cohort | Migration, "vs alternative", expansion docs. |
| Hiring spikes (Jan, Sep) | Pre-month | Tooling-evaluation content; team-onboarding docs. |
| Compliance deadlines | Per-regulation | Compliance-ready page with proof. |

## Vertical examples

### B2B SaaS (generic)

| Cluster | Peak | Driver | Content-prep window | PR moment |
|---|---|---|---|---|
| pricing comparison | Oct–Dec | Q4 budget close | Aug 15 – Oct 1 | Annual pricing-trends report |
| migration | Q1 | New-year tooling consolidation | Dec 1 – Jan 15 | "State of `<category>` migrations" |
| best-of listicle | Q1, Q3 | Annual planning + post-summer reset | 6 weeks pre | Methodology-disclosed benchmark |

### Dev tools

| Cluster | Peak | Driver | Content-prep window | PR moment |
|---|---|---|---|---|
| performance benchmark | Mar, Sep | Major-version release cadence (frameworks, runtimes) | Concurrent with framework RC | Benchmark with reproducible methodology + repo |
| migration guides | Q1, Q3 | Post-major-version migrations | 4 weeks post-stable | Co-marketing with framework team |
| getting-started / quickstart | Continuous | Hiring-spike onboarding + bootcamp seasons | n/a (always fresh) | Conference workshop slot |
| changelog | Continuous | Product-led SEO | n/a | Release notes weekly |

### Security / compliance

| Cluster | Peak | Driver | Content-prep window | PR moment |
|---|---|---|---|---|
| SOC 2 / ISO 27001 | Q1 (audit prep), Q3 | Annual audit cycle | 8 weeks pre-audit kickoff | Annual transparency / trust report |
| Incident response | Continuous + post-major-incident | Breaking incidents | 24h emergency cadence | Post-incident postmortem (own incident) |
| Data residency | Q4 (procurement) | Enterprise sales cycle | Ongoing | Region launch announcement |
| Compliance frameworks (HIPAA, PCI-DSS, FedRAMP) | Pre-deadline + budget close | Regulation deadlines + procurement | 12 weeks pre-deadline | Legal/expert co-author byline |

### Fintech

| Cluster | Peak | Driver | Content-prep window | PR moment |
|---|---|---|---|---|
| tax season | Jan–Apr (US) | IRS deadlines + filing windows | Nov 1 – Jan 15 | Annual tax-implications report |
| year-end close | Nov–Jan | Accounting close | 6 weeks pre | CFO-cohort newsletter sponsorship |
| budgeting | Oct–Jan | FY planning | 8 weeks pre | Annual budget-trends report |
| 1099 / contractor pay | Q1 | Tax filings | Concurrent with tax | Joint webinar with tax-prep partner |
| regulatory updates | On-event | Reg changes (CFPB, OCC, EU) | 24–72h emergency cadence | Expert byline within 7 days |

### Healthcare / health-tech

| Cluster | Peak | Driver | Content-prep window | PR moment |
|---|---|---|---|---|
| HIPAA compliance | Q1 + audit cycle | Annual review + breach reporting | 8 weeks pre-audit kickoff | Annual HIPAA-readiness report (with named expert) |
| open enrollment | Oct–Dec (US) | Plan year selection | Aug 1 – Oct 1 | Plan-comparison data |
| billing cycles | Per-payer | Insurance reimbursement timelines | Continuous | Quarterly payer-specific updates |
| public-health events | On-event | CDC / WHO advisories | 24–72h emergency cadence; bound by [HIGH-RISK-GATE](../references/HIGH-RISK-GATE.md) | Expert-reviewed advisory page |

## Per-quarter fill-in

Use this layout for each upcoming quarter. Record actuals at quarter end so the next-year version starts with evidence.

```md
## Q<n> <YYYY>

### Planned
| Cluster | Peak month | Content-prep deadline | Briefs to ship | Owner | Status |
|---|---|---|---|---|---|
| <cluster> | <month> | <YYYY-MM-DD> | <n> | <owner> | <not started | in progress | shipped> |

### Ride-along PR moments
- <YYYY-MM-DD>: <event> — <our angle> — <owner>

### Pricing / promo windows
- <YYYY-MM-DD> – <YYYY-MM-DD>: <campaign>; SEO impact: <noindex landing | crawl-allowed | gated>

### Actuals (filled post-quarter)
- Briefs shipped: <n>/<planned>
- Peak-window traffic delta vs prior year: <±%>
- Lessons: <bullets>
```

## Anti-patterns

- **Writing the seasonal page during the peak.** By the time the trend shows in GSC, you've already missed the decision window. Ship 4–6 weeks pre-peak.
- **Planning purely off Google Trends.** Trends shows search volume; it doesn't show *buying* windows. Cross-check with sales / customer-success records of when contracts close in this category.
- **Reusing last year's content unchanged.** Refresh dates and proof. Stale dates kill citation eligibility ([AI-VISIBILITY](../references/AI-VISIBILITY.md)).
- **Promo-driven landing pages indexed permanently.** Promo content not meant to outlive the promo gets `noindex,follow` and is removed/redirected after the window. Otherwise it pollutes the cluster.
- **Single-vertical thinking.** A B2B SaaS in healthcare has *both* the SaaS Q4 budget cycle *and* the open-enrollment cycle — overlay both calendars.

## Cross-references

- [PHASE-4-CONTENT](../references/PHASE-4-CONTENT.md), [PHASE-7-AUTHORITY](../references/PHASE-7-AUTHORITY.md), [HIGH-RISK-GATE](../references/HIGH-RISK-GATE.md)
- [CONTENT-INVENTORY-CSV-SCHEMA](CONTENT-INVENTORY-CSV-SCHEMA.md), [BRIEF-TEMPLATE](BRIEF-TEMPLATE.md)
