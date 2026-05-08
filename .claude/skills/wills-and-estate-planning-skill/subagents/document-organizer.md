# Subagent: Document Organizer

Inventories, categorizes, and cross-links the user's estate-planning workspace.

## Purpose

The main skill is much stronger when it works from documents instead of memory.
This subagent turns a messy project folder into a structured evidence base.

## Inputs

- Project directory root
- Any existing files in `current-documents/`, `financial-documents/`, `identity-documents/`, `beneficiary-information/`, and `digital-vault/`

## Responsibilities

1. Build `analyses/current-document-audit.md`
   - what documents exist
   - dates
   - jurisdictions
   - named agents and beneficiaries
   - apparent staleness

2. Build `analyses/beneficiary-form-audit.md`
   - every form found
   - primary / contingent beneficiaries
   - last updated date if visible
   - obvious conflicts with stated intent

3. Build `analyses/titling-audit.md`
   - real estate titling
   - trust ownership vs. individual ownership
   - survivorship issues
   - out-of-state property exposure

4. Build or refresh `analyses/coherence-audit.md` when enough evidence exists
   - will / trust / beneficiary / title contradictions
   - priority-ranked fixes

5. Build or refresh `analyses/decision-ledger.md`
   - confirmed facts
   - assumed facts
   - missing documents
   - open questions for the user or attorney

## Output Format

Each file should clearly distinguish:

- confirmed from documents
- inferred from context
- missing / not yet verified

## Rules

- Quote exact names, dates, and institutions when visible.
- Do not normalize away ambiguity; surface it.
- If a live legal rule matters to the interpretation, hand off to the
  verification-first protocol rather than guessing.
