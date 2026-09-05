# TRIANGULATION.md — Multi-Model Verification

Phases 6 / 7 / 10 benefit from independent second opinions. Multi-model triangulation runs the same input through different models (Claude + Codex + Gemini + Grok) and aggregates the responses to surface disagreements.

This file specifies the protocol, prompt format, and aggregation.

---

## When to triangulate

Not every site needs three model reads — that's expensive and the marginal value drops fast. Triangulate when:

- A (C) classification has confidence < 0.7 (the planner agent itself is uncertain).
- A (A) classification has a steel-man attack that "feels under-explored."
- A site is on the soundness surface AND the proposed change is large (high blast radius).
- The Phase 7 fresh-eyes pass found a non-trivial issue and the fix is ambiguous.
- Phase 10 maintainer-empathy review wants independent confirmation.

The orchestrator picks the top N=5 (default; configurable per run) sites by these criteria.

---

## Prompt format (each model, independently)

```
You are a senior Rust engineer reviewing a proposed unsafe-to-safe refactor.

You are reviewing the site INDEPENDENTLY. You have NOT seen any other reviewer's
opinion. Do not anchor to a "consensus" answer.

CONTEXT
=======
Project: <project-name>
Crate: <crate>
Site: <site-id>
File: <file>:<line_range>
Inventory kind: <block | unsafe_fn | unsafe_impl | ...>

INVENTORY ROW
=============
<inventory JSONL row verbatim>

PER-SITE WRITE-UP
=================
<full audit/sites/<crate>/.../<site-id>.md contents>

CURRENT CLASSIFICATION
======================
<bucket A/B/C> with confidence <0.X>

JUSTIFICATION (from the classifier)
====================================
<full audit/classification/site-<id>.md contents>

PROPOSED PLAN
=============
<full audit/plans/site-<id>.md contents>

YOUR TASKS
==========

1. Bucket review.
   Do you agree with the (A) / (B) / (C) classification? If not, what bucket?
   Reasoning in 2-3 sentences.

2. Soundness review (if (C) plan).
   Read the proposed safe replacement code. Identify:
   a. Any UB the safe version might exhibit (use Rust knowledge — stacked borrows,
      provenance, alignment, atomicity, allocator identity).
   b. Any behavior-on-failure mismatch with the original unsafe (different panic,
      different error, different drop order).
   c. Any silent allocator identity change.
   d. Any panic-in-Drop or async-cancellation hazard.
   e. Any silent O() regression.

3. Falsification attack (if (A) plan).
   Read the falsification justification. Construct your STRONGEST steel-man for a
   safe alternative. If the steel-man defeats the justification, propose a
   reclassification.

4. Test review (if equivalence test is in the plan).
   Does the property-based test cover the failure modes the original handled?
   List any input class the test misses.

OUTPUT FORMAT
=============

```yaml
bucket_agreement: <yes | no, change-to-B | no, change-to-C | no, change-to-A>
bucket_reasoning: |
  <2-3 sentences>

soundness_issues:
  - severity: <critical | high | medium | low>
    location: <line in proposed safe code>
    issue: <one-line>
    fix_suggestion: <one-line>
  # ... more entries ...

falsification_attacks:
  - alternative: <name + 1-sentence sketch>
    survives_original_rebuttal: <yes | no>
    reasoning: <2-3 sentences>

test_coverage_gaps:
  - <input class the property test misses>

overall_recommendation:
  confidence_in_current_plan: <Low | Medium | High>
  next_step: <land-as-is | refine-plan | reclassify | reject>
  notes: |
    <free-form follow-up>
```
```

The prompt is sent to each model; each model produces its own YAML response.

---

## Aggregation

The orchestrator collects all responses and writes
`<audit-dir>/audit/phase10/triangulation/site-<id>__triangulation.md`:

