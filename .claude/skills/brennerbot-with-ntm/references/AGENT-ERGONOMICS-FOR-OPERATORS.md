# AGENT-ERGONOMICS-FOR-OPERATORS.md — Skill Optimized for Agent Operators

<!-- TOC: Why agent-ergonomic | The agent reads first 50 lines | Trigger optimization | Layered context loading | Decision-tree-first | Failure-table-first | Card-format references | Composition over inheritance | Self-test triggers | Anti-patterns from /sw -->

Per /sw skill-writing principles. The brennerbot-with-ntm skill is itself a Claude Code skill, executed by an agent operator. The skill's ergonomics determine whether the operator can apply it under real-time pressure.

This file documents the agent-ergonomic decisions in the skill's design and how to extend them when adding content.

---

## Why agent-ergonomic

A skill that's "comprehensive but unusable" is worse than a thin skill that gets applied. Per /sw philosophy:

- The agent reads the description in the available-skills list (must trigger correctly)
- If activated, the agent reads SKILL.md (front-loaded essentials)
- Only when needed does the agent read references/ files
- Scripts are 0 tokens (executed, not loaded)

For brennerbot, the operator agent has tick-time decisions. If the skill forces a deep tree-search to find the relevant guidance, the operator drifts.

This file captures the decisions that keep the skill operator-ergonomic.

---

## The agent reads first 50 lines

Per /sw: the first 50 lines of SKILL.md determine the agent's interpretive frame. For brennerbot, the SKILL.md opens with:

1. **One Rule**: the optimizing principle for hypothesis deletion.
2. **Cold Start**: the shortest safe route for a new operator who has no BrennerBot context.
3. **Mandatory Loop**: the phase skeleton, with an artifact required at every phase.
4. **Hypothesis Opportunity Matrix / Proof Card**: the scoring and proof discipline that prevents vague research drift.

Those sections set the operator's frame before the large reference library appears: this is a falsification engine running on NTM, not a generic research prompt collection. The detailed tick-time tools now live a little later in SKILL.md: Operator Quickstart, Decision Tree, Red-Flag Phrases, and Liveness Truth Stack.

When adding content to SKILL.md:

- ✗ Don't insert long background prose before Cold Start / Loop / Proof Card
- ✓ Keep the first screen executable for an agent: what this is, how to start, what evidence is required
- ✓ Add new content after the spine; link from the spine only if a cold operator must see it
- ✓ Compress non-critical detail to references/

---

## Trigger optimization

Per /sw, the description triggers the skill. Brennerbot's current description front-loads:

> "Run Brenner-style hypothesis research on native NTM swarms."

This catches the load-bearing concepts: Brenner-style, hypothesis research, native NTM swarms, incident RCA, methodology distillation, and resume/drift checks. Keep "hypothesis", "research", and "NTM swarms" near the front; they disambiguate this skill from `/vibing-with-ntm`, which is about tending already-running panes.

When adding new trigger phrases (per SELF-TEST.md), prefer:
- Operator-task language ("run a brennerbot session", "investigate via Brenner method")
- Symptom language ("methodology drift", "cross-session reconciliation")
- Compose-with language ("brennerbot + codebase-archaeology", "brennerbot for incident-investigation")

---

## Layered context loading

The skill is structured for progressive disclosure:

```
Layer 0 — Description (50-100 chars)        [always loaded; trigger]
Layer 1 — SKILL.md spine (front-loaded route) [loaded when triggered]
Layer 2 — SKILL.md detail (phase loop, assets, scripts, references) [loaded when triggered]
Layer 3 — references/<TOPIC>.md             [loaded on-demand]
Layer 4 — assets/marching-orders/MO-*.md    [loaded by dispatch script]
Layer 5 — assets/templates/*.md             [loaded when rendering]
Layer 6 — scripts/                          [0 tokens; executed]
```

When adding new content, place it at the appropriate layer:

- Always-needed (every session, every operator): SKILL.md spine
- Often-needed (per-session): SKILL.md detail or main references/
- Specific-failure-recovery: references/ catalogs (FAILURE-TABLE, ANTI-PATTERNS)
- Per-phase recipe: references/PHASES.md or per-MO docs
- Domain-specific: references/EXTENDED-PROJECT-TYPES.md or DOMAIN-RECIPE-LIBRARY.md
- Once-per-skill-load: scripts/ (no token cost)

### Layer 1 budget (SKILL.md spine)

Per /sw, the body should be <500 lines. Brennerbot intentionally exceeds this because the cold operator needs the 10-phase route, mode router, proof gates, asset index, and script/subagent inventory without guessing. The validator warns about size; treat that as a budget pressure, not a reason to remove the operator spine.

