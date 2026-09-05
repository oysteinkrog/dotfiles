# MO-06a-distill.md — Per-Model-Family Distillation

**Phase:** 6
**Operators activated:** ≡ Invariant-Extract, ⊘ Level-Split (across hypotheses)
**Parameters:** `<PANE_N>`, `<MODEL_FAMILY>` (cc | cod | gmi), `<SESSION_ID>`, `<WORKSPACE_PATH>`

---

You are pane `<PANE_N>` (model family `<MODEL_FAMILY>`) in the Synthesizer role. Your job: produce *your model family's* distillation of the session into `distillations/by_<MODEL_FAMILY>.md`.

**This must be your model family's distinct perspective.** Don't try to write what you think the operator wants or what cross-model consensus would look like — that's the Meta-synthesizer's job (Phase 6b). Your job is to give one independent view.

---

**Step 1 — Read everything.**

```bash
cat <WORKSPACE_PATH>/intake/question_of_record.md
br list --label=hypothesis --status=open --json | jq '.issues[]? | select((.description // "") | contains("state: confirmed") or contains("state: superseded"))'
br list --label=hypothesis --json | jq '.issues[]? | select((.description // "") | contains("state: refuted"))'
ls <WORKSPACE_PATH>/evidence/packs/
br list --label=debate --json | jq '.issues[]?'
br list --label=anomaly --json | jq '.issues[]?'
br list --label=audit-finding --json | jq '.issues[]?'   # if Phase 7 has run already
```

**Step 2 — Apply ≡ Invariant-Extract.**

Across all surviving hypotheses + verified evidence, find ≥3 invariants that hold regardless of which surviving H is "the answer." These are the kernel claims of your distillation.

**Step 3 — Apply ⊘ Level-Split across surviving Hs.**

For each surviving H, identify which level it speaks to (mechanistic / phenomenological / boundary / auxiliary). The distillation should organize claims by level, not by H-id.

**Step 4 — Write the distillation.**

Create `distillations/by_<MODEL_FAMILY>.md` with these sections (mandatory):

```markdown
# Distillation by <MODEL_FAMILY> — <SESSION_ID>

**Question of record:** <verbatim from question_of_record.md>
**Synthesizer pane:** <PANE_N> (model: <MODEL_FAMILY>)
**Session phase reached:** Phase 6 distillation
**Surviving hypotheses:** <count> confirmed, <count> superseded, <count> deferred

---

## Two-Axiom restatement (adapted to this question)

### Axiom 1: <restate Brenner's "Reality has a generative grammar" specific to this domain>
### Axiom 2: <restate "Understanding = reconstruction" specific to this domain>

---

## Invariants (the kernel — claims that hold regardless of which surviving H is "the answer")

### I-001: <invariant 1>
- Source EVs: EV-NNN, EV-NNN
- Operator that surfaces it: ≡ Invariant-Extract

### I-002: <invariant 2>
...

---

## Generative loop (adapted to this domain)

<your domain-specific rendering of the Brenner Generative Loop:
  ◊ paradox → ⊘ level-split → 𝓛 reduce → ⌂ materialize → ✂ exclude → ...

in this domain, what does each operator look like? cite specific EV examples>

---

## Operator algebra (which Brenner operators apply specifically here)

For each of the 15 operators, note:
- **Applied here?** yes/no
- **How** (specific to this domain)
- **Example from this session** (EV-NNN cite)

If an operator did NOT apply, say so explicitly with rationale (this is the cleanest way to surface methodological gaps).

---

## Required Failure Modes

When does this distillation NOT apply?
1. <case 1>
2. <case 2>
3. <case 3>

---

## One-page summary

<3-paragraph summary fitting in ≤80 lines that captures:
  - the question
  - the kernel invariants
  - the surviving best-explanation H
  - the open uncertainties>

---

## Bayesian substrate

For each surviving H, what's its posterior weight given the evidence? (informal — high/medium/low — not numerically computed)

| Surviving H | Posterior weight | Why |
|-------------|------------------|-----|
| H-NNN (state: confirmed) | high | survived debate D-NNN; ≥3 supporting EV from independent sources |
| H-NNN (state: confirmed) | medium | survived but only 2 supporting EV |
| H-NNN (state: superseded) | n/a | replaced by H-NNN |

---

## Disagreements I expect with peers

You haven't read the other model families' distillations yet. But anticipate:
- Where do you suspect cc / cod / gmi will differ from your reading?
- What's the one claim in your distillation you think is most likely to be challenged?

These will be reconciled in Phase 6b's `disagreement_register.md`.
```

**Step 5 — File a distillation bead.**

```bash
d_ref="D-<MODEL_FAMILY>-NNN"  # public ref; replace NNN before running
d_id="$(br create "$d_ref: Distillation by <MODEL_FAMILY>" \
  --type=task --labels=distillation --priority=2 \
  --slug="$d_ref" --external-ref="$d_ref" --silent \
  --description="$(cat <<'EOF'
by_model: <MODEL_FAMILY>
kernel_axioms:
  - <axiom 1 restatement>
  - <axiom 2 restatement>
generative_loop: <one-paragraph summary>
operator_algebra_adapted: <list>
session: <SESSION_ID>

## File
distillations/by_<MODEL_FAMILY>.md
EOF
)")"
printf 'Created %s as br id %s\n' "$d_ref" "$d_id"

br update "$d_id" --status=closed   # done
```

**Step 6 — Post to META-DISTILL thread.**

```
Subject: [<SESSION_ID>-META-DISTILL] <MODEL_FAMILY> distillation complete
Body:
  Distillation: distillations/by_<MODEL_FAMILY>.md
  Bead: D-<MODEL_FAMILY>-NNN
  Surviving Hs covered: <count>
  Anticipated disagreements with peers (per § Disagreements I expect):
  - <claim 1>
  - <claim 2>
```

---

**Anti-patterns to avoid:**

- ✗ Trying to write what you think the meta-synthesizer would write. That's Phase 6b's job. You give the *individual perspective*.
- ✗ Citing EVs without verbatim excerpts. The pack files have them; you can re-cite the verbatim quote.
- ✗ Writing >2 pages. The Polish Bar at Phase 6 is the kernel + the loop + the operator algebra + the summary — that fits in ≤2 pages.
- ✗ Hedging every claim ("perhaps", "it might be"). State your model family's view confidently; the Meta-synthesizer will reconcile against peers.
- ✗ Skipping the "Disagreements I expect with peers" section. That section is what makes Phase 6b's job possible.

**Ship-or-Surface SLA:** within 60 minutes, deliver `by_<MODEL_FAMILY>.md` OR surface a specific blocker.
