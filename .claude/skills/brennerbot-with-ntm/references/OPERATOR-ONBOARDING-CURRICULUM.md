# OPERATOR-ONBOARDING-CURRICULUM.md — Train a New brennerbot Operator

<!-- TOC: Why a curriculum | Week 1 fundamentals | Week 2 phase mastery | Week 3 multi-session | Week 4 advanced | Trust ladder | Buddy system | Anti-patterns -->

Mirrors saas-billing's ONBOARDING-NEW-ENGINEERS.md and wills-and-estate-planning's similar pattern. A new operator can't run T3+ sessions safely without guided practice.

This curriculum is 4 weeks (≥10h/week) for someone with general agent-coding background. Faster (1-2 weeks) for experienced multi-agent operators. Slower (6-8 weeks) for total beginners.

---

## Why a curriculum

The skill has 60+ references and 30+ marching orders. An ad-hoc operator drowns in references and produces methodologically-unsound sessions. The curriculum provides:

- **Trust ladder** — start with low-stakes (T1) sessions; graduate to T4+ over time
- **Buddy system** — pair with experienced operator for first sessions
- **Reflection checkpoints** — Phase 10 drift checks become learning signals
- **Theory + practice** — read references then run sessions

After Week 4, the operator should be safe to run T3 sessions solo. T4+ requires more experience (often 6+ months).

---

## Week 1 — Fundamentals

### Required reading (in order)

1. SKILL.md (full) — orient
2. KERNEL.md — the two axioms + 15 operators
3. OPERATORS.md — operator card library
4. PHASES.md — phase loop
5. SOURCE-CORPUS.md — Track A pattern + Brenner's transcript

### Practical exercises

**Exercise 1.1**: Frame a question (T1 dry-run)

- Pick a small, low-stakes question of your own ("which database is best for my side project?")
- Walk through FRAMING-WORKBOOK.md F1-F9 alone
- Produce intake/question_of_record.md
- Self-test per QUESTION-OF-RECORD-TEMPLATE.md

**Self-grade**: did you produce a falsifiable question with non-empty Out-of-Scope?

**Exercise 1.2**: Solo-tier session (T1)

- Bootstrap a workspace via `bootstrap-session.sh`
- Run a Solo-tier session on Exercise 1.1's question
- Reach Phase 9 with HANDBACK.md ≤80 lines

**Self-grade**: Did all phases complete? Was the verdict supported by evidence with verbatim citations?

**Exercise 1.3**: Read three case studies

From CASE-STUDIES.md, read A1.1, A2.1, A4.1. Note: which operator cards fired, which failure modes were avoided.

### Week 1 deliverable

A T1 session in your `~/brennerbot_sessions/week1/` workspace, with all artifacts committed. Operator buddy reviews for completeness (not correctness — just methodology compliance).

---

## Week 2 — Phase mastery

### Required reading

1. BEADS-SCHEMA.md — bead invariants
2. AGENT-MAIL-CONVENTIONS.md — coordination
3. ROSTER-PLANS.md — role rotation
4. CONVERGENCE.md — exit criteria
5. METRICS.md — measurable quality
6. TRIANGULATION.md — multi-model triangulation
7. CRITIQUE-CRAFT.md — how to write good critiques
8. RESUME-PROTOCOL.md — resumability

### Practical exercises

**Exercise 2.1**: Pair-tier session (T2)

- Pick a slightly higher-stakes question
- Bootstrap with Pair tier (cc + cod)
- Run all 9 phases (10 optional)
- Apply MO-04a + MO-04b consistently
- Use convergence-check.sh

**Self-grade**: Did you produce a non-empty disagreement_register.md (≥1 entry)? Did Phase 4 converge with kill_rate ≥ add_rate?

**Exercise 2.2**: Multi-model triangulation

- Add gmi to Exercise 2.1's roster (Squad-light)
- Re-run Phase 6 with 3 families
- Verify ≥3 disagreement entries (one per pair)

**Exercise 2.3**: Stress-test scenario walkthrough

- Read STRESS-TEST-SCENARIOS.md S1-S5
- Mentally simulate each on a hypothetical session
- Identify which MO/script applies

### Week 2 deliverable

A T2 session committed; Phase 6 disagreement_register populated; resume-session.sh dry-run passes.

---

## Week 3 — Multi-session and advanced patterns

### Required reading

1. EXTENDED-OPERATING-MODES.md — niche modes
2. CROSS-SESSION-LEARNING.md — lifecycle
3. DRIFT-RUBRIC.md — Phase 10 drift checks
4. CASS-MINING-RECIPES.md — prior-session mining
5. ARCHETYPE-START-PACKS.md + QUESTION-ARCHETYPES.md
6. WALL-TIME-BUDGET.md — discipline
7. SIX-LAYER-VALIDATION.md — defense-in-depth
8. RECONCILIATION-OF-PRIOR-SESSIONS.md

### Practical exercises

**Exercise 3.1**: Resume a prior session

- Take Exercise 2.1's workspace
- Run resume-session in `targeted-investigation` mode on a deferred H
- Update RESUME.md after the loop
- Verify Layer 1-5 of SIX-LAYER-VALIDATION.md pass

**Exercise 3.2**: Drift check

- Run Phase 10 drift on Exercise 2.1
- Use a fresh general-purpose Agent (NOT a swarm pane!)
- Produce DRIFT-CHECK.md with ≥1 lesson
- Commit the lesson back to your local skill copy

**Exercise 3.3**: Mode variant

- Pick one EXTENDED-OPERATING-MODES.md mode (e.g., `peer-review`, `meta-analysis`, or `living-review`)
- Run a sample session in that mode
- Document mode-specific tweaks in your session notes

**Exercise 3.4**: Composition

