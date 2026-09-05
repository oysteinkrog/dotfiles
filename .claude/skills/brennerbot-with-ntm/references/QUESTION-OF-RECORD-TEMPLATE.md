# QUESTION-OF-RECORD-TEMPLATE.md — Brenner Step-0 Framing

<!-- TOC: Required sections | Example: corpus-distillation mode | Example: code-investigation mode | Example: incident-investigation mode | Common framing failures | Self-test for the question of record -->

The question of record is the load-bearing artifact of Phase 1. Without it, every subsequent phase is shadow-boxing.

This template lives at `assets/templates/question-of-record-template.md` (copy-paste version). This file documents the *grammar* and *examples*.

---

## Required sections

Every `intake/question_of_record.md` must have these top-level sections (in this order, with these exact titles):

```markdown
# Question of Record — RS-<YYYYMMDD>-<slug>

## Question
<one sentence — the research question>

## Paradox
<2-3 sentences identifying the contradiction or open question that motivates this; per ◊ Paradox-Hunt operator>

## Falsifier
<what observation O, if seen, would prove (a) the question is malformed OR (b) is already answered>

## Scope
<bullet list of what's IN scope>

## Out of Scope
<bullet list of what's NOT in scope; equally important — this prevents Phase 4 drift>

## Mode
<one of: fresh-question | code-investigation | corpus-distillation | resume-session | methodology-drift-check | incident-investigation>

## Provenance
<where the question came from — user ask, prior session, paradox surfaced in corpus, incident, etc.>

## Stakes
<2-3 sentences: what depends on the answer; how would different verdicts change downstream actions>

## Initial paradox bead
<H-000 description if filed; the paradox itself becomes the first hypothesis bead>
```

---

## Example: corpus-distillation mode

```markdown
# Question of Record — RS-20260506-event-log-format

## Question
What is the best on-disk format for an append-only event log of events under 1KB each?

## Paradox
Industry consensus splits between (a) length-prefixed binary frames (Kafka, Pulsar) for throughput, and (b) JSONL (newline-delimited JSON) for tooling ergonomics. But there's a third class — content-addressed CBOR-of-FlatBuffers with a sparse offset index — that benchmarks comparably to (a) and tools comparably to (b). Why hasn't it taken over? Either (i) we're missing a deal-breaker, or (ii) it's a new-enough technique that the field hasn't caught up, or (iii) there's no actual best — the choice is workload-dependent and the question is malformed.

## Falsifier
If a literature/codebase survey produces a verifiable benchmark where format X dominates format Y by ≥10× on a workload that matches our target (≤1KB events, append-heavy, occasional random reads, no long retention), the question becomes "use format X" and is trivially answered.

If no such benchmark exists for any format pair across our workload class, the question is malformed (workload-dependent) and must be reframed per workload class.

## Scope
- Event size: 100B–1KB (median ~400B)
- Append rate: 10K–100K events/sec
- Retention: 30–90 days
- Read pattern: 99% sequential append, 0.5% recent-tail seek, 0.5% offset-by-id
- Storage: NVMe + S3 cold tier
- On-disk binary format proposals (with optional metadata sidecar)
- Comparison metrics: ingest throughput, on-disk size after compression, p99 read latency, tooling support (cat / grep / index rebuild), schema evolution

## Out of Scope
- Distributed coordination (replication, leader election) — we assume single-writer
- Encryption at rest — orthogonal layer
- Log compaction / squashing — separate concern
- In-memory representation (we care about on-disk only)
- Streaming protocol (Kafka wire format vs gRPC) — this is the *file* format question

## Mode
corpus-distillation

## Provenance
User ask, motivated by an upcoming append-only event log redesign in project Z. Paradox identified by the user reading the format-comparison literature and finding the same 3 formats benchmarked top in different papers.

## Stakes
This decision will be in the hot path of project Z's event ingestion (10K events/sec target) for ≥2 years. Migration cost from the wrong choice is ~6 weeks of engineering. Different verdicts route to different code structures (frame parser vs JSONL-stream vs CBOR-of-FlatBuffers).

## Initial paradox bead
H-000 (origin: anomaly_spawned): "There exists an objectively-best format for this workload class, but the field hasn't agreed on it because evaluations are workload-mismatched."
```

---

## Example: code-investigation mode