When adding to the spine: only if the content is *every-tick* critical. Otherwise reference from the spine.

### Layer 3 budget (references)

Per /sw, references should be one level deep (no reference-file → nested-supporting-reference chain). Brennerbot has some violations (per /sw warnings) for unavoidable cross-references (PHASES.md → AGENT-MAIL-FALLBACKS.md). Accept these as documented exceptions.

When adding new references:
- Should have a TOC if >100 lines (per /sw)
- Should link UP to SKILL.md, not LATERALLY to other references (mostly)
- Should be lazy-loadable (operator only reads when relevant)

---

## Decision-tree-first

Per /sw: agents prefer decision trees over prose. SKILL.md's Operator Decision Tree is structured as:

```
Symptom → Diagnosis class → Recovery action
```

Operator scans the tree, matches the symptom, and dispatches the recovery. No prose-reading required.

When extending the decision tree:
- ✗ Don't add prose explanations
- ✓ Add new decision branches at appropriate node
- ✓ Cross-reference details to references/ files

---

## Failure-table-first

Per /sw: failure tables make recovery actionable. Brennerbot's failure rows map F-### codes to:

```
Code | Phase | Symptom | First-aid recovery | Escalate to
```

Operator searches by symptom OR by code, finds the row, applies the action.

When extending:
- ✗ Don't add narrative descriptions
- ✓ Add new F-### codes to the table with consistent format
- ✓ Detailed recovery in references/FAILURE-TABLE.md or references/EXTENDED-FAILURE-CATALOG.md

---

## Card-format references

Per /sw and OPERATOR-CARDS.md format:

```
OC-NNN: <one-line title>
**Trigger:** <specific signal>
**Recipe:** <3-7 line procedure>
**Validator:** <how to know it worked>
```

This format is high-density, agent-scannable. Used for:
- OPERATOR-CARDS.md (31 cards)
- /vibing-with-ntm operator cards (referenced)
- STRESS-TEST-SCENARIOS.md (S1-S15)
- PHASE-1-ANTI-EXAMPLES.md (AE-1.1 through AE-1.10)
- PHASE-7-ANTI-EXAMPLES.md (AE-7.1 through AE-7.10)

When adding new patterns, prefer card format over prose.

---

## Composition over inheritance

Per /sw and SKILL-COMPOSITION-PATTERNS.md: brennerbot deliberately *composes* with adjacent skills rather than reimplementing them.

- Pane-state recovery → /vibing-with-ntm
- Bug hunting on deliverables → /multi-pass-bug-hunting
- Codebase context → /codebase-archaeology
- Prior-session mining → /cass + /flywheel
- Multi-model triangulation → /multi-model-triangulation

This keeps the skill focused on its load-bearing methodology and lets adjacent concerns be handled by their specialists.

When adding new functionality:
- ✗ Don't reimplement what /vibing-with-ntm does
- ✓ Document the composition pattern in SKILL-COMPOSITION-PATTERNS.md
- ✓ Cross-reference the adjacent skill in the dispatch documentation

---

## Self-test triggers

Per /sw + SELF-TEST.md: each skill should have trigger phrases that should activate it. Brennerbot's SELF-TEST.md lists 10+:

- "Investigate the design space for X"
- "Use brennerbot to figure out the best architecture"
- "Run a multi-agent research session on X"
- "Spin up a brennerbot swarm on this codebase"
- "Resume the brennerbot session at <workspace>"
- "Set up a Brenner-style hypothesis-and-evidence loop"
- "Triangulate a research question across cc + cod + gmi"
- "Methodology drift check: how did we diverge?"
- "Run a Brenner-style audit on this design doc"

When adding new sub-skill or capability: add corresponding trigger phrase to SELF-TEST.md.

### Trigger calibration

Test triggers across all 3 model families:
- Haiku: most literal interpreter; clearest signal needed
- Sonnet: balanced
- Opus: most flexible interpreter

If Haiku doesn't trigger reliably, the description is too implicit (per /sw guidance).

---

## Anti-patterns from /sw

| ✗ | Why | brennerbot's defense |
|---|-----|----------------------|
| Description in first person ("I can help...") | Doesn't trigger | brennerbot uses third person ("Tend swarms... Use when...") |
| Blank line before frontmatter `---` | Silently ignored | brennerbot's SKILL.md starts with `---` |
| Skill > 200 lines without progressive disclosure | Context overload | brennerbot uses references/ for layer 3 |
| No "Use when" clause | Triggers vaguely | brennerbot has explicit "Use when" |
| Test only with Opus | Haiku fails silently | brennerbot's SELF-TEST.md probes all 3 |
| Examples buried in references/ | Agent doesn't find them | brennerbot's spine has the Decision Tree |
| Detailed prose explanation in SKILL.md | Tokens wasted | brennerbot uses tables + cards |
| References cite each other excessively | Lazy-load chain breaks | brennerbot accepts some warnings (documented in Meta-Note) |

