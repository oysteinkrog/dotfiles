# EVIDENCE-WEIGHTING-TAXONOMY.md — How to Weight Different Evidence Types

<!-- TOC: Why weight evidence | The five weight axes | Source-class weights | Verification-status weights | Independence weights | Recency weights | Domain-fit weights | Composite scoring | Anti-patterns | Worked examples -->

Per CRITIQUE-CRAFT.md and CONFIDENCE-SCORING.md. Brennerbot's hypothesis lifecycle depends on EV beads — but not all EVs are equal. A peer-reviewed paper isn't a tweet. A 2003 paper might be obsolete. A self-replicated experiment is stronger than a citation. Without explicit weighting, the swarm collapses to "vote count" which is anti-Brenner.

This file specifies the five axes for evidence weighting and how to compose them into a per-EV strength score.

---

## Why weight evidence

Without explicit weights:

- Confirmation bias survives Phase 4 (5 weak EVs outweigh 1 strong refuter)
- Source-credibility blind spots persist (ad-hoc rejection of contrarian evidence)
- Cross-session reconciliation breaks (different sessions used different implicit weights)

With explicit weights:

- Adjudicator decisions are reproducible
- Disagreement register surfaces *weighting* disagreements, not just claim disagreements
- Phase 7 audit can verify weighting was sound

---

## The five weight axes

Each EV bead is scored along five axes:

```
W_source        — source class (paper / preprint / blog / docs / measurement)
W_verification  — verification status (verified / replicated / both / neither)
W_independence  — how many independent sources support the same claim
W_recency       — staleness vs the question's domain volatility
W_domain_fit    — how well the source's regime matches our regime
```

Composite: `W = W_source × W_verification × W_independence × W_recency × W_domain_fit`

Each axis is in [0, 1]. Composite is in [0, 1]. By convention:
- W ≥ 0.7: strong evidence (load-bearing)
- 0.4 ≤ W < 0.7: moderate (corroborating)
- 0.2 ≤ W < 0.4: weak (suggestive)
- W < 0.2: too weak to cite as load-bearing (still record as informative)

---

## W_source — Source class

```
1.0  Formal proof (verified machine-checked) OR your own measurement under controlled conditions
0.9  Peer-reviewed paper in top-tier venue (NeurIPS, SIGMOD, etc.)
0.8  Peer-reviewed paper in mid-tier venue
0.8  Reference implementation by domain expert (e.g., the original paper author's code)
0.7  Preprint (arXiv, biorxiv) with widespread expert citation
0.7  Authoritative documentation from product/library maintainer
0.6  Survey/textbook from established author
0.5  Industry whitepaper / engineering blog from major company
0.5  Replicated benchmark from independent third party
0.4  Conference talk by domain expert
0.3  Single engineering blog post
0.2  Stack Overflow / forum / GitHub issue
0.1  Tweet / social media post
0.05 Unverified claim ("someone said")
```

For domain-specific adjustments, see DOMAIN-RECIPE-LIBRARY.md per-domain notes.

### Notes:

- Top-tier venues are domain-specific. NeurIPS for ML; SIGMOD for DBs; OSDI/SOSP for systems.
- Engineering blogs from major companies (Netflix, Google, Stripe) carry weight on their *operational* claims but not their *academic* claims.
- Tweets / forums can be valuable but should be triangulated with stronger sources before load-bearing use.

---

## W_verification — Verification status

```
1.0  Independently verified (different pane re-checked source) AND replicated (you re-ran the experiment)
0.85 Independently verified (re-checked) but not replicated
0.7  Replicated but not independently re-verified
0.6  Initial pin only (default for fresh evidence)
0.4  Verification skipped or noted unavailable
0.2  Source has known errata / corrections
0.1  Source withdrawn / retracted (only cite to acknowledge prior reliance)
```

Per VERIFICATION-FIRST.md and MO-evidence-verify.md, verification is independence-checked re-reading; replication is running the experiment yourself.

### Anti-patterns:

