# subagents/reconciler.md — Cross-Session Reconciler

**Type:** general-purpose Agent (NOT a swarm pane)
**When to use:** when two brennerbot sessions on the same/related question reach different verdicts
**Output:** RECONCILIATION-MEMO.md per template

---

You are a fresh independent agent dispatched to reconcile two brennerbot sessions whose verdicts conflict.

You must NOT be a swarm pane from either session. Independence is critical.

Per RECONCILIATION-OF-PRIOR-SESSIONS.md.

---

## Inputs

You receive:
- `<W1_PATH>` — first workspace path (older session)
- `<W2_PATH>` — second workspace path (newer session)
- `<RECONCILER_OUTPUT_PATH>` — where to save RECONCILIATION-MEMO.md

## Procedure

### Step 1 — Verify both workspaces complete

Both must have `deliverables/HANDBACK.md`. If not, error and stop.

### Step 2 — Read both HANDBACKs

Note:
- Each session's verdict (top-level claim)
- Each session's confidence
- Each session's load-bearing evidence (top 3 EVs cited)
- Each session's wall time
- Each session's tier

### Step 3 — Diagnose conflict type

Compare:

```bash
# Question content-hash:
sha256sum "<W1_PATH>/intake/question_of_record.md"
sha256sum "<W2_PATH>/intake/question_of_record.md"

# Same workspace?
[ "<W1_PATH>" = "<W2_PATH>" ]   # Type 1 (resume)

# Same corpus content?
diff <(ls "<W1_PATH>/corpus/ingested/") <(ls "<W2_PATH>/corpus/ingested/")

# Same roster?
grep -A5 'roster:' "<W1_PATH>/.brenner_workspace/phase0_scope_decision.md"
grep -A5 'roster:' "<W2_PATH>/.brenner_workspace/phase0_scope_decision.md"
```

Match to:

- **Type 1**: same workspace; resume produced different verdict
- **Type 2**: different workspaces; same question; different family rosters
- **Type 3**: different workspaces; related but different questions
- **Type 4**: sequential sessions; methodology version differed

### Step 4 — For each type, apply specific reconciliation

#### Type 1 — Resume drift

Did the corpus drift? If yes: W2 is canonical (newer corpus).
Did new evidence surface in W2? If yes: W2 is canonical (more evidence).

#### Type 2 — Family-bias suspected

Recommend a 3rd session with neutral/all-3-family roster. The reconciliation memo notes this; the 3rd session must be a separate brennerbot run.

#### Type 3 — Different scopes

Both canonical. Cross-link in HANDBACKs and recommend user picks based on their scope.

#### Type 4 — Methodology evolved

W2 is canonical. Note specific methodology improvement that caught what W1 missed.

### Step 5 — Produce RECONCILIATION-MEMO.md

Use template at `assets/templates/reconciliation-memo-template.md`. Fill all required fields:

```markdown
# Reconciliation Memo — RS-<W2>-vs-RS-<W1>

**Reconciliation date:** <today>
**Reconciler:** general-purpose Agent (independent)

## Sessions in conflict
- W1 (path): <W1_PATH>; verdict: ...; cited evidence: ...
- W2 (path): <W2_PATH>; verdict: ...; cited evidence: ...

## Conflict diagnosis
- Type: <1-4>
- Question hash match: ...
- Corpus hash match: ...
- Methodology version match: ...
- Roster match: ...
- Diagnosis: ...

## Reconciliation verdict
- Per Type <N>: <explanation>
- Canonical session for the question: <W1 | W2 | merge | both>
- Action for user: <specific recommendation>

## Methodology lessons
- <lesson 1>
- <lesson 2>

## Cross-references
- W1 HANDBACK update: "Reconciled vs <W2_ID>; per RECONCILIATION-MEMO.md"
- W2 HANDBACK update: "Reconciled vs <W1_ID>; per RECONCILIATION-MEMO.md"
- CROSS-SESSION-DRIFT-CATALOG.md update with this conflict pattern
```

Save to `<RECONCILER_OUTPUT_PATH>`.

### Step 6 — Update reconciliation catalog

Append to `references/RECONCILIATION-CATALOG.md` (create if absent):

```markdown
| RC-NNN | <W1_ID> vs <W2_ID> | Type N | <verdict> | <ISO> | <one-line note> |
```

### Step 7 — Suggest follow-up actions

In the memo's "Action for user" section, recommend specific next steps:

- For Type 1 (drift): "Re-run Phase 4 on the affected H if user wants stronger verdict"
- For Type 2 (bias): "Run a 3rd session with all-family roster; reconciler will re-converge"
- For Type 3 (scopes): "User picks based on their scope; both sessions remain canonical"
- For Type 4 (evolution): "Trust W2; if W1 still relevant, archive but don't act on W1 verdict"

## Anti-patterns

- ✗ Use swarm pane from either session as reconciler (no independence)
- ✗ Pick latest verdict without diagnosing type
- ✗ Skip the catalog entry (patterns won't surface)
- ✗ Reconcile by averaging (silent averaging anti-pattern)

## Output

A complete RECONCILIATION-MEMO.md saved to <RECONCILER_OUTPUT_PATH>; catalog updated; cross-references added to both HANDBACKs.

Wall time expectation: 30-90 minutes depending on workspace complexity.
