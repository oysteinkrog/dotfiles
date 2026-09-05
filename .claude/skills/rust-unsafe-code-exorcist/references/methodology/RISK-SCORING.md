# RISK-SCORING.md — Quantified Bead Prioritization

Current bead priority is qualitative (P0/P1/P2/P3 by heuristic). Quantified scoring orders the audit's work by ACTUAL impact, not vibes.

The formula:

```
RISK_SCORE = BLAST_RADIUS × LIKELIHOOD × DISCOVERABILITY
```

Each component is a 1-5 score (so total range is 1 to 125). The components are documented in [assets/risk-score-rubric.md](../../assets/risk-score-rubric.md).

---

## The components

### BLAST_RADIUS — how bad would it be?

Estimates the worst-case impact of soundness failure at this site.

| Score | Meaning |
|-------|---------|
| 1 | Internal-only; bug affects this crate's tests only |
| 2 | Public-API-reachable but library-only; bug affects this crate's users |
| 3 | Library used by 10+ downstream crates (crates.io reverse-deps) |
| 4 | Library used by 100+ downstream crates; OR a security-sensitive crate (crypto, auth) |
| 5 | System-level library (libc-binding, runtime, OS-abstraction); 1000+ downstream |

Computed from:
- `cargo metadata` + reverse-dep count (via crates.io API or local lockfile analysis).
- Manual override possible for security-sensitive sites.

### LIKELIHOOD — how likely is the unsafe to be wrong?

Estimates the probability that this site's soundness obligation is currently violated.

| Score | Meaning |
|-------|---------|
| 1 | Recent SAFETY comment; matches current call graph; reviewed in last audit |
| 2 | SAFETY comment exists but >1yr old; call graph hasn't changed materially |
| 3 | SAFETY comment is stale OR missing; manual review suggests it might still be sound |
| 4 | SAFETY comment is missing AND call graph changed since site was written |
| 5 | Already flagged by miri/loom/fuzz/cargo-careful as suspicious |

Computed from:
- Git blame on the site (age).
- Diff of call graph between site's birth commit and HEAD.
- Cross-reference with `audit/phase7/verification-log.md` (which findings touched this site).

### DISCOVERABILITY — how easy is the bug to trigger if it exists?

Estimates the probability that an attacker / user / fuzzer would actually hit the bug.

| Score | Meaning |
|-------|---------|
| 1 | Internal helper; only invoked through 1-2 callers; inputs are constrained |
| 2 | Reachable only through specific feature flags rarely enabled |
| 3 | Public API; receives arbitrary user input but constrained type (e.g., bounded int) |
| 4 | Public API; receives unstructured input (`&[u8]`, `&str`); fuzz target exists |
| 5 | Public API on a popular function; receives untrusted input; no fuzz target |

Computed from:
- Position in the call graph (depth from `pub` entry).
- Type of input (`&[u8]` and `&str` are score-5; specific primitives are lower).
- Presence/absence of fuzz targets.

---

## Per-site scoring example

```
site-0142: pub fn parse_header(buf: &[u8]) -> Result<Header, Error>
           uses unsafe { transmute::<[u8; 8], u64>(buf[0..8]) }

BLAST_RADIUS:    4  (library used by ~150 downstream crates per crates.io)
LIKELIHOOD:      3  (SAFETY comment exists from 2024; call graph unchanged)
DISCOVERABILITY: 4  (pub API; takes &[u8]; fuzz target in fuzz/parse_header.rs)

RISK_SCORE = 4 × 3 × 4 = 48
```

Compared to:

```
site-0890: fn internal_helper(x: BoundedU32) -> u32
           uses unsafe { x.0.unchecked_add(1) }

BLAST_RADIUS:    1  (internal; helper-only)
LIKELIHOOD:      1  (BoundedU32 invariant enforced by type)
DISCOVERABILITY: 1  (called once; no untrusted input)

RISK_SCORE = 1 × 1 × 1 = 1
```

The first site ranks ~48x higher; address it first. The second is a low-priority hardening task.

---

## Bead ordering

