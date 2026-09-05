# MO-cross-domain-import.md — Import a Pattern from an Unrelated Field

**Phase:** 3 (proposing) or 4 (investigation rescue)
**Operators activated:** ⊕ Cross-Domain (subsumed under ⊙ Productive-Ignorance), 𝓛 Recode
**Parameters:** `<PANE_N>`, `<SOURCE_DOMAIN>` (the unrelated field), `<TARGET_QUESTION>` (the current research question), `<SESSION_ID>`

---

Per Brenner's `⊕ Cross-Domain` move (Opus 4.5 distillation; subsumed under ⊙ in our 15-operator algebra) — many breakthroughs come from importing patterns from adjacent fields. Negative staining (Brenner §86) was imported from spirochete medical staining. C. elegans (§145) was imported from "what fits in an EM window" — a constraint from microscopy, not biology.

When stuck in Phase 3 (no diverse-enough hypotheses) or Phase 4 (investigation isn't surfacing decisive evidence), apply this MO.

---

**Step 1 — Identify a candidate source domain.**

Pick `<SOURCE_DOMAIN>` based on:

- **Structural similarity** — the source domain has a problem with similar shape (constraints, dimensions, decision space)
- **Maturity** — the source domain has had enough time for solutions to settle
- **Cross-domain distance** — the further from `<TARGET_QUESTION>`'s native field, the more likely it brings fresh patterns

Heuristic: domains good for cross-import for typical brennerbot questions:

- Coding theory / error correction (for distributed systems questions)
- Linguistics / formal grammar (for semantic / interpretation questions)
- Ecology / evolutionary biology (for system stability / equilibrium questions)
- Statistical mechanics / thermodynamics (for scale / regime / phase-transition questions)
- Game theory / mechanism design (for incentive / behavior / coordination questions)
- Music theory / signal processing (for periodic / frequency-domain questions)
- Architecture / urban planning (for layered system design questions)

The pane `<PANE_N>`'s job: pick a *specific* source domain (not "physics" — too broad — but "phase transitions in 2D Ising models").

**Step 2 — State the source pattern as a generic.**

Strip the source domain's specific terms. Express the pattern as a generic shape:

> "In `<SOURCE_DOMAIN>`, when problem of shape <X> arises, the canonical solution is <Y>. The solution works because <invariant Z>."

Example:
- Source: error-correcting codes (Reed-Solomon)
- Generic shape: "Need to recover N original symbols from N+K transmitted symbols, K of which can be corrupted, without knowing which K."
- Solution: redundant encoding with algebraic structure permitting decode-from-any-N.
- Invariant: K-independence guaranteed by Reed-Solomon's polynomial-evaluation structure.

**Step 3 — Project the generic onto `<TARGET_QUESTION>`.**

Substitute current-domain terms into the generic. Does the projection produce a hypothesis with a falsifier?

Example projection (RS coding → distributed consensus):
> "In a distributed consensus problem, when we need agreement among N nodes from which K can be Byzantine, the canonical solution may be redundant message-passing with algebraic structure. Falsifier: if the message overhead exceeds the state's information content by ≥K times, the projection is invalid."

If the projection yields a *new H bead with a real falsifier*, file it.

**Step 4 — Apply 𝓛 Recode if needed.**

If the projection looks superficially right but the predictions don't separate from existing Hs, apply 𝓛: re-encode the target question in the source domain's coordinate system. New encoding, new disagreements visible.

**Step 5 — File the imported H bead.**

```bash
h_ref="H-NNN"  # public ref; replace NNN before running
h_id="$(br create "$h_ref: <one-line claim, projected from <SOURCE_DOMAIN>>" \
  --type=task --labels=hypothesis --priority=2 \
  --slug="$h_ref" --external-ref="$h_ref" --silent \
  --description="$(cat <<'EOF'
claim: <projected claim>
mechanism: <production rule from source domain, projected>
falsifier: <what observation, in target-domain terms, kills this>
expected_evidence: <what observation, in target-domain terms, supports this>
category: mechanistic | boundary
origin: third_alternative   # cross-domain imports often serve as the third alternative
confidence: speculative
parent: H-<the question's primary H if any>
session: <SESSION_ID>
cross_domain_source: <SOURCE_DOMAIN>

## Detail
Generic pattern (in source-domain terms): <pattern>
Projection (in target-domain terms): <projection>
Why this projection might fail: <known mismatch points>

## Coordinates (per 𝓛 Recode)
This claim disagrees with rivals when expressed in: <coordinate system>.
EOF
)")"
printf 'Created %s as br id %s\n' "$h_ref" "$h_id"
```

**Step 6 — Post to the main session thread.**

```
Subject: [<SESSION_ID>] Cross-domain import: <SOURCE_DOMAIN> → <H-NNN>

Imported pattern from <SOURCE_DOMAIN>:
  Generic shape: <one sentence>
  Solution: <one sentence>
  Invariant: <one sentence>

Projection to current question:
  H-NNN filed.

Operators applied: ⊕ Cross-Domain, 𝓛 Recode.

This may serve as the third alternative if the slate currently lacks one.
```

---

**Anti-patterns:**

- ✗ Pick `<SOURCE_DOMAIN>` so close to target it's not really cross-domain ("we imported from databases for a database question — same field"). Whole point is *adjacent* field.
- ✗ Pick `<SOURCE_DOMAIN>` so far it doesn't actually have structurally similar problems. "We imported from poetry to solve a memory-allocation question" — uninterpretable.
- ✗ Project without a falsifier. The projection must yield a new H bead with all required fields, including falsifier.
- ✗ Use cross-domain import as a substitute for thinking. It's a generation tool, not a verdict.
- ✗ File the import as a confirmed H. It's `confidence:speculative` — needs the same Phase 4 investigation as any H.

**Ship-or-Surface SLA:** within 30 min, file the H bead OR explicitly state the import didn't yield a falsifiable claim (which is itself a finding — that the source-target mapping doesn't work for this question).
