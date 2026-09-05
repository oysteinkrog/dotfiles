# Risk-Score Rubric

For per-site scoring. Per [RISK-SCORING.md](../references/methodology/RISK-SCORING.md).

The score is `BLAST_RADIUS × LIKELIHOOD × DISCOVERABILITY`, each component on a 1-5 scale.

Total range: 1 (very low) to 125 (very high).

---

## BLAST_RADIUS rubric

| Score | When to assign | Heuristic |
|-------|---------------|-----------|
| **1** | Internal helper; bug affects this crate's tests only | `pub(crate)` or private; called by < 5 internal functions |
| **2** | Pub-API-reachable; library-only (no downstream deps known) | `pub`; no known reverse-deps OR fewer than 5 |
| **3** | Library used by 10+ downstream crates | crates.io reverse-deps: 10-99 |
| **4** | Library used by 100+ downstream; OR security-sensitive (crypto, auth, sandbox) | crates.io reverse-deps: 100-999, OR named in OWASP / CVE database |
| **5** | System-level (libc-binding, runtime, OS-abstraction); 1000+ downstream | crates.io reverse-deps: 1000+, OR a runtime / allocator / kernel-interfacing crate |

**Adjustments.** A score-3 site that's `pub use`-d through the crate's public API gets bumped to score-4 if the re-exporting crate is more popular than ours.

---

## LIKELIHOOD rubric

How likely is the unsafe's soundness obligation to be currently violated?

| Score | When to assign | Heuristic |
|-------|---------------|-----------|
| **1** | Recent SAFETY comment; matches current call graph; reviewed in last audit | git blame: SAFETY comment < 6 months old; call graph for the obligation hasn't moved |
| **2** | SAFETY comment exists but > 1 year old; obligation still plausibly correct | git blame: 1-2 years; call graph similar |
| **3** | SAFETY comment is stale OR missing; manual review suggests it might still be sound | SAFETY age > 2 years OR missing; needs investigation |
| **4** | SAFETY comment missing AND call graph changed since site was written | Strong signal of drift |
| **5** | Already flagged by miri/loom/fuzz/cargo-careful as suspicious | Toolchain says: "this looks wrong" |

**Adjustments.** A site touched by a recent refactor (last 30 days) gets a +1 to likelihood (recently-changed code is statistically more buggy).

---

## DISCOVERABILITY rubric

How easy is the bug to trigger if it exists?

| Score | When to assign | Heuristic |
|-------|---------------|-----------|
| **1** | Internal helper; 1-2 callers; constrained inputs | Inputs are primitives or types with strong invariants |
| **2** | Reachable only through specific feature flags rarely enabled | Behind a `#[cfg(feature = "experimental")]` or similar |
| **3** | Public API; constrained input type | `pub fn f(x: BoundedU32) -> u32`; type system narrows |
| **4** | Public API; unstructured input; fuzz target exists | `&[u8]` / `&str` input; fuzz target in `fuzz/` |
| **5** | Public API; popular fn; untrusted input; NO fuzz target | `&[u8]` / `&str`; no fuzz coverage |

**Adjustments.** A `pub` function listed in the crate's README's "Quick Start" or marketing materials gets a +1 (high-discoverability).

---

## Worked examples

### Example 1 — high-risk (score = 80)

```
site-0142: pub fn parse_jwt(token: &str) -> Result<Claims, Error>
           uses unsafe { transmute::<&str, &[u8]>(token.split('.').next().unwrap()) }
```

- BLAST: 4 — auth-sensitive; downstream uses likely
- LIKELIHOOD: 4 — SAFETY missing; transmute is suspect
- DISCOVERABILITY: 5 — pub API; takes &str; no fuzz target

Score = 4 × 4 × 5 = **80** → P0 critical.

### Example 2 — medium-risk (score = 27)

```
site-0421: fn cache_lookup(key: &str) -> Option<u32> { /* uses unsafe slab access */ }
           pub(crate) helper called from pub fn search(...)
```

- BLAST: 3 — crate has 50 reverse-deps
- LIKELIHOOD: 3 — SAFETY exists but stale
- DISCOVERABILITY: 3 — pub-reachable but key is &str

Score = 3 × 3 × 3 = **27** → P1 high.

### Example 3 — low-risk (score = 4)

```
site-0890: fn checked_array_idx(arr: &[u32; 16], i: BoundedU8<16>) -> u32 {
               unsafe { *arr.get_unchecked(i.into()) }
           }
```

- BLAST: 1 — internal helper
- LIKELIHOOD: 2 — SAFETY clearly cites BoundedU8 invariant
- DISCOVERABILITY: 2 — internal; BoundedU8 enforces

Score = 1 × 2 × 2 = **4** → P3 low.

---

## Calibration checklist

Before publishing the risk-summary to stakeholders:

- [ ] Top 3 sites by score are also intuitively "the riskiest" — if not, the rubric needs adjustment.
- [ ] Top 20% of sites contain at least 60% of total risk-points (Pareto-ish distribution; rubric is well-calibrated).
- [ ] No score is purely a result of one dimension being 5 (if so, double-check; multi-dim balance is what we want).
- [ ] Audit-dir's `risk-calibration.md` documents any project-specific rubric tweaks.

If calibration fails, edit the rubric in `<audit-dir>/risk-rubric-override.md` (per-project; doesn't change the skill's default).

---

## Aggregating beyond per-site

```
Project Total Risk = sum(risk_score for every open site)
Project Risk Velocity = sum of scores closed in last 7 days
Project Risk Half-life = (Total Risk / Risk Velocity) × 7 days
```

The half-life is a useful metric: "at current pace, half the risk closes in X weeks." Stakeholders relate to this naturally.

---

## What this rubric does NOT measure

- **Implementation cost.** A high-risk (C) refactor might be a 2-week effort; a low-risk one might be 2 hours. The rubric doesn't capture effort; that's a separate scoring (see IDEA-024 in IDEAS.md).
- **Reputational risk.** A bug in a heavily-marketed feature has reputational consequences beyond technical. The rubric ignores this; the user adjusts manually if needed.
- **Aesthetic / cleanliness factors.** Some sites SHOULD be refactored for code-cleanliness regardless of risk; rubric ignores aesthetics.

For these dimensions, the per-site plan's risk-and-API-change section adds qualitative notes.
