# PILOT-RETROSPECTIVE-PROTOCOL.md — Operational Lessons from Real Pilots

<!-- TOC: Why a retrospective | The retrospective format | The 4-section structure | Per-section guidance | Discovered work + bead generation | When to run a retrospective | Cross-pilot pattern detection | Per-organization rollup | Anti-patterns | Cross-references -->

A pilot retrospective captures what worked, what failed, and what to change — based on **real pilot sessions**, not abstract reasoning. It's the bridge between "the methodology spec" and "the methodology in practice."

This file specifies the retrospective format, the 4 canonical sections, the discovered-work pattern, and the cross-pilot rollup.

Mined from `/dp/brenner_bot/specs/pilot_retrospective_v0.1.md` (which itself is the canonical example).

---

## Why a retrospective

Specs describe *intended* behavior. Real pilots reveal *actual* behavior, including:

- Failure modes that emerge only at full scale
- Friction points operators silently adapt around
- Spec ambiguities the model interprets differently than expected
- Format-evolution failures (per DELTA-PROTOCOL-FAIL-FAST.md)

Without a retrospective protocol, these lessons are lost. With it, every pilot becomes a methodology contribution.

---

## The retrospective format

A pilot retrospective is a Markdown file at:

```
docs/pilot-retros/PILOT-RETRO-<YYYY-MM-DD>-<slug>.md
```

It has YAML frontmatter:

```yaml
---
status: working_memo | finalized
purpose: <single sentence>
inputs_reviewed:
  - <session-id-1>: <one-line description>
  - <session-id-2>: <one-line description>
date: <ISO>
authors: [<operator-id>, ...]
---
```

Plus the 4 canonical sections (next).

---

## The 4-section structure

Every retrospective has these sections in this order:

```
## 1) What Worked (keep / amplify)
## 2) What Failed / Friction (fix next)
## 3) Proposed Protocol/Kernel Changes (concrete)
## 4) Discovered Work (Beads)
```

### Section 1: What Worked (keep / amplify)

Subsections per worked-thing:

```markdown
### A) Role-separated prompting + operator framing

- Role separation (Hypothesis Generator / Test Designer / Adversarial Critic) reliably produced *complementary* deltas (hypotheses, tests, critiques) instead of homogenized "consensus chat".
- The "triangulated kernel" framing makes the session feel like a *method* rather than a vibe.
```

Quality bar:
- Specific behavior, not "it was good"
- Citation to session evidence (which session? which round?)
- Why it worked (mechanism), not just that it worked

### Section 2: What Failed / Friction (fix next)

Subsections per failure mode:

```markdown
### A) "Inline deltas" are a high-frequency, high-impact failure mode

Observed in pilots (Round 2 explicitly calls this out as "format evolution"):
- Agents sometimes post inline JSON that *looks* like a delta but is not wrapped in a fenced `delta` code block.
- The delta parser then extracts **0 blocks**, and compilation silently drops the intended update.

This is not a "doc polish" issue — it is a *protocol robustness* issue because it breaks the mechanistic handshake.
```

Quality bar:
- Concrete observed behavior (with session/round citation)
- Categorize as protocol/spec/UX issue
- Explicit cost: what does the failure produce?

### Section 3: Proposed Protocol/Kernel Changes (concrete)

For each failure in Section 2, propose a specific change:

```markdown
### Change 1: Fail-fast on DELTA messages with 0 parsed delta blocks

**Why**: silent drops destroy operator trust; the system must be noisy when the handshake fails.

**Implementation**: see bead `brenner_bot-a3z4`.

### Change 2: Make delta-format failure modes impossible to miss in specs

**Why**: "delta blocks" are the protocol's machine language; the spec must be brutally explicit.

**Implementation**: see bead `brenner_bot-1fvd`.
```

Quality bar:
- Concrete change description (not "improve documentation")
- Explicit reasoning ("why" line)
- Bead reference for tracking implementation

### Section 4: Discovered Work (Beads)

Append-only list of beads created from this retrospective:

```markdown
## 4) Discovered Work (Beads)

Created from this retrospective (all `discovered-from:brenner_bot-5so.10.3`):
- `brenner_bot-a3z4` — Bug: compile should surface missing delta code fences
- `brenner_bot-1fvd` — Spec: delta formatting failure modes + remediation template
- `brenner_bot-evjo` — Feature: CLI session diagnose delta parsing failures
```

Quality bar:
- Every bead has a one-line description
- Every bead has the `discovered-from:` link to this retrospective
- Bead labels are appropriate (bug / spec / feature)

---

## Discovered work + bead generation

The retrospective is **action-generating**. Each Section-3 proposed change → one or more `discovered-from:` beads in Section 4.

Bead conventions:

```bash
# Create a bead from a retrospective change:
br create \
  --type=task \
  --labels="discovered-bug" \
  --description="Compile should surface missing delta code fences (per pilot retro 5so.10.3)" \
  --discovered-from="<retro-bead-id>" \
  --priority=1
```

