# Reconciliation Memo — RS-<NEW>-vs-RS-<OLD>

**Reconciliation date:** <ISO>
**Reconciler:** <fresh general-purpose Agent | named human reviewer>

---

## Sessions in conflict

### W1 (older / first)

- **Path:** <W1_PATH>
- **Session ID:** <RS-...>
- **Operator:** <name>
- **Date:** <ISO>
- **Tier:** T<N>
- **Roster:** <Solo/Pair/Squad/Swarm>
- **Verdict:** <one-line>
- **Confidence:** <low/medium/high>
- **Cited evidence (top 3):** EV-NNN, EV-NNN, EV-NNN

### W2 (newer / second)

- **Path:** <W2_PATH>
- **Session ID:** <RS-...>
- **Operator:** <name>
- **Date:** <ISO>
- **Tier:** T<N>
- **Roster:** <Solo/Pair/Squad/Swarm>
- **Verdict:** <one-line>
- **Confidence:** <low/medium/high>
- **Cited evidence (top 3):** EV-NNN, EV-NNN, EV-NNN

---

## Conflict description

<2-3 paragraphs explaining what the two sessions disagree on. Include:>

- The shared question (or near-shared)
- W1's verdict and W2's verdict (which differ how)
- Whether the disagreement is on the verdict, the confidence, the scope, or the methodology

---

## Conflict diagnosis

| Aspect | W1 | W2 | Match? |
|--------|----|----|--------|
| Question content-hash | <hash> | <hash> | <yes/no> |
| Corpus content-hash | <hash> | <hash> | <yes/no> |
| Methodology version | <commit SHA> | <commit SHA> | <yes/no> |
| Roster (model families) | <list> | <list> | <yes/no> |
| Tier | T<N> | T<N> | <yes/no> |

**Conflict type:** Type 1 / 2 / 3 / 4 (per RECONCILIATION-OF-PRIOR-SESSIONS.md)

**Diagnosis explanation:**

<one paragraph explaining why this is the type, citing specific evidence from the comparisons above>

---

## Reconciliation verdict

**Type-N reconciliation rule applied:** <which rule>

**Canonical session for the question:** <W1 | W2 | merge | both-canonical-different-scopes | neither-genuinely-under-determined>

**Detailed verdict:**

<2-3 paragraphs explaining the reconciliation. Specifically address:>

- Why this verdict over the alternatives
- What evidence supports the verdict
- What conditions would change the verdict (e.g., "if the corpus drifts further, W2's verdict may need re-evaluation")

---

## Action for user

**Short version:** <one sentence>

**Detailed steps:**

1. <action 1>
2. <action 2>
3. <action 3>

(Examples by type:)

### Type 1 (corpus drift)

- W2 is canonical; act on W2's recommendation
- W1's HANDBACK marked superseded by reconciliation
- Update CROSS-SESSION-DRIFT-CATALOG with corpus-drift pattern

### Type 2 (model-family bias)

- Run a 3rd session with neutral/all-3-family roster to triangulate
- Reconciler will re-converge after 3rd session
- Document family-bias in CROSS-SESSION-DRIFT-CATALOG

### Type 3 (different scopes)

- Both canonical for their respective scopes
- User picks based on their use case
- Cross-link both HANDBACKs

### Type 4 (methodology evolved)

- W2 is canonical; methodology improvement caught what W1 missed
- W1 archived but not deleted; available for historical reference
- Methodology lesson documented in references/

---

## Methodology lessons

<1-3 lessons that this reconciliation surfaced, if any. Lessons should be commit-worthy to references/.>

- <lesson 1>
- <lesson 2>

---

## Cross-references

Update both HANDBACKs to point to this memo:

- [ ] W1's HANDBACK.md § Cross-session note: "Reconciled vs <W2_ID>; per <this memo>"
- [ ] W2's HANDBACK.md § Cross-session note: "Reconciled vs <W1_ID>; per <this memo>"
- [ ] CROSS-SESSION-DRIFT-CATALOG.md: append entry per RECONCILIATION-CATALOG format

---

## Reviewer sign-off

- [x] Reconciler: <name/agent> on <ISO>

(For T5 reconciliations, ≥2 reviewers should sign off.)

---

## Catalog entry

For inclusion in `references/RECONCILIATION-CATALOG.md`:

```markdown
| RC-NNN | <W1_ID> vs <W2_ID> | Type N | <verdict> | <ISO> | <one-line note> |
```

---

## Future-proofing

If new evidence surfaces or methodology improves further, this reconciliation may need re-running. Mark this memo with version:

- **Memo version:** v1
- **Re-run trigger conditions:** <e.g., "if corpus_index.md hashes change for any source cited"; "if methodology version moves past <SHA>">
