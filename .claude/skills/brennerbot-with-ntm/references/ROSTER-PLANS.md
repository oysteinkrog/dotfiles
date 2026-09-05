# ROSTER-PLANS.md — Pane Roster by Tier + Role Rotation

<!-- TOC: Tier Definitions | Tier Rosters | Role-Rotation Rules | Role Cards | Domain Assignment | Pane Spawn Patterns | When to Re-Roster Mid-Session -->

The 5 canonical roles map to ntm panes. The roster *tier* (Solo / Pair / Squad / Swarm) determines how many panes per role.

---

## Tier Definitions

| Tier | Pane count | Use when | Wall time budget |
|------|------------|----------|------------------|
| **Solo** | 1 | Quick sanity check; question likely has a known answer | 30–60 min |
| **Pair** | 2 | Two-perspective triangulation, minimal swarm | 1–2 h |
| **Squad** | 5 (default) | Most research questions | 3–5 h |
| **Swarm** | 8–12 | Complex design space; multi-model triangulation; deep audits | half-day to full day |

---

## Tier Rosters

### Solo (1 pane, 1 model family)

```
pane 0 (operator) — human / orchestrator
pane 1 (cc)       — universal pane: proposer + investigator + adjudicator
                    (no devil's-advocate; phase 5 collapsed into self-cross-exam)
```

Limitations:
- Phase 5 cross-examination is degraded (self-debate; lower signal)
- Phase 6 distillation is single-model — no triangulation
- Phase 7 fresh-eyes audit must use kill+respawn to simulate a different perspective

When to escalate: any question where the user actually wants triangulated answers — escalate to Pair or higher.

### Pair (2 panes, 2 model families)

```
pane 0 — operator
pane 1 (cc)  — Proposer + Investigator (cycles)
pane 2 (cod) — Devil's-Advocate + Synthesizer (cycles)
```

Adjudication: rotates between pane 1 and pane 2 (never the same one twice in a row for the same H).

### Squad (5 panes, default)

```
pane 0 — operator
pane 1 (cc)  — Proposer (designated ⊙ productive-ignorance pane)
pane 2 (cod) — Investigator-A
pane 3 (cc)  — Investigator-B
pane 4 (gmi) — Devil's-Advocate
pane 5 (cc)  — Synthesizer + Adjudicator (rotating)
```

