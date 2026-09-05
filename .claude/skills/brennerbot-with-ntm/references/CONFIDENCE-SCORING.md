# CONFIDENCE-SCORING.md — How to Score Confidence in Hypotheses, Evidence, and Distillations

<!-- TOC: Hypothesis confidence | Evidence confidence | Distillation confidence | Recommendation confidence | Audit-finding confidence | Scoring discipline | Phase 7 audit role | Cross-session confidence drift -->

Vibes-based confidence is anti-Brenner. This file specifies the rubric for scoring confidence at every layer.

Mirrors wills-and-estate-planning's CONFIDENCE-SCORING.md but tuned for research-session output.

---

## Hypothesis confidence (`H-*.confidence` field)

Five-level scale: `high | medium | low | speculative` (with refuted/superseded as terminal states).

### `speculative`
- Newly proposed; no evidence yet
- Born from `⊕ Cross-Domain` import or `◊ Paradox-Hunt`
- Default for `origin:third_alternative` at Phase 3 exit

### `low`
- ≥1 supporting `EV-*` from a single source domain
- No falsifier attempts yet
- Or: prior confidence reduced by a critique that didn't fire the falsifier

### `medium`
- ≥2 supporting `EV-*` from same or adjacent source domains
- ≥1 falsifier attempt completed (didn't fire)
- Survived ≥1 informal probe (e.g., quickie pilot)

### `high`
- ≥3 supporting `EV-*` from independent source domains
- ≥1 falsifier attempt across multiple plausible attack angles
- Survived ≥1 formal Phase 5 debate (with rebuttals on record)
- All assumptions of `type:scale_physics` have verified `calculation:` blocks

### `confirmed` (state, not confidence)
- All `high` requirements PLUS
- Adjudicator formally settled in `DEBATE-NNN`
- Phase 7 audit didn't surface critical findings against this H

### `refuted` (state, not confidence)
- Falsifier event observed and verified per MO-falsifier-fired.md
- `refuted_by:` field non-empty

---

## Evidence confidence (`EV-*.verified` flag + implicit weight)

### `verified: false` (default)
- Imported from corpus / cass / external; not yet independently re-checked
- Cited but treatable as provisional

### `verified: true`
- Investigator (or another pane) independently navigated to the source AND confirmed the verbatim excerpt is accurate
- Verification recorded in `evidence/verification_log.md`

### Implicit weight (not a field, but a discipline)

When citing an EV in a distillation, weight by:

- **Source independence** — is this EV's source independent of other cited EVs? (Same paper cited 5x is 1 EV, not 5)
- **Verification status** — verified > unverified
- **Source quality** — primary > secondary > derivative; corpus > cass-mined-prior > general-knowledge
- **Recency / volatility** — pinned content-hash > unpinned external > volatile (e.g., a benchmark blog post that may be edited)

Phase 6 meta-synthesis should weight independent verified primary EVs over correlated unverified secondary EVs, and explicitly note when the kernel rests heavily on a single source.

---

## Distillation confidence (per-family + meta)

### Per-family distillation confidence (`distillations/by_<family>.md`)

Self-rated by the Synthesizer pane:

- **Strong** — the per-family distillation cleanly explains all surviving Hs and the disagreement register reflects deliberate choices
- **Moderate** — some Hs are explained tentatively; some load-bearing claims rest on thin EVs
- **Tentative** — one or more H families are under-investigated; distillation is provisional until Phase 4 reopen

Each distillation includes a "Confidence note" section stating the level and reasoning.

### Meta-synthesis confidence

Overall confidence per claim in `meta_synthesis.md`. Each major claim should be tagged:

- **[K] Kernel** — agreed across all per-family distillations; load-bearing
- **[M] Majority** — agreed by N-1 of N families; check disagreement register
- **[D] Disputed** — explicitly resolved in disagreement register; cite resolution
- **[O] Open** — meta-synthesis cannot resolve; needs Phase 4 reopen

The handback briefing should report the [K] count, [M] count, [D] count, [O] count to give the user a confidence-weighted view.

---

## Recommendation confidence (Phase 9 handback)

For each "recommended next step" in HANDBACK.md, tag:

- **High confidence:** [K] kernel claims; verified EVs; survived Phase 5 + 7
- **Medium confidence:** [M] majority claims; verified EVs; survived Phase 5
- **Low confidence:** [D] disputed claims with specific evidence required; or [O] open
- **Speculative:** ⊕ Cross-Domain imports that survived the session but haven't been deeply investigated

The user reads confidence to decide which recommendations to act on now vs which need another loop.

---

## Audit-finding confidence

`audit-finding-*.severity` field already implies confidence:

- **Critical** — falsifier-grade evidence the artifact is wrong; must address before exit
- **High** — strong evidence of a methodology violation or substantive error
- **Medium** — concerning pattern; should address but defer if time-pressed
- **Low** — typo, formatting, minor consistency issue

Severity is not just impact — it's confidence × impact. A vague "this might be wrong" without evidence is `low` regardless of how scary the implication is.

---

## Scoring discipline

Don't over-score. Honest tentative > confident-but-wrong. The Phase 6 disagreement register exists precisely to capture "we don't know" claims so they don't get silently rounded up to "we know".

When in doubt:

- Hypothesis: prefer `medium` over `high` unless all `high` requirements demonstrably hold
- Evidence: prefer `verified: false` until verification is logged
- Distillation: prefer `[D]` or `[O]` over `[K]` if any disagreement exists
- Recommendation: prefer `medium` over `high` unless every condition holds

The handback's value comes from honesty about uncertainty, not from a confident-sounding verdict.

---

## Phase 7 audit role

Phase 7 audit explicitly checks:

- Are `H-*.confidence` levels consistent with the evidence packs?
- Are `EV-*.verified` flags backed by `verification_log.md` entries?
- Are distillation [K] tags backed by genuine cross-family agreement?
- Are HANDBACK.md confidence levels honest?

Findings of "over-stated confidence" are `severity:high` audit findings — they corrupt the user's downstream actions.

---

## Cross-session confidence drift

Phase 10 drift-check reads the prior session's RESUME.md confidence levels and compares to the current session's verdicts. Drift patterns:

- **Persistent over-confidence:** sessions consistently rate H `high` that get refuted in subsequent sessions → calibrate down
- **Persistent under-confidence:** sessions rate H `medium` that prove robust → calibrate up
- **Confidence regression:** later sessions score lower confidence than earlier sessions on same claims → either evidence base eroded OR earlier sessions were over-confident

Calibration findings get fed back as Phase 10 lessons into this skill's references/.
