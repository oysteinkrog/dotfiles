# EXCERPT-FORMAT-AND-CORPUS-WORKFLOW.md — Building Excerpts From the Brenner Corpus

<!-- TOC: Why structured excerpts | The corpus search CLI | Excerpt building strategies | Excerpt section anchoring | The kickoff excerpt pattern | Per-operator excerpt selection | Excerpt formatting rules | Anti-patterns | Cross-references -->

The Brenner corpus is 473KB / ~2900 lines / ~236 sections. A new session needs a *small slice* of this corpus to seed the conversation — too much overwhelms the panes; too little misses the relevant Brenner moves.

Brennerbot's excerpt workflow makes the slicing systematic: search by keyword, filter by section, deduplicate by §-anchor, format for kickoff.

This file specifies the corpus search CLI, the excerpt-building strategies, and the formatting rules.

Mined from `/dp/brenner_bot/specs/excerpt_format_v0.1.md` and `/dp/brenner_bot/README.md § Run a multi-agent session`.

---

## Why structured excerpts

Three failures of ad-hoc corpus inclusion:

1. **Too much corpus** — kickoff prompt becomes 50KB; panes lose focus on the question
2. **Too little corpus** — panes don't have the Brenner anchors they need to ground critiques
3. **Wrong slice** — operator picks excerpts that match operator's intuition, not the question's domain

Three benefits of structured excerpts:

1. **Search-driven selection** — keyword + section-anchor matching surfaces relevant content
2. **Operator-tagged filtering** — per operator (⊘ / ✂ / ⊞), surface tagged anchors
3. **Format-stable** — the excerpt block has a known structure that panes can parse

---

## The corpus search CLI

```bash
# Search transcript by keyword:
brenner corpus search "exclusion" --docs transcript --limit 5

# Search across all corpus types:
brenner corpus search "third alternative" --limit 10

# Filter by section:
brenner excerpt build --sections "§103,§105,§147" --ordering chronological > excerpt.md

# Build by quote-bank tag:
brenner excerpt build --tags "third-alternative,conversation" --limit 7 > excerpt.md
```

The CLI returns ranked results:

```
§103 (relevance: 0.95): "You've forgotten there's a third alternative... 'Both could be wrong'"
§147 (relevance: 0.92): "Exclusion is always a tremendously good thing in science."
§99 (relevance: 0.81): "Well, I'll do a quickie."
```

Operators chain `corpus search` → `excerpt build` → `prompt compose` to construct a kickoff.

---

## Excerpt building strategies

Three strategies, each appropriate for different question types:

### Strategy A: Operator-driven (when you know the moves)

If the question targets specific operators (e.g., "design a discriminative test"):

```bash
brenner excerpt build \
  --tags "exclusion-test,potency-check,scale-check" \
  --limit 7 \
  > excerpt.md
```

Returns the §-anchors tagged with those operators. Best for Phase 4 dispatch.

### Strategy B: Domain-driven (when you know the domain)

If the question is about a specific topic (e.g., "memory hierarchy"):

```bash
brenner corpus search "memory" --docs transcript --limit 10 \
  | brenner excerpt build --from-search > excerpt.md
```

Returns the most relevant sections by keyword match. Best for Phase 1 framing.

### Strategy C: Section-driven (when you know the anchors)

If you know specific sections (e.g., "§99 quickie + §103 third-alternative + §147 exclusion"):

```bash
brenner excerpt build --sections "§99,§103,§147" --ordering chronological > excerpt.md
```

Best for resuming sessions or when the operator has prior knowledge.

---

## Excerpt section anchoring

Every excerpt is anchored to its source section in the corpus. The format:

```markdown
> **§99**: "Well, I'll do a quickie." — *Pilot experiment to de-risk*

> **§103**: "You've forgotten there's a third alternative… 'Both could be wrong'" — *Third-alternative guard*

> **§147**: "Exclusion is always a tremendously good thing in science." — *Forbidden patterns ↔ kill experiments*
```

Each excerpt has:
- The **§-anchor** in bold
- The **verbatim quote** in quotes
- Optionally an **interpretation tag** in italics (the operator move it exemplifies)

Per CITATION-PROVENANCE-RULES.md: panes use the §-anchor in subsequent claims. The format makes the anchor *prominent* so panes don't miss it.

---

## The kickoff excerpt pattern

The full kickoff prompt structure (per MESSAGE-BODY-SCHEMA-PER-TYPE.md):

```markdown
# Brenner Loop Session: <topic>

## Research Question
<one-sentence; will become RT>

## Context
<2-4 sentences>

## Excerpt
<5-8 §-anchored excerpts; each ≤2 lines>

## Initial Hypotheses (optional)
...

## Constraints
...

## Requested Outputs
<deliverable list>
```

The Excerpt section is the corpus slice. 5-8 excerpts is the sweet spot:
- **<5**: panes don't have enough Brenner-anchor material to ground critiques
- **>8**: kickoff prompt becomes too long; signal-to-noise drops

The excerpts are chosen for **diversity** — different operators, different Brenner moves, not all the same theme. Per Strategy A (operator-driven): mix tags.

---

## Per-operator excerpt selection

For each operator (per OPERATORS.md), there's a curated set of canonical anchors:

