# HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md — The 9-State Hypothesis FSM

<!-- TOC: Why an FSM | The 9 states | State-name mapping (bead state field ↔ FSM state) | Valid transitions | Transition events | Side effects | State invariants | Per-state operator behavior | Detection: detecting illegal transitions | The under_attack and assumption_undermined patterns | Refined-as-versioning | Anti-patterns | Cross-references -->

A hypothesis is not just "active" or "refuted" — it lives in one of **9 distinct lifecycle states** with formally-typed transitions, side effects, and invariants. Without this machinery, sessions confuse "actively challenged" with "killed", lose audit trails on refinement chains, and silently bypass adversarial review.

This file is the canonical conceptual FSM. Bead descriptions still store the compact 6-state vocabulary used by `BEADS-SCHEMA.md` and `audit-bead-invariants.sh`; the mapping below is normative. Every conceptual transition MUST map to one of those compact bead-state changes.

Mined from `/dp/brenner_bot/README.md § Hypothesis Lifecycle State Machine` and the brenner-loop implementation at `/dp/brenner_bot/brenner.ts`.

---

## Why an FSM

A 2-state model (`active` / `refuted`) loses critical information:

- **"Under attack but not yet killed"** — the hypothesis is being tested; verdict pending. Different from `active`, different from `killed`.
- **"Key assumption falsified"** — the hypothesis hasn't been directly killed but its load-bearing assumption is now refuted. Different from `under_attack`.
- **"Refined into a new version"** — the original H-1 became H-1.b after evidence forced a revision. Audit trail must distinguish from "killed" and "started fresh".
- **"Parked for later"** — the hypothesis is plausible but deferred. Different from active (no investigation in progress) and different from killed (still viable).
- **"Validated"** — survived rigorous testing; promoted to terminal-survivor. Different from "still active" (validated has higher epistemic status).

A 9-state FSM catches all five. Every distinction matters at Phase 5 adjudication, Phase 7 audit, and Phase 9 HANDBACK.

---

## The 9 states

| State | Symbol | Description | Editable? | Deletable? | Terminal? |
|-------|--------|-------------|-----------|------------|-----------|
| `draft` | ○ | Initial formulation, freely editable | ✓ | ✓ | ✗ |
| `proposed` | ◐ | Submitted for evaluation; awaiting adoption | ✓ | ✗ | ✗ |
| `active` | ● | Under active investigation | ✗ (only via refine) | ✗ | ✗ |
| `under_attack` | ⚔ | Facing serious challenges; verdict pending | ✗ | ✗ | ✗ |
| `assumption_undermined` | ⚠ | Key assumption falsified; hypothesis logic compromised | ✗ | ✗ | ✗ |
| `refined` | ↻ | Evolved based on feedback; new version created | ✗ | ✗ | ✗ |
| `dormant` | ◇ | Parked for later; investigation paused | ✗ | ✗ | ✗ |
| `killed` | ✗ | Definitively falsified | ✗ | ✗ | **✓** |
| `validated` | ✓ | Survived rigorous testing | ✗ | ✗ | **✓** |

**Terminal states** (`killed`, `validated`) cannot transition further. Once reached, the H is locked.

---

## State-name mapping (bead `state` field ↔ FSM state)

The canonical FSM has 9 conceptual states. The compact bead-level vocabulary used in `BEADS-SCHEMA.md`, `SKILL.md § Beads Schema`, `audit-bead-invariants.sh`, `DRIFT-RUBRIC.md`, and `OPERATORS.md` uses 6 short names. Both are correct; one is granular, the other is compact. **Scripts and beads use the compact 6 names; methodology discussion uses the granular 9.**

