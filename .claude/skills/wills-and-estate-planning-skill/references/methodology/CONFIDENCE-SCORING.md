# Recommendation Confidence Scoring

Not all recommendations in a plan deserve the same level of confidence.
Some rest on signed documents and verified law. Others rest on hazy memory,
state-law uncertainty, or implementation assumptions.

Capture this explicitly in:

- `analyses/recommendation-confidence-register.md`

---

## Scoring Dimensions

Score each recommendation from 1 to 5 on each dimension.

### 1. Evidence Quality

- `5` = supported by signed documents / statements / records
- `3` = partly documented, partly memory-based
- `1` = mostly unsupported memory or inference

### 2. Law Stability

- `5` = evergreen and unlikely to change the outcome
- `3` = state-specific or procedural, but currently verified
- `1` = volatile or unresolved live-law point

### 3. Implementation Dependence

- `5` = recommendation works with little additional action
- `3` = requires ordinary cleanup or institutional forms
- `1` = requires complex retitling, multiple counterparties, or fragile follow-through

### 4. Human / Conflict Sensitivity

- `5` = unlikely to provoke conflict or misunderstanding
- `3` = may require explanation or sequencing
- `1` = highly contestable or emotionally explosive

---

## Composite Rating

Use the lowest score as the practical ceiling, then write a plain-English label:

- `High confidence`
- `Moderate confidence`
- `Conditional`
- `Do not treat as settled`

This prevents a mathematically average score from hiding a fatal weak link.

---

## Required Columns

| Recommendation | Evidence | Law | Implementation | Human factors | Overall | What would increase confidence |
|----------------|---------:|----:|---------------:|--------------:|---------|--------------------------------|

---

## Operating Rules

1. Anything with weak evidence should stay provisional even if the legal theory is good.
2. Anything that depends on unverified state law should not be presented as final.
3. Anything likely to trigger conflict must be paired with litigation-defense review.
4. Anything operationally fragile must also appear in the implementation ledger.

---

## Anti-Pattern

Do not present low-confidence recommendations with the same tone as high-confidence ones.
The user and attorney need to see where the plan is solid and where it is contingent.
