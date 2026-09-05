# Skill Fallbacks

The skill orchestrates multiple helper skills (`/operationalizing-expertise`, `/codebase-archaeology`, etc.). When one is missing, *fall back inline* — never block a phase on a missing skill.

---

## Detection

`scripts/check-skills.sh` writes `phase0_skill_inventory.json`:

```json
{
  "installed": ["operationalizing-expertise", "codebase-archaeology", "ubs", "agent-mail", "br"],
  "missing": ["security-audit-for-saas", "multi-pass-bug-hunting", "multi-model-triangulation"],
  "jsm_available": true,
  "jsm_authenticated": false
}
```

If `jsm_available` AND `jsm_authenticated`, propose `jsm install <name>` for each missing skill. If not, fall back inline.

---

## Per-skill fallback playbooks

### `/operationalizing-expertise` — Track A (missing)

Inline fallback: when distilling a project's billing patterns into a kernel for the project's docs, write the kernel by hand using the format from `references/source/SOURCE-INDEX.md`. Tag every claim with a file:line citation.

### `/codebase-archaeology` (missing)

Inline fallback: use the Phase 1 prompt in [AGENT-PROMPTS.md § Archaeologist](AGENT-PROMPTS.md#phase-1--archaeologist) directly. The pattern is documentation-first → entry-points → data-flow → key-types → integration-points. Always start with `cat AGENTS.md README.md package.json | head -200` before diving into code.

### `/codebase-report` (missing)

Inline fallback: produce `.billing_workspace/phase1_codebase_report.md` using this template:

```markdown
# Project codebase report (billing scope)

## Project at a glance
- Type: [Next.js App Router / ...]
- Lines of billing code: ~N
- Providers: [stripe, paypal]
- Key services: [list each src/lib/services/ file relevant to billing]

## Architecture sketch
[ASCII / mermaid showing webhook → handler → state mutator → side effects]

## Top 5 things a new contributor must know
1. [the most surprising design decision]
2. ...
```

### `/multi-pass-bug-hunting` (missing)

Inline fallback: Phase 7 fresh-eyes IS the multi-pass bug hunting workflow. Use the three calibrated prompts verbatim from [AGENT-PROMPTS.md § Phase 7](AGENT-PROMPTS.md#phase-7--fresh-eyes-verbatim-calibrated). Iterate until two consecutive rounds are clean.

### `/multi-model-triangulation` (missing)

Inline fallback: skip the multi-model fanout in Phase 7 Round D. Run only Claude rounds A/B/C. Annotate the run as "single-model triangulation skipped" in the workspace; the user can re-run later when the skill is available.

If the user has both `codex` and `gemini` CLIs installed but no triangulation skill, you can hand-roll a fanout: write the same prompt to both via shell pipes (`echo "..." | codex --json | jq` and similar) and reconcile yourself. See [TRIANGULATION.md](TRIANGULATION.md) for the consensus rules.

### `/security-audit-for-saas` (missing)

Inline fallback: the patterns in `references/patterns/50-SECURITY.md` already incorporate the SA-01..SA-22 findings from the source guide. For Phase 7's security-reviewer subagent, use the prompt in [AGENT-PROMPTS.md § Phase 7 Round C](AGENT-PROMPTS.md#round-c--fellow-agent--adversarial-lens) which lists the explicit focus areas.

If the user has *the source-guide reference doc* available (`COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md` at the repo root or local copy), § 78a is the canonical security cross-reference list. Read it during Phase 3 risk-scoring.

### `/saas-customer-analytics` (missing)

Inline fallback: the patterns in `references/patterns/100-ANALYTICS.md` already cover MRR snapshot, churn, fees, health scoring, forecasting, runway. For B100 Phase 5, the implementer subagent has enough to work from.

### `/ubs` — Ultimate Bug Scanner (missing)

Inline fallback: skip the `ubs` Phase 7 step. Use the project's existing linter (`tsc --noEmit`, `eslint`, `ruff`, `clippy`, etc.) as the static-analysis gate.

### `/ru` — Multi-Repo Workflow (missing)

Not needed for this skill (single-repo focus).

### `/agent-mail` (missing)

Inline fallback: Squad/Swarm tier requires Agent Mail for coordination. If missing AND the user's running multi-worker, either:
- Drop to Solo/Pair tier (single worker per bundle, sequential).
- Coordinate via filesystem (lockfiles like `.billing_workspace/.lock_<file>`) — primitive but works.

### `/beads-br` — Beads (missing)

Inline fallback: skip the `br create` calls in Phase 4. Maintain the task graph in `phase4_implementation_plan.md` as a markdown table. Workers manually claim by editing the table (with a file reservation).

### `/vercel`, `/supabase`, `/stripe-checkout`, `/e2e-testing-for-webapps`, `/testing-real-service-e2e-no-mocks` (missing)

These are "platform expertise" skills that this skill leverages but doesn't strictly require. If missing, the implementer subagents work from the relevant source-guide section directly.

### `/idea-wizard` (missing)

Not used by this skill's core flow. Optional Phase 3 enhancement only.

---

## jsm installer

```bash
# Linux/macOS
curl -fsSL https://jeffreys-skills.md/install.sh | bash

# Windows (PowerShell)
irm https://jeffreys-skills.md/install.ps1 | iex
```

After install:

```bash
jsm login
# Browser opens for OAuth; or use --headless for SSH sessions
```

```bash
# Bulk install all the skills referenced by this skill
./scripts/install-referenced-skills.sh .billing_workspace
```

The bulk installer reads `phase0_skill_inventory.json`, picks the missing list, and runs `jsm install <name>` for each. Failures are logged but don't abort.

---

## When to refuse vs. fall back

- **Refuse**: if the user explicitly asks for a feature that *requires* a skill we don't have a fallback for. Example: "Run the multi-model triangulation now" when neither `multi-model-triangulation` nor `codex`/`gemini` CLIs are installed. Answer: "We can't run multi-model triangulation right now. Your options: (a) install codex + gemini and re-run; (b) skip Round D and accept single-model review."
- **Fall back**: if the missing skill is one of many sources for the same outcome. Example: missing `/codebase-archaeology` → use the inline Phase 1 prompt; the outcome is the same artifact.

The default is **fall back, don't block**. Surface the missing skill in the phase summary so the user knows what they got vs. what they would have gotten with the full toolkit.
