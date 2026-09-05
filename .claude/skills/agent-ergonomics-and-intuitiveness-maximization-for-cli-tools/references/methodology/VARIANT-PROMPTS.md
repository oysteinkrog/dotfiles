# VARIANT-PROMPTS — Calibrated user prompts for invoking this skill

## Table of Contents

- [The 12 variants](#the-12-variants)
- [Variant A — Comprehensive first-time application](#variant-a--comprehensive-first-time-application)
- [Variant B — Audit-only review (no changes)](#variant-b--audit-only-review-no-changes)
- [Variant C — Targeted single-surface improvement](#variant-c--targeted-single-surface-improvement)
- [Variant D — Re-score after changes](#variant-d--re-score-after-changes)
- [Variant E — Robot-mode hardening](#variant-e--robot-mode-hardening)
- [Variant F — Mega-prompt (chain everything)](#variant-f--mega-prompt-chain-everything)
- [Variant G — Resumed pass](#variant-g--resumed-pass)
- [Variant H — Multi-tool family audit](#variant-h--multi-tool-family-audit)
- [Variant I — MCP server alongside CLI](#variant-i--mcp-server-alongside-cli)
- [Variant J — CASS-mined priorities](#variant-j--cass-mined-priorities)
- [Variant K — Self-application (audit a Claude Code skill)](#variant-k--self-application-audit-a-claude-code-skill)
- [Variant L — Plumbing-test validation](#variant-l--plumbing-test-validation)

This file is the canonical corpus of how this skill is invoked. Each variant encodes a distinct user intent that maps to a distinct mode + ambition profile + scope boundary. They are NOT interchangeable: blending them dilutes the signal that drives mode selection and ambition calibration.

> **Why this corpus exists.** Across applied passes, the same skill responds very differently to slightly different prompts. The "polite scorecard" attractor is defeated by Variant F's explicit "ship the changes" framing; the "auto-branch" attractor is defeated by Variant A's verbatim "DO NOT CREATE A NEW BRANCH" clause; the "size-driven downshift" attractor is defeated by Variant H's "as a SET" framing. Calibrated phrasings produce calibrated behavior.

---

## The 12 variants

| # | Variant | Mode | Ambition | When to use |
|---|---------|------|----------|-------------|
| A | Comprehensive first-time | `full` | Mandatory | First time applying skill to a CLI |
| B | Audit-only review | `audit-only` | N/A | User wants a report only, no changes |
| C | Targeted single-surface | `single-surface-rescore` | Light | One named flag/subcommand needs fixing |
| D | Re-score after changes | `re-score-only` | N/A | "Did the changes work?" |
| E | Robot-mode hardening | `full` | Phase-8-emphasized | Tool needs `capabilities`/`robot-docs` added |
| F | Mega-prompt (chain everything) | `full` | Maximum | Experienced user, minimum back-and-forth |
| G | Resumed pass | varies | depends on prior | Workspace exists from prior pass |
| H | Multi-tool family | `full` (Swarm) | Maximum + cross-cut | cargo + cargo-audit + cargo-deny family |
| I | MCP server alongside CLI | `full` (Squad) | Phase-8 + parity | Tool has both MCP + CLI surfaces |
| J | CASS-mined priorities | `full` | Frequency-weighted | "Fix what frustrates me most" |
| K | Self-application (skill audit) | Phase 11 (meta) | Variable | Auditing a Claude Code skill |
| L | Plumbing-test validation | `mini` | None (dry-run) | Verify pipeline works on a new repo |

The skill picks the variant by parsing the user's prompt for the keywords associated with each (table below); when ambiguous, it defaults to Variant A and asks for confirmation.

---

## Variant A — Comprehensive first-time application

**Verbatim corpus prompt:**

```
First read ALL of the AGENTS.md file and README.md file super carefully and understand
ALL of both! Then use your code investigation agent mode to fully understand the code
and technical architecture and purpose of the project. Then apply
$agent-ergonomics-and-intuitiveness-maximization-for-cli-tools comprehensively to the
project. DO NOT CREATE A NEW BRANCH, DO ALL WORK ON main (any existing new branch
made for this must be folded into main). Be ambitious — I expect dramatic, measurable
improvements, not a polite scorecard.
```

**Detection keywords:** "apply $agent-ergonomics", "apply this skill comprehensively", "make `<tool>` agent-friendly", "improve the agent ergonomics of `<tool>`".

**Mode:** `full`. Tier picked by surface count (Solo/Pair/Squad/Swarm).

**Ambition:** Mandatory soft target (≥ 10 commits non-trivial / ≥ 5 tiny, ≥ 3 dimensions, all five "at least one of each" types when missing). "That's it??" self-prompt mandatory if bar unmet.

**Branch + workspace:** Current branch (typically `main`). In-tree workspace at `<target>/agent_ergonomics_audit/`. Both axioms baked in.

**Stop condition:** Phase 10 with HANDOFF.md + Ambition Bar gate met OR self-prompt run + one more apply round.

---

## Variant B — Audit-only review (no changes)

**Verbatim corpus prompt:**

```
Audit `<tool>` for agent ergonomics. Score every surface across the 11 dimensions, give
me the top-10 recommendations playbook, but DO NOT change any code. I want to read the
report before deciding whether to apply.
```

**Detection keywords:** "audit `<tool>`", "score `<tool>` for", "give me a scorecard", "review `<tool>`'s ergonomics", "report on", "DO NOT change any code".

**Mode:** `audit-only`. Phase 5 (apply), Phase 7 (fresh-eyes), Phase 8 (self-doc hardening), Phase 9 (simulation post-pass) all forbidden. Phase 0–4 only.

**Ambition:** N/A. Bar doesn't apply to audit-only.

**Branch + workspace:** Current branch (workspace artifacts still committed in-tree on the same branch — the report itself is the deliverable, and committing it preserves it).

**Stop condition:** Phase 4 produces playbook.md + recommendations.jsonl with `applied:false` for all. HANDOFF.md is brief: "audit-only pass; no remediation. Run `full` to apply."

**Anti-pattern to avoid:** Don't auto-escalate to `full` mid-flow. The user explicitly said "DO NOT change any code"; honor it. If after seeing the playbook they want to apply, that's a follow-up `full` pass.

---

## Variant C — Targeted single-surface improvement

**Verbatim corpus prompt:**

```
For `<tool>`, the agent always picks the wrong flag for `<subcommand>`. Just fix the
intent inference for that one surface. I don't want a full re-audit.
```

**Detection keywords:** "just fix `<one named flag/subcommand>`", "agent always picks wrong flag for", "intent inference for `<X>`", explicit single named surface, "don't re-audit everything".

**Mode:** `single-surface-rescore`. Phase 1 narrowed to one surface; Phase 4 narrowed to recs touching that surface; Phase 5 lands the rec.

**Ambition:** Light — one rec, one commit, one regression test.

**Skip:** CASS deep mining, multi-model triangulation, full intent corpus generation. The rec is essentially given by the user.

**Stop condition:** Single-surface rec applied + test passes + manifest updated.

---

## Variant D — Re-score after changes

**Verbatim corpus prompt:**

```
I made some changes to `<tool>` since the last agent-ergonomics pass. Re-score the
modified surfaces and tell me what improved, what regressed, and whether the previous
recommendations still apply.
```

**Detection keywords:** "re-score", "since the last pass", "did the changes work?", "what improved/regressed?", "compare to prior pass".

**Mode:** `re-score-only`. Phase 0 (verify SHA changed) + Phase 2 (re-score) + Phase 6 (uplift diff) only. No Phase 3, 4, 5, 7, 8, 9.

**Ambition:** N/A. Re-scoring is purely measurement.

**Stop condition:** `scorecard_pass_<N+1>.md` + `uplift_diff.md` + `regression_alerts.md` written. If a regression > 50 pts is detected, switch to a single-surface `full` pass focused on that surface.

---

## Variant E — Robot-mode hardening

**Verbatim corpus prompt:**

```
Add `--robot-*` mode, `capabilities --json`, and `robot-docs guide` to `<tool>`. Make
the canonical mega-command (`--robot-triage` shape) returning quick_ref +
recommendations + commands in one call. Pin schema with regression tests.
```

**Detection keywords:** "add `--robot-`", "add `capabilities`", "add `robot-docs`", "mega-command", "make agent-readable".

**Mode:** `full`. The recommendation set is essentially pre-staged: the operators Σ Mega-Command, 📜 Self-Describing, 📖 In-Tool-Docs, 🧪 Pin-The-Contract-Test dominate.

**Ambition:** Phase 8 emphasized. The five "at least one" types are all directly invoked by the user prompt — make sure each lands.

**Pre-flight check:** Does the tool already have any of these? If `<tool> capabilities` exists, don't break it; add `--json` instead. If `<tool> robot-docs` exists with different semantics, propose a renamed alternative + deprecation path.

---

## Variant F — Mega-prompt (chain everything)

**Verbatim corpus prompt:**

```
Reread AGENTS.md so it's still fresh in your mind. Apply
$agent-ergonomics-and-intuitiveness-maximization-for-cli-tools to `<tool>`
COMPREHENSIVELY. DO NOT CREATE A NEW BRANCH (work on the current branch — typically
main; fold any auto-created branch back into main first). DO NOT CREATE A SIBLING
DIRECTORY (the audit workspace lives at `<tool>/agent_ergonomics_audit/`). Be
AMBITIOUS — I expect ≥ 10 substantive landed changes for a non-trivial CLI, ≥ 5 for
a tiny one, covering ≥ 3 of the 11 dimensions, with at least one mega-command +
capabilities/robot-docs + --json + error rewrite + intent-inference handler when
missing. After Phase 5, run the verbatim "That's it??" self-prompt and re-enter
Phase 4/5 if the bar is unmet. DO NOT stop at a polite scorecard. SHIP THE CHANGES.
```

**Detection keywords:** explicit "DO NOT" clauses; both axioms (branch + sibling) verbatim; "AMBITIOUS"; "SHIP THE CHANGES"; user has read the SKILL.md.

**Mode:** `full`. Maximum ambition. Minimum confirmation overhead — the user has front-loaded all the policy decisions into the prompt.

**Ambition:** Maximum. The bar is non-negotiable in this variant.

**Behavior:** Skip intake confirmations (the user has set them all). Don't pause between phases unless an axiom is in conflict. Check in only at end of Phase 6 (uplift evidence) and Phase 9 (simulation outcomes).

**Why this variant exists:** For the user who has applied this skill multiple times and is tired of confirming the same defaults. Front-loaded policy ⇒ maximum velocity.

---

## Variant G — Resumed pass

**Verbatim corpus prompt (when manifest exists):**

```
Resume the agent-ergonomics audit on `<tool>`. There's a workspace at
`<tool>/agent_ergonomics_audit/` from a prior pass. <Tell me what changed since the
last pass | Apply more recommendations | Just re-score>.
```

**Detection signal:** `<target>/agent_ergonomics_audit/audit/manifest.json` exists.

**Sub-variants based on prior state:**

- **Same SHA, prior pass complete:** Default to `audit-only` (refresh recs). Or `simulate-only` (verify canonical tasks still work). User picks.
- **Different SHA, prior pass complete:** Default to `re-score-only` first (compute uplift), then optionally `full` Pass N+1 if regressions or new gaps.
- **Prior pass `pass_N+1_ready: false`:** Recovery mode. Re-validate manifest with `validate_pass.sh`, archive any partial state, restart from the last clean phase.
- **Prior pass had unfilled `applied:false` recs:** Resume Phase 5 on those recs.

---

## Variant H — Multi-tool family audit

**Verbatim corpus prompt:**

```
Audit and improve the agent ergonomics of the `<family>` tools as a SET — don't just
audit each binary independently. Apply cross-cut consistency dimensions:
flag-spelling parity across tools, exit-code-dictionary alignment, capabilities
schema versioning, output-envelope shape. The family-cross-cut-auditor and
parity-auditor subagents are designed for this.
```

**Detection keywords:** "as a SET", "as a family", "cross-cut consistency", "flag-spelling parity", multi-binary toolkit.

**Mode:** `full` + Swarm tier (≥ 8 workers, multi-model triangulation). See `MULTI-TOOL-FAMILY-AUDIT.md`.

**Ambition:** Maximum + cross-cut. The Phase 4 prioritization explicitly weights cross-tool consistency higher than per-tool depth.

**Special:** `family-cross-cut-auditor` subagent runs in Phases 1 and 4. The cross-cut Phase 4 produces a separate `family_recommendations.jsonl` that has recommendations affecting ≥ 2 tools.

**Anti-pattern:** Don't audit each tool sequentially as Variant A — that misses the cross-tool dimensions. Always batch the family.

---

## Variant I — MCP server alongside CLI

**Verbatim corpus prompt:**

```
The tool has both an MCP server and a CLI. Audit them as a paired system, not in
isolation — check MCP-CLI parity, ensure the MCP tool surface and the CLI subcommand
surface line up, and any divergence is intentional with documented rationale.
```

**Detection keywords:** "MCP server alongside", "tool surface and CLI surface", "paired system", presence of `mcp__` tool prefix in the user's prior prompts.

**Mode:** `full` + Squad tier. See `MCP-SERVER-AUDIT.md`.

**Special:** `parity-auditor` subagent runs in Phase 1 and Phase 4. Produces `mcp_cli_parity_gaps.jsonl`. Each gap is a recommendation candidate.

**Phase 8 hardening:** The MCP server gets the same `capabilities` / `robot-docs` treatment as the CLI — MCP `prompts/`, MCP `tools/list`, MCP `resources/list` are all agent surfaces.

---

## Variant J — CASS-mined priorities

**Verbatim corpus prompt:**

```
Mine my prior agent sessions for moments where `<tool>`'s ergonomics frustrated me or
my agents — wrong flag picked, error message that didn't teach, retry loop because of
ambiguous output. Prioritize fixing those specifically.
```

**Detection keywords:** "mine my prior agent sessions", "moments where ... frustrated", "retry loop", "wrong flag picked", "prioritize what's actually frustrating".

**Mode:** `full` + `CASS appetite=deep` (38+ targeted queries). See `CASS-MINING-RECIPES-DEEP.md`.

**Special:** Phase 4 priority formula gets `frequency × score_gap × blast_radius` where `frequency` is heavily weighted by CASS hit count for the surface. A surface that was hit 12 times in CASS with errors outranks a surface hit 0 times even if both have similar score gaps.

**Phase 0 addition:** CASS mining produces `cass_findings.jsonl` BEFORE Phase 1 inventory. The inventory is then compared against CASS findings to ensure CASS-flagged surfaces aren't missed.

---

## Variant K — Self-application (audit a Claude Code skill)

**Verbatim corpus prompt:**

```
Apply $agent-ergonomics-and-intuitiveness-maximization-for-cli-tools to itself. Or to
$<some-other-skill>. The Polish Bar still applies — every script in scripts/ should
respond to --help, every subagent should have a clean Inputs section, the SKILL.md
should pass its own first-try-inevitability test.
```

**Detection keywords:** "to itself", "to $<skill-name>", "Claude Code skill", "Polish Bar applies to skills".

**Mode:** Phase 11 (meta) via `subagents/skill-self-applier.md` and `scripts/sw-self-audit.sh`. See `SELF-APPLICATION.md`.

**Special:** "Surfaces" are different — they're the skill's scripts (responding to `--help`), the skill's subagents (their `Inputs` sections), the SKILL.md itself (its first-try test, its anchor links, its asset references). The 11 scoring dimensions still apply but with skill-specific anchors.

**Anti-pattern:** Don't audit a skill as if it were a regular CLI. The methodology adapts; the rubric stays the same; the "binary" is the skill orchestration.

---

## Variant L — Plumbing-test validation

**Verbatim corpus prompt:**

```
Run the agent-ergonomics audit on `<tool>` in `mini` mode just to verify the pipeline
works end-to-end on this repo. I'll commit to a longer pass after I see the scorecard.
```

**Detection keywords:** "verify the pipeline", "mini mode", "plumbing test", "is this skill ready for `<tool>`?".

**Mode:** `mini`. Phases 0, 1, 2 only. No Phase 3 (intent corpus), Phase 4 (recs), Phase 5 (apply).

**Ambition:** None — this is a dry-run validation, not an improvement.

**Output:** `surface_inventory.jsonl` + `agent_surfaces.jsonl` + `scorecard.md` + `heatmap.svg`. Bypasses the full pipeline so the user can validate the rubric/inventory makes sense before committing tokens to a full pass.

**Wall-time budget:** ~5–15 min on a small CLI; longer on a 1000-surface tool.

---

## Cross-variant rules

**Always do (regardless of variant):**

1. Read AGENTS.md verbatim. The kernel axioms over-rule clever variant-specific reasoning.
2. Record the variant chosen in `audit/phase0_scope_decision.md` so resumed passes know.
3. Treat the user's prompt as the authoritative variant signal — don't override based on workspace state alone.

**Never do (regardless of variant):**

1. Create a new branch (Axiom 1).
2. Create a sibling workspace (Axiom 2).
3. Auto-downgrade to `audit-only` when the user asked for `full` (Rule 4).
4. Skip the Ambition Bar self-prompt in `full` mode (Axiom 3).
5. Bundle feature work into the pass (out-of-scope; file as bead).

**Variant escalation:**

- Variant B → Variant A: User reads the audit-only report and now wants changes. Run a fresh `full` pass with the prior workspace's recs as input.
- Variant C → Variant A: The single-surface fix touches a shared primitive (error format, exit code, help template) → escalate to `full` so cross-surface effects are audited.
- Variant L → Variant A: User saw the mini scorecard and wants the full pass. Resume from Phase 3 with the existing inventory + scorecard.

**Variant downshift (rare, requires user OK):**

- Variant A → Variant B: Tool is much larger than expected (S > 1000 surfaces); user prefers to read the audit before committing to applying. Save the inventory + scorecard, file remaining phases as Pass-2 work.
- Variant H → Variant A × N: Family is too divergent to harmonize cross-cut; audit each tool independently, file family-level recs as a separate pass.

---

## Calibration data

This corpus was assembled from:
- Real applied-pass prompts captured in CASS (sessions referenced in `LESSONS-FROM-SESSIONS.md`).
- The user's stated preferences ("DO NOT CREATE A NEW BRANCH", "this skill should NEVER be making whole new sibling directories like this!!!", "I was hoping you would get a lot more practical value out of this skill").
- Sibling-skill variants from `reality-check-for-project` (`../../reality-check-for-project/SKILL.md`, outside this skill package) which encode the same intent-driven calibration pattern.

When adding a new variant, capture:
1. A real prompt (from CASS or transcript) that motivates it.
2. The mode + ambition + scope it implies.
3. The detection keywords.
4. The escalation/downshift rules to/from the other variants.

Without all four, the variant is half-formed and produces drift instead of calibration.
