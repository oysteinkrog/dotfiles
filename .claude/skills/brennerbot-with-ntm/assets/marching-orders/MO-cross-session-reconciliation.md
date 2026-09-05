# MO-cross-session-reconciliation.md — Reconcile Multiple Sessions on Same Question

**Phase:** Phase 0 (pre-bootstrap) or Phase 10 (drift-check) for sessions that conflict with prior
**Operators activated:** ≡ Invariant-Extract, ⊘ Level-Split, 🔧 DIY (run reconciliation)
**Parameters:** `<W1_PATH>`, `<W2_PATH>` (workspaces in conflict), `<RECONCILER_PANE>`

---

Per RECONCILIATION-OF-PRIOR-SESSIONS.md. When two brennerbot sessions on the same (or related) question reach different verdicts, this MO reconciles.

The reconciler is a FRESH agent — NOT a swarm pane from either session.

---

**Step 1 — Verify both workspaces complete.**

Both `<W1_PATH>` and `<W2_PATH>` must have reached Phase 9 (HANDBACK) at minimum:

```bash
test -f "<W1_PATH>/deliverables/HANDBACK.md" || { echo "W1 incomplete"; exit 1; }
test -f "<W2_PATH>/deliverables/HANDBACK.md" || { echo "W2 incomplete"; exit 1; }
```

Don't reconcile mid-session.

**Step 2 — Establish conflict.**

Read both HANDBACKs. Verdicts differ how?

- Same conclusion, different confidence?
- Opposite conclusions?
- Same conclusion at different scope?
- Different sub-questions answered?

Document in `RECONCILIATION-MEMO.md § Conflict description`.

**Step 3 — Diagnose conflict type.**

Per RECONCILIATION-OF-PRIOR-SESSIONS.md:

- **Type 1**: same workspace; resume produced different verdict
- **Type 2**: different workspaces; same question; different family rosters
- **Type 3**: different workspaces; related but different questions
- **Type 4**: sequential sessions; methodology version differed

Match to one type via:

```bash
# Compare question content-hash:
sha256sum "<W1_PATH>/intake/question_of_record.md"
sha256sum "<W2_PATH>/intake/question_of_record.md"

# Compare corpus content-hash (per source):
ls "<W1_PATH>/corpus/ingested/"
ls "<W2_PATH>/corpus/ingested/"

# Compare roster:
grep -A5 'tier:\|roster:' "<W1_PATH>/.brenner_workspace/phase0_scope_decision.md"
grep -A5 'tier:\|roster:' "<W2_PATH>/.brenner_workspace/phase0_scope_decision.md"
```

**Step 4 — Apply reconciliation per type.**

### Type 1 (corpus drift OR new evidence)

```bash
# Check corpus drift between W1 and W2:
for source in $(ls "<W1_PATH>/corpus/ingested/"); do
  H1=$(cat "<W1_PATH>/corpus/ingested/$source/.hash" 2>/dev/null || echo "n/a")
  H2=$(cat "<W2_PATH>/corpus/ingested/$source/.hash" 2>/dev/null || echo "n/a")
  if [ "$H1" != "$H2" ]; then
    echo "DRIFT: $source: W1=$H1 W2=$H2"
  fi
done
```

If drift: W2 is canonical (more recent).
If no drift: identify new EVs in W2 not in W1.

### Type 2 (model-family bias)

If verdicts conflict and only family roster differs:

- Run a *third* session with neutral or all-3-family roster
- Reconciler verdict from triangulation across W1, W2, W3

### Type 3 (different scopes)

Both canonical for their scope. Cross-link in HANDBACKs:

```markdown
# In W1's HANDBACK.md § Cross-session note:
This session's verdict applies to <scope from W1>. For <scope from W2>, see <W2_PATH>.

# In W2's HANDBACK.md § Cross-session note:
This session's verdict applies to <scope from W2>. For <scope from W1>, see <W1_PATH>.
```

### Type 4 (methodology evolution)

W2 is canonical. Document why:

- Specific methodology improvement between V1 and V2
- The improvement caught issue X that W1 missed
- W1's verdict deprecated; archived but not deleted

**Step 5 — Produce reconciliation memo.**

`<W2_PATH>/deliverables/RECONCILIATION-MEMO.md` (or save in a separate location):

Per template `assets/templates/reconciliation-memo-template.md`.

Mandatory sections:

- Sessions in conflict (W1, W2 IDs)
- Conflict description
- Diagnosis (type)
- Reconciliation verdict
- Action for user
- Methodology lessons

**Step 6 — Update reconciliation catalog.**

Append to `references/RECONCILIATION-CATALOG.md` (created if not exists):

```markdown
| RC-NNN | <workspace-1 id> vs <workspace-2 id> | Type N | <verdict> | <TIMESTAMP_UTC> | <one-line note> |
```

**Step 7 — Cross-link.**

Update both HANDBACKs to reference the reconciliation memo.

**Step 8 — Methodology lessons.**

If reconciliation surfaces a methodology issue:

- Update `references/` per CROSS-SESSION-LEARNING.md
- Phase 10 lesson committed to skill repo
- Mark in CROSS-SESSION-DRIFT-CATALOG.md

---

**Anti-patterns:**

- ✗ Pick latest verdict by default without reconciliation
- ✗ Use a swarm pane from W1 or W2 as reconciler (no independence)
- ✗ Skip the methodology-version check (Type 4 missed)
- ✗ Reconcile by averaging verdicts (silent averaging)
- ✗ Skip catalog entry (patterns not surfaced)

**Ship-or-Surface SLA:** within 2-4h, reconciliation memo committed.

---

## When MO doesn't fully resolve

Sometimes reconciliation reveals genuine under-determination — the question can't be answered with current methodology + corpus. In that case:

- Document as "under-determined" verdict
- Recommend Phase 4 reopen with deliberately broader corpus / methodology
- For T5: schedule multi-session triangulation (per CROSS-SESSION-LEARNING.md)

Don't force a verdict when one isn't defensible.

---

## Composition

- Subagents/reconciler.md is the canonical conductor
- Compose with /flywheel for cross-session pattern detection
- Compose with /multi-model-triangulation for Type 2 reconciliation

Per SKILL-COMPOSITION-PATTERNS.md.
