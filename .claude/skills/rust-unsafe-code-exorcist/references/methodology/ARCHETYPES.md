# ARCHETYPES.md — Where This Skill Fits in the Public Skill-Shape Taxonomy

This package uses a public, implementation-neutral taxonomy for agent skills:

| Archetype | Example | When this skill plays it |
|-----------|---------|--------------------------|
| **CLI Archetype** | How to use a CLI / API / library | When invoked for "show me how to run miri / loom / kani correctly." |
| **Methodology Archetype** | Code review / PR workflow / deployment | When invoked for "audit this project per the rust-unsafe-code-exorcist methodology." |
| **Safety Archetype** | Pre-commit checks / migration safety | When invoked as `pre-release-soundness-gate` mode. |
| **Orchestration Archetype** | Initializer spawns workers | The default flow: orchestrator spawns enumerator + classifier + ...; multi-phase loop. |
| **Data Domain Archetype** | DB schemas / analytics / domain knowledge | When invoked with domain overlays (cryptography-audit, etc.). |

The skill is a **hybrid Methodology + Orchestration archetype**, with optional domain-overlays. The methodology defines WHAT to do; the orchestration defines HOW the agents coordinate to do it.

---

## Methodology archetype features

Agent-facing methodology skills should have:

| Methodology feature | This skill's instance |
|---------------------|------------------------|
| Step-by-step playbook | [PHASES.md](PHASES.md) — 10 phases with exit criteria |
| Decision rubric | [CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md) — (A)/(B)/(C) with falsification tests |
| Mode router | [OPERATING-MODES.md](OPERATING-MODES.md) — 7 base modes + fast-track variants |
| Quality bar | [POLISH-BAR.md](POLISH-BAR.md) — 12 dimensions per site |
| Anti-patterns | [SKILL.md § Anti-Patterns](../../SKILL.md) + per-pattern bundles |
| Validation | [TOOLCHAIN-RUNBOOK.md](TOOLCHAIN-RUNBOOK.md), `verify.sh`, `validate-corpus.py`, `validate-operators.py` |
| Examples | [COOKBOOK.md](COOKBOOK.md) — 12 paste-ready recipes |

---

## Orchestration archetype features

Agent-facing orchestration skills should have:

