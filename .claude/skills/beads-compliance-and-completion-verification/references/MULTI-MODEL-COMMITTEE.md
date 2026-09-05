# MULTI-MODEL-COMMITTEE.md — Triangulation patterns for high-stakes audits

When the audit verdict will be cited in a release decision, a regulatory submission, an incident post-mortem, or a contractual delivery — the cost of a wrong verdict outweighs the cost of running multiple models in parallel. Multi-model committee mode runs Phases 4, 5, 7, and 10 with N independent model instances and combines their outputs.

This composes with `/multi-model-triangulation` (the cross-model consensus skill).

---

## When to invoke committee mode

| Situation | Committee size | Roles |
|-----------|:--------------:|-------|
| Comprehensive mode pre-release | 3 | Opus + Sonnet + Gemini |
| SOC2 / HIPAA evidence pack | 5 | 3 Anthropic + 1 Gemini + 1 GPT |
| Security-flagged bead requiring zero false-negatives | 3 | 1 Anthropic + 1 Gemini (red-team specialist) + 1 GPT |
| Post-mortem retro audit | 3 | 1 model trained pre-incident knowledge + 2 fresh-context |
| Customer / regulator-facing audit explanation | 2 (writer + adversary) | One writes, the other adversarially edits |

For Standard / Triage / Tripwire modes, single-model is fine — committee adds 3-5x cost without proportional value.

---

## Committee phases (which phases parallelize across models)

```
Phase 4 COMPLIANCE EXEC      ── Same Phase 4 RAW outputs read by N models;
                                each emits its own compliance.json#checks
                                verdict. Final verdict = majority OR conservative
                                (any FAIL → FAIL, per-bead-type override).

Phase 5 ANTI-THEATER         ── Each model independently scans evidence files.
                                Findings are UNIONED (not majority) — a finding
                                only one model caught is still a finding. Phase 8
                                weights by detector count (3-of-3 → BLOCKING,
                                2-of-3 → MAJOR, 1-of-3 → ADVISORY).

Phase 7 SYNTHESIS            ── Independent contract-drift sweeps. Result is the
                                INTERSECTION (every model agreed it's a drift)
                                plus a "candidate drifts" appendix
                                (1-of-N caught) for human review.

Phase 10 FRESH EYES          ── Each model reviews 5 random scorecards. Disagreement
                                rate ≥ 30% → rubric ambiguity flag.
```

Phases 1, 2, 3, 6, 8, 9 are deterministic enough that committee adds noise without value. Run them once.

---

## Output: `committee.json`

```json
{
  "computed_at": "2026-05-06T16:00:00Z",
  "members": [
    {"id": "opus-4-7-1m", "role": "primary", "tokens": 245000},
    {"id": "sonnet-4-6", "role": "validator", "tokens": 180000},
    {"id": "gemini-2.5-pro", "role": "adversary", "tokens": 200000}
  ],
  "phase_4_disagreements": [
    {"bead": "bd-foo", "verdicts": {"opus": "PASS", "sonnet": "PASS", "gemini": "PARTIAL"},
     "final": "PARTIAL", "rule": "any-failure-wins for security beads"}
  ],
  "phase_5_findings_by_count": {"3-of-3": 12, "2-of-3": 4, "1-of-3": 7},
  "phase_7_drifts": {"intersection": 5, "candidates": 8},
  "phase_10_disagreement_rate": 0.12,
  "rubric_ambiguity_flags": []
}
```

---

## Combining rules

### Phase 4 verdicts (per-check)

| Bead type | Combination rule |
|-----------|------------------|
| security, auth, compliance | **Any-failure-wins**: PASS only if all members PASS. |
| migration, data-integrity | **Any-failure-wins**. |
| feature, bug | **Majority** (≥ ⌈N/2⌉). Tie → conservative (PARTIAL beats PASS). |
| docs, chore | **Majority**. |
| perf | **Median observation** (not majority verdict — combine via `perf.json` aggregation). |

### Phase 5 findings

- Union of all findings across members.
- A finding's `severity` is set per `audit-policy.yaml#committee.severity_by_count`:
  - 3-of-3 → BLOCKING
  - 2-of-3 → MAJOR (downgraded from BLOCKING if minority dissent)
  - 1-of-3 → ADVISORY (logged for human review; doesn't dock score by default)

### Phase 10 disagreement

- Each member re-scores the 5 randomly-selected scorecards.
- Compute std-dev of scores per scorecard.
- > 50 points std-dev on any scorecard → flag as RUBRIC_AMBIGUITY for that bead-type.
- Aggregate disagreement rate ≥ 30% → recommend rubric clarification before next pass.

---

## Cost calculus

| Tier | Members | Phases parallelized | Token multiplier | Wall-time multiplier |
|------|:-------:|---------------------|:----------------:|:--------------------:|
| Single-model | 1 | — | 1x | 1x |
| Committee (3) | 3 | 4, 5, 7, 10 | ~2.4x | ~1.3x (parallel) |
| Committee (5) | 5 | 4, 5, 7, 10 | ~3.5x | ~1.4x |

Wall-time multiplier < member-count because deterministic phases don't replicate.

---

## Anti-patterns

- **Cross-loading models with the same context.** Each member must be a separate session with no shared chat history; otherwise you measure context-bias, not model independence.
- **Same-vendor committee.** Three Anthropic models still share training-data correlations; for true triangulation include at least one cross-vendor (Gemini, GPT, open-weight).
- **Treating committee as voting democracy.** For security/migration beads, conservatism wins; for general beads, majority wins. The rules per-bead-type matter.
- **Letting one member's longer context "speak louder."** Cap each member at the same token budget per Phase to prevent context-asymmetry bias.

---

## Composition with other skills

- `/multi-model-triangulation` provides the cross-model orchestration layer; this doc describes how to wire its output into the audit's phases.
- `/agent-mail` provides the join keys for committee member identity tracking.
- `/ntm` provides the parallel-pane infrastructure for running members concurrently in a Swarm-tier portfolio audit.

---

## Operator pairing

`⊻ COMMITTEE` (added in this expansion) — invoke deliberately, tag findings with member-ID provenance, combine per the rules above. Pairs with `⊞ TRIANGULATE` (Phase 10), but extends it to the Phase 4-7 plane.
