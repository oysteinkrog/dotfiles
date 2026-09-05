# COMPARISON.md — How This Skill Compares To Alternatives

<!-- TOC: vs manual code review | vs JIRA/Linear status hygiene | vs Mayhem/Daikon/dynamic analyzers | vs spec-side AI tools | vs human auditor | When to use what -->

> The bead-completion-verification problem isn't unique to this skill. Manual code review, JIRA workflow checks, fuzz infrastructure, and human compliance auditors all attack adjacent versions. This file maps the landscape and explains where this skill's contribution sits.

---

## vs manual code review

| Aspect | Manual code review | This skill |
|--------|-------------------|------------|
| Subject | Code diff at PR time | Bead state across the entire history |
| Frequency | Per PR | Per audit pass (weekly / monthly) |
| Scope | One change | The whole bead universe |
| Determinism | Subjective; depends on reviewer | Deterministic per rubric |
| Catches stub implementations | Sometimes (if reviewer notices) | Always (Phase 5) |
| Catches false closes after merge | No (PR is closed) | Yes |
| Cost per audit | Hours of human attention | Minutes of agent + token cost |
| What it can't do | Track bead-graph integrity | Replace human judgment on architecture / design |

**When to use which:** Use code review for quality at merge time. Use this skill for graph integrity over time. They compose — code review prevents new false-closes, this skill catches the ones that slipped through.

---

## vs JIRA / Linear / GitHub Issues workflow

| Aspect | JIRA/Linear/GH workflow | This skill |
|--------|-------------------------|------------|
| Status semantics | "Done" means whatever the team agrees | "Closed" must be evidence-verifiable |
| Verification step | None enforced | Phase 4 re-runs proofs |
| Cross-issue integrity | Manual ("Bob said it's done") | Phase 7 synthesis |
| Score | None — binary done/not-done | 0-1000 with cited evidence |
| Failure detection | Retrospective via QA / customer reports | Proactive via audit pass |
| Tool integration | Webhooks, custom fields, dashboards | Reads bead store directly |
| Audit trail | Activity log (who changed what) | Full evidence pack per bead |

**Key difference:** JIRA's "Definition of Done" is *aspirational*; this skill makes "done" *empirically verifiable*. Without verification, every "Done" issue is a hypothesis.

---

## vs dynamic analyzers (Mayhem, Daikon, fuzzers)

