# Dueling Wizards Improvement Synthesis

This report records the improvement ideas selected from a dueling-wizards pass
run on 2026-04-27 for the two new support skills:

- `user-support-triage-for-saas-and-open-source-projects`
- `user-support-ticketing-system-for-saas`

The run used Claude Code and Codex idea generation plus cross-scoring. Gemini
was spawned but did not produce a usable artifact in the allotted run, so the
implemented synthesis uses the two completed wizard outputs.

## Highest-Consensus Ideas

| Idea | Why It Matters | Implemented As |
|---|---|---|
| Replayable fire-drill harness | Proves the runbook under pressure, especially no-send safety | [FIRE-DRILL-HARNESS.md](FIRE-DRILL-HARNESS.md) |
| Universal support adapter contract | Gives every support surface one normalized input shape | [ADAPTER-CONTRACT.md](ADAPTER-CONTRACT.md) |
| Runbook/operator/onboarding validators | Turns "good docs" into checkable handoffs | adapter validator + acceptance gates |
| Accretive outcome loop | Converts support sessions into KB, product, template, and operator improvements | [POST-SEND-OUTCOME.md](POST-SEND-OUTCOME.md) |
| State-machine conformance | Keeps ticket lifecycle behavior portable and testable | ticketing skill's `STATE-MACHINE-CONFORMANCE.md` |
| Framework/provider portability | Separates universal support invariants from Next.js/Resend/Drizzle syntax | ticketing portability references |
| Operator evolution | Allows the skill to get sharper from real sessions without uncontrolled doctrine drift | [OPERATOR-EVOLUTION.md](OPERATOR-EVOLUTION.md) |

## Explicit Non-Goals For This Expansion

The scorers rejected or delayed several tempting ideas:

- autonomous scheduled triage before adapter validation and no-send drills;
- refund preview in the generic adapter contract;
- full customer-health scoring in the support adapter;
- a six-level maturity router that would overfit edge cases;
- adversarial AI review machinery before simpler grounding metrics exist;
- status-page/provider automation before incident cohorting is reliable.

These can be revisited later, but only after the core contracts and drills are
proven.

## Kernel Chosen

The durable kernel is:

1. normalize support surfaces through a read-first adapter;
2. rehearse the workflow through no-send fire drills;
3. prove custom ticket systems through state-machine conformance;
4. write outcome records so every session can improve the project and skill;
5. promote new operators only after evidence, owner approval, and rehearsal.

This is intentionally practical. It adds moving parts only where they make the
skill more executable, more universal, or more safely automatable.

## Scoring Notes

Claude scoring of Codex ideas:

- Fire-drill harness: 920
- Adapter contract: 870
- Post-send outcome loop: 810
- Evidence anchor ledger: 780
- State-machine conformance: 750
- Incident commander layer: 730

Codex scoring of Claude ideas:

- Runbook/operator/onboarding validators: 930
- Accretive knowledge loop: 860
- Triage session mining/operator evolution: 800
- Framework abstraction layer: 760
- Multi-provider abstraction: 730

## How Future Agents Should Use This Report

Use this report as a prioritization memo, not a replacement for the detailed
references. If expanding either skill again, start by asking:

- Does the change strengthen the adapter contract?
- Does it make a fire drill more realistic?
- Does it make ticket lifecycle behavior more testable?
- Does it improve the outcome loop?
- Does it preserve the owner confirmation gate?
- Does it keep policy evidence anchored rather than guessed?

If the answer is no to all of those, the idea is probably decorative rather than
operational.
