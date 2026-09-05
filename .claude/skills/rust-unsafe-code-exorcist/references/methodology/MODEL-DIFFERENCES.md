# MODEL-DIFFERENCES.md — Haiku / Sonnet / Opus

This skill is designed to trigger correctly across the Claude model family, including smaller models that need more explicit signals. This file documents per-model behavior + when to use which.

---

## At a glance

| Model | Best for | Typical use in this skill |
|-------|----------|---------------------------|
| **Haiku** | Fast trigger / classification helpers | Subagent for routine enumeration; fast risk-score; bead-converter |
| **Sonnet** | Most subagent work | Default orchestrator; per-site analyzer; refactor planner; classifier passes |
| **Opus** | Highest-judgment tasks | Phase 6 adversarial reclassifier; Phase 10 maintainer-empathy reviewer; multi-model triangulation lead |

---

## Per-model trigger reliability

The skill's frontmatter description is calibrated for Haiku-level trigger reliability. To verify:

```
Type each of these in Claude Code:
  "Audit my unsafe code." (high subtlety)
  "Run the rust-unsafe-code-exorcist." (low subtlety, explicit)
  "I want to remove unsafe from my Rust crate." (medium subtlety)
```

All three should activate the skill regardless of model. If Haiku misses the first phrase but Sonnet+ catches it, the description needs more explicit triggers.

---

## Per-task model recommendations

### Phase 1 — Enumerate

**Best model: Haiku** (or Sonnet for safety).

Enumeration is structured: run ast-grep, parse output, emit JSONL. No subtle judgment required. Haiku's speed pays off if you have many crates.

Override to Sonnet if:
- The project uses extensive `cargo expand` output that needs interpretation (rare; the script handles it).
- The crate has unusual file organization the enumerator might confuse.

### Phase 2 — Per-site write-up

**Best model: Sonnet.**

The write-up needs to NAME invariants ("sound IFF X") and TRACE the call graph. Haiku can do this but tends to be terser; Sonnet's slightly richer interpretation produces more useful per-site write-ups.

### Phase 3 — Synthesize

**Best model: Sonnet.**

Cross-site invariant clustering needs holistic vision. Haiku is too local; Opus is overkill.

### Phase 4 — Classify

**Best model: Sonnet (for iteration speed); Opus on the FINAL pass.**

Most classifier passes are Sonnet (cost-effective; converges fast). The final pass — when you want maximum confidence on the (A) bucket — should be Opus, because the falsification justification is the artifact the rest of the audit's confidence rests on.

### Phase 5 — Plan-draft

**Best model: Sonnet for the drafts; Opus for review.**

Plan-drafts are constructive (write the safe code; sketch the test). Sonnet excels. The optional review pass by Opus catches bugs.

### Phase 6 — Adversarial reclassifier

**Best model: Opus, ideally different model entirely (multi-model triangulation).**

Adversarial work needs Opus-level judgment. The whole POINT of Phase 6 is "challenge the classification with the strongest plausible attack." Opus's nuance + multi-model triangulation (Codex / Gemini / Grok) catches what Sonnet would accept.

### Phase 7 — Fresh-eyes review

**Best model: Opus, ideally different model from prior phases.**

Same reasoning as Phase 6. The three verbatim review prompts are calibrated for Opus-level depth.

### Phase 10 — Maintainer-empathy review

**Best model: Opus, ideally different model from prior phases.**

A fresh-context, judgment-heavy read. Opus is the right tool.

### Specialty subagents

| Subagent | Best model | Why |
|----------|-----------|-----|
| cass-miner | Haiku | Search + summarize, no novel judgment |
| exemplar-miner | Haiku → Sonnet | Read repos + extract; Sonnet for richer extraction |
| archeologist | Sonnet | Mining + interpretation |
| classifier | Sonnet (Opus for final pass) | Iteration speed |
| refactor-planner | Sonnet | Constructive |
| equivalence-prover | Sonnet | Test generation |
| adversarial-reclassifier | Opus | Judgment |
| fresh-eyes-reviewer | Opus | Judgment |
| harness-builder | Haiku → Sonnet | Mostly mechanical |
| bead-converter | Haiku | Pure transformation |
| maintainer-empathy-reviewer | Opus | Judgment-heavy |
| multi-model-triangulator | Sends to Codex + Gemini + Grok | External coordination |
| idea-generator | Opus | Creative |
| safety-comment-author | Sonnet | Writing + citation |
| allocator-identity-auditor | Sonnet | Pattern recognition |
| panic-boundary-auditor | Sonnet | Pattern recognition |
| api-stability-reviewer | Sonnet | Diff analysis |
| upstream-issue-filer | Sonnet | Drafting prose |
| regression-test-author | Sonnet | Test generation |
| changelog-writer | Sonnet | Drafting |
| kani-prover | Opus | Symbolic reasoning |
| active-checkout implementer (`worktree-implementer.md` legacy filename) | Sonnet | Constructive |
| pin-projection-auditor | Sonnet | Pattern recognition |
| drift-detector | Haiku | Pure diff |
| risk-scorer | Sonnet | Heuristic + refinement |
| inverse-auditor | Sonnet | Test generation |
| contract-verifier | Sonnet | Verification |
| test-generator | Sonnet | Test generation |
| security-md-author | Sonnet | Drafting |

