# DOMAIN-AWARE-CONFOUND-DETECTION.md — Catching Confounds Before They Sink the Verdict

<!-- TOC: Why confound detection | The 5 universal confound classes | Per-domain confound libraries | Detection signals | When to apply confound detection | Per-phase confound activity | The confound-as-critique pattern | Anti-patterns | Cross-references -->

A confound is a third factor that *looks like* it's the cause but isn't. Classic example: ice cream sales correlate with drowning, not because ice cream causes drowning but because both correlate with summer (heat). Confounds are the most common *invisible* failure mode — operators feel confident, but the verdict is wrong.

Brennerbot's domain-aware confound detection surfaces likely confounds *automatically* based on the question's domain. The pane gets prompted with "have you considered ... ?" before publishing the verdict.

Mined from `/dp/brenner_bot/CHANGELOG.md` v0.2.0 § Implement domain-aware confound detection.

---

## Why confound detection

Three failures of bare-hands hypothesis testing:

1. **The obvious cause isn't** — the apparent driver is actually downstream of a hidden upstream factor
2. **Selection bias** — the data you have isn't representative; what you observe is filtered through a confound
3. **Reverse causation** — A causes B vs B causes A produces the same correlation; without intervention, you can't tell

Three benefits of disciplined confound detection:

1. **Domain-aware suggestions** — the system knows "in this domain, confounds X, Y, Z are common"
2. **Triggered at the right moment** — confound check happens when there's an H to check, not as abstract list
3. **Surfaced as critiques** — confound detection generates `C-NNN` critique beads with severity calibrated

---

## The 5 universal confound classes

These apply across all domains:

### 1. Reverse causation

> "Maybe B causes A, not A → B"

Detection: are interventions in both directions tested? If only A→B was perturbed (not B→A), reverse causation isn't ruled out.

Example: "high cortisol causes weight gain" — but maybe weight gain causes high cortisol.

### 2. Hidden common cause

> "Maybe both A and B are caused by Z, which is unmeasured"

Detection: are there plausible upstream factors that drive both observed variables?

Example: "ice cream sales correlate with drowning" — both driven by heat.

### 3. Selection bias

> "Maybe the data you have isn't representative; the population is filtered"

Detection: what's the sampling process? Could the filtering itself produce the apparent effect?

Example: "tall basketball players have higher PRP (probability of being recruited to professional)" — measured from a population of recruited players. Selection bias.

### 4. Survivorship bias

> "We're only seeing the survivors; the failures are invisible"

Detection: where did the data come from? Did anything fail to enter the dataset?

Example: "war planes that returned with bullet holes were studied; bullet holes were everywhere except the engine" → engine hits caused crashes (no return). Studying only returnees misses the signal.

### 5. Measurement artifact

> "Maybe the apparent effect is an artifact of how we measure"

Detection: same observation under different measurement methodology — does the effect persist? If not, it's measurement, not phenomenon.

Example: "survey reports of happiness are higher in high-income countries" — but the questionnaire was translated; cultural meaning of "happiness" shifts.

---

## Per-domain confound libraries

Each archetype has domain-specific confounds layered on the universal 5:

### A1 design-space (architectural decisions)

- **Premature optimization confound**: "this design is faster" — measured at unit scale; production may be different
- **Survivorship of designs**: studying production designs; failures didn't ship
- **Operator-bias confound**: the team that designed it evaluated it (per F-403)

### A2 codebase (debugging)

- **Caching confound**: bug appears in code path X; actual cause is stale cache
- **Dependency-version confound**: behavior differs across env; library version mismatch
- **Heisenbug**: instrumentation changes the bug; observation alters phenomenon

### A3 methodology (research-method evaluation)

- **Cherry-picking confound**: papers cited support the methodology; refuting papers excluded
- **Replication-context confound**: original study + replication used different populations
- **Statistical-power confound**: n=5 study "confirmed" methodology; underpowered

### A4 incident (production-incident investigation)

- **Co-incident confound**: deploy + traffic spike + DB migration all occurred near time of incident; isolating cause hard
- **Recovery-bias confound**: incident appeared to resolve when X was done; might've resolved spontaneously
- **Logging-gap confound**: critical signal not logged; "we didn't see X" doesn't mean X didn't happen

### A6 adversarial (security-threat assessment)

- **Defender-perspective confound**: threats come from how you defend, not how attackers think
- **Population-bias confound**: known-attack patterns are the published ones; novel attacks invisible
- **Honeypot-bias confound**: most attacks are kiddies; targeted attacks are rare in honeypot data

### A7 decision (recommendation / option-choice)

- **Stakeholder-frame confound**: the question was framed by people with interests; rephrase neutrally
- **Status-quo confound**: "this works; why change?" — survivorship of incumbent
- **Sunk-cost confound**: prior investment biases the comparison

For each archetype, the confound library has 5-10 entries. Per ARCHETYPE-START-PACKS.md: each start-pack includes the confound list.

---

## Detection signals

Domain-aware confound detection is **automatic** — patterns in the artifact trigger checks:

### Trigger 1: Single-direction perturbation

If H proposes "A causes B" and the slate doesn't have a test for "B causes A" → trigger reverse-causation check.

### Trigger 2: Correlation without intervention

