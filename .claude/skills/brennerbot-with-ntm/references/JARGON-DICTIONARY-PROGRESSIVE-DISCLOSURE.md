# JARGON-DICTIONARY-PROGRESSIVE-DISCLOSURE.md — 100+ Term Glossary with Multi-Level Explanation

<!-- TOC: Why a jargon dictionary | The 6 categories | Progressive disclosure: 4 levels per term | Per-term schema | Tooltips, glossary, hover patterns | Per-pane jargon-aware prompting | Anti-patterns | Cross-references -->

The brennerbot vocabulary is dense — 15 operators, ~25 Brenner-specific terms, dozens of taxonomy enums, statistical and methodological jargon. New operators (and external readers) face a wall of terminology.

The Jargon Dictionary solves this with **progressive disclosure**: every term has a tooltip, a full explanation, an analogy for non-experts, and a "why it matters" framing. Operators see the right level for the situation.

Mined from `/dp/brenner_bot/README.md § Jargon Dictionary`.

---

## Why a jargon dictionary

Three failures of unstructured glossaries:

1. **Single-level definitions** — "Level-Split: separating program from interpreter" is fine for experts but opaque for newcomers
2. **Term overload** — 100+ terms in flat list = no navigation
3. **No "why it matters"** — definitions teach what; not when to invoke

Three benefits of progressive disclosure:

1. **Tooltip-on-hover** — see term, hover, get short definition (≤100 chars)
2. **Click-for-more** — full explanation when needed (2-4 sentences)
3. **Analogy for non-experts** — "think of it like..." bridges domain knowledge gap

---

## The 6 categories

Terms are organized by category for scalable navigation:

| Category | Content |
|----------|---------|
| `operators` | Brenner operators (⊘ Level-Split, 𝓛 Recode, ✂ Exclusion-Test, etc.) |
| `brenner` | Core Brenner concepts (third alternative, forbidden pattern, etc.) |
| `biology` | Scientific/biology terms (C. elegans, morphogen, etc.) |
| `bayesian` | Statistical/probabilistic terms (likelihood ratio, prior, etc.) |
| `method` | Scientific method terms (hypothesis, falsification, etc.) |
| `project` | Brennerbot-specific terms (delta, artifact, session, etc.) |

Browsing by category is more efficient than flat search for newcomers. Per-category counts (approximate):
- operators: 15 (the algebra)
- brenner: 25 (vocabulary glossary)
- biology: 30 (domain-specific)
- bayesian: 15 (probabilistic frame)
- method: 20 (scientific method)
- project: 25 (brennerbot-specific)

Total: ~130 terms.

---

## Progressive disclosure: 4 levels per term

Each term has 4 progressively-deeper levels:

```
Level 1: short (≤100 chars; tooltip)
Level 2: long (2-4 sentences; click-for-more)
Level 3: analogy (optional; "think of it like..." for non-experts)
Level 4: why (optional; "why this matters in the Brenner context")
```

Plus relations:

```
related: [<term-key>, ...]   # related terms for discovery
```

### Example progression: "Level-split"

**Level 1 (short, tooltip):**
> Separating distinct causal levels (program vs interpreter; message vs machine).

**Level 2 (long):**
> A core Brenner operator that distinguishes conceptually-blended categories so they can be reasoned about cleanly. Apply when arguments confuse different layers of explanation: e.g., "the gene tells the cell to..." conflates information with mechanism. Operator symbol: ⊘.

**Level 3 (analogy):**
> Like distinguishing the *recipe* from the *cooking*: the same recipe (program) can be cooked (interpreted) by different cooks (interpreters) with different results — and the recipe itself doesn't determine the meal.

**Level 4 (why):**
> Without level-splitting, hypotheses get stuck arguing inside a blended category — neither side can name what would distinguish them. Brenner's third axiom (machine-language constraint) is the discipline: "Proper simulation must be done in the machine language of the object." Per §147.

---

## Per-term schema

```typescript
interface JargonTerm {
  term: string;       // Display name (e.g., "Level-split")
  short: string;      // ~100 char tooltip definition
  long: string;       // 2-4 sentence explanation
  analogy?: string;   // Optional: "think of it like..." for non-experts
  why?: string;       // Optional: "why this matters in Brenner context"
  related?: string[]; // Optional: related term keys
  category: JargonCategory;
}
```

The `term` field is human-readable; the lookup uses lowercase-hyphenated key (`level-split`).

---

## Tooltips, glossary, hover patterns

The web app uses the dictionary in three modes:

### Mode 1: Hover tooltips

Anywhere a term appears in prose:

```
"Apply ⊘ <span class="jargon" data-term="level-split">Level-Split</span> to distinguish..."
```

On hover: tooltip shows `short` definition + "Click for more".

### Mode 2: Glossary page

`/glossary` shows all terms grouped by category with collapsible cards:

```
[ ▶ Operators (15) ]
  ⊘ Level-Split        Separating distinct causal levels...
  𝓛 Recode             Change representation / coordinates...
  ...

[ ▶ Brenner Concepts (25) ]
  Third alternative    The "both could be wrong" option...
  Forbidden pattern    Observation that cannot occur if H is true...
  ...
```

Click a card → full term card with `long` + `analogy` + `why` + `related`.

### Mode 3: Progressive click-through

User starts with `short`, clicks for `long`, clicks for `analogy + why`. Each click reveals more depth without overwhelming.

In a CLI environment (no web), the equivalent: `brenner jargon term <term-key>` outputs the full term.

