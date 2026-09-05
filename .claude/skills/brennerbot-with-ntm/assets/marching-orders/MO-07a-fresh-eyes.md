# MO-07a-fresh-eyes.md — Verbatim Trio of Fresh-Eyes Prompts

**Phase:** 7
**Operators activated:** ⊞ Scale-Check (re-verify), ∿ Dephase, ✂ Exclusion-Test (re-verify)
**Parameters:** `<PANE_N>`, `<SESSION_ID>`

---

You are pane `<PANE_N>` in the Fresh-Eyes Audit role. Your job: run the three calibrated review prompts below, in order, and file `audit-finding` beads for everything you find. Each pane runs **all three** prompts; this is one trio-round.

If you've been a Synthesizer or Investigator earlier in this session, the operator should have killed and respawned you on a different model family for this audit. If not, flag that and proceed cautiously (your audit will be biased toward the work you did).

---

## Prompt 1 (verbatim — calibrated; same as `/documentation-website-for-software-project` and `/saas-billing-patterns-for-stripe-and-paypal`)

> Carefully read over all of the artifact and evidence packs you and the other panes just produced with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, missing falsifiers, omitted hypotheses, unsupported leaps, etc. Carefully fix anything you uncover.

**For this skill specifically:** the artifacts to read are:

- `intake/question_of_record.md`
- `evidence/packs/EV-pack-*.md` (all of them)
- `distillations/by_*.md`
- `distillations/meta_synthesis.md`
- `distillations/disagreement_register.md`

**File findings as `audit-finding` beads with `prompt_used: 1`. Cite specific files + bead ids. Vibes-only findings will be rejected.**

---

## Prompt 2 (verbatim — calibrated)

> Sort of randomly explore the evidence packs and distillations in this workspace, choosing files to deeply investigate and trace their citations through the related evidence and corpus excerpts. Once you understand the purpose of each piece in the larger context of the question of record, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes.

**For this skill specifically:**

- Pick 2–3 evidence packs at random
- For each, follow each `EV-NNN`'s `source` and verify the verbatim excerpt actually says what's claimed
- Check assumption beads' `calculation:` blocks — does the math actually hold?
- Trace each `H-*.refuted_by` to verify the EV cited actually fires the falsifier

**File findings as `audit-finding` beads with `prompt_used: 2`. Specific citations mandatory.**

---

## Prompt 3 (verbatim — calibrated)

> Turn your attention to reviewing the distillations and evidence packs written by your fellow panes and check for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep.

**For this skill specifically:**

- Identify which panes wrote which artifacts (`git blame`, bead `imported_by:`)
- For each artifact, check: does it conform to its template (per `references/QUESTION-OF-RECORD-TEMPLATE.md` / `MO-04c-evidence-pack.md` etc)?
- Check for: missing falsifiers (✂), missing scale-physics calculations (⊞), distillations averaged without disagreements (D-001 in DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md), confirmation-only evidence (F-403)

**File findings as `audit-finding` beads with `prompt_used: 3`. Root-cause diagnosis required.**

---

## Step-by-step procedure

**Step 1.** Run Prompt 1 for ~20 minutes. File all findings.

**Step 2.** Run Prompt 2 for ~20 minutes. File all findings.

**Step 3.** Run Prompt 3 for ~20 minutes. File all findings.

**Step 4 — Apply ⊞ Scale-Check explicitly.**

For every `assumption.type:scale_physics`:

```bash
br list --label=assumption --json | jq '.issues[]? | select((.description // "") | contains("type: scale_physics"))'
```

For each, verify the `calculation:` block is correct. File `audit-finding` if any are wrong.

**Step 5 — Apply ∿ Dephase explicitly.**

Read `distillations/meta_synthesis.md` and ask: "Is the surviving best-explanation H what a domain expert would name first?" If yes, ask: "Did our session genuinely test alternatives, or did we just reproduce the consensus prior?"

If reproduced-consensus, file `audit-finding`:

```yaml
severity: medium
target_artifact: distillations/meta_synthesis.md
recommendation: |
  The surviving best-explanation H matches domain consensus, but Phase 4 only tested 2/3 alternatives meaningfully (the third-alternative H-NNN was prematurely deferred).
  Recommend Phase 4 reopen targeting H-NNN.
prompt_used: 3
```

**Step 6 — File audit findings.**

```bash
af_ref="AF-NNN"  # public ref; replace NNN before running
priority="2"  # critical=0, high=1, medium=2, low=3
af_id="$(br create "$af_ref: <short finding>" \
  --type=task --labels=audit-finding --priority="$priority" \
  --slug="$af_ref" --external-ref="$af_ref" --silent \
  --description="$(cat <<'EOF'
severity: critical | high | medium | low
target_artifact: <file path or bead id>
recommendation: <what to fix>
by_pane: <PANE_N>
prompt_used: 1 | 2 | 3
session: <SESSION_ID>

## Detail
<longer explanation>
EOF
)")"
printf 'Created %s as br id %s\n' "$af_ref" "$af_id"
```

**Step 7 — Post to per-pane audit thread.**

```
Subject: [<SESSION_ID>-AUDIT-p<PANE_N>] Trio-round complete
Body:
  Findings filed:
  - [CRITICAL] AF-001: <summary> (target: ...)
  - [HIGH] AF-002: <summary>
  - [MEDIUM] AF-003: <summary>
  - [LOW] AF-004: <summary>
  Operators applied: ⊞, ∿, ✂ (re-verify)
  Total findings this round: <N>
  Of which: <critical/high/medium/low counts>
```

---

**Anti-patterns to avoid:**

- ✗ Posting "LGTM" or "no findings" without specific citations (per F-701). If you genuinely have no findings, list which 5 specific things you checked and conformed.
- ✗ Reopening Phase 4 questions on rhetoric (per AP-O07). If a finding warrants reopen, the recommendation is to reopen — not to investigate inline.
- ✗ Critical findings without falsifier-grade evidence. "I don't agree" is not critical; "the calculation says X but the assumption claims Y" is critical.
- ✗ Skipping Prompt 2 because Prompts 1 and 3 already covered it. The trio is calibrated — different prompts surface different findings; running all three is the discipline.

**Ship-or-Surface SLA:** within 60 minutes per trio-round, file findings + post summary.
