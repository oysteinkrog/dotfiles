# Operator Library

Applied from the [`operationalizing-expertise`](../../operationalizing-expertise/SKILL.md) Track A methodology: each *cognitive move* a documentation writer makes is an operator — a reusable, composable verb with explicit triggers, failure modes, and a copy-paste prompt module.

Agents invoke operators by tag. Every Polish-Bar failure maps to exactly one operator.

---

## How to use this file

1. When drafting or polishing a page, walk it against the Polish Bar (see [SKILL.md](../SKILL.md#the-polish-bar-non-negotiable)).
2. For each failing dimension, find the operator whose tag matches.
3. Paste the operator's *prompt module* into your working context (or inline into a subagent invocation).
4. Do what it says. Exit criteria are in the module.

The library is intentionally small. If you add operators, they must pass the operator-card validator (required fields from [operationalizing-expertise/references/FORMATS.md](../../operationalizing-expertise/references/FORMATS.md)).

---

## Meta-operator: ★ ORIENT

**Definition**: Reshape the first 3 paragraphs of a page so a cold reader lands, understands what they're reading, and knows whether to keep going — without needing the page's title or breadcrumbs.

**When-to-Use Triggers**:
- Page's first paragraph under 40 words (Polish Bar P1 fail)
- Page opens with a signature / table / code block (no prose)
- Page opens with "This document describes..." (AI-tell; zero orientation signal)
- Reader would need context from a sibling page to understand why this page exists
- You're writing an *overview* or *index.mdx*

**Failure Modes**:
- Over-orientation: a 600-word preamble before any concrete content → reader bounces
- Marketing voice: "Welcome! We're excited..." → inauthentic; [de-slopify](../../de-slopify/SKILL.md) fixes
- Redundant with page title: title says "Configuration"; intro says "This page covers configuration" → cut

**Prompt Module**:
```
[OPERATOR: ★ ORIENT]
1) Read the page. Identify the one user question this page answers.
2) Write a new first paragraph (40-80 words) that:
   - Names the thing in the first sentence.
   - States the audience (end-user / contributor / integrator).
   - Locates it in the project (one sentence: "it's the part that…").
3) If relevant: add a sentence previewing what the reader will walk away with.
4) Delete any existing "This page covers…" / "Welcome" / "In this guide…" opener.

Output: rewritten first paragraph. Leave the rest of the page alone.
Required: result ends with a period; doesn't mention "this page".
```

**Canonical tag**: `orient`

**Quote-bank anchors**: §EX-1 (Stripe's one-line positioning), §EX-7 (Astro's prerequisite frame)

---

## ✦ MOTIVATE

**Definition**: Give the reader the "why this exists" before any "how to use it" instruction.

**When-to-Use Triggers**:
- Polish Bar P2 fails (no `why|because|motivated|exists to|solves` in opening 1200 chars)
- Page is a method/API dump with no prose explaining why the thing was built
- A reviewer asked "why not just use X?" — that question belongs on the page

**Failure Modes**:
- Straw-manning alternatives ("X was too slow") without evidence → reader skeptical
- Marketing motivation ("Built for developers who care about quality") → empty
- Motivation longer than the how-to → ratio is off

**Prompt Module**:
```
[OPERATOR: ✦ MOTIVATE]
1) In 2-4 sentences, answer: what problem did this section/module solve, that
   the obvious alternative didn't?
2) Cite the alternative by name if one exists (another library, a different
   design, a manual process). No straw men — if the alternative is fine for
   some cases, say so.
3) Place this paragraph between the ORIENT paragraph and the first how-to
   heading. Add a `## Why it exists` heading if the page is long enough to
   warrant it.
4) Remove any motivation paragraphs later in the page that now duplicate this.

Output: one motivation paragraph (2-4 sentences), placed correctly.
Required: at least one of [why, because, solves, exists to] appears in the first
sentence of the paragraph.
```

**Canonical tag**: `motivate`

**Quote-bank anchors**: §EX-9 (tRPC's "keeping API contracts in sync is painful")

---

## ◐ MENTAL-MODEL

**Definition**: Give the reader a diagram or analogy so they have a visual / conceptual hook to hang details on.

**When-to-Use Triggers**:
- Polish Bar P3 fails (no mermaid / FileTree / Cards / image / ASCII box drawing)
- The page talks about relationships between 3+ objects
- You catch yourself writing "see the diagram" but no diagram exists

**Failure Modes**:
- Decorative diagram: mermaid with generic A→B→C that matches the prose literally → no new information → cut it
- Over-detailed diagram: 30 boxes with every internal function → overwhelming; reader can't read it
- Diagram contradicts prose: diagram shows "Worker pulls from queue" but code shows "push" → embarrassing

**Prompt Module**:
```
[OPERATOR: ◐ MENTAL-MODEL]
Pick ONE:

(a) MERMAID DIAGRAM. Best for request flow, component hierarchy, state machine.
    Use `graph LR` / `graph TD` / `sequenceDiagram` / `stateDiagram-v2`. Keep
    ≤10 nodes. Labels are nouns (not adjectives). Verify the diagram matches
    the actual code paths in the source repo.

(b) FILETREE COMPONENT. Best for describing directory organization.
    Use <FileTree> with defaultOpen on the relevant folder. Mark the file
    under discussion with `active`.

(c) ANALOGY IN PROSE. Best for state, protocol, or conceptual model.
    "Think of X as a Y that Z." Three sentences max; the analogy must
    illuminate the real structure, not obscure it.

(d) NUMBERED LIST OF CONCEPTS. Acceptable fallback when a visual would
    overcomplicate. Maximum 5 concepts; each must be a noun with a one-line
    role description.

Do NOT use a generic diagram that just mirrors the prose structure. If the
diagram would add no information, skip it and use option (c) or (d).

Output: the chosen mental model, placed right after the MOTIVATE paragraph.
Required: if mermaid, syntax is valid (parse locally); if FileTree, paths
match the source repo.
```

**Canonical tag**: `mental-model`

**Quote-bank anchors**: §EX-2 (Next.js file-tree diagrams + folder code blocks)

---

## ⬡ EXEMPLIFY

**Definition**: Include at least one concrete, copy-pasteable, actually-runnable example with realistic inputs and expected output.

**When-to-Use Triggers**:
- Polish Bar P4 fails (no fenced code block with a language tag)
- The page describes a function / command / config without showing its use
- The example on the page uses `foo`, `bar`, `baz`, or `lorem ipsum` — replace with realistic inputs

**Failure Modes**:
- Too-cute example: reverses a string in a function called `quokka` → distracts from the concept
- Half-example: `foo.configure({...})` → what goes in the object? Always fill the blanks.
- Stale example: code doesn't match the current API because the source was renamed → cite file:line to pin it, and verify

**Prompt Module**:
```
[OPERATOR: ⬡ EXEMPLIFY]
1) Write a concrete scenario: "Here's a realistic case — [describe it]."
2) Add a fenced code block with the correct language tag.
3) Use realistic inputs (real-looking filenames, plausible strings, sensible
   numeric constants — not 'foo'/'bar').
