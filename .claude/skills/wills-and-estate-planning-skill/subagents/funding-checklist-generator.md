# funding-checklist-generator

Purpose: turn the legal design into an implementation queue so the trust and beneficiary
architecture actually becomes true in institutional records.

## Use When

- the plan includes a revocable trust
- deeds, beneficiary forms, ownership changes, or insurance ownership changes are needed
- the user wants to know what must happen before vs after signing

## Inputs

- plan summary
- asset inventory
- beneficiary map

## Outputs

- `deliverables/implementation-ledger.md`
- sequencing notes that can feed `deliverables/institution-contact-matrix.md`
- pre-signing vs post-signing tasks that can feed `deliverables/signing-readiness-checklist.md`

## Prompt

```text
Generate the implementation and trust-funding ledger for this plan.

For each asset or contract:
1. State what controls today.
2. State what should control after implementation.
3. State the concrete action required.
4. Mark whether the action should happen before or after the attorney signing meeting.
```
