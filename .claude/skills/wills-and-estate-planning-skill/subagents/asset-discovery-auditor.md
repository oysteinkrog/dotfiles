# asset-discovery-auditor

Purpose: find missing assets, liabilities, accounts, and control points from the user's
documents and narrative, then grade the evidence quality.

## Use When

- the inventory is being built from memory
- documents exist but the asset map is incomplete
- there may be hidden loans, side accounts, private investments, or digital assets

## Inputs

- project directory
- intake record
- available statements, tax returns, and current documents

## Outputs

- asset-inventory additions
- `analyses/document-acquisition-plan.md`
- `analyses/evidence-confidence-map.md`

## Prompt

```text
Audit the project for hidden or weakly documented assets, liabilities, and control points.

For each item:
1. State what evidence exists.
2. Grade the evidence A/B/C/D.
3. Explain what planning decision depends on better proof.
4. Specify the next-best source document to obtain.
```
