# QUICKREF — One-page agent quickref for this skill

## Table of Contents

- [Mode picker](#mode-picker)
- [The 11 dimensions (memorize these)](#the-11-dimensions-memorize-these)
- [The 17 most-used operators](#the-17-most-used-operators)
- [Phase loop (10 phases + 1 meta)](#phase-loop-10-phases--1-meta)
- [Polish Bar (every shipped CLI must satisfy)](#polish-bar-every-shipped-cli-must-satisfy)
- [Ambition Bar (the gate before declaring done)](#ambition-bar-the-gate-before-declaring-done)
- [File layout (in-tree, NOT a sibling)](#file-layout-in-tree-not-a-sibling)
- [The 7 operator rules (when in doubt, re-anchor here)](#the-7-operator-rules-when-in-doubt-re-anchor-here)
- [Common failure attractors (defeat them)](#common-failure-attractors-defeat-them)
- [Where to look](#where-to-look)
- [Smoke test (verify skill is intact)](#smoke-test-verify-skill-is-intact)

**The One Rule.** First command an agent guesses must work or be redirected with a useful hint. Never silent-fail. Always offer a safe alternative for any dangerous request. Output is parseable, deterministic, self-describing.

**Three policy axioms (over-rule everything else):**
1. NEVER create a new branch. Commit to current branch (typically `main`).
2. NEVER create a sibling workspace. Audit lives at `<target>/agent_ergonomics_audit/` (in-tree).
3. NEVER stop with a polite scorecard. Run "That's it??" self-prompt before declaring done.

---

## Mode picker

```
"audit / review / score / report" only          → audit-only
"apply / improve / harden / make agent-friendly" → FULL (the strong default)
"did the changes work?" / "what regressed?"     → re-score-only or simulate-only
"just fix this one named flag/subcommand"        → single-surface-rescore
"verify the pipeline works"                      → mini
```

When ambiguous: default to `full`. Tool size never downgrades the mode — that's a Phase 4 prioritization issue, not a mode issue.

---

## The 11 dimensions (memorize these)

| # | Dim | Quick check |
|---|-----|-------------|
| 1 | agent_intuitiveness | First-try success on canonical task? |
| 2 | agent_ergonomics | Min round-trips to canonical task? |
| 3 | agent_ease_of_use | Discoverable from `--help` / `capabilities`? |
| 4 | output_parseability | `<tool> X --json \| jq` works without grep? |
| 5 | error_pedagogy | Error names the exact corrected command? |
| 6 | intent_inference | Recovers from typos / wrong flag spellings? |
| 7 | safety_with_recovery | Dangerous ops gated; safe alternative offered? |
| 8 | determinism_and_reproducibility | Same input → same bytes? |
| 9 | self_documentation | `capabilities --json` + `robot-docs guide` exist? |
| 10 | composability | Honors NO_COLOR / CI / non-TTY / pipes cleanly? |
| 11 | regression_resistance | Golden tests pin the surface? |

Score 0–1000 per dim. Score > 700 needs evidence (file:line OR runtime transcript).

---

## The 17 most-used operators

```
①  First-Try-Inevitability        Σ  Mega-Command
⟁  Intent-Infer-Then-Act           🛡  Safe-Alternative-Always
📜 Self-Describing                 📖 In-Tool-Docs
🚦 Exit-Code-Contract              🪧 Stdout-Data-Stderr-Diag
🧪 Pin-The-Contract-Test           🔀 Macros-vs-Granular
🆔 Stable-Handle                   🩹 Error-Teaches
🚫 Never-Silent-Fail               ⏱  Sub-Second-Hot-Path
🌐 Honors-Env-Conventions          🔢 Deterministic-Output
🧭 Discoverable-From-Help
```

Full library (33 operators): `methodology/OPERATORS.md`.

---

## Phase loop (10 phases + 1 meta)

```
0  INPUT + BOOTSTRAP        manifest, scope decision, helper-skill inventory
1  SURFACE INVENTORY        enumerate every flag/subcmd/env-var/exit-code/error
2  RUBRIC SCORING           ≥2 scorers per surface, median + spread
3  INTENT-INFERENCE STRESS  naive + savvy wrong-invocation corpora
4  RECOMMENDATION SYNTHESIS rank by frequency × score_gap × blast_radius
5  APPLY CHANGES (full)     one commit per rec, current branch, never new branch
6  RE-SCORE & UPLIFT        median ≥ 25 pts; no surface drops > 50 pts
7  FRESH-EYES BUG REVIEW    3 calibrated prompts; until clean twice
8  SELF-DOC HARDENING       capabilities, robot-docs, --robot-* if missing
9  AGENT-IN-THE-LOOP SIM    fresh-context agent attempts canonical tasks
10 HANDOFF + AMBITION BAR   "That's it??" self-prompt; HANDOFF.md; push branch
11 META (optional)          self-application: audit a Claude Code skill
```

---

## Polish Bar (every shipped CLI must satisfy)

- [ ] `<tool>`, `<tool> --help`, `<tool> help <sub>` all produce useful output (no stack trace, no silent exit, no TUI-on-bare).
- [ ] Every read-side command has `--json` or `--robot-*`.
- [ ] `<tool> capabilities --json` returns version + contract + commands + exit codes + env vars.
- [ ] `<tool> robot-docs guide` prints a paste-ready agent handbook.
- [ ] At least one mega-command (`--robot-triage` shape) returns multiple slices in one call.
- [ ] Exit codes are a documented dictionary (0=success, 1=user-input-error, 2=safety-block, …).
- [ ] Every error names: what failed + where + the exact command to use instead.
- [ ] Common typos / deprecated flags either succeed-with-warning or get a "did you mean" hint.
- [ ] Dangerous ops require explicit `--yes` AND offer a safe alternative.
- [ ] Output is deterministic (stable ordering, no wall-clock leakage, honors `SOURCE_DATE_EPOCH`).
- [ ] Honors `NO_COLOR` / `CI` / `--no-color` / non-TTY.
- [ ] Every applied rec has a regression test in `audit/regression_tests/`.

---

## Ambition Bar (the gate before declaring done)

For `full` mode on a non-trivial CLI, target:

- ≥ 10 substantive landed changes (≥ 5 for tiny CLIs).
- ≥ 3 of the 11 dimensions touched.
- At least one each of the following types when missing:
  - Mega-command (`--robot-triage` shape)
  - `capabilities --json` OR `robot-docs guide`
  - `--json` (or `--robot-*`) on a read-side command
  - Error-message rewrite naming the exact corrected command
  - Typo / intent-inference handler

If short → run verbatim "That's it??" self-prompt → re-enter Phase 4/5 once more.

A "substantive landed change" = moves a scored surface up by ≥ 100 points on at least one dim AND ships with a regression test that fails if reverted.

---

## File layout (in-tree, NOT a sibling)

```
<target>/                                          (current branch, typically main)
├── (your code diffs from Phase 5)
├── tests/                                         (golden tests if project has tests/)
└── agent_ergonomics_audit/                       (THE WORKSPACE — INSIDE the target)
    ├── audit/
    │   ├── manifest.json                          (entry point)
    │   ├── surface_inventory.jsonl                (Phase 1)
    │   ├── agent_surfaces.jsonl                   (Phase 2; scored)
    │   ├── intent_inference_corpus.jsonl          (Phase 3)
    │   ├── recommendations.jsonl                  (Phase 4; ranked)
    │   ├── playbook.md                            (Phase 4; top-10 narrative)
    │   ├── applied_changes.jsonl                  (Phase 5)
    │   ├── ambition_bar_check.md                  (Phase 10 gate)
    │   ├── scorecard*.md, heatmap.svg, uplift_diff.md
    │   ├── regression_tests/                      (R-NNN__*.test.{sh,rs,py,ts})
    │   ├── agent_simulations/{pre,post}_pass_<N>/
    │   └── HANDOFF.md
    └── tools/                                     (per-workspace helpers)
```

Legacy variable `<SIBLING>` resolves to `<target>/agent_ergonomics_audit/`. The variable name is kept for back-compat; the location is in-tree.

---

## The 7 operator rules (when in doubt, re-anchor here)

1. **Branch policy is fixed; never auto-branch even when it "feels safer."**
2. **Workspace is in-tree; the variable name `<SIBLING>` is legacy.**
3. **Ambition Bar is the gate; the self-prompt is mandatory and verbatim.**
4. **Intent wins over state when picking mode; default `full`.**
5. **Score with evidence or don't score; > 700 needs file:line.**
6. **Regression test ≡ applied recommendation; one without the other is half-applied.**
7. **"AGENTS.md says no" outranks every other axiom.**

Full discussion of each rule with failure cases: SKILL.md § "Operator Rules".

---

## Common failure attractors (defeat them)

| Attractor | Defeat with |
|-----------|-------------|
| "Polite scorecard, stop" | Verbatim "That's it??" self-prompt + re-enter Phase 4/5 |
| "Branch creation feels safer" | Axiom 1 + the verbatim "DO NOT CREATE A NEW BRANCH" check |
| "Sibling workspace is cleaner" | Axiom 2 + scaffold script warns if outside target |
| "Audit-only because tool is too big" | Tighten Phase 4 prioritization; keep mode `full` |
| "Vibe-anchored high scores" | Validator rejects > 700 without evidence |
| "Half-applied rec (no test)" | Phase 5 exit criterion requires regression test |
| "Cross-skill bleed" (other skills DO branch) | Anti-pattern + kickoff prompt explicit ban |

---

## Where to look

| Need | File |
|------|------|
| Comprehensive prompts to invoke this skill | `methodology/VARIANT-PROMPTS.md` |
| Real session corpus + lessons | `methodology/LESSONS-FROM-SESSIONS.md` |
| 30+ shippable Phase 5 patterns | `methodology/AMBITION-PLAYBOOK.md` |
| Per-language framework recipes | `methodology/LANGUAGE-RECIPES.md` |
| Mega-command shapes + JSON schemas | `methodology/MEGA-COMMAND-DESIGN.md` |
| Error-message rewriting cookbook | `methodology/ERROR-REWRITING-COOKBOOK.md` |
| Per-phase playbook | `methodology/PHASES.md` |
| Scoring rubric anchors | `rubric/SCORING-RUBRIC.md` |
| Canonical CLI exemplars | `exemplars/CANONICAL-EXEMPLARS-DEEP.md` |
| Counter-examples (CE-1 to CE-20) | `exemplars/COUNTER-EXAMPLES.md` |

---

## Smoke test (verify skill is intact)

```bash
SKILL=<repo>/.claude/skills/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools

# 1. SKILL.md frontmatter parseable
head -10 "$SKILL/SKILL.md" | grep -E '^name:|^description:'

# 2. All 19 kernel axioms present
grep -c '^\*\*Axiom [0-9]' "$SKILL/SKILL.md"   # should equal 19

# 3. All 12 variants present
grep -c '^## Variant [A-L]' "$SKILL/references/methodology/VARIANT-PROMPTS.md"   # 12

# 4. Manifest schema is valid JSON
jq . "$SKILL/assets/manifest-template.json" > /dev/null

# 5. Scaffold script does NOT git init
grep -q "git init" "$SKILL/scripts/scaffold-workspace.sh" && \
  ! grep -q "^[^#]*git init" "$SKILL/scripts/scaffold-workspace.sh"

# 6. Applier subagent does NOT take FEATURE_BRANCH
! grep -q "FEATURE_BRANCH>" "$SKILL/subagents/applier.md" || \
  grep -q "NO.*<FEATURE_BRANCH>" "$SKILL/subagents/applier.md"
```
