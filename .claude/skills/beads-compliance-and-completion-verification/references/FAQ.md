# FAQ.md — Common Questions

<!-- TOC: General | Setup | Running | Interpreting results | Cost / time | Compliance / regulatory | Failure modes | Adjacent skills | Philosophy -->

## General

**Q: What does this skill do in one sentence?**

A: It re-executes the proof for every closed bead in your project and tells you which ones are lying about being done.

**Q: Why "false-closed" specifically?**

A: Long-running multi-agent projects accumulate beads that are status-flipped without verification. The "false-closed" framing names the problem. Catching them is the audit's headline output.

**Q: Is this only for `beads_rust` (br)?**

A: Yes. The skill assumes a `br`-compatible bead store with `.beads/`. For other issue trackers (Jira, Linear, GitHub Issues), the kernel ideas transfer but the implementation doesn't.

**Q: Will this slow down agent development?**

A: The audit runs out-of-band (typically weekly) and produces remediation beads that fold into normal triage. Day-to-day agent work is unaffected. The audit's value is in the *occasional surprise*, not in continuous interrupt.

**Q: Does this replace code review?**

A: No. Code review checks code quality. This skill checks bead-graph integrity. Both are needed.

---

## Setup

**Q: What do I need installed?**

A: `br`, `jq`, `git`, `python3`, `rg` (ripgrep). Recommended: `bv`, `cass`, `ast-grep`, plus the project's test runner. See [README.md § Install](../README.md#install).

**Q: Where does the audit dir live?**

A: As a subdirectory of the project: `<project>/beads_compliance_audit/`. It's tracked by its own `.git/` and `bootstrap-audit.sh` adds it to the project's `.gitignore`, so the project's git never sees it. See [AUDIT-DIRECTORY-LAYOUT.md](AUDIT-DIRECTORY-LAYOUT.md).

**Q: Can I commit the audit dir to the project's GitHub?**

A: We don't recommend it. The audit dir is local-by-default; pushing scatters internal critique. If you need shared visibility, push to a *separate* repo (e.g., `myproject-audit`).

**Q: How do I configure the rubric?**

A: Edit `<audit-dir>/rubric.md` frontmatter. See [AUDIT-AS-CODE.md](AUDIT-AS-CODE.md) for the schema.

---

## Running

**Q: Quick start?**

A:
```bash
~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
  /path/to/project --threshold 700 --policy completion-debt
```

**Q: How long does an audit take?**

A: Depends on bead count and mode. Tripwire: ~5 min. Standard on 200 beads: ~60 min. See [MODES-AND-TIERS.md](MODES-AND-TIERS.md).

**Q: Can I run multiple audits in parallel?**

A: Yes — different projects can audit concurrently. Within one project, only one audit at a time (lockfile enforced).

**Q: How often should I run it?**

A: Weekly for active projects; monthly for steady-state; daily tripwire after convergence. See [MULTI-PASS-FLOW.md](MULTI-PASS-FLOW.md).

**Q: What's the difference between modes?**

A: Triage skips Phase 4 (no test execution); Standard runs phases 1-9; Comprehensive adds Phase 10 + multi-model triangulation; Tripwire is autonomous report-only. See [MODES-AND-TIERS.md](MODES-AND-TIERS.md).

---

## Interpreting results

**Q: My audit found 30 false-closed beads. What do I do?**

A: Triage them per [REMEDIATION-PRIORITIZATION.md](REMEDIATION-PRIORITIZATION.md). Don't try to fix all 30 at once; focus on T0-fire and T1-high tier first.

**Q: A bead scored 612/1000. Is that bad?**

A: It's "🟠 False-closed (mild)." The closer's claim is partially true but enough is missing that the bead's status is misleading. Read the scorecard's Missing items section.

**Q: A bead is on the false-closed list but I think the audit is wrong. What do I do?**

A: Either:
1. Enable closer-defense ([CLOSER-DEFENSE.md](CLOSER-DEFENSE.md)) and respond with evidence.
2. Investigate via [DEBUGGING-THE-AUDIT.md](DEBUGGING-THE-AUDIT.md).
3. If you find a real audit bug, file it (see [CONTRIBUTING-PATTERNS.md](CONTRIBUTING-PATTERNS.md)).

**Q: My project has zero false-closed in the first audit. Is that suspicious?**

A: Yes. See [AUDIT-SMELLS.md](AUDIT-SMELLS.md) Smell 1 — the threshold may be too low or Phase 5 isn't running.

**Q: What does "convergence" mean?**

A: Two consecutive audit passes show no material change (±10 score deltas, zero new false-closed). After convergence, you maintain via tripwire mode. See [CONVERGENCE-CRITERIA.md](CONVERGENCE-CRITERIA.md).

---

## Cost / time

**Q: How much does an audit cost in tokens?**

A: ~$0.06 per bead at Solo tier with Opus; ~$0.03/bead at Swarm tier. A 200-bead Standard audit ≈ $10. Subscription accounts (Claude Max, GPT Pro) amortize this to $0. See [COST-OPTIMIZATION.md](COST-OPTIMIZATION.md).

**Q: My tripwire takes 30 minutes daily. Too slow?**

A: Tripwire mode should be ~5 min. If yours is 30 min, Phase 4 is probably running (check `manifest.json#mode`). Tripwire skips Phase 4 by design. See [COST-OPTIMIZATION.md](COST-OPTIMIZATION.md).

**Q: Differential auditing — what is it?**

A: Re-verification mode caches per-bead evidence packs. Only beads whose cited files changed since prior pass get re-executed. Typical 80%+ cache hit rate on tripwire. See [COST-OPTIMIZATION.md](COST-OPTIMIZATION.md).

