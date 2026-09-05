# ANTI-ANALOGY-AND-PLAUSIBILITY.md — Two Methodological Warnings

<!-- TOC: Why these matter | Anti-analogy: when metaphors lie | Plausibility filter: pruning before experimenting | Detection patterns | Per-phase application | Anti-patterns | Cross-references -->

Two of Brenner's most under-discussed disciplines:

1. **Anti-analogy** — reject "logical but non-natural" theories; metaphors that *seem* perfect are often misleading
2. **Plausibility filter** — use physics/scale to prune hypothesis space *before* running experiments

Both are constraints on what hypotheses get to enter the slate. Without them, sessions waste effort on hypotheses that physics or domain reality rule out *a priori*.

Mined from `/dp/brenner_bot/metaprompt_by_gpt_52.md` tags `anti-analogy` and `plausibility-filter` and the underlying transcript anchors.

---

## Why these matter

Both warnings preempt entire classes of bad investigations:

- **Anti-analogy** prevents 30-90 minute Phase 4 rounds that go in circles because "the metaphor sounded right but the system doesn't actually work that way"
- **Plausibility filter** prevents Phase 4 rounds testing physically impossible Hs

For T3+ sessions, both are checked at Phase 1 framing. For incident-investigation, applied even more aggressively (time pressure makes wasted rounds catastrophic).

---

## Anti-analogy: when metaphors lie

### The principle

A metaphor that "fits" too cleanly is suspicious. Brenner's example: computational metaphors for biology. "Computation" feels like the right metaphor for cells, but cells do strong analogue computation that the digital metaphor misses. The result: theories built on the metaphor make wrong predictions.

In code: the "object-oriented inheritance is like biological inheritance" metaphor was widely seductive and led to catastrophically over-engineered class hierarchies. The biological inheritance system is *not* the right model for code reuse.

### Detection signals

A pane has fallen for an analogy when:

- The H is stated in terms of the source domain ("our system has antibodies that...")
- Predictions are derived by analogy ("if neurons fire, then our messages should...")
- Falsifiers are the analogy's failure modes ("if the antibodies don't recognize...")
- The analogy is presented as load-bearing ("the whole architecture works like the immune system")

### Recovery

When detected (per Red-Flag Phrases or Phase 7 audit):

1. **Force re-statement in machine language** — the system's own primitives, not the analogy's. Per BRENNER-VOCABULARY.md "Machine language."
2. **Demand independent prediction** — what does the H predict that's NOT a translation of the analogy?
3. **Apply ∿ Dephase** — if the analogy is consensus, deliberately seek the contrarian framing.
4. **Re-grade falsifier** — analogies often produce vague falsifiers; per `subagents/falsifier-grader.md`.

### Per-domain warning examples

| Domain | Common bad analogy | What it misses |
|--------|---------------------|----------------|
| Distributed systems | "It's like a brain — neurons firing" | Brains have global signaling; networks have routing latencies |
| ML | "It's like human reasoning" | LLMs don't have memory across calls by default |
| Microservices | "Like cellular biology" | Cells have stable membranes; service boundaries leak |
| Auth/security | "Like a bouncer at a club" | Bouncer is binary; auth has many gradations |
| Concurrency | "Like a kitchen" | Cooks don't have global state-machine constraints |
| Caching | "Like memory" | Memory is uniform; caches have hot/cold + invalidation |
| Databases | "Like filing cabinets" | Cabinets don't have transactions or replication |

When you reach for a metaphor, *also* state the metaphor's failure modes. If you can't, the metaphor is doing too much work.

---

## Plausibility filter: pruning before experimenting

### The principle

Some hypotheses are physically/scale impossible. Don't put them in the slate. Don't waste a Phase 4 round investigating them. Per ⊞ Scale-Check + TEN-PRINCIPLES.md #8 ("imprisoned in physics").

Brenner's example: claims about DNA structure that violated the known length-vs-cell-volume math. He'd reject those *before* designing experiments. "DNA is 1mm long in a 1μm bacterium, folded 1000×" — calculations like this prune the hypothesis space.

In code: claims about throughput that exceed the bandwidth of the underlying network or disk. Throughput-bound systems can be analyzed via Little's Law before any benchmark runs.

### The discipline

For every candidate H, before adding it to the Phase 3 slate:

1. **List the load-bearing physical assumptions** (network bandwidth, disk IOPS, memory bandwidth, query plan complexity, etc.)
2. **Compute the rough magnitudes** — order of magnitude is enough; don't chase precision
3. **Check for impossibility** — does any computation exceed a known limit?
4. **If impossible: reject the H immediately**; don't add to slate
5. **If possible-but-tight: tag with `assumption_type:scale_physics`**; require explicit calculation in Phase 4

This pruning is cheap (minutes) but kills hours of bad investigation.

### Detection

A pane is missing the plausibility filter when:

