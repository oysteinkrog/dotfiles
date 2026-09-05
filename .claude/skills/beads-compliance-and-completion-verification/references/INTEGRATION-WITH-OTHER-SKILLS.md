# INTEGRATION-WITH-OTHER-SKILLS.md — How Adjacent Skills Plug In

This skill is a *composer* — it stands on top of many existing skills rather than reimplementing their work. This file maps each phase to the skill(s) it leans on, the exact integration point, and the inline fallback if the helper skill isn't installed.

---

## Phase 1 — Inventory & sanity check

| Skill | Role | Integration point |
|-------|------|-------------------|
| `/beads-br` | Bead CLI | All `br doctor`, `br list`, `br show`, `br dep cycles` calls |
| `/beads-bv` | Graph metrics | `bv --robot-graph --graph-format json` for the DAG; `bv --robot-insights` for richer metrics |
| `/fixing-beads-problems` | Escape hatch | If `br doctor` fails, hand off and STOP this audit |
| `/agent-mail` | File-reservations for parallel phases | Reserve `passes/<UTC>/` so concurrent agents don't trample each other |

**Fallback if `bv` missing:** Use only `br dep` commands; DAG analysis is shallower but Phase 1 still completes.

---

## Phase 2 — Spec extraction

| Skill | Role | Integration point |
|-------|------|-------------------|
| `/beads-workflow` | Bead body conventions | The "self-contained, self-documenting" bead pattern is what we parse |
| `/operationalizing-expertise` | Operator library philosophy | Implicit-requirement injection per bead type uses operator-style triggers |

**Fallback:** None needed; spec extraction uses only `show.json` content.

---

## Phase 3 — Evidence gathering

| Skill | Role | Integration point |
|-------|------|-------------------|
| `/codebase-archaeology` | Reading unfamiliar code | When a bead cites a module the auditor agent doesn't recognize |
| `/codebase-report` | Optional pre-pass | If the project has no architecture doc, run this once to give Phase 3 agents context |
| `/cass` | Mining prior agent sessions | Find the original implementing agent's plan / approach if commit messages are sparse |
| `/optimized-ripgrep-rg-instructions` | Faster lookahead/lookbehind grep | Build PCRE2 ripgrep if the audit grep patterns need it |

**Fallback if `cass` missing/stale:** Skip the prior-session lookup; rely on git log + ripgrep only.

---

## Phase 4 — Compliance verification

| Skill | Role | Integration point |
|-------|------|-------------------|
| `/testing-perfect-e2e-integration-tests-with-logging-and-no-mocks` | E2E pattern enforcement | Every e2e test is verified against this skill's "real-DB, real-services, structured-log" rubric |
| `/testing-real-service-e2e-no-mocks` | Same | Synonym; either skill works |
| `/testing-conformance-harnesses` | Conformance test execution | Phase 4 verdict for conformance type uses this skill's "MUST clauses ≥ 0.95" rule |
| `/testing-fuzzing` | Fuzz harness verification | Phase 4 fuzz check uses this skill's compile + corpus + run-for-stated-time pattern |
| `/testing-golden-artifacts` | Golden artifact verification | Phase 4 + 6 use this skill's regenerate-and-diff approach |
| `/testing-metamorphic` | Metamorphic test execution | Phase 4 metamorphic check uses this skill's MR taxonomy to verify completeness |
| `/agent-mail` | Resource-conflict prevention | `file_reservation_paths` for shared test fixtures; thread_id = `audit-<bead-id>` |
| `/dcg` | Destructive-command guard | Compliance-verifier should NOT issue destructive commands; dcg blocks them |

**Fallback if a `/testing-*` skill is missing:** Fall back to running the test command without the skill's rubric; record `methodology: tool-only` in `compliance.json` and Phase 8 dings the depth dimension.

---

## Phase 5 — Anti-theater scan

| Skill | Role | Integration point |
|-------|------|-------------------|
| `/mock-code-finder` | THE primary tool for this phase | Every `theater.json` finding traces back to a mock-code-finder pattern |
| `/de-slopify` | Tangentially | Some "slop" patterns (vague TODOs, half-comments) overlap with theater |