| Bead `state:` (compact, what `H-NNN` records hold) | FSM state(s) (granular, what this doc enumerates) | Notes |
|----------------------------------------------------|---------------------------------------------------|-------|
| *(no bead yet)* | `draft` | Pre-bead form; the proposer is still wording. `br create` transitions out of `draft`. |
| `proposed` | `proposed` | One-to-one. |
| `active` | `active` ∪ `under_attack` ∪ `assumption_undermined` | Compact `active` covers all three "currently being investigated" sub-states. The FSM sub-state distinction matters for adjudicator scoring + audit; the bead description SHOULD carry an `attack_level:` or `compromise:` annotation when in the sub-states. |
| `confirmed` | `validated` | Terminal. The compact name is `confirmed` for parity with brenner_bot's CLI; the FSM concept is `validated` (survived rigorous testing). |
| `refuted` | `killed` | Terminal. The compact name is `refuted` (used by audit-bead-invariants.sh:`every_refuted_has_refuted_by`); the FSM concept is `killed` (definitively falsified). Treat them as synonyms; if you see one in a script and the other in prose, that's intentional. |
| `superseded` | `refined` (this H's terminal mark) + new H in `draft`/`proposed` | The original H is `superseded` and carries `parent: <replacement H>` so scripts can follow the machine-checkable pointer forward. The refined replacement is a new H bead, usually with `origin: refinement`. The FSM models this as a `refined` transition that *spawns* a new draft. |
| `deferred` | `dormant` | One-to-one rename. The compact name follows brenner_bot's CLI; the FSM uses `dormant` for the same concept. |

**When to use which vocabulary:**

- **In bead descriptions, scripts, audit invariants, marching-orders that grep `state: refuted`** → use the compact 6 (`proposed`, `active`, `confirmed`, `refuted`, `superseded`, `deferred`).
- **In methodology prose, debate adjudication, FSM transitions, drift-check rubrics that distinguish "challenged but not killed" from "killed"** → use the granular 9.

**Why we don't unify.** The compact vocabulary mirrors brenner_bot's CLI surface and is what the existing `audit-bead-invariants.sh` greps for. Renaming `refuted`→`killed` in beads would require updating ~30 files plus all in-flight session beads. The 9-state FSM is the *conceptual* enrichment that explains the compact vocabulary's transitions; the mapping above is the bridge.

---

## Valid transitions

```
                                    ┌──→ killed (terminal)
                                    │
draft ─→ proposed ─→ active ─→ under_attack ─→ assumption_undermined ─→ killed
                       │            │
                       │            ├──→ refined ───→ (new H, draft state)
                       │            │
                       │            └──→ dormant ───→ active (reactivation)
                       │
                       └─────→ validated (terminal)
```

### Edge list (machine-checkable)

| From | To | Event |
|------|-----|-------|
| `draft` | `proposed` | `submit` |
| `proposed` | `active` | `activate` |
| `active` | `under_attack` | `challenge` |
| `active` | `assumption_undermined` | `undermine_assumption` |
| `under_attack` | `assumption_undermined` | `undermine_assumption` |
| `active` | `refined` | `refine` |
| `under_attack` | `refined` | `refine` |
| `active` | `dormant` | `park` |
| `dormant` | `active` | `reactivate` |
| `under_attack` | `killed` | `kill` |
| `assumption_undermined` | `killed` | `kill` |
| `active` | `validated` | `validate` |

Any transition NOT in this table is **illegal**. The FSM rejects it.

---

## Transition events

Events are *triggers*, not direct state changes. Each event:

1. Validates source state ∈ allowed-from
2. Computes target state per edge list
3. Runs side effects (per next section)
4. Updates the bead's `state` field
5. Logs transition to session-logs/state-transitions.jsonl

```typescript
// Pseudocode (TypeScript-style)
function transitionHypothesis(h: Hypothesis, event: TransitionEvent): TransitionResult {
  const allowed = getAvailableTransitions(h.state);
  if (!allowed.includes(event)) {
    return { success: false, reason: `event ${event} not valid from state ${h.state}` };
  }
  const newState = computeTargetState(h.state, event);
  runSideEffects(h, event, newState);
  h.state = newState;
  logTransition(h, event, newState);
  return { success: true, newState };
}
```

In the current brennerbot `br` integration, transitions go through `br update` plus manual logging to `session-logs/state-transitions.jsonl`. `scripts/transition-h.sh H-001 --event=challenge` is the planned validator-backed helper.

---

## Side effects

Certain transitions trigger automatic side effects:

| Transition | Side effects |
|------------|--------------|
| `submit` (draft → proposed) | Lock H description; assign canonical ID; mail-broadcast to roster |
| `activate` (proposed → active) | Spawn investigator pane (per MO-04a); open per-H mail thread |
| `challenge` (active → under_attack) | Spawn devil's-advocate (per MO-04b); raise H to top of debate queue |
| `undermine_assumption` (active \| under_attack → assumption_undermined) | Mark depending tests `T-NNN` blocked; notify investigator |
| `refine` (active \| under_attack → refined) | **Create new H bead** (next sequential ID, state=draft); link as `refined-from` |
| `park` (active → dormant) | Release investigator pane; archive open mail threads |
| `reactivate` (dormant → active) | Re-spawn investigator; re-open mail threads |
| `kill` (under_attack \| assumption_undermined → killed) | Record `kill_reason` field; update arena leaderboard if applicable; release all panes |
| `validate` (active → validated) | Mark as champion in arena if applicable; trigger Phase 8 validation gate |

**Critical:** the `refine` event creates a NEW hypothesis, doesn't mutate the existing one. The original transitions to `refined` (terminal-ish from a "still being investigated" perspective); the new H starts fresh in `draft`. The link is via `refined-from: H-NNN` field.

This preserves the audit trail: you can always reconstruct the lineage `H-001 → H-001.b → H-001.c → H-001.c (validated)`.

---

## State invariants

For every H bead, the linter (per ARTIFACT-LINTER-RULES.md) checks:

- `state` ∈ {draft, proposed, active, under_attack, assumption_undermined, refined, dormant, killed, validated}
- If `state == killed` → `kill_reason` field non-empty
- If `state == validated` → `validating_tests` field lists ≥1 T-NNN
- If `state == refined` → `refined_into` field cites the new H ID
- If `state == assumption_undermined` → `undermined_by_assumption` cites A-NNN
- Terminal states (`killed`, `validated`) cannot have subsequent transitions logged

Violations generate audit-finding beads at Phase 7.

---

## Per-state operator behavior

The operator's behavior depends on which state each H is in:

### draft / proposed states (Phase 1-3)

- Don't dispatch investigators yet
- Falsifier-grade is allowed to fail (still being shaped)
- Refinement encouraged before activation

### active state (Phase 3-5)

- Dispatch investigator (MO-04a) per H
- Per-H evidence pack required
- Activate Devil's-Advocate when adversarial round begins

### under_attack state (Phase 5)

- Active debate; adjudicator is gathering evidence
- New evidence is high-priority
- Investigator + Devil's-Advocate both engaged

### assumption_undermined state (Phase 5-7)

- The hypothesis itself wasn't refuted, but its A-NNN was
- Decision: rebuild on different assumption (refine) OR kill
- Per Phase 7 audit: assumption_undermined H without resolution = audit-finding severity:high

### refined state (terminal-ish in original lineage)

- The original H is *no longer being investigated* — its successor is
- Audit trail: HANDBACK should mention "originally H-001 refined to H-001.b based on EV-014"

### dormant state

- Investigation paused; not killed
- Phase 8 freeze allows dormant H to remain (with note in HANDBACK § Open Questions)
- Reactivation requires explicit operator decision

### killed / validated states (terminal)

- Locked; no further changes
- HANDBACK § Verdict must report final state per H

---

## Detection: detecting illegal transitions

When it exists, the transition validator (`scripts/transition-h.sh`) rejects illegal transitions. Today, agents can still mutate `H-NNN.state` directly via `br update`, so Phase 7 must audit the transition log manually.

Per Phase 7 audit, run the current invariant checks and manually inspect state transitions:

```bash
scripts/audit-bead-invariants.sh --check=phase7_exit
```

- Scan session-logs/state-transitions.jsonl
- For each H, verify the sequence of `state` values follows the FSM edge list
- Flag any H whose `state` history violates the FSM

Common violations:

1. **Direct kill from `active`** (skipping `under_attack`) — bypasses adversarial review (per F-501)
2. **Direct validate from `under_attack`** (skipping back to `active`) — premature validation
3. **Reactivate from `killed`** — illegal; killed is terminal
4. **State change with no transition event logged** — `br update` was used instead of `transition-h.sh`

All flagged as audit-finding beads.

---

## The `under_attack` and `assumption_undermined` patterns

These two states are the *most under-used* in practice — operators tend to skip them, going `active → killed` directly.

### `under_attack` is mandatory before `kill`

The FSM enforces: you cannot kill from `active`. You must go through `under_attack` first. Why?

- Forces explicit adversarial evidence (Devil's-Advocate produces it)
- Produces an *audit trail* showing the hypothesis was attacked, not just abandoned
- Allows the original Investigator to defend (per BRENNER-GAN-MECHANICS.md)
- Distinguishes "we found evidence against H1" from "we got bored of H1"

If the FSM allowed `active → killed` directly, `kill_rate` would be cheap and meaningless.

### `assumption_undermined` is its own state

Why not just `under_attack`? Because the failure mode is *different*:

- `under_attack`: the H itself is being directly contested
- `assumption_undermined`: the H is fine *given its assumptions*, but those assumptions broke

The decision tree is different:
- `under_attack` → kill or refine the H itself
- `assumption_undermined` → rebuild on different assumption OR accept H is unrescuable on this foundation

Not surfacing this distinction → operators try to `refine` an `assumption_undermined` H without touching the assumption (silently broken).

---

## Refined-as-versioning

The `refine` event creates a new H. The lineage is:

```
H-001 (state: refined, refined_into: H-001.b)
  └─→ H-001.b (state: draft, refined_from: H-001)
       └─→ H-001.c (state: active, refined_from: H-001.b)
```

Each refinement is its own bead with its own state machine. The original is *not deleted* — it's preserved with state `refined`, and the chain is auditable via `refined_into` / `refined_from` fields.

Why? Because refinement is not "we changed our minds about H-001 — the state is now X." It's "we learned something that made us articulate a *different but related* hypothesis." Cross-session reconciliation (per RECONCILIATION-OF-PRIOR-SESSIONS.md) needs both the original and the refined version to track epistemic evolution.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Using only `active` and `refuted` states | Loses 7 of 9 lifecycle distinctions |
| Direct `active → killed` transition | Bypasses adversarial review (F-501) |
| `refine` mutates the H in place | Loses lineage; audit trail broken |
| `kill_reason` left empty | Per state invariant: kill_reason mandatory; lint will catch |
| Reactivating a `killed` H | Terminal; create a new draft H instead |
| Treating `dormant` as semantically equivalent to `killed` | Dormant is recoverable; killed is not |
| Skipping `assumption_undermined` and going to `killed` | Loses the "the assumption was the problem" signal |
| Multiple H's with same lineage missing `refined_from` | Lineage chain breaks |
| `validated` without a `validating_tests` list | Missing audit trail for what survived |

---

## Composition with brennerbot phases

| Phase | FSM activity |
|-------|--------------|
| 1 framing | No H exist yet |
| 3 hypothesis generation | H beads created in `draft` → `proposed` → `active` |
| 4 investigation | Active H accumulate EV; some transition to `under_attack` |
| 5 cross-examination | Under-attack H either kill, refine, or survive (back to active) |
| 6 distillation | All H states feed into per-family distillations |
| 7 audit | State invariants checked; illegal transitions flagged |
| 8 freeze | Terminal states (killed/validated) locked; dormant H listed |
| 9 handback | HANDBACK § Verdict reports final state per H |

---

## Cross-references

- [BEADS-SCHEMA.md](BEADS-SCHEMA.md) — H-NNN bead schema; `state` field type
- [ARTIFACT-LINTER-RULES.md](ARTIFACT-LINTER-RULES.md) — state-invariant lint rules
- [BRENNER-GAN-MECHANICS.md](BRENNER-GAN-MECHANICS.md) — under_attack engagement protocol
- [TRIBUNAL-AND-OBJECTION-REGISTER.md](TRIBUNAL-AND-OBJECTION-REGISTER.md) — adversarial review enforcement
- [CONFIDENCE-SCORING.md](CONFIDENCE-SCORING.md) — confidence value depends on state
- [PHASES.md](PHASES.md) — per-phase state activity
- `scripts/transition-h.sh` — the validator (Tier-7 future addition; until then, transitions go through `br update` + manual logging to `session-logs/state-transitions.jsonl`)
- [scripts/audit-bead-invariants.sh](../scripts/audit-bead-invariants.sh) — state-transition checker
- /dp/brenner_bot/README.md § Hypothesis Lifecycle State Machine — original source
- /dp/brenner_bot/brenner.ts § hypothesis-lifecycle module — implementation
