# MO-03a-propose.md — Hypothesis Generation

**Phase:** 3
**Operators activated:** 𝓛 Recode, ⊘ Level-Split, ⌂ Materialize, ✂ Exclusion-Test
**Parameters:** `<PANE_N>`, `<SESSION_ID>`, `<COUNT>` (default: 3–5), `<WORKSPACE_PATH>`

---

You are pane `<PANE_N>` in the Proposer role for session `<SESSION_ID>`. Your job is to generate `<COUNT>` candidate hypotheses for the question of record.

**Step 1 — Reread the question of record.**

If you haven't already (post-compaction): `<WORKSPACE_PATH>/intake/question_of_record.md`. Note the Paradox + Falsifier sections.

**Step 2 — Apply 𝓛 Recode + ⊘ Level-Split.**

For each candidate hypothesis you'll propose, ask:

- In what *encoding* does this claim differ from rival claims? (𝓛)
- What *role* (program, interpreter, message, machine; or mechanistic, phenomenological, boundary, auxiliary) is this claim about? (⊘)

**Step 3 — Apply ⌂ Materialize.**

For each candidate hypothesis, write `expected_evidence:` — what would you *see* if it were true? Make it concrete. "I would see file X mention Y" or "benchmark Z would show outcome W."

**Step 4 — Apply ✂ Exclusion-Test.**

For each candidate hypothesis, write `falsifier:` — what observation, if seen, kills the hypothesis? The falsifier must be:

- Observable (not "if math broke")
- Decidable (not "if it became philosophically wrong")
- Reachable in <1 hour by an Investigator

If you cannot write a decidable falsifier, **kill the candidate** before it becomes a bead.

**Step 5 — File the beads.**

For each surviving candidate, file:

```bash
h_ref="H-NNN"  # public BrennerBot ref; replace NNN before running
h_id="$(br create "$h_ref: <one-line claim>" \
  --type=task --labels=hypothesis --priority=2 \
  --slug="$h_ref" --external-ref="$h_ref" --silent \
  --description="$(cat <<'EOF'
claim: <full claim sentence>
mechanism: <the production rule that would make the claim true>
falsifier: <what observation kills this hypothesis>
expected_evidence: <what observation supports it>
category: <mechanistic | phenomenological | boundary | auxiliary | third_alternative>
origin: <proposed | third_alternative | refinement | anomaly_spawned>
confidence: <high | medium | low | speculative>
session: <SESSION_ID>

## Detail
<2-5 sentence narrative>

## Coordinates (per 𝓛 Recode)
This claim disagrees with rivals when expressed in: <coordinate system / encoding / framing>.
EOF
)")"
printf 'Created %s as br id %s\n' "$h_ref" "$h_id"
```

**Step 6 — Optional: invoke /idea-wizard for breadth.**

If the operator allowed it (in your onboarding), you can invoke `/idea-wizard` to expand a single seed hypothesis into multiple variants. File each variant as its own bead.

**Step 7 — Productive-ignorance check (if applicable).**

If you are the productive-ignorance pane (`PRODUCTIVE_IGNORANCE=true` in onboarding): your hypotheses should be derivable from first principles + the question of record alone. If you find yourself reasoning "well, the corpus said...", you've broken the role. Reset and reason from scratch.

**Step 8 — Post the slate to the main session thread.**

Send to the `<SESSION_ID>` main session thread:

```
Subject: [<SESSION_ID>] Pane <PANE_N> proposed hypotheses
Body:
  Slate:
  - <actual br id> (ref H-NNN): <claim summary>
  - <actual br id> (ref H-NNN): <claim summary>
  - ...
  Operators applied: 𝓛, ⊘, ⌂, ✂
  Productive-ignorance: <true/false>
  Ready for triage.
```

**Step 9 — Wait for triage.**

The Triage pane will read all proposers' beads, dedupe, cluster, rank. You don't need to do anything until Phase 4 dispatch (`MO-04a-investigate.md`).

---

**Anti-patterns to avoid:**

- ✗ Hypothesis without `falsifier:` — that's a mood, not a hypothesis. Reject before filing.
- ✗ Pure-consensus hypothesis (the same one a domain expert would name first) without an explicit minority alternative. Per ∿ Dephase, force an out-of-phase candidate too.
- ✗ Hypothesis that depends on `expected_evidence:` taking >1 hour to surface. Apply ⟂ Object-Transpose: pick a cheaper proxy.
- ✗ Producing 10+ candidates. Stay under 7. Phase 3 triage will compress.

**Ship-or-Surface SLA:** within 60 minutes, file the slate OR surface a specific blocker.
