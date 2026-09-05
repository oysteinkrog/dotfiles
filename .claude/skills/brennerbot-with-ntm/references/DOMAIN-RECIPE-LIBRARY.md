# DOMAIN-RECIPE-LIBRARY.md — Cookbook Recipes per Question Shape

<!-- TOC: Why a recipe library | Recipe format | R1 backend system design | R2 algorithm choice | R3 perf investigation | R4 security audit | R5 ML/DS methodology | R6 distributed-systems debug | R7 API contract design | R8 data-pipeline integrity | R9 frontend perf | R10 storage selection | R11 auth/authz design | R12 reliability budget | R13 observability gap | R14 migration risk | R15 cost optimization | Recipe composition | Adding a recipe -->

Mirrors saas-billing's pattern-recipe library. Domain shape × archetype × tier combinations recur often enough to be cataloged. Each recipe is a *fast-start configuration* — not a full session script, but enough to skip 30-60 minutes of generic Phase 1-2 setup.

For new operators, recipes are training wheels. For experienced operators, recipes are reset state — when stuck, drop back to the recipe and re-run from a known-good baseline.

---

## Why a recipe library

Without recipes, every operator re-derives the same configuration:
- "Backend perf question → which roster?"
- "Security audit → which MO?"
- "ML methodology distillation → which corpus pattern?"

This burns 30-60 min per session in re-derivation. Worse: solo operators may pick a sub-optimal config and lock in for hours before realizing.

Recipes encode the cumulative wisdom of past sessions: "When Q is shape X, the optimal config is C." Save the bootstrap time; spend it on the actual investigation.

---

## Recipe format

Each recipe entry:

```
R<N>: <one-line title>

**Question shape:** <archetype × topical pattern>
**Typical tier:** T<N>
**Mode:** <mode from OPERATING-MODES.md or EXTENDED-OPERATING-MODES.md>
**Roster preset:**
  - cc: <count> [roles]
  - cod: <count> [roles]
  - gmi: <count> [roles]
**Pre-bootstrap actions:**
  - <action 1>
  - <action 2>
**Phase 1 framing emphasis:** <which F-phases of FRAMING-WORKBOOK to emphasize>
**Critical operators (per OPERATORS.md):** <which to apply at each phase>
**Common failure modes:** <F-### list with brief countermeasure>
**Composition with other skills:** <list per SKILL-COMPOSITION-PATTERNS.md>
**Wall-time estimate:** <H>h
**Sample question of record:** "<one-line>"
**Anti-patterns specific to this recipe:** <list>
```

---

## R1: Backend system design

