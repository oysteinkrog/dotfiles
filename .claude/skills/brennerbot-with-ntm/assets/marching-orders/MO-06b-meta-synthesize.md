# MO-06b-meta-synthesize.md — Meta-Synthesis & Disagreement Register

**Phase:** 6
**Operators activated:** ≡ Invariant-Extract (across distillations), ⊘ Level-Split (across distillations)
**Parameters:** `<PANE_N>`, `<SESSION_ID>`, `<WORKSPACE_PATH>`

---

You are pane `<PANE_N>` in the Meta-Synthesizer role. Your model family MUST be different from the dominant per-family distillation (per ROSTER-PLANS.md role rotation rule). Your job: reconcile the per-family distillations into `distillations/meta_synthesis.md` AND populate `distillations/disagreement_register.md`.

**The disagreement register is the load-bearing artifact of Phase 6.** A meta-synthesis without disagreements registered is rejected.

---

**Step 1 — Read every per-family distillation.**

```bash
ls <WORKSPACE_PATH>/distillations/by_*.md
cat distillations/by_cc.md   # adjust per available families
cat distillations/by_cod.md
cat distillations/by_gmi.md
```

Read each one's "Disagreements I expect with peers" section — those are starting points.

**Step 2 — Identify points of agreement.**

For each *invariant*, *axiom restatement*, *generative-loop step*, and *Bayesian-posterior assignment*: do the per-family distillations agree?

If yes — the claim graduates to `meta_synthesis.md`.

**Step 3 — Identify points of disagreement.**

For every pair of distillations, find ≥1 point of disagreement. **This is mandatory.** Even if the disagreement is small ("cc emphasizes X; cod emphasizes Y"), it goes in the register.

If you genuinely cannot find a disagreement between a pair, you have a problem:

- The distillations are too thin (rerun MO-06a with more depth)
- OR you are pattern-matching to consensus (apply ∿ Dephase: are you in-phase with all three?)

**Step 4 — Write `meta_synthesis.md`.**

```markdown
# Meta-Synthesis — <SESSION_ID>

**Reconciled across model families:** cc, cod, gmi
**Meta-synthesizer:** <PANE_N> (model family different from dominant)

## Convergent kernel (where all distillations agree)

### Axioms (restated for this question's domain)
- <axiom 1>
- <axiom 2>

### Invariants (cited in ≥2 distillations)
- I-001: <invariant>
  - cc cites: by_cc.md § X
  - cod cites: by_cod.md § Y
  - gmi cites: by_gmi.md § Z

### Surviving best-explanation hypothesis (consensus pick if any)
<H-NNN, with rationale; or "no consensus — see disagreement_register.md D-NNN">

## Divergent claims (link to disagreement_register.md)

For each major divergence: short summary + link to disagreement entry.

## Open uncertainties (where all distillations agree they don't know)

- <uncertainty 1>
- <uncertainty 2>

## Operator coverage matrix (which operators were applied in this session)

| Operator | Applied? | Cited by | Notes |
|----------|----------|----------|-------|
| ◊ Paradox-Hunt | yes | all 3 | Phase 1 framing |
| ⊘ Level-Split | partial | cc, gmi | cod missed in Phase 3 triage |
| ... | ... | ... | ... |

(This section feeds Phase 10 drift-check.)
```

**Step 5 — Write `disagreement_register.md` (mandatory).**

```markdown
# Disagreement Register — <SESSION_ID>

This file records ≥1 disagreement per pair of per-family distillations. Phase 6 cannot exit without ≥(N choose 2) entries where N = number of model families.

## D-001: <one-line subject of disagreement>

**Distillations involved:** cc vs cod
**The point under dispute:** <one sentence>
**cc reading:** (cite by_cc.md § X) <cc's view>
**cod reading:** (cite by_cod.md § Y) <cod's view>
**Chosen synthesis:** <which view, or new synthesis>
**Reasoning for synthesis:** <one paragraph>
**Operator that surfaces this disagreement:** <which Brenner operator's lens makes the disagreement visible>

## D-002: ...

## D-003: ...

## D-004: ...

(Required entries: ≥(N choose 2). For N=3 model families, ≥3 entries.)

---

## Anti-pattern check (run before exit)

- [ ] Each pair of distillations has ≥1 disagreement entry: <yes/no>
- [ ] No entry is "trivial" (typo / wording-only). <yes/no — list violators>
- [ ] No entry is rationalized by averaging without choosing. <yes/no>
- [ ] Each entry cites specific sections of the per-family distillations. <yes/no>

If any answer is "no", the register is not yet complete.
```

**Step 6 — Run `disagreement-register-lint.sh`.**

```bash
./scripts/disagreement-register-lint.sh
```

This script verifies the register has the required entry count and all entries cite specific sections. If lint fails, fix and re-run.

**Step 7 — File the meta-distillation bead.**

```bash
d_ref="D-meta-001"  # public ref
d_id="$(br create "$d_ref: Meta-synthesis" \
  --type=task --labels=distillation --priority=2 \
  --slug="$d_ref" --external-ref="$d_ref" --silent \
  --description="$(cat <<'EOF'
by_model: meta
kernel_axioms:
  - <agreed axiom 1>
  - <agreed axiom 2>
generative_loop: <one-paragraph from meta_synthesis.md>
operator_algebra_adapted: <list>
disagreements_flagged:
  - D-001: <subject>
  - D-002: <subject>
  - D-003: <subject>
session: <SESSION_ID>

## Files
- distillations/meta_synthesis.md
- distillations/disagreement_register.md
EOF
)")"
printf 'Created %s as br id %s\n' "$d_ref" "$d_id"
br update "$d_id" --status=closed
```

**Step 8 — Post to META-DISTILL thread.**

```
Subject: [<SESSION_ID>-META-DISTILL] Meta-synthesis complete
Body:
  Meta: distillations/meta_synthesis.md
  Disagreements: distillations/disagreement_register.md (count: <N>)
  Lint: <pass | fail>
  Per-family distillations cited: by_cc.md, by_cod.md, by_gmi.md
```

---

**Anti-patterns to avoid:**

- ✗ Empty disagreement register (F-603). Mandatory artifact.
- ✗ Averaging "cc says X; cod says Y; meta says (X+Y)/2" — that's silent averaging (F-601). Choose, with reasoning.
- ✗ Distillations agreed on everything → suspicious. Check for consensus-seeking; check that per-family distillations are actually independent perspectives.
- ✗ Single model family dominates the meta (F-602). If 80%+ of meta is from cc, the meta-synthesizer is biased; rotate to a different family.
- ✗ Meta-synthesizer same family as a per-family synthesizer. Defeats triangulation.

**Ship-or-Surface SLA:** within 60 minutes, deliver both `meta_synthesis.md` AND `disagreement_register.md`.
