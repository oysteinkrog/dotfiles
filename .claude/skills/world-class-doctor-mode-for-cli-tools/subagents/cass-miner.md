# subagent: cass-miner (Phase 0)

**Description.** Mine the user's prior agent sessions for evidence about how the target CLI fails in real life, classified into SYMPTOM / ROOT_CAUSE / MANUAL_FIX / INCIDENT / WISH_THIS_EXISTED.

## Inputs

- `{{tool}}` — the binary name (e.g., `br`, `cass`, `am`)
- `{{workspace}}` — the doctor workspace directory

## Outputs

- `{{workspace}}/cass_findings.md` (human-readable)
- `{{workspace}}/cass_findings.jsonl` (one entry per line)

Each entry: `{quote, kind, source_path, agent, created_at, line_number, query}`. `kind` is one of `SYMPTOM | ROOT_CAUSE | MANUAL_FIX | INCIDENT | WISH_THIS_EXISTED`. `query` is the cass query that surfaced the quote (for reproducibility — matches the IO-CONTRACTS.md schema).

## Prompt

```
You are mining the user's prior agent sessions (via cass) for evidence about
how the target CLI {{tool}} fails in real life — not how its docs say it
fails. The doctor we are about to build absorbs this real-world experience.

Run these 13 canonical queries and capture the strongest 5–15 quotes per query, classified
by kind:

1. cass search "\"{{tool}} stale lock\"" --json --limit 20 --fields minimal
2. cass search "\"{{tool}} corruption\" OR \"{{tool}} corrupt\"" --json --limit 20 --fields minimal
3. cass search "\"{{tool}} migration\" failure" --json --limit 20 --fields minimal
4. cass search "\"{{tool}} race\" OR TOCTOU" --json --limit 20 --fields minimal
5. cass search "\"{{tool}} deadlock\"" --json --limit 20 --fields minimal
6. cass search "\"{{tool}} sqlite\" corruption" --json --limit 20 --fields minimal
7. cass search "\"{{tool}} jsonl\" tombstone OR drift" --json --limit 20 --fields minimal
8. cass search "\"{{tool}} undo\" OR \"{{tool}} restore\"" --json --limit 20 --fields minimal
9. cass search "\"{{tool}} crash\" recovery" --json --limit 20 --fields minimal
10. cass search "\"{{tool}} symlink\" TOCTOU OR traversal" --json --limit 20 --fields minimal
11. cass search "\"{{tool}} schema\" version mismatch" --json --limit 20 --fields minimal
12. cass search "\"{{tool}} cache\" stale" --json --limit 20 --fields minimal
13. cass search "\"{{tool}} had to manually\"" --json --limit 20 --fields minimal

For each strong quote, classify into one of:

- SYMPTOM: agent describes a broken state but not the cause
- ROOT_CAUSE: agent identifies why the broken state happened
- MANUAL_FIX: agent ran a sequence of commands to recover (these are GOLD —
  these are the exact playbook the doctor must absorb)
- INCIDENT: a specific past failure that hurt
- WISH_THIS_EXISTED: an explicit "if {{tool}} had X, this would be easy"

Save:
- `{{workspace}}/cass_findings.md` — Markdown with one section per kind, one
  quote per bullet, full citation (source_path, agent, created_at,
  line_number) per quote.
- `{{workspace}}/cass_findings.jsonl` — one JSONL entry per quote with the
  schema {quote, kind, source_path, agent, created_at, line_number, query}.

Do NOT invent quotes. If a query returns zero hits, record that fact in the
findings file under "Empty queries". An empty query is data — it tells us
the symptom isn't recurring in the user's experience.

Length budget: ~500 lines total. Tight. Quotes only, no commentary.
```

## Exit criteria

- `cass_findings.md` exists and is non-empty
- `cass_findings.jsonl` is valid JSONL (each line parses)
- At least one MANUAL_FIX entry, OR an explicit "no manual fix sessions found" note

## Failure modes

- `cass` not installed: emit a TODO to `<workspace>/cass_findings.md` ("install cass via `jsm install cass`") and proceed without findings.
- `cass health` reports unhealthy: write the diagnostic to `<workspace>/cass_findings.md` and proceed without findings.
- All queries empty: probably a new tool with no prior sessions — record explicitly so Phase 1 doesn't expect cass-mined FMs.