```markdown
# Site <id> — Multi-Model Triangulation

## Bucket agreement

| Model | Bucket | Reasoning |
|-------|--------|-----------|
| Claude (Opus 4.7) | (C) | ... |
| Codex (gpt-5.5)   | (C) | ... |
| Gemini Ultra      | (B) | "I think the perf cost might be higher than the budget allows..." |
| Grok              | (C) | ... |

**Consensus.** 3/4 (C). Gemini dissents toward (B).
**Action.** Per ORCHESTRATION.md § Multi-model triangulation, dissent triggers a Phase 5 re-measurement of perf to settle the (B) vs (C) question.

## Soundness issues (union of all models)

| Severity | Location | Issue | Suggested fix | Surfaced by |
|----------|----------|-------|---------------|-------------|
| high | rewrite.rs:42 | Panic in `?` propagation leaks `mmap`ed pointer | Use a guard struct | Codex |
| medium | rewrite.rs:67 | Drop-glue runs in different order from original | Document order explicitly | Gemini |

**Action.** Refine plan per the union. The next planner-agent pass picks these up.

## Falsification attacks

(N/A — site is (C); falsification attacks only apply to (A))

## Test coverage gaps

| Gap | Surfaced by |
|-----|-------------|
| Test doesn't cover zero-length input | Claude |
| Test doesn't cover input that exhausts the bounded queue | Grok |

**Action.** Equivalence-prover agent extends the property test.

## Aggregate recommendation

- Confidence (weighted by individual model confidence): Medium
- Next step: refine plan + extend test, then re-triangulate on revised plan (one round)
- Notes: Gemini's (B) dissent is the main signal; resolving it via re-measurement is cheap and removes the ambiguity.
```

---

## Single-model fallback

When only Claude is available (no `/multi-model-triangulation`), simulate multi-model by running multiple Claude passes with DIFFERENT priming:

```
Pass 1 — LITERAL READER
"Read the plan strictly. Take every statement at face value. Look for what is
LITERALLY written that is wrong, irrespective of intent."

Pass 2 — SKEPTICAL READER
"Read the plan as a skeptical security reviewer. Where is the author taking a
shortcut? Which assumption carries the soundness argument without a citation
to back it?"

Pass 3 — JUNIOR ENGINEER READER
"Read the plan as if you're a junior engineer encountering this code for the first
time. What confuses you? Where are the unstated invariants?"

Pass 4 — ADVERSARIAL READER
"Read the plan as if you are trying to break it. Construct the most damaging input,
the most awkward race, the most obscure trigger. What does it do to the system?"
```

The four passes produce four perspectives. Aggregate the same way as multi-model — but acknowledge in the output that this is single-model triangulation, lower signal than true multi-model.

---

## Manual multi-model (API keys, no skill)

If the user has OpenAI / Gemini / xAI API keys but `/multi-model-triangulation` isn't installed, run direct API calls:

```bash
# OpenAI
curl -s https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg prompt "$(cat triangulation_prompt.txt)" \
    '{model:"gpt-5.5",messages:[{role:"user",content:$prompt}]}')" \
  | jq -r '.choices[0].message.content' > codex_response.md

# Gemini
curl -s "https://generativelanguage.googleapis.com/v1/models/gemini-ultra:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg prompt "$(cat triangulation_prompt.txt)" \
    '{contents:[{parts:[{text:$prompt}]}]}')" \
  | jq -r '.candidates[0].content.parts[0].text' > gemini_response.md

# xAI / Grok (per their current API)
curl -s https://api.x.ai/v1/chat/completions \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg prompt "$(cat triangulation_prompt.txt)" \
    '{model:"grok-3",messages:[{role:"user",content:$prompt}]}')" \
  | jq -r '.choices[0].message.content' > grok_response.md
```

Then aggregate the same way as the skill would.

---

## Cost discipline

Multi-model triangulation is expensive — 4 models × ~10K tokens of context per site × N sites. For a 200-site audit, triangulating all sites would cost ~8M tokens per model.

Budget per audit (default):
- Top 5 sites: full triangulation across 4 models.
- Top 5–20 sites: dual-model (Claude + one other).
- Below top 20: single-model (Claude); flagged for triangulation if Phase 6 surfaces a dissent.

