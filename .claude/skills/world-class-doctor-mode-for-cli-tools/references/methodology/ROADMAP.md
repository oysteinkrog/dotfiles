# Roadmap — Planned-but-Not-Implemented

This file tracks planned methodology improvements that haven't been implemented yet. Use as the standing backlog for the skill's own evolution.

When something is implemented, move it from "Planned" to "Done in vN.N" and update [CHANGELOG.md](../../CHANGELOG.md). Per AGENTS.md no-delete, the Done sections accumulate (no rolling history limit).

---

## Planned (priority-ordered)

### High priority

1. **`scripts/scorecard.py latency-p95`** — convenience wrapper for the `METRICS.md` JSONL + `jq` gate. Computes p95 latency per detector from `scorecard_history.jsonl`.

2. **`scripts/scorecard.py panics-total`** — convenience wrapper for the `METRICS.md` JSONL + `jq` gate. Sums `panics_caught` across recent runs. Alert threshold > 0 because Axiom 5 says zero.

3. **`scripts/verify-coverage.sh`** (planned) — referenced in KERNEL.md Axiom 18. Walks both detector list and fixture list; fails CI if either is incomplete.

4. **`scripts/translate-legacy-artifacts.py`** (planned) — referenced in MIGRATION-GUIDE.md. Converts pre-this-methodology run artifacts to current schema for trend analysis.

5. **`scripts/compute-priority.py`** (planned) — wraps PRIORITY-FORMULA.md formula in a script that reads the workspace and emits a priority-sorted FM list for Phase 4.

### Medium priority

6. **Doctor's `--audience` flag** — per MENTAL-MODELS.md. Allows explicit selection of user / agent / operator / maintainer output formatting.

7. **Doctor's `metrics-export` subcommand** — per METRICS.md. Replays per-run summaries to a telemetry sink (Datadog / Honeycomb / Prometheus / etc.).

8. **`tests/doctor_fixtures/adversarial/` driver** — per ADVERSARIAL-REVIEW.md. Runs the 18 adversarial scenarios as part of CI.

9. **Property-test driver script** — per PROPERTY-TESTS.md. Wraps Hypothesis / proptest / fast-check invocations into a single CI step.

10. **`scripts/docagent-bench.sh`** (planned) — runs a benchmark suite of agents using the doctor; produces an agent-ergonomics score that's distinct from the rubric scorecard.

11. **9 additional `validate-skill.sh` detector sections** (planned) — per [META-DOCTOR.md § Implementation status](META-DOCTOR.md), the meta-doctor documents 9 detectors that aren't yet implemented:
    - `fm-references-integrity-corpus-path-rot` — CORPUS.md cites paths that don't exist locally.
    - `fm-references-integrity-circular-link` — cycle detection in the methodology graph.
    - `fm-frontmatter-description-too-long` — over a 220-char display budget (current check is the harder 1024-char API limit).
    - `fm-frontmatter-description-missing-trigger-words` — heuristic against a word list.
    - `fm-subagents-consistency-prompt-not-self-contained` — regex for unresolved `{{vars}}` in subagent prompts.
    - `fm-scripts-shebang-missing` — first line isn't `#!/usr/bin/env bash`.
    - `fm-scripts-set-euo-pipefail-missing` — grep first ~25 lines for `set -e`.
    - `fm-assets-template-malformed` — jq-parse all `assets/*.json` (with documented JSONL exception per round-23).
    - `fm-assets-template-references-undefined-id` — cross-check Q-NNN refs in templates.
    Each detector is a small section addition; round-by-round implementation closes META-DOCTOR.md's documented-vs-implemented gap.

### Lower priority

11. **Bayesian-weighted detector priority** — per DESIGN-PATTERNS.md DP-004. Replaces the simple `frequency × score_gap × blast_radius` formula with a Bayesian update model.

12. **Doctor's own changelog generator** — per OPS-RUNBOOK.md. Reads `.beads/issues.jsonl` and generates per-doctor-version CHANGELOG entries.