- H proposed without scale-magnitude calculation
- Falsifier doesn't reference physical limits
- Phase 4 evidence pack doesn't include scale verification
- Audit finding (per AE-7.7) catches scale-physics calculation missing

### Per-domain plausibility heuristics

| Domain | Quick plausibility check |
|--------|---------------------------|
| Network systems | Bandwidth × latency; Little's Law for throughput-vs-concurrency |
| Storage | IOPS × seek-time × utilization for disk-bound; cache hit-rate for read-bound |
| ML | Compute / dataset size for training; memory / parameter count for inference |
| Concurrency | Context-switch overhead × thread count; lock contention via Amdahl's law |
| Distributed | CAP triangle; network partition probabilities |
| Auth | Session token entropy / brute-force-rate vs replay attempts |
| Cryptography | Key size / current attack capability per NIST guidance |
| UI rendering | Frame budget / layout complexity / repaint cost |

For T3+ sessions in any domain, the plausibility filter is mandatory at Phase 1 framing.

---

## Detection patterns

### Anti-analogy red flags

Pane tail contains:
- "...just like in [other domain]..."
- "...analogous to..."
- "...think of it as..."
- "...the same as..." (without per-domain caveat)

Per Red-Flag Phrases in SKILL.md.

### Plausibility-filter failure red flags

Pane tail contains:
- An H without calculation
- "Should scale to 100k req/s" (without latency × concurrency math)
- "Big-O is fine" (without constant-factor analysis)
- "Memory is enough" (without precise estimate)

---

## Per-phase application

### Phase 1 framing

Apply BOTH filters when drafting the question of record:

- Anti-analogy: re-state in machine language; check that no metaphor is load-bearing
- Plausibility: list scale assumptions; verify physical possibility

### Phase 3 hypothesis generation

Apply BOTH filters per proposed H:

- Anti-analogy: each H should be machine-language native, not metaphor-derived
- Plausibility: each H should be scale-physics-checked before adding to slate

If a proposed H fails either filter, it's NOT added to the slate. Document the reason in `phase0_scope_decision.md § rejected_hypotheses`.

### Phase 4 investigation

Plausibility filter is automatic via `assumption_type:scale_physics` beads. Anti-analogy filter is checked via:

- EV beads should cite specific code/data, not metaphor predictions
- Critique beads (`C-NNN`) call out hypotheses that lean on analogy

### Phase 7 audit

Audit panes specifically check:

- Did any active H rely on a metaphor that the artifact doesn't justify? (anti-analogy violation; AF severity:medium)
- Did any active H lack scale-physics calculation? (plausibility violation; AF severity:high; per AE-7.7)

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Use metaphor in framing without disclaimer | Metaphors are heuristics, not theories |
| Skip plausibility filter "we'll find out empirically" | Cheap calculation prevents expensive experiments |
| Trust an analogy because "it works for our team's intuition" | Team intuition is consensus, not validation |
| Use plausibility filter only at Phase 7 | Too late; budget already spent |
| Treat anti-analogy as "no metaphors allowed" | Metaphors are useful; the discipline is to disclose load-bearing-ness |
| Skip the failure-mode listing for analogies | Without it, the analogy is doing more work than it can support |
| Allow scale-physics assumption without explicit calculation | Per AE-7.7; mandatory at Phase 7 |
| Reject all metaphors aggressively | Sometimes the analogy is a useful starting point; just don't let it carry weight |

---

## When the analogy is the answer

Sometimes the right move IS to find the right analogy — when:

- An adjacent field has *the same problem* and a known solution
- The translation is verifiable mechanism-by-mechanism
- Independent panes reach the same analogy from different starting points

In these cases, the analogy isn't an anti-analogy but a *cross-domain import* (per ⊕). The discipline is to make the import explicit:

- Document the source domain
- List the load-bearing translation steps
- Identify what's NOT translated (the failure modes of the analogy)
- Verify the translation produces machine-language-native predictions

Per `MO-cross-domain-import.md`: cross-domain imports are powerful when applied with discipline.

---

## Cross-references

- [BRENNER-VOCABULARY.md](BRENNER-VOCABULARY.md) — anti-analogy, plausibility filter, machine language
- [TEN-PRINCIPLES.md](TEN-PRINCIPLES.md) — principle #8 (imprisoned in physics)
- [OPERATORS.md](OPERATORS.md) — ⊞ Scale-Check, ⊕ Cross-Domain
- [PHASE-1-ANTI-EXAMPLES.md](PHASE-1-ANTI-EXAMPLES.md) — AE-1.* framing failures
- [PHASE-7-ANTI-EXAMPLES.md](PHASE-7-ANTI-EXAMPLES.md) — AE-7.7 scale-physics skip
- [MO-cross-domain-import.md](../assets/marching-orders/MO-cross-domain-import.md) — disciplined cross-domain
- /dp/brenner_bot/metaprompt_by_gpt_52.md tags `anti-analogy`, `plausibility-filter` — original source
