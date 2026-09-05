# POST-BRENNERBOT-METHODOLOGIES.md — What Comes After

<!-- TOC: Why think post | The 5 emerging directions | Direction 1: continuous research programs | Direction 2: federated multi-org sessions | Direction 3: methodology-of-methodology evolution | Direction 4: hybrid human-AI sessions at scale | Direction 5: cross-domain methodology export | Capability gaps to fill | When to fork the methodology | Anti-patterns | Cross-references -->

The Brenner method (in the brennerbot-with-ntm form) is **not the end state**. It's a substrate that subsequent methodologies will build on, replace parts of, or supersede entirely. Operators planning long-term should think about what comes after.

This file names 5 directions where post-brennerbot methodologies are emerging — all extrapolated from current limitations and where /dp/brenner_bot's roadmap suggests evolution.

This is original synthesis. Where these directions emerge depends on operator demand, AI agent capability evolution, and ongoing methodology research.

---

## Why think post

Three reasons to think beyond brennerbot:

1. **Locked-in to current limits** — operators committed to brennerbot may not adapt when the world changes
2. **Methodology lifecycle** — every methodology has a lifecycle; brennerbot will too
3. **Composability with new methods** — knowing what's coming lets you compose, not replace

Three benefits of forward-thinking:

1. **Smoother transition** — when post-brennerbot methods emerge, you've prepared
2. **Hybrid use** — you can use brennerbot + emerging method together rather than choose
3. **Methodology innovation** — you can *contribute* to post-brennerbot methods rather than wait

---

## Direction 1: Continuous research programs

**Current state:** brennerbot sessions are episodic (kickoff → freeze → handback). Cross-session is rare; programs (per RESEARCH-PROGRAMS.md) aggregate but don't continuously update.

**Emerging direction:** **continuous research programs** — running 24/7, with hypotheses that are perpetually under investigation.

**What changes:**
- Hypotheses don't reach `validated` terminal state — they have *time-windowed* validation ("validated as of 2026-Q2; re-validation due 2026-Q4")
- Sessions become *checkpoints* in an ongoing investigation, not bounded units
- The hypothesis-funnel becomes a **flow** rather than a stage-gate

**Brennerbot infrastructure that supports this:**
- RESEARCH-PROGRAMS.md (multi-session aggregation)
- LIVING-DOCUMENTATION-PATTERNS.md (cadence-driven refresh)
- HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md (`dormant` ↔ `active` reactivation)

**What's missing:** explicit time-windowed validation; automatic re-investigation triggers when validation expires.

---

## Direction 2: Federated multi-org sessions

**Current state:** brennerbot sessions are single-organization. Cross-org collaboration uses external coordination (papers, conferences); the methodology runs locally per org.

**Emerging direction:** **federated sessions** — multiple organizations contribute panes to a shared session, with privacy boundaries respected.

**What changes:**
- Org A's evidence pack and Org B's evidence pack are *combined* in a shared evidence pack
- Hypotheses from both orgs face the same Phase 5 cross-exam
- Verdicts are co-published

**Brennerbot infrastructure that supports this:**
- Agent Mail's cross-project boundaries (per cross_workspace_binding_v0.1.md)
- LAB-MODE-AUTHORIZATION.md (auth per workspace)
- EVIDENCE-PACK-PROTOCOL.md `imported_from` (cross-source attribution)

**What's missing:** privacy-preserving evidence sharing (Org A doesn't want to expose its raw data); federated identity for inter-org pane authentication; cross-org HANDBACK conventions.

**Implication:** brennerbot is positioned to be a research-collaboration platform, not just an internal tool.

---

## Direction 3: Methodology-of-methodology evolution

**Current state:** the brennerbot methodology is *applied* to research questions. The methodology itself evolves through pilot retrospectives + methodology-evolution-log + quarterly review.

**Emerging direction:** **the methodology evolves continuously**, driven by aggregated session metrics and cross-pilot patterns. The methodology runs *as a brennerbot session* on itself.

**What changes:**
- Methodology updates are formalized as Phase 6 distillations across sessions
- The "champion methodology" is the version that wins the most sessions over time
- Methodology versions are first-class artifacts (per METHODOLOGY-EVOLUTION-LOG.md, but more rigorous)

**Brennerbot infrastructure that supports this:**
- METHODOLOGY-EVOLUTION-LOG.md
- FAILURE-MODE-ANALYTICS.md (cross-session patterns)
- PILOT-RETROSPECTIVE-PROTOCOL.md
- THREE-DISTILLATIONS-CROSSWALK.md (this skill IS this direction applied to /dp/brenner_bot)

**What's missing:** automated methodology-pull-request system; A/B testing of methodology variants across sessions; champion-methodology declaration.

---

## Direction 4: Hybrid human-AI sessions at scale

**Current state:** brennerbot sessions are AI-multi-pane with human operator. Humans intervene per OPERATOR-INTERVENTION-RECORDING.md but aren't *participants* in the AI tribunal.

**Emerging direction:** **human panes alongside AI panes** as full participants — humans contribute deltas via the same delta protocol; their critiques and hypotheses are first-class.

**What changes:**
- Roster expands to include `role: human_panelist`
- Humans interact via the web UI (per /dp/brenner_bot/apps/web)
- Tone calibration extends to human voice (per MULTI-AGENT-TRIBUNAL-PERSONAS.md)
- The hybrid combines AI breadth with human depth-on-specific-domains

