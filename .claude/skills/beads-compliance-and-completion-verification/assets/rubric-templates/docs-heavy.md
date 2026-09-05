---
rubric_version: "docs-heavy-1.0.0"
threshold: 700
score_threshold: 700
weights_by_type:
  docs:
    implementation: 500    # the doc IS the implementation
    tests:           100   # link-checker, fidelity tests
    anti_theater:    100   # no "TODO: write this section"
    test_depth:      100
    docs:            150
    integration:      50
  documentation:
    implementation: 500
    tests:           100
    anti_theater:    100
    test_depth:      100
    docs:            150
    integration:      50
weights_by_label:
  user-facing:
    tests:          200    # screenshots / live examples must work
    anti_theater:   150
---

# Rubric — docs-heavy variant

For documentation-led projects (docs sites, API references, tutorials,
runbooks-as-code). Re-weights so the doc text itself counts as
"implementation" and demands link-checker + fidelity tests.

## Per-type overrides for `docs` / `documentation` beads

| Dimension | docs max | Default | Why |
|-----------|---------:|--------:|-----|
| **Implementation** | **500** | 300 | The doc body IS the deliverable |
| Tests | 100 | 250 | Link checker + spell + reading-grade + fidelity |
| Anti-theater | 100 | 150 | No "TODO: write this section" markers |
| Test depth | 100 | 150 | Pages render, examples execute, screenshots match |
| Docs | 150 | 100 | Bumped slightly (meta-docs about THIS docs project) |
| Integration | 50 | 50 | Same |

## Threshold = 700 (default — docs aren't held to security/perf bar)

## Hard rules

- Any `docs` bead with `TODO`, `FIXME`, `HACK`, `XXX`, or `[draft]` markers in the new content → MAJOR (Pattern 28 in `references/FAILURE-MODES.md`).
- Any code example in a doc that the doc claims is "tested" / "working" must actually execute. If the doc has a `tested-example` marker block, the audit RE-EXECUTES it. Failure → BLOCKING.
- Any new doc that links to a not-yet-existing target (`see [X]` where X doesn't exist) → MAJOR.
- Screenshots: if the doc has screenshot files, they must be < 30 days old or have a regeneration trigger. Stale screenshots → MINOR.

## What this variant does NOT change

- 10-phase loop unchanged
- Convergence unchanged
- Tier routing unchanged

## When to use

- Project's primary deliverable is a documentation site (Nextra, MkDocs, Hugo, Docusaurus)
- > 30% of beads are `docs` / `documentation` type
- Pre-launch documentation pass
- Adopting docs-as-code workflow on a new repo
