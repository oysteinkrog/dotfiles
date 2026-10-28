---
name: swarm-oracle
description: Run 2x oracle sessions (FOR + AGAINST stances) to validate design decisions, plans, or bead readiness. Default = two GPT-6 Astra runs via Codex CLI (one per stance, one bounded prompt each); add two Fable subagents only for security-sensitive or contested validations, and use them as the fallback when Codex fails. Use after design rounds, before implementation, or to challenge architecture decisions.
argument-hint: "<topic or file to evaluate> [--rounds N]"
---

# Oracle Consensus

> **Oracle policy (2026-10-24, all reviews since 2026-10-28):** GPT-6 Astra is the
> primary oracle. The default FOR/AGAINST debate runs as two bounded Astra runs at
> effort `medium`, one per stance: one prompt of about 60k tokens each, with the diff
> and the needed excerpts pasted in, run from an empty directory with the shell tools
> off (see `/consult-oracles`, Bounded Astra run). Astra alone is the normal shape of
> a validation; no pairing is required.
> Fable is the **secondary oracle** (fresh `Agent` subagent, `model: "fable"`). Add a
> Fable FOR/AGAINST pair only when the validation is a security review, when the two
> Astra stances leave the call contested or one looks wrong, or when the user asks
> for a cross-provider opinion.
>
> Why: the three OpenAI accounts ended last week at about 26% to 31% with reset
> credits unused, while four Claude accounts hit 100%. If any OpenAI account passes
> 70% of its week before its reset, go back to Fable first.
>
> Effort stays `medium`. Use `high` only for one high-stakes question, and say why.
> Lesson from 2026-10-22: high-effort Astra reviews on whole repos used up all three
> OpenAI accounts in about 90 minutes. That is why the bounded prompt and medium
> effort are required. At most 4 Astra runs at once.
>
> **Availability fallback:** if Codex fails (auth error, rate limit, empty output), run
> the same FOR/AGAINST debate as two Fable subagents and state the substitution in the
> verdict. If Fable also fails, use Opus subagents (`model: "opus"`) and say so. Do not
> silently downgrade.
>
> **Gemini 4 Argon** (via PAL) is the optional third oracle but is currently
> unavailable: the AI Studio prepay credit ran out on 2026-10-21 and Oystein chose to
> leave it off. Do not plan around it.
>
> **Sensitive code:** Anthropic, OpenAI and Google are approved providers. Proprietary
> material can go to Astra, Fable and Gemini 4 Argon without asking first.
>
> **Cost rules:** short self-contained briefs, the needed excerpts pasted in, the
> change delta rather than the whole module, and one validation per change.

Run a structured FOR/AGAINST debate between two high-capability oracle sessions on a design decision, plan, or bead set. Produces a scored verdict with specific actionable corrections.

## When to Use

- After a design swarm to validate decisions
- Before committing to an architecture direction
- After bead creation to validate readiness
- When two approaches seem equally valid
- Any time "validate this with oracles" is requested

## Prerequisites

The default Astra tier needs Codex: confirm `codex` is on PATH and logged in. The Fable check needs nothing beyond the `Agent` tool. For the PAL route: verify PAL MCP is running before launching those oracles. If `mcp__pal__listmodels` fails or returns empty, alert the user, because agents silently fall back to self-analysis without PAL, producing unreliable results.

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

**Default tier (GPT-6 Astra):** run two bounded `codex exec` runs in a single message,
one FOR and one AGAINST. Each prompt file is self-contained: the evaluation prompt,
the stance, and the excerpts it needs pasted in with paths and line numbers (about
60k tokens at most). The two runs share no context. Astra is not reachable through
PAL, and the explicit tier ID is required (the bare `gpt-6` alias hangs). See the
`/codex` skill for prompting and exec pitfalls.

`medium` is the default effort. Use `high` only for one high-stakes question, and say
why. `xhigh`, `max` and `ultra` only when Oystein asks for them:

```bash
mkdir -p /var/tmp/claude/<task>/astra-empty && cd /var/tmp/claude/<task>/astra-empty
codex exec -m gpt-6-astra -c model_reasoning_effort=medium \
  --disable shell_tool --disable unified_exec --skip-git-repo-check \
  -o <scratchpad>/oracle-for.md - < <scratchpad>/prompt-for.md 2>/dev/null
codex exec -m gpt-6-astra -c model_reasoning_effort=medium \
  --disable shell_tool --disable unified_exec --skip-git-repo-check \
  -o <scratchpad>/oracle-against.md - < <scratchpad>/prompt-against.md 2>/dev/null
```

The prompt goes in on stdin (`- < file`); without a stdin source `codex exec` blocks
forever. The shell tools are off, so Astra answers from the pasted text only. `-o
<file>` captures the final message; an empty file after exit 0 means the run failed.
A stance answer that cites none of the pasted excerpts was given too little: add the
excerpt and rerun.

Then skip to Step 4 and synthesize the two responses yourself.

**Cross-provider check (Fable):** for security reviews, when the two Astra stances
leave the call contested or one looks wrong, or when Codex fails (auth error, rate
limit, empty output), spawn two fresh Fable subagents in one message, one FOR and one
AGAINST. Each prompt is self-contained; the two subagents share no context. Synthesize
all four responses, or the two Fable responses when Fable replaces a failed Codex run.

```
Agent({ subagent_type: "general-purpose", model: "fable",
  prompt: "<evaluation prompt>\n\nStance: Advocate for this design. Identify its strengths, explain why the decisions are sound, and argue that it should be approved. Be specific, cite exact decisions and explain their merit. Score honestly; 'for' does not mean blindly positive." })

Agent({ subagent_type: "general-purpose", model: "fable",
  prompt: "<evaluation prompt>\n\nStance: Challenge this design. Find weaknesses, missing considerations, contradictions, and risks. Propose specific corrections for each issue found. Score honestly; 'against' does not mean blindly negative." })
```

**Gemini 4 Argon (currently unavailable):** when it is back, a Gemini FOR/AGAINST pair
is two `mcp__pal__chat` calls with `model: "gemini-4-argon"`, `thinking_mode: "max"`
and the same two stance prompts.

*Alternate route, PAL 2x GPT-Pro* (when the structured consensus flow is wanted;
PAL tops out at gpt-5.5-pro):

```json
{
  "models": [
    {"model": "gpt-5.5-pro", "stance": "for", "stance_prompt": "Advocate for this design. Identify its strengths, explain why the decisions are sound, and argue that it should be approved. Be specific — cite exact decisions and explain their merit. Score honestly; 'for' does not mean blindly positive."},
    {"model": "gpt-5.5-pro", "stance": "against", "stance_prompt": "Challenge this design. Find weaknesses, missing considerations, contradictions, and risks. Propose specific corrections for each issue found. Score honestly; 'against' does not mean blindly negative."}
  ]
}
```

#### Alternate Configurations (PAL route)

**Architecture validation (3 models; needs Gemini 4 Argon, currently unavailable):**
```json
[
  {"model": "gpt-5.5-pro", "stance": "for"},
  {"model": "gpt-5.5-pro", "stance": "against"},
  {"model": "gemini-4-argon", "stance": "neutral", "stance_prompt": "Provide an independent technical assessment. Focus on feasibility, risk, and alternatives the other evaluators may miss."}
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

Each oracle session is independent and gets its own bounded prompt. Run at most 4
Astra runs at once. Compile all corrections after all complete.

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