```markdown
# Question of Record — RS-20260506-asupersync-arch-audit

## Question
Where are the load-bearing weaknesses in asupersync's region-scheduler design that would prevent it from outperforming Tokio on a multi-tenant workload at scale?

## Paradox
asupersync claims O(1) wakeup-cost and zero-copy region transitions, while Tokio's runtime overhead is well-documented at >1µs per task wake. If asupersync's claims hold, it should dominate Tokio on every benchmark. But our internal benchmarks show asupersync trailing Tokio on certain multi-tenant workloads. Either the claims are unconditional (and benchmarks are wrong), or there's a workload-dependent failure mode the design literature hasn't surfaced.

## Falsifier
If a code-level audit of asupersync's region scheduler produces a specific code path that demonstrably violates the O(1) wakeup-cost claim under multi-tenant conditions, the design is constrained.
If no such code path exists, the benchmark discrepancy is in the harness, not the runtime.

## Scope
- asupersync's region scheduler (region/, scheduler/, executor/ modules)
- Wakeup cost path: from event ready → task wake → task poll
- Multi-tenant workload: ≥4 logical tenants sharing the runtime
- Comparison surface: Tokio's current task wake path

## Out of Scope
- I/O drivers (epoll, io_uring) — orthogonal
- API ergonomics — design audit, not API audit
- Tokio's internals beyond what's needed for comparison
- Single-tenant performance (already measured)

## Mode
code-investigation

## Provenance
Internal benchmark report from project asupersync; user requests independent design audit before adopting in production.

## Stakes
This decision gates whether to migrate hot-path services from Tokio to asupersync. Wrong call costs 6+ weeks. Right call yields measured 2× p99 reduction.

## Initial paradox bead
H-000: "asupersync's wakeup-cost is workload-dependent — multi-tenant conditions trigger a specific code path that re-introduces O(N) scheduling decisions."
```

---

## Example: incident-investigation mode

```markdown
# Question of Record — RS-20260506-payment-double-charge

## Question
What is the root cause of the payment double-charge incident affecting 47 customers between 14:00 and 14:23 UTC today?

## Paradox
Stripe's webhook idempotency should prevent double-charges. But our logs show 47 instances where the same `charge.succeeded` event appears to have triggered two ledger writes. Either Stripe sent the event twice (violating their idempotency promise) or our handler isn't actually idempotent.

## Falsifier
If the Stripe Dashboard shows 47 distinct `evt_*` IDs for the same payment_intent_id, the duplicate is on Stripe's side (extremely unlikely; would be a major Stripe incident).
If the handler ingest log shows the same `evt_*` ID processed twice, our idempotency layer is broken.

## Scope
- The 47 affected payments (customer IDs, payment_intent_ids, charge IDs)
- The webhook handler code path (ingest → dedup → ledger write)
- The 14:00–14:23 UTC window
- Recent (last 24h) deploys that touched the handler

## Out of Scope
- Customer communication (separate workstream)
- Refund processing (separate workstream)
- Long-term hardening (post-mortem)

## Mode
incident-investigation

## Provenance
PagerDuty alert at 14:25 UTC; on-call engineer escalated.

## Stakes
Direct customer harm (47 double-charged customers). Refund + apology in flight. Need root cause within 60 min to prevent further bleeding.

## Initial paradox bead
H-000: "Our idempotency layer was bypassed for 47 events between 14:00 and 14:23 UTC due to <unknown root cause>."
```

---

## Common framing failures

| Framing failure | Recovery |
|-----------------|----------|
| Question too broad ("design the future of X") | Force scope/out-of-scope; if can't fill out-of-scope, the question is malformed |
| No falsifier ("when we know") | Demand observable falsifier; refuse to exit Phase 1 without one |
| Mixed modes (corpus + code) | Split into ≥2 sub-questions, each framed individually with its own mode |
| Stakes too vague ("would be good to know") | Demand: "what action depends on the answer?" If no action depends, downgrade priority — likely curiosity, not research |
| Provenance missing | Operator must record where the question came from (user ask, prior session, paradox in corpus) — keeps drift-check honest |

---

## Self-test for the question of record

After writing it, ask:

1. **Could a hostile reader misread "Out of Scope"?** If yes, sharpen.
2. **Is the falsifier observable in <1 hour by an investigator?** If no, the falsifier is too abstract — make it concrete.
3. **Could two reasonable people disagree on what "Scope" means?** If yes, sharpen.
4. **Does the paradox actually motivate the question, or is it post-hoc?** If post-hoc, the question may not be a research question — it might be a curiosity.
5. **What action changes if the answer is X vs Y vs Z?** If no action changes for some answer, the question may be incomplete.

If any of (1)–(5) fails, return to MO-01-frame-question.md and tighten before exiting Phase 1.