13. **Cross-skill consistency validator** — extends `validate-skill.sh` to walk multiple skills in this repo and assert consistency (e.g., the same Q-NNN ID isn't reused across skills).

14. **Multi-language conformance suite** — for each language recipe (rust.md / go.md / etc.), a test that builds a tiny doctor in that language and runs it through the conformance checklist.

15. **Live agent simulation** — instead of fixture-based testing, spawn an agent (via Agent SDK) in a sandbox, give it the doctor + a corrupted workspace, observe its behavior. Per cold-agent-prober subagent.

### Long-term

16. **Doctor SDK** — extract the methodology into a published SDK (a Rust crate, a Go module, an npm package). Projects depend on the SDK; it provides the chokepoint, the runtime, the schemas. Reduces per-project copy-paste.

17. **Doctor mesh** — for multi-binary toolkits AND multi-project orgs. Doctors discover each other via a registry; a meta-orchestrator coordinates passes.

18. **AI-driven detector authoring** — use prior cass evidence to PROPOSE new detector specs. Phase 2 spec-author becomes "pick from these auto-proposed specs" instead of "write from scratch".

19. **Formal verification** — express invariants in Lean / Coq / Dafny; mechanically verify the chokepoint preserves them.

20. **`<tool> doctor evolve`** — the doctor proposes its OWN improvements based on its `scorecard_history.jsonl`. Self-improving loop. Highly speculative; cite as a long-term aspiration.

---

## Done (history)

### v1.5.0 (round-4 expansion + round-5 fresh-eyes)

- KERNEL stretch axioms 17–23 added.
- 7 new operators in OPERATORS.md.
- COOKBOOK patterns 13–15 added.
- 11 new methodology files (CASS-PLAYBOOK, FIRST-PRINCIPLES, SKILLS-CROSS-REF, THREAT-MODEL, PROPERTY-TESTS, FAILURE-ONTOLOGY, FIRST-30-MINUTES, DECISION-LOG, MENTAL-MODELS, MONOREPO, RFC).
- CHANGELOG.md.
- Meta-doctor `validate-skill.sh`.

### v1.5.1 (round-6 expansion, this round)

- PROMPT-LIBRARY.md with copy-paste recipes for every common situation.
- INCIDENT-RESPONSE.md (active-incident playbook).
- MIGRATION-GUIDE.md (existing doctor → this methodology).
- PREDICATE-LIBRARY.md (15 reusable detector predicates in 5 languages).
- COMPARATIVE-ANALYSIS.md (industry doctor comparison).
- DESIGN-PATTERNS.md (18 higher-order patterns).
- ROADMAP.md (this file).
- AGENT-PROMPT-RECIPES.md.
- SCALE.md.

### v1.4.0

- KERNEL.md, CORPUS.md, QUOTE-BANK.md, COOKBOOK.md, WORKED-EXAMPLE.md.
- TESTING-INTEGRATION, SECURITY, PERFORMANCE, VERSIONING, META-DOCTOR.
- AGENT-MAIL-INTEGRATION, BEADS-INTEGRATION, FAQ, GLOSSARY.
- Recipes: multi-binary, distributed, daemon, installer.

### v1.3.0

- STATE-MACHINE.md, ADVERSARIAL-REVIEW.md, GROWTH-LADDER.md.
- METRICS.md, CASE-STUDIES.md, OPS-RUNBOOK.md, ETIQUETTE.md.
- AGENT-PERSPECTIVE.md, WORKED-EXAMPLE-WRANGLER, WORKED-EXAMPLE-INSTALLER.
- recipes/jvm.md (Java/Kotlin/Scala/Clojure/Swift).

### v1.2.0 / v1.1.0

- Initial skill structure. See CHANGELOG.md for full history.

---

## How to add to the roadmap

When you find yourself wanting a feature that doesn't exist:

1. Decide priority (high / medium / lower / long-term).
2. Add to the appropriate section.
3. Briefly cite the rationale (which methodology file references it).
4. Allocate the next item number; never reuse retired numbers.

Items don't need to be "ready to implement" — the roadmap captures intent, not a sprint plan. When implementation happens, move to Done.

---

## What's deliberately NOT on the roadmap

- **Removing existing features.** Per AGENTS.md no-delete, the methodology is additive.
- **Breaking the contract for convenience.** Major contract bumps are surgical.
- **Adding things only because other tools have them.** Each addition must trace to a real gap.
- **Cosmetic improvements.** The skill is dense; readability is acceptable.

---

## How the roadmap interacts with passes

Each pass-N + 1 reviews the roadmap. Items that are now blocking the user's work get promoted to high priority. Items that have become irrelevant get demoted to "Long-term" or marked as "no longer needed".

Quarterly per [OPS-RUNBOOK.md](OPS-RUNBOOK.md), the maintainer does a roadmap review. New items surface; old ones get re-prioritized.

The roadmap is the skill's own meta-backlog. Like any backlog, it's most valuable when it accurately reflects the team's current understanding.
