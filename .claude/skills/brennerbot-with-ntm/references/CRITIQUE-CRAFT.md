# CRITIQUE-CRAFT.md — How to Write Good Critiques

<!-- TOC: Why critique-craft | Specificity | Citation density | Curse of knowledge | Steelmanning | Ad hominem avoidance | Severity calibration | Brenner-Crick GAN voice | Critiques in adversarial mode | Phase-7 audit critiques | Anti-patterns -->

Mirrors documentation-website's WRITING-CRAFT.md. The quality of critiques (`C-*` beads) directly determines Phase 5 debate quality, which determines Phase 6 distillation quality. Bad critiques → useless debates → averaged distillations.

This file documents the craft of critique-writing for Devil's-Advocate panes (Phase 4), Adjudicators (Phase 5), and Auditors (Phase 7).

---

## Why critique-craft matters

A critique is an *assault on a hypothesis*. Bad assaults bounce off; good ones either fire the falsifier or sharpen the hypothesis. The difference is craft.

Per Brenner §229 ("kill them when they go ugly") + the Crick-Brenner GAN (per Gemini distillation §4.1) — critique is the operational substrate of theory-killing. Good critiques save weeks of investigation; bad ones waste rounds.

---

## Specificity

A critique without specifics is rhetoric, not a critique.

### Bad

> "H-005 doesn't seem right. The reasoning has issues."

### Good

> "H-005's claim depends on assumption A-003 ('memory bandwidth is the bottleneck'). A-003 cites EV-012 (Smith et al. 2023). EV-012's benchmark uses workload class W-1, not W-2 which is what H-005 actually claims. Therefore A-003 is unverified for H-005's regime."

The good version names: specific bead, specific assumption, specific evidence, specific scope-mismatch. Operator can verify each link.

### Specificity checklist

A good critique cites:

- ≥1 specific `H-*`, `EV-*`, `T-*`, or `A-*` bead
- ≥1 verbatim quote from a source
- A specific reason the target fails (not "doesn't feel right")
- A specific observation that would confirm the critique

If any of these is missing, the critique is rhetoric.

---

## Citation density

Per EXEMPLARS.md (Knuth, academic style): citation density signals rigor.

### Healthy critique citation density

For a 1-paragraph critique:
- ≥1 specific bead reference
- ≥1 verbatim quote
- ≥1 concrete observation

### Anti-density

> "Many sources suggest H-005 is wrong."

(No specific source, no quote, no observation.)

### Density done right

> "Three sources support the alternative reading. From Smith 2023 §4.2: 'Under workload class W-2, the cache miss rate dominates.' From Jones 2024 (cited in EV-018): 'Memory bandwidth is rarely the bottleneck above 64 cores.' From the Patel benchmark (`corpus/ingested/S-019/main.md` line 142): 'CPU contention dominates at our scale.' All three contradict H-005's claim that memory bandwidth bottlenecks at our regime."

---

## The curse of knowledge

A reviewer often writes critiques that assume context the target's owner doesn't share.

### Bad (curse-of-knowledge)

> "H-005 is wrong; obviously the cache effects dominate."

