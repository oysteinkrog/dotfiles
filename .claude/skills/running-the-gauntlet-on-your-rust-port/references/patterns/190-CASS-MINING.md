# pattern:190-CASS-MINING

## What

Before any major perf or conformance campaign, the agent runs a **60-day cass session-history grep** for failure terms, across the *local* cass index plus four cross-machine indices (`css`, `csd`, `ts1`, `ts2`), producing a deduplicated candidate-blocker report. The mining catches negative evidence that lives in past chat transcripts but never made it into the ledger — discoveries an earlier session made and abandoned without writing down. The grep is mandatory: an agent that cannot run cass (rate-limit, stale index, network down) must write a `blocker` or `patch-ready` entry, not silently proceed.

## Why

> "For major perf campaigns, agents must also mine: last 60 days of CASS session history, recent commits, perf artifacts, failed/rejected/slower/regressed terms. If CASS or the ledger is unavailable or reserved, the agent must record a blocker or patch-ready entry rather than silently skipping the step." — CODEX.md §10.2 (lines 1464–1472, verbatim)

Failure mode prevented: *the conversation that found the answer and lost it*. A prior session may have profiled the same hotspot, tried the same lever, and noted "that's actually doing N — surprise, it doesn't help" — but only in chat. The ledger captures the entries the agent thought to write down; cass mining captures the entries the agent forgot to. Skipping the mining step makes session amnesia permanent.

## Where in FrankenSQLite

- `CODEX.md` §10.2 (lines 1464–1472) — the mandate paragraph (verbatim above)
- `scripts/mine-ledger.sh` — local ledger grep
- `scripts/mine-cass-cross-machine.sh` — invokes cass on local + css + csd + ts1 + ts2
- The cass skill's "Cross-Machine Search" section — the canonical invocation pattern

## Verbatim shape — the mandate paragraph

From CODEX.md §10.2, lines 1464–1472, verbatim:

> For major perf campaigns, agents must also mine:
> - last 60 days of CASS session history
> - recent commits
> - perf artifacts
> - failed/rejected/slower/regressed terms
>
> If CASS or the ledger is unavailable or reserved, the agent must record a blocker or patch-ready entry rather than silently skipping the step.

## Universal failure-term list

Every campaign greps these strings against the last 60 days of cass:

```
rejected
reverted
abandoned
slower
regressed
didn't help
within noise
no improvement
failed to improve
rolled back
backed out
not a keep
keep gate
```

A hit on any of these in a past session, on the same code path, is grounds for an attached note before proceeding.

## Per-class instantiation — additional failure terms

| Class | Add to the universal list |
|---|---|
| SQL | `cold-start outlier`, `selections= mismatch`, `MT8 within noise`, `focused improved broad worsened`, `prepared-cache evict`, `cv_pct >5`, `PRAGMA drift`, `WAL frame mismatch` |
| RESP | `RESP frame mismatch`, `PUBSUB FIFO violation`, `AOF replay diverged`, `RDB checksum mismatch`, `cluster slot drift`, `expired-key sweep regression`, `keyspace notif missed` |
| Numerical-Python | `ULP exceeded`, `dtype promotion divergent`, `RNG stream desync`, `BLAS thread leak`, `SIMD masked`, `array view became copy`, `nan propagation differed`, `axis order rendered` |
| ML-System | `gradcheck failed`, `nondeterministic op caught`, `JIT cache miss spike`, `NCCL hang`, `CUDA OOM`, `MPS dtype unsupported`, `autograd tape diverged`, `bf16 underflow` |
| HTTP-Protocol | `OpenAPI schema drift`, `route-match rejected`, `middleware order flipped`, `validation error category changed`, `extractor zero-copy broke`, `connection pool starved` |

## Cross-machine search

Per the cass skill's Cross-Machine Search section, the canonical invocation pattern is:

```bash
# local
timeout 30s cass search "<term> AND <code-path>" --robot --days 60 --limit 50 --mode lexical --timeout 30000

# cross-machine — invoke via the four remote indices
ssh css 'timeout 30s cass search "<term>" --robot --days 60 --limit 50 --mode lexical --timeout 30000'
ssh csd 'timeout 30s cass search "<term>" --robot --days 60 --limit 50 --mode lexical --timeout 30000'
ssh ts1 'timeout 30s cass search "<term>" --robot --days 60 --limit 50 --mode lexical --timeout 30000'
ssh ts2 'timeout 30s cass search "<term>" --robot --days 60 --limit 50 --mode lexical --timeout 30000'
```

`scripts/mine-cass-cross-machine.sh` aggregates these into a single JSON; the result is committed under `<workspace>/phase8_cass_mining_<run_id>.json` and any hits on the targeted code path become attached evidence on the new bead before it enters Phase 5.

## Composition

- Pairs with [pattern:180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) — cass mining is the *implicit* ledger; the explicit ledger is its complement. New cass hits that aren't yet in the ledger should be promoted.
- Pairs with [pattern:185-RETRY-CONDITION-PREDICATE](185-RETRY-CONDITION-PREDICATE.md) — a cass hit on a prior failure should produce a ledger entry with a fresh retry-condition predicate, not a re-attempt.
- Pairs with [pattern:195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md) — every cass mining artifact embeds the gauntlet `run_id` + `commit_sha` so the mining is itself reproducible.
- Pairs with [pattern:150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md) — the cass mining output is required attached evidence on the 19-field proof-pack card.

## Pitfalls

- **Mining only the local index.** The four remote indices contain the productive sessions of the other machines in the cluster; skipping them throws away most of the cross-time evidence. The "Cross-Machine Search" rule is non-negotiable.
- **Searching only one failure term.** "rejected" alone misses every entry that said "didn't help" or "within noise"; the universal list of 13 terms exists for a reason.
- **Treating zero hits as the answer.** Zero hits on a hot code path is *suspicious*, not encouraging — the code path is famous enough that something should have been tried. Zero hits → re-run with a broader query or a different term list.
- **Silent skip when cass is rate-limited.** The mandate paragraph is explicit: blocker entry, not silent proceed.
- **Mining for a code path that doesn't exist in cass-searchable form.** If the function name is internal or recent, search for the surrounding crate or for the bead id under which it was added.
- **Not extending the failure-term list per class.** A FrankenRedis perf campaign searching only the SQL failure terms misses `RESP frame mismatch` and `cluster slot drift`; the per-class list is mandatory.
- **Treating cass mining as a one-time setup task.** It runs *per campaign*, not *per project*. Sixty days roll over; rejected ideas may become viable; the mining is fresh evidence every time.