---

## Specific decisions per /sw

### Decision 1: Front-loaded Method Spine

Per /sw: the first 50 lines determine interpretive frame. Brennerbot now front-loads the One Rule, Cold Start, Mandatory Loop, scoring matrix, and Phase Proof Card so a fresh operator understands the method before opening references.

### Decision 2: Decision Tree Before Deep Reference Reading

Per /sw: agents should not have to deep-read references before acting. Brennerbot's Operator Quickstart and Decision Tree appear in SKILL.md before the long phase, reference, script, and asset inventories.

### Decision 3: Failure Tables Stay Scannable

Per /sw: agents scan failure tables for symptom-match before reading prose. Brennerbot keeps the short pathology table and red-flag phrase table in SKILL.md, with full expansions in references/FAILURE-TABLE.md and related catalogs.

### Decision 4: Mode Router As Quick Decision

Per /sw: agents need fast routing. Brennerbot's Mode Router is a one-row-per-mode reference with explicit auto-detect heuristics and fallback behavior.

### Decision 5: Phase Quick Reference Table

Per /sw: phases should map to quick references, artifacts, and validators. SKILL.md's phase table is the compact phase index; references/PHASES.md is the expansion.

### Decision 6: Anti-Patterns + Pre-Flight after main body

Per /sw: anti-patterns should reinforce, not interrupt, the operating route. SKILL.md keeps the short anti-pattern table before the long operational detail and uses deeper reference files for expanded catalogs.

### Decision 7: Reference index by topic

Per /sw: reference indexes should route by user task. SKILL.md's References section maps topics to the files an operator should open on demand.

### Decision 8: Self-Test at the end

Per /sw: self-test is meta-content; lower priority. Keep trigger calibration in SELF-TEST.md and only surface the routing consequences in SKILL.md.

### Decision 9: Meta-Note on size

Per /sw: large skills should justify their size. Brennerbot's size is justified by its role as an operator methodology, asset index, and native NTM execution guide; additions still need to preserve progressive disclosure.

---

## Adding new content: ergonomic checklist

When adding to brennerbot, check:

1. **Layer**: which layer (0-6) does this content belong to?
2. **Format**: card format if pattern; table if catalog; prose only if argument
3. **Trigger**: does this introduce a new agent-task class? Add to SELF-TEST.md
4. **Cross-reference**: does this cross-link to existing content? One-level-deep only (per /sw)
5. **TOC**: if >100 lines, add `<!-- TOC: ... -->` at top
6. **Anti-pattern table**: most references should end with anti-patterns
7. **Composition note**: if this overlaps with another skill, document the composition pattern

---

## /sw self-validation

Run periodically:

```bash
/home/ubuntu/.claude/skills/sw/scripts/validate-skill.py \
    /data/projects/je_private_skills_repo/.claude/skills/brennerbot-with-ntm/
```

Expect warnings (size, nested refs); investigate any errors.

Compare warnings to the /sw exemplars (vibing-with-ntm, saas-billing): same trade-offs accepted? Then we're calibrated.

---

## Operator-ergonomic anti-patterns we DELIBERATELY accept

Per the SKILL.md Meta-Note, we accept some /sw warnings:

1. **Large SKILL.md body**: the operator needs the method spine, mode router, phase route, and asset/script index in one place; documented.
2. **Nested references**: Cross-domain references (PHASES.md → AGENT-MAIL-FALLBACKS.md) can't be flattened; documented.
3. **Total tokens > 3000**: Brennerbot is a methodology-heavy skill; comparable to vibing-with-ntm and saas-billing.

These are conscious trade-offs. New content should NOT add new such trade-offs unless documented.

---

## Continuous ergonomics review

Per Phase 10 drift, the methodology evolves. Apply the same to ergonomics:

- Quarterly: re-run /sw validate; track warning count over time
- After major content additions: ensure new content lands in correct layer
- If operator productivity drops: surface as Phase 10 lesson; investigate ergonomic root cause

---

## Cross-references

- /sw (workmanship + validation tooling for `.claude/skills/*` directories)
- /sc (sibling tool that turns an existing CLI / codebase into a `.claude/skills/*` directory)
- /operationalizing-expertise (Track-A pattern; QUOTE-BANK-METHODOLOGY)
- vibing-with-ntm (operator-ergonomic exemplar)
- saas-billing-patterns-for-stripe-and-paypal (operator-ergonomic exemplar)