The `discovered-from` field links the bead to its source retrospective. Per CASS-MINING-RECIPES.md, this enables: "show me all beads discovered from real pilot work in the last quarter" — a high-signal filter.

---

## When to run a retrospective

Triggers:

- **After any T3+ pilot session** (mandatory)
- **After 3+ T1-T2 sessions** in the same archetype (cumulative pattern detection)
- **After any session with a high-severity audit-finding** (incident-class)
- **Quarterly** for at-scale operators (per BRENNERBOT-AT-SCALE.md)
- **Before any methodology version bump** (e.g., delta_format v0.1 → v0.2)

The retrospective is **NOT** a replacement for Phase 10 drift check. Drift check measures trajectory; retrospective produces actionable changes.

---

## Cross-pilot pattern detection

When multiple retrospectives surface similar issues:

```
Retro-A (2026-03-01): "Inline deltas without fence — 5 instances"
Retro-B (2026-03-15): "Inline deltas without fence — 3 instances"
Retro-C (2026-04-10): "Inline deltas — 8 instances; agents getting worse"
```

Pattern detected: 3+ retrospectives surface the same issue → escalate to **methodology issue, not session issue**:

1. Promote to METHODOLOGY-EVOLUTION-LOG.md as a methodology bug
2. Generate cross-pilot bead: "Methodology: agents systematically miss the fence requirement"
3. Trigger spec/role-prompt update (not just per-session fix)

This is the difference between fixing one session's failure and fixing the methodology.

---

## Per-organization rollup

Per BRENNERBOT-AT-SCALE.md, organizations running 10+ sessions/week:

- Aggregate retrospectives quarterly
- Identify the top-3 friction patterns
- Generate organization-level methodology updates

Format:

```markdown
# Q1 2026 Brennerbot Retro Rollup

## Top 3 Friction Patterns

1. **Inline-delta-without-fence**: appeared in 7/12 retrospectives.
   Status: spec change v0.2; fail-fast added; recurrence rate dropping.

2. **Adjudicator-non-rotation**: appeared in 4/12 retrospectives.
   Status: rule enforcement added (scripts/check-rotation-rules.sh); recurrence dropped to 0/4 in latest sessions.

3. **Phase-1-framing-rushed**: appeared in 5/12 retrospectives.
   Status: FRAMING-WORKBOOK F1-F9 introduced; tracking impact.

## Cross-pattern observations
...
```

The rollup feeds METHODOLOGY-EVOLUTION-LOG.md.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip the retrospective ("session went fine") | Even successful sessions have lessons |
| Retrospective without session citation | Vague; not actionable |
| Section 3 proposes "improve documentation" | Too vague; specify what changes and how |
| No Section 4 beads (retrospective without action items) | Lessons evaporate; nothing changes |
| Multiple retrospectives without rollup | Cross-pilot patterns invisible |
| Retrospective written by single operator without review | Misses other perspectives; bias |
| Retrospective that only documents failures | "What worked" matters too — confirms what to keep |
| Retrospective that documents successes only | Missing the failure signal |
| Sit on a methodology issue across 3+ retros without escalating | Pattern → cross-pilot rollup |

---

## Composition with brennerbot phases

| Phase | Retrospective activity |
|-------|---------------------------|
| 8 freeze | Note "retrospective candidate" if anything notable happened |
| 9 handback | HANDBACK § Lessons hints at retrospective topics |
| 10 drift | Drift check may identify methodology drift; retrospective addresses it |
| Post-session (within 48h) | Write the retrospective while context is fresh |
| Quarterly | Rollup across retrospectives |

---

## The pilot_retrospective_v0.1.md exemplar

The original pilot retrospective in `/dp/brenner_bot/specs/pilot_retrospective_v0.1.md` is the canonical example. New retrospectives should:

- Match its 4-section structure
- Match its specificity (citation to session evidence)
- Match its action-generating discipline (Section 4 beads)

Operators learning the protocol should read it as the model.

---

## Cross-references

- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — quarterly rollup destination
- [DELTA-PROTOCOL-FAIL-FAST.md](DELTA-PROTOCOL-FAIL-FAST.md) — example of retrospective-driven protocol change
- [POST-MORTEM-FORMALIZATION-PLAYBOOK.md](POST-MORTEM-FORMALIZATION-PLAYBOOK.md) — incident retrospectives
- [DRIFT-RUBRIC.md](DRIFT-RUBRIC.md) — Phase 10 drift check
- [CROSS-SESSION-LEARNING.md](CROSS-SESSION-LEARNING.md) — cross-session learning protocol
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — at-scale rollup
- [CASS-MINING-RECIPES.md](CASS-MINING-RECIPES.md) — discovered-from filtering
- /dp/brenner_bot/specs/pilot_retrospective_v0.1.md — canonical example
