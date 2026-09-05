# CITATION-PROVENANCE-RULES.md — Anchor Taxonomy + Provenance Discipline

<!-- TOC: Why provenance matters | The 6 provenance categories | Anchor format catalog | Per-anchor lint rules | The fake-anchor disqualifier | Inference vs verbatim discipline | Synthesis markers | External + axiomatic markers | Per-phase enforcement | Anti-patterns | Cross-references -->

Every claim in a brennerbot artifact must trace to a specific source. Without disciplined citation, the artifact loses audit value — and Phase 7 fresh-eyes audit becomes "trust me" instead of "verify."

This file is the canonical citation taxonomy: 6 provenance categories, 10+ anchor formats, machine-checkable rules, and disqualifier for fake anchors.

Mined from `/dp/brenner_bot/specs/artifact_linter_spec_v0.1.md § Citation & Provenance Rules` and `/dp/brenner_bot/specs/role_prompts_v0.1.md` Output Contract.

---

## Why provenance matters

Three failures of unsourced claims:

1. **Hallucination decay** — agents confabulate sources confidently; no audit catches it
2. **Drift across rounds** — the original source disappears as claims morph
3. **Stale-knowledge bleed** — model training data leaks into "the corpus says..."

Three benefits of disciplined provenance:

1. **Verifiable** — every claim has a check
2. **Audit-stable** — Phase 7 reviewer can resolve every anchor
3. **Cross-session-comparable** — different sessions citing the same source make assertions about that source explicit

The rule: **no claim without an anchor**. The anchor type is your honesty signal.

---

## The 6 provenance categories

Every claim in an artifact section falls into exactly one:

| Category | Marker | Meaning | Audit requirement |
|----------|--------|---------|---------------------|
| Quote-backed | `§n` | Direct citation from Brenner transcript | Anchor must exist in `complete_brenner_transcript.md` |
| Multi-source | `§n, §m, ...` | Synthesized from multiple sections | All anchors must exist |
| Inference | `[inference]` | Agent-derived conclusion | Must follow from cited context |
| Inference+Source | `[inference] from §n` | Inference grounded in source | Anchor must exist |
| External | `[external: source]` | From non-corpus, non-evidence-pack source | Source must be identified |
| Axiomatic | `[axiomatic]` | Foundational assumption | No further justification needed (rare) |

Plus evidence pack anchors (per EVIDENCE-PACK-PROTOCOL.md):

| Category | Marker | Meaning |
|----------|--------|---------|
| Evidence (whole) | `EV-NNN` | Whole evidence record |
| Evidence (excerpt) | `EV-NNN#E<n>` | Specific excerpt |
| Evidence (verbatim) | `EV-NNN#E<n> [verbatim]` | Direct quote |

---

## Anchor format catalog

### Brenner transcript anchors

```
§n              # single section
§n, §m          # multiple sections
§n-§m           # range (sections n through m)
§n.k            # subsection (e.g., §58.2)
```

Validation: anchor numbers must exist in `complete_brenner_transcript.md`. `scripts/validate-anchors.sh` is a planned validator; until it exists, Phase 7 auditors must manually cross-check every `§` reference against `references/SOURCE-CORPUS.md`.

### Evidence pack anchors

```
EV-001          # whole record
EV-001#E1       # excerpt 1
EV-001#E2 [verbatim]   # excerpt 2, marked as direct quote
EV-001#E3 [paraphrase] # excerpt 3, paraphrased
```

Validation: EV record must exist in `evidence.json`; excerpt anchor must exist within the record.

### Inference markers

```
[inference]                      # agent reasoning beyond evidence
[inference] from §58             # inference grounded in source
[inference] from EV-007          # inference grounded in evidence
[inference] across [§58, EV-007] # inference grounded in multiple sources
```

The grounded form (`[inference] from <source>`) is preferred for high-stakes claims. Bare `[inference]` is acceptable for low-stakes derivations.

### Synthesis markers

```
[synthesis]                          # synthesis across distillations
[synthesis] of {Opus, GPT, Gemini}   # explicit triangulation
[synthesis] from §58 + EV-007        # multi-source synthesis
```

Synthesis is the *combining* of multiple sources, not the *citation* of any single one. Use when the claim couldn't be derived from any single source.

### External markers

```
[external: NIST AI RMF 1.0]          # external standard
[external: doi:10.1146/...]          # external paper not in evidence pack
[external: github.com/foo/bar]       # external code reference
```

