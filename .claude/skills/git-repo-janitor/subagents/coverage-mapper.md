# Subagent: coverage-mapper

**Phase:** 2.5 (after Phase 2 inventory + Phase 2.5 secret scan)
**Spawn:** Once per run.

## Role

Build the per-run coverage matrix. For each smell rule in FILE-SMELLS.md, emit a row showing whether it fired and against which candidates. Records `present | partial | missing | n/a` per rule. See COVERAGE-MATRIX.md for the schema.

## Prompt

You are building the smell-rule coverage matrix for this run.

Read:
- `<workspace>/candidates.tsv` (the inventory)
- `<workspace>/secret_findings.tsv` (Phase 2.5 output)
- `<workspace>/project_profile.json` (archetype + protected_globs)
- `references/FILE-SMELLS.md` (the master smell catalogue)

For each smell rule listed in FILE-SMELLS.md (every entry in the "Tag glossary" table and every section under "Filename pattern rules" / "Content fingerprints"):

1. Count how many candidates in `candidates.tsv` have this rule's tag in their `smell_tags` column.
2. Determine status:
   - `present`: ≥1 candidate has the tag
   - `partial`: candidates have the tag but some still have empty verdict (Phase 4 incomplete)
   - `missing`: no candidates have the tag, BUT the archetype suggests the rule should apply (e.g., a Python project with `pyproject.toml` has no `__pycache__` candidates — investigate)
   - `n/a`: no candidates have the tag, AND the archetype doesn't suggest the rule should apply

3. For each row, capture:
   - hit_count: number of candidates with this tag
   - verdict_distribution: count of each verdict among matching candidates
   - evidence: 2-3 sample paths
   - notes: any Cat-X deferral, archetype-specific reasoning, etc.

Use COVERAGE-MATRIX.md "Should this rule apply?" archetype heuristics to decide between `missing` and `n/a`.

Write to `<workspace>/coverage_matrix.md` per the schema in COVERAGE-MATRIX.md.

For any `missing` row, write a short investigation note: "Expected `<rule>` to fire on this archetype but no candidates were tagged. Possible reasons: (a) the rule's regex needs widening; (b) the project has `<rule>` in `.gitignore` already; (c) the user manually cleaned this category before."

## Output

`<workspace>/coverage_matrix.md` with one row per smell rule.

## Tools used

Read, Bash, Edit (for the markdown).

## Time budget

3-8 min depending on number of rules and candidates.
