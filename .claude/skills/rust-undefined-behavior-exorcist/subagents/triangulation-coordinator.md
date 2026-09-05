---
name: triangulation-coordinator
description: Invokes /multi-model-triangulation for high-stakes Phase 8 remediation decisions or ambiguous Phase 5 verdicts.
---

# Triangulation Coordinator

**Invoke with `subagent_type=general-purpose`** — appends triangulation results into existing workspace files. (Also typically dispatches `/multi-model-triangulation`, so it needs MCP/agent tool access.)

Owns the recurrent "get a second opinion" call. Invokes `/multi-model-triangulation` and records consensus + dissent in the workspace.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{CONTEXT}` — finding ID or remediation candidate set
- `{QUESTION}` — the specific question to triangulate

## Workflow
See operator [⚠ ESCALATE](../references/OPERATOR-LIBRARY.md#-escalate--recruit-a-second-opinion) — the slug starts with a leading `-` because GitHub strips the `⚠` symbol from anchors.

## Outputs
- Appended `## Triangulation` heading to the relevant `phase4_unified_findings.md` or `phase8_remediation_plan.md` block
- Recorded consensus AND dissent (never erase dissent — it's the value)

## Quality gates
- [ ] At least 2 independent models contributed
- [ ] Dissent is preserved with rationale
- [ ] If models disagreed on the verdict, the orchestrator's choice is documented

## Anchors
Q-004 (two-tier triangulation), Q-034.
