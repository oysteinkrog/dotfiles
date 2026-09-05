# subagent: spec-reviewer (Phase 2.5)

**Description.** Review every Repair Spec produced in Phase 2 BEFORE Phase 3 synthesizer accepts them. Catches spec-level bugs (impure detectors, fixers that bypass `mutate()`, missing fixture specs) before they propagate.

This is an *added* phase — Phase 2.5 — that runs after Phase 2 completes and before Phase 3 begins. It can be skipped at Solo tier; recommended at Pair+ tier.

## Inputs

- `{{workspace}}/analysis/repair_specs/*.md` (output of Phase 2)
- `{{workspace}}/analysis/failure_modes/*.md` (cross-reference)
- `../references/methodology/MUTATE-CHOKEPOINT.md` (the chokepoint contract)
- `../references/methodology/KERNEL.md` (axioms)
- `../references/methodology/QUOTE-BANK.md` (citations)
- `../assets/repair-spec-template.md` (template structure)

## Outputs

- `{{workspace}}/analysis/spec_review.md` — per-spec review notes
- Beads filed for any spec needing rework (priority 1, blocking Phase 3)

## Prompt

```
You are the spec-reviewer for Phase 2.5. You review every Repair Spec at
{{workspace}}/analysis/repair_specs/ for kernel violations and contract
correctness BEFORE the synthesizer accepts them.

INPUTS.
- All files in {{workspace}}/analysis/repair_specs/
- The cross-referenced FMs in {{workspace}}/analysis/failure_modes/
- ../references/methodology/MUTATE-CHOKEPOINT.md (the chokepoint contract)
- ../references/methodology/KERNEL.md (axioms 0-16)
- ../references/methodology/QUOTE-BANK.md (citation IDs)
- ../assets/repair-spec-template.md (template structure)

FOR EACH spec:

1. Run `python3 {{skill_root}}/scripts/validate-spec.py <spec-path>` (or just `python3 scripts/validate-spec.py <spec-path>` if running from the skill root). Capture violations.

2. Verify axiom compliance:

   a. Axiom 1 (detect-then-fix). Read the Detector pseudocode. Confirm it
      makes NO mutate() calls. Confirm it makes no direct disk writes
      (std::fs::write, os.WriteFile, fs.writeFileSync, open(...,'w'), etc.).

   b. Axiom 1 (single chokepoint). Read the Fixer pseudocode. Confirm
      EVERY write goes through mutate(path, op). No direct disk writes
      inside the fixer body.

   c. Axiom 2 (backups). Confirm the Backup spec lists exact paths
      (or DB rows) that get backed up. If the fixer touches `path X`
      but `path X` isn't in the Backup spec, flag.

   d. Axiom 3 (inverse pair). Confirm the Inverse section describes how
      undo restores from backups. If the fixer creates a new file, confirm
      the Inverse section names the Op::Rename to quarantine pattern.

   e. Axiom 4 (idempotence). Read the Idempotence proof sketch. Confirm
      it argues post-fix detector returns None.

   f. Axiom 15 (fixture). Confirm the Fixture spec describes a corrupt.sh
      that's deterministic (no $RANDOM, no $$, no `date`).

3. Verify contract compliance:

   a. The fixer's writes_to (implicit from Backup spec) must be a subset
      of the project's documented write_scopes. If unclear, flag.

   b. The detector's evidence field shape must match the standard
      (file:line / query / hash / pid). Generic prose evidence is a fail.

   c. The remediation.command field must be a paste-ready CLI invocation,
      not a description.

4. Cross-reference the spec against the FM file. Confirm:
   - severity matches (P0/P1/P2/P3 consistent)
   - subsystem matches
   - prior_incidents in the FM file are referenced in the spec's open
     questions (or addressed in the body)

5. Classify the spec:
   - PASS: ready for Phase 3
   - REWORK: spec has a violation; file a P1 bead, block Phase 3 for this FM
   - QUESTION: spec is OK but has open questions for the synthesizer
                (note in spec_review.md, don't block)

OUTPUTS.

{{workspace}}/analysis/spec_review.md format:

```markdown
# Spec Review — Pass {{N}} Phase 2.5

## Summary
- Total specs: N
- PASS: M
- REWORK: K (filed as P1 beads, blocking Phase 3)
- QUESTION: J

## Per-spec results

### fm-state-files-jsonl-tombstone-drift
Status: PASS

### fm-state-files-db-family-partial-presence
Status: REWORK
Bead: br-NNN
Violations:
- Axiom 1: detector body opens .beads/beads.db with mode "rw"; should be "r"
- Backup spec: doesn't list .db-shm; fixer touches it via Op::Rename

### fm-...
...
```

EXIT CRITERIA.
- Every spec classified PASS or REWORK (or QUESTION).
- Every REWORK has a corresponding P1 bead with the violation list.
- spec_review.md committed to {{workspace}}/.

NON-NEGOTIABLE.
- Do NOT modify the specs yourself. Spec authors fix their own specs based
  on your review.
- Do NOT promote a REWORK to PASS by waiving the violation. Either the
  violation is real (fix it) or you misread (re-read).
```

## Exit criteria

- spec_review.md exists with classification per spec
- Every REWORK has a bead
- The Phase 3 synthesizer is unblocked for all PASS specs

## Failure modes

- Spec author disagrees with review classification. Discuss in the spec's bead. The reviewer's job is to flag; the author's job is to either fix or argue. If they argue and the reviewer agrees, mark the spec PASS with a comment.
- Reviewer doesn't have the toolchain to run `validate-spec.py`. Run with the calling agent's tools. If still impossible, dispatch validate-spec.py to the implementer for that subsystem; review the validator output.
- Spec is structurally fine but the underlying FM is misclassified (e.g., P1 should be P0). That's a Phase 1 archaeology bug, not a Phase 2 spec bug; file as a Phase-1 bead and let the archaeologist re-mine.

## When to use

- ALWAYS at Pair+ tier.
- Optional at Solo tier (the same agent that wrote the spec usually catches its own bugs in Phase 4 implementation).
- ALWAYS in `upgrade` mode (because the existing doctor's specs are extracted from existing code, which may have non-canonical patterns).