| Aspect | Dynamic analyzer | This skill |
|--------|-----------------|------------|
| Subject | Running code | Bead claims about code |
| Discovers bugs | Yes, novel ones | No — verifies known claims |
| Discovers theater | Indirectly (crashes reveal stubs) | Directly (Phase 5 patterns) |
| Per-issue accountability | No (bugs aren't tied to issues) | Yes (per-bead scoring) |
| Cross-issue gaps | No | Yes (Phase 7 synthesis) |
| What it adds | Novel bug discovery | Bead-graph truthfulness |

**Compose:** Dynamic analyzers find new bugs. When they file the bug as a bead, this skill verifies that the closure of that bead is real.

---

## vs spec-side AI tools (specdriven, AI-assisted code review)

| Aspect | Spec-side AI tool | This skill |
|--------|-------------------|------------|
| Input | Spec / requirement / user story | Bead body (which IS the spec) |
| Output | "Did the implementation match the spec?" | Same question, but at scale, with evidence pack |
| Determinism | LLM-judgment | Deterministic rubric + LLM-augmented operators |
| Multi-agent | Usually no | Yes (subagents per phase) |
| Cross-issue | Usually no | Yes (Phase 7) |
| Audit trail | Usually transient | Persistent + git-tracked |

**Key contribution of this skill:** the **discipline** — operator pipelines, marker-bounded artifacts, persistent evidence packs, convergence semantics. AI-assisted spec-checking is a single-shot Q&A; this is a sustained verification loop.

---

## vs human compliance auditor

| Aspect | Human auditor | This skill |
|--------|--------------|------------|
| Cost | $$$ (consulting day rate × N days) | Tokens (cents per bead) + setup time |
| Coverage | Sample-based (a few items) | Exhaustive (every closed bead) |
| Determinism | Auditor judgment (varies) | Deterministic rubric |
| Repeatability | Annually | Daily (tripwire) |
| Evidence quality | Notes, screenshots | Cited file:line, raw test outputs |
| Stakeholder trust | Established (regulators recognize) | Emerging (still proving itself) |
| What it can't do | N/A — humans bring contextual judgment | Replace human judgment for legal / strategic decisions |

**Compose:** This skill produces the **evidence pack**; human auditor reads it and makes the *legal* attestation. The skill removes the manual evidence-collection grunt work; the human focuses on judgment.

For SOC2 / HIPAA: see [COMPLIANCE-EVIDENCE-PACK.md](COMPLIANCE-EVIDENCE-PACK.md).

---

## vs other beads-related skills

| Skill | Purpose | Overlap with this skill |
|-------|---------|-------------------------|
| `/br` | Bead CLI usage | This skill *uses* `/br` |
| `/bv` | Graph triage and metrics | This skill *uses* `/bv` |
| `/beads-workflow` | How to write good beads | Pre-implementation; complements this skill |
| `/fixing-beads-problems` | Repair bead store corruption | Pre-audit handoff |
| `/idea-wizard` | Generate ideas → beads | Pre-implementation |
| `/reality-check-for-project` | Code-vs-vision audit | Strategic alignment; this skill is tactical |
| `/mock-code-finder` | General stub detection | This skill *uses* `/mock-code-finder` for Phase 5 |

This skill is the *audit* of bead completion. The other skills are different stages of the bead lifecycle.

---

## When to use what

```
Need to verify a single bead is done?      → this skill, --mode single-bead
Need to find ALL stubs in a codebase?      → /mock-code-finder
Need to know if project meets README?      → /reality-check-for-project
Need to plan new work as beads?            → /beads-workflow + /idea-wizard
Need to fix bead store corruption?         → /fixing-beads-problems
Need to triage what to work on?            → /bv --robot-triage
Need to find security bugs?                → /security-audit-for-saas
Need bug fixes verified?                   → this skill, BISECT mode
Need release gate?                         → this skill (RELEASE-GATING.md)
Need SOC2 evidence?                        → this skill (COMPLIANCE-EVIDENCE-PACK.md)
Need to debug an incident?                 → this skill (POST-MORTEM-MODE.md)
Need to audit a historical state?          → this skill (TIME-MACHINE-MODE.md)
```

---

## What this skill is NOT

- **Not a project management tool.** It doesn't tell you what to work on next.
- **Not a code quality scanner.** UBS / clippy / eslint do that.
- **Not a security scanner.** `/security-audit-for-saas` does that.
- **Not a test framework.** Vitest / cargo test / pytest do that.
- **Not a deployment tool.** `/release-preparations` does that.
- **Not a one-shot tool.** Designed for repeated passes over weeks.
- **Not a replacement for human judgment.** It surfaces facts; humans decide what to do.

---

## What makes this skill distinctive

| Feature | This skill | Most alternatives |
|---------|-----------|-------------------|
| Deterministic scoring | ✓ | ✗ (LLM judgment varies) |
| Persistent evidence packs | ✓ | ✗ (transient) |
| Convergence semantics | ✓ | ✗ (single-shot) |
| Cross-bead integration check | ✓ | ✗ (per-issue only) |
| Per-bead-type playbooks | ✓ | ✗ (one rubric for all) |
| Audit-of-the-audit (Phase 10) | ✓ | ✗ |
| Cost/time accounting per pass | ✓ | ✗ |
| Bayesian framing (opt-in) | ✓ | ✗ |
| Cross-pass trends | ✓ | ✗ |
| Sloppy-session trauma guard | ✓ | ✗ |

The combination is the value — no single feature is novel, but the assembled discipline is.

---

## Honest limits (vs what alternatives do better)

- **Performance bug discovery:** dynamic analyzers (Mayhem) find bugs this skill can't — bugs the bead never claimed to fix.
- **Architecture review:** human architects bring system-level judgment this skill can't.
- **UX evaluation:** `/ux-audit` evaluates user-facing quality; this skill doesn't.
- **Bead authoring quality:** `/beads-workflow` polishes specs; this skill audits implementations.
- **Real-time monitoring:** Sentry / Datadog watch production; this skill audits source artifacts.

The skill is a verification tool, not a discovery tool. It's strong at "did the closer's claim hold up?" and weak at "what unstated quality issues exist?"

---

## When to NOT adopt this skill

- Project has < 10 closed beads (overhead exceeds value).
- Project doesn't use beads (use issue-tracker-specific tools).
- Project is being deprecated (audit live projects only).
- Team can't act on remediation beads (audit's value depends on follow-through).
- Project bead bodies are universally vague (fix authoring first via `/beads-workflow`).

In those cases, simpler tools — manual review, ad-hoc grep for `unimplemented!()`, single-bead spot-checks — are more cost-effective.