- Mark `verified: true` without actually navigating to source (= self-attestation)
- Replicate but skip independence check (= confirmation bias)
- Skip verification "obvious sources don't need it" (= F-303 silent drift)

---

## W_independence — Multi-source corroboration

For a claim:

```
1.0  ≥3 independent sources from different communities reach the same claim
0.85 2 independent sources from different communities
0.7  ≥3 sources but from same community (citation chain)
0.5  Single source
0.2  Multiple sources but all derive from one (e.g., paper P + blog post citing P + tutorial citing P)
```

### Independence detection

Two sources are independent if:
- Different authors (no co-author overlap)
- Different institutions
- Different funding source / conflict of interest
- Different methodology (one survey + one experiment is more independent than two surveys)

### Anti-patterns:

- Citation cascade illusion: source A cites B cites C cites A. All "say the same" but it's one origin.
- Author overlap: 5 papers from same lab arguing the same way ≠ 5 independent sources.
- Methodological monoculture: 5 ML benchmark papers using the same flawed test set are 1 source w.r.t. the benchmark question.

---

## W_recency — Staleness vs domain volatility

The "decay rate" depends on the domain:

```
DOMAIN_VOLATILITY     |  HALF-LIFE  | example
----------------------|-------------|---------------------------------
Frontier ML           |   6 months  | LLM techniques, post-2023
Web frameworks        |   18 months | React/Next.js patterns
Cloud / SaaS infra    |   24 months | Kubernetes patterns, OAuth flows
Distributed systems   |    5 years  | Paxos, Raft variants
Database internals    |   10 years  | B-tree, LSM-tree
Foundational CS       |   30 years  | Algorithms, complexity
Mathematics           |    forever  | Theorems
```

W_recency:
```
1.0  age < half-life × 0.25
0.9  age < half-life × 0.5
0.7  age < half-life × 1
0.5  age < half-life × 2
0.3  age < half-life × 4
0.1  age > half-life × 4
```

### Notes:

- For "live" sources (per VERIFICATION-FIRST.md), recency is computed from last_verified_at.
- For "frozen" sources, recency is computed from publication date.
- Some domains have multiple half-lives: e.g., distributed systems' theoretical foundations have 10y half-life, but specific framework versions (Kafka 3.x) have 18mo.

---

## W_domain_fit — Regime match

The source studied scenario S_source. We're applying it to scenario S_ours. Mismatch reduces weight:

```
1.0  Source studied EXACTLY our regime (same workload class, same scale, same constraints)
0.85 Same general regime (same workload class, similar scale within 10x)
0.7  Adjacent regime (workload class similar, scale within 100x)
0.5  Different regime but reasonable extrapolation (e.g., paper studies 1k QPS, we run 100k QPS)
0.3  Different regime, extrapolation requires assumptions (e.g., paper studies single-DC, we deploy multi-region)
0.1  Different regime, source explicitly noted limitation (paper says "doesn't apply at scale X")
```

### Notes:

- Per Brenner ⊞ Scale-Check: paper benchmarks at 100 nodes; we deploy at 10,000 nodes — extrapolation is dangerous.
- Workload class matters: read-heavy vs write-heavy, batch vs streaming, single-tenant vs multi-tenant.

---

## Composite scoring

```
W = W_source × W_verification × W_independence × W_recency × W_domain_fit
```

