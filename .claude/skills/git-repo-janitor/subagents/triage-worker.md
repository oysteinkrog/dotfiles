# Subagent: triage-worker

**Phase:** 4
**Spawn:** One per batch (~30 candidates each).

## Role

Per-batch classify + reference-grep + verdict.

## Prompt

You are triaging candidates batch_`<NNN>` from `<workspace>/candidates.tsv` (rows `<start>` to `<end>`).

For each candidate in your assigned batch:

1. **CLASSIFY-PURPOSE** — read `<bundle>/working-tree-copies/<path>`; determine purpose (source / fixture / artifact / plan / scratch / log / db / config). Use `bash <skill-dir>/scripts/classify-purpose.sh <bundle>/working-tree-copies/<path>` for a quick magic-byte/header check, then read the content for nuance.

2. **REFERENCE-GREP** — read `reference_graph.json[<id>].inbound_refs`. If non-empty:
   - Inspect each match's surrounding context (use Read tool on the referenced file).
   - Distinguish real references from false positives (e.g., `test_ptr` matching `test_ptrmap_*`).
   - Real references bias toward `keep-in-place` or `surface-to-user`.

3. **LOCATE-PROPER-HOME** — for `move` candidates, propose a destination from the `references/TRIAGE-RUBRIC.md § LOCATE-PROPER-HOME` table. Prefer existing dirs over new ones.

4. **ASSESS-VALUE** — does this file have unique content not derivable from elsewhere? Plan docs YES; auto-generated reports usually NO.

5. **VERDICT** — apply the `references/TRIAGE-RUBRIC.md` decision flow. Output one of:
   - `delete-and-gitignore`
   - `delete-no-gitignore`
   - `gitignore-only`
   - `move`
   - `keep-in-place`
   - `protected`
   - `surface-to-user`

6. **CONFIDENCE** in [0, 1]. <0.7 forces `surface-to-user`.

7. **EVIDENCE** — compact string per `references/EVIDENCE-CITATIONS.md`.

Write one row per candidate to `<workspace>/triage/batch_<NNN>.tsv` with columns:
`id, verdict, confidence, evidence, proposed_dest, gitignore_pattern`.

DO NOT modify any project files. DO NOT operate outside your assigned batch range.

## Output

`<workspace>/triage/batch_<NNN>.tsv`.

## Tools used

Read, Bash, Grep.

## Time budget

5–30 min per batch (depends on candidate count and avg ref-graph complexity).
