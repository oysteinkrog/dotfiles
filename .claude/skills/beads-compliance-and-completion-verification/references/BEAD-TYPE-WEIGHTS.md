# BEAD-TYPE-WEIGHTS.md — Per-Bead-Type Rubric Tunings

The rubric in `RUBRIC.md` is the default. Different bead types reasonably weight different dimensions. This file documents the tunings; the tunings are written into `rubric.md` at audit-dir bootstrap (so they're project-specific and reproducible).

---

## Type table

`br` recognizes these bead types: `task`, `bug`, `feature`, `epic`, `chore`, `docs`, `question`, plus user-defined `Custom(...)` types.

| Type | Implementation | Tests | Anti-theater | Test depth | Docs/migration | Cross-bead |
|------|---------------:|------:|-------------:|-----------:|---------------:|-----------:|
| **feature** (default) | 300 | 250 | 150 | 150 | 100 | 50 |
| **bug** | 200 | 350 | 150 | 150 | 100 | 50 |
| **task** (default) | 300 | 250 | 150 | 150 | 100 | 50 |
| **epic** | 100 | 100 | 100 | 100 | 100 | 500 |
| **chore** | 350 | 200 | 150 | 100 | 150 | 50 |
| **docs** | 50 | 50 | 50 | 50 | 750 | 50 |
| **question** | n/a — questions don't have evidence in the same sense; score on whether the question was actually *answered* in the close-reason / linked bead | | | | | |

**Why these specific weights?**

- **bug:** Bug fixes live or die by their *regression test*. If you don't have a test that fails before and passes after, you didn't actually fix it — you just stopped seeing it. Test weight bumped from 250 → 350; implementation dropped from 300 → 200.
- **epic:** Epics aggregate child beads; their own evidence is mostly cross-bead integration. Cross-bead weight bumped from 50 → 500. (An epic should NOT be marked closed until its children are; if it is, that's a Phase 7 finding.)
- **chore:** Chores (refactors, dep upgrades) are mostly about implementation correctness; tests less central but anti-theater still matters (incomplete refactors are common).
- **docs:** Documentation beads should be scored almost entirely on whether the docs exist, are accurate, and are reachable. Implementation/tests weight collapsed; docs weight up to 750.
- **question:** Questions don't fit the rubric. Score them as a binary `answered: true | false` based on the close reason and linked beads.

---

## Implicit-requirement injection per type

The spec extractor adds these implicit checklist items based on bead type:

| Type | Implicit requirements added |
|------|------------------------------|
| feature | At least one happy-path test; documentation update if user-facing; telemetry if performance-sensitive |
| bug | A regression test that would have caught the bug; the test must be in the diff that closed the bead |
| task | A test for whatever was added/changed (unless explicitly N/A) |
| epic | Every child bead is closed and scored ≥ threshold |
| chore | Tests still pass after the chore; build still green |
| docs | The doc file exists; the doc is reachable from the docs index |
| question | The close reason references the answer or a linked bead |

The implicit requirements have weight 1 (vs. weight 2 for explicit items), so explicitly-named requirements dominate the score.

---

## Custom bead types

If a project uses `Custom(<name>)` types, the rubric falls back to the `task` defaults unless the user adds a tuning in `rubric.md`:

```yaml
# rubric.md frontmatter (excerpt)
custom_type_weights:
  research:
    implementation: 100
    tests: 100
    docs: 600   # research beads are mostly write-ups
    cross_bead: 200
  spike:
    implementation: 200
    tests: 100
    docs: 400   # spikes mostly produce writeups + decisions
```

---

## Priority influence

Priority does NOT change the rubric weights. Priority influences:

- **Remediation urgency** in Phase 9: a P0 false-closed bead becomes a P0 reopen / completion-debt bead.
- **Executive summary ordering** in `REPORT.md`: false-closed P0/P1 beads are listed first.
- **Convergence sensitivity:** a +/- 10 score change on a P0 bead is more interesting than the same change on a P4; the convergence check flags P0/P1 deltas separately.