(Why "obvious"? The target's owner needs to be told.)

### Good

> "H-005 claims memory bandwidth dominates. But at our workload class, cache effects (specifically L3 contention from concurrent threads) typically dominate before memory bandwidth saturates. See Patel 2024 § Cache-Performance-At-Scale: 'L3 contention contributes 60-80% of stall cycles in 64-core regimes.' This means H-005's mechanism is unlikely to be the load-bearing factor."

The good version pre-fills the unfamiliar reader's context.

---

## Steelmanning

Per the GAN discipline (per Gemini distillation §4.1): a good critique attacks the strongest version of the target, not a weak strawman.

### Bad (strawman)

Target: "H-005: Async I/O improves throughput when network is the bottleneck."
Critique: "H-005 is wrong because async I/O doesn't help when CPU is the bottleneck."

(But H-005 didn't claim that. The critique attacks something the target didn't say.)

### Good (steelman)

Target: same.
Critique: "H-005 claims async I/O improves throughput in network-bottlenecked regimes. The strongest version of this claim is: async I/O improves p99 by ≥2x when network round-trip dominates wall-time. Under THAT version: EV-019 (Kafka benchmark) shows network-bottlenecked workloads see 1.3x improvement, not 2x. So even the strongest H-005 form is partly refuted by EV-019."

The steelman attacks the target's claim *at full strength*. If the steelman fails, the weaker original certainly fails.

---

## Ad hominem avoidance

Critique the hypothesis, not the proposer.

### Bad

> "H-005 was filed by p3, who's been wrong about cache effects before."

(Even if true, irrelevant. Hypotheses stand or fall on evidence, not authorship.)

### Good

> "H-005 fails its falsifier under EV-019 evidence. <details>"

The proposer is irrelevant.

---

## Severity calibration

Per `assets/templates/critique-template.md` rubric: `minor | moderate | serious | critical`.

A critical critique fires the falsifier — the H is dead. A serious critique substantially weakens the claim. A moderate critique reveals a load-bearing assumption is unverified. A minor critique notes a small issue.

### Calibration discipline

- **Critical** (rare): EV-NNN cited fires the H's falsifier verbatim. The H must transition to `state: refuted` per `MO-falsifier-fired.md`.
- **Serious**: a load-bearing assumption is unverified or contradicted. The H should not advance past Phase 5 without addressing.
- **Moderate**: a non-critical assumption is questionable; H stands but with reduced confidence.
- **Minor**: typo, citation issue, formatting; H unaffected.

### Inflation problem

Devil's-Advocate panes sometimes inflate severity to feel productive. The Adjudicator must resist:

> "Your critique is severity:critical but you cite EV-019 which doesn't actually fire H-005's falsifier verbatim. Re-grade as serious or provide the falsifier-firing EV."

Per F-501 anti-pattern: an Adjudicator who never kills suggests F-501; an Adjudicator who kills frequently on rhetoric suggests inflation.

---

## Brenner-Crick GAN voice

The GAN discipline (per Gemini distillation §4.1) has a specific voice:

- Generator (Devil's-Advocate / Investigator): "Here's a claim with a specific mechanism..."
- Discriminator (cross-pane critic): "That claim fails because <specific>..."
- Both: terse, specific, evidence-grounded

### Bad voice (academic-prose)

> "While the proposed mechanism in H-005 has interesting properties, careful consideration reveals that the empirical support, on closer inspection, may be insufficient for the strong conclusion drawn."

### Good voice (Brenner-Crick)

> "H-005 fails: EV-019 shows network-bottlenecked workloads see 1.3x improvement, not the ≥2x H-005's mechanism predicts. Killed."

Terse + specific + evidence-grounded. No hedging.

---

## Critiques in adversarial mode (A6)

For T4+ A6 sessions (per QUESTION-ARCHETYPES.md), critiques become the load-bearing artifact. Quality matters more.

### Per-threat critique structure

```
Threat: <one-line>
Attack class: <correctness | security | etc>
Severity: <levels>
Precondition: <what must hold for attack to succeed>
Attack walkthrough: <step-by-step>
Evidence to confirm: <observable that, if found, proves attack>
Recommended remediation: <specific>
Cost of NOT remediating: <impact estimate>
```

This is more structured than standard critiques. Use the `assets/templates/critique-template.md` adversarial variant.

---

## Phase 7 audit critiques

Auditors write critiques *about the artifact*, not about hypotheses directly.

### Audit-finding template

```
Severity: critical | high | medium | low
Target artifact: <file path or bead id>
Recommendation: <specific>
Evidence: <which content of the target artifact is wrong>
Methodology violation: <which F-### or AP-* this is>
```

Audit findings should cite *specific lines / sections* of the target artifact, not vague "the distillation has issues."

### Bad audit finding

> "The meta_synthesis.md isn't great."

### Good audit finding

> "meta_synthesis.md § Convergent kernel claims I-001 invariant 'memory bandwidth is the bottleneck' is supported by all three families. But by_cod.md § Operators explicitly says 'cod's reading is that CPU contention dominates.' This is a F-602 silent-averaging — a substantive disagreement got merged into convergent kernel. Recommendation: split I-001 into D-NNN entry; reduce convergent kernel to claims actually shared."

---

## Anti-patterns in critique writing

| ✗ | Why |
|---|-----|
| "I disagree" without evidence | Vibes; not a critique |
| Strawman the target | Easy to refute strawmen; doesn't kill the real H |
| Critique the proposer | Ad hominem; methodologically irrelevant |
| Inflate severity | Wastes Adjudicator time; degrades signal |
| Cite "many sources" without specifics | No verifiability |
| Hedge ("perhaps", "it might be") | Per Dijkstra exemplar; assert with evidence |
| Critique without recommended remediation | Phase 5/7 reader doesn't know what to do |
| Critique without "evidence to confirm" | Per ✂ discipline, every claim needs falsifier-equivalent |
| Critique that mentions only the target's strengths | "What I like about H-005..." is praise, not critique |
| Critique that's longer than the target | Brevity signals confidence; verbosity signals doubt |

---

## Worked examples

### Example: Phase 4 Devil's-Advocate critique

**Setup:** Investigator p3 filed H-005 (memory-bandwidth-dominated). Devil's-Advocate p4 (gmi).

**Bad critique:**
```
C-007: H-005 may not be right
target: H-005
attack: I think the memory bandwidth claim is overstated
severity: serious
```

**Good critique:**
```
C-007: H-005 fails under workload class W-2
target: H-005
attack: H-005's mechanism cites memory bandwidth as bottleneck. EV-018 (Kafka benchmark, lines 200-220) shows network-bottlenecked workloads at 100K events/sec see <50% improvement when memory bandwidth is doubled. This contradicts H-005's claim that memory bandwidth is dominant for our regime.
severity: serious
evidence_to_confirm: A repeat benchmark at our specific workload class W-2 with memory bandwidth varied 1x-4x. If improvement remains <50%, H-005 falsifier fires.
```

The good version: specific EV cite + line range, specific quantitative claim, specific reproducibility test.

### Example: Phase 7 audit finding

**Setup:** Auditor reviewing meta_synthesis.md.

**Bad audit finding:**
```
AF-003: meta_synthesis has issues
severity: medium
target: meta_synthesis.md
recommendation: Review and improve
```

**Good audit finding:**
```
AF-003: meta_synthesis.md § Convergent kernel reproduces consensus prior on H-005
severity: high
target: meta_synthesis.md § Convergent kernel
recommendation: Add ∿ Dephase analysis: did our session genuinely test alternatives, or is consensus inheritance? Specifically the third-alternative H-007 (different mechanism) is mentioned only briefly. Recommend Phase 4 reopen targeting H-007 OR document why H-007 was prematurely deferred.
methodology_violation: ∿ Dephase failure (per S8 STRESS-TEST-SCENARIOS); F-301-class on the third-alternative
```

The good version: specific section, specific operator that should have fired, specific recommendation.

---

## Critique calibration metrics

Per METRICS.md, track:

- **Critique-to-EV ratio**: how many critiques per supporting EV? (Healthy: 0.3-1.0; too low → not adversarial enough; too high → spam)
- **Severity distribution**: critical : serious : moderate : minor (Healthy: 1 : 3 : 5 : 10)
- **Critique-induced state changes**: % of critiques that resulted in H state flip (Healthy: 20-40%; lower → critiques are noise; higher → adversarial too aggressive)

These calibrate via OPERATOR-CALIBRATION-LOG.md. Persistent imbalances suggest re-training the operator's critique-writing or rotating panes.

---

## When critiques are well-crafted

The session's evidence packs read like a good court case:

- Each H has supporting EVs cited verbatim
- Each H has refuting EVs (or attempted) cited verbatim
- Each `C-*` is severity-calibrated and evidence-grounded
- The Adjudicator's verdict cites both sides
- The HANDBACK can defensibly trace each claim to evidence

When critiques are poorly-crafted, the session reads like a vibes-based agreement that any rigorous reader will reject.

The craft is learnable. Operators improve over sessions; track via OPERATOR-CALIBRATION-LOG.md and refine via Phase 10 lessons.