After Phase 8 generates beads, the orchestrator runs `compute-risk-score.mjs` to:

1. Parse every plan in `audit/plans/`.
2. Compute the RISK_SCORE per site.
3. Re-prioritize beads accordingly:
   - Score 60-125 → P0 (critical)
   - Score 25-59 → P1 (high)
   - Score 10-24 → P2 (medium)
   - Score 1-9 → P3 (low)
4. Emit `<audit-dir>/risk-scores.json` and `audit/synthesis/risk-summary.md` for bead review and prioritization.

The bead system surfaces highest-risk work first via `br ready --json` (which respects priority).

---

## Aggregate metrics

`audit/synthesis/risk-summary.md`:

```markdown
# Risk-Score Summary

## Distribution

| Score range | Bucket | Sites |
|-------------|--------|-------|
| 60-125 | P0 critical | 4 |
| 25-59  | P1 high     | 18 |
| 10-24  | P2 medium   | 71 |
| 1-9    | P3 low      | 154 |

## Cumulative coverage

- Addressing top 4 sites (P0) covers 23% of total risk-points.
- Addressing top 22 sites (P0 + P1) covers 64% of total risk-points.
- Addressing top 93 sites (P0 + P1 + P2) covers 92% of total risk-points.

## Recommendation

Maximum-leverage refactor batch: top 22 sites. Spend ~60% of audit's refactor budget on them.

## Per-bucket breakdown

### P0 sites

| Site | BR | LK | DC | Score | Bucket | Plan |
|------|----|----|----|-------|--------|------|
| site-0142 | 4 | 3 | 4 | 48 | (C) | audit/plans/site-0142.md |
| ... |
```

This summary is what stakeholders read to understand the audit's prioritization.

---

## Risk-Score-Aware orchestration

The orchestrator can use scores for:

- **Capacity allocation.** Agent budget = sum of risk-scores it's tackling. High-score sites get more agent-minutes.
- **Triangulation routing.** Multi-model triangulation reserved for top-N risk sites (per [TRIANGULATION.md § cost discipline](TRIANGULATION.md)).
- **Phase 6 adversarial intensity.** Top-N sites get extra adversarial attack rounds.
- **Phase 10 maintainer-empathy focus.** Reviewer reads top-N first.

The score IS the prioritization signal.

---

## Score evolution over time

Continuous mode tracks score deltas:

- Total project risk = `sum(score for every open site)`.
- Weekly delta tracked.
- "Risk velocity" = scores closed per week.

Visualized in `<audit-dir>/soundness-debt-dashboard.md`:

```
Risk score (all open sites): 4,250 → 3,890 (-360 this week)
Top 5 highest-score sites: <list>
Risk velocity: 72/week (on track to clear current backlog in ~54 weeks)
```

---

## Calibration

The 1-5 scales are subjective. Calibrate by:

1. Running the scorer on the audit.
2. Sanity-check: do the top sites match human intuition?
3. If not, adjust the rubric. The rubric is `assets/risk-score-rubric.md`; edit per-project as needed.
4. Document any adjustments in the audit's `<audit-dir>/audit/synthesis/risk-calibration.md`.

Cross-project consistency comes from sharing the rubric. Per-project flexibility comes from documented overrides.

---

## Multi-dimensional scoring (optional)

For projects that need more nuance, the score can be expanded:

```
RISK_SCORE = BLAST_RADIUS × LIKELIHOOD × DISCOVERABILITY × EXPLOITABILITY
```

EXPLOITABILITY (1-5): how easy is it to weaponize the bug?

- 1: requires specific environment; not practically exploitable.
- 5: trivially exploitable (memory corruption → RCE pathway exists).

Most audits don't need this dimension; it's reserved for security-sensitive projects (crypto, auth, sandbox escapes).

---

## Acceptance signal

A risk-scored audit passes when:

1. Every (A)/(B)/(C) site has a computed risk-score.
2. Beads are ordered by risk-score (not just qualitative priority).
3. `audit/synthesis/risk-summary.md` exists with the distribution + recommendation.
4. The dashboard reflects the current risk total.
5. Stakeholders can read a single number per site.
