---
name: swarm-oracle
model: opus
description: Run 2x oracle sessions (FOR + AGAINST stances) to validate design decisions, plans, or bead readiness. Default = two GPT-6 Astra sessions via Codex CLI; add two Fable subagents as a second opinion for high-stakes or contested validations, and use them as the fallback when Codex is unavailable. Use after design rounds, before implementation, or to challenge architecture decisions.
argument-hint: "<topic or file to evaluate> [--rounds N] [--models M1,M2]"
---

# Oracle Consensus

> **Oracle policy (2026-09):** GPT-6 Astra (`gpt-6-astra`, via the Codex CLI) is the
> primary oracle — the default FOR/AGAINST debate runs as two `codex exec` calls, one
> per stance. Astra alone is the normal shape of a validation; no pairing is required.
> Fable (`claude-fable-5`) is the **secondary oracle**: add a Fable FOR/AGAINST pair
> when the validation is high-stakes or the two Astra stances leave the call contested,
> or when the user asks for a second opinion. See `/consult-oracles` and the Oracle
> Consultation Policy in `~/CLAUDE.md`.
>
> **Availability fallback:** if the Codex calls fail (Codex missing, path not trusted,
> auth error, empty output after a real attempt), run the same FOR/AGAINST debate with
> Fable subagents (`Agent` tool with `model: "fable"`; Fable is not reachable through
> PAL) and state the substitution in the verdict. If Fable spawns also fail, use
> `model: "opus"` subagents and say so. Do not silently downgrade.
>
> **Sensitive code:** the Codex calls leave the machine. Proprietary or sensitive
> material needs approval first; without it, run the debate on Fable and note why.

Run a structured FOR/AGAINST debate between two high-capability oracle sessions on a design decision, plan, or bead set. Produces a scored verdict with specific actionable corrections.

## When to Use

- After a design swarm to validate decisions
- Before committing to an architecture direction
- After bead creation to validate readiness
- When two approaches seem equally valid
- Any time "validate this with oracles" is requested

## Prerequisites

The default Astra tier needs Codex only: confirm `codex` is on PATH and the repo root is trusted in `~/.codex/config.toml`. For the PAL route: verify PAL MCP is running before launching those oracles. If `mcp__pal__listmodels` fails or returns empty, alert the user — agents silently fall back to self-analysis without PAL, producing unreliable results. Fable subagents need no PAL.

## Workflow

### Step 1: Frame the Evaluation

Write a clear, specific evaluation prompt. This is what both models will see.

**Good framing:**
```
Evaluate this sensor plate settings redesign for a WPF desktop app:
- Plan: [summary of key decisions]
- Key constraint: Must support 1-8 sensor plates, composite plates, and auto-detection
- Files affected: [list]
- Risk areas: [list]
Score 1-10 on: correctness, completeness, feasibility, UX quality, architecture quality
```

**Bad framing:**
```
Is this plan good?
```

The evaluation prompt must be self-contained — models do not share context between stances.

### Step 2: Configure Stances

**Default tier (GPT-6 Astra):** run FOR and AGAINST as two `codex exec` calls in one
message. Each prompt is self-contained (evaluation prompt + file paths); the two
sessions share no context. Astra is not reachable through PAL, and the explicit tier
ID is required — the bare `gpt-6` alias hangs. See the `/codex` skill for prompting
and exec pitfalls.

`xhigh` is the default effort; switch a stance to `model_reasoning_effort=ultra`
(subagent fan-out) only when its evaluation decomposes into parallel facets, e.g. an
AGAINST pass over a large bead set or a design spanning several independent
subsystems:

```bash
codex exec -m gpt-6-astra -c model_reasoning_effort=xhigh \
  -o <scratchpad>/oracle-for.md "<evaluation prompt>\n\nStance: Advocate..." < /dev/null 2>/dev/null
codex exec -m gpt-6-astra -c model_reasoning_effort=xhigh \
  -o <scratchpad>/oracle-against.md "<evaluation prompt>\n\nStance: Challenge..." < /dev/null 2>/dev/null
```

`< /dev/null` is required: without a stdin source `codex exec` blocks forever on
"Reading additional input from stdin" and looks like a slow model. `-o <file>`
captures the final message; read the file rather than parsing stdout.

Do not pass `--sandbox read-only`. On WSL1 the sandbox cannot start, so Astra cannot
read any file and answers from the prompt alone, while still exiting 0. The default
`sandbox_mode` in `~/.codex/config.toml` lets it read the repo. Before the two long
runs, send one cheap probe: ask Astra for the title and line count of one known file,
check both, and run `git status` afterwards to confirm it wrote nothing. A stance
answer that cites no file or line was not read from the repo.

Then skip to Step 4 and synthesize the two responses yourself.

**Second opinion (Fable):** for high-stakes validations, or when the two Astra
stances leave the call contested, spawn a Fable FOR/AGAINST pair in a single message
and synthesize all four responses. Same shape when Codex is unavailable, in which
case the Fable pair is the whole debate.

