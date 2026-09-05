# HANDBACK-VOICE-GUIDE.md — Writing the One-Page Operator Briefing

<!-- TOC: Why voice matters | Voice characteristics | Verdict-first structure | Citation density | Hedging vs assertion | Imperative vs declarative | Bullets vs prose | Comparative anti-patterns | Worked HANDBACK examples | Editing pass | Line-by-line tightening | Composition with EXEMPLARS -->

Per documentation-website-for-software-project's WRITING-CRAFT.md adapted for the Phase 9 deliverable. The HANDBACK is ≤80 lines and is the user's first read after Phase 8 freeze. Its voice determines whether the user acts on the recommendation or files it for later.

---

## Why voice matters

Brennerbot produces evidence; HANDBACK communicates the verdict. Even a methodologically-flawless session lands flat if the HANDBACK reads like:

- An academic paper (passive voice, hedged conclusions, citation cascade)
- A consultant deliverable (recommendations buried in framing)
- A status report (chronological, no recommendation)

The HANDBACK should read like:

- An expert friend giving you their best read on the question, with specific citations to back it up

Per Brenner's own brief style (per EXEMPLARS.md), the voice is:
- Direct: front-load the verdict
- Evidence-grounded: cite specific EVs with verbatim quotes
- Acknowledged-uncertainty: state confidence and caveats
- Action-oriented: tell the user what to do next

---

## Voice characteristics

### Direct (not hedged)

✗ "It would seem that approach A might possibly be preferable to approach B under certain conditions."

✓ "Approach A is preferable for our regime (workload class W, scale 100k QPS). Specifically: under EV-014's benchmark and our 6-month load forecast, A's p99 stays below 200ms; B's grows linearly past 350ms."

The first version sounds smart; it's actually empty. The second has the same uncertainty (it's still bounded to "our regime") but commits to a verdict.

### Specific (not abstract)

✗ "We found significant performance issues."

✓ "Phase 4 round 3 round-trip benchmark on `/api/checkout` showed p99 = 450ms vs 80ms baseline (EV-019). Root cause: connection pool saturation at 95% under traffic > 5000 req/s (EV-022)."

Numbers, file paths, EV citations. The reader can verify.

### Honest (about uncertainty)

✗ "We are confident the answer is X."

✓ "Confidence: medium. Load-bearing assumption A-007 (memory bandwidth ≥ 100GB/s) was verified by EV-018 but not replicated by us; if the assumption is wrong, the verdict flips. Re-verification recommended at 6mo cadence."

State the confidence; state the load-bearing assumption; state the conditions that would flip the verdict.

### Imperative (when actionable)

✗ "Consideration should be given to migrating the database."

✓ "Migrate the database to PostgreSQL 16 by 2026-08-01. Migration plan in DECISION-MEMO.md. Rollback plan in section 4."

Tell the user what to do, when, and where to find the details.

---

## Verdict-first structure

```
# HANDBACK — <Session ID>

**Verdict:** <one-line>
**Confidence:** <high | medium | low>
**Action recommended:** <one-line>

## Reasoning (3-5 sentences)
<load-bearing argument with specific EV-NNN citations>

## What's still open
- <H-NNN: status>; next-action: <specific>
- <EV-NNN: deferred verification>; next-action: <specific>

## Top 3 risks
1. <risk> — <mitigation>
2. <risk> — <mitigation>
3. <risk> — <mitigation>

## Cited evidence (top 3 by W_composite)
- EV-NNN (W=0.85): <verbatim quote> — <source>
- EV-NNN (W=0.72): <verbatim quote> — <source>
- EV-NNN (W=0.70): <verbatim quote> — <source>

## Provenance
Workspace: <path>
Session: <ISO>
Tier: T<N>
Roster: <Solo/Pair/Squad/Swarm>
Wall time: <H>h
Phase 7 audit: <converged-after-N-rounds | open-with-caveats>
Phase 10 drift: <verdict>
```

≤80 lines. The user reads top-down; if they stop after "Verdict + Action recommended", they have enough to act.

---

## Citation density

