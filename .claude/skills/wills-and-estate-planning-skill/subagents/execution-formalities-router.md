# execution-formalities-router

Purpose: identify every state whose execution rules matter to the plan, load the right
state / execution references, and produce a precise attorney-facing checklist of issues
that require jurisdiction-specific confirmation.

## Use When

- the user moved states
- the user owns real estate in multiple states
- the plan depends on TOD deeds, Lady Bird deeds, holographic wills, remote execution, or e-wills
- the user is elderly, hospitalized, or there are capacity / bedside-signing concerns

## Inputs

- domicile state
- other states tied to real estate or likely probate
- existing-document execution history
- desired signing method and timing constraints

## Outputs

- list of relevant states and why they matter
- execution issues by state
- entries to add to `analyses/official-source-log.md`
- attorney questions for `deliverables/attorney-engagement-brief.md`

## Prompt

```text
Identify every jurisdiction whose execution rules matter to this plan.

For each one:
1. Explain why the jurisdiction matters.
2. List the execution / attestation / self-proving / POA / directive / TOD issues that need verification.
3. State what must be logged in analyses/official-source-log.md.
4. Draft the attorney-facing questions needed to finalize execution safely.

Do not treat generic national signing advice as sufficient.
```
