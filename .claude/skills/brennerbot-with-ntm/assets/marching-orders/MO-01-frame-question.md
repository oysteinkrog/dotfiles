# MO-01-frame-question.md — Brenner Step-0 Framing

**Phase:** 1
**Operators activated:** ◊ Paradox-Hunt, ⌂ Materialize, ✂ Exclusion-Test
**Parameters:** `<RAW_USER_ASK>`, `<TARGET>` (path or "n/a"), `<MODE>` (one of OPERATING-MODES.md modes), `<SESSION_ID>`, `<WORKSPACE_PATH>`

---

You are framing a research question for a Brenner-style multi-agent research session. The user's raw ask is below. Your job is to compile it into a question of record per the template at `references/QUESTION-OF-RECORD-TEMPLATE.md`.

**Raw user ask:**
```
<RAW_USER_ASK>
```

**Target:** `<TARGET>`
**Mode:** `<MODE>`

---

**Step 1 — Read the template.**

Read `references/QUESTION-OF-RECORD-TEMPLATE.md` end-to-end. Note the required sections (Question, Paradox, Falsifier, Scope, Out of Scope, Mode, Provenance, Stakes, Initial paradox bead).

**Step 2 — Apply ◊ Paradox-Hunt.**

Identify ≥2 well-attested facts in tension within the raw ask. Phrase the tension as: "If A is true, then B should be impossible. But B is observed. So either A is wrong, B is misobserved, or there's a hidden mechanism."

If you cannot find a paradox, the question is too vague — return to the user with: "I cannot identify the paradox that motivates this question. Could you describe what specific tension or open contradiction you want this session to resolve?"

**Step 3 — Apply ✂ Exclusion-Test.**

Write the Falsifier section: what specific observation O, if seen, would prove (a) the question is malformed OR (b) is already answered? The falsifier must be:
- Observable (not "if math broke")
- Decidable (not "if it became philosophically wrong")
- Reachable in the session's wall-time budget

If you cannot write a decidable falsifier, the question is not yet a research question. Reject and return to the user.

**Step 4 — Apply ⌂ Materialize.**

Write the Scope and Out of Scope sections. Scope must be specific (≤8 bullets); Out of Scope is equally important — it prevents Phase 4 drift. If you cannot articulate Out of Scope, the question is too broad.

**Step 5 — Write the rest.**

Fill Mode, Provenance, Stakes (what action depends on the answer), and Initial paradox bead.

**Step 6 — Self-test.**

Apply [QUESTION-OF-RECORD-TEMPLATE.md § Self-test for the question of record](../../references/QUESTION-OF-RECORD-TEMPLATE.md):

1. Could a hostile reader misread "Out of Scope"? If yes, sharpen.
2. Is the falsifier observable in <1 hour by an investigator? If no, make it concrete.
3. Could two reasonable people disagree on what "Scope" means? If yes, sharpen.
4. Does the paradox actually motivate the question, or is it post-hoc?
5. What action changes if the answer is X vs Y vs Z? If no action changes for some answer, the question may be incomplete.

**Step 7 — Write to disk.**

Write the question of record to `<WORKSPACE_PATH>/intake/question_of_record.md`.

**Step 8 — File the seed beads.**

```bash
q_ref="Q-001"
q_id="$(br create "$q_ref: <one-line question>" \
  --type=question --labels=q-of-record --priority=0 \
  --slug="$q_ref" --external-ref="$q_ref" --silent \
  --description="$(cat <<'EOF'
question: <full question>
falsifier: <full falsifier>
scope: <bullet list>
out_of_scope: <bullet list>
mode: <MODE>
provenance: <where from>
session: <SESSION_ID>
EOF
)")"

h_ref="H-000"
h_id="$(br create "$h_ref: <paradox-as-hypothesis>" \
  --type=task --labels=hypothesis --priority=2 \
  --slug="$h_ref" --external-ref="$h_ref" --silent \
  --description="$(cat <<'EOF'
claim: <restate the paradox as a claim>
mechanism: <the hidden mechanism the paradox suggests>
falsifier: <what would prove the paradox is illusory>
expected_evidence: <what would confirm the hidden mechanism>
category: phenomenological
origin: anomaly_spawned
confidence: speculative
parent: Q-001
session: <SESSION_ID>
EOF
)")"

printf 'Created %s as br id %s\n' "$q_ref" "$q_id"
printf 'Created %s as br id %s\n' "$h_ref" "$h_id"
```

**Step 9 — Output.**

Reply to the operator with:

1. The path to the written `question_of_record.md`
2. The Q-001 and H-000 bead IDs
3. A 3-sentence summary of the paradox + falsifier
4. A list of the helper skills you'd recommend invoking next (cass-mining, codebase-archaeology, etc.)

Do NOT propose hypotheses (that's Phase 3). Do NOT begin investigation. Phase 1 is framing only.

---

**Ship-or-Surface SLA:** within 60 minutes, deliver the question of record OR surface a specific blocker (e.g., "user's ask is too vague; need clarification on X").