| Operator | Canonical anchors |
|----------|---------------------|
| ⊘ Level-Split | §45-46, §50, §59, §105, §147, §205 |
| 𝓛 Recode | §34, §58, §147, §161, §175, §197, §205, §208 |
| ≡ Invariant-Extract | §62, §80, §95, §150 |
| ✂ Exclusion-Test | §99, §103, §147 |
| ⟂ Object-Transpose | §85, §107, §128 |
| ↑ Amplify | §60, §72, §88, §145 |
| ⊕ Cross-Domain | §40, §52, §78, §90 |
| ◊ Paradox-Hunt | §31, §44, §66, §82 |
| ⊞ Scale-Check | §49, §70, §92, §165 |
| ΔE Exception-Quarantine | §110, §122, §138, §152 |
| † Theory-Kill | §99, §103, §117, §128 |
| ⌂ Materialize | §38, §54, §99, §141 |
| 🔧 DIY | §55, §72, §99, §140 |
| 🤝 GAN | §35, §86, §125, §178 |
| ⊙ Productive-Ignorance | §10, §40, §60, §95 |
| ∿ Dephase | §75, §132, §155 |

Per `quote_bank_restored_primitives.md`: each anchor has metadata (operator tags, section context, interpretation). The excerpt builder pulls from this metadata.

---

## Excerpt formatting rules

| Rule | Description |
|------|-------------|
| §-anchor in bold first | Panes can parse |
| Quote in italics or block-quote | Visually distinct from interpretation |
| Verbatim or paraphrase, marked | Per CITATION-PROVENANCE-RULES.md |
| ≤2 lines per excerpt | Keep excerpt prompt compact |
| Interpretation tag optional | Operator may add `*<tag>*` italicized |
| Source citation if non-Brenner | E.g., `[external: NIST AI RMF 1.0]` |
| Order: chronological or thematic | Operator's choice |
| 5-8 excerpts ideal | Balance between context + signal |

The format is parseable: panes can extract `§n` references via regex `§\d+(?:\.\d+)?`.

---

## Cross-corpus search

Beyond the Brenner transcript, the corpus includes:

| Corpus | Description | Anchor format |
|--------|-------------|---------------|
| `transcript` | Brenner interview transcripts | `§n` |
| `quote-bank` | Curated primitives tagged by operator | `§n` (cross-references transcript) |
| `distillations` | Per-model distillations (Opus, GPT, Gemini) | `[opus:1.2.3]` or similar |
| `metaprompts` | Prompt templates | (no anchor; whole-document) |
| `raw-responses` | Raw model outputs feeding distillations | `[opus:batch-1#turn-3]` or similar |

The cross-corpus search:

```bash
brenner corpus search "exclusion" --docs all --limit 10
```

Returns hits across all corpora; operator filters by `--docs <type>` to narrow.

For new sessions: usually `--docs transcript` is right (Brenner's actual words). For meta-research (per archetype A3): include `--docs distillations` to surface model-specific framings.

---

## Performance characteristics

Per `/dp/brenner_bot/internal_notes_and_plans/search_approach_decision_v0.1.md`:

- Corpus size: 485KB total, ~236 sections
- Parse time: ~12ms (negligible)
- Search time: <50ms with module-level caching
- Memory footprint: 1-2MB once parsed

The search is **runtime-parsing with in-memory caching** — no precompiled index. First request parses; subsequent requests hit cache. This was a deliberate design decision (per the spec): simplicity > precompiled index for a 485KB corpus.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip excerpt; just include the question | Panes lose Brenner-anchor grounding; calibration drops |
| Include 20+ excerpts | Kickoff bloat; panes lose focus |
| Use only one operator's anchors | Diversity matters; mix operators per Strategy A |
| Hand-pick excerpts that match operator's prior | Per ⊙ Productive-Ignorance: bias toward known-good is a confound |
| Cite §-anchor not in transcript (fake anchor) | Per CITATION-PROVENANCE-RULES.md: universal disqualifier |
| Skip section anchoring | Format-loss; panes can't trace |
| Include external sources without `[external:]` marker | Per CITATION-PROVENANCE-RULES.md |
| Excerpt verbatim without `[verbatim]` marker | Per CITATION-PROVENANCE-RULES.md |
| Use a stale corpus (old commit) | Anchor numbers may have shifted; per AGENTS.md preserve canonical |

---

## Composition with brennerbot

Excerpt workflow integrates with:

- **Phase 1 framing** (per FRAMING-WORKBOOK.md): excerpt selection part of F1-F9
- **Kickoff prompt** (per MESSAGE-BODY-SCHEMA-PER-TYPE.md): excerpt section in body
- **Quote-bank methodology** (per QUOTE-BANK-METHODOLOGY.md): per-operator anchor library
- **Citation provenance** (per CITATION-PROVENANCE-RULES.md): anchor format
- **Operator-aware quote matching** (per HYPOTHESIS-SIMILARITY-AND-CROSS-SESSION-SEARCH.md): semantic search beyond keyword

---

## Cross-references

- [QUOTE-BANK-METHODOLOGY.md](QUOTE-BANK-METHODOLOGY.md) — Track-A corpus → quote bank
- [SOURCE-CORPUS.md](SOURCE-CORPUS.md) — `complete_brenner_transcript.md` overview
- [CITATION-PROVENANCE-RULES.md](CITATION-PROVENANCE-RULES.md) — anchor format
- [MESSAGE-BODY-SCHEMA-PER-TYPE.md](MESSAGE-BODY-SCHEMA-PER-TYPE.md) — KICKOFF body
- [FRAMING-WORKBOOK.md](FRAMING-WORKBOOK.md) — Phase 1 framing
- [HYPOTHESIS-SIMILARITY-AND-CROSS-SESSION-SEARCH.md](HYPOTHESIS-SIMILARITY-AND-CROSS-SESSION-SEARCH.md) — semantic search
- /dp/brenner_bot/specs/excerpt_format_v0.1.md — excerpt format spec
- /dp/brenner_bot/internal_notes_and_plans/search_approach_decision_v0.1.md — search architecture
- /dp/brenner_bot/quote_bank_restored_primitives.md — operator-tagged quotes