The Adjudicator role rotates among panes 4 and 5 (and pane 1 in early rounds before it's needed for proposing).

### Swarm (8–12 panes)

Example 10-pane configuration:

```
pane 0  — operator
pane 1  (cc)  — Proposer-A (with ⊙ productive-ignorance directive)
pane 2  (cod) — Proposer-B (full corpus access)
pane 3  (gmi) — Proposer-C (full corpus access)
pane 4  (cc)  — Investigator-1
pane 5  (cod) — Investigator-2
pane 6  (cc)  — Investigator-3
pane 7  (gmi) — Devil's-Advocate-A
pane 8  (cc)  — Devil's-Advocate-B
pane 9  (cod) — Synthesizer-cod
pane 10 (gmi) — Synthesizer-gmi
pane 11 (cc)  — Synthesizer-cc + Meta-synthesizer (later phases)
```

Adjudicator rotates among panes 7–11 (the synthesizers and devil's advocates).

---

## Role-Rotation Rules

### Mandatory rotations

1. **Adjudicator never adjudicates the same H twice in a row.** Tracked in `session-logs/round-N.md`.
2. **Adjudicator is never a champion of the H being adjudicated.** Auto-detected by `scripts/audit-bead-invariants.sh`.
3. **Devil's-Advocate must be a different model family than the strongest-confidence Proposer.** Apply 🤝 GAN.
4. **Phase 6 Meta-synthesizer is a different model family than the dominant per-family distillation.** This forces the meta-synthesizer to surface disagreements rather than rubber-stamp.
5. **Phase 7 audit panes must include ≥1 different model family from Phase 6 synthesizer panes.** Fresh eyes need fresh families.

### Recommended rotations

- **Investigator → Devil's-Advocate flip** when an Investigator shows confirmation bias (F-403): use `MO-mode-flip-investigator-to-advocate.md`.
- **Synthesizer-as-Adjudicator** rotation for Phase 5 mid-debate adjudications when the named Adjudicator is saturated.
- **Productive-Ignorance pane rebinding** between Phase 3 and Phase 4: the ⊙ pane can shift to Investigator role for Phase 4, but should be told *which corpus surfaces to read* — they shouldn't read everything just because Phase 3 is over.

---

## Role Cards (per-role briefings)

Each role card lives at `subagents/<role>.md` and is referenced in `MO-02-onboarding.md`.

### Proposer

**Reads:** corpus (or nothing if ⊙ pane), `intake/question_of_record.md`, prior `H-*` beads.
**Writes:** new `H-*` beads.
**Operators favored:** ◊ (paradox), 𝓛 (recode), ⊘ (level-split), ⌂ (materialize), ✂ (falsifier).
**Default model preference:** cod (broad generation).
**Anti-pattern alarm:** if the slate has only 2 alternatives, MO-03c forces a third.

### Investigator

**Reads:** one assigned `H-*`, the corpus, prior `EV-*`.
**Writes:** `EV-*` beads + per-H evidence pack file.
**Operators favored:** ⟂ (proxy), ↑ (amplify), ⌂ (materialize check), ⊞ (scale), ≡ (invariant), 🔧 (DIY).
**Default model preference:** cc (careful reading + grounded citations).
**Anti-pattern alarm:** all EVs supporting, none refuting → flip to Devil's-Advocate role for next round.

### Devil's-Advocate

**Reads:** the top 2–3 highest-confidence active `H-*`, their evidence packs, prior `C-*`.
**Writes:** `C-*` (critique) beads, counter-`EV-*`.
**Operators favored:** ✂ (forbidden patterns probe), † (kill), 🤝 (GAN partner).
**Default model preference:** gmi (adversarial framing).
**Anti-pattern alarm:** kills every hypothesis on rhetoric → escalate to Adjudicator review per F-501.

### Synthesizer

**Reads:** full session state (all surviving H, EV, DEBATE, audit findings).
**Writes:** `D-*` (distillation) beads + `distillations/by_<model>.md`.
**Operators favored:** ≡ (invariant), ⊘ (level-split across distillations).
**Default model preference:** matches own family (each family writes its own distillation).
**Anti-pattern alarm:** distillations agree by averaging → reject; mandate disagreement.

### Adjudicator

**Reads:** debate threads + cited evidence packs.
**Writes:** adjudication notes; `state:` updates on `H-*` descriptions.
**Operators favored:** † (kill on falsifier-fired), ∿ (dephase check).
**Default model preference:** cc (judgment).
**Anti-pattern alarm:** never kills any H → rotate immediately.

---

## Domain Assignment (for ≥3 investigators)

Per `/vibing-with-ntm` AP-19 (Missing Domain Assignment), explicit domain split is the single biggest productivity lever for wide swarms. For Investigators in Squad / Swarm tiers, assign each pane a **domain** at Phase 2 onboarding:

```
pane 4 (Investigator-1): owns hypotheses {H-001, H-005, H-008}
pane 5 (Investigator-2): owns {H-002, H-007}
pane 6 (Investigator-3): owns {H-003, H-006, H-009}
```

Domains are recorded in `phase0_scope_decision.md`. Re-balance between rounds if one investigator finishes early.

---

## Pane Spawn Patterns

For Squad tier with cc + cod + gmi mix:

```bash
ntm spawn RS-YYYYMMDD-<slug> --cc=3 --cod=1 --gmi=1
ntm --robot-snapshot   # confirm 5 panes alive
```

For Swarm tier:

```bash
ntm spawn RS-YYYYMMDD-<slug> --cc=5 --cod=3 --gmi=2 --no-user
```

Or, after spawning the session, use the canonical pipeline:

```bash
ntm pipeline run .ntm/pipelines/brennerbot-squad.yaml --session RS-YYYYMMDD-slug --var session_id=RS-YYYYMMDD-slug
```

The pipeline embeds the role assignments and dispatches `MO-02-onboarding.md` per pane.

---

## When to Re-Roster Mid-Session

| Trigger | Action |
|---------|--------|
| A pane is saturated (context >85%, circular reasoning) | `ntm --robot-restart-pane=<session> --panes=N --restart-bead=<H-id>`; re-onboard with the same role |
| A pane is rate-limited for >30 min | `ntm rotate <session> --pane=N --account=...` per `/vibing-with-ntm` |
| Confirmation-biased Investigator | Flip to Devil's-Advocate via `MO-mode-flip-investigator-to-advocate.md` |
| Two panes claim same role | Adjudicator (current round's) reassigns; loser gets a different role |
| Phase 7 audit needs fresh perspective | Add 1–2 panes on different model families, e.g. `ntm add <session> --gmi=1` |
| Swarm too thin for parallelization | `ntm scale RS-YYYYMMDD-<slug> --cc=4` to grow |

Record every re-roster in `phase0_scope_decision.md` under `roster_changes:` log.
