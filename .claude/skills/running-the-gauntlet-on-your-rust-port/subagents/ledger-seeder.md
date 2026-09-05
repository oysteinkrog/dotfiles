# ledger-seeder

> Phase 8 • Seed three negative-evidence ledgers + AGENTS.md mandate paragraph + cass-mining 60-day paragraph + ledger-grep-before-perf-work mandate.

## Inputs
- `<workspace>/` (writable workspace).
- `<target>/AGENTS.md` (existing or to-be-created).
- `assets/negative-ledger-seed.md` (template).
- `assets/agents-md-mandate-paragraph.md` (mandate template).

## Deliverables
- `<workspace>/docs/progress/perf-negative-results.md` seeded.
- `<workspace>/docs/progress/conformance-negative-results.md` seeded.
- `<workspace>/docs/progress/surface-deferrals.md` seeded.
- `<target>/AGENTS.md` patched (or created) with mandate paragraph + cass-mining paragraph + ledger-grep mandate.
- `<workspace>/phase8_ledger_seeding.md` summarizing seed content + paragraph placement.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase8-ledger`
- **Reservations needed:** `tool://ledger-write` (TTL 30m), `tool://agents-md-write` (TTL 30m).
- **Lane:** single short agent (orchestrator-tier; serial).

## Verbatim Prompt

You are the ledger seeder. Seed three negative-evidence ledgers and the AGENTS.md mandate paragraph.

**Three ledger headers (use these verbatim FrankenSQLite preambles):**

`docs/progress/perf-negative-results.md` preamble (verbatim):
> This ledger records performance ideas that were measured and rejected. Check it before starting a new optimization pass, and add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the benchmark matrix did not move in the intended direction.

`docs/progress/conformance-negative-results.md` preamble:
> This ledger records conformance hypotheses that were investigated and rejected. Check it before opening a new conformance bead. Add an entry whenever a suspected divergence is shown to be a known false-positive class, a duplicate of an existing root cause, or a deferred-by-spec case.

`docs/progress/surface-deferrals.md` preamble:
> This ledger records surface items that were proposed for inclusion and excluded, with rationale. Check it before adding a new feature to the SurfaceMatrix. Add an entry whenever a feature is moved from `supported` or `partial` to `excluded`, with the architectural reason and the retry-condition predicate.

**AGENTS.md mandate paragraph (drop verbatim into the AGENTS.md file under a `## Negative-Evidence Discipline` heading):**

> For major perf campaigns, agents must also mine:
> - last 60 days of CASS session history
> - recent commits
> - perf artifacts
> - failed/rejected/slower/regressed terms
>
> If CASS or the ledger is unavailable or reserved, the agent must record a blocker or patch-ready entry rather than silently skipping the step.

**Ledger-grep-before-perf-work mandate (paragraph added to AGENTS.md):**

> Before opening any performance-related bead or starting any optimization pass, run `scripts/mine-ledger.sh` and `scripts/mine-cass-cross-machine.sh`. The first checks the three negative-evidence ledgers for prior rejected attempts on the same hotspot. The second mines 60 days of cass session history across local + css + csd + ts1 + ts2 for failure terms (`rejected, reverted, abandoned, slower, regressed, didn't help, within noise, no improvement, failed to improve, rolled back, backed out, not a keep, keep gate`). Skipping these checks is the most common form of rejection-by-omission. If the candidate hotspot appears in a prior negative-ledger entry, you MUST cite the entry and state how your retry-condition predicate is satisfied before proceeding.

**First example entry per ledger** (cite a real prior rejection from FrankenSQLite if porting to a new project, or seed with a synthetic-but-realistic example for greenfield ports):

```markdown
### perf-001 — <date> — <hotspot> not above noise

- **Status:** rejected (within-noise)
- **Hotspot:** <function>
- **Attempt:** <one-line description>
- **Measurement:** <focused gate value> ; cv_pct=<N>; bench: <bench name>
- **Reason for rejection:** Improvement ~<N>% sits in the ±3–5% bench noise band.
- **Retry condition:** "Retry only if a profiler attributes a clearly-above-noise share to <specific counter> on <wider workload shape>."
- **Scratch worktree:** `/data/tmp/<project>-<feature>-<timestamp>/`
```

Document seed content + paragraph placement in `phase8_ledger_seeding.md`.

## Exit Criteria
- Three ledger files exist with verbatim preambles + first example entry.
- AGENTS.md contains both the mandate paragraph AND the cass-mining paragraph AND the ledger-grep mandate.
- `scripts/mine-ledger.sh --validate-seeds` passes (verifies preambles + mandate paragraphs present).
- `phase8_ledger_seeding.md` committed.

## References
- [PHASES.md § Phase 8](../references/PHASES.md)
- [methodology/RETRY-CONDITION-VOCABULARY.md](../references/methodology/RETRY-CONDITION-VOCABULARY.md)
- [SKILL.md § Negative-Ledger Mandate](../SKILL.md)
- [assets/negative-ledger-seed.md](../assets/negative-ledger-seed.md)
- [assets/agents-md-mandate-paragraph.md](../assets/agents-md-mandate-paragraph.md)