```
Agent({ subagent_type: "general-purpose", model: "fable",
  prompt: "<evaluation prompt>\n\nStance: Advocate for this design. Identify its strengths, explain why the decisions are sound, and argue that it should be approved. Be specific — cite exact decisions and explain their merit. Score honestly; 'for' does not mean blindly positive." })

Agent({ subagent_type: "general-purpose", model: "fable",
  prompt: "<evaluation prompt>\n\nStance: Challenge this design. Find weaknesses, missing considerations, contradictions, and risks. Propose specific corrections for each issue found. Score honestly; 'against' does not mean blindly negative." })
```

*Alternate route — PAL 2x GPT-Pro* (when Codex is unavailable and the structured
consensus flow is wanted; PAL tops out at gpt-5.5-pro):

```json
{
  "models": [
    {"model": "gpt-5.5-pro", "stance": "for", "stance_prompt": "Advocate for this design. Identify its strengths, explain why the decisions are sound, and argue that it should be approved. Be specific — cite exact decisions and explain their merit. Score honestly; 'for' does not mean blindly positive."},
    {"model": "gpt-5.5-pro", "stance": "against", "stance_prompt": "Challenge this design. Find weaknesses, missing considerations, contradictions, and risks. Propose specific corrections for each issue found. Score honestly; 'against' does not mean blindly negative."}
  ]
}
```

#### Alternate Configurations (PAL route)

**Architecture validation (3 models):**
```json
[
  {"model": "gpt-5.5-pro", "stance": "for"},
  {"model": "gpt-5.5-pro", "stance": "against"},
  {"model": "gemini-3.1-pro-preview", "stance": "neutral", "stance_prompt": "Provide an independent technical assessment. Focus on feasibility, risk, and alternatives the other evaluators may miss."}
]
```

**Bead readiness (2 models, specific stance prompts):**
```json
[
  {"model": "gpt-5.5-pro", "stance": "for", "stance_prompt": "Argue these beads are implementation-ready. Each bead should have: clear ACs in Given/When/Then, correct file paths, correct dependencies, no spec contradictions, and be self-contained."},
  {"model": "gpt-5.5-pro", "stance": "against", "stance_prompt": "Find beads that are NOT ready. Look for: vague ACs, wrong file paths, missing dependencies, contradictions between beads, beads too large for atomic implementation, cross-cutting requirements not embedded."}
]
```

### Step 3: Run Consensus (PAL route only)

Use the PAL MCP consensus tool. The tool manages the multi-step flow internally:

1. **Step 1 (your analysis):** Write the evaluation prompt and your own independent assessment
2. **Steps 2-N (model consultations):** Each model responds with its stance
3. **Final step (synthesis):** You synthesize all responses into a verdict

```
mcp__pal__consensus(
  step="Evaluate the following design for [topic]:\n\n[evaluation prompt]\n\n[relevant context]",
  step_number=1,
  total_steps=4,  // 1 (your analysis) + N models + 1 (synthesis)
  next_step_required=true,
  findings="[your independent analysis before seeing model responses]",
  models=[...],
  relevant_files=["/absolute/path/to/plan.md", ...]
)
```

### Step 4: Extract Corrections

From the synthesized consensus, extract:

1. **Score** (1-10) with breakdown by category
2. **Unanimous findings** — both FOR and AGAINST agree (highest confidence)
3. **Contested findings** — disagreement between stances (needs human judgment)
4. **Corrections** — specific, actionable changes to make

Format corrections as:

```markdown
## Oracle Consensus Results

**Overall Score:** 8/10
**Unanimous:** 3 findings | **Contested:** 1 finding | **Corrections:** 5

### Unanimous Findings
1. [Finding both stances agreed on]

### Corrections (ordered by impact)
1. **CRITICAL:** [correction] — Reason: [why]
2. **HIGH:** [correction] — Reason: [why]
3. **MEDIUM:** [correction] — Reason: [why]

### Contested
1. FOR says [X], AGAINST says [Y] — **Recommendation:** [your judgment]
```

### Step 5: Apply Corrections

For each correction:
1. Verify it against the original plan/code/beads
2. Apply if valid; reject with rationale if not
3. Track applied vs rejected corrections

### Step 6: Optional Re-validation

If corrections were extensive (5+ CRITICAL/HIGH), run a second oracle round on the corrected version. Use a shorter evaluation prompt focused on whether corrections were properly applied.

**Convergence criterion:** Stop when oracle score is 8+ AND zero CRITICAL corrections remain.

## Multiple Concurrent Oracles

For large targets (e.g., 80 beads across 10 epics), run parallel oracle sessions:

```
Oracle 1: Evaluate epics 1-3 (data model + safety)
Oracle 2: Evaluate epics 4-6 (UI + UX)
Oracle 3: Evaluate epics 7-10 (integration + testing)
Oracle 4: Evaluate cross-cutting concerns (deps, ordering, completeness)
```

Each oracle session is independent. Compile all corrections after all complete.

## Scoring Guide

| Score | Meaning | Action |
|-------|---------|--------|
| 9-10 | Excellent, minor polish only | Ship it |
| 7-8 | Good, specific corrections needed | Apply corrections, no re-validation needed |
| 5-6 | Significant issues | Apply corrections + re-validate |
| 1-4 | Fundamental problems | Redesign required |

## Example Invocations

```
/swarm-oracle foundation/product/features/sensor-plate-implementation-plan.md
/swarm-oracle "Should we split StationConfigurationVM into 5 VMs or 4?"
/swarm-oracle --rounds 2 .beads/  # validate all open beads, re-validate if needed
```