Multiplicative because any axis being weak makes the EV weak overall. (A peer-reviewed paper from 1995 about a regime that doesn't match ours is weak even if W_source = 0.9.)

### Examples

**EV-001: peer-reviewed paper from NeurIPS 2024, replicated by us, cited 50× independently, our exact regime:**

```
W_source        = 0.9
W_verification  = 1.0 (verified + replicated)
W_independence  = 1.0 (50× independent citations)
W_recency       = 1.0 (< 6 months)
W_domain_fit    = 1.0
W = 0.9 × 1.0 × 1.0 × 1.0 × 1.0 = 0.9 (strong)
```

**EV-002: stackoverflow answer from 2018, single source, our regime:**

```
W_source        = 0.2
W_verification  = 0.6 (initial pin, not re-verified)
W_independence  = 0.5 (single source)
W_recency       = 0.5 (8 years, web framework half-life ~18mo, so age ~5x)
                  → actually closer to 0.3 since 8y > 4 × 18mo = 6y
W_recency       = 0.3
W_domain_fit    = 1.0
W = 0.2 × 0.6 × 0.5 × 0.3 × 1.0 = 0.018 (very weak)
```

**EV-003: paper from 2020 on distributed consensus, we re-checked the source, paper has 3 independent replications, our deployment is 10× scale:**

```
W_source        = 0.85 (mid-tier venue)
W_verification  = 0.85 (verified, not replicated by us)
W_independence  = 0.85 (3 independent)
W_recency       = 0.7 (6 years, distributed systems half-life ~5y)
W_domain_fit    = 0.85 (10× scale extrapolation)
W = 0.85 × 0.85 × 0.85 × 0.7 × 0.85 = 0.366 (weak-moderate)
```

This composite tells the Adjudicator: this evidence is real but not load-bearing. We can use it to inform but not justify a high-confidence claim.

---

## Bayesian-flavored update

For an H bead with multiple EVs supporting and refuting:

```
H_strength_after = ∏ (1 + W_supporting_i) / ∏ (1 + W_refuting_i)  (product form)
```

OR (per CONFIDENCE-SCORING.md), the simpler:

```
support_score = sum(W_supporting_i)
refute_score  = sum(W_refuting_i)
H_state:
  - if support_score > 2 × refute_score AND ≥1 EV with W ≥ 0.7: confirmed
  - if refute_score > 2 × support_score AND ≥1 EV with W ≥ 0.7: refuted
  - else: active / deferred
```

---

## Phase-specific application

### Phase 4 (investigation)

Investigators tag each EV with W_source, W_verification, W_independence, W_recency, W_domain_fit on creation. The composite W is computed automatically (e.g., via `scripts/score-ev.sh`).

### Phase 5 (adjudication)

Adjudicator evaluates support_score vs refute_score using composite W. Decisions cite specific EVs with their composite W.

### Phase 6 (distillation)

Per-family distillations include W per claim. Meta-synthesis can highlight where families weighted the same evidence differently — that's a substantive disagreement.

### Phase 7 (audit)

Audit checks: are the W values defensible? Did Investigator inflate W to support pet hypothesis?

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip explicit weighting | Defaults to vote-count, which is anti-Brenner |
| Pick weights from gut | Inconsistency across panes corrupts adjudication |
| Inflate W_source for pet sources | Audit catches this |
| Ignore W_recency for stable domains | Even DB internals evolve |
| Ignore W_domain_fit | Most weak/wrong cases come from regime mismatch |
| Hide W in description text | Make W explicit fields per BEADS-SCHEMA.md extension |

---

## Schema extension to BEADS-SCHEMA

Per BEADS-SCHEMA.md, EV-* beads should include W fields:

```yaml
type: paper
source: "<URL>"
source_id: S-NNN
W_source: 0.85
W_verification: 0.6
W_independence: 0.7
W_recency: 0.9
W_domain_fit: 0.8
W_composite: 0.26  # computed
last_updated: <ISO>
```

The `scripts/score-ev.sh` (Tier-5 script) computes the composite from the axes and updates the bead.

---

## Calibration via cross-session learning

Per CROSS-SESSION-LEARNING.md, track:

- Sessions where high-W evidence was later proven wrong → recalibrate (your W_source for that source-type was too high)
- Sessions where low-W evidence was later proven right → recalibrate (your W_independence was overcautious)

These are operator-specific. Track in OPERATOR-CALIBRATION-LOG.md.

---

## Composition with other patterns

- Per CRITIQUE-CRAFT.md: critique severity correlates with W_composite of the cited EV.
- Per CONFIDENCE-SCORING.md: H confidence emerges from W of supporting EVs.
- Per SIX-LAYER-VALIDATION.md: Layer 1 (bead invariants) verifies all W fields are present.
- Per MO-evidence-verify.md: verification updates W_verification.