---

## When to upgrade or downgrade

### Upgrade to Opus when

- The audit is for a high-stakes crate (security, kernel, runtime).
- A specific (A) classification was challenged by maintainer review.
- Multi-model triangulation surfaced conflicting opinions.
- An incident is being responded to (every classification matters).

### Downgrade to Haiku when

- The audit is exploratory (triage mode).
- Iterating on classification for fast convergence.
- Cost-sensitive (Haiku is ~10x cheaper than Opus for similar throughput on routine work).

### Mixed-model audits

Most audits should mix models intentionally:
- Sonnet for the 90% of routine work (enumeration, drafting, mechanical).
- Opus for the 10% of judgment-heavy moments (Phase 6 + 7 + 10, kani, multi-model lead).
- Haiku for the trivial-but-many tasks (drift checks, bead conversions, cass mining).

Cost projection per audit (rough):
- All-Sonnet: ~3 hours of Sonnet equivalents = baseline.
- Mixed (Haiku/Sonnet/Opus): ~70% Sonnet + 20% Opus + 10% Haiku = ~1.5x baseline cost but 2x quality on high-stakes judgments.
- All-Opus: ~10x baseline cost; usually overkill.

---

## Per-model "Use when" trigger details

When you (or the orchestrator) start a subagent, pass the explicit model:

```
Agent(
  description: "Classify site cluster R-001",
  subagent_type: "Sonnet",
  prompt: "...verbatim from AGENT-PROMPTS.md..."
)
```

The model parameter governs both:
- The MODEL the subagent runs as.
- The COST of the subagent's work.
- The TIME the subagent takes (Haiku ~2x faster than Sonnet ~2x faster than Opus, very roughly).

---

## Per-model failure modes

### Haiku failure modes

- **Misses subtle triggers** in the description. (Why we test triggers on Haiku specifically.)
- **Truncates rich context** sometimes. For 50K+ token write-ups, prefer Sonnet.
- **Overconfident on simple classifications.** Add a Sonnet+ verification pass on the final classification.

### Sonnet failure modes

- **Can miss adversarial framings.** Phase 6 should use Opus or multi-model.
- **Defaults to plausible-sounding classifications without deep justification.** The falsification block forces explicit reasoning.

### Opus failure modes

- **Sometimes over-elaborates.** Use a polish-bar checker (per [POLISH-BAR.md](POLISH-BAR.md)) to enforce structure.
- **Cost.** Mitigate by reserving for high-stakes phases only.

---

## Multi-model triangulation in detail

When the audit hits high-stakes sites (top-5 by risk score; pre-release-gate mode; etc.), spawn:

1. **Claude Opus** — the primary reviewer.
2. **Codex (GPT-5.5 or later)** — different model family.
3. **Gemini Ultra** — different organization.
4. **Grok 3** — different organization.

Each gets the SAME materials (write-up + classification + plan + tests). Each produces independent verdicts. Synthesis catches blind spots that any single model would miss.

Per [TRIANGULATION.md](TRIANGULATION.md), the orchestrator aggregates + flags dissents.

---

## What this file is NOT

- Not a complete model reference. See https://docs.claude.com/ for model specs.
- Not a cost optimizer. Use judgment per-task based on stakes.
- Not a definitive ranking. Models evolve; this guide reflects today's capabilities.

If new Claude models ship (4.7, 4.8, etc.), update this file's model-to-task mapping based on the new model's strengths.

---

## Smoke test (you should do this)

```
1. Open Claude Code in a Rust project.
2. Set model to Haiku: /model haiku
3. Type: "Audit my unsafe code with the rust-unsafe-code-exorcist."
4. The skill should activate.
5. Switch to Sonnet: /model sonnet
6. Repeat. Should activate.
7. Switch to Opus: /model opus
8. Repeat. Should activate.

If any of these miss, file feedback so the description gets refined.
```

For details on testing trigger phrases: [TESTING.md](TESTING.md).
