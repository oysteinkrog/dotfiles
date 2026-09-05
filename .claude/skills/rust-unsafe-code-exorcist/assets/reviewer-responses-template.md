# REVIEWER_RESPONSES.md — Maintainer-Empathy Review

**Reviewer agent.** `<model + run-id>`
**Reviewed on.** `<YYYY-MM-DD>`
**Audit dir.** `<path>`

---

## Q1: Would I land these as-is?

**Confidence:** `Low | Medium | High`

**Reasoning:**
<paragraph>

---

## Q2: Where am I unconvinced?

| Site / Cluster | Concern | Severity |
|----------------|---------|----------|
| site-NNNN | <specific objection> | high/med/low |
| Cluster X-NNN | <objection> | high/med/low |

---

## Q3: What evidence am I missing?

- <missing test on input class X>
- <missing per-target bench on aarch64>
- <missing loom model for site-NNNN>
- <missing migration-path doc for breaking API change on Y>

---

## Q4: Riskiest plan

**Site:** site-NNNN
**Analysis:**
<paragraph: what makes it risky; is the risk worth the gain; how to de-risk>

---

## Q5: 20/80 priority order

Top 3 clusters / sites by impact-per-effort:

1. **<cluster or site>** — <why: impact / effort>
2. **<cluster or site>** — <why>
3. **<cluster or site>** — <why>

Recommend landing these first; the heavier refactors can follow.

---

## Q6: Missed refactor strategies

(Cross-reference `audit/phase10/idea-wizard-output.md`)

| Strategy | Where applicable | Trade-off |
|----------|------------------|-----------|
| <alt> | <cluster> | <cost vs benefit> |
| <alt> | <cluster> | <cost vs benefit> |

---

## Q7: (A) falsification audit

For each (A) site with weak justification (confidence < 0.7 or steel-man reads thin):

| Site | Attack attempted | Result |
|------|------------------|--------|
| site-NNNN | <one-paragraph steel-man> | <holds / defeats> |

If any attack defeats the original rebuttal, REOPEN Phase 6 for that site.

---

## Q8: (B) perf credibility

For each (B) site:

| Site | Bench machine | Workload representative? | Runs | Variance | Verdict |
|------|---------------|-------------------------|------|----------|---------|
| site-NNNN | <hostname> | <yes/no — why> | 10 | <%> | credible / suspect |

---

## Q9: (C) test coverage

For each (C) site with `diff_size: large`:

| Site | Test file | Failure modes covered | Gaps |
|------|-----------|----------------------|------|
| site-NNNN | `audit/tests/equivalence_NNNN.rs` | <list> | <list> |

---

## Action items

### For original planner agents (revise plans)

- site-NNNN: <revision request>
- site-MMMM: <revision request>
- Cluster X-NNN: <revision request>

### For follow-up beads (deferred)

- <one-liner per deferred concern, with "deferred — see REVIEWER_RESPONSES.md §N">

### For pre-existing-UB triage

- pre-existing-ub-N: <priority>; <recommendation: address now / next / never>

---

## Sign-off

After revisions land, the reviewer (or another fresh agent) re-runs this template. The audit closes when:

- Confidence reaches `Medium` or `High`.
- All "addressed" action items have been addressed in revised plans.
- All "deferred" action items have follow-up beads.
- pre-existing-UB triage is complete.

`Status: open | closed`
`Closed on: <YYYY-MM-DD>` (if closed)
