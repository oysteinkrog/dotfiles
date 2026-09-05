# PHASE-1-ANTI-EXAMPLES.md — Concrete Examples of Phase 1 Framing Failures

<!-- TOC: Why anti-examples | AE format | AE-1.1 too broad | AE-1.2 unfalsifiable | AE-1.3 hidden trigger | AE-1.4 multi-question | AE-1.5 confirmation-seeking | AE-1.6 missing decision-rule | AE-1.7 scope balloon | AE-1.8 false binary in framing | AE-1.9 stakes mismatch | AE-1.10 corpus blind | How to use anti-examples -->

Mirrors documentation-website's WRITING-CRAFT.md anti-example pattern. A good way to learn Phase 1 framing is to study what bad framing looks like and how to recover.

For each anti-example: the user's raw ask, the bad framing it would produce, the diagnosis (which F-phase failed), and the recovery (how the operator should redirect).

---

## Why anti-examples

Per FRAMING-WORKBOOK.md F1-F9, sound framing is hard. Even experienced operators silently slip into common failure modes. Concrete anti-examples make the failure modes recognizable in real-time, before they cost a session.

Operators should walk through these before T3+ sessions; they're also useful for buddy-system review per OPERATOR-ONBOARDING-CURRICULUM.md.

---

## Anti-example format

Each anti-example:

```
AE-1.<N>: <one-line title>

**User's raw ask:** "<verbatim or near-verbatim>"

**Bad framing produced:**
- Question: <what the operator wrote>
- Falsifier: <weak/missing>
- Scope: <vague>
- (other fields...)

**Diagnosis:** Which F-phase(s) failed (per FRAMING-WORKBOOK.md), which F-### code applies (per FAILURE-TABLE.md).

**Recovery:** Specific operator move to redirect.

**Resulting good framing:** <how the operator would have written it after recovery>
```

---

## AE-1.1: Too broad

**User's raw ask:** "What's the best way to design our system?"

**Bad framing produced:**
- Question: "What's the optimal architecture for our system?"
- Falsifier: "If after exhaustive analysis no architecture stands out, the question is malformed."
- Scope: "Whole system."

**Diagnosis:** F3 (scope) failed catastrophically. F1 (trigger) wasn't probed. The "best" is unmeasurable. F-101.

**Recovery:** Operator probes:
- "Best for what specific user-visible metric? Latency? Throughput? Cost? Reliability?"
- "Best at what scale? Current 10k users? Forecast 1M users?"
- "What changed recently that made you ask this NOW? Is there a pain point?"
- "What's clearly OUT of scope? List 3 things you don't want changed."

**Resulting good framing:**
- Question: "Under workload class W (current scale 10k users, forecast 100k in 12 months, p99 ≤ 200ms), what's the load-bearing architecture decision between (a) keep monolith + add caching, (b) extract auth as separate service, (c) full microservices migration?"
- Falsifier: "If exhaustive Phase 4 finds zero architectural choice that meets the SLO at forecast scale within constraint X, the question is too constrained — re-frame."
- Scope: monolith→service-extraction trade-off; OUT of scope: framework rewrite, language change, persistent storage rewrite.

---

## AE-1.2: Unfalsifiable

**User's raw ask:** "Why is our system slow?"

**Bad framing produced:**
- Question: "What makes our system slow?"
- Falsifier: "We'll know when we find the cause."
- Scope: "All slowness."

**Diagnosis:** F5 (falsifier) failed. "We'll know when we see it" is the canonical anti-falsifier. F-103.

**Recovery:** Operator probes:
- "Slow on which specific page / endpoint / operation?"
- "Slow how? Specific p99 number? Compared to what baseline?"
- "Did this start at a specific time? Is there a regression window?"
- "If you found a single fix that improved p99 by X%, would that close the question?"

**Resulting good framing:**
- Question: "p99 latency on `/api/checkout` rose from 80ms baseline (2026-04-01) to 450ms (2026-04-15). What's the load-bearing factor among (a) deploy at 4-12, (b) traffic spike, (c) dependency degradation, (d) database connection pool?"
- Falsifier: "If reducing the load-bearing factor's contribution by 50% does NOT bring p99 below 200ms, the diagnosis is wrong."

---

## AE-1.3: Hidden trigger

**User's raw ask:** "How should I think about session management?"

**Bad framing produced:**
- Question: "What's the best session management strategy?"
- Falsifier: "If no strategy stands out, defer."
- Scope: "Session management generally."

**Diagnosis:** F1 (trigger) failed. The "neutral" framing hides the actual driver. F-101.

**Recovery:** Operator probes:
- "What triggered this question? Did something break? Are you about to make a change?"
- "Is this driven by a specific incident, a planned rollout, a security audit, or a recurring concern?"
- "What's the specific user impact you're hoping to address?"

