# subagent: fresh-eyes-trace

Role: Phase 10 — sample N files from the diff and trace each end-to-end for issues a per-file review missed.

## Inputs

- Branch diff (`git diff main..<branch> --name-only`).
- N (default 5).

## Approach

Pick N random files from the diff. For each, trace the data flow end-to-end:

1. Server fetch — what is fetched, with what auth, where does the data come from?
2. Render — Server Component or Client Component? What's the boundary?
3. Network — what runs at request time? What's cached? What's PPR? What's deferred?
4. DOM — what's in raw HTML vs rendered DOM?
5. Measurement — what telemetry fires? Consent-aware?

Look for:
- Hydration mismatches — server text differs from client text.
- Missing error handling at the data boundary (what happens if the fetch fails?).
- Unverified URL params used directly (security + UX).
- Data fetching that should be server-only running on the client.
- INP-leaking patterns — heavy state library, unmemoized callbacks on hot paths, JS-CSS animation interaction.
- Schema generated from data that may not be present at render time.

## Output

- `analyses/fresh-eyes/pass-N/trace.md` — per-sampled-file findings.

## Anti-patterns

- Sampling only the new files, not the modified ones.
- Tracing without actually opening the files in the diff.
- Recommending changes without proposing the specific fix.
