# pattern:180-NEGATIVE-LEDGER

## What

Three durable, git-committed markdown ledgers — one per pillar — that record every optimization or behavior-change idea that was *measured and rejected*. The ledgers are an output of the gauntlet, not a side-effect: they are mined before any new campaign starts, and every campaign that fails to load them is required to record a blocker entry. The three files are:

- `docs/progress/perf-negative-results.md`
- `docs/progress/conformance-negative-results.md`
- `docs/progress/surface-deferrals.md`

A rejected idea is data that costs hours to produce; the ledger is the bank where that data is preserved so the next agent doesn't repay the cost.

## Why

> "This ledger records performance ideas that were measured and rejected. Check it before starting a new optimization pass, and add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the benchmark matrix did not move in the intended direction." — CC.md lines 479–482 (verbatim, MINING-1 §3)

Failure mode prevented: *rerunning an experiment that already failed* — the most expensive form of session amnesia. Without a committed ledger, every new agent re-discovers that `chunks_exact` is slower than `as_chunks`, that the planner's `env::var` calls are the bottleneck, that the prepared-statement cache key is overcooked. The ledger turns those discoveries into permanent capital and makes "rejection by omission" (anti-pattern from CC.md §40 #3) a CI-detectable offense.

## Where in FrankenSQLite

- `docs/progress/perf-negative-results.md` — 380 entries as of the bibles' freeze date
- `docs/progress/conformance-negative-results.md`
- `docs/progress/surface-deferrals.md`
- `AGENTS.md` — mandate paragraph that names all three
- `scripts/mine-ledger.sh` + `scripts/mine-cass-cross-machine.sh` — the enforcement scripts

## Verbatim shape

The mandatory entry fields (from MINING-1 §3 + CODEX.md §10.2):

```
### <ISO date> — <short title> — <status>

- **Hypothesis:** <what the agent thought would help>
- **Workload(s) probed:** <focused workload + broad bench>
- **Measurement summary:** <focused gate result + broad gate result, both numeric>
- **Outcome:** rejected | reverted | abandoned | within-noise | correctness-abandoned
- **Scratch worktree:** /data/tmp/<project>-<feature>-<timestamp>
- **Profile evidence:** <flamegraph path, samply path, baseline.flame.svg path>
- **Retry-condition predicate:** <one of the 8 verbatim forms from pattern:185-RETRY-CONDITION-PREDICATE>
- **Bead id (if applicable):** bd-<id>
- **Commit (if attempted):** <sha or "uncommitted">
```

Mandate paragraph (from CODEX.md §10.2, lines 1464–1472, verbatim):

> For major perf campaigns, agents must also mine:
> - last 60 days of CASS session history
> - recent commits
> - perf artifacts
> - failed/rejected/slower/regressed terms
>
> If CASS or the ledger is unavailable or reserved, the agent must record a blocker or patch-ready entry rather than silently skipping the step.

Header rule (from CC.md opening, lines 479–482, verbatim):

> This ledger records performance ideas that were measured and rejected. Check it before starting a new optimization pass, and add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the benchmark matrix did not move in the intended direction.

## Per-class instantiation

| Class | Ledger naming | Pillar-specific fields beyond the universal set |
|---|---|---|
| SQL | `perf-negative-results.md`, `conformance-negative-results.md`, `surface-deferrals.md` | PRAGMA matrix used; SQLite version pinned; MT8 attribution self-time frame closed |
| RESP | same three names | RESP version (2/3); persistence mode (None/AOF/RDB); client-concurrency band |
| Numerical-Python | same three names | numpy version; SIMD flags; BLAS thread count; per-op ULP tolerance baseline |
| ML-System | same three names | torch/jax version; CUDA/MPS device; determinism flag state; per-op ULP table |
| HTTP-Protocol | same three names | framework version; routing config hash; middleware stack fingerprint |

The "patch-ready or blocker" rule when cass is unavailable: if `cass` is rate-limited, indexed-stale, or otherwise unreadable, the agent does **not** proceed silently. It writes either (a) a `patch-ready` entry that includes the candidate diff so a later agent can replay once cass is back, or (b) a `blocker` entry with a one-line description of the unavailability. Both forms count as ledger entries; neither is a pass.

## Composition

- Pairs with [pattern:185-RETRY-CONDITION-PREDICATE](185-RETRY-CONDITION-PREDICATE.md) — every entry's retry-condition field uses one of the 8 verbatim forms.
- Pairs with [pattern:190-CASS-MINING](190-CASS-MINING.md) — the 60-day cass grep is the second half of the mandate paragraph.
- Pairs with [pattern:195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md) — every entry's scratch-worktree and profile-evidence paths embed the run-identity tuple so the entry is replayable.
- Pairs with [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — the measurement-summary field cites both gates.

## Pitfalls

- **Entry without retry-condition predicate.** Pure prose without one of the 8 verbatim forms (see pattern:185) reads "rejected" but is unfilterable; future agents can't tell whether circumstances might have changed.
- **Ledger lives in PR description, not in `docs/progress/`.** The PR closes, the description rots into GitHub backwater, the ledger is effectively gone. Must be a committed file in the repo tree.
- **Ledger entry without scratch-worktree path.** "Tried this, didn't work" with no breadcrumb back to the code = unreproducible. The scratch-worktree path is the *evidence pointer*.
- **`mine-ledger.sh` not called as a perf-bead pre-flight.** The script's existence is irrelevant; what matters is that no bead enters phase 5+ without grep-output from it attached.
- **Silent skip when cass unavailable.** Every gauntlet that skipped the mining step without leaving a blocker entry has produced at least one wasted re-discovery in the FrankenSQLite ledger; the fix is the "patch-ready or blocker" rule.
- **Mistaking `correctness-abandoned` for `perf-rejected`.** The former earns a beads bug fix; the latter earns a ledger entry. Conflating them lets correctness bugs hide in the perf ledger.
- **Ledger entries that look like commit messages.** "Fixed planner to avoid env::var" is a commit message, not a ledger entry. The ledger documents what *didn't* work; what worked goes in `git log`.