**Resulting good framing (after probing reveals the actual driver was a security audit finding):**
- Question: "Per security audit finding SF-2026-04-23, our current session-token rotation has a critical vulnerability under threat model T. What rotation strategy mitigates this within (constraint: cannot break existing mobile clients within 30 days, cannot increase auth latency by >5ms)?"
- Falsifier: specific re-test of the vulnerability after implementation.

---

## AE-1.4: Multi-question

**User's raw ask:** "I want to investigate (a) which database is best, (b) how should we handle migrations, and (c) what's our backup strategy?"

**Bad framing produced:**
- Question: "What's our optimal data-platform strategy across DB choice, migrations, and backup?"
- Scope: "All three."

**Diagnosis:** Three separate questions packaged as one. F-101.

**Recovery:** Operator says:
- "These are three questions. Each needs its own session, OR we pick one as the anchor and the others get derived as constraints."
- "Which is most urgent / time-pressed / has the deadline?"
- "If you ran ONE question now and the others later, which would unblock the most?"

**Resulting good framing (after user picks DB choice as anchor):**
- Anchor question: "Given constraints C, what's the load-bearing DB choice?" → run as separate session R10 storage selection
- Derived: "Given DB X chosen above, what's the migration strategy?" → next session R14 migration risk
- Derived: "Given DB X + migration strategy, what's the backup architecture?" → next session R12 reliability budget

---

## AE-1.5: Confirmation-seeking

**User's raw ask:** "I think we should switch from PostgreSQL to ScyllaDB. Can you confirm?"

**Bad framing produced:**
- Question: "Is ScyllaDB better than PostgreSQL for our use case?"
- Scope: "Compare PostgreSQL vs ScyllaDB."
- (Implicit: user wants confirmation of switch)

**Diagnosis:** Anti-Brenner — the user has prior conclusion. F4 (paradox) wasn't probed. F-403 (confirmation bias risk).

**Recovery:** Operator surfaces the bias:
- "I notice you have a prior conclusion. The brennerbot session can either: (a) test the conclusion against alternatives, with risk that it gets refuted, or (b) skip the session and just plan the migration. Which do you want?"
- If (a): "OK, I'll frame the question as comparison among ≥3 alternatives, including 'stay on PostgreSQL but tune'. The session may refute your prior."
- If (b): "Don't run a brennerbot session. Just go to migration planning per R14."

