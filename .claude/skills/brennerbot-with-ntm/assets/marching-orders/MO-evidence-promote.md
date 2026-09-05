# MO-evidence-promote.md — Promote a Low-Confidence EV to High-Confidence

**Phase:** 4 (post-investigation) or 7 (audit)
**Operators activated:** ✂ Exclusion-Test, 🔧 DIY (replication), ≡ Invariant-Extract
**Parameters:** `<EV_ID>`, `<TARGET_CONFIDENCE>` (high), `<SESSION_ID>`, `<PANE_N>`

---

When an EV bead's load-bearing weight is high but its `W_composite` (per EVIDENCE-WEIGHTING-TAXONOMY.md) is below the threshold for `confidence:high`, this MO formalizes the promotion procedure.

Promotion isn't free: it requires independent verification, replication (where feasible), and adjudicator sign-off.

---

**Step 1 — Verify EV exists and is currently low-confidence.**

```bash
ev_ref="<EV_ID>"
ev_id="$(br list --all --json | jq -r --arg ref "$ev_ref" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' | head -1)"
[ -n "$ev_id" ] || { echo "No bead found for public ref: $ev_ref" >&2; exit 1; }
br show "$ev_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' | grep -E 'W_composite|confidence'
```

If already `confidence:high`, abort (already promoted).

If composite W < 0.4, this is too weak to promote in one step; defer or seek stronger evidence first.

**Step 2 — Identify the load-bearing claim.**

The EV supports/refutes specific Hs. List them:

```bash
br show "$ev_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' | grep -E 'supports:|refutes:|informs:'
```

For each supported H, compute the W_composite contribution. If this EV is the load-bearing evidence for the H (i.e., removing it would significantly reduce W aggregate), promotion is justified.

If this EV is corroborating but not load-bearing, promotion is optional.

**Step 3 — Check current axes.**

Per EVIDENCE-WEIGHTING-TAXONOMY.md, the 5 axes:

```
W_source        — current value
W_verification  — current value
W_independence  — current value
W_recency       — current value
W_domain_fit    — current value
W_composite     — product
```

Identify the weakest axis. That's the bottleneck for promotion.

**Step 4 — Strengthen the weakest axis.**

### W_source weak (paywalled / single-author / non-peer-reviewed)

Find a corroborating peer-reviewed source. Compose with /software-research or /cass for prior brennerbot sessions on the topic.

### W_verification weak (initial pin only)

Per MO-evidence-verify.md: dispatch a different pane to re-read source and confirm verbatim. Update verification_log.md.

### W_independence weak (single source)

Find ≥2 additional independent sources. Per QUOTE-BANK-METHODOLOGY.md: independent = different authors, institutions, methodology. File new EV-NNN cross-referencing the original.

### W_recency weak (stale)

Re-verify the source per VERIFICATION-FIRST.md class-specific cadence. If source has been updated, capture new version with content hash. If source is unchanged, update `analyses/official-source-log.md` `last_verified_at`.

### W_domain_fit weak (regime mismatch)

Replicate the experiment under our specific regime (per MO-academic-replication). If our replication confirms, file as a separate EV with W_domain_fit = 1.0.

**Step 5 — Re-compute composite W.**

After strengthening the weak axis, recompute. If `W_composite ≥ 0.7`, promotion is justified.

If still < 0.7, multiple axes need strengthening; this is acceptable, but each strengthening is its own protocol. Run sequentially.

**Step 6 — Update the EV bead.**

```bash
br update "$ev_id" --description="$(br show "$ev_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' \
    | sed -E 's/W_(source|verification|independence|recency|domain_fit): [0-9.]+/<updated value per Step 4>/g' \
    | sed -E 's/W_composite: [0-9.]+/W_composite: <new>/' \
    | sed -E 's/confidence: low/confidence: high/' \
    | awk '1; END { print "promoted_at: " strftime("%Y-%m-%dT%H:%M:%SZ"); print "promoted_by: <PANE_N>" }')"
```

**Step 7 — Adjudicator review.**

For T3+ sessions, the adjudicator (per ROSTER-PLANS.md, must be cross-family) reviews the promotion:

- Are the strengthened axes legitimate?
- Does the W_composite calculation hold?
- Is the cross-referencing accurate?

If adjudicator rejects: file a counter-update that downgrades the promotion and documents the rejection in `audit-findings/`; do not delete the original EV.

**Step 8 — Update H state if needed.**

Per CONFIDENCE-SCORING.md, an H's state may flip from `active` to `confirmed` once supporting EVs cross W threshold. Re-evaluate H state:

```bash
# Re-compute support_score, refute_score using updated W:
support_score = sum(W_supporting_i)
refute_score  = sum(W_refuting_i)
```

If state flips, update H bead with explicit citation to the promoted EV.

**Step 9 — Cross-session impact.**

If this EV was cited in prior sessions (per /cass + /flywheel), the promotion may invalidate or confirm prior verdicts. Document in `analyses/cross-session-impact.md`.

---

**Anti-patterns:**

- ✗ Promote without strengthening axes (just inflate the W field)
- ✗ Skip adjudicator review (operator self-promotion = anti-Brenner)
- ✗ Skip H state re-evaluation (promotion is local; impact is session-wide)
- ✗ Promote based on time (not strength change) — staleness shouldn't promote
- ✗ Promote in batches without per-EV justification

**Ship-or-Surface SLA:** within 30-60 min per EV (depends on which axis to strengthen).

---

## When promotion is impossible

Sometimes an EV's W can't be promoted within session budget:
- Source is paywalled and we lack access
- Replication requires resources we don't have
- Independent corroboration doesn't exist in literature

In these cases:
- Document the W axes that couldn't be improved
- Mark the EV as `unable_to_promote: true; reason: <specific>`
- Use the EV at its current W; load-bearing claims that depend on un-promoted EVs are flagged in HANDBACK as caveats

This is honest reporting of methodology limits.

---

## Composition with other patterns

- Per MO-evidence-verify: independent verification raises W_verification
- Per MO-academic-replication: replication raises W_domain_fit
- Per CASS-MINING-RECIPES: prior-session search may surface independent corroboration
- Per CRITIQUE-CRAFT: severity of critique correlates with W of disputed EV

---

## Cross-references

- EVIDENCE-WEIGHTING-TAXONOMY.md (the W axes)
- CONFIDENCE-SCORING.md (the H confidence rubric)
- MO-evidence-verify.md (verification pass)
- MO-academic-replication.md (replication pass)
- VERIFICATION-FIRST.md (per-class re-verification)