4) Show either:
   (a) the expected output as a comment in the code block, or
   (b) a second code block / sentence describing what the user sees.
5) Verify against {SOURCE_PATH}: every identifier used in the example exists
   in the codebase. No invented APIs.

Output: scenario sentence + code block + result. ≤30 lines total.
Required: language tag is present; no `foo`/`bar`/`lorem`; identifiers
verified.
```

**Canonical tag**: `exemplify`

**Quote-bank anchors**: §EX-1 (Stripe's complete runnable curl requests with `<<PLACEHOLDER>>` markers), §EX-3 (Tailwind's example-in-context blocks)

---

## ⚠ WARN

**Definition**: Make common failure modes visible so readers don't trip over them.

**When-to-Use Triggers**:
- Polish Bar P5 fails on a non-overview page
- You know of at least one gotcha — every module has one; if you can't find it, you haven't looked hard enough
- Grepping the source surfaced a cluster of "don't do X" / "// NOTE:" / `panic!` comments

**Failure Modes**:
- Over-warning: every page has 3 warnings → readers tune them all out
- Hypothetical warning: "Make sure you don't forget to…" → should be enforced in code, not docs
- Warning without fix: "Watch out for X" with no "do Y instead"

**Prompt Module**:
```
[OPERATOR: ⚠ WARN]
Pick ONE of these surfaces. Never more than one per page unless the page is
a dedicated "gotchas" page.

(a) <Callout type="warning">one-sentence gotcha</Callout>
    Use for things that WILL go wrong if the reader doesn't know.

(b) <Callout type="important">one-sentence rule</Callout>
    Use for hard requirements (e.g., "runs ONLY under a specific mode").

(c) A `## Pitfalls` or `## Common mistakes` section with 2-4 bullets, each
    structured as: "Mistake: <X>. Fix: <Y>."

(d) GitHub alert syntax `> [!WARNING]` or `> [!CAUTION]` (renders like (a)).