Use when the source is real but not formally imported into the evidence pack. The reviewer should treat this as a weaker citation than a `EV-NNN` (which has been excerpted + verified).

### Axiomatic markers

```
[axiomatic]
```

Reserved for foundational assumptions — usually scale-physics or domain-axiom assumptions that need no further justification. Use sparingly; per Phase 7 audit, every `[axiomatic]` claim is challenged: "is this really axiomatic, or is it a hidden assumption?"

---

## Per-anchor lint rules

Per ARTIFACT-LINTER-RULES.md, the linter checks:

| Rule | Severity | Check |
|------|----------|-------|
| `EH-006` | Error | Every H claim with corpus reference has valid `§n` anchor |
| `EH-007` | Error | Every H Anchors field is non-empty |
| `WT-004` | Warning | Test procedure cites ≥1 §-anchor or [inference] |
| `WC-003` | Warning | Critique attack cites ≥1 §-anchor or [inference] |
| `EA-004` | Error | Scale-physics A has explicit calculation (not just `[axiomatic]`) |
| `WA-004` | Warning | Don't-Worry A has falsifier + grounded inference |
| `EX-003` | Error | Anomaly observation has source citation |

Plus the cross-reference resolution check:

| Rule | Severity | Check |
|------|----------|-------|
| `RE-001` | Error | All `§n` anchors resolve to existing transcript sections |
| `RE-002` | Error | All `EV-NNN` anchors resolve to existing evidence records |
| `RE-003` | Error | All `EV-NNN#E<n>` anchors resolve to existing excerpts |
| `RE-004` | Warning | `[external:]` source identifier present + non-empty |

The cross-reference resolution runs at Phase 7 audit (per `scripts/check-six-layer-validation.sh` Layer 4) and Phase 8 freeze.

---

## The fake-anchor disqualifier

Per EVALUATION-RUBRIC-14-CRITERIA.md Pass/Fail Gates:

> **Fake anchor detected** (`§n` that doesn't exist) — universal disqualifier

A pane that fabricates a `§99` reference when the transcript only has §1-§85 fails the entire scoring round. Why?

- The fake anchor *cannot be detected by the reader* without verification
- It poisons trust: if §99 is fake, what about §58, §103, §105?
- It reduces audit value to zero for that pane's contributions

Detection: when `scripts/validate-anchors.sh` exists, it checks every `§n` reference against the source corpus. Until then, auditors manually cross-check anchors and file failures as audit-finding beads with `severity: critical`.

Per OPERATOR-CALIBRATION-LOG.md D-Cal-7: persistent fake-anchor offenses → mandatory re-onboarding (per OPERATOR-ONBOARDING-CURRICULUM.md Week 1 Citation Discipline module).

---

## Inference vs verbatim discipline

Distinction:
- **Verbatim**: copy of the source's exact words; quoted; preserves wording
- **Paraphrase**: source's ideas in different words; meaning preserved
- **Inference**: claim derived from the source but not stated by the source

The discipline:

```
✓ "PAR proteins establish A-P polarity through cortical flows" (EV-001#E1 [verbatim])
✓ "Polarity is established by cortical flows of PAR proteins" (EV-001#E1 [paraphrase])
✓ "If PAR establishes polarity through flows, RNAi should disrupt asymmetric divisions" ([inference] from EV-001#E1)

✗ "PAR proteins establish polarity through gradient diffusion" (EV-001#E1 [verbatim])  ← verbatim is wrong; gradient diffusion not in source
✗ "PAR proteins are essential" ([inference])  ← needs source grounding
```

The marker tells the reviewer where to look:
- `[verbatim]` → can be quoted directly; mismatch = error
- `[paraphrase]` → words may differ; meaning must match
- `[inference]` → not in source; reasoning must be derivable

---

## Synthesis markers

When a claim emerges from combining multiple sources:

```
"The two axioms (generative grammar + reconstruction) jointly imply the operator algebra
[synthesis] of (§58 + §147) and {Opus, GPT, Gemini distillations}"
```

This is **not** the same as `[inference] across [§58, §147]`. The distinction:

- `[inference] across [§58, §147]` — agent's reasoning that depends on §58 and §147
- `[synthesis] of (§58 + §147)` — the claim emerges from the *interaction* between §58 and §147; neither alone suffices

The synthesis marker is rarer. Use it when reading the sources separately wouldn't generate the claim.

---

## External + axiomatic markers

### `[external:]` — when to use

Use for:
- External standards (NIST, RFC, ISO) cited in scale-physics A or framing
- Recent papers not yet imported to the evidence pack (T1-T2 sessions; T3+ should import)
- Web sources (GitHub, blog posts) for non-claim context (e.g., "the codebase pattern is documented here")

Don't use for:
- Brenner-corpus claims (use `§n`)
- Evidence-pack claims (use `EV-NNN`)
- Hidden assumptions disguised as external standards

### `[axiomatic]` — when to use

Use for:
- Foundational assumptions that the reader will accept without further justification
- Scale-physics axioms (e.g., "speed of light is finite") that are not in dispute

Don't use for:
- Convenient "we assume X" without justification
- Hidden assumptions you don't want to defend

Per Phase 7 audit: every `[axiomatic]` is challenged. If it survives challenge, fine. If not, downgrade to `[inference]` with grounding.

---

## Per-phase enforcement

| Phase | Citation discipline activity |
|-------|---------------------------------|
| 1 framing | RT cites Brenner anchors for the question's grounding |
| 3 hypothesis | Each H has Anchors field non-empty |
| 4 investigation | EV beads have full evidence pack records (per EVIDENCE-PACK-PROTOCOL.md) |
| 5 cross-exam | C bead Attack field cites specific anchors |
| 6 distillation | Distillations include `[synthesis]` markers explicitly |
| 7 audit | manual anchor-resolution check + `scripts/check-anchor-density.sh` |
| 8 freeze | Cross-reference resolution must be 100% |
| 9 handback | HANDBACK § Verdict cites top anchors per surviving H |

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| "Brenner emphasized..." without `§n` | Universal disqualifier |
| Use `[inference]` when there's a real source | Lazy; loses audit value |
| Use `[verbatim]` when paraphrasing | Verbatim mismatch = error |
| Use `§n` for evidence-pack claim | Wrong namespace; use `EV-NNN` |
| `[synthesis]` for single-source claim | Synthesis requires combining; use `[paraphrase]` or `[inference]` |
| `[external: source]` without specific source identifier | Validator rejects |
| `[axiomatic]` to avoid justifying load-bearing assumption | Downgrade to grounded inference |
| Mix anchors and inferences in same Anchors field | Be explicit: "EV-001#E1 [verbatim], [inference] from §58" |
| Drop anchors during refinement (refined H has no anchors) | Refined H must inherit + add anchors, not lose them |

---

## Validation tooling

```bash
# Validate all anchors resolve
# Planned: ./scripts/validate-anchors.sh artifacts/RS-...
# Current: manually grep `references/SOURCE-CORPUS.md` for every cited § anchor

# Check anchor density (claims-per-anchor ratio)
./scripts/check-anchor-density.sh artifacts/RS-...

# Sample output:
# RT: 1 anchor / 1 claim (1.0)
# H1: 3 anchors / 5 claims (0.6) — recommend ≥1.0
# H2: 5 anchors / 4 claims (1.25) — good
# H3: 0 anchors / 3 claims (0.0) — VIOLATION (EH-007)
```

For T3+: anchor density per H ≥ 0.8.
For T4+: ≥ 1.0 (every claim grounded).
For T1-T2: ≥ 0.5 (some looseness OK).

---

## Cross-references

- [EVIDENCE-PACK-PROTOCOL.md](EVIDENCE-PACK-PROTOCOL.md) — EV anchor system
- [ARTIFACT-LINTER-RULES.md](ARTIFACT-LINTER-RULES.md) — provenance lint rules
- [EVALUATION-RUBRIC-14-CRITERIA.md](EVALUATION-RUBRIC-14-CRITERIA.md) — fake-anchor disqualifier
- [QUOTE-BANK-METHODOLOGY.md](QUOTE-BANK-METHODOLOGY.md) — Track-A quote bank source for `§n` anchors
- [SOURCE-CORPUS.md](SOURCE-CORPUS.md) — `complete_brenner_transcript.md` as the §-namespace
- [VERIFICATION-FIRST.md](VERIFICATION-FIRST.md) — verified flag policy
- `scripts/validate-anchors.sh` — anchor resolution checker (Tier-7 future addition; until then, anchor validation is manual via `grep -n "^§" references/SOURCE-CORPUS.md` cross-checked against artifact)
- [scripts/check-anchor-density.sh](../scripts/check-anchor-density.sh) — density checker (already exists)
- /dp/brenner_bot/specs/artifact_linter_spec_v0.1.md § Citation & Provenance Rules — spec source
- /dp/brenner_bot/specs/role_prompts_v0.1.md § Output Contract — citation rules source