Cost projection in `<audit-dir>/phase0_cost_estimate.md`. The user approves before triangulation runs.

### Concrete cost projection

Token math (per site):

| Component | Tokens | Notes |
|-----------|--------|-------|
| Per-site write-up (input) | ~3,500 | The site's `.md` + surrounding context |
| Operator card library (input) | ~2,000 | Trimmed to relevant operators |
| Classification rubric (input) | ~1,500 | The kernel-bounded section |
| Site source + surrounding code | ~2,000 | Enough context to reason |
| Cumulative model output (one response) | ~1,500 | Bucket + justification + dissent rationale |
| **Per-site-per-model total** | **~10,500 tokens** | Round to 10K for projection |

Dollar estimate per model (US$, late-2025 published prices, approximate — verify before final):

| Model | Input price | Output price | Per-site-per-model | Per-site (4-model triangulation) |
|-------|-------------|--------------|---------------------|-----------------------------------|
| Claude Opus | $15 / 1M in | $75 / 1M out | $0.13 + $0.11 = **$0.24** | (only one of 4) |
| Codex (GPT-5.5) | $10 / 1M in | $30 / 1M out | $0.09 + $0.045 = **$0.13** | — |
| Gemini Ultra | $7 / 1M in | $21 / 1M out | $0.06 + $0.03 = **$0.09** | — |
| Grok 4 | $5 / 1M in | $15 / 1M out | $0.045 + $0.022 = **$0.07** | — |
| **4-model total per site** | — | — | — | **~$0.53** |

### Projections by audit size

| Audit size | Triangulation depth | Sites × $0.53 | + dual-model | + single-model | **Total estimate** |
|------------|---------------------|---------------|--------------|----------------|--------------------|
| Small (≤ 20 sites) | Top 5 quad + top 15 dual | $2.65 | $1.95 | $0 | **~$5** |
| Medium (50 sites) | Top 5 quad + top 15 dual + 30 single | $2.65 | $1.95 | $3.90 | **~$8.50** |
| Large (200 sites) | Top 5 quad + top 15 dual + 180 single | $2.65 | $1.95 | $23.40 | **~$28** |
| Polyrepo (1000 sites) | Top 10 quad + top 30 dual + 960 single | $5.30 | $3.90 | $124.80 | **~$134** |

These are upper bounds — actual usage runs lower because:
1. Prompt caching reduces input cost for repeated context (the operator library, the rubric).
2. Many sites cluster — once one site in a cluster is triangulated, the others get the same verdict.
3. Phase 4 / 6 convergence usually exits before exhaustive triangulation runs.

### When the cost is justified

- Pre-release-soundness-gate runs: yes, triangulate the top 20 sites.
- Routine audit-only of a 50-site lib: triangulate top 5 only; budget ~$3.
- Continuous-mode drift check: usually no triangulation; flagged only if drift surfaces dissent.

### Cost-saving tactics

1. **Prompt caching** — feeding the operator library + rubric as cached prefix reduces input cost by ~80% on calls 2+. Per Anthropic's caching pricing.
2. **Sequential, not parallel, on first pass** — if Claude's verdict matches the classifier's, skip the other 3 models entirely.
3. **Cluster-then-triangulate** — triangulate one representative per cluster, propagate the verdict to siblings.
4. **Cap by budget** — set a hard $20 ceiling per audit run by default; raise per-audit if the project asks.

The `--triangulation-budget <USD>` flag (added in skill version 2026.05) caps total spend; the orchestrator skips lower-priority sites when the cap is reached.

---

## Honest reporting

The audit summary line includes the triangulation depth:

```
Triangulation: top-5 sites verified across 4 models (Claude / Codex / Gemini / Grok);
top-15 dual-verified (Claude + Codex); remainder single-model. Dissents resolved: 2.
```

If only single-model was run, the line says so:
```
Triangulation: single-model only (Claude, with 4-perspective priming pass on top-10 sites).
```

The user reads this and calibrates their merge confidence accordingly.