Every warning must have a REMEDIATION, not just a description. If you don't
know the fix, don't write the warning.

Output: one warning surface, correctly placed (usually after Pitfalls-worthy
content, not at the top of the page).
Required: text contains a fix, not just a symptom.
```

**Canonical tag**: `warn`

**Quote-bank anchors**: §EX-1 (Stripe's `> **Tip:**` / `> **Complexity:**` blockquote markers)

---

## ✧ TIP

**Definition**: Surface a non-obvious insight that separates casual users from experienced ones.

**When-to-Use Triggers**:
- You know something from reading the source code that the docstring doesn't say
- There's a trick that saves 10x time / memory / typing once you know it
- The same question shows up in issue comments or commit messages repeatedly

**Failure Modes**:
- Obvious tip: "Use the `--help` flag" → remove; everyone knows
- Performance voodoo without measurements: "This is faster" → prove it or cut it
- Unscoped tip: "In general you should…" → tips should be situational

**Prompt Module**:
```
[OPERATOR: ✧ TIP]
1) Identify the non-obvious insight. Verify it by reading the source and/or
   testing.
2) Surface with `<Callout type="info">` or a `## Tip` subheading.
3) Structure:
   - ONE sentence stating the tip.
   - ONE sentence stating WHEN it applies (scope!).
   - Optional: a code snippet showing the usage.
4) Prefer `<Callout type="info">` over `<Callout type="default">`; reserve
   `emoji` prop for "default" type when you want a custom marker.

Output: one tip surface, sized to the insight (1-4 sentences).
Required: the tip names a specific scenario where it applies; it isn't
generic advice.
```

**Canonical tag**: `tip`

---

## ⇄ CROSS-LINK

**Definition**: Ensure no page is a dead end. Every page has ≥2 navigable links to related content.

**When-to-Use Triggers**:
- Polish Bar P6 fails (<2 in-repo links)
- The page introduces a term that's defined elsewhere (link to the glossary entry)
- The page's natural next step is another page in the docs (link it)

**Failure Modes**:
- Link farm: a "Related" section at the bottom with 20 links → useless; curate
- Wrong link direction: always linking deeper but never back up → reader gets lost
- Broken relative paths: `./foo` when the current page is at a depth where `./foo` doesn't resolve → run the link checker

**Prompt Module**:
```
[OPERATOR: ⇄ CROSS-LINK]
Ensure every page has AT LEAST:

1) Inline links for every domain term on first use (to the glossary).
2) One "prerequisite" link (if relevant): "If you're new to X, start with
   [X](...) first."
3) One "next step" link or `<Cards>` grid near the bottom: "See also /
   What's next."

Link style:
- Use relative paths (`./foo`, `../section/foo`).
- Use Markdown links (`[text](path)`), not `<a href>` (unless external with
  `target="_blank"`).
- Link text is a noun phrase or action, never "click here" / "this".

Verify: run `./scripts/link-check.mjs content/{SECTION}/` — no broken links.

Output: 2+ in-repo links added to the page in their natural homes.
Required: link checker reports all targets resolve.
```

**Canonical tag**: `cross-link`

**Quote-bank anchors**: §EX-7 (Astro's community bridge-links), §EX-10 (Svelte Kit's prev/next pagination)

---

## ⤵ DECOMPOSE

**Definition**: Split a long, multi-audience page into focused sub-pages when one page is trying to do too many jobs.

**When-to-Use Triggers**:
- Page >3000 words (content-lint may not flag this but reader experience does)
- Page mixes tutorial + reference + conceptual (Diátaxis violation — see [DIATAXIS.md](DIATAXIS.md))
- You find yourself writing "In this section, for beginners, do X; for advanced users, do Y" repeatedly

**Failure Modes**:
- Over-decomposing: 20 two-paragraph pages → sidebar bloat, hard to skim
- Decomposing without index: now readers need to find the pieces → add a `<Cards>` grid to the parent
- Decomposing mid-topic: splits a single concept across pages and forces scroll-chase

**Prompt Module**:
```
[OPERATOR: ⤵ DECOMPOSE]
1) Classify every section of the too-long page by Diátaxis quadrant (Tutorial /
   How-to / Reference / Explanation). See DIATAXIS.md.
2) If the page spans ≥2 quadrants, split:
   - Move tutorial-shaped content to `/guides/<topic>.mdx`.
   - Move reference tables to `/reference/<topic>.mdx`.
   - Keep explanation on the main page.
3) Move, don't retype. `git mv` preserves history; if it's a new file, just cut.
4) Add a <Cards> or sidebar block on the parent page linking to the new
   pieces.
