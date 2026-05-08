# Document Ingestion and Quality Triage

Real users bring messy inputs:

- scans
- blurry phone photos
- unsigned drafts
- stale statements
- partial PDFs
- old attorney markups
- memory summaries with no documents

This file standardizes how the skill treats those inputs.

Output to:

- `analyses/document-quality-triage.md`

---

## Document Classes

### A. Authoritative

Use when the document is current, signed, legible, and appears complete.

Examples:

- signed will
- signed trust
- latest beneficiary confirmation
- recent account statement
- recorded deed

### B. Probative But Not Final

Useful, but not enough by itself.

Examples:

- unsigned draft from attorney
- stale statement
- email summary from advisor
- screenshot lacking full page context

### C. Context Only

Helpful for background but not for treating a fact as settled.

Examples:

- user notes
- old planning memo
- recollection of what the attorney "probably did"

### D. Unreliable / Unusable

Examples:

- illegible image
- missing pages
- contradictory version with no execution proof
- clearly superseded document

---

## Triage Questions

For each meaningful document:

1. What is it?
2. Who likely prepared it?
3. Is it signed?
4. Is it dated?
5. Is it complete?
6. Is it legible?
7. Does it appear current or superseded?
8. What facts can safely be extracted from it?
9. What planning conclusions should remain blocked pending a better copy?

---

## Naming and Normalization Rules

Prefer stable filenames and notes such as:

- `will-2018-signed.pdf`
- `trust-amendment-2023-unsigned-draft.pdf`
- `vanguard-ira-beneficiary-confirmation-2026-03.pdf`

If the user's files are chaotic, record a normalized alias in the triage output rather
than renaming their originals by force.

---

## Required Output Sections

1. authoritative documents
2. weak / stale / incomplete documents
3. blocked planning decisions
4. follow-up documents to request
5. contradictions between versions

---

## Anti-Pattern

Do not treat:

- an unsigned draft as an executed document
- a 2018 beneficiary confirmation as proof of the 2026 beneficiary
- a user memory statement as equivalent to a deed or account statement