| Orchestration feature | This skill's instance |
|-----------------------|------------------------|
| Initializer agent | The orchestrator (described in [KICKOFF-PROMPTS.md](KICKOFF-PROMPTS.md)) |
| Worker agents | [subagents/*.md](../../subagents/) — 32 specialized agents |
| Coordination | MCP Agent Mail file reservations + thread IDs per [ORCHESTRATION.md](ORCHESTRATION.md) |
| Tier scaling | Solo / Pair / Squad / Swarm tiers in [ORCHESTRATION.md § Tier shapes](ORCHESTRATION.md) |
| Convergence detection | Phase 4 + Phase 6 iterative-until-quiet rules |
| Failure recovery | [ORCHESTRATION.md § Failure / recovery](ORCHESTRATION.md) |
| Per-agent prompts | [AGENT-PROMPTS.md](AGENT-PROMPTS.md) — verbatim per-subagent |

---

## Why the hybrid?

A pure methodology skill would tell the user WHAT to do; the user does it manually. A pure orchestration skill would coordinate agents but lack domain knowledge.

The hybrid does both:

1. **Methodology layer.** The user (or another agent) reads the methodology to understand the goal. The classification rubric, operators, polish bar are the durable knowledge.

2. **Orchestration layer.** The skill knows how to spawn the right subagents at the right times, coordinate them via Agent Mail, detect convergence, handle failures.

Either layer is useful standalone; together they enable a single user prompt to produce a defensible audit.

---

## Safety archetype features

The safety archetype covers guardrails, validation, and migration safety. This skill plays the safety archetype in specific contexts:

- **Pre-release-soundness-gate mode.** The strictest gate; no `cargo publish` until verify.sh + gate criteria pass.
- **CI integration.** [CI-INTEGRATION.md](CI-INTEGRATION.md) — per-PR gates: geiger regression, new unsafe without SAFETY comment, harness regression.
- **Continuous mode.** [CONTINUOUS-MODE.md](CONTINUOUS-MODE.md) — drift detection prevents soundness debt accrual.
- **Active-checkout refactor protocol.** [WORKTREE-REFACTOR-PROTOCOL.md](WORKTREE-REFACTOR-PROTOCOL.md) — legacy filename; discipline ensures no destructive ops, no git worktrees, no scope creep.

When the user asks "make sure my unsafe doesn't regress," the skill plays the safety archetype.

---

## Data domain archetype features

The data-domain archetype covers structured domain knowledge and domain-specific overlays. This skill plays the data-domain archetype via:

- **Domain overlays.** [DOMAIN-MODES.md](DOMAIN-MODES.md) + per-overlay pattern bundles ([100-CRYPTOGRAPHY-AUDIT.md](../patterns/100-CRYPTOGRAPHY-AUDIT.md), [130-TAGGED-POINTER-MIGRATION.md](../patterns/130-TAGGED-POINTER-MIGRATION.md), more in [IDEAS.md](IDEAS.md)).
- **Exemplar catalog.** [EXEMPLAR-CATALOG.md](../source/EXEMPLAR-CATALOG.md) — 43+ `[E-NNN]` canonical patterns from 10 reference Rust projects.
- **Failure case catalog.** [COMMON-FAILURE-CASES.md](COMMON-FAILURE-CASES.md) — F-001..F-016 with symptoms + fixes.

When the user asks "audit my cryptography crate," the skill plays the data-domain archetype with the crypto overlay.

---

## CLI archetype features

The CLI archetype covers how to use a CLI, API, or library. This skill plays a small CLI role:

- **TOOLCHAIN-RUNBOOK.md.** Per-tool invocation + flag explanations.
- **QUICK-REFERENCE.md.** Cheat sheet for the audit's commands.
- **Per-script docstrings.** Each script in `scripts/` has a usage line.

When the user asks "how do I run `cargo +nightly miri test --features safe-only`," the skill plays the CLI archetype (briefly; details in [TOOLCHAIN-RUNBOOK.md](TOOLCHAIN-RUNBOOK.md)).

---

## How the archetype affects skill structure

Recommended structures per archetype:

- **CLI.** Single SKILL.md; references go to per-command flags.
- **Methodology.** SKILL.md + decision rubric + multi-phase playbook + worked examples.
- **Safety.** SKILL.md + validation script + clear "what to check" criteria.
- **Orchestration.** SKILL.md + per-subagent prompt files + coordination doc.
- **Data domain.** SKILL.md + structured data / examples / catalog.

This skill has all of these. The body is long because it's hybrid; the references, pattern bundles, subagents, assets, and scripts are split so agents can load only the layer they need.

The trade-off: large overall, but progressively disclosed. Most readers start at SKILL.md + 1-2 references for their immediate need.

---

## Implications

Because this skill plays multiple archetypes:

- A user can invoke it for any of: audit, classification, refactoring, CI integration, continuous monitoring, SECURITY.md generation, etc.
- The skill's frontmatter description must trigger on all those use cases (currently: "Audit and refactor every `unsafe` in a Rust project. Use when auditing unsafe, removing unsafe, soundness review, FFI hardening, SIMD safe-only feature flag, or 'exorcise unsafe'.").
- The mode router routes by user intent; the orchestrator picks the right subagents per mode.

A user who's only doing a quick triage doesn't read the full methodology — they hit the `triage` fast-track. A user who's doing pre-release gating reads the full methodology + the safety patterns. Same skill; different reader paths.

---

## Compared to other hybrids

Other Claude Code skills with similar archetype-hybrid shape:

- **saas-billing-patterns-for-stripe-and-paypal** — methodology + orchestration + data-domain (78 pattern sections + 31 subagents).
- **wills-and-estate-planning-skill** — methodology + data-domain + safety (estate-planning kernel + 18 operators).
- **documentation-website-for-software-project** — methodology + orchestration (10 phases + 11 subagents).

This skill follows the same pattern: hybrid archetype for a complex audit lifecycle.
