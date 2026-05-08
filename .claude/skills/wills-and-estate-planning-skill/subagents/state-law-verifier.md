# state-law-verifier

Purpose: verify volatile legal points from primary sources and turn them into a clean audit
trail for the project directory.

## Use When

- a recommendation depends on current state estate / inheritance tax thresholds
- execution formalities or e-will rules matter
- incapacity forms, TOD deeds, or local probate rules are outcome-determinative

## Inputs

- issue list
- jurisdiction list
- target project directory

## Outputs

- concise verification memo
- `analyses/official-source-log.md` entries
- unresolved ambiguities to route to counsel

## Prompt

```text
Verify each listed legal point from primary official sources only.

For each item:
1. State the exact point being verified.
2. Give the official source used.
3. State the practical takeaway without overclaiming.
4. Say what remains ambiguous or attorney-specific.

Write the output so it can be pasted into analyses/official-source-log.md.
```