**Fallback:** Phase 5 has its own internal pattern list (in `FAILURE-MODES.md`). It can run without `mock-code-finder` installed but loses richness.

---

## Phase 6 — Test depth

| Skill | Role | Integration point |
|-------|------|-------------------|
| All `/testing-*` skills | Depth criteria per test type | Each skill's "what makes this test type real" rubric becomes a depth check |
| `/extreme-software-optimization` | Performance budgets | If bead spec includes performance budgets, use this skill's measurement approach |
| `/profiling-software-performance` | Measurement methodology | Same |

**Fallback:** Use language-native coverage tools only; record `methodology: native-only`.

---

## Phase 7 — Cross-bead synthesis

| Skill | Role | Integration point |
|-------|------|-------------------|
| `/reality-check-for-project` | Vision-vs-reality lens | Phase 7's "shared invariants nobody owns" check is reality-check's "no_bead" gap pattern at the bead level |
| `/codebase-pattern-extraction` | Cross-bead pattern recognition | If multiple beads silently re-implement the same primitive |
| `/multi-model-triangulation` | Optional second opinion | Spawn a Codex/Gemini agent to read the same per-bead reports and produce an independent synthesis; compare |

**Fallback:** Single-model synthesis from one senior agent.

---

## Phase 8 — Scoring

| Skill | Role | Integration point |
|-------|------|-------------------|
| `/multi-pass-bug-hunting` | Fresh-eyes pattern | Phase 10 fresh-eyes audit borrows directly from this skill |

**Fallback:** None needed; scoring is internal to this skill.

---

## Phase 9 — Remediation

| Skill | Role | Integration point |
|-------|------|-------------------|
| `/beads-br` | Bead writes | `br create`, `br reopen`, `br dep add`, `br update` |
| `/beads-workflow` | Bead body conventions | Completion-debt bead description follows the "self-contained, self-documenting" pattern |
| `/agent-mail` | Coordination notice | Optional: send a thread message to other agents announcing the audit-driven bead changes |

**Fallback:** `br` is required; without it Phase 9 can't run. Drop to `report-only` policy.

---

## Phase 10 — Fresh-eyes

| Skill | Role | Integration point |
|-------|------|-------------------|
| `/multi-pass-bug-hunting` | Fresh-eyes methodology | Direct adaptation; the fresh-eyes agent re-reads scorecards as if for the first time |
| `/multi-model-triangulation` | Optional cross-model check | Spawn a different model to re-derive scores for spot-checks |
| `/codebase-archaeology` | If the spot-check requires reading unfamiliar code | When spot-checking forces the fresh-eyes agent to verify a citation |

**Fallback:** Same-model fresh-eyes spot-check; tighten the deviation threshold to ±25 to compensate.

---

## Skill installation orchestration

`scripts/check-skills.sh` runs at bootstrap to detect which referenced helper skills are present. If any are missing AND `jsm` is installed + authenticated, it offers `jsm install <name>` for each. If `jsm` is missing, the user can install it:

```bash
# Linux/macOS
curl -fsSL https://jeffreys-skills.md/install.sh | bash
jsm login

# Then install the missing ones
jsm install mock-code-finder
jsm install testing-conformance-harnesses
# etc.
```

The audit pipeline degrades gracefully — every helper skill has an inline fallback. No helper-skill absence is fatal; the audit just loses richness in the corresponding phase, and `manifest.json#tools` records what was/wasn't available so the trend report can explain dimensional changes between passes.

---

## What this skill does NOT integrate with

For clarity:

- **`/security-audit-for-saas`** — separate concern; runs independently.
- **`/codebase-audit`** — broader and shallower than this skill.
- **`/multi-agent-swarm-workflow`** — orchestration pattern; this skill *is* a swarm pattern internally but doesn't replace it for general-purpose work.
- **`/idea-wizard`** — generates new ideas; this skill verifies prior closed ones.
- **`/release-preparations`** — pre-release checklist; this skill is a more rigorous, bead-by-bead version focused on completion claims.
