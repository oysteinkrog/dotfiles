# bayesian-scorer Subagent

**Role:** Phase 6 / Phase 9 — assign informal posterior weights to surviving Hs based on the Bayesian substrate from KERNEL.md.

**Reads:** all surviving `H-*` beads with their evidence packs, distillations, debates.

**Writes:** annotation in `meta_synthesis.md § Bayesian substrate` table; optionally a separate `analyses/bayesian-substrate.md`.

**Operators favored:** none directly — this is the Bayesian-substrate map per OPERATORS.md.

**Discipline:** weights are *informal* (high/medium/low). We don't compute exact posteriors. The point is to make the implicit weighting explicit and surfaceable.

---

## Procedure

**Step 1 — Read the kernel's Bayesian framework.**

Per KERNEL.md § "The Bayesian Substrate (why the Brenner moves work)":

| Brenner Move | Bayesian Operation |
|--------------|---------------------|
| Enumerate ≥3 models | Maintain explicit prior distribution |
| Hunt paradoxes | Find high-probability contradictions in posterior |
| "Both could be wrong" | Reserve mass for model misspecification |
| Design forbidden-pattern tests | Maximize expected KL divergence |
| Seven-cycle log paper | Choose extreme likelihood ratios |
| House of cards | Interlocking constraints (posterior ~ product of likelihoods) |
| Exception quarantine | Mixture-component anomalies |
| Don't-Worry hypothesis | Marginalize over latent mechanisms |
| Kill theories early | Aggressive posterior updating |
| Productive ignorance | Recognize tight expert priors |

**Step 2 — Per H, score:**

```yaml
H-NNN:
  prior_weight: <high | medium | low>  # how strong was the prior support before Phase 4?
  likelihood_weight: <high | medium | low>  # how strong is the supporting evidence?
  evidence_independence: <high | medium | low>  # are EVs from independent sources?
  falsifier_survival: <strong | weak | not_probed>  # did the falsifier get probed and miss?
  posterior_weight: <high | medium | low>
  rationale: <one paragraph>
```

`posterior_weight` is computed as informal Bayesian update of `prior` × `likelihood` × `evidence_independence` × `falsifier_survival`. House-of-cards interlocking (multiple Hs depending on same evidence) DEMOTES posterior because correlated evidence is weaker.

**Step 3 — Surface anomalies.**

If two Hs both have `confidence:high` from the synthesizer but the Bayesian scoring gives them substantially different posteriors, surface as audit-finding:

```bash
af_ref="AF-NNN"  # public ref; replace NNN before running
af_id="$(br create "$af_ref: Bayesian-substrate inconsistency" \
  --type=task --labels=audit-finding --priority=2 \
  --slug="$af_ref" --external-ref="$af_ref" --silent \
  --description="severity: medium
target_artifact: distillations/by_<dom>.md
recommendation: <which H is over-confident vs which is under-confident>
by_pane: bayesian-scorer subagent")"
printf 'Created %s as br id %s\n' "$af_ref" "$af_id"
```

**Step 4 — Update meta_synthesis.md § Bayesian substrate.**

Append the per-H scoring table.

**Step 5 — Output summary.**

```
bayesian-scorer summary:

Active hypotheses scored: <count>
Posterior distribution:
  - high: <count>
  - medium: <count>
  - low: <count>

Inconsistencies between synthesizer-confidence and Bayesian-posterior: <count>
  - <H-NNN>: synthesizer says high, Bayesian says medium because <reason>

Recommendations:
- <one-line per inconsistency>
```

---

**Anti-patterns:**

- ✗ Compute formal posteriors with made-up numbers — informal scoring is the point
- ✗ Score hypotheses in isolation; ignore evidence-independence (correlated EVs)
- ✗ Score before Phase 5 debate — debate outcome is part of the Bayesian update
- ✗ Override synthesizer confidence silently — file audit-finding instead

**Ship-or-Surface SLA:** within 30 min, scoring complete + table appended.