If `EV-NNN` cites correlational data (not interventional) → trigger common-cause check.

### Trigger 3: Population-selection patterns

If H references "data from X source" and X is known-filtered → trigger selection-bias check.

### Trigger 4: Observational-only studies

If `EV-NNN.type == "dataset"` (not "experiment") → trigger survivorship-bias check.

### Trigger 5: Cross-condition consistency

If H references one measurement methodology → trigger measurement-artifact check.

The detector emits a `C-NNN` critique with severity calibrated:

```yaml
id: C-007
label: critique
target: H-002
severity: serious
attack: "Domain confound detected — reverse causation possible. H-002 says 'memory pressure causes tail latency', but no intervention reverses (high latency → memory pressure). Common case in incident-investigation domain (A4)."
evidence: "[inference] from confound library A4"
status: active
```

---

## When to apply confound detection

The detector runs at:

1. **Phase 1 framing** — confound check on the question itself ("what would confound this?")
2. **Phase 3 hypothesis generation** — per H, run confound detection
3. **Phase 4 investigation** — when EV is added, check if it triggers detection signals
4. **Phase 7 audit** — full re-scan of all H + EV + A
5. **Phase 9 handback** — final review before publication

For T3+: detection is mandatory at Phase 7.
For T4+: detection is mandatory at Phase 1 + 7 + 9.

---

## Per-phase confound activity

| Phase | Confound activity |
|-------|---------------------|
| 1 framing | Apply 5 universal confounds to question |
| 3 hypothesis | Per H, run domain-aware detection |
| 4 investigation | EV-triggered detection (correlation → common-cause check) |
| 5 cross-exam | Confound critiques debated like any other |
| 7 audit | Full rescan; high-severity confounds become audit-findings |
| 9 handback | Verdict cites unresolved confound risks (per HANDBACK § Caveats) |

---

## The confound-as-critique pattern

Confound detection produces `C-NNN` critiques (per TRIBUNAL-AND-OBJECTION-REGISTER.md), not separate beads. This means:

1. Confound critiques get same severity calibration
2. Confound critiques can `block freeze` if `severity ≥ serious`
3. Resolution requires `addressed` / `dismissed` / `accepted` like any critique
4. Operators can override with documented reason

The pattern: domain-aware detection IS adversarial review with domain-specific knowledge. It complements the human-driven Devil's-Advocate role.

---

## Cross-session confound patterns

Per FAILURE-MODE-ANALYTICS.md, track confound types across sessions:

- **Reverse-causation confounds dominant in A4** → adjustment to A4 start-pack
- **Selection-bias confounds in A3** → operators citing self-selecting paper sets
- **Operator A consistently misses survivorship-bias** → calibration coaching D-Cal-14

These feed METHODOLOGY-EVOLUTION-LOG.md as quarterly methodology updates.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip confound check; "we know our domain" | Domain expertise is exactly when blind spots are biggest |
| Detect confounds but never file critiques | Detection without action is theater |
| Treat all confound critiques as `severity: minor` | Sandbagging; per Phase 7 audit, this is detected |
| Assume domain-aware library covers everything | Universal 5 should always be applied; domain library augments |
| Run detection only at Phase 7 | Too late; budget is spent on potentially-confounded H |
| Run detection on EVs but not on A's | Assumptions are confound vectors too |
| Domain library not updated when new confounds emerge | Quarterly review per BRENNERBOT-AT-SCALE.md |
| Confound critique without `[inference] from confound library X` anchor | Per CITATION-PROVENANCE-RULES.md: every claim has anchor |

---

## Composition with brennerbot

Confound detection integrates with:

- **Tribunal** (per TRIBUNAL-AND-OBJECTION-REGISTER.md): generates critiques
- **Multi-Agent Tribunal Personas** (per MULTI-AGENT-TRIBUNAL-PERSONAS.md): Devil's Advocate gets domain-confound prompt fragments
- **Counterfactual exploration** (per WHAT-IF-COUNTERFACTUAL-EXPLORER.md): confound-driven counterfactuals
- **Failure analytics** (per FAILURE-MODE-ANALYTICS.md): cross-session confound patterns
- **Question archetypes** (per QUESTION-ARCHETYPES.md): per-archetype confound library

---

## Cross-references

- [TRIBUNAL-AND-OBJECTION-REGISTER.md](TRIBUNAL-AND-OBJECTION-REGISTER.md) — confound generates critiques
- [MULTI-AGENT-TRIBUNAL-PERSONAS.md](MULTI-AGENT-TRIBUNAL-PERSONAS.md) — Devil's Advocate domain prompts
- [WHAT-IF-COUNTERFACTUAL-EXPLORER.md](WHAT-IF-COUNTERFACTUAL-EXPLORER.md) — confound-driven counterfactuals
- [QUESTION-ARCHETYPES.md](QUESTION-ARCHETYPES.md) — per-archetype confound libraries
- [ARCHETYPE-START-PACKS.md](ARCHETYPE-START-PACKS.md) — start-pack includes confounds
- [FAILURE-MODE-ANALYTICS.md](FAILURE-MODE-ANALYTICS.md) — cross-session patterns
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — domain library updates
- /dp/brenner_bot/CHANGELOG.md v0.2.0 § Implement domain-aware confound detection — feature source