**Resulting good framing (assuming user picks (a)):**
- Question: "For workload W (write-heavy, ~50k ops/sec, multi-region replication target), which is the load-bearing storage choice among (a) keep PostgreSQL with logical-replication tuning, (b) PostgreSQL + Citus, (c) ScyllaDB, (d) CockroachDB?"
- Falsifier: per-candidate failure under our specific workload.
- (Operator notes: user's prior was ScyllaDB; session may confirm or refute.)

---

## AE-1.6: Missing decision-rule

**User's raw ask:** "Should we adopt Service Mesh?"

**Bad framing produced:**
- Question: "Is Service Mesh worth adopting?"
- Falsifier: "If cost outweighs benefit."
- Scope: "Service Mesh adoption."

**Diagnosis:** F2 (stakes) failed — "worth adopting" is undefined. F-101 + F-103.

**Recovery:** Operator probes:
- "What action do you take if the answer is yes? Plan a Q3 rollout? Hire SRE? Train team?"
- "What do you take if the answer is no? Defer 6 months? Re-evaluate at next architecture review?"
- "What if the answer is 'maybe — depends on Y'? What's Y?"

**Resulting good framing:**
- Question: "Given current scale (50 services, 5 engineering teams, 99.9% SLO target), is adopting Istio Service Mesh load-bearing for our reliability goals over the next 12 months — meaning if we DON'T adopt it, we'd predictably fail the SLO target?"
- Decision rule: "Yes → Q3 rollout starting 2026-07-01. No → defer to 2027 review. Maybe → operator must specify the gating condition."
- Falsifier: "If specific reliability incidents in the next 6 months can be attributed to lack of mesh-style features (mTLS, observability, traffic management), 'no' is wrong."

---

## AE-1.7: Scope balloon

**User's raw ask:** "Investigate our authentication system."

**Bad framing produced:**
- Question: "What's wrong with our authentication system?"
- Scope: "Authentication." (vague)

**Diagnosis:** F3 (scope) failed. "Authentication" is a domain, not a question. F-101.

**Recovery:** Operator forces specifics:
- "What specific question? Performance? Security? Reliability? UX? Cost?"
- "Which user-flow? Login? Token refresh? OAuth? Recovery? MFA?"
- "Which system? Web? Mobile? B2B SDK? Internal services?"

**Resulting good framing:**
- Question: "For OAuth2-based login on web, with current session handling via JWT in HttpOnly cookies, what are the load-bearing security weaknesses ranked by severity × exploitability?"
- Scope: web only; OAuth2 only; HttpOnly cookies + JWT.
- OUT of scope: mobile auth, internal-service auth, password recovery flow.

---

## AE-1.8: False binary in framing

**User's raw ask:** "Should we use REST or GraphQL?"

**Bad framing produced:**
- Question: "REST vs GraphQL?"
- Falsifier: "Whichever is better for our use case."
- Scope: "API style choice."

**Diagnosis:** F4 (paradox) failed — there's no genuine paradox; both can work; the question is binary by default. F-301.

**Recovery:** Operator forces ≥3 alternatives:
- "What's the third alternative? (gRPC? tRPC? hybrid REST + GraphQL?)"
- "What's the no-choice alternative? (keep current style and tune)"
- "What constraint forces this binary? Could the constraint be relaxed?"

**Resulting good framing:**
- Question: "For our public API serving (a) web SPA, (b) mobile apps, (c) partner integrations, what's the load-bearing API style choice among REST, GraphQL, gRPC, hybrid?"
- Per Brenner §103: at least one third-alternative mandatory; mark with `origin: third_alternative`.

---

## AE-1.9: Stakes mismatch

**User's raw ask:** "Just curious — what color should our admin UI buttons be?"

**Bad framing produced:**
- Question: "Optimal button color for admin UI?"
- Tier: T3 (Squad with full triangulation)

**Diagnosis:** F2 (stakes) mismatch — operator over-tiered. T1 curiosity is not a Squad job. F-101 (over-engineering).

**Recovery:** Operator says:
- "This is T1 curiosity. Squad is overkill. Recommendations: (a) Solo session for ≤30 min, OR (b) just consult /ux-audit recommendations directly without a brennerbot session."
- "If you want a real session, what's the higher-stakes question? E.g., 'admin UI accessibility audit' (T2) or 'admin UX redesign for productivity' (T3)?"

**Resulting good framing (if T1):**
- Just answer directly with /ux-audit principles, no brennerbot session needed.

**Resulting good framing (if escalated to T2):**
- Question: "For admin users with WCAG-AA color contrast requirements and our brand-color palette, what's the load-bearing button-color decision for primary/secondary/destructive actions to maximize task completion rate?"
- Tier T2 with /ux-audit composition.

---

## AE-1.10: Corpus blind

**User's raw ask:** "Investigate consistency models for our DB."

**Bad framing produced:**
- Question: "Which consistency model is best?"
- Corpus: empty (operator didn't pin sources)

**Diagnosis:** F7 (corpus) skipped. Without authoritative sources, the session distills opinions instead of evidence. F-102 risk.

**Recovery:** Operator pins corpus before bootstrap:
- "Pin: Bailis et al. 'HAT, not CAP'; Brewer's CAP twelve-years-later; Vogels 'Eventually Consistent'; per relevant docs from your DB vendor."
- "Each pinned source gets content-hash + recency annotation per VERIFICATION-FIRST.md."
- "Now Phase 1 framing has authoritative anchors."

**Resulting good framing:**
- Question: same.
- Corpus pinned: 4 papers + 2 docs + 1 talk; all hashed.
- F7 explicit: corpus is frozen for the session.

---

## How to use anti-examples

### During Phase 1 framing

Operator drafts a question of record. Before bootstrap, scan the AE list:
- Does my question match AE-1.1 (too broad)? → re-scope
- Does my falsifier match AE-1.2 (unfalsifiable)? → tighten
- Did I probe trigger (AE-1.3)? → if not, ask user
- ... etc.

This is a 5-minute self-check that catches 80% of framing failures.

### During buddy review

When reviewing a new operator's first sessions, the buddy can categorize their failures using AE codes:
- "Your Week 1 session matched AE-1.4 — multi-question. For Week 2, run separate sessions."

### During Phase 10 drift

Drift auditor checks: did the session's question match any AE pattern? If yes, lesson: future sessions on similar topics should use the AE-recovery instead.

---

## Adding new anti-examples

Each session may surface novel framing failures. Document them:
1. Capture the user's raw ask + the bad framing.
2. Diagnose against FRAMING-WORKBOOK + FAILURE-TABLE codes.
3. Document the recovery.
4. Add to this catalog.

The catalog grows with operator experience.

---

## Cross-references

- FRAMING-WORKBOOK.md (the F1-F9 phases these AE map to)
- FAILURE-TABLE.md (the F-### codes)
- QUESTION-OF-RECORD-TEMPLATE.md (the canonical question schema)
- OPERATOR-ONBOARDING-CURRICULUM.md (Week 1-2 buddy review)