**Question shape:** A1 design-space × backend system architecture
**Typical tier:** T3-T4
**Mode:** fresh-question or codebase-investigation
**Roster preset:**
- cc: 3 (Proposer, Investigator-1, Synthesizer)
- cod: 1 (Investigator-2)
- gmi: 1 (Devil's-Advocate / Adjudicator)

**Pre-bootstrap actions:**
- Run `/codebase-archaeology` if existing system
- Run `/cass search "<topic>"` for prior decisions
- Identify target SLO (latency p99, throughput, availability target)
- Identify constraint regime (compute budget, team headcount, technology stack)

**Phase 1 framing emphasis:**
- F2 stakes (decision is reversible? what's recovery cost?)
- F3 scope (workload class, time horizon)
- F8 constraints (technology stack, headcount, compute budget)

**Critical operators:**
- ⊞ Scale-Check (Phase 4 mandatory): does the design hold at 10× user count? At 100×?
- ⊕ Cross-Domain (Phase 3): import patterns from adjacent domains (queue theory, CAP, erasure coding)
- ✂ Exclusion-Test (Phase 4): falsifier-firing investigation

**Common failure modes:**
- F-101 (broad question) — force concrete workload class
- F-501 (Adjudicator never kills) — rotate via cross-family
- F-602 (single-family dominance) — force 3-family triangulation

**Composition with other skills:**
- /alien-graveyard for buried CS techniques
- /multi-pass-bug-hunting on prototype code
- /lean-formal-feedback-loop if formal correctness needed

**Wall-time estimate:** 3-5h (T3) or 6-10h (T4)

**Sample question of record:**
"Under workload class W (1M req/s, p99 ≤ 200ms, 99.99% availability), what is the load-bearing architecture choice that distinguishes a sound design from a fragile one?"

**Anti-patterns specific:**
- Skip ⊞ Scale-Check (designs that work at toy scale fail at production scale)
- Skip cross-domain ⊕ import (locks the swarm into consensus answers)
- Treat the design as one big blob H instead of decomposing into orthogonal H per concern

---

## R2: Algorithm choice (data structure / algorithm trade-off)

**Question shape:** A1 design-space × algorithmic trade-off
**Typical tier:** T2-T3
**Mode:** fresh-question
**Roster preset:**
- cc: 2 (Proposer, Investigator)
- cod: 1 (Devil's-Advocate)
- gmi: 1 (Synthesizer)

**Pre-bootstrap actions:**
- Identify the operations + their relative frequency (workload distribution)
- Identify the dataset characteristics (size, distribution, key cardinality)
- Per-candidate algorithm: known asymptotic complexity (per CS literature)

**Phase 1 framing emphasis:**
- F3 scope (operation mix, dataset shape)
- F5 falsifier ("at workload W with input X, the chosen algorithm produces sub-optimal result Y vs an alternative")

**Critical operators:**
- ⊞ Scale-Check (test at expected scale and 100× scale)
- ✂ Exclusion-Test (per-candidate elimination)
- 🔧 DIY (microbenchmark each finalist)
- ≡ Invariant-Extract (which invariants does each algorithm preserve?)

**Common failure modes:**
- F-301 (false binary, two algorithms only) — force ≥1 third-alternative including "use a hybrid"
- F-403 (confirmation bias on textbook answer) — flip Investigator to advocate

**Composition with other skills:**
- /alien-graveyard for buried algorithms
- /lean-formal-feedback-loop for correctness proof
- /testing-fuzzing on prototypes

**Wall-time estimate:** 2-4h (T2-T3)

**Sample question of record:**
"For a workload of 95% point-lookup, 4% range-scan, 1% insert, with key cardinality 10M, p99 latency ≤ 5ms, what's the load-bearing algorithm choice between B-tree, LSM-tree, hash-map, and Bloom-filter+secondary?"

**Anti-patterns specific:**
- Cite asymptotic complexity without empirical validation
- Skip cross-product analysis (operation × dataset × constraint)

---

## R3: Performance investigation (production system slowdown)

**Question shape:** A4 incident × performance regression
**Typical tier:** T2-T3 (live), T3-T4 (post-mortem)
**Mode:** incident-investigation initially, post-mortem-formalization for the lessons
**Roster preset:**
- cc: 2 (Investigator-1 timeline + code, Adjudicator)
- cod: 1 (Investigator-2 metrics + monitoring)
- gmi: 1 (Devil's-Advocate alternative explanations)

**Pre-bootstrap actions:**
- Verify access to production logs / dashboards / traces
- Identify the suspected regression window (commit range)
- Snapshot dashboard state at pin point
- Compose with /gdb-for-debugging if process is hung

**Phase 1 framing emphasis:**
- F1 trigger (when did this start? what changed?)
- F5 falsifier ("if metric X stays elevated under condition Y, hypothesis Z is wrong")
- F8 constraints (wall-time critical for incident; tight budget)

**Critical operators:**
- ⊞ Scale-Check (does the regression scale with traffic?)
- ∿ Dephase (decouple from "the obvious cause")
- ΔE Exception-Quarantine (separate incident-causers from incident-amplifiers)
- 🔧 DIY (run the suspected slow operation in isolation)

**Common failure modes:**
- F-301 (focus on first hypothesis without alternatives)
- F-403 (only confirming evidence)
- Time-pressure operator skipping Phase 7 audit

**Composition with other skills:**
- /gdb-for-debugging for live process inspection
- /profiling-software-performance for systematic perf attribution
- /system-performance-remediation for triage

**Wall-time estimate:** ≤60 min (live incident-investigation) + 4-6h (follow-up post-mortem)

**Sample question of record:**
"Starting 2026-05-10 14:23 UTC, p99 latency on /api/checkout rose from 80ms baseline to 450ms. What's the load-bearing factor among (a) deploy at 14:18, (b) traffic spike, (c) downstream service degradation, (d) database connection pool exhaustion?"

**Anti-patterns specific:**
- Conflate "this changed at the same time" with "this caused" (correlation ≠ causation)
- Stop at first plausible cause (always test ≥2 alternatives)
- Skip metric-based falsifier (intuition is not evidence)

---

## R4: Security audit (adversarial review)

**Question shape:** A6 adversarial × security audit
**Typical tier:** T3-T4 (T5 for compliance-critical)
**Mode:** red-team-only or pre-publication-review
**Roster preset:**
- cc: 2 (Reviewer-1, Reviewer-2 different sub-domains)
- cod: 1 (cross-domain attacker)
- gmi: 1 (Adjudicator + final audit)

**Pre-bootstrap actions:**
- Run `/security-audit-for-saas` for baseline checklist
- Run `/multi-pass-bug-hunting` on suspected modules
- Identify threat model (who attacks, what's the asset)
- Identify regulatory regime (PCI, HIPAA, SOC2, etc.)

**Phase 1 framing emphasis:**
- F2 stakes (likely impact in compromise scenarios)
- F4 paradox (every system has vulnerabilities — what makes THIS one worth attacking?)
- F5 falsifier ("if attack class X requires capability Y that the threat actor lacks, the scenario is moot")
- F7 corpus (existing security audits, CVE history, threat-intel reports)

**Critical operators:**
- ⊕ Cross-Domain (import attack patterns from adjacent systems)
- ◊ Paradox-Hunt (where do defenders' assumptions clash with reality?)
- ⊞ Scale-Check (what attacks are economical at our scale?)
- 🤝 GAN (Devil's-Advocate must be cross-family)

**Common failure modes:**
- F-501 (no critical findings = adjudicator capture)
- F-503 (rhetoric over evidence; demand specific PoC paths)
- F-705 (audit pane = synthesizer pane; cross-family check)

**Composition with other skills:**
- /security-audit-for-saas for systematic checks
- /multi-pass-bug-hunting for code-level audit
- /testing-fuzzing for input-class attacks
- /lean-formal-feedback-loop for crypto/protocol formalization

**Wall-time estimate:** 6-12h (T3); 3-5 days (T4); weeks (T5 with external review)

**Sample question of record:**
"For SaaS application X with threat model Y, what are the load-bearing security weaknesses ranked by severity × exploitability × business impact, and what remediations would reduce the threat surface by ≥50%?"

**Anti-patterns specific:**
- Treat audit as compliance paperwork (focus on adversary, not checklists)
- Skip threat model (without it, "secure" is undefined)
- Skip dual-use-review (per MO-dual-use-review.md) for findings disclosure

---

## R5: ML/data-science methodology distillation

**Question shape:** A3 methodology × ML technique
**Typical tier:** T3-T4
**Mode:** corpus-distillation or academic-replication
**Roster preset:**
- cc: 2 (Synthesizer-cc, Investigator-1)
- cod: 1 (Investigator-2 cross-domain framing)
- gmi: 1 (Synthesizer-gmi for formal/mathematical lens)

**Pre-bootstrap actions:**
- Pin the corpus (papers, code, datasets) with content hashes
- Identify the load-bearing claim (which methodology is supposed to win?)
- Identify the workload (which use case does the methodology target?)
- Optionally: run /alien-artifact-coding for formal-claim verification

**Phase 1 framing emphasis:**
- F4 paradox (per Brenner: what's the tension that makes this method controversial?)
- F5 falsifier (which empirical observation would refute the method?)
- F7 corpus (peer-reviewed papers, replicated benchmarks)

**Critical operators:**
- 𝓛 Recode (reframe each paper's claim in your own words; surfaces inconsistencies)
- ≡ Invariant-Extract (what assumptions does the method depend on?)
- ⊞ Scale-Check (does the method work at our scale and our distribution shift?)
- ⊙ Productive-Ignorance (one pane reads ONLY the question, generates first-principles alternative)

**Common failure modes:**
- F-601 (silent averaging across distillations)
- F-603 (no disagreement register)
- Paper-citation cascade (cite paper P which cites Q which cites R, never reading Q or R)

**Composition with other skills:**
- /alien-artifact-coding for formal claims (calibrated bounds, proofs)
- /multi-model-triangulation for cross-family meta-synthesis
- /testing-conformance-harnesses for spec compliance

**Wall-time estimate:** 6-12h (T3); 1-3 days (T4 with replication)

**Sample question of record:**
"For task class T (e.g., out-of-distribution detection on tabular data), is method M1 (proposed in paper P) more reliably effective than method M2 across (a) standard benchmarks, (b) our specific workload, (c) edge cases the paper doesn't cover?"

**Anti-patterns specific:**
- Treat the paper as authority (the paper might be wrong or misapplied)
- Skip replication (cite without re-running)
- Conflate "works in benchmark" with "works at our deployment"

---

## R6: Distributed-systems debug (consistency / availability / partition)

**Question shape:** A2 codebase × distributed system + A4 incident
**Typical tier:** T3-T4
**Mode:** incident-investigation or fresh-question depending on urgency
**Roster preset:**
- cc: 2 (Investigator-1 protocol layer, Investigator-2 application layer)
- cod: 1 (Cross-region / cross-shard analysis)
- gmi: 1 (Adjudicator with formal/mathematical lens)

**Pre-bootstrap actions:**
- Identify the consistency model claimed by the system
- Identify the actual observed inconsistency
- Pin the time window of the incident
- Compose with /gdb-for-debugging if processes accessible

**Phase 1 framing emphasis:**
- F4 paradox (what assumptions did designers make that don't hold here?)
- F5 falsifier ("if observation X persists, hypothesis Y is wrong")
- F7 corpus (system docs, formal spec if any, change log)

**Critical operators:**
- ⊘ Level-Split (network layer vs protocol layer vs application layer)
- ⊞ Scale-Check (does the issue scale with #nodes? with cross-region traffic?)
- ✂ Exclusion-Test (each candidate cause must have observable falsifier)
- ⊙ Productive-Ignorance (someone re-derives the consistency claim from scratch)

**Common failure modes:**
- F-301 (false binary: "it's the network OR the application")
- F-401 (evidence accumulates without state changes; require kill_rate ≥ add_rate)
- Stop at first plausible cause; distributed bugs usually have ≥2 contributing factors

**Composition with other skills:**
- /lean-formal-feedback-loop for protocol invariants
- /alien-artifact-coding for vector-clock or CRDT design
- /codebase-archaeology if system is unfamiliar

**Wall-time estimate:** 4-8h (T3) or 1-3 days (T4)

**Sample question of record:**
"Across our 3-region deployment, write-write conflicts surface as observable inconsistencies for ~2% of cross-region writes. What's the load-bearing factor among (a) clock skew, (b) Last-Write-Wins resolution incompatible with workload, (c) network partition not handled gracefully, (d) application-level race?"

**Anti-patterns specific:**
- Reason about consistency without a precise model (specify: linearizable? causal? eventual?)
- Test at low load (distributed bugs often appear only under stress)
- Skip cross-region / cross-shard reproduction (single-node test doesn't catch them)

---

## R7: API contract design (versioning, compatibility, deprecation)

**Question shape:** A1 design-space × API surface
**Typical tier:** T2-T3
**Mode:** fresh-question or pre-publication-review
**Roster preset:**
- cc: 1 (Proposer)
- cod: 1 (Devil's-Advocate from consumer perspective)
- gmi: 1 (Adjudicator + Synthesizer)

**Pre-bootstrap actions:**
- Identify all consumers (mobile, web, internal services, external partners)
- Identify the change driver (new feature? deprecation? regulatory?)
- Identify the rollout / migration constraints

**Phase 1 framing emphasis:**
- F3 scope (which consumers in scope, which versions)
- F8 constraints (deprecation SLA, compatibility window, migration cost)

**Critical operators:**
- ≡ Invariant-Extract (which contracts must NOT break?)
- ⊞ Scale-Check (each consumer × each version × each deprecation step)
- ✂ Exclusion-Test (every change has a per-consumer impact path)

**Common failure modes:**
- F-301 (just-add-a-field-and-hope) — force versioning consideration
- F-101 (broad question without consumer enumeration)

**Composition with other skills:**
- /testing-conformance-harnesses for spec compliance
- /testing-golden-artifacts for backwards-compat regression

**Wall-time estimate:** 2-4h (T2-T3)

**Sample question of record:**
"For our payment API v3 → v4 migration, with consumers C1 (mobile, ~80% traffic), C2 (web, ~15%), C3 (partner integrations, ~5%), and a 6-month deprecation window, what's the load-bearing migration plan that minimizes consumer churn AND avoids data corruption AND meets the deprecation deadline?"

**Anti-patterns specific:**
- Design for the easy 80% consumer; ignore the long-tail 5%
- Skip migration safety analysis (rollback possible? data loss risk?)
- Treat versioning as cosmetic (ignore semantic versioning implications)

---

## R8: Data-pipeline integrity (correctness, latency, completeness)

**Question shape:** A2 codebase × data flow
**Typical tier:** T3
**Mode:** code-investigation or post-mortem-formalization
**Roster preset:**
- cc: 2 (Investigator-1 ingestion, Investigator-2 transformation)
- cod: 1 (Adjudicator + cross-stage analysis)
- gmi: 1 (Devil's-Advocate / Synthesizer)

**Pre-bootstrap actions:**
- Map the pipeline: ingestion → transformation → storage → consumption
- Identify each stage's contract (input schema, output schema, latency target)
- Identify the failure symptom (row mismatch? row count drift? latency drift?)

**Phase 1 framing emphasis:**
- F1 trigger (when did this start? schema change?)
- F3 scope (which stages, which time window)
- F5 falsifier (specific row/count comparison)

**Critical operators:**
- ⊘ Level-Split (ingestion vs transformation vs storage vs consumption)
- ≡ Invariant-Extract (per-stage data invariants)
- ⊞ Scale-Check (does the issue scale with row count? with new partitions?)

**Common failure modes:**
- F-301 (focus on one stage without verifying others)
- F-403 (the "obvious" cause is rarely THE cause)

**Composition with other skills:**
- /testing-metamorphic for pipeline-level invariant tests
- /testing-golden-artifacts for output regression

**Wall-time estimate:** 3-5h (T3)

**Sample question of record:**
"Daily aggregate count for table T diverged from expected by ~3% starting 2026-04-01. What's the load-bearing factor among (a) schema change in upstream source, (b) transformation logic bug, (c) partition pruning issue in storage, (d) duplicate-detection logic regression?"

---

## R9: Frontend performance (render, hydration, bundle)

**Question shape:** A2 codebase × frontend rendering pipeline
**Typical tier:** T2-T3
**Mode:** code-investigation
**Roster preset:**
- cc: 1 (Investigator browser/render layer)
- cod: 1 (Investigator network/bundle layer)
- gmi: 1 (Adjudicator)

**Pre-bootstrap actions:**
- Capture Lighthouse / WebPageTest baseline
- Identify the metric of concern (LCP, INP, CLS, TTFB)
- Identify the page / route / component
- Compose with /vercel:performance for Vercel-specific guidance

**Phase 1 framing emphasis:**
- F3 scope (which page, which metric, which device class)
- F5 falsifier (specific Lighthouse threshold)

**Critical operators:**
- ⊘ Level-Split (network → JS bundle → render → hydration → user input)
- ⊞ Scale-Check (does the issue scale with device class? network speed?)

**Common failure modes:**
- F-101 (broad "make it fast" without specific metric)

**Composition with other skills:**
- /vercel:performance for Vercel-specific
- /tanstack-table for virtualization

**Wall-time estimate:** 2-4h

---

## R10: Storage selection (DB / cache / queue)

**Question shape:** A1 design-space × storage technology
**Typical tier:** T3
**Mode:** fresh-question
**Roster preset:**
- cc: 2 (Proposer, Investigator-1)
- cod: 1 (Investigator-2)
- gmi: 1 (Devil's-Advocate / Adjudicator)

**Pre-bootstrap actions:**
- Identify access pattern (read/write ratio, query shape, transaction needs)
- Identify scale (data volume, ops/sec, cardinality)
- Identify durability requirements

**Phase 1 framing emphasis:**
- F3 scope (data shape, access pattern, scale envelope)
- F8 constraints (cost, operational maturity, team expertise)

**Critical operators:**
- ⊞ Scale-Check (each candidate × current scale × 100x scale)
- ⊕ Cross-Domain (consider designs from queueing theory, log-structured systems)
- ✂ Exclusion-Test (each candidate has per-workload elimination criterion)

**Common failure modes:**
- F-301 (PostgreSQL vs Redis without considering hybrids)
- F-403 (familiarity bias: pick what team knows)

**Composition with other skills:**
- /alien-graveyard for buried storage techniques
- /supabase if Supabase is candidate
- /rust-cli-with-sqlite if SQLite is candidate

**Wall-time estimate:** 3-5h (T3)

---

## R11: Auth / authz design

**Question shape:** A1 design-space × access control
**Typical tier:** T3-T4 (security-critical)
**Mode:** fresh-question + dual-use-review
**Roster preset:**
- cc: 2 (Proposer, Investigator + threat-model)
- cod: 1 (Devil's-Advocate)
- gmi: 1 (Synthesizer + adjudicator)

**Pre-bootstrap actions:**
- Identify identity provider(s)
- Identify resource model (objects, attributes, relationships)
- Identify policy domains (RBAC, ABAC, ReBAC, OPA, etc.)

**Phase 1 framing emphasis:**
- F2 stakes (compromise scenarios)
- F4 paradox (every auth system has weaknesses; which are tolerable?)
- F5 falsifier (specific attack class observable in penetration test)

**Critical operators:**
- ⊞ Scale-Check (auth at 100k users vs 100M)
- ◊ Paradox-Hunt (privilege escalation paths)
- 🤝 GAN (red-team must be cross-family)

**Common failure modes:**
- F-501 (audit accepts everything)
- F-705 (audit ≠ synthesizer)

**Composition with other skills:**
- /security-audit-for-saas
- /testing-fuzzing for token-class attacks

**Wall-time estimate:** 5-8h (T3); 1-3 days (T4)

---

## R12: Reliability budget (SLO design)

**Question shape:** A7 decision × reliability planning
**Typical tier:** T3
**Mode:** fresh-question or living-review
**Roster preset:**
- cc: 1 (Investigator existing-system data)
- cod: 1 (Investigator workload analysis)
- gmi: 1 (Synthesizer + adjudicator)

**Pre-bootstrap actions:**
- Pin existing reliability data (uptime, error budget burn)
- Identify customer-impact SLOs (vs internal-only)
- Identify cost of higher reliability (engineering time, infra cost)

**Phase 1 framing emphasis:**
- F2 stakes (cost of downtime, customer impact)
- F8 constraints (engineering budget, infra budget)

**Critical operators:**
- ⊞ Scale-Check (SLO at current load vs forecasted)
- ⌂ Materialize (specific incidents that would breach budget)

**Wall-time estimate:** 3-5h

---

## R13: Observability gap (what we can't see)

**Question shape:** A2 codebase × monitoring/logging gaps
**Typical tier:** T2-T3
**Mode:** code-investigation
**Roster preset:**
- cc: 2 (Investigator-1 metrics, Investigator-2 logs)
- cod: 1 (Investigator-3 traces)
- gmi: 1 (Adjudicator)

**Pre-bootstrap actions:**
- Identify the question we couldn't answer in last incident
- Identify existing monitoring stack (Prometheus/Grafana/Datadog/etc.)

**Phase 1 framing emphasis:**
- F1 trigger (what specific debug session was painful?)
- F3 scope (production vs staging vs dev)

**Critical operators:**
- ⊕ Cross-Domain (telemetry patterns from adjacent systems)
- ⊞ Scale-Check (cardinality + ingest cost)

**Composition with other skills:**
- /world-class-doctor-mode-for-cli-tools for diagnostic ergonomics

**Wall-time estimate:** 2-4h

---

## R14: Migration risk (cutover strategy)

**Question shape:** A7 decision × migration planning
**Typical tier:** T3-T4 (business-critical)
**Mode:** fresh-question + ADR-PATTERNS for sign-off
**Roster preset:**
- cc: 2 (Migration-architect, Risk-investigator)
- cod: 1 (Cutover-strategy)
- gmi: 1 (Devil's-Advocate + Adjudicator)

**Pre-bootstrap actions:**
- Pin existing data shape (export of source schema)
- Identify cutover window
- Identify rollback constraints

**Phase 1 framing emphasis:**
- F2 stakes (data loss tolerance, downtime budget)
- F5 falsifier ("if dual-write produces N% inconsistency, the strategy fails")

**Critical operators:**
- ⊞ Scale-Check (migration at full data volume, not toy subset)
- ✂ Exclusion-Test (each phase has go/no-go gate)
- ◊ Paradox-Hunt (what assumptions about old system don't hold?)

**Common failure modes:**
- F-101 (broad "migrate to X")
- Skip rollback design (one-way migration is rare)

**Composition with other skills:**
- /testing-real-service-e2e-no-mocks for cutover dry-run

**Wall-time estimate:** 5-10h (T3); days (T4)

---

## R15: Cost optimization (infra / vendor / compute)

**Question shape:** A7 decision × cost reduction
**Typical tier:** T2-T3
**Mode:** fresh-question or living-review
**Roster preset:**
- cc: 2 (Cost-attribution, Optimization-options)
- cod: 1 (Devil's-Advocate "premature optimization?")
- gmi: 1 (Synthesizer)

**Pre-bootstrap actions:**
- Pin current cost breakdown (per service / per customer / per query)
- Identify cost driver (compute, storage, egress, vendor licenses)

**Phase 1 framing emphasis:**
- F2 stakes (savings target vs engineering investment)
- F5 falsifier ("if optimization saves <X%, ROI is negative")

**Critical operators:**
- ⊞ Scale-Check (savings at current vs forecasted scale)
- ✂ Exclusion-Test (each option has per-axis cost-benefit)

**Wall-time estimate:** 2-5h

---

## Recipe composition

Recipes can be composed for hybrid questions. E.g., a security audit on a distributed system migration uses R4 (security audit) + R14 (migration risk).

When composing:

- Take the larger tier (security audit T4 + migration T3 → T4)
- Combine the rosters (often hits the Squad ceiling; consider Swarm)
- Sequence the phases (security audit findings inform migration plan)
- Schedule the wall-time additively + 25% coordination overhead

---

## Adding a recipe

When a session reveals a useful new recipe pattern:

1. Match an existing recipe? Update it.
2. New shape? Document per the recipe format above.
3. Test on ≥1 subsequent session.
4. Promote to canonical when it's used ≥3 times across operators.

The recipes evolve with experience. Phase 10 lessons may surface "the recipe was wrong for this case" — update or fork the recipe.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Treat recipes as gospel | Recipes are fast-start templates; the question may need divergence |
| Skip recipes "I know better" | Even experienced operators benefit from the cumulative wisdom |
| Pick recipe by surface keyword match | Match on question SHAPE (archetype × pattern), not topic words |
| Compose all recipes for ambition | Composition multiplies overhead; pick 1-2 most relevant |
| Recipe-only mode | Recipes seed; the methodology still runs the question |

---

## Operator self-test

Before running a session, the operator should:
1. Identify the recipe(s) that match the question shape
2. Note the recipe's typical tier vs current question's stakes (if mismatch, escalate or downgrade)
3. Apply the pre-bootstrap actions
4. Run the standard Phases 1-10 with the recipe's emphasis

This often saves 1-2 hours per session.