---

## Compliance / regulatory

**Q: Can I use this for SOC2 evidence?**

A: Yes. See [COMPLIANCE-EVIDENCE-PACK.md](COMPLIANCE-EVIDENCE-PACK.md). The skill produces signed bundles mappable to SOC2 / HIPAA / PCI / ISO27001 controls.

**Q: How long do I retain audit dirs?**

A: Per regulatory framework: SOC2 5y, HIPAA 6y, PCI 1y, ISO27001 3y. The audit dir is git-tracked so retention = git retention.

**Q: What if I want to attest "we audit every release"?**

A: Use [RELEASE-GATING.md](RELEASE-GATING.md). The release pipeline blocks tag creation if any milestone bead is false-closed. The CI artifact is your attestation.

**Q: Can I tamper-proof the audit dir?**

A: Yes — use signed commits, append-only logs, and integrity checks. See [ANTI-CORRUPTION.md](ANTI-CORRUPTION.md).

---

## Failure modes

**Q: What if `br doctor` fails?**

A: Don't run the audit. Hand off to `/fixing-beads-problems`. The audit assumes a healthy bead store.

**Q: What if my project has no test runner?**

A: Phase 4 verdicts will be MISSING. Phase 5 + 6 still produce useful output (anti-theater + structural analysis). Score docks for missing tests, but not for the audit's inability to run them.

**Q: What if my project uses a weird bead-id prefix?**

A: As of round-2 fixes, the audit handles arbitrary prefixes (`bd-abc123`, `myproject-456-xyz`, etc.). If something breaks on prefix detection, file a bug.

**Q: The audit produces inconsistent results across runs. Why?**

A: It shouldn't — scoring is deterministic per [DESIGN-PHILOSOPHY.md](DESIGN-PHILOSOPHY.md). If you're seeing variance: Phase 4 test results may be flaky (real signal); subagent prompts may have drifted (re-run with cached prompts); the rubric was tuned mid-pass (banned per `☖ STAKE-RUBRIC`). See [DEBUGGING-THE-AUDIT.md](DEBUGGING-THE-AUDIT.md).

---

## Adjacent skills

**Q: How does this differ from `/reality-check-for-project`?**

A: Reality-check compares code to README/plan vision (high-level). This skill verifies bead-by-bead completion (granular). Use both: reality-check for strategic alignment, this for tactical truthfulness.

**Q: How does this differ from `/mock-code-finder`?**

A: Mock-code-finder finds stubs across the project unrelated to bead state. This skill finds stubs *in the cited evidence of closed beads*. The two compose: mock-code-finder is Phase 5's primary tool here.

**Q: How does this differ from `/multi-pass-bug-hunting`?**

A: Multi-pass-bug-hunting iterates fix-rescan cycles for general bugs. This skill is bead-graph-truthfulness specifically. Phase 10's fresh-eyes pattern borrows from multi-pass-bug-hunting.

**Q: When should I use `/codebase-audit` instead?**

A: For broad code-quality reviews unrelated to beads (security, perf, UX). Codebase-audit is general; this is bead-specific.

---

## Philosophy

**Q: Why is the rubric deterministic instead of LLM-judgment-based?**

A: Two scorers must produce the same score from the same evidence. LLM judgment varies pass-to-pass; deterministic rubric doesn't. See [DESIGN-PHILOSOPHY.md](DESIGN-PHILOSOPHY.md) Principle 1.

**Q: Why per-bead scoring instead of project-aggregate?**

A: Bad beads hide in good neighborhoods at the aggregate level. Per-bead surfaces the specific theater. See [DESIGN-PHILOSOPHY.md](DESIGN-PHILOSOPHY.md) Principle 2.

**Q: Why do I need to keep prior pass dirs forever?**

A: Convergence requires comparison. Without history, "is it converged?" is meaningless. See [DESIGN-PHILOSOPHY.md](DESIGN-PHILOSOPHY.md) Principle 6.

**Q: Why do I need to run the audit multiple times to converge?**

A: First pass discovers; subsequent passes verify remediation; convergence requires two stable passes. See [MULTI-PASS-FLOW.md](MULTI-PASS-FLOW.md).

**Q: This seems like a lot of process for "did the agent finish the work?"**

A: Yes. The audit is for projects where bead status genuinely matters (compliance, paid product, security-critical). For toy projects, manual review is fine. The skill exists because at scale (100+ closed beads, multiple agents), process is the only way to maintain trust in bead state.

---

## Special cases

**Q: Can I audit a private bead that I don't want others to see?**

A: The audit dir contains the bead's content (description, AC). If those are sensitive, store the audit dir on a private filesystem and don't push.

**Q: My project uses both bd (legacy beads) and br. What do I do?**

A: Migrate per `/bd-br-migration` first. The audit only supports br.

**Q: Can the audit modify my project?**

A: Only Phase 9 with `--policy=completion-debt` or `--policy=reopen` writes to `<project>/.beads/`. Use `--policy=report-only` to keep the audit pure-read.

**Q: How do I add a custom check that the rubric doesn't cover?**

A: Add a custom pipeline to rubric.md frontmatter. See [AUDIT-AS-CODE.md](AUDIT-AS-CODE.md) custom_pipelines section.

---

## Still stuck?

- See [DEBUGGING-THE-AUDIT.md](DEBUGGING-THE-AUDIT.md) for a troubleshooting flowchart.
- Read [CASE-STUDIES.md](CASE-STUDIES.md) for worked examples that resemble your scenario.
- Check [AUDIT-SMELLS.md](AUDIT-SMELLS.md) if results look wrong.
- Check [KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md) if you suspect the skill can't handle your case.
