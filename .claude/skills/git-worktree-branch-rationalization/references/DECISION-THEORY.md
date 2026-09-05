# Decision Theory — Bayesian + Decision-Theoretic Rigor for Triage and Harmonization

> **Why this file exists.** A wrong `superseded` verdict deletes useful work. A wrong `novel-and-accretive` verdict spends the user's time on a dud and pollutes the rationalization branch. The triage and harmonization rows in [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) and [HARMONIZATION.md](HARMONIZATION.md) carry **confidence** numbers that the user reads at face value. Those numbers had better mean something — not vibes, but principled posterior probabilities with a stated worst-case-loss interpretation. This file makes the math explicit so the rubric isn't a black box.

> **Cross-link to the kernel.** Per [SKILL.md Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms): "If a Phase 3 byte-equality check disagrees on even one entry, the run is unsafe — halt." The same coherence discipline applies to verdicts: a run whose mean-confidence is high but whose tails (the 0.60-0.74 band) are populated is a run that will land bad applies unless those tails go to MANUAL — and "MANUAL" is exactly what this file's conformal threshold makes operational.

> **Companion rigor skills.** [/multi-pass-bug-hunting](../../multi-pass-bug-hunting/SKILL.md) (the audit-fix-rescan termination criterion, formalized below as SPRT) and the broader decision-theoretic toolkit (conformal calibration, worst-case bounds, sequential testing).

---

## 1. Why Decision-Theoretic Rigor Matters Here

The skill makes destructive decisions under uncertainty. Every `triage.tsv` row is a hypothesis test:

- **H0** — the branch should be *kept* (not deleted, not merged into the rationalization branch unless it's `novel`).
- **H1** — the branch should follow its verdict's prescribed action (delete if `garbage` / `superseded` / `already-merged`, apply if `novel-and-accretive`, etc.).

Two errors are possible:

| Error | What happens | Loss |
|-------|--------------|------|
| **False supersession** (Type I) | A branch is classified `superseded` when it has truly novel content. The skill's bundle preserves the bytes, but the agent's intent attribution is lost; the user has to re-discover that the branch had novel material — and might not, because it was reported as superseded. | High — silent loss of work. The bundle survives, but the user trusted the verdict and didn't look. |
| **False novelty** (Type II) | A branch is classified `novel-and-accretive` when its content is actually already on canonical (a fingerprint heuristic missed the equivalence). The skill applies it, the apply produces a no-op or a conflict, the user wastes Phase 8 time. | Medium — wastes time but is reversible because the rationalization branch isolates the impact. |

The asymmetry — false-supersession is worse than false-novelty — drives the calibration policy in §3 and the threshold-conditional MANUAL escalation in §4.

> **Why:** [SKILL.md Polish Bar — "Verdict evidence"](../SKILL.md#the-polish-bar-non-negotiable): "Every triage row cites concrete evidence on canonical." This file makes the inverse explicit: every triage row's confidence is the *posterior probability* that the cited evidence actually supports the verdict.

---

## 2. Bayesian Confidence Calibration for Triage Verdicts

The [TRIAGE-RUBRIC.md "Confidence Calibration"](TRIAGE-RUBRIC.md#confidence-calibration) table gives qualitative bands. The bands are correct, but they're outputs, not inputs. The input is a **prior × likelihood = posterior** computation per row.

### 2.1 The prior — branch-family probability table

Every branch's name carries a prior over verdicts. The priors below are calibration defaults — empirically reasonable starting points that `verdict-stats.sh` can update mid-run via §6.

| Branch family (regex match on name) | P(garbage) | P(already-merged) | P(superseded) | P(novel-and-accretive) | P(partially-novel) | P(novel-but-stale) | P(divergent-refactor) | P(unknown) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `agent-.*-broken-attempt$` | 0.85 | 0.02 | 0.05 | 0.04 | 0.02 | 0.01 | 0.00 | 0.01 |
| `agent-.*-other-agent-broken$` | 0.85 | 0.02 | 0.05 | 0.04 | 0.02 | 0.01 | 0.00 | 0.01 |
| `agent-.*-temp-pre-push$` | 0.30 | 0.40 | 0.20 | 0.05 | 0.02 | 0.01 | 0.00 | 0.02 |
| `agent-cleanup-pass-\d+$` | 0.40 | 0.10 | 0.20 | 0.20 | 0.05 | 0.02 | 0.02 | 0.01 |
| `agent-.*-attempt-\d+$` | 0.40 | 0.10 | 0.20 | 0.18 | 0.05 | 0.04 | 0.02 | 0.01 |
| `agent-.*` (other) | 0.30 | 0.10 | 0.20 | 0.25 | 0.08 | 0.04 | 0.02 | 0.01 |
| `feature/.*` | 0.05 | 0.20 | 0.20 | 0.30 | 0.15 | 0.05 | 0.04 | 0.01 |
| `feature/.*-v\d+$` | 0.05 | 0.20 | 0.30 | 0.20 | 0.10 | 0.05 | 0.09 | 0.01 |
| `fix/.*` | 0.05 | 0.30 | 0.30 | 0.25 | 0.05 | 0.02 | 0.02 | 0.01 |
| `hotfix/.*` (auto-protected) | — | — | — | — | — | — | — | — |
| `release/.*` (auto-protected) | — | — | — | — | — | — | — | — |
| `dependabot/.*` (auto-protected) | — | — | — | — | — | — | — | — |
| `wip-.*` | 0.40 | 0.10 | 0.10 | 0.20 | 0.15 | 0.04 | 0.00 | 0.01 |
| `revert-of-\w+$` | 0.85 | 0.05 | 0.05 | 0.02 | 0.01 | 0.01 | 0.00 | 0.01 |
| `^lockfile-bump$` | 0.95 | 0.03 | 0.01 | 0.00 | 0.00 | 0.00 | 0.00 | 0.01 |
| `^autostash-.*` | 0.50 | 0.20 | 0.20 | 0.07 | 0.01 | 0.01 | 0.00 | 0.01 |
| `<everything else>` | 0.10 | 0.20 | 0.20 | 0.30 | 0.10 | 0.05 | 0.04 | 0.01 |

> **Why these priors:** the table was populated empirically from cass-mined sessions — see [CASS-MINING.md](CASS-MINING.md). In the source corpus, `agent-*-broken-attempt` branches resolved to `garbage` 85% of the time; `feature/*` branches that aren't auto-protected split roughly evenly among `superseded` / `novel` / `partially-novel`. These are starting points, not laws.

> **Why publish a prior at all:** without a prior, the rubric's "confidence" column conflates likelihood with posterior. A branch named `agent-cleanup-pass-3` with strong `novel`-pointing fingerprint evidence still has lower posterior probability of being `novel` than a `feature/*` branch with the same fingerprint, simply because more `agent-cleanup-pass-*` branches turn out to be garbage.

### 2.2 The likelihood — evidence from FINGERPRINT + VERIFY-ON-CANONICAL + cherry-summary

For each verdict V, the likelihood `P(evidence | V)` is the probability of seeing this branch's evidence pattern conditional on the true verdict being V.

```
evidence = (fingerprint_coverage, file_existence_coverage, same_signature_ratio,
            apply_check, cherry_summary, fingerprint_size)
```

Likelihoods (compact form; full table is in `scripts/triage-batch.sh`'s likelihood lookup):

| Evidence pattern | P(ev \| garbage) | P(ev \| superseded) | P(ev \| novel) | P(ev \| stale) |
|---|---:|---:|---:|---:|
| empty fingerprint AND cherry-summary all `-` | 0.05 | 0.95 | 0.001 | 0.001 |
| empty fingerprint AND cherry-summary all `+` AND no `+` content (only `-`) | 0.95 | 0.04 | 0.001 | 0.05 |
| fp-coverage ≥ 0.95 AND same-sig ≥ 0.7 AND apply-clean | 0.01 | 0.92 | 0.05 | 0.02 |
| fp-coverage ≥ 0.95 AND same-sig ≤ 0.7 (signature divergence) | 0.05 | 0.20 | 0.10 | 0.65 |
| fp-coverage ≤ 0.05 AND apply-clean AND cherry all `+` | 0.02 | 0.02 | 0.94 | 0.02 |
| fp-coverage ≤ 0.05 AND apply-fail AND file-existence ≤ 0.5 | 0.05 | 0.02 | 0.08 | 0.85 |
| fp-coverage in [0.4, 0.9] AND apply-fail AND collides-with-other | 0.05 | 0.10 | 0.05 | 0.10 (residual to `divergent-refactor` 0.70) |

(The cells must sum to ≤1.0 across all verdicts; residual mass goes to `unknown`.)

### 2.3 The posterior — Bayes' rule

For row R with branch family F and evidence E:

```
P(V | E, F) = P(E | V) × P(V | F)  /  Σ_v [ P(E | v) × P(v | F) ]
```

The **confidence column** in `triage.tsv` is the posterior `P(V | E, F)` for the chosen verdict V. The rubric's qualitative bands map onto this:

| Posterior P(V \| E, F) | Band | What the rubric says |
|---|---|---|
| ≥ 0.95 | "Multiple independent signals agree" | strong; auto-proceed |
| 0.85 – 0.94 | "Two strong signals agree" | strong; auto-proceed |
| 0.70 – 0.84 | "One strong + one weak" | proceed; user-sanity-check at Phase 6 |
| 0.60 – 0.69 | "Surface to user" | MANUAL — surfaced verbatim in Phase 6 |
| < 0.60 | force `unknown` | row goes to `unknown`, never auto-classified |

> **Why mapping qualitative bands to posteriors:** the bands as written ([TRIAGE-RUBRIC.md "Confidence Calibration"](TRIAGE-RUBRIC.md#confidence-calibration)) are good intuitions but invite drift. Tying them to posteriors makes the bands defensible against the question "why is this 0.85 and that 0.92?".

### 2.4 Worked example — agent-cleanup-pass-3 with novel fingerprint

Branch name: `agent-cleanup-pass-3`. Family: `agent-cleanup-pass-\d+$`.

**Prior:** P(garbage) = 0.40, P(superseded) = 0.20, P(novel-and-accretive) = 0.20, ... (per §2.1 row 4).

**Evidence:** FINGERPRINT extracts a single function `null_arg_guard_for_log` and a test `test_log_null`. VERIFY-ON-CANONICAL: NOT FOUND on canonical for either symbol. APPLY-CHECK: clean. cherry-summary: 1 commit, all `+`. The worktree pinned to this branch has uncommitted changes that include adding the same null-arg guard with an additional length-cap (a hint that the branch is real defensive work in progress).

The evidence pattern matches row 5 of §2.2: "fp-coverage ≤ 0.05 AND apply-clean AND cherry all `+`".

```
Likelihoods:
  P(E | garbage)     = 0.02
  P(E | superseded)  = 0.02
  P(E | novel)       = 0.94
  P(E | stale)       = 0.02

Numerator (per V):
  garbage:    0.02 × 0.40 = 0.008
  superseded: 0.02 × 0.20 = 0.004
  novel:      0.94 × 0.20 = 0.188
  stale:      0.02 × 0.02 = 0.0004

Denominator: 0.008 + 0.004 + 0.188 + 0.0004 + (residual ~0.001) ≈ 0.2014

Posteriors:
  P(garbage | E)     = 0.008 / 0.2014  ≈ 0.04
  P(superseded | E)  = 0.004 / 0.2014  ≈ 0.02
  P(novel | E)       = 0.188 / 0.2014  ≈ 0.93
  P(stale | E)       = 0.0004 / 0.2014 ≈ 0.002
```

A name-only prior would have called this `garbage` 40% of the time. The Bayesian posterior says **novel-and-accretive at 0.93**. The triage row's confidence column reads `0.93`. The rubric's band: "Two strong signals agree." Auto-proceed in Phase 8 with a `cherry-pick` strategy.

### 2.5 Worked example — agent-cleanup-pass-3 where prior wins

Same branch name. **Different evidence:** fingerprint empty (the diff is mostly `-` lines). cherry-summary all `+` (no patch-id matches; the commits aren't on canonical). APPLY-CHECK: rejects on every hunk. file_existence_coverage 0.3 (most files this branch touched have been removed from canonical).

Evidence pattern matches §2.2 row 2: "empty fingerprint AND cherry all `+` AND no `+` content (only `-`)".

```
Likelihoods:
  P(E | garbage) = 0.95
  ...

Posteriors (mostly):
  P(garbage | E) ≈ 0.40 × 0.95 / Z ≈ 0.93 (Z dominated by garbage term)
```

Same branch family, same prior, opposite evidence — posterior 0.93 for `garbage`. The triage row's confidence column reads `0.93` for the `garbage` verdict. Auto-proceed.

The key insight: the prior is **prior**, not destiny. Strong evidence overwhelms it; weak/absent evidence lets it dominate. This is what "principled, not vibes" means.

---

## 3. Conformal Prediction for Verdict Acceptance

Posterior probabilities are calibrated when, of all rows the skill labels with confidence ≥0.85, ≥85% are correct. Calibration is empirical — verified by sampling user overrides across runs (see §6).

### 3.1 The conformal threshold τ

For each run, choose a threshold τ such that:

> Of all triage rows the skill auto-accepts (confidence ≥ τ), **at least 1−τ** of accepted rows are correct in expectation.

Default τ = 0.85 (matches the rubric band "two strong signals agree"). The skill enforces τ at Phase 6:

- `confidence ≥ τ` → auto-proceed; row appears in the user-facing decision table but is not flagged for forced review.
- `0.60 ≤ confidence < τ` → MANUAL; surfaced verbatim to the user in Phase 6 (`triage_decision.md` flags these rows).
- `confidence < 0.60` → force `unknown`; the row is removed from the auto-classification path entirely.

> **Why τ = 0.85:** the rubric's existing band already aligns. Tightening τ to 0.90 reduces false-supersession at the cost of more MANUAL work; loosening to 0.80 speeds runs but increases the risk that a missed-signature case slips through.

### 3.2 The run-level coverage guarantee

When `verdict-stats.sh` reports the run's confidence distribution, the user gets a stated guarantee:

> "Of the N rows accepted at confidence ≥ τ=0.85, the expected false-classification rate is ≤15%."

If the user overrides ≥5 verdicts in Phase 6, the merger re-asks for confirmation (per [TRIAGE-RUBRIC.md "When the Rubric Is Wrong"](TRIAGE-RUBRIC.md#when-the-rubric-is-wrong)) AND the τ for downstream runs is recalibrated upward by `verdict-stats.sh` (see §6).

### 3.3 Adaptive τ for high-stakes cases

Council mode tightens τ to 0.92 (cuts the expected false-classification rate in half). The user can override τ explicitly in Phase 0 inputs, but the default for production-critical or security-sensitive content is 0.92.

> **Why mode-conditional τ:** [SKILL.md "Mode Variants"](../SKILL.md#mode-variants) — Council mode is exactly the case where false-supersession would be catastrophic. The looser default τ would still produce a strong run, but the tighter τ matches the failure cost asymmetry.

---

## 4. Worst-Case Bounds on Recovery Success

Every removal/deletion in Phase 10 is reversible via the [SAFETY-MODEL.md](SAFETY-MODEL.md) layered chain (5 layers per branch, 4 layers per worktree). The user wants to know: **what's the probability that EVERY layer survives a 30-day window?**

### 4.1 Per-layer survival probabilities

Let p_i be the probability that layer i is intact at recovery time (typically 1–4 weeks after Phase 10).

| Layer | Layer description | Default p_i (1-week window) | Default p_i (4-week window) |
|---|---|---:|---:|
| L1 | `refs/branch-rationalization-backup/<slug>` (in `.git/refs/`) | 0.999 | 0.998 |
| L2 | Object bundle `<bundle>/object-bundle.pack` (filesystem) | 0.998 | 0.995 |
| L3 | Per-branch diff `<bundle>/branches/<slug>/diff-vs-merge-base.diff` | 0.998 | 0.995 |
| L4 | Per-branch format-patch series `<bundle>/branches/<slug>/format-patch/*.patch` | 0.998 | 0.995 |
| L5 | Reflog `refs/heads/<name>` (default 90-day gc.reflogExpire) | 0.95 | 0.85 |

Defaults are conservative empirical estimates; replace with project-measured rates if known.

### 4.2 Composing the layered bound

Layers are *intended* to be independent. Layer-failure independence is not perfect — a `rm -rf <bundle>` kills L2/L3/L4 simultaneously. So the layers cluster:

- **Cluster A** = {L1, L5} — both inside `.git/`. Joint failure ≈ catastrophic repo loss.
- **Cluster B** = {L2, L3, L4} — all inside the bundle directory. Joint failure ≈ user deleted the bundle.

P(all layers fail) ≤ P(Cluster A fails) × P(Cluster B fails) (cluster failures are roughly independent — different filesystems, different physical risks).

```
P(Cluster A fails) ≈ (1 − 0.998) × (1 − 0.85) = 0.002 × 0.15 = 3 × 10⁻⁴
P(Cluster B fails) ≈ (1 − 0.998) × (1 − 0.998) × (1 − 0.998)
                   ≈ 8 × 10⁻⁹     (assuming bundle artifacts share a fate)
                   OR ≈ 1 − 0.995 = 5 × 10⁻³ if the user deletes the bundle directory in one shot

Composite worst-case (4-week, user did NOT delete bundle):
P(all layers fail) ≤ 3 × 10⁻⁴ × 5 × 10⁻³ ≈ 1.5 × 10⁻⁶ per branch
```

Per branch, over a 4-week window, the worst-case probability that EVERY recovery layer is gone is roughly **1.5 × 10⁻⁶** — about one in a million. Over 200 branches in a single run, the union bound gives ~3 × 10⁻⁴ — still very strong.

### 4.3 Tightening the bound

For users who want catastrophic-survival guarantees:

| Tightening action | Effect | Worst-case bound |
|---|---|---:|
| Default | Single-machine bundle + reflog + .git refs | 1.5 × 10⁻⁶ per branch |
| Copy bundle to second machine via `rsync` | Cluster B failure now requires both filesystems to fail | 7.5 × 10⁻⁹ per branch |
| Push bundle to S3 / B2 / Tigris via `rclone` | Adds a third independent cluster | < 10⁻¹¹ per branch |
| Tighten reflog: `git config gc.reflogExpire 365.days.ago` | Layer L5 survives a year, not 90 days | Same upper bound; deeper recovery window |
| Sign backup refs with GPG | Doesn't change probability; adds tamper-evidence | (orthogonal) |

The skill *recommends* (in `handoff_report.md`) that the user copy the bundle to a second location for high-stakes runs. The skill never *runs* the copy itself — that's outside scope.

### 4.4 What "the bound holds" actually means

A bound on P(all-layers-fail) is a *worst-case* — it does not mean "if a layer fails, recovery fails." Layer-independence is the point. As long as ONE layer is intact, [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) gives a concrete restore path. The bound's job is to ensure that the union-of-layers is robust, not to prove any single layer.

> **Why this matters:** [SKILL.md "The One Rule"](../SKILL.md): "Every worktree removal and every local branch deletion must be reversible byte-for-byte at the moment it's authorized." The bound formalizes "reversible" as a probability and lets the user reason about *how* reversible.

---

## 5. Sequential Testing for Fresh-Eyes Termination (SPRT)

Phase 9's "≥2 clean rounds" rule (Phase 9 in [PHASES.md](PHASES.md)) is a sequential hypothesis test. Frame it formally as Wald's Sequential Probability Ratio Test (SPRT).

### 5.1 The hypotheses

For round N of fresh-eyes review, the question is: "Is the run clean?"

- **H0 (run is clean):** the underlying defect rate is θ ≤ θ_safe (e.g., θ_safe = 0.01 — at most 1% of keepers have problems).
- **H1 (run has issues):** θ ≥ θ_unsafe (e.g., θ_unsafe = 0.05 — at least 5% of keepers have problems).

### 5.2 The SPRT termination rule

For each fresh-eyes round, count `n_findings` (number of issues found across all three review prompts). The SPRT log-likelihood ratio is:

```
LLR = n_findings × log(θ_unsafe / θ_safe) + (N − n_findings) × log((1 − θ_unsafe) / (1 − θ_safe))
```

Where N is the number of keepers reviewed in this round.

- If LLR ≤ log(β / (1 − α)) → **accept H0**, the run is clean. Phase 9 may terminate.
- If LLR ≥ log((1 − β) / α) → **reject H0**, issues remain. Continue to round N+1.
- Otherwise → continue.

With α = 0.01 (false-positive: declaring clean when not), β = 0.05 (false-negative: declaring issues remain when clean):

```
Lower bound: log(0.05 / 0.99) ≈ −2.99
Upper bound: log(0.95 / 0.01) ≈ 4.55
```

### 5.3 Why ≥2 clean rounds

A single clean round (n_findings = 0 over N=20 keepers) gives:

```
LLR = 0 × log(5) + 20 × log(0.95 / 0.99) ≈ 20 × (−0.041) ≈ −0.82
```

`−0.82 > −2.99` — does NOT cross the H0 acceptance threshold. The skill must run another round.

A second clean round doubles N to 40:

```
LLR = 0 × log(5) + 40 × log(0.95 / 0.99) ≈ −1.64
```

Still above `−2.99`. A third clean round:

```
LLR ≈ −2.46
```

Still above `−2.99`. By round 4, LLR ≈ −3.28 < −2.99 — H0 accepted.

So **≥2 clean rounds is not actually enough for SPRT(α=0.01, β=0.05)** if N is small. The skill's policy is a pragmatic heuristic that's calibrated for the typical Phase 9 round size of ~40+ items reviewed (across three prompts), where 2 clean rounds with N≈80 reach:

```
LLR ≈ 80 × (−0.041) ≈ −3.28
```

Which DOES cross the H0 threshold. This is why the policy reads as "≥2 clean rounds" — at typical run scales, it implements α=0.01, β=0.05 SPRT.

### 5.4 Why Comprehensive mode bumps to ≥3 rounds

Comprehensive mode reviews production-critical or security-sensitive content. Tighten α to 0.005, β to 0.025:

```
Lower bound: log(0.025 / 0.995) ≈ −3.69
```

For two clean rounds at N=80: LLR ≈ −3.28 — still above −3.69. So Comprehensive mode requires a third round to cross the tighter threshold. This is exactly the "≥3 rounds" rule in [SKILL.md "Mode Variants"](../SKILL.md#mode-variants).

> **Why pre-derive these:** the policy "≥2 rounds" is correct in practice, but it's load-bearing — if a Phase 9 reviewer thinks 1 clean round is enough, they're letting through more false-clean runs than α implies. Pre-deriving the SPRT shows why the policy is what it is and lets the user reason about adjusting it.

### 5.5 What "an issue" counts as

Per [FRESH-EYES-PROMPTS.md](FRESH-EYES-PROMPTS.md), the three prompts (rotation / harmonization-fidelity / cleanup-precondition) each return findings. `n_findings` for SPRT purposes is the count of *non-trivial* findings — typo-and-formatting findings don't count, conflicting-claims-about-source-branch DO count. The skill's `subagents/fresh-eyes.md` flags severity per finding so SPRT classification is automatic.

---

## 6. Distribution Shift Detection — Recalibrating Mid-Run

The §2.1 priors are starting points. If a particular project's branch-family distribution drifts from the corpus baseline, the skill's verdicts will be miscalibrated. `verdict-stats.sh` watches for this and recalibrates.

### 6.1 The drift signal

Per `scripts/verdict-stats.sh` ([SKILL.md "Phase 5–7 — Triage + Harmonization"](../SKILL.md#phase-57--triage--harmonization)), the skill tracks the empirical confidence distribution at Phase 6:

```
For each verdict V:
  observed_count(V) = number of rows classified V at confidence ≥ τ
  observed_count_user_override(V) = number flipped by user in Phase 6
  empirical_FPR(V) = observed_count_user_override(V) / observed_count(V)
```

If `empirical_FPR(V) > 1 − τ + δ` for some verdict V (where δ is a tolerance, say 0.05), the prior for V is mis-calibrated for this project's distribution.

### 6.2 The recalibration

When drift is detected, `verdict-stats.sh` writes a `prior_recalibration.json` that the merge step (Phase 6) consumes:

```json
{
  "project": "/data/projects/asupersync",
  "detected_drift": {
    "verdict": "garbage",
    "empirical_FPR": 0.23,
    "expected_FPR": 0.15
  },
  "recalibration": {
    "agent-cleanup-pass-\\d+$": {
      "garbage": 0.30,           // was 0.40
      "novel-and-accretive": 0.30,  // was 0.20
      "...": "..."
    }
  },
  "rationale": "User overrode 23% of garbage verdicts on agent-cleanup-pass-* family — this swarm produces more novel work than the calibration corpus suggests."
}
```

The recalibrated prior is applied to the *remaining* triage rows. Already-confirmed rows are not re-triaged; the user's overrides are recorded.

### 6.3 Recalibration boundaries

- The recalibration only applies within a single project's run. The default §2.1 priors are NOT updated globally — that would let one run with weird patterns corrupt the corpus.
- If the user completes a run with overrides, `skill_feedback.md` (Phase 12) can record the overrides as candidate corpus updates for the skill's maintenance owner.
- Recalibration is paused if the user has overridden ≥10 verdicts already — at that point the skill has lost calibration confidence and Phase 6 surfaces ALL remaining rows for review.

> **Why mid-run recalibration:** the alternative is to let bad priors poison every row in the run. Drift detection costs almost nothing, and recalibration recovers most of the value of strong priors when the project distribution genuinely differs from corpus.

---

## 7. Metamorphic Relations as Confidence Boosters

Metamorphic relations (full taxonomy in [TESTING-METAMORPHIC.md](TESTING-METAMORPHIC.md)) are oracle-free verifications. They're useful for harmonization confidence: if a synthesis preserves a metamorphic invariant that the participating variants individually preserve, the synthesis is more likely to be correct.

### 7.1 The harmonization MR

Let H(A, B) denote the synthesis of variants A and B (per [HARMONIZATION.md §4](HARMONIZATION.md)). The relevant MR is:

> **MR-Compose:** if both A and B individually preserve a domain intent X (e.g., "all logger calls reject empty messages"), then H(A, B) preserves X.

This is exactly intent-preservation as a property. The harmonization-planner subagent can sample the participating variants' tests, run them on the synthesis, and confirm that every passing test on a variant also passes on H. If yes, MR-Compose holds. If no, the synthesis dropped intent — the planner's confidence on that synthesis row should drop accordingly.

### 7.2 As a Bayesian update

For a harmonization synthesis row R with prior confidence c (from §2's per-file analysis), the MR-check is a likelihood update:

```
posterior(R correct | MR-pass) = c × P(MR-pass | R correct) / [ c × P(MR-pass | R correct) + (1−c) × P(MR-pass | R wrong) ]
```

With P(MR-pass | R correct) ≈ 0.99 and P(MR-pass | R wrong) ≈ 0.20:

```
prior c = 0.85, MR-pass:
  posterior ≈ 0.85 × 0.99 / (0.85 × 0.99 + 0.15 × 0.20) ≈ 0.965
```

A passing MR-Compose check raises a 0.85-confidence synthesis to 0.965. Failure drops it sharply:

```
prior c = 0.85, MR-fail:
  posterior ≈ 0.85 × 0.01 / (0.85 × 0.01 + 0.15 × 0.80) ≈ 0.066
```

A failed MR-Compose check is decisive — the synthesis is almost certainly wrong; the user must review.

### 7.3 The self-check loop

The harmonization-planner subagent runs MR-Compose on every synthesis row at confidence < 0.95 (high-confidence rows already have multiple agreeing signals; the MR is supplementary). Failures get flagged in `harmonization_plan.md` with the dropped-intent identified. Cross-link to [TESTING-METAMORPHIC.md MR-4 "Intent preservation"](TESTING-METAMORPHIC.md#the-metamorphic-relations).

### 7.4 Composition of MRs

If a synthesis passes MR-Compose AND MR-Idempotence (re-running synthesis is a no-op) AND MR-Commutativity (order-independent) — see [TESTING-METAMORPHIC.md](TESTING-METAMORPHIC.md) — confidence climbs further. With three independent MRs each at P(pass | correct)=0.99 and P(pass | wrong)=0.20, prior 0.85:

```
posterior ≈ 0.85 × 0.99³ / (0.85 × 0.99³ + 0.15 × 0.20³)
         ≈ 0.85 × 0.97 / (0.85 × 0.97 + 0.15 × 0.008)
         ≈ 0.999
```

Three independent MR passes drives confidence near 1.0. This is the principled path from "the planner is plausible" to "we're done — Phase 8 may proceed."

---

## 8. Worked Example — The Subtle Agent-Cleanup Branch

A single end-to-end example showing prior, evidence, posterior, and MR check.

### 8.1 The branch

`agent-cleanup-pass-3` on a project where canonical is `master`. The branch's diff vs canonical:

- `src/util/logger.rs`: adds a function `null_arg_guard_for_log` and modifies `log()` to call it.
- `tests/log_null.rs`: new test file.
- The worktree pinned to this branch (at `/data/projects/foo--wt-3`) has uncommitted changes that further tighten the guard with a length-cap.

`cherry -v` shows: 1 commit, all `+`. APPLY-CHECK: clean. fingerprint_coverage on canonical: 0% (neither symbol exists). file_existence_coverage: 100% (both files are reachable from canonical). same_signature_ratio: N/A (the symbols don't exist on canonical to compare).

### 8.2 The prior-only verdict (naive — what name-pattern alone would say)

Branch family `agent-cleanup-pass-\d+$` has prior P(garbage) = 0.40, P(novel) = 0.20. Prior alone says **garbage** (highest mass). Confidence 0.40. Below threshold τ = 0.85 — flagged MANUAL.

A naive skill that uses only name-prior would surface this row to the user. The user reads "agent-cleanup-pass-3 → garbage" and either accepts (loses the work) or overrides (correct, but tedious). Across 50 such branches the user is doing 50 manual reviews.

### 8.3 The Bayesian posterior (the skill's actual behavior)

Evidence pattern: §2.2 row 5 — "fp-coverage ≤ 0.05 AND apply-clean AND cherry all `+`" — likelihoods (0.02 garbage / 0.02 superseded / 0.94 novel / 0.02 stale).

Numerator and denominator per §2.4:

```
P(novel | E) ≈ 0.93
```

The triage row's confidence column reads **0.93** for `novel-and-accretive`. Above τ = 0.85 — auto-proceed. The user sees one row in `triage_decision.md` saying "agent-cleanup-pass-3 → novel-and-accretive (0.93) — apply via cherry-pick" and does NOT have to manually review.

### 8.4 The harmonization layer

Now suppose `feature/length-cap` ALSO touches `src/util/logger.rs`. Phase 7 builds the variant matrix per [HARMONIZATION.md §2](HARMONIZATION.md). Rows: `canonical`, `agent-cleanup-pass-3` (null-arg guard), `feature/length-cap` (length-cap), `worktree:data-projects-foo--wt-3` (null-arg + length-cap, both tighter).

The planner's per-variant confidence (from §7's combined Bayesian + MR analysis):

| Variant | Initial planner conf (vibes) | Bayesian posterior | After MR-Compose | After MR-Compose + MR-Idempotence + MR-Commutativity |
|---|---:|---:|---:|---:|
| agent-cleanup-pass-3 (null-arg) | 0.85 | 0.92 | 0.97 | 0.999 |
| feature/length-cap | 0.85 | 0.93 | 0.98 | 0.999 |
| worktree:data-projects-foo--wt-3 (worktree dirty-state) | 0.45 | 0.45 | (n/a, dirty-state lacks tests) | 0.45 |

The synthesis row for the contested file `src/util/logger.rs` carries the *minimum* of the row confidences (the synthesis is only as strong as its weakest variant). 0.45 < 0.7, so per [HARMONIZATION.md §5](HARMONIZATION.md), the row is forced to user review with the dirty-worktree variant flagged.

The user reviews the worktree variant, decides whether to lift it, signs off. The synthesis lands.

> **Why this is the right behavior:** without rigor, a planner might either (a) auto-accept the worktree variant because "it has more guards, must be better" (false-novelty) or (b) auto-drop it because "dirty state isn't real until committed" (false-supersession of the user's in-progress work). The Bayesian + MR combination correctly says "the variant is real but our evidence is thin — surface to user."

---

## 9. Cross-References

- [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) — the qualitative bands this file calibrates
- [HARMONIZATION.md](HARMONIZATION.md) — confidence column on synthesis rows
- [SAFETY-MODEL.md](SAFETY-MODEL.md) — the layered recovery chain whose composition §4 bounds
- [TESTING-METAMORPHIC.md](TESTING-METAMORPHIC.md) — the MR taxonomy referenced in §7
- [FRESH-EYES-PROMPTS.md](FRESH-EYES-PROMPTS.md) — Phase 9 review prompts whose termination §5 formalizes
- [PHASES.md](PHASES.md) — Phase 6 (triage merge), Phase 9 (fresh-eyes) where these rules apply
- [MEASUREMENT.md](MEASUREMENT.md) — the SLO surface that exposes calibration metrics
- [/multi-pass-bug-hunting](../../multi-pass-bug-hunting/SKILL.md) — the audit-fix-rescan pattern §5 formalizes

---

## 10. The Mantra

> **Priors aren't superstition; evidence isn't oracle. Compute the posterior; surface the threshold; bound the worst case; terminate the loop with a stated false-rate. If you can't write down the probability, you can't defend the verdict.**