- Read SKILL-COMPOSITION-PATTERNS.md
- Run a session that composes brennerbot + at least one other skill
- (e.g., brennerbot + /codebase-archaeology for a code-investigation session)

### Week 3 deliverable

3 sessions: a resume, a drift-check, a mode-variant. Each with proper artifacts.

---

## Week 4 — Advanced and edge cases

### Required reading

1. EXTENDED-FAILURE-CATALOG.md — niche F-codes
2. ANTI-PATTERNS.md (full)
3. STRESS-TEST-SCENARIOS.md (full)
4. POST-MORTEM-FORMALIZATION-PLAYBOOK.md
5. ADR-PATTERNS.md
6. TIER-TRIAGE.md — when to escalate
7. VERIFICATION-FIRST.md — for volatile sources
8. EXEMPLARS.md — quote bank

### Practical exercises

**Exercise 4.1**: T3 Squad session

- A real research question of moderate stakes
- Squad tier with all 3 families
- Apply CRITIQUE-CRAFT.md discipline to all `C-*` beads
- Run subagents/falsifier-grader.md at Phase 7
- Run subagents/red-team.md if archetype is A6

**Exercise 4.2**: Stress-test response

- Designate a buddy to introduce a stress-test scenario mid-session (e.g., simulate a rate-limit cluster)
- Apply the matching MO + script
- Document recovery in session-logs

**Exercise 4.3**: Reconciliation

- Find two prior sessions on related questions (yours or buddy's)
- Run subagents/reconciler.md
- Produce RECONCILIATION-MEMO.md

**Exercise 4.4**: Methodology improvement

- Identify one Phase 10 lesson from your sessions
- Propose a change to `references/` (don't commit yet)
- Have buddy review

### Week 4 deliverable

A T3 session with full Six-layer-validation passing; one drift check that produced a committed lesson; reconciliation memo.

---

## Trust ladder

After completing Week 4, the operator should be at:

| Trust level | Tier ceiling | Buddy required? |
|-------------|--------------|------------------|
| Week 1 | T1 | yes (review) |
| Week 2 | T2 | yes (review) |
| Week 3 | T3 (with composition) | optional |
| Week 4 | T3 solo | optional |
| Month 2-3 | T4 with buddy review | yes (review) |
| Month 4-6 | T4 solo | optional |
| Month 6+ | T5 | mandatory ≥2 reviewers |

T5 sessions should never be solo regardless of operator experience. Per TIER-TRIAGE.md.

---

## Buddy system

For Weeks 1-2, the operator pairs with an experienced operator (preferably someone who's run ≥10 sessions of various tiers).

The buddy:

- Reviews Week 1-2 deliverables for methodology compliance
- Available via mail/chat for stuck moments
- Doesn't run sessions for the operator (operator must own the work)

For Weeks 3-4, the buddy is optional but recommended.

After Month 2, the operator becomes a buddy candidate for new operators.

---

## Self-assessment checkpoints

At end of each week, the operator runs:

```bash
# Self-assessment script (Tier-4 if added):
./scripts/operator-self-assessment.sh --week=<N>
```

Outputs:
- Phases completed across all this-week sessions
- Failure-mode rate (F-### codes triggered)
- Methodology compliance per six-layer-validation
- Areas of weakness (e.g., "Phase 5 adjudication consistently rules without EV citation")

This is calibration, not grading. Use to focus subsequent learning.

---

## Anti-patterns in operator development

| ✗ | Why |
|---|-----|
| Skip Week 1 fundamentals "I know this" | Methodology details matter; even experienced people miss the load-bearing rules |
| Run T4+ sessions in Week 1-2 | Stakes too high for unfamiliar operator |
| Skip Phase 10 drift checks "they're tedious" | Drift is how you learn; skipping means you'll repeat mistakes |
| Compose with other skills before mastering brennerbot solo | Composition multiplies failure modes |
| Skip reading EXEMPLARS.md "it's just history" | The exemplars are *how* the operators learn cognitive patterns |
| Race through curriculum (≤2 weeks) | Pattern depth requires reflection time |
| Skip the buddy review for "small things" | Operator self-evaluates; buddy catches blind spots |

---

## Specialty paths

After Week 4, operators may specialize:

### Domain specialist

Focus on one research domain (per EXTENDED-PROJECT-TYPES.md). Become the go-to operator for that domain. Read more papers in the field; build domain-specific corpus.

### Methodology specialist

Focus on the methodology itself. Run more drift checks; propose more lessons. Maintain `references/` with care. Become the go-to reviewer for buddy-system new operators.

### Adversarial specialist

Focus on A6 (adversarial) archetype. Become the go-to red-team operator. Read more security literature; understand attack patterns deeply.

### Multi-session specialist

Focus on T4-T5 sessions and reconciliation. Run cross-session triangulation; maintain CROSS-SESSION-DRIFT-CATALOG. Coordinate with multiple operators.

The skill needs all four specialties. Most operators end up in one or two by month 6.

---

## Operator certification (optional)

For organizations running brennerbot at scale, consider operator certification:

- Complete Week 1-4 curriculum
- ≥10 sessions across tiers T1-T3
- ≥3 reviews of other operators' sessions
- Pass a "stress-test interview" (operator handles 5 STRESS-TEST scenarios in real-time)
- Document one methodology contribution (Phase 10 lesson committed and adopted)

Certified operators may run T4 solo and lead T5 sessions.

---

## Continuous learning

After Week 4, ongoing:

- Read every Phase 10 lesson committed by any operator
- Quarterly: review CROSS-SESSION-DRIFT-CATALOG for patterns
- Quarterly: read latest EXEMPLARS.md additions
- Quarterly: update OPERATOR-CALIBRATION-LOG with own metrics

The methodology evolves; operators who don't keep learning fall behind quickly.
