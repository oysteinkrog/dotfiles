# ANALYSES-LAYOUT — Predictable Output Paths

> **Why this exists:** every script writes to a known relative path under `analyses/`. Phase-N consumers find Phase-K outputs without grepping. Read this once and you know where everything lives.

All paths are relative to the **repo root** (where `.git` lives). Scripts auto-create directories with `mkdir -p`.

---

## Tree

```
analyses/
├── representative-urls.json     # PRODUCED FIRST — Phase 1, every other script consumes this
├── skill-availability.md        # gaps in sibling skills (manual fallback notes)
├── seo-changelog.md             # ALSO at repo root; one entry per shipped change
│
├── crawl/
│   ├── _index.json              # roll-up of every crawled page
│   ├── <hash>.raw.html          # raw HTML (no JS)
│   ├── <hash>.rendered.html     # post-render HTML
│   └── <hash>.json              # extracted meta + diff
│
├── ai-crawler/
│   ├── _report.json             # roll-up across (URL × bot)
│   └── <slug>__<bot>.html       # raw HTML each bot received
│
├── lighthouse/                  # Lighthouse CI filesystem output
├── crux/                        # per-URL JSON + _summary.csv / _summary.md
├── cwv-attribution/
│   └── <slug>.json              # per-page interaction breakdown
│
├── schema-validation.md
├── og-images.md / .json
├── hreflang.md / .json
├── redirect-chains.md / .json
├── sitemap-audit.txt            # plain text (legacy; pipe to file)
├── internal-links.md
├── entity-consistency.md / .json
├── ai-bot-policy.md / .json
├── llms-txt.md / .json
│
├── gsc/
│   ├── performance.csv
│   ├── per-page.csv
│   ├── per-query.csv
│   └── summary.md
├── striking-distance.md / .json
│
├── serps/
│   └── <query-slug>.json + .html
│
├── content-inventory.csv        # see assets/CONTENT-INVENTORY-CSV-SCHEMA.md
├── citation-tracking.csv        # see assets/CITATION-TRACKING-CSV-SCHEMA.md
│
├── post-deploy-verification.md  # PRODUCED LAST per release; no .json by default
└── decisions/                   # one DECISION-CARD per recommendation
    └── <YYYY-MM-DD>-<slug>.md
```

---

## Phase → output map (which phase produces what)

| Phase | Produces |
|---|---|
| 1 — Discovery | `representative-urls.json`, `crawl/`, `ai-crawler/`, `gsc/`, baseline of every other artifact |
| 2 — Keyword | `striking-distance.json`, GSC slices, query clusters in `decisions/` |
| 3 — Technical | `schema-validation.md`, `og-images.*`, `hreflang.*`, `redirect-chains.*`, `internal-links.md`, `lighthouse/`, `crux/`, `cwv-attribution/`, `entity-consistency.*`, `ai-crawler/`, `ai-bot-policy.*`, `llms-txt.*`, `sitemap-audit.txt` |
| 4 — Content | `content-inventory.csv`, draft markdown under `content-drafts/` (consumer-defined) |
| 5 — IA | internal-links graph + redirect map (`migration-url-map.csv` if migration) |
| 6 — Implementation | code changes in repo + `decisions/*.md` per change |
| 7 — Authority | `citation-tracking.csv`, `serps/` |
| 8 — Analytics | dashboard wiring + `decisions/*.md` |
| 9 — Experimentation | experiment cards under `decisions/` (one per `EXPERIMENT-CARD.md`) |
| 10 — Fresh-eyes | `phase-10-review.md` (consumer-defined) |
| 11 — Deploy | `seo-changelog.md` append |
| 12 — Verification | `post-deploy-verification.md` |
| 13 — Compounding | weekly/monthly reports under `analyses/reports/` |

---

## How to find a previous run

- **Latest snapshot** is always the file at the documented path. Re-runs overwrite.
- **Historical snapshots** are tracked via `git log analyses/`. Commit before re-running if you want a baseline.
- **Per-release diffs** live in `seo-changelog.md`. Each entry references the relevant `decisions/*.md`.

---

## Required: `representative-urls.json`

Almost every script consumes this. Shape:

```jsonc
{
  "tier": "T1|T2|T3|T4",
  "urls": [
    {
      "url": "https://www.example.com/",
      "template": "homepage|pricing|product|blog|comparison|integrations|location|...",
      "intent": "navigational|transactional|informational|investigational",
      "expected_status": 200,
      "expected_canonical": "https://www.example.com/",
      "expected_robots": "index, follow"
    }
  ]
}
```

Pick 30-100 URLs spanning every distinct page template. Include the homepage, top-converting marketing pages, the highest-traffic blog posts, an example of each programmatic family, and any pages flagged in GSC as anomalous. The rest of the program is calibrated against this set.

---

## Convention: `decisions/<YYYY-MM-DD>-<slug>.md`

One file per recommendation, structured per `assets/DECISION-CARD.md`. The agent's job is to emit these as findings. The PR description references them by filename. The changelog references them by URL/PR-number.

Sample slug: `2026-04-30-canonicalize-pricing-pricing-old.md`.

---

## What does NOT live in `analyses/`

- Source code changes — those are in the actual repo files.
- Marketing copy drafts — convention is `content-drafts/<slug>.md` under repo root, not `analyses/`.
- Big binary artifacts (Playwright traces, screenshots > 1 MB) — keep under `tmp/` or a CI artifact upload, not committed.
- Secrets, service-account keys, or raw GA4 exports with PII — never in `analyses/`. Use a sibling `secrets/` directory in `.gitignore`.

---

## Cleanup

After a phase ships:
- Archive bulky historical artifacts only if the target repo's retention policy allows it; otherwise leave them or upload them as CI artifacts.
- Keep `_index.json` files and `decisions/*.md` indefinitely — they're the audit trail.