**Brennerbot infrastructure that supports this:**
- AGENT-ROSTER-AND-PRESETS.md (`agent_name: human` patterns exist)
- DELTA[human] subject prefix (per MESSAGE-BODY-SCHEMA-PER-TYPE.md)
- The web UI for human delta-authoring

**What's missing:** real-time pane-quality feedback to humans (humans don't see scoring in real-time); human-pane onboarding for non-experts; conventions for handling slow-human-response timing differences.

---

## Direction 5: Cross-domain methodology export

**Current state:** brennerbot is shaped for software/research domains. Per QUESTION-ARCHETYPES.md A1-A10 + EXTENDED-PROJECT-TYPES.md, it adapts to domains, but the core methodology is tuned for "questions you can compute against."

**Emerging direction:** **methodology exports** for domains that didn't shape the original — clinical research, policy analysis, design research, climate-modeling, etc.

**What changes:**
- New archetypes (A11, A12, ...) that don't fit current 10-archetype taxonomy
- Domain-specific evidence types beyond `paper | dataset | experiment` (per EVIDENCE-PACK-PROTOCOL.md)
- Domain-specific role personas (e.g., "Clinical-Reviewer" for medicine; "Policy-Analyst" for governance)

**Brennerbot infrastructure that supports this:**
- ARCHETYPE-START-PACKS.md (extensible)
- DOMAIN-AWARE-CONFOUND-DETECTION.md (already domain-aware)
- SESSION-AND-DOMAIN-TEMPLATES.md (domain templates)

**What's missing:** institutional credibility in non-software domains; domain-expert-authored archetypes; cross-domain exemplar walkthroughs (per EXEMPLAR-SESSION-WALKTHROUGH.md).

---

## Capability gaps to fill

For each direction, capability gaps:

| Direction | Gap |
|-----------|-----|
| Continuous research programs | Time-windowed validation; auto-re-investigation triggers |
| Federated multi-org sessions | Privacy-preserving evidence sharing; federated identity |
| Methodology-of-methodology evolution | Methodology-PR system; A/B testing of variants |
| Hybrid human-AI sessions | Real-time scoring feedback; human onboarding |
| Cross-domain methodology export | Domain-expert authoring; institutional credibility |

These gaps are *future work*. Operators interested in these directions can contribute by:

1. Documenting use-cases that exemplify the direction
2. Building the missing infrastructure
3. Running pilots that *fail* in informative ways
4. Submitting pilot retrospectives that map to the directions

Per BRENNERBOT-AT-SCALE.md: aggregate pilots toward methodology evolution.

---

## When to fork the methodology

The Brenner method may need to be *forked* — not extended — when:

- **The core axioms don't apply** — domain doesn't believe in "generative grammar" or "to understand is to reconstruct"
- **The hypothesis state machine doesn't fit** — domain has different lifecycle (e.g., "evolving" vs "draft → killed/validated")
- **The discriminative-test discipline doesn't exist** — domain doesn't have the concept of "test that eliminates options"

Forking ≠ rejecting. A fork is a respectful "this method works for domain X but not Y; we're building a sister method."

Per AGENTS.md: forks are documented; not deleted; cross-referenced.

---

## How to recognize you're at a methodology frontier

Detection signals:

- **Sessions consistently miss specific F-codes** — the failure mode is structural; methodology gap, not session gap
- **Cross-pilot retrospectives surface same proposed change repeatedly** — the change is needed
- **External methodology development passes brennerbot in capability** — competitive pressure to evolve
- **Operators consistently work *around* a constraint** — the constraint is methodology-imposed, not domain-imposed

Per FAILURE-MODE-ANALYTICS.md cross-session patterns: methodology-frontier signals show up here first.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Treat brennerbot as the final form | Methodologies evolve; planning matters |
| Force-fit brennerbot to all future directions | Sometimes a fork is right |
| Skip the post-thinking exercise | "What comes next" influences current decisions |
| Adopt every emerging direction | Each direction has costs; choose deliberately |
| Replace brennerbot prematurely | Current methodology is well-tested; transition carefully |
| Refuse to fork when the domain demands it | Forks are respectful, not betrayal |
| Wait for a methodology revolution | Continuous evolution beats waiting for revolution |

---

## Composition with brennerbot

This reference is **strategic** — for operators planning multi-quarter or multi-year brennerbot use. It's not for individual sessions.

Read this:
- When deciding whether to invest in brennerbot at scale (per BRENNERBOT-AT-SCALE.md)
- When considering brennerbot adoption in a new domain
- When facing methodology limits (per THE-LIMITS-OF-BRENNER-METHOD.md)
- When committing to long-term research programs (per RESEARCH-PROGRAMS.md)

---

## Cross-references

- [THE-LIMITS-OF-BRENNER-METHOD.md](THE-LIMITS-OF-BRENNER-METHOD.md) — current limits motivate post-thinking
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — at-scale operational patterns
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — methodology change tracking
- [PILOT-RETROSPECTIVE-PROTOCOL.md](PILOT-RETROSPECTIVE-PROTOCOL.md) — pilot-driven evolution
- [RESEARCH-PROGRAMS.md](RESEARCH-PROGRAMS.md) — multi-session aggregation
- [LIVING-DOCUMENTATION-PATTERNS.md](LIVING-DOCUMENTATION-PATTERNS.md) — continuous-research patterns
- [GROUP-COGNITION-PATTERNS-FROM-MULTI-PANE.md](GROUP-COGNITION-PATTERNS-FROM-MULTI-PANE.md) — patterns to extend
- [THREE-DISTILLATIONS-CROSSWALK.md](THREE-DISTILLATIONS-CROSSWALK.md) — meta-methodology already practiced
