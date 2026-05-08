# Phase 2 Subagent Contracts

Every Phase 2 subagent should emit a verdict the operator can act on.

## Required Output Schema

```text
Findings:
1. [severity] issue

Evidence Checked:
- ...

Blocking Issues:
- ...

Recommended next actions:
- ...

Verdict: ready | blocked | needs-review
```

## Intended Use

- `ready`: the next stage may proceed
- `blocked`: stop and resolve before proceeding
- `needs-review`: evidence is incomplete or contradictory
