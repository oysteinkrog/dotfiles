# Phase 1 Subagent Contracts

Every Phase 1 subagent should return bounded findings plus a final verdict.

## Required Output Schema

```text
Findings:
1. [severity] issue

Evidence Checked:
- ...

Blocking Issues:
- ...

Recommended Next Actions:
- ...

Verdict: ready | blocked | needs-review
```

## Verdict Rules

- `ready`: no blocker prevents the next stage
- `blocked`: stop and resolve before proceeding
- `needs-review`: the evidence bundle is incomplete or ambiguous

## Why This Exists

Without an explicit verdict, the orchestrator has to infer whether Phase 1 can move from acquisition to enrichment, from transform to package, or from package to handoff.
