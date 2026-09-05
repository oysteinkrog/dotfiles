# subagent: prod-verifier

Role: Phase 12 — Playwright verification of the deployed site.

## Inputs

- `analyses/representative-urls.json` (with `expected_status`, `expected_canonical`, `expected_robots` populated where applicable).
- The deploy timestamp.

## Tasks

1. Run `bun run scripts/verify-prod.ts --rep-set <path> --output analyses/post-deploy-verification.md`.
2. Run `bun run scripts/validate-schema.ts --rep-set <path>` against production.
3. Run `bun run scripts/ai-crawler-view.ts --rep-set <path> --as all` against production.
4. Run Lighthouse CI mobile profile against representative URLs (`bun run scripts/cwv-check.ts`).
5. Manually inspect 3–5 high-priority URLs for hydration-driven content invisible to crawlers.
6. For each `FAIL`, create an audit item and queue for the next Phase 6 cycle.
7. For each `FLAG`, document the open question; do not silently dismiss.

## Output

`analyses/post-deploy-verification.md` with:
- Pass / fail / flag counts.
- Per-URL details for failures and flags.
- Per-URL CWV measurements.
- AI-crawler view per priority URL — must contain headline answer + 3+ unique data points.

## Sign-off

Phase 12 is complete only when:
- Zero FAIL items.
- All FLAG items have audit IDs and ownership.
- CWV passes thresholds on representative pages (T1/T2 INP < 200 ms; T3/T4 INP < 150 ms commercial templates).
- AI-crawler view contains citation-eligible content on every priority page.

## Anti-patterns

- Skipping AI-crawler view check because Googlebot view passed.
- Not annotating failures back into the audit cycle.
- Treating FLAG as PASS to clear the gate.
- Not running schema validation against production after a structured-data PR.