Per CRITIQUE-CRAFT.md and EVIDENCE-WEIGHTING-TAXONOMY.md, citations are load-bearing. In the HANDBACK:

- "Reasoning" section: ≥3 specific EV-NNN cites
- "Top 3 risks": each tied to specific assumption (A-NNN) or hypothesis (H-NNN)
- "Cited evidence": top 3 by composite W

Don't pad with citations; cite where claim load is highest.

### Bad citation density

> "We investigated several factors and concluded X."

(Zero citations; reader can't verify.)

### Good citation density

> "Phase 4 round 4 measured network round-trip = 220ms p99 (EV-019, replicated EV-024); the 200ms SLO target requires < 200ms total budget; therefore the 'pure-network' diagnosis is supported. The application-level alternative (H-005) was refuted by EV-018 (CPU profile shows < 5ms application time)."

(Three EV cites; specific numbers; refutation cited.)

---

## Hedging vs assertion

Hedge ONLY when uncertainty is real:

✓ Hedge: "If our forecasted scale (10× current) doesn't materialize within 12 months, the recommendation may be premature."

✗ Hedge for diplomacy: "Some might argue that approach A could be considered as one possibility..."

When you're uncertain, say so AND say what would resolve the uncertainty:

> "Confidence in H-005 is medium. Required to upgrade to high: independent replication of EV-018's microbenchmark by a different team within 4 weeks."

---

## Imperative vs declarative

For action recommendations: imperative.

✓ "Migrate to PostgreSQL 16 by 2026-08-01."
✗ "Migration to PostgreSQL 16 is recommended."

For factual statements: declarative.

✓ "p99 latency on `/api/checkout` is 450ms (vs 80ms baseline)."
✗ "It is observed that p99 latency... [appears to be] 450ms."

For uncertainty: explicit.

✓ "We don't know whether the bandwidth saturation persists at 1M QPS."
✗ "It is unclear whether the bandwidth saturation persists at 1M QPS."

---

## Bullets vs prose

Bullets work for:
- Lists of risks (parallel structure)
- Action items with owner + deadline
- Open threads with next-action

Prose works for:
- Reasoning chain (argument flow)
- Caveats with conditions
- Cross-session context

A HANDBACK uses both. Don't bullet-everything ("bulletization"); don't prose-everything (walls of text).

### Bad bulletization

> Verdict:
> - We recommend X
> - Because of Y
> - And Z

### Good mix

> Verdict: Recommend X.
>
> Reasoning: Y holds because Z (EV-014). Alternative X' was refuted (EV-019). Load-bearing assumption: scale stays below 100k QPS for next 6 months.
>
> Risks:
> 1. ...

---

## Comparative anti-patterns

| ✗ | ✓ |
|---|---|
| "There are some considerations..." | "Three considerations:..." |
| "It is widely understood..." | "Per EV-014 (Smith 2024 §3.2):..." |
| "We came to the conclusion that..." | "Verdict:..." |
| "Multiple sources support..." | "EV-014, EV-019, EV-022 support..." |
| "The data suggests..." | "Phase 4 measurements show p99=450ms (EV-019)..." |
| "Various tradeoffs exist..." | "Tradeoff: A maximizes throughput at cost of memory; B reverses." |
| "It would be advisable to..." | "Migrate by 2026-08-01." |
| "Could potentially impact..." | "Will impact: per H-005 mechanism, X drops by Y%." |
| "Best-effort..." | "≥99.9% under workload W (per SLO budget)." |

---

## Worked HANDBACK examples

### Example A: Code-investigation handback

```
# HANDBACK — RS-2026-05-12-checkout-latency

**Verdict:** Database connection pool saturation is the load-bearing factor. Increase pool from 20 to 60 connections.
**Confidence:** high
**Action recommended:** Update `src/db/pool.ts` line 14 to MAX_CONNECTIONS=60. Deploy to staging by 2026-05-13. Production rollout 2026-05-15 if staging shows p99 < 200ms.

## Reasoning

Phase 4 round 4 isolated the regression to connection-pool exhaustion. Under load > 5000 req/s, all 20 pool connections become busy; new requests queue (EV-022 timeline trace). Increasing to 60 connections eliminates the queue under our forecast peak (EV-027 stress-test). The competing hypothesis "downstream latency" was refuted by EV-018 (downstream p99 stable at 30ms). The "GC pause" hypothesis was refuted by EV-014 (no GC events in regression window).

## What's still open

- H-008 (memory pressure at 60 connections): next-action — monitor heap usage in staging for 48h
- A-007 (workload stays below 10k req/s): next-action — re-verify in 90 days

## Top 3 risks

1. **Underprovisioned DB CPU at 60 connections**: each connection holds ~50MB; total memory use rises to ~3GB. Mitigation: confirm DB instance has ≥8GB headroom; current capacity 16GB.
2. **Pool exhaustion at 50k req/s (10× current)**: doesn't manifest now but will at forecast scale. Mitigation: add read-replicas for SELECT-heavy traffic (Q3 2026).
3. **Connection leak from buggy client code**: would re-introduce regression. Mitigation: existing connection-tracker telemetry detects leaks; alert is configured.

## Cited evidence (top 3 by W_composite)

- EV-022 (W=0.91): "All 20 pool connections in use; 47 requests queued at 14:23:14" — `application-logs/checkout-pool-saturation.log`
- EV-027 (W=0.83): "p99 = 145ms at 5000 req/s with pool=60" — staging stress-test 2026-05-12 16:00 UTC
- EV-018 (W=0.78): "Downstream service p99 stable at 30ms ±5ms across regression window" — Datadog query `service:payment-gateway`

## Provenance

Workspace: /home/ubuntu/brennerbot_sessions/RS-2026-05-12-checkout-latency
Session: RS-2026-05-12-checkout-latency
Tier: T2
Roster: Pair (cc + cod)
Wall time: 4.5h
Phase 7 audit: converged after 2 trio-rounds
Phase 10 drift: convergent (1 lesson committed: F-401 false positive on "downstream first" — added to OPERATOR-CALIBRATION-LOG)
```

(67 lines. Under 80. Verdict in line 3. Action item in line 5. Reasoning in 5 lines. Risks specific and actionable.)

### Example B: Decision-memo handback (A7 archetype)

```
# HANDBACK — RS-2026-04-22-storage-choice

**Verdict:** Stay on PostgreSQL with logical-replication tuning + read replicas (option B). Defer migration to Citus or ScyllaDB.
**Confidence:** high
**Action recommended:** Implement logical-replication tuning per ADR-2026-04-22-postgres-tuning.md. Add 2 read-replicas by 2026-06-01. Re-evaluate at 2027-Q1 if scale forecasts revise upward by ≥3×.

## Reasoning

The proposed migration to ScyllaDB (option C) was the user's prior, but Phase 6 distillation refuted it: ScyllaDB's claim of "10× write throughput" doesn't hold at our query mix (95% read, 4% range-scan, 1% write — see EV-031). Citus (option D) addresses our scale concerns at a 3× operational cost (EV-040). Tuning current PostgreSQL deployment (option B) closes the gap at 0.4× the cost (EV-038). Stay-and-tune is load-bearing; migration is premature.

## What's still open

- A-014 (assumption: 12-month scale forecast holds): next-action — review at 2027-Q1
- H-009 (multi-region requirement at 24-month forecast): next-action — Phase-1-reframe in 18 months

## Top 3 risks

1. **Scale forecast revisions**: if customer growth accelerates beyond current model, decision flips. Mitigation: quarterly review with growth team.
2. **PostgreSQL upgrade cycle**: 2-year-out major version may force migration. Mitigation: track release notes; budget Q1 of upgrade year.
3. **Tuning failure mode**: tuning may not deliver projected benefit at 100k QPS. Mitigation: ADR commits to staging benchmark before rollout.

## Cited evidence (top 3 by W_composite)

- EV-031 (W=0.88): "ScyllaDB write-throughput claim verified for 100% write workload only; degrades sub-linearly for read-mixed workloads" — Patel et al. 2024 §5.4 + our replicated benchmark `analyses/scylla-replication`
- EV-040 (W=0.81): "Citus operational cost: 3 dedicated DBA hours/week + cross-shard query rewriting" — internal Citus PoC docs (S-014)
- EV-038 (W=0.79): "PostgreSQL pg_stat_statements + autovacuum_naptime tuning at our workload reduced p99 by 35%" — `analyses/postgres-tuning-experiment`

## Provenance

Workspace: /home/ubuntu/brennerbot_sessions/RS-2026-04-22-storage-choice
Session: RS-2026-04-22-storage-choice
Tier: T3
Roster: Squad (cc:2, cod:1, gmi:1)
Wall time: 7h
Phase 7 audit: converged after 2 trio-rounds
Phase 10 drift: convergent

## Cross-session note

Reconciled with prior session RS-2026-02-15-db-evaluation (Type 4 — methodology evolved): per RECONCILIATION-MEMO.md, this verdict supersedes the earlier "ScyllaDB feasible" reading because Phase 7 audit applied falsifier-grading that the prior session skipped.
```

(74 lines. Verdict surfaces user's prior was refuted. Specific evidence cited with composite W.)

---

## Editing pass

After drafting, run a 5-minute editing pass:

1. **Line 1-3**: verdict + confidence + action — readable in 10 seconds?
2. **Reasoning**: ≥3 EV cites? Specific numbers? No vague language?
3. **Risks**: each tied to specific assumption? Each has mitigation?
4. **Cited evidence**: composite W shown? Verbatim quotes?
5. **Total lines**: ≤80? If over, compress (don't extend).

Cut anything that doesn't earn its tokens.

---

## Line-by-line tightening

Common compressions:

| Before | After |
|--------|-------|
| "We have come to the conclusion that..." | "Verdict:" |
| "It is our recommendation that you..." | "[imperative verb]" |
| "The data appears to indicate..." | "Per EV-NNN:" |
| "There are several factors that we considered..." | "Three factors:" |
| "It is important to note that..." | (delete; just say it) |
| "We thought it would be helpful to..." | (delete) |
| "In conclusion..." | (delete; the verdict is at the top) |

---

## Composition with EXEMPLARS

Per EXEMPLARS.md quote bank:

- **Dijkstra-style**: imperative + assertive ("X is wrong because Y.")
- **Knuth-style**: dense citation + step-by-step proof
- **Brenner-style**: terse + specific + paradox-aware

The HANDBACK can borrow from all three depending on the audience. For executives: Dijkstra. For peers: Knuth. For research: Brenner.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Bury verdict on line 30 | User stops reading at line 5 if no verdict |
| Hedge with "perhaps", "possibly", "might" | If you're uncertain, state it explicitly with a flip-condition |
| Cite "various sources" without specifics | Reader can't verify |
| Treat the HANDBACK as a process narrative | The user wants the answer, not the journey |
| Use jargon without defining (or linking) | Reader unfamiliar with brennerbot terms can't act |
| Skip the "what would change my mind" caveat | The verdict has implicit uncertainty; surface it |
| Pad to fill 80 lines | If the verdict + reasoning fits in 30 lines, keep it 30 |
| Put cited evidence after a long preamble | Front-load citations |
| Skip the "next-action" for open threads | Reader doesn't know what to do |

---

## When to escalate to longer formats

If the question warrants more than 80 lines:

- **DECISION-MEMO.md** for A7-archetype decisions (per `assets/templates/decision-memo-template.md`)
- **THREAT-CATALOG.md** for A6-archetype audits (per `assets/templates/threat-catalog-template.md`)
- **POST-MORTEM-REPORT.md** for incident-formalization (per `assets/templates/post-mortem-template.md`)

The HANDBACK is the entry point; longer artifacts are referenced and can be skipped if the user just needs the verdict.

---

## Cross-references

- EXEMPLARS.md (voice exemplars from research literature)
- DOMAIN-RECIPE-LIBRARY.md (per-recipe HANDBACK adjustments)
- EVIDENCE-WEIGHTING-TAXONOMY.md (composite W for citations)
- CRITIQUE-CRAFT.md (specificity in cited evidence)
- documentation-website-for-software-project's WRITING-CRAFT.md (broader voice guide)
