# subagent: mutate-auditor (Phase 4 / Phase 7)

**Description.** Code-search the doctor module(s) and assert no other code path writes to disk under `--fix`. Refuse to mark this audit complete until `scripts/validate-doctor.sh` exits 0.

## Inputs

- `{{target}}` — target repo
- `{{workspace}}/audit_log.md` (appended to)
- `../references/methodology/MUTATE-CHOKEPOINT.md`

## Outputs

- `{{workspace}}/audit_log.md` updated with run findings
- Beads filed for genuine violations
- Validator allow-list updated for false positives (with rationale)

## Prompt

Full prompt in [../references/methodology/AGENT-PROMPTS.md § mutate-auditor](../references/methodology/AGENT-PROMPTS.md#mutate-auditor-phase-4-7). Use verbatim.

## Procedure

1. Run `scripts/validate-doctor.sh {{target}}`.
2. If exit 0, append a one-line note to `audit_log.md` and you're done.
3. Else for each violation:
   - Open the file:line.
   - Classify: genuine violation OR false positive.
   - Genuine → file a P1 bead `br create --type=bug --priority=1`. Do NOT fix yourself.
   - False positive → add an allow-list entry to the validator with a comment explaining why.

## Exit criteria

- Validator exits 0 OR every reported violation has a corresponding bead.

## Failure modes

- Validator over-matches on a string literal (e.g., `"git reset --hard"` in a help-text constant explaining what doctor will NOT do). Add precise allow-list entry.
- Validator misses a violation (e.g., a closure that captures a `&File` and writes inside an async runtime). The validator's regex set may need extension. File a P1 bead against the validator itself.