5) Update every inbound link to point at the new canonical location.

Output: one split into 2-N focused pages, all cross-linked, no content lost.
Required: content-lint passes on each new page; link checker green.
```

**Canonical tag**: `decompose`

**Quote-bank anchors**: §EX-6 (TanStack Query's Guides vs API Reference separation)

---

## ⊕ SYNTHESIZE

**Definition**: Produce cross-cutting content that can only be written after all sections are drafted — architecture, data-flow, contributing, glossary.

**When-to-Use Triggers**:
- Phase 3 (exclusively)
- After Phase 4 polish, a reviewer notes "the overall story is missing"

**Failure Modes**:
- Duplicating section content: the architecture page re-states what each section says → add nothing; cut
- Top-down-only: architecture that never traces a real request through the system → useless; include data-flow
- Assuming knowledge: overview page that uses project-specific jargon without glossary → unreadable

**Prompt Module**:
```
[OPERATOR: ⊕ SYNTHESIZE]
See the full Phase 3 prompt in AGENT-PROMPTS.md#phase-3.

Required outputs: index.mdx, overview/what-is-this.mdx, overview/architecture.mdx,
overview/data-flow.mdx, overview/contributing.mdx, overview/glossary.mdx.

Each output is a distinct operator composition:
- what-is-this = ORIENT + MOTIVATE + ⇄ CROSS-LINK
- architecture = ★ ORIENT + ◐ MENTAL-MODEL + component walkthrough + ⇄ CROSS-LINK
- data-flow    = ★ ORIENT + ⬡ EXEMPLIFY (request trace) + ⇄ CROSS-LINK
- contributing = ★ ORIENT + ⬡ EXEMPLIFY (dev-env setup) + ⚠ WARN (common gotchas)
- glossary     = alphabetical operator (maintain one term per line with a
                 canonical link; Phase 5 expands this)

Output: all six files under content/ with consistent voice. Update
app/_meta.global.tsx to place Overview first.
Required: every domain term introduced in section drafts appears in the glossary.
```

**Canonical tag**: `synthesize`

---

## ⊙ DE-SLOP

**Definition**: Remove AI-generated writing tells (emdash abuse, "It's not X, it's Y", "Here's why", forced enthusiasm) and recast sentences to sound authentically human.

**When-to-Use Triggers**:
- Every Phase 4 pass (apply before the rubric check)
- A human reviewer flags "reads like AI"
- An automated scan (`scripts/audit-content.mjs`) flags high emdash / cliche density

**Failure Modes**:
- Over-correcting: replacing every emdash with a semicolon → prose becomes Victorian
- Losing technical precision: rewriting "precisely 2^32 entries" as "lots of entries" → lost meaning
- Regex-only approach: script replaces but never recasts → stilted output

**Prompt Module**:
```
[OPERATOR: ⊙ DE-SLOP]
Full prompt inline from the de-slopify skill (applies even if the skill isn't
installed):

"Read through the text carefully and look for telltale signs of 'AI slop' style
writing; one big tell is the use of emdash. Replace with a semicolon, a comma,
or recast the sentence so it sounds good while avoiding emdash.

Also avoid certain writing tropes: 'It's not [just] X, it's Y', 'Here's why',
'Here's why it matters:', 'Let's dive in', 'At its core', 'It's worth noting'.
Anything that sounds like what an LLM would write disproportionately more than
a human. Can't be done with regex; MUST manually read each line and revise it
manually in a systematic, methodical, diligent way. Use ultrathink."

Do this pass AFTER other operators — there's no point de-slopping a page that
will be rewritten.

Output: the same page, cleaner prose. No content cuts; just recasting.
Required: no emdash (unless single, genuinely parenthetical); no listed AI
tells; prose scans naturally aloud.
```

**Canonical tag**: `de-slop`

---

## ⊞ NEXTRA-UPLIFT

**Definition**: Upgrade plain MDX to use Nextra components where appropriate, without overdoing it.

**When-to-Use Triggers**:
- Phase 6b exclusively
- The page has obvious opportunities: sequential headings that should be `<Steps>`, directory code fences that should be `<FileTree>`, install commands that should be `npm2yarn`

**Failure Modes**:
- Component-itis: Callouts + Cards + Tabs + Steps on one page → reader loses the thread
- Wrong component: wrapping a two-item list in `<Cards>` → use `<Cards num={1}>`? just use markdown list
- Breaking MDX syntax with nested fences: three-backtick inside three-backtick (see [NEXTRA.md](NEXTRA.md#code-block-features))

**Prompt Module**:
```
[OPERATOR: ⊞ NEXTRA-UPLIFT]
Walk the page. For each opportunity, decide YES / NO:

- ### Step 1 / ### Step 2 → <Steps> YES if ≥3 steps, NO if 1-2
- Language choice → <Tabs> YES if 2+ real alternatives, NO if one-primary
- Directory listing → <FileTree> YES if showing organization, NO if showing
  one path in prose
- Section-index page → <Cards> YES if home/overview, NO elsewhere
- ```sh install command → npm2yarn YES for package installs, NO for arbitrary
  shell
- Ambient inline warning → <Callout type=...> YES, but ONE per page max
- Architecture paragraph with 3+ boxes → ```mermaid YES

After uplift, run `bun run build`. If it breaks, fix immediately before moving
on (most common: nested triple-backticks — switch outer to four).

Output: upgraded MDX; logged in phase6_nextraify_log.md as [substantive] or
[trivial].
Required: build green; one Callout per page max; Cards only on
landing/overview pages.
```

**Canonical tag**: `nextra-uplift`

---

## ⌘ REDUCE

**Definition**: Cut words, code comments, redundant explanations, and hedges. Every remaining sentence must earn its place.

**When-to-Use Triggers**:
- Content-lint or audit says "code-to-prose ratio skewed to prose"
- Page is >1200 words and can be said in half that
- You just finished a polish pass and the page has grown — reduce before shipping

**Failure Modes**:
- Over-reducing: losing necessary context → now readers are lost
- Reducing precision: collapsing a 3-parameter description to "it takes some options" → lost reference value
- Reducing too eagerly: cutting examples to save words → cuts the most valuable content

**Prompt Module**:
```
[OPERATOR: ⌘ REDUCE]
Sentence-by-sentence, ask: "Does this sentence carry information the previous
sentences don't?" If no, cut.

Specific targets:
- Hedges: "perhaps", "it's worth noting", "you might want to" — usually
  droppable.
- Meta: "In this section" / "As mentioned above" / "Next, we'll…" — the
  headings already say this.
- Compound words: "functionality" → "function"; "utilize" → "use"; "additional" →
  "more".
- Double-verbs: "we can go ahead and create" → "create".
- Restatement: if the code says it, prose doesn't have to.

What NOT to cut:
- Motivation (keep the WHY).
- Concrete examples.
- Warnings with fixes.
- Diagrams / tables.

Output: the page, shorter. Record before/after word counts in the polish log.
Required: no loss of meaning; code examples intact.
```

**Canonical tag**: `reduce`

---

## Operator composition cheat-sheet

| Page type | Operator pipeline |
|-----------|-------------------|
| Section overview (`<section>/overview.mdx`) | ORIENT → MOTIVATE → MENTAL-MODEL → EXEMPLIFY → CROSS-LINK |
| Module deep-dive | ORIENT → MOTIVATE → (public API table) → EXEMPLIFY → WARN → TIP → CROSS-LINK |
| CLI command page | ORIENT → (synopsis) → EXEMPLIFY → (flags table) → WARN → CROSS-LINK |
| Tutorial / how-to | ORIENT → (prerequisites callout) → Steps (⊞ NEXTRA-UPLIFT) → EXEMPLIFY → verify → WARN |
| Reference index | ORIENT → (alphabetical list with one-liners) → CROSS-LINK to deep pages |
| Architecture | ORIENT → MOTIVATE → MENTAL-MODEL (mermaid) → (component walkthrough) → CROSS-LINK |
| FAQ | ORIENT → (Q/A pairs) → CROSS-LINK on each answer |
| Changelog | (header + version blocks) → each version: highlights → Added/Changed/Fixed/Deprecated → Migration |

When in doubt: ORIENT → MOTIVATE → MENTAL-MODEL → EXEMPLIFY → WARN → CROSS-LINK is the "safe" pipeline for any mid-length page.

---

## Validation

`scripts/audit-content.mjs` scores each page against operator coverage:

```
$ node scripts/audit-content.mjs content/
OK — cli/commands/run.mdx: orient ✓ motivate ✓ mental-model ✓ exemplify ✓ warn ✓ tip ○ cross-link ✓ (6/7)
FAIL — core/indexing.mdx: orient ✓ motivate ✗ mental-model ✗ exemplify ✓ warn ✗ cross-link ✓ (3/7)
...
```

- ✓ = operator applied
- ○ = operator not applied but optional for this page type
- ✗ = operator applied poorly or not applied when required → rework

Phase 4 termination: ≥95% of pages have ✓ on every required operator for their type.
