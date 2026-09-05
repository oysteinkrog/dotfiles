# AGENT-QUICKREF — Decision Tree for Agents

> **Purpose:** load this first. It maps user intent → exact files to read → exact scripts to run → expected outputs. Skip the rest of `SKILL.md` until you've identified your branch.
>
> **Token budget:** ~3 KB. Read in full.
>
> **When to deviate:** never on first pass. After the path runs, you may consult deeper references for nuance.

---

## STEP 1 — Identify intent (look for these phrases in the user's message)

| If the user says (or implies)... | Mode | Load these refs in order | Run these scripts |
|---|---|---|---|
| "audit", "do an SEO pass", "improve our SEO" | `mature-site-audit` | INTAKE → AUDIT-CHECKLIST → PHASE-1 → PHASE-3 | `crawl.ts` → `validate-schema.ts` → `cwv-check.ts` → `internal-links.ts` |
| "we just launched", "new SaaS", "no SEO yet" | `greenfield-seo` | INTAKE → 90-DAY-PLAN → PHASE-1..6 | `crawl.ts` → `gsc-extract.ts` → all of Phase 3 |
| "traffic dropped", "lost rankings", "core update", "down YoY" | `traffic-drop-triage` | INTAKE → TRAFFIC-DROP-PLAYBOOK → PHASE-1 | `gsc-extract.ts` → `striking-distance.ts` → `redirect-chain-audit.ts` |
| "shipping locations/templates/comparisons/integrations pages" | `programmatic-launch-review` | PROGRAMMATIC-GATES → PHASE-3 → ANTI-PATTERNS | `crawl.ts` (sample) → `validate-schema.ts` → `serp-snapshot.ts` |
| "domain change", "rebranding", "framework rewrite" | `migration` | MIGRATION-CHECKLIST → REDIRECT-PLAYBOOK | `redirect-chain-audit.ts` → `sitemap-audit.ts` → `crawl.ts` (before+after) |
| "AI Overview", "AI Mode", "ChatGPT cites", "Perplexity", "LLM citation" | `ai-visibility-pass` | AI-VISIBILITY → CITATION-OPS → GEO-MEASUREMENT → WIRING-OBSERVABILITY → OPERATORS | `ai-crawler-view.ts` → `entity-consistency-check.ts` → `serp-snapshot.ts` |
| "fix INP", "Core Web Vitals", "page speed" | implementation | INP-DEEP-DIVE → IMAGE-PERF-COOKBOOK → PAGE-WEIGHT | `cwv-check.ts` → `cwv-by-component.ts` → `crux-collect.ts` |
| "schema", "rich results", "structured data" | implementation | SCHEMA-COOKBOOK → SCHEMA-POLICY | `validate-schema.ts` |
| "international", "hreflang", "localization" | implementation | HREFLANG-COOKBOOK | `hreflang-validator.ts` |
| "OG images", "Twitter cards", "social previews broken" | implementation | (sibling skill `og-share-images`) | `og-image-audit.ts` |
| "robots.txt", "AI bots", "blocking crawlers", "GPTBot" | policy | AI-BOTS-AND-LLMSTXT → AI-VISIBILITY → CRAWL-BUDGET → NEXTJS-PATTERNS | `ai-bot-policy-check.ts` → `llms-txt-validator.ts` → `ai-crawler-view.ts` |
| "low-hanging fruit", "ranking 8-15", "boost CTR" | tactical | STRIKING-DISTANCE-PLAYBOOK | `gsc-extract.ts` → `striking-distance.ts` → `serp-snapshot.ts` |
| "duplicate content", "cannibalization" | content | CONTENT-INVENTORY-OPS → ANTI-PATTERNS | `crawl.ts` → (manual diff or future `cannibalization-embeddings.ts`) |
| "author bios", "E-E-A-T", "expertise signals" | trust | AUTHORSHIP-AND-EEAT → TRUST-INFRASTRUCTURE | `entity-consistency-check.ts` |
| "deploy SEO changes", "ship to prod" | deploy | PHASE-11-DEPLOY → PHASE-12-VERIFICATION | `verify-prod.ts` |
| "monthly report", "weekly check-in" | reporting | DELIVERABLES-INDEX → assets/MONTHLY-EXEC-TEMPLATE | `gsc-extract.ts` → `crux-collect.ts` |

If no match, fall through to SKILL.md MODE ROUTER.

---

## STEP 2 — Confirm the working surface (do this before writing)

1. Where is the project? Path or `.git` URL.
2. Is there already a branch named `seo-pass/*`? Use it. Otherwise propose one.
3. Does `analyses/` exist at repo root? Create it on first script run.
4. Are GSC, GA4, CrUX API keys/service-accounts available? See `WIRING-OBSERVABILITY.md`.

**Stop and ask** if any of these are unknown. Do not invent.

---

## STEP 3 — Always emit a Decision Card per recommendation