```bash
$ brenner jargon term level-split
Term: Level-split
Category: operators
Short: Separating distinct causal levels...
Long: A core Brenner operator that distinguishes...
Analogy: Like distinguishing the recipe from the cooking...
Why: Without level-splitting, hypotheses get stuck...
Related: program-vs-interpreter, machine-language, chastity-vs-impotence
```

---

## Per-pane jargon-aware prompting

The dictionary integrates with role prompts (per role_prompts_v0.1.md):

When a pane is dispatched on a Phase 4 investigation, the dispatcher injects relevant jargon definitions:

```
You are dispatching MO-04a-investigate on H-002 ("PAR-mediated polarity").

JARGON CONTEXT (relevant to this dispatch):
- ⊘ Level-Split: <short>
- ⊞ Scale-Check: <short>
- Don't Worry hypothesis: <short>
- Forbidden pattern: <short>

Use these terms in your evidence pack and any critiques you generate.
```

Per Phase 7 audit: panes that consistently use vocabulary correctly score higher on EVALUATION-RUBRIC-14-CRITERIA.md "Citation Compliance" (criterion 2).

---

## Cross-session vocabulary tracking

Per BRENNERBOT-AT-SCALE.md: track vocabulary usage across sessions:

- Per-operator: which terms get used (and missed)?
- Per-pane: does a model family consistently miss certain terms?
- Per-archetype: which terms cluster around specific question types?

Sessions in archetype A4 (incident) cluster around `forbidden pattern` and `digital handle`. Sessions in A1 (design-space) cluster around `level-split` and `cross-domain import`. The clustering informs ARCHETYPE-START-PACKS.md per-archetype jargon emphasis.

---

## Brenner-specific jargon highlights

A few terms that catch newcomers:

### "Chastity vs impotence"

> Same outcome (no offspring), fundamentally different reasons. A diagnostic for *causal typing*.

Why it matters: when two hypotheses predict the same observable, design the discriminator that separates them by mechanism, not by outcome. Per Brenner §50.

### "Don't Worry hypothesis"

> Assume required mechanisms exist; proceed with theory development.

Why it matters: per BRENNER-VOCABULARY.md, this is the *deferral* mechanism — pair every Don't-Worry with an `assumption_ledger` entry, never use it to handwave permanently.

### "Productive ignorance"

> Fresh eyes unconstrained by expert priors.

Why it matters: experts have *overly tight* probability mass on known solutions; novices spread mass thinner. Per ⊙ operator.

### "Seven-cycle log paper"

> Test for qualitative, visible differences.

Why it matters: prefer effect sizes that don't need statistics. If your effect requires N=10000 and t-tests, you may be measuring something that won't generalize. Per Brenner.

---

## How to extend the dictionary

When new terms emerge across sessions:

1. **Track usage** in OPERATOR-CALIBRATION-LOG.md
2. **Promote to dictionary** when ≥3 sessions use the term consistently
3. **Author the 4 levels** (short / long / analogy / why)
4. **Add `related` links** to existing terms
5. **Bump dictionary version** in METHODOLOGY-EVOLUTION-LOG.md

Don't add casual one-off terms; the dictionary curates *enduring* vocabulary.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip the dictionary; use undefined jargon in prompts | Newcomers stuck; calibration scoring drops |
| Definition longer than 100 chars in `short` field | Tooltip becomes wall of text |
| `long` reads like a single-line definition | Should be 2-4 sentences with mechanism + when-to-use |
| Skip `analogy` for technical terms | Non-experts struggle; analogy bridges |
| Skip `why` for operators | Operators need to know *when to invoke*, not just what |
| Add domain-specific jargon as `category: project` | Use `biology` / `bayesian` / `method` per content |
| `related: [...]` lists 20 terms | Keep tight (≤5 most-relevant); too many is noise |
| Inconsistent capitalization across `term` fields | Display key consistency matters |

---

## Composition with brennerbot

The dictionary integrates with:

- **Role prompts** (per role_prompts_v0.1.md): inject jargon definitions in dispatches
- **Web app** (per /glossary route): browseable glossary
- **MOs** (per MARCHING-ORDERS.md): MOs reference jargon by key, not by definition
- **HANDBACK** (per HANDBACK-VOICE-GUIDE.md): use canonical terms; don't redefine
- **Phase 7 audit** (per EVALUATION-RUBRIC-14-CRITERIA.md): "Citation Compliance" includes vocabulary correctness
- **Onboarding** (per OPERATOR-ONBOARDING-CURRICULUM.md): Week 1 reading includes glossary tour

---

## Cross-references

- [BRENNER-VOCABULARY.md](BRENNER-VOCABULARY.md) — the Brenner-specific subset
- [OPERATORS.md](OPERATORS.md) — operator algebra; each is a glossary entry
- [TAXONOMIES-COMPLETE-CATALOG.md](TAXONOMIES-COMPLETE-CATALOG.md) — taxonomy enums (linked from glossary)
- [BAYESIAN-FRAMEWORK.md](BAYESIAN-FRAMEWORK.md) — Bayesian terms (likelihood ratio, prior, etc.)
- [OPERATOR-ONBOARDING-CURRICULUM.md](OPERATOR-ONBOARDING-CURRICULUM.md) — Week 1 glossary tour
- [HANDBACK-VOICE-GUIDE.md](HANDBACK-VOICE-GUIDE.md) — using canonical terms
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — dictionary version bumps
- /dp/brenner_bot/README.md § Jargon Dictionary — original source