Every change you propose gets one card from `assets/DECISION-CARD.md`:
- Hypothesis · Expected impact · Tracking plan · Rollback path · Owner · Ship-by · Recheck-by

Without these fields filled, the recommendation is not done.

---

## STEP 4 — Idempotence and resumption

- Scripts write to predictable paths under `analyses/` — see `ANALYSES-LAYOUT.md` and `SCRIPT-IO-CONTRACTS.md`.
- Re-running a script overwrites by default. To preserve a snapshot, copy the file before re-running or pass `--output <path>`.
- A `seo-changelog.md` at repo root tracks every shipped change. Read it before starting; append after every PR merges.

---

## STEP 5 — Verify before claiming completion

- For implementation work: run the relevant verification script (`verify-prod.ts`, `validate-schema.ts`, `hreflang-validator.ts`).
- For content work: run `de-slopify` (sibling skill) on every drafted page.
- For programmatic launches: PROGRAMMATIC-GATES checklist, top to bottom.
- For migrations: redirect-chain audit before AND after launch, on the same URL set.

---

## Failure recovery — most common errors

| Symptom | Likely cause | First fix |
|---|---|---|
| `bun: command not found` | Bun not installed | `curl -fsSL https://bun.sh/install \| bash`, restart shell |
| Script fails: `Could not resolve "playwright"` | Deps not installed | `bun install` in repo root, or `bun add -d playwright @playwright/test` |
| `crawl.ts` hits 30x in a loop | Site auth-walls or geo-blocks the UA | Pass a real-browser UA via `--user-agent`, or run from VPN |
| `cwv-by-component.ts` reports `dur=0` for every interaction | Selectors don't exist on the page being probed | Inspect the page in DevTools, update the selector list, re-run |
| `validate-schema.ts` reports `BAD_TYPE` but page renders fine | Mixed `@graph` shape — some validators don't unwrap | Read SCHEMA-COOKBOOK §3, normalize to single-`@graph` |
| `gsc-extract.ts` 401s | Service account not added to GSC property | Add the service account email as a user with at least `restrictedUser` role |
| `hreflang-validator.ts` flags AUTO_REDIRECT_TRAP on every URL | Site has a global www→apex or http→https redirect | Verify hreflang URLs match the canonical scheme/host; that's the real fix, not silencing the check |
| `ai-crawler-view.ts` shows empty body for ClaudeBot/GPTBot | Site renders client-side and blocks JS-less UAs | This IS the finding; fix is server-rendering critical content (see NEXTJS-PATTERNS) |
| `redirect-chain-audit.ts` says ">10 hops" | Genuine infinite-redirect loop or cookie-driven loop | Manually `curl -I -L --max-redirs 20`, find the cycle |
| `og-image-audit.ts` reports `OVER_SIZE_LIMIT` for next/og output | ImageResponse PNG too heavy — usually a chart or photo | Switch to JPEG via `responseHeaders` or downscale in the route |

If the symptom isn't here, search `OPERATORS.md` first (covers expert-level diagnostics), then inspect the relevant script's usage header before guessing.

---

## Anti-patterns the agent itself should avoid

1. **Don't recommend before discovering.** Phase 1 outputs are a precondition for Phases 4-6 recommendations.
2. **Don't quote third-party CTR/AIO percentages without a citation entry in `SOURCE-LOG-TEMPLATE.md`.**
3. **Don't introduce new score scales.** The skill standard is `0-1000`. Anything else is a bug.
4. **Don't write a "comprehensive SEO audit" markdown blob.** Emit one Decision Card per finding, sortable by severity.
5. **Don't run scripts without a representative URL set.** First Phase-1 task is producing `analyses/representative-urls.json`.
6. **Don't mix lab (Lighthouse) and field (CrUX) numbers without labelling.** Lab is for debugging; field is for ranking.
7. **Don't propose `FAQPage` rich result for marketing pages.** Rich result is restricted; use the schema for content only when accurate.
8. **Don't promise "ranking lift in N days" with confidence.** SEO outcomes are bandit + algorithm-dependent. Frame as hypotheses with tracking.

---

## Sibling skills you will likely call

| Need | Skill |
|---|---|
| Build OG images programmatically | `og-share-images` or `creating-share-images` |
| Polish AI-drafted prose | `de-slopify` |
| Generate hypotheses for SEO experiments | `idea-wizard` |
| Run the experiments | `ab-testing` |
| Deploy / Vercel ops | `vercel`, `vercel:deploy`, `vercel:nextjs` |
| Open the PR | `github`, `commit-and-release` |
| Static analysis on changed code | `ubs` |
| Wire analytics events | `ga4` |
| Repo with Supabase | `supabase` |
| UX review on landing pages | `ux-audit` |
| Cache strategy on Next.js 16 | `vercel:next-cache-components` |
| Performance optimization beyond INP | `extreme-software-optimization` |

If a sibling skill is not installed, install via `jsm install <skill>` if available; otherwise note the gap in `analyses/skill-availability.md` and fall back to manual.
