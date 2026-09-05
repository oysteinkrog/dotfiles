---
name: agent-ergonomics-and-intuitiveness-maximization-for-cli-tools
description: >-
  Score and aggressively improve CLI ergonomics for AI agents. Use when auditing
  agent-friendly CLI UX, robot/json modes, help/errors, or applying fixes in-tree.
---

<!-- TOC: One Rule | Inputs | Mode Router | Skill Bootstrap | Phase Loop | Parallelism | Dimensions & Rubric | Polish Bar | Scoring Workspace Layout | IO Contracts | Anti-Patterns | Failure Modes | Pre-Flight & End | Reference Index | Scripts | Subagents | Assets | Self-Test -->

# Agent Ergonomics and Intuitiveness Maximization for CLI Tools

> **🚫 BRANCH POLICY (read this BEFORE doing anything else).** This skill **never creates a new branch**. All applied changes land directly on the currently checked-out branch — typically `main`. The legacy `agent-ergonomics-pass-N` feature-branch convention has been **removed**: do not propose it, do not create it, do not ask the user about it. If you find yourself starting on a non-`main` branch (e.g., a swarm-mate accidentally created one), the correct move is to **fold the work into `main`**, not to add another branch on top.
>
> **🗂 WORKSPACE POLICY (equally critical).** This skill **never creates a sibling directory**. The audit workspace lives *inside the target repo* at `<target>/agent_ergonomics_audit/`. The legacy sibling pattern (`<target>__agent_ergonomics_audit/` next to the repo) has been **removed**: do not create siblings, do not `git init` a separate workspace, do not place audit artifacts outside the target repo. The audit folder is committed alongside code changes to the same branch (typically `main`), so the methodology trail and the implementation trail land together. References below to `<SIBLING>` in older text should be read as `<TARGET>/agent_ergonomics_audit/` — the name is legacy; the location is **in-tree**.
>
> **🔥 AMBITION CHARTER (the second thing you read).** This skill is for *active improvement*, not for delivering a polite scorecard and stopping. A `full` pass that ships < 5 substantive surface changes has not earned the right to call itself done. Before you declare Phase 10 complete, you MUST trigger the [Ambition Bar self-prompt](#ambition-bar-the-thats-it-gate) — a verbatim "That's it??" round that forces re-entry into Phase 4/5 if the bar is unmet. Audit-only is a real mode for explicit audit/review requests; it is *not* a fallback when implementation feels hard. Default mode for any "apply / improve / harden / make agent-friendly" intent is **`full`**, regardless of CLI size.
>
> **First action — cold-context agents start here.** When activated for "audit `<TARGET>`" or "apply this skill to `<TARGET>`", the agent MUST execute these steps in order before any other work:
>
> 1. **Run intake.** Open `assets/intake-prompt.md` and ask the user the questions verbatim. Default mode: see [Mode-default heuristic](#mode-default-heuristic) below — pick a default deterministically and let the user override. **Do NOT ask about branches** — the policy is fixed (always current branch). If your intake template includes a branch question, that template is stale; ignore it.
> 2. **Pre-flight checklist.** Run `scripts/preflight.sh <TARGET>` to verify: target is a directory, target's `<TOOL>` binary builds + `--help` exits 0, `jq` + `git` + `flock` available, optional helpers (Beads `br`, Agent Mail) detected with fallback path noted. Fail fast on missing requirements with an actionable message; don't proceed to scaffold until pre-flight is green or the user has explicitly accepted the missing-helper fallback.
> 3. **Skill bootstrap (Phase 0.5).** Run the three scripts in `## Skill Bootstrap` below in EXACT order: `scaffold-workspace.sh` → `discover-cli.sh` → `check-skills.sh`. The order matters: scaffold creates the in-tree workspace at `<target>/agent_ergonomics_audit/` (legacy variable: `<SIBLING>`), so the discover-cli redirect has a real `<SIBLING>/audit/` directory to write into.
> 4. **Then enter the Phase Loop.** Phases 1→10 in `## Phase Loop` below. Each phase has a script-or-subagent invocation, an artifact, and an exit criterion. Don't skip the validation steps — `validate_pass.sh` and `validate_scorecard.sh` are mandatory between phases that produce durable artifacts.
>
> If the user is impatient ("just run it"): pick the deterministic default mode + skip CASS-mining, but always run the pre-flight + intake confirmations. Failing fast on a misconfigured target is far cheaper than salvaging a corrupted audit halfway through Phase 5.

> **In a hurry?** Read **[references/CHEAT-SHEET.md](references/CHEAT-SHEET.md)** — the dense single-page reference (~330 lines) covering everything below.

> **Need the shortest usable version?** Read **[references/QUICKREF.md](references/QUICKREF.md)** — one page that preserves the mode picker, dimensions, phase loop, ambition gate, file layout, and smoke tests.

## Trigger Preservation & Deliverables

This short frontmatter description intentionally optimizes `/sw` trigger reliability. Preserve these richer activation phrases and promises here:

- Use for: "agent ergonomics", "make CLI agent-friendly", "robot mode audit", "intuitiveness scoring", "score my CLI for agents", rebuilding a CLI's `--help` / `--json` / robot surface, and applying measurable fixes.
- Primary-user stance: AI agents are the primary user; humans still benefit from clearer CLI contracts.
- Workspace/branch policy: audit artifacts live inside `<target>/agent_ergonomics_audit/`; applied fixes land directly on the current branch, typically `main`; do not create sibling workspaces or `agent-ergonomics-pass-N` branches.
- Durable output: surfaces, scorecard, heatmap, recommendations, playbook, regression tests, post-pass simulation transcripts, and applied changes committed with the target repo.
- If the user says "use `/sw` on this skill", treat this package itself as the target and follow [methodology/SELF-APPLICATION.md](references/methodology/SELF-APPLICATION.md). Add useful guidance; do not delete useful content just to make the skill smaller.

> **The One Rule.** Design every surface of the CLI so the FIRST thing an agent instinctively tries "just works" — a feel of natural inevitability. When the agent's intent is legible but its command is technically wrong, the tool infers intent, does the right thing (or refuses with a precise, actionable explanation of what to do instead), and leaves a breadcrumb that helps the agent learn permanently. Never silent-fail. Never punish a reasonable misstep. Always provide a safe alternative for any dangerous request. Output is parseable, deterministic, and self-describing.

> **What this skill produces.** Either (a) a thorough **audit-only** scorecard + recommendations for a CLI tool's agent ergonomics (use only when the user asked for a review/audit/score, not for improvements), or (b) the **default** outcome: an **audit + apply + re-score + test** loop that lands the highest-leverage ergonomics fixes **directly on the current branch** (typically `main`), with every score, surface, recommendation, applied change, and post-pass simulation persisted as durable, machine-readable artifacts that future agents can re-score against. The bar is *measurable, dramatic uplift* on the dimensions where the tool currently scores worst — not a polite report.

---

## What This Skill Is For

You point this skill at a CLI tool repo (Rust, Go, Python, TypeScript, Bash, anything with a binary or entry point a shell can invoke) and ask one of these:

1. *"Audit this CLI for how well it works when an AI agent is the primary user."*
2. *"Score every command, flag, and error message in `<tool>` from 0–1000 across the agent-ergonomics dimensions and tell me what to fix first."*
3. *"Make this CLI feel like the first thing an agent tries actually works — apply the changes."*
4. *"Add `--robot-*` mode, `capabilities --json`, `robot-docs guide` to this tool."*
5. *"Re-run the agent-ergonomics audit on `<tool>` against the changes since the last pass and report uplift."*
6. *"Compare two passes of the audit and tell me which surfaces regressed."*
7. *"Mine my prior agent sessions for examples where this CLI's ergonomics failed me, and prioritize those."*

The skill answers each by routing through the same kernel (the One Rule + the canonical exemplars distilled in [references/exemplars/CANONICAL-EXEMPLARS.md](references/exemplars/CANONICAL-EXEMPLARS.md)), the same operator library ([references/methodology/OPERATORS.md](references/methodology/OPERATORS.md)), the same **eleven-dimension rubric** ([references/rubric/SCORING-RUBRIC.md](references/rubric/SCORING-RUBRIC.md)), and the same **ten-phase loop** that you can re-enter idempotently to drive cumulative uplift across passes.

**Not in scope.** This skill does not redesign the CLI's *features*. It re-shapes the *surface* an agent touches: command/subcommand naming, flag spelling, output format, exit codes, error messages, intent inference, self-documentation, dangerous-op safety, determinism. Feature work (new commands, real new functionality) is filed as beads for follow-up, never silently bundled into an ergonomics pass.

---

## THE AGENT-ERGONOMICS KERNEL (Universal Axioms)

<!-- KERNEL_START v1.0 -->

Every non-trivial decision this skill makes should be stress-tested against these axioms. They are default truths, not mindless scripts: if an edge case seems to break one, explain why before treating it as an exception. The first three are user-pain axioms — discovered the hard way across applied passes — and they over-rule cleverer reasoning whenever they conflict.

**Axiom 0 — The first command an agent guesses must work or be redirected with a useful hint.**
"First-try inevitability" is the whole point. Every other axiom feeds this one. When the agent's intent is legible but its command is technically wrong, the tool infers intent, does the right thing (or refuses with a precise, actionable explanation of what to do instead), and leaves a breadcrumb that helps the agent learn permanently. A surface that fails this on its canonical task is automatically a P0 finding regardless of how it scores on other dimensions.

**Axiom 1 — Never create a new branch. Always work on the current branch (typically `main`).**
The user has explicitly stated they detest auto-branching behavior. The legacy `agent-ergonomics-pass-N` feature-branch convention has been removed. If you arrive on a stale auto-branch from a prior version of this skill, fold it back into `main` before continuing. Multi-agent coordination happens through Agent Mail file reservations + Beads, not branches. This axiom over-rules any "but it's safer to branch" reasoning, including from sibling skills you may have read recently.

**Axiom 2 — Never create a sibling workspace. Audit artifacts live INSIDE the target repo.**
The audit workspace is `<target>/agent_ergonomics_audit/` — a folder inside the target's working tree, committed alongside code on the same branch. Never `git init` a separate workspace. Never `/tmp/`. Never a sibling. A single `git log` should show both the methodology and the implementation. If a legacy sibling exists from a prior run, migrate its contents into the in-tree folder before continuing — do not silently abandon prior measurement history.

**Axiom 3 — Be ambitious. A polite scorecard is a failure.**
This skill is for *active improvement*. A `full` pass that ships < 5 substantive surface changes (or < 10 for a non-trivial CLI) hasn't earned the right to call itself done. Run the [Ambition Bar self-prompt](#ambition-bar-the-thats-it-gate) verbatim before declaring done. Default mode for any "apply / improve / harden / make agent-friendly" intent is **`full`**, regardless of CLI size. If you find yourself reaching for `audit-only` because the tool is "too big to fix in one pass", **stop**. Pick the highest-leverage 10–20 surfaces and run `full` on those. Picking a focused subset is a Phase 4 prioritization decision, not a mode decision.

**Axiom 4 — Stdout is data. Stderr is diagnostics. Mixing them is a dimension-0 violation.**
`<tool> X --json | jq …` must work without `grep -v`-ing log lines out of stdout. Progress bars, status messages, deprecation warnings, debug output, and anything else that isn't the requested data goes to stderr. Mixing stdout and stderr is the #1 cause of agent fragility — it cascades into every downstream parser. Score 0 on output_parseability when violated.

**Axiom 5 — Exit codes are a documented dictionary, not vibes.**
0 = success. ≥ 1 = a specific category from a published list (1=user-input-error, 2=safety-block, 3=tool-environment-error, 4=upstream-failure, 5=conflict, …). Never use exit 1 to mean "ran fine, no results"; that's exit 0 with an empty `[]` in JSON output. Document the dictionary in `capabilities --json`. Surface it in `--help`. An agent should be able to write `case $? in 1) …; 2) …; esac` deterministically.

**Axiom 6 — Every error names the exact flag/command the agent should have used.**
"See --help" alone is failure. The error message has three required parts: (a) what failed, (b) where (file:line if applicable), (c) the *exact* command the agent should have typed instead — copy-pasteable. The `🩹 Error-Teaches` operator is the cognitive move; the rubric anchors it at §5; the cookbook in [ERROR-REWRITING-COOKBOOK.md](references/methodology/ERROR-REWRITING-COOKBOOK.md) has 17 before/after examples.

**Axiom 7 — Intent inference recovers from legible-but-wrong invocations.**
Common typos (`--jsno`, `--jason`), deprecated flag spellings, and mis-orderings either succeed-with-warning or produce a "did you mean: `--json`" hint with the exact corrected command. The Levenshtein-1 typo-correction handler is now table stakes — `scripts/extract-known-flags.sh` keeps the suggestion list in sync with source. An agent that mistypes once and gets a surgical correction *learns the spelling forever*; an agent that gets `error: unknown flag` learns nothing.

**Axiom 8 — Every read-side command has `--json` (or a `--robot-*` mode).**
Human output is the default; structured output is a flag away. The schema is documented and stable across patch versions. Stable across patch versions means: a regression test in `audit/regression_tests/` pins the schema and fails the build if it drifts. Schema-pinning is the `🧪 Pin-The-Contract-Test` operator.

**Axiom 9 — A `capabilities --json` and `robot-docs guide` surface exists for the tool.**
Without `<tool> capabilities --json`, an agent has to *remember* the contract, which means it needs an out-of-band doc lookup. With it, the agent reads the contract straight from the tool. `robot-docs guide` (or `--robot-help`) prints a paste-ready agent-targeted handbook in-tool — no external doc lookup required. Both are cheap to add and have outsized leverage.

**Axiom 10 — One mega-command returns multiple useful slices in a single call.**
The canonical mega-command shape (`<tool> --robot-triage`-style) returns `quick_ref + recommendations + commands + health` in one round-trip. Three separate read calls collapse into one. The Σ Mega-Command operator is the most-cited single uplift in CASS. See [MEGA-COMMAND-DESIGN.md](references/methodology/MEGA-COMMAND-DESIGN.md) for the four canonical shapes (TRIAGE / DIAGNOSE / PLAN / CAPABILITIES).

**Axiom 11 — Dangerous operations are gated AND offer a safe alternative.**
Every irreversible operation (delete, force-push, drop, reset, prune) requires explicit `--yes`/`--force`/`--confirm=<token>` AND the error names a safe alternative (`--dry-run`, `--plan`, `--diff`). The `🛡 Safe-Alternative-Always` operator. `dcg`'s "use git revert instead" hint is the canonical example.

**Axiom 12 — Output is deterministic; same input → same output bytes.**
Stable ordering (sorted or insertion-order). No raw timestamps in stdout — timestamps belong in JSON fields, not free text. Honors `SOURCE_DATE_EPOCH`. IDs are deterministic where possible. `verify-determinism.sh` re-runs the binary twice and diffs the bytes. Non-determinism in stdout is a Polish Bar fail.

**Axiom 13 — Honor env conventions. `NO_COLOR`, `CI`, `TERM=dumb`, `--no-color`, non-TTY all suppress styling.**
ANSI codes leaking into piped output is a recurring failure — every audit catches at least one CLI doing this. Detect non-TTY via `isatty(2)` on stdout AND honor the env vars. The `🌐 Honors-Env-Conventions` operator. `verify-non-tty-discipline.sh` is the regression test.

**Axiom 14 — Never silent-fail. Every failure produces stderr output AND non-zero exit.**
A command that fails but exits 0 with empty stdout is the agent's worst nightmare — they can't even detect the failure to retry. Crashes, network errors, lock conflicts, missing prerequisites — all must show up on stderr with a non-zero exit. The `🚫 Never-Silent-Fail` operator.

**Axiom 15 — TUI-on-bare-invocation is forbidden for agent-ergonomic CLIs.**
Bare `<tool>` (no args) launching a TUI blocks any agent that didn't know to expect it. Either `<tool>` shows useful help/triage immediately and exits, or `<tool> tui` is the explicit invocation that opens an interactive interface. Never both.

**Axiom 16 — Surfaces are scored on evidence, not vibes.**
Any score > 700 requires a concrete citation: file:line for source-defined behavior, or full `--help` excerpt + invocation transcript for runtime-discovered behavior. `tools/validate_scorecard.sh` rejects unsourced high scores. This rule applies to dimensions you *don't* think apply too — record the evidence stub explaining why (e.g. `n/a — read-only verb; no irreversible op`).

**Axiom 17 — Regression tests pin every applied recommendation.**
Each Phase 5 commit lands a test in `audit/regression_tests/R-NNN__<short>.test.{sh,rs,py,ts}`. The test must pass against the post-apply binary AND fail against a genuine pre-apply binary. Without one, the next pass can't tell "fixed" from "regressed-back". `scripts/validate_pass.sh` rejects un-tested applied recs.

**Axiom 18 — One Rule outranks all others: the One Rule (above) is the lens.**
When axioms conflict (rare but possible), Axiom 0 — first-try inevitability — is the tiebreaker. A change that improves another dimension at the cost of first-try success is the wrong change. Subtract the cost of confused agents from the value of any uplift before scoring it.

<!-- KERNEL_END v1.0 -->

These 19 axioms compose: Axiom 1 + Axiom 2 establish the irreducible "where the work lands" pact (current branch, in-tree workspace); Axiom 3 + Axiom 16 + Axiom 17 establish the "shipped, evidenced, pinned" outcome bar; Axiom 0 + Axiom 6 + Axiom 7 give the "agent-as-user" lens that drives every recommendation; Axiom 4 + Axiom 5 + Axiom 12 + Axiom 14 are the four pillars of parseable output. When you find yourself wanting to break one, slow down and check whether you've actually identified an exception or whether the kernel is right.

---

## Decision Tree — What Should Happen When the Skill Activates?

```
Step 1: classify intent (most prompts have one)
  ├── "audit / review / score / report" only → mode = audit-only
  ├── "apply / improve / harden / make agent-friendly /
  │    use this skill comprehensively" → mode = full
  ├── "did the changes work?" / "what regressed?" + prior pass exists
  │    → mode = re-score-only OR simulate-only
  └── "change just <one named flag>" → mode = single-surface-rescore

Step 2: count CLI surfaces (rough — don't block on exact)
  S = number of subcommands × (1 + avg flags-per-subcommand) + env-vars + exit-codes
  ├── S ≤ 30   → Solo tier (1 worker)
  ├── 30 < S ≤ 150 → Pair tier (2 workers, fan-out on Phase 1/2/5)
  ├── 150 < S ≤ 500 → Squad tier (4–6 workers parallel by subcommand)
  └── S > 500  → Swarm tier (8–12 workers + multi-model triangulation)

Step 3: existing maturity (auto-detected by discover-cli.sh)
  ├── tool already has --robot-* / capabilities / robot-docs → skip Phase 8
  ├── tool has only --json → Phase 8 adds capabilities + robot-docs
  ├── tool has nothing structured → Phase 8 is the heaviest lift
  └── tool has a TUI on bare invocation → P0 finding for Phase 4

Step 4: branch + workspace policy (NOT a question — fixed)
  ├── current branch is `main` → continue on `main`
  ├── current branch is `master` → continue on `master` (sync to `main` if dual)
  ├── current branch is `agent-ergonomics-pass-N` → fold into `main`, then continue
  └── current branch is something else → record as `target_branch`, continue there

Step 5: ambition (NOT a question — fixed for `full` mode)
  ├── after Phase 5: ≥ 10 substantive commits, ≥ 3 dimensions touched,
  │   one each of {mega-command, capabilities/robot-docs, --json, error rewrite,
  │   intent-inference handler} when missing → declare done
  └── otherwise → run "That's it??" self-prompt, re-enter Phase 4/5 once more
```

The five steps are independent: intent + size + maturity decide *what to do*, branch + workspace decide *where it lands*, ambition decides *when to stop*. Mixing them up is the most common confusion in the first run on a new repo.

---

## Ambition Bar (the "That's it??" gate)

This skill exists because the *first* time an agent runs an ergonomics audit, it has a strong tendency to deliver a tidy scorecard, a polite playbook, and stop — leaving the user with no actual improvements in the binary. **That outcome is a failure of this skill.** The skill is for *active improvement*; the audit is just the planning surface.

### Soft target for a `full` pass on a non-trivial CLI

Before declaring Phase 10 complete, the agent SHOULD have shipped:

- **≥ 10 substantive landed changes** on the current branch (one commit per recommendation, per the [Phase 5 cookbook](references/methodology/PHASES.md#phase-5--apply-changes-full-mode)). Tiny CLIs (≤ 5 subcommands) can target ≥ 5 landed changes instead.
- Coverage of **≥ 3 of the 11 scoring dimensions** in the applied set (don't pile all changes onto one dimension).
- At least one of each of the following types, where the tool didn't already have it:
  - a **mega-command** (the `--robot-triage` / `--robot-next` shape — see [MEGA-COMMAND-DESIGN.md](references/methodology/MEGA-COMMAND-DESIGN.md));
  - a **`capabilities --json`** or **`robot-docs guide`** surface;
  - **`--json` (or `--robot-*`) output** on at least one read-side command;
  - an **error-message rewrite** that names the exact flag/command the agent should have used (see [ERROR-REWRITING-COOKBOOK.md](references/methodology/ERROR-REWRITING-COOKBOOK.md));
  - a **typo / intent-inference handler** for the most common wrong invocation surfaced in Phase 3.
- **All applied changes have regression tests** in `audit/regression_tests/` and the project test suite is green.

These are *targets*, not gates: if Phase 6 shows real measurable uplift but the count is short, that's allowed — but it triggers the self-prompt below.

### The self-prompt (verbatim — run on yourself before declaring done)

After Phase 5 produces its first batch of applied commits and Phase 6 reports uplift, the agent MUST self-evaluate against the soft target above. If any of the following is true:

- Fewer than 5 substantive commits landed for a typical CLI;
- Phase 6 median uplift across the audited surfaces is < 50 points;
- None of the five "at least one of each" types above were added when the tool didn't already have them;
- The user-facing summary doesn't pass the test "would a skeptical user reading this say *that's it??*".

…then the agent runs the following prompt **on itself** (verbatim, paraphrasing forbidden) and re-enters Phase 4 → Phase 5 for one more round before proceeding to Phase 10:

```
That's it?? I was hoping you would get a lot more practical value out of this skill.
Where are the dramatic improvements? Re-read the playbook, look at the surfaces still
scoring below 500 on output_parseability / error_pedagogy / intent_inference /
self_documentation, and ship a substantially larger batch of high-leverage changes.
You're allowed to be ambitious. Default to acting, not deliberating.
```

After the self-prompt round, the agent may proceed to Phase 10 even if the bar is still short — but the Phase 10 HANDOFF.md must explicitly list what was deferred and why. **One self-prompt round is mandatory; a second is at the agent's discretion if the first round materially under-delivered.** Do not loop forever — convergence beats churn.

### What does NOT count as a "substantive landed change"

To prevent inflating the count:

- A whitespace edit, a typo fix, or a comment-only commit. Not substantive.
- Adding a regression test without the underlying surface change. Not substantive (the test belongs to a real change).
- Renaming a private symbol with no external behavior change. Not substantive.
- A `--help` text rewrite *without* also pinning a regression test that locks it. Marginal — counts as half.

A substantive change is one that *moves a scored surface up by ≥ 100 points on at least one dimension* and ships with a regression test that fails if the change is reverted.

### Why this section exists

When the user has to prod with "that's it??" to get the agent to actually ship improvements, the skill has failed at its core purpose. This section exists so the agent prods *itself* before the user has to. The reality-check skill calls this its "ambition rounds"; this is the same idea, baked directly into the agent-ergonomics loop.

---

## Inputs

- **Target CLI repo path** (default: cwd) — absolute path to a CLI tool's source repo, OR a git URL we should clone into `/tmp/`.
- **Audit workspace path** — **always** `<target>/agent_ergonomics_audit/` (a folder inside the target repo). This is fixed; do not create a sibling, do not use `/tmp/`, do not ask the user where to put it. Auto-detected if it already exists; resumes prior pass.
- **Pass number** (auto-detected from `audit/manifest.json`; first run = `pass 1`).
- **Mode** — `mini` (Phase 1+2 only — scorecard + heatmap, ~5 min) | `audit-only` (no code changes, recs only) | `full` (audit + apply + re-score + tests). See **Mode-default heuristic** below. Use `mini` as a "is this worth committing to?" preview.
- **Tool language(s)** — auto-detected by `scripts/discover-cli.sh` (Rust / Go / Python / TypeScript / Bash / Ruby / Java / etc.); the skill won't install a missing toolchain without explicit user approval.
- **Binary entry points** — auto-detected (Cargo bin, `package.json` bin, Go `cmd/*`, Python `entry_points`, Bash exec scripts). User can override.
- **Triangulation appetite** — `none` | `peer-claude` (two Claude subagents) | `multi-model` (Claude + Codex + Gemini via `/multi-model-triangulation`). Default: `peer-claude` for `audit-only`, `multi-model` for `full` if available.
- **CASS mining appetite** — `skip` | `quick` (10 canned queries) | `deep` (38+ queries against the user's prior agent sessions). Default: `quick` for first pass, `skip` on resumed passes unless surface count changed materially.

## Mode-default heuristic

Compute the default mode deterministically rather than blocking on the user. Compute, then present as: "I'll default to `<MODE>`. Override with `audit-only` / `full` if you'd rather."

**Intent wins over size.** Classify the user's prompt first:

- **`full` (the strong default).** Any of "apply", "improve", "fix", "harden", "make it agent-friendly", "use this skill on", "comprehensively apply", or any other phrasing that asks for the *outcome* (a more agent-ergonomic CLI). Tool size does NOT change the mode — large tools just have a larger ranked-recommendations list, and you still ship the top-N. Picking a focused 10–20-surface subset is a *Phase 4 prioritization* decision, not a mode decision.
- **`audit-only`.** ONLY when the user explicitly asked for a "review", "audit", "scorecard", "report", or "score" and did *not* ask for changes. If the prompt is ambiguous, default to `full` and tell the user "I'll apply changes; if you only wanted a report, say `audit-only`."
- **`re-score-only` / `simulate-only`.** "Did the changes work?" / "what changed since last time?" — only valid when a prior pass exists in the in-tree workspace (`<target>/agent_ergonomics_audit/`).

If you find yourself reaching for `audit-only` because the tool is "too big to fix in one pass," **stop**. Pick the highest-leverage 10–20 surfaces and run `full` on those. The whole point is to *act*. Audit-only because the size feels intimidating is the slop pattern this skill exists to defeat.

```
prior_pass     = max(.passes[].pass) from manifest.json    # 0 if first run
last_apply_age = days since last passes[-1].applied_changes_count > 0 commit
                 (∞ if no apply pass yet)

Default = "audit-only" if user prompt explicitly asks for review/audit/score only
        = "re-score-only" if user asks "did the changes work?" AND prior pass exists
        = "full"       otherwise — INCLUDING when surface count is large
                       (Phase 4 will rank; Phase 5 ships the top-N)
```

The user can override at intake. **Do not auto-downgrade `full` to `audit-only` mid-flow** because the recommendation list is long; that's a sign Phase 4 prioritization needs to be tighter, not that the apply phase should be skipped.

## Triangulation availability detection

`Triangulation appetite` defaults to `peer-claude` for `audit-only` and `multi-model` for `full` IF the latter is available. To detect availability deterministically:

```bash
have_multi_model=false

# Check 1: is the /multi-model-triangulation skill present?
if jsm list 2>/dev/null | grep -q '^multi-model-triangulation\b'; then
  have_multi_model=true
else
  for skill_root in "$HOME/.claude/skills" "${CODEX_HOME:-$HOME/.codex}/skills" "./.claude/skills"; do
    if [ -d "$skill_root/multi-model-triangulation" ]; then
      have_multi_model=true
      break
    fi
  done
fi

# Check 2: are the underlying CLIs reachable? (the skill needs at least one)
if $have_multi_model; then
  if ! { command -v codex >/dev/null 2>&1 || command -v gemini >/dev/null 2>&1 || command -v grok >/dev/null 2>&1; }; then
    have_multi_model=false  # skill installed but no peer model on PATH
  fi
fi
```

Set `Triangulation appetite=multi-model` only when both checks pass. Otherwise default to `peer-claude` (two parallel Claude subagents — always available since this skill is itself running in Claude Code).

---

## Up-Front Confirmations (Ask Before Starting)

Use the intake template at `assets/intake-prompt.md` verbatim. The summary:

1. **Target CLI path?** Confirm absolute path or clone URL. If GitHub URL, clone to `/tmp/<basename>` first. **Never** clone into a path the user didn't approve.
2. **Audit workspace location** — fixed, no question. The audit workspace is `<target>/agent_ergonomics_audit/` (a folder inside the target repo). Do NOT create a sibling. Do NOT `git init` a separate workspace. The folder is committed to the same branch as the code changes (typically `main`), so a single `git log` shows both the methodology and the implementation.
3. **Mode?** `audit-only` (read-only, scoring + recommendations only, no code changes) or `full` (audit + apply + re-score + tests). Default: `full` for any "apply / improve / make agent-friendly" intent; `audit-only` only when the user explicitly asked for a review/score/report.
4. **Resuming a prior run?** If `<target>/agent_ergonomics_audit/audit/manifest.json` exists, read its `pass` field; offer to start `pass N+1` (preserves all history) or `re-score current pass` (re-runs scoring against the same SHA).
5. **Toolchain consent.** If the target CLI is in a language whose toolchain isn't installed (e.g. Rust target, no `cargo`; Go target, no `go`), ask before installing it. Phase 1 needs to *invoke* the binary, so the toolchain must be present.
6. **Triangulation + CASS appetite** — confirm defaults above.
7. **Scope guardrails.** Confirm the user's "must not touch" list: features they don't want refactored, deprecation policies (e.g. "you may add but never remove"), config files that must remain backwards-compatible, etc. Persisted to `audit/phase0_scope_decision.md`.

### Branch Policy (NOT a question — fixed)

This skill **never creates a feature branch**, **never asks the user about a branch name**, and **never proposes one**. All applied changes commit directly to the currently checked-out branch of the target repo (typically `main`). Reasons:

- Users running this skill have repeatedly told us they detest the auto-branch behavior.
- Multi-agent swarms working on the same repo coordinate through Agent Mail file reservations and Beads, not through branches; an extra branch just fragments work.
- The in-tree audit *workspace* at `<target>/agent_ergonomics_audit/` already lives in the target's git history — adding a separate branch on top of that adds no information, just friction.

If you arrive on a non-`main` branch (e.g., a teammate created `agent-ergonomics-pass-1` from an older revision of this skill), **the correct move is to fold that branch into `main` first** (merge or fast-forward, with the user's confirmation if conflicts exist), then continue on `main`. Do not start a new pass on the stale branch.

If the user *explicitly* says "use a branch called X" in their prompt, honor that — but the default and silent behavior is "current branch."

After the user answers, send the matching kickoff prompt from [references/methodology/KICKOFF-PROMPTS.md](references/methodology/KICKOFF-PROMPTS.md) verbatim.

If any helper SKILL referenced here is missing (`/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/multi-pass-bug-hunting`, `/multi-model-triangulation`, `/ubs`, `/dcg`, `/agent-mail`, `/beads-br`, `/beads-bv`, `/cass`, `/idea-wizard`, `/gh-cli`, `/cc-hooks`): if the user has `jsm` installed and authenticated, offer to `jsm install <name>` for each missing one. Don't block a phase if a polish skill is missing — note it and proceed with the inline fallback in [references/methodology/SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md).

`bun`, `cargo`, `uv`, `gh`, `git`, `jq`, `node` are TOOLCHAINS (binaries on PATH), not skills. Verify they're installed during pre-flight (Phase 0); if missing, instruct the user to install via the platform's package manager (`apt`, `brew`, `cargo install`, etc.). Do NOT attempt `jsm install bun` — `jsm` only ships skills.

---

## Skill Bootstrap (Phase 0.5 — right after inputs, before Phase 1)

**Order matters.** The scaffold creates the in-tree workspace at `<target>/agent_ergonomics_audit/` (legacy variable: `<SIBLING>`); the discover-cli output gets redirected into `<SIBLING>/audit/`; both feed check-skills. Run them in this exact order:

```bash
# 1. Create the audit workspace FIRST. Without this, the redirect on step 2
#    has nowhere to land. <sibling> = <target>/agent_ergonomics_audit/ (in-tree).
./scripts/scaffold-workspace.sh <sibling> <target>
# Creates audit/, audit/regression_tests/, audit/agent_simulations/{pre,post_pass_N},
# audit/partial/, audit/.archive/, tools/, .gitignore (excludes pass-local
# scratch); writes a populated audit/manifest.json seeded with tool_name,
# tool_repo, audit_workspace, current_pass: 1. Does NOT run `git init` —
# the workspace lives inside the target repo and is tracked by the target's
# existing git history.

# 2. Run discover-cli, redirect its JSON to the now-existing audit dir.
./scripts/discover-cli.sh <target> > <sibling>/audit/phase0_cli.json
# Detects language, build system, binary entry points, completion-script paths,
# config-file schemas, env-var prefix conventions, embedded man pages.

# 3. Inventory helper skills (jsm state, /agent-mail availability, etc.).
./scripts/check-skills.sh <sibling>/audit
# Writes phase0_skill_inventory.json. Run last because it reads phase0_cli.json
# to decide which language-specific helper skills are relevant.
```

If skills are missing and `jsm` is installed + authenticated:

```bash
./scripts/install-referenced-skills.sh <sibling>/audit
```

If `jsm` isn't installed, offer the official installer (Linux/macOS):

```bash
curl -fsSL https://jeffreys-skills.md/install.sh | bash
```

Then `jsm login`. Requires a paid [jeffreys-skills.md](https://jeffreys-skills.md) subscription to install premium skills. The pipeline degrades gracefully without `jsm` — every helper skill has an inline fallback playbook.

Full bootstrap detail: **[references/methodology/SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md)**.

---

## Mode Router

Pick the primary mode first. The phase loop is the same; the **stop conditions and required artifacts** differ.

| Mode | Use when | Must finish with |
|------|----------|------------------|
| `audit-only` | Existing CLI; user explicitly asked for a scorecard + recommendations only | `agent_surfaces.jsonl`, `scorecard.md`, `heatmap.svg`, `recommendations.jsonl`, `playbook.md`, `agent_simulations/pre/`, `manifest.json` (no code changes touch the target repo) |
| `full` | **Default.** User wants the gaps fixed with measurable uplift | everything in `audit-only` + per-recommendation commits **on the current branch** of the target (typically `main`) + `regression_tests/` green + Phase 6 re-score showing uplift + Phase 9 post-pass simulation transcripts + Ambition Bar self-prompt round before declaring done |
| `re-score-only` | Resumed run; user wants Phase 2 re-run against the current target HEAD with no other changes | new `scorecard_pass_N+1.md`, `uplift_diff.md`, `regression_alerts.md` for any surface that dropped > 50 points |
| `simulate-only` | Validation run; user wants a fresh-eyes agent to attempt canonical tasks against the current binary | `agent_simulations/post_pass_N/` with full transcripts + per-task pass/fail/round-trip counts |
| `single-surface-rescore` | Targeted; user changed one surface and wants to know the new score | one row appended to `agent_surfaces_pass_N+1.jsonl` for the named `surface_id`; everything else unchanged |

Auto-detect heuristics: `scripts/discover-cli.sh` looks for `audit/manifest.json` (resumed run), `Cargo.toml` / `go.mod` / `package.json` / `pyproject.toml` (language), and a `--robot-*` / `--json` / `capabilities` surface (existing maturity). Picks the mode and shows reasoning; user can override.

**Single-surface guard.** If the user asks for one bounded change (e.g. "just add `--json` to the `list` subcommand"), start in `single-surface-rescore` and only score that one `surface_id`. Escalate to `full` only when the change crosses a shared primitive: error-message format, exit-code contract, or `--help` template.

Full mode definitions, exit criteria, and required artifacts: **[references/methodology/OPERATING-MODES.md](references/methodology/OPERATING-MODES.md)**.

---

## The Phase Loop (Mandatory)

```
Phase 1  SURFACE INVENTORY & ARCHAEOLOGY     enumerate every agent surface (parallel by subcommand)
Phase 2  RUBRIC-DRIVEN SCORING               two scorers per surface + tiebreaker; median + spread
Phase 3  INTENT-INFERENCE STRESS TEST        naive-agent + savvy-agent corpora; corpus_id'd
Phase 4  RECOMMENDATION SYNTHESIS            propose fixes; merge; rank by priority; triangulate top 10
Phase 5  APPLY CHANGES (full mode)           per-recommendation commit on the current branch (typically main); file reservations via Agent Mail
Phase 6  RE-SCORE & UPLIFT VERIFICATION      regress against pre-pass; flag regressions; loop until quiet
Phase 7  FRESH-EYES BUG & ERGONOMIC REVIEW   the three calibrated prompts; ubs; lint; until clean twice
Phase 8  SELF-DOCUMENTATION HARDENING        ensure capabilities, robot-docs, --robot-*, schema export
Phase 9  AGENT-IN-THE-LOOP VERIFICATION      fresh subagent attempts canonical tasks; transcripts captured
Phase 10 HANDOFF & ITERATION-READINESS       HANDOFF.md, beads for next pass, idea-wizard, push the plane
```

**Phases 4, 5, 6, 7** are *reapply-until-quiet* — keep spawning passes until an entire pass produces only trivial edits (a typo, a comment, no surface scoring change > 25 points). Phase 7's two clean rounds are the explicit termination gate before Phase 8.

**Phase 11 (meta — self-application).** Optional. Apply this very skill to itself or to another Claude Code skill via `subagents/skill-self-applier.md` and `scripts/sw-self-audit.sh`. Use to keep the agent-ergonomics methodology honest: if the skill cannot pass its own polish bar, neither can anything it audits. See [methodology/SELF-APPLICATION.md](references/methodology/SELF-APPLICATION.md).

**Phase 7 fresh-eyes prompts** (use verbatim — they're calibrated):

1. *"Carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover."*
2. *"Sort of randomly explore the code files in this project, choosing code files to deeply investigate and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes. Comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in AGENTS.md."*
3. *"Turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep."*

Repeat until two consecutive rounds come up clean except for trivial changes. Then run `ubs` (if available), the project's typecheck/lint/test suite, and the regression tests in `audit/regression_tests/`. Fix everything.

### Termination thresholds (Phase 4/5/6 loop exit criteria)

The loop terminates when ALL of:

- Median absolute uplift in the last pass is **< 25 points** across all surfaces.
- **No surface regressed** by more than 50 points (a regression > 50 is a **hard stop** — investigate before continuing).
- Phase 4 produced no new top-10 recommendation that wasn't a near-duplicate of one already applied.
- Phase 7 fresh-eyes ran clean two times in a row (only trivial edits).

Full per-phase playbook with exit criteria + exact prompts: **[references/methodology/PHASES.md](references/methodology/PHASES.md)** and **[references/methodology/AGENT-PROMPTS.md](references/methodology/AGENT-PROMPTS.md)**.

---

## Parallelism Model

The CLI's surface partitions naturally along subcommand and surface-class boundaries.

```
┌────────────────────────────────────────────────────────────────────────┐
│  PARTITION (Phase 1, by main agent)                                    │
│  ─> recursive --help walk: enumerate top-level subcommands             │
│  ─> assign one surface-inventorist subagent per subcommand subtree     │
│     plus dedicated agents for env vars, exit codes, error corpus,      │
│     completion scripts, config-file schemas, signal handlers           │
└────────────────┬───────────────────────────────────────────────────────┘
                 │
   ┌─────────────┼──────────────┬──────────────┬────────────────────────┐
   ▼             ▼              ▼              ▼                        ▼
┌────────┐  ┌─────────┐    ┌──────────┐   ┌──────────┐           ┌──────────────┐
│ subcmd │  │ subcmd  │    │ env-vars │   │ exit-    │           │ error-msg    │
│ inv. A │  │ inv. B  │ …  │ inv.     │   │ codes    │           │ corpus       │
└───┬────┘  └────┬────┘    └────┬─────┘   └────┬─────┘           └──────┬───────┘
    │            │              │              │                        │
    └────────────┴──────────────┴──────────────┴────────────────────────┘
                                │
                                ▼
                  ┌──────────────────────────┐
                  │ Phase 2 SCORING          │  ≥2 scorers per surface, median;
                  │ (parallel by surface_id) │  warn at 200, tiebreak at ≥300
                  └──────────────┬───────────┘
                                 ▼
                Phase 3 INTENT STRESS (naive + savvy agents)
                                 ▼
                Phase 4 RECOMMENDATIONS (synthesis + triangulation)
                                 ▼
        Phase 5 APPLY (one bead per recommendation, current branch (typically main), reservations)
                                 ▼
                Phase 6 RE-SCORE swarm (parallel by surface_id again)
                                 ▼
                Phase 7 FRESH-EYES swarm (multi-model if available)
                                 ▼
                Phase 9 SIMULATION (fresh agent, canonical tasks)
```

**Coordination.** Use [MCP Agent Mail](../agent-mail/SKILL.md) file reservations whenever a Phase 5 implementer touches a file another implementer is also editing (especially `--help` output strings, error-message catalogs, config schemas, and the canonical output-format module). Thread id: `agent-ergo-<pass>-<phase>-<surface_id>`.

**Orchestration tier** — pick based on tool size:

| Tier | Shape | When |
|------|-------|------|
| Solo | 1 worker, serial phases | Tiny tool, ≤ 5 subcommands, ≤ 30 flags |
| Pair | 2 workers, fan-out only on Phase 1/2/5 | Typical CLI, 6–15 subcommands |
| Squad | 4–6 workers, parallel by subcommand | Full CLI suite, 16–40 subcommands |
| Swarm | 8–12 workers, beads-driven + multi-model triangulation in Phase 4/7 | Multi-binary toolkit (e.g. cargo + cargo-audit + cargo-deny family); ≥ 41 subcommands; rewriting an entire CLI surface |

Triangulation is reserved for Phase 4 (synthesizing top-10 recommendations) and Phase 7 (fresh-eyes), where independent reads produce the highest signal. See **[references/methodology/ORCHESTRATION.md](references/methodology/ORCHESTRATION.md)**.

---

## The Eleven Scoring Dimensions

Every scorable surface ("**agent surface**" — a verb, subcommand, flag, argument, env var, exit code, error message, prompt, interactive confirmation, file format, lockfile, cache directory, signal handler, or side-effect surface) gets a 0–1000 score across each of these eleven dimensions. Rubric anchors at 0/250/500/750/1000 are in **[references/rubric/SCORING-RUBRIC.md](references/rubric/SCORING-RUBRIC.md)** with concrete examples drawn from `dcg`, `bv`, `am`, `ubs`, and `cass`.

| # | Dimension | The question it answers |
|---|-----------|-------------------------|
| 1 | **agent_intuitiveness** | Would the first command an agent guesses succeed, or be redirected with a useful hint? |
| 2 | **agent_ergonomics** | Minimum keystrokes / tool-calls / round-trips to accomplish the canonical task; macros vs. granular composition where relevant. |
| 3 | **agent_ease_of_use** | Discoverability without external docs (`--help`, `capabilities`, self-describing JSON, `robot-docs`). |
| 4 | **output_parseability** | Stable schema, `--json` / `--robot-*` mode, stdout-data / stderr-diagnostics separation, exit-code contract. |
| 5 | **error_pedagogy** | Does the error message teach? Suggest the safe alternative? Cite the exact flag the agent should have used? |
| 6 | **intent_inference** | How gracefully does the tool recover from a legible-but-wrong invocation (typos, deprecated flags, common mis-orderings)? |
| 7 | **safety_with_recovery** | Irreversible operations gated; safe alternatives always offered; reservations / leases / dry-runs available. |
| 8 | **determinism_and_reproducibility** | Stable output ordering, no wall-clock leakage, deterministic IDs, content-addressed where possible. |
| 9 | **self_documentation** | `--help` quality, embedded examples, `capabilities` endpoint, machine-readable schema export. |
| 10 | **composability** | Exit codes / stdout work cleanly in pipelines; no surprise interactive prompts in non-TTY mode; honors `NO_COLOR`, `CI`, `--yes`. |
| 11 | **regression_resistance** | Golden tests, snapshot tests, schema-pinned outputs that protect ergonomics from drift. |

**Threshold rule.** Any score > 700 requires concrete evidence cited in the surface record (file:line for source-defined behavior, or full `--help` excerpt + invocation transcript for runtime-discovered behavior). Scoring without evidence is rejected by `tools/validate_scorecard.sh`.

**Priority** is computed per-surface as: `priority = frequency × score_gap × blast_radius` where `frequency` is "how often agents hit this surface" (estimated from CASS mining + canonical-task usage), `score_gap = 1000 − weighted_avg(dimension_scores)`, and `blast_radius` is "how badly does it stay-bad if unfixed" (rubric in [references/rubric/PRIORITY-FORMULA.md](references/rubric/PRIORITY-FORMULA.md)).

**Recommendation block** (one per below-quartile surface): minimal diff sketch, expected score-after-fix per dimension, risk notes, test additions required.

The rubric and dimension list are **overridable** via `references/rubric/SCORING-RUBRIC.md` (which the skill ships with sensible defaults). Users extend it for their own taxonomy without forking the skill.

---

## The Polish Bar (Non-Negotiable)

Every shipped CLI must satisfy these on its primary surfaces. If a surface fails a dimension, that's a Phase 5 rework target.

| Dimension | Test |
|-----------|------|
| **First-try success** | `<tool>`, `<tool> --help`, `<tool> help <subcmd>` all produce useful output (never a stack trace, never silent exit, never a TUI that blocks an agent). |
| **JSON everywhere** | Every read-side command has `--json` or `--robot-*`. Output schema is documented. Stdout is data-only; stderr is diagnostics-only. |
| **Capabilities endpoint** | `<tool> capabilities --json` returns version, contract version, feature flags, command list, exit-code dictionary, env-var dictionary. |
| **Robot-docs endpoint** | `<tool> robot-docs guide` (and/or `--robot-help`) prints a paste-ready agent-targeted handbook in-tool — no external doc lookup required. |
| **Mega-command** | At least one `<tool> --robot-triage`-style mega-command returns multiple useful slices in a single call (quick_ref + recommendations + commands + health), with copy-paste-ready follow-up commands embedded. |
| **Exit-code contract** | 0 = success, ≥1 = documented categories (1=user-input-error, 2=safety-block, 3=tool-environment-error, …). Never use exit 1 to mean "ran fine, no results." |
| **Error pedagogy** | Every error message names: (a) what failed, (b) where (file:line if applicable), (c) the *exact* flag/command the agent should have used instead. No "see --help" on its own. |
| **Intent inference** | Common typos (`--jsno`, `--jason`), deprecated flag spellings, and mis-orderings either succeed-with-warning or produce a "did you mean" hint with the exact corrected command. |
| **Dangerous-op gating** | Every irreversible operation (delete, force-push, drop, reset, prune) requires explicit `--yes`/`--force`/`--confirm=<token>` AND offers a safe alternative (`--dry-run`, `--plan`) named in the error. |
| **Determinism** | Output ordering is stable (sorted or insertion-order). No raw timestamps in stdout (timestamps belong in JSON fields, not free text). IDs are deterministic where possible. Honors `SOURCE_DATE_EPOCH`. |
| **NO_COLOR / CI / non-TTY** | Tool detects non-TTY and skips ANSI codes, progress bars, interactive prompts. `NO_COLOR=1`, `CI=true`, `--no-color` all suppress styling. |
| **Regression test** | Every applied recommendation lands a golden/snapshot test in `audit/regression_tests/` named after the recommendation ID (`R-NNN__<short_description>`). |

If a surface can't satisfy these, it fails the bar. Full rubric, per-dimension queries, and dispute-resolution flowchart: **[references/methodology/POLISH-BAR.md](references/methodology/POLISH-BAR.md)**.

---

## Cognitive Operators (Agent-Ergonomic Thinking Moves)

Composable moves. Apply to any surface, any error message, any flag-design decision. **The full library is 33 operators** with triggers, failure modes, and prompt modules in **[references/methodology/OPERATORS.md](references/methodology/OPERATORS.md)**. The 17 below are the **most-used core**; OPERATORS.md adds 16 more (Recommended-Action `🪄`, Provenance-Field `🪟`, Schema-Pin `📐`, Doctor-Mode `🩻`, Telemetry-Disable `🔇`, Discovery-Footer `🎯`, Two-Phase-Latency `🪜`, Cross-Verb-Reference `🔗`, Identity-Friction-Collapse `🛂`, Stable-Envelope `📦`, Single-Step-Atomicity `🔬`, Idempotency-Pin `🧷`, Composable-Verbs `🧶`, Bulk-Friendly `🧮`, Drift-Guard `🧾`, Onboarding-Curve `🎓`).

| Glyph | Name | Question | Fix-pointer |
|-------|------|----------|-------------|
| `①` | **First-Try-Inevitability** | "If an agent that's never seen this tool guesses a command, does it work or get a useful redirect?" | Rubric §1, exemplar: `bv --robot-triage` |
| `Σ` | **Mega-Command** | "Can three round-trips collapse into one mega-call returning quick_ref + recommendations + commands?" | Rubric §2, exemplar: `bv --robot-triage` |
| `⟁` | **Intent-Infer-Then-Act** | "If the invocation is wrong but the intent is legible, can we infer-and-warn instead of error-and-stop?" | Rubric §6, exemplar: `dcg explain` |
| `🛡` | **Safe-Alternative-Always** | "For every dangerous op, is there a `--dry-run` / `--plan` / safe-alt named in the error?" | Rubric §7, exemplar: `dcg`'s "use git revert instead" hint |
| `📜` | **Self-Describing** | "Does `<tool> capabilities --json` exist and pin the contract?" | Rubric §9, exemplar: `cass capabilities --json` |
| `📖` | **In-Tool-Docs** | "Does `<tool> robot-docs guide` make external doc lookup unnecessary?" | Rubric §9, exemplar: `cass robot-docs guide` |
| `🚦` | **Exit-Code-Contract** | "Are non-zero exits a documented dictionary, not ad-hoc?" | Rubric §4, exemplar: `ubs` (0=safe, ≥1=fix) |
| `🪧` | **Stdout-Data-Stderr-Diag** | "Does `<tool> X --json | jq …` work without grep-filtering log lines?" | Rubric §4, §10, exemplar: all of `cass`, `bv`, `ubs` |
| `🧪` | **Pin-The-Contract-Test** | "Does this surface have a golden/snapshot test that fails if `--help` text or output schema drifts?" | Rubric §11, exemplar: cass `--robot-meta` schema-pinned |
| `🔀` | **Macros-vs-Granular** | "Is the canonical task a single macro? Is the granular path also exposed for control?" | Rubric §2, exemplar: `am macro_start_session` vs granular `register_agent` |
| `🆔` | **Stable-Handle** | "Does the tool give every artifact a stable, content-addressed handle (project_key, surface_id, request_id)?" | Rubric §8, exemplar: `am` project_key |
| `🩹` | **Error-Teaches** | "Does this error name the *exact* flag the agent should have used?" | Rubric §5, exemplar: `dcg` block message |
| `🚫` | **Never-Silent-Fail** | "If something goes wrong, does the user see *something* on stderr with non-zero exit?" | Rubric §5, §10, exemplar: rejected pattern in [references/exemplars/COUNTER-EXAMPLES.md](references/exemplars/COUNTER-EXAMPLES.md) |
| `⏱` | **Sub-Second-Hot-Path** | "Does the canonical first invocation return in < 1s?" | Rubric §2, exemplar: `dcg` quick-reject filter |
| `🌐` | **Honors-Env-Conventions** | "Does the tool honor `NO_COLOR`, `CI`, `TERM=dumb`, `SOURCE_DATE_EPOCH`, `XDG_*`?" | Rubric §10 |
| `🔢` | **Deterministic-Output** | "Same input → same output bytes? Stable ordering? No timestamp leakage?" | Rubric §8 |
| `🧭` | **Discoverable-From-Help** | "Does `--help` mention `--json`, `capabilities`, `robot-docs`, `--robot-*` modes?" | Rubric §9 |

Composition cheat-sheet (operator pipelines per failing dimension): [references/methodology/OPERATORS.md § Composition](references/methodology/OPERATORS.md).

---

## Operator Stacks (the most-shipped Phase 5 patterns)

In practice, single operators are rarely shipped in isolation — the highest-leverage Phase 5 commits stack 3–5 operators together. These are the canonical stacks distilled from prior applied passes; they're the seed set for [AMBITION-PLAYBOOK.md](references/methodology/AMBITION-PLAYBOOK.md).

### Stack A — The Mega-Command Triple

```
Σ Mega-Command  +  📜 Self-Describing  +  📖 In-Tool-Docs  +  🧪 Pin-The-Contract-Test
```

**What it ships:** `<tool> --robot-triage` (or equivalent) returning `quick_ref + recommendations + commands + project_health` in a single call. Plus `<tool> capabilities --json` returning the schema. Plus `<tool> robot-docs guide` returning the agent handbook. Plus the regression test pinning the schema.

**Dimensions affected:** agent_ergonomics (+400–600), agent_intuitiveness (+250), self_documentation (+400–600), regression_resistance (+150).

**When the stack is the right move:** Every CLI without an agent-readable mega-command. This is the single highest-leverage Phase 5 commit on most CLIs.

**Worked exemplar:** `bv --robot-triage`. See [exemplars/CANONICAL-EXEMPLARS-DEEP.md](references/exemplars/CANONICAL-EXEMPLARS-DEEP.md) for the actual code-level shape.

### Stack B — The Output-Contract Quartet

```
🪧 Stdout-Data-Stderr-Diag  +  🚦 Exit-Code-Contract  +  🔢 Deterministic-Output  +  🌐 Honors-Env-Conventions
```

**What it ships:** Stdout becomes data-only. Stderr becomes diagnostics-only. Exit codes get a documented dictionary. Output is byte-deterministic across re-runs. `NO_COLOR`/`CI`/non-TTY/`SOURCE_DATE_EPOCH` all honored.

**Dimensions affected:** output_parseability (+300–500), composability (+300–400), determinism_and_reproducibility (+250).

**When the stack is the right move:** Tool emits ANSI codes into piped output OR mixes log lines into stdout OR has variable output across re-runs. Almost every audit catches at least one of these.

**Worked exemplar:** `cass` post-2026-04 — pure JSON stdout, all diagnostics on stderr, exit-code dictionary in `cass capabilities --json`.

### Stack C — The Intent-Recovery Triad

```
⟁ Intent-Infer-Then-Act  +  🩹 Error-Teaches  +  🚫 Never-Silent-Fail
```

**What it ships:** Levenshtein-1 typo correction on flags (`--jsno` → `--json` with hint). Error messages name the exact corrected command. Common misspellings (`--colour`/`--licence`) recognized and inferred. No silent failures — every error path exits non-zero with stderr.

**Dimensions affected:** intent_inference (+300–500), error_pedagogy (+300–500), agent_intuitiveness (+200).

**When the stack is the right move:** Phase 3 intent corpus shows ≥ 5 wrong-invocation outcomes are `useless_error` instead of `useful_hint`.

**Worked exemplar:** `dcg explain` — recognizes near-misses on dangerous-command patterns and explains exactly what was blocked + the safe alternative.

### Stack D — The Safety Pair

```
🛡 Safe-Alternative-Always  +  🩹 Error-Teaches
```

**What it ships:** Every dangerous op gated behind `--yes`/`--confirm`. Every dangerous-op error names the safe alternative (`--dry-run`, `--plan`). `--dry-run` flag added to mutating commands.

**Dimensions affected:** safety_with_recovery (+400–600), error_pedagogy (+200).

**When the stack is the right move:** Tool has any irreversible op without a `--dry-run` mode OR without explicit confirmation. dcg-like tools, repo-mutating CLIs.

**Worked exemplar:** `dcg`'s "use git revert instead of git reset --hard" hint pattern.

### Stack E — The Self-Describing Pair

```
📜 Self-Describing  +  🆔 Stable-Handle
```

**What it ships:** `capabilities --json` includes `version`, `contract_version`, `feature_flags`. Every entity the tool produces has a stable, content-addressed handle (project_key, surface_id, request_id, content_hash). IDs are deterministic across machines.

**Dimensions affected:** self_documentation (+250), determinism_and_reproducibility (+200), composability (+150).

**When the stack is the right move:** Tool produces entities with auto-increment IDs (different across machines) OR has no schema versioning.

**Worked exemplar:** `am` (mcp-agent-mail) — `project_key` is content-derived, every message has a stable handle.

### Stack F — The Discoverability Trio

```
🧭 Discoverable-From-Help  +  📖 In-Tool-Docs  +  🪧 Stdout-Data-Stderr-Diag
```

**What it ships:** `--help` references `--json`, `capabilities`, `robot-docs`, `--robot-*` modes (so an agent reading `--help` learns about the structured surface). `robot-docs guide` exists. Help itself is on stderr or stdout per agent convention (data on stdout).

**Dimensions affected:** self_documentation (+300), agent_ergonomics (+150), agent_intuitiveness (+100).

**When the stack is the right move:** `--help` is human-only (no mention of `--json`, no mention of robot surfaces) but the tool already has those surfaces — they're undiscoverable.

### How to compose stacks

When Phase 4 produces a single recommendation, ask: "Does it pull in adjacent operators?" Most do. The synthesizer subagent merges semantically-overlapping recs. The applier subagent commits the stack as a single coherent commit.

**Stacking rules:**
- A stack is one commit; reviewing one diff that hits 4 operators is more readable than 4 diffs that hit 1 operator each.
- Stacks that exceed 5 operators usually decompose into 2 stacks; the synthesizer flags this.
- Cross-stack contradictions (rare) get resolved in the playbook before Phase 5 starts.

Full stack catalog with per-language code: [references/methodology/WORKED-OPERATOR-COMPOSITIONS.md](references/methodology/WORKED-OPERATOR-COMPOSITIONS.md).

---

## Agent Profiles (the rubric weights aren't universal)

Different agents have different working-memory shapes, retry semantics, and tolerance for ambiguity. The 11-dimension rubric's anchors are the same across profiles, but the **weights** differ — what's a deal-breaker for Claude Code might be merely annoying for Codex CLI.

### Profile: Claude Code (the canonical primary user)

**Strengths:** Long-context reasoning, multi-file edit, strong JSON parsing, follows Markdown structure well.

**Weaknesses:** Can be slow; tools that gate behind interactive prompts in non-TTY get stuck.

**Rubric weight overrides:**
- agent_ergonomics ×1.5 (round-trip cost is high for Claude Code; mega-commands matter more)
- composability ×1.3 (non-TTY discipline is critical)
- self_documentation ×1.2 (Claude Code reads `capabilities` aggressively)
- intent_inference ×1.0 (baseline; Claude tolerates some friction)

### Profile: Codex CLI (sandboxed agent)

**Strengths:** Sandboxed by default, careful about destructive ops, structured tool calls.

**Weaknesses:** Network access often restricted; tools that need network for `--help` fail.

**Rubric weight overrides:**
- determinism_and_reproducibility ×1.4 (sandboxed re-runs need byte-identical output)
- safety_with_recovery ×1.3 (Codex tends to retry; safe re-runs matter)
- composability ×1.4 (sandbox discipline)
- intent_inference ×0.9 (Codex types more carefully than Claude)

### Profile: Gemini CLI (multimodal agent)

**Strengths:** Good at visual tasks, can read screenshots, sometimes runs ad-hoc Python.

**Weaknesses:** Inconsistent JSON parsing on edge cases; sometimes "helps" by reformatting output.

**Rubric weight overrides:**
- output_parseability ×1.4 (Gemini's JSON parser is the strictest)
- regression_resistance ×1.3 (output-format drift bites Gemini hardest)
- agent_intuitiveness ×1.2 (Gemini guesses more aggressively)
- error_pedagogy ×1.0 (baseline)

### Profile: smaller models (e.g. Haiku)

**Strengths:** Fast, cheap, good for high-volume scoring.

**Weaknesses:** Short context, weaker reasoning on novel error messages, can miss subtle intent.

**Rubric weight overrides:**
- agent_intuitiveness ×1.5 (fewer second chances)
- error_pedagogy ×1.5 (small models read errors more literally)
- intent_inference ×1.3 (small models don't infer well — explicit help matters more)
- agent_ergonomics ×1.0 (baseline)

### Profile: IDE-integrated (Cursor, Continue, Claude Code IDE plugin)

**Strengths:** Full file context, can edit interactively.

**Weaknesses:** Often runs commands in a sub-shell where TTY detection lies.

**Rubric weight overrides:**
- composability ×1.3 (TTY-detection edge cases)
- self_documentation ×1.2 (IDE agents lean heavily on hover-help-style discovery)
- agent_ergonomics ×0.9 (IDE agents tolerate more round-trips than CLI agents)

### How to apply profile weights

The default profile is **Claude Code** (since this skill itself runs in Claude Code). For audits where the user names a target agent (e.g. "make this CLI work with Codex specifically"), apply that profile's weights to the priority formula:

```
weighted_priority = frequency × score_gap × blast_radius × profile_weight_multiplier
```

The profile is recorded in `phase0_scope_decision.md`. Multi-profile audits (rare) compute the priority across profiles and use the max.

Full per-profile rubric weights and CLI-specific examples: [references/methodology/AGENT-PROFILES.md](references/methodology/AGENT-PROFILES.md).

---

## Self-Pacing Decision: When to Stop, When to Loop, When to Escalate

This skill has feedback loops at multiple scales. The rule of thumb is: **converge by signal, not by time.**

### Within-phase loops (Phase 2 tiebreaks, Phase 5 retries)

- **Phase 2 spread ≥ 300:** Spawn tiebreaker; if it produces a clean median, accept; if not, escalate to user.
- **Phase 5 applier failure (test red after edit):** Up to 3 retries with refined diff sketch; then defer the rec.
- **Phase 7 fresh-eyes finding:** Apply the fix; re-run; until 2 consecutive rounds clean.

### Cross-phase loops (Phase 4↔5↔6, Phase 7 reapply-until-quiet)

- **Phase 4→5→6 cycle:** Re-enter when (median uplift in last cycle ≥ 25 pts) AND (no surface regressed > 50 pts) AND (Phase 4 produced new top-10 recs not yet applied).
- **Phase 4→5→6 termination:** Stop when (median uplift < 25 pts) OR (Phase 4 produces only near-duplicates of already-applied recs).
- **Phase 7 termination:** Stop when 2 consecutive fresh-eyes rounds produce only trivial edits.

### Cross-pass loops (Pass N → Pass N+1)

- **Re-run trigger:** target HEAD differs from manifest's `target_sha` AND user wants new uplift.
- **Re-run skip:** target HEAD == manifest's `target_sha` AND `pass_N+1_ready: false` (recover the in-progress pass first).
- **Stop condition:** All Polish Bar items satisfied across all surfaces; subsequent passes find only minor refinements.

### Ambition Bar self-prompt loop

- **Fires when:** End of Phase 9, before Phase 10, if Ambition Bar gates unmet.
- **Self-prompt:** Verbatim "That's it??" prompt. NOT a paraphrase.
- **Re-enters:** Phase 4 (re-rank, possibly add new recs from playbook) → Phase 5 (apply more) → Phase 6 (re-score).
- **Termination:** Mandatory: 1 round. Optional: 1 more if first round materially under-delivered. Never more than 2 self-prompt rounds — beyond that, defer remaining items to Pass N+1.

### Hard stops (terminate immediately, do not loop)

- **Regression > 50 pts on any surface in Phase 6:** Investigate root cause before continuing. NOT a loop trigger.
- **AGENTS.md violation detected mid-flow:** Stop. Don't try to recover by loop; ask the user.
- **Manifest corruption detected by `validate_pass.sh`:** Stop. Run recovery per [TROUBLESHOOTING.md](references/methodology/TROUBLESHOOTING.md).
- **Cost cap exceeded (per `tools/cost-cap.sh`):** Stop. Don't spawn more subagents.

### Anti-pattern: time-based stops

Don't stop because "this is taking too long." Stop because the signal says converged. Loops that terminate on time-budget produce incomplete passes; loops that terminate on signal produce shippable passes.

If wall-time is a real concern, the right move is to drop to a lower-tier orchestration (Squad → Pair → Solo) and run a tighter scope, NOT to terminate the loop early.

---

## Audit Workspace Layout (the IO Contract)

The audit workspace is **inside the target repo** at `<target>/agent_ergonomics_audit/`. It's tracked in the same git history as the code, on the same branch (typically `main`). There is no sibling, no separate `git init`, no `/tmp/` location.

```
<target>/  (on the currently checked-out branch — typically main; NEVER a new branch)
├── (your applied code diffs — src/, cmd/, lib/ — one commit per recommendation)
├── tests/                                              ← golden tests added here too if project has tests/
├── agent_ergonomics_audit/                            ← THE WORKSPACE — INSIDE the target, committed to main
│   ├── audit/
│   │   ├── manifest.json                              ← entry point: tool, target_sha, pass, paths, target_branch
│   │   ├── phase0_scope_decision.md                   ← user's "must not touch" list (no branch field)
│   │   ├── phase0_skill_inventory.json                ← which helper skills are installed
│   │   ├── phase0_cli.json                            ← language, build system, binaries detected
│   │   ├── surface_inventory.jsonl                    ← Phase 1: every agent surface, with surface_id
│   │   ├── agent_surfaces.jsonl                       ← Phase 2: every surface scored on 11 dims
│   │   ├── intent_inference_corpus.jsonl              ← Phase 3: wrong invocations + outcomes
│   │   ├── recommendations.jsonl                      ← Phase 4: ranked recs with applied:bool
│   │   ├── playbook.md                                ← Phase 4: top-10 narrative
│   │   ├── applied_changes.jsonl                      ← Phase 5: before/after evidence per change
│   │   ├── ambition_bar_check.md                      ← Phase 10 gate: count + dimensions + deferrals
│   │   ├── scorecard.md                               ← Phase 2/6: human-readable scorecard
│   │   ├── scorecard_pass_<N>.md                      ← Phase 6: per-pass historical scorecards
│   │   ├── heatmap.svg                                ← Phase 2: surfaces × dimensions, hot=low
│   │   ├── uplift_diff.md                             ← Phase 6: pass-N vs pass-N-1 deltas
│   │   ├── regression_alerts.md                       ← Phase 6: surfaces that dropped
│   │   ├── regression_tests/                          ← Phase 5/8: golden/snapshot tests
│   │   ├── agent_simulations/
│   │   │   ├── pre_pass_<N>/                          ← Phase 3: baseline transcripts
│   │   │   └── post_pass_<N>/                         ← Phase 9: post-fix transcripts
│   │   └── HANDOFF.md                                 ← Phase 10: queued for next pass
│   └── tools/                                         ← per-workspace helper scripts (reusable across passes)
│       ├── rescore_surface.sh
│       ├── diff_scorecards.sh
│       ├── render_heatmap.sh
│       └── replay_simulation.sh
└── (no other side files; no V2 / _improved variants — see AGENTS.md)
```

> **Legacy variable name.** Many internal docs and subagent specs reference `<SIBLING>` as a path variable. Treat it as `<TARGET>/agent_ergonomics_audit/`. The semantics changed (the location is now in-tree, not a sibling); all the inner paths like `audit/manifest.json`, `audit/recommendations.jsonl`, `tools/rescore_surface.sh` resolve identically inside that folder, so subagent and script paths still work without rename. Renaming the variable everywhere is a future housekeeping task; for now, just remember: `<SIBLING>` = "the in-tree workspace folder."

Full per-artifact schema, including JSONL line shapes for `surface_inventory.jsonl`, `agent_surfaces.jsonl`, `recommendations.jsonl`, `applied_changes.jsonl`, and the manifest: **[references/methodology/IO-CONTRACTS.md](references/methodology/IO-CONTRACTS.md)**.

---

## Variant Prompts (the corpus of how to invoke this skill)

Different user intents map to different kickoff phrasings. Modeled on the `reality-check-for-project` skill's Variant A–H pattern, the corpus below is the canonical set this skill is calibrated for. Use the variant whose phrasing most closely matches the user's actual prompt — they're not interchangeable, the variants encode different scope-and-stop pairings.

### Variant A — Comprehensive first-time application (the most common)

```
First read ALL of the AGENTS.md file and README.md file super carefully and understand
ALL of both! Then use your code investigation agent mode to fully understand the code
and technical architecture and purpose of the project. Then apply
$agent-ergonomics-and-intuitiveness-maximization-for-cli-tools comprehensively to the
project. DO NOT CREATE A NEW BRANCH, DO ALL WORK ON main (any existing new branch
made for this must be folded into main). Be ambitious — I expect dramatic, measurable
improvements, not a polite scorecard.
```

This is the verbatim user prompt that drove the kernel design. It implies `full` mode + Solo/Pair/Squad tier auto-picked by surface count + Ambition Bar mandatory.

### Variant B — Audit-only (review, no changes)

```
Audit `<tool>` for agent ergonomics. Score every surface across the 11 dimensions, give
me the top-10 recommendations playbook, but DO NOT change any code. I want to read the
report before deciding whether to apply.
```

`audit-only` mode. Phase 5–9 forbidden. Workspace artifacts are still committed in-tree on the current branch (the report itself is the deliverable).

### Variant C — Targeted single-surface improvement

```
For `<tool>`, the agent always picks the wrong flag for `<subcommand>`. Just fix the
intent inference for that one surface. I don't want a full re-audit.
```

`single-surface-rescore` mode + Phase 4/5 narrowed to the one surface. Skip CASS deep mining + multi-model triangulation.

### Variant D — Re-score after changes ("did the previous pass work?")

```
I made some changes to `<tool>` since the last agent-ergonomics pass. Re-score the
modified surfaces and tell me what improved, what regressed, and whether the previous
recommendations still apply.
```

`re-score-only` mode. No new recommendations, no code changes. Read prior `audit/manifest.json` for `target_sha`, diff against current HEAD.

### Variant E — Robot-mode hardening (specific, common ask)

```
Add `--robot-*` mode, `capabilities --json`, and `robot-docs guide` to `<tool>`. Make
the canonical mega-command (`--robot-triage` shape) returning quick_ref +
recommendations + commands in one call. Pin schema with regression tests.
```

`full` mode + Phase 8 emphasized. The recommendation set is essentially pre-staged: Σ Mega-Command, 📜 Self-Describing, 📖 In-Tool-Docs operators dominate.

### Variant F — Mega-prompt (chain Phase 1 → Phase 5 in one shot, "just do it")

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

This is the speed variant — chains the entire flow with all three policy axioms (no branch, no sibling, ambition-bar-mandatory) baked in. Copy-paste ready. Use when the user has already understood the methodology and wants minimum back-and-forth.

### Variant G — Resumed pass (manifest exists)

```
Resume the agent-ergonomics audit on `<tool>`. There's a workspace at
`<tool>/agent_ergonomics_audit/` from a prior pass. <Tell me what changed since the
last pass | Apply more recommendations | Just re-score>.
```

The orchestrator reads `manifest.json`, picks the suggested mode (full / re-score-only / single-surface-rescore based on what's needed), and asks the user to confirm.

### Variant H — Multi-tool family (cargo + cargo-audit + cargo-deny family)

```
Audit and improve the agent ergonomics of the `<family>` tools as a SET — don't just
audit each binary independently. Apply cross-cut consistency dimensions:
flag-spelling parity across tools, exit-code-dictionary alignment, capabilities
schema versioning, output-envelope shape. The family-cross-cut-auditor and
parity-auditor subagents are designed for this.
```

`full` mode + Swarm tier + multi-tool extension per [MULTI-TOOL-FAMILY-AUDIT.md](references/methodology/MULTI-TOOL-FAMILY-AUDIT.md).

### Variant I — MCP server alongside CLI

```
The tool has both an MCP server and a CLI. Audit them as a paired system, not in
isolation — check MCP-CLI parity, ensure the MCP tool surface and the CLI subcommand
surface line up, and any divergence is intentional with documented rationale.
```

`full` mode + parity-auditor subagent + extension per [MCP-SERVER-AUDIT.md](references/methodology/MCP-SERVER-AUDIT.md).

### Variant J — Mine my CASS for which surfaces actually frustrated me

```
Mine my prior agent sessions for moments where `<tool>`'s ergonomics frustrated me or
my agents — wrong flag picked, error message that didn't teach, retry loop because of
ambiguous output. Prioritize fixing those specifically.
```

`full` mode + `CASS appetite=deep` + Phase 4 priority weighted by CASS frequency. Per [CASS-MINING-RECIPES-DEEP.md](references/methodology/CASS-MINING-RECIPES-DEEP.md).

### Variant K — Self-application (audit a Claude Code skill)

```
Apply $agent-ergonomics-and-intuitiveness-maximization-for-cli-tools to itself. Or to
$<some-other-skill>. The Polish Bar still applies — every script in scripts/ should
respond to --help, every subagent should have a clean Inputs section, the SKILL.md
should pass its own first-try-inevitability test.
```

Phase 11 (meta) + `subagents/skill-self-applier.md`. The skill audits a skill — Track A Level 6 self-application.

### Variant L — Plumbing-test validation (mini mode)

```
Run the agent-ergonomics audit on `<tool>` in `mini` mode just to verify the pipeline
works end-to-end on this repo. I'll commit to a longer pass after I see the scorecard.
```

`mini` mode (Phases 0, 1, 2 only). No Phase 3 / 4 / 5. Output is `surface_inventory.jsonl` + `agent_surfaces.jsonl` + `scorecard.md` + `heatmap.svg`. Use as a 5–15 minute dry-run validation before committing tokens to a full pass.

Full corpus (12 variants total + the failure-mode reactions you'd append to each): see [references/methodology/VARIANT-PROMPTS.md](references/methodology/VARIANT-PROMPTS.md). Pick the variant whose intent matches; do not blend them.

---

## Operator Rules (distilled from real applied passes)

These are the durable lessons from past application of this skill — captured because they were learned the hard way and forgetting them produces the same regressions repeatedly. Modeled on the `reality-check-for-project` operator-rules pattern.

**Rule 1: Branch policy is fixed; never auto-branch even when it "feels safer."**
- **When:** Any time you're about to run `git switch -c`, `git checkout -b`, `git worktree add`, or anything that creates a new branch as part of this skill.
- **Action:** Don't. Commit on the current branch (typically `main`) instead. If a swarm-mate already created an `agent-ergonomics-pass-N` branch, fold it back into `main` first.
- **Why:** The user explicitly detests auto-branching; multi-agent coordination uses Agent Mail file reservations + Beads, not branches; an extra branch fragments work and adds friction without any safety benefit.
- **Failure if skipped:** The user sees a new branch and reacts with "DO NOT CREATE A NEW BRANCH". Trust evaporates.

**Rule 2: Workspace is in-tree; the variable name `<SIBLING>` is legacy.**
- **When:** Phase 0 scaffolding, every subagent that resolves `<SIBLING>/audit/...`, every script that takes a workspace path.
- **Action:** Resolve `<SIBLING>` to `<TARGET>/agent_ergonomics_audit/`. Never create a directory at `<TARGET>__agent_ergonomics_audit/`. Never `git init` the workspace. The workspace is committed alongside code on the same branch.
- **Why:** Same single-record principle as Rule 1 — one git history, one `git log`, one place to look. Sibling repos fragment the trail.
- **Failure if skipped:** The user reacts with "this skill should NEVER be making whole new sibling directories like this!!!".

**Rule 3: Ambition Bar is the gate before declaring done; the self-prompt is mandatory and verbatim.**
- **When:** End of Phase 5, before Phase 10.
- **Action:** Self-evaluate against the soft target (≥ 10 substantive commits for non-trivial / ≥ 5 for tiny; ≥ 3 dimensions touched; at least one each of mega-command / capabilities / `--json` / error rewrite / intent-inference handler when missing). If short, run the verbatim "That's it??" prompt on yourself and re-enter Phase 4/5 once more.
- **Why:** Without this gate, the agent's natural attractor is "polite scorecard, stop". The user has prodded with "that's it??" enough times to make this a regression theme.
- **Failure if skipped:** The user has to say "I was hoping you would get a lot more practical value out of this skill". Trust evaporates.

**Rule 4: Intent wins over state when picking mode; default `full` is the strong default.**
- **When:** Mode selection at intake.
- **Action:** Classify the user's prompt for "apply / improve / harden / make agent-friendly" intent first. Only fall to `audit-only` when the user explicitly asked for "review / audit / score / report". Tool size never downgrades `full` to `audit-only` — that's a Phase 4 prioritization issue, not a mode issue.
- **Why:** Audit-only is a real mode for explicit audit requests, but it's also an attractor for "this is too much work, let me deliver a report instead". Defaulting to `full` defeats the attractor.
- **Failure if skipped:** Large CLI → reflexively pick `audit-only` → ship a 47-page playbook with zero applied changes.

**Rule 5: Score with evidence or don't score; > 700 needs file:line or invocation transcript.**
- **When:** Any Phase 2 scorer or re-scorer assigning a number.
- **Action:** For dim ≤ 700, evidence is recommended. For dim > 700, evidence is mandatory. For n/a dims, write a one-line rationale (e.g. `n/a — read-only verb`).
- **Why:** Vibe-anchored high scores produce false-confidence playbooks that miss real issues. The scorecard is meant to be regression-graded, which means scores must be reproducible.
- **Failure if skipped:** Phase 6 uplift comparisons become noise; tiebreakers explode; the methodology drifts.

**Rule 6: Regression test ≡ applied recommendation; one without the other is a half-applied rec.**
- **When:** Phase 5, every applied recommendation.
- **Action:** Land `audit/regression_tests/R-NNN__<short>.test.{sh,rs,py,ts}` in the same pass. Test must pass post-apply AND fail pre-apply.
- **Why:** Without the test, the next pass can't tell "this surface was fixed and stayed fixed" from "the score happened to be high this run". Drift is invisible.
- **Failure if skipped:** Pass 3 finds the same recommendation as Pass 1, with no way to know whether Pass 2's apply actually worked.

**Rule 7: "AGENTS.md says no" outranks every other axiom.**
- **When:** Tempted to bypass a hook (`--no-verify`), delete a file, run `git reset --hard`, run a script-based codemod, create a `_v2` file, etc.
- **Action:** Don't. Re-read the relevant AGENTS.md section. Find the AGENTS.md-compliant alternative.
- **Why:** AGENTS.md rules were learned from the user losing work. They're not negotiable.
- **Failure if skipped:** Catastrophic data loss. Trust evaporates permanently.

These rules are baked into the kernel axioms, the anti-patterns table, and the subagents' Discipline sections — but having them as a single distilled list helps an agent re-anchor mid-flight when it's about to drift.

---

## Mega-Prompt — chain everything in one shot

For experienced users who want minimum back-and-forth, this prompt encodes Variants A + F + the three policy axioms + the Ambition Bar self-prompt in a single message. Verbatim copy-paste:

```
Reread AGENTS.md so it's still fresh in your mind. First read ALL of the AGENTS.md
file and README.md file super carefully and understand ALL of both! Then use your
code investigation agent mode to fully understand the code and technical architecture
and purpose of the project. Then apply
$agent-ergonomics-and-intuitiveness-maximization-for-cli-tools comprehensively to
the project.

THREE NON-NEGOTIABLE POLICIES:

1. DO NOT CREATE A NEW BRANCH. Commit directly to the current branch (typically
   main). Any existing `agent-ergonomics-pass-N` branch from a prior version of this
   skill must be folded into main FIRST.

2. DO NOT CREATE A SIBLING DIRECTORY. The audit workspace lives at
   `<TARGET>/agent_ergonomics_audit/` (in-tree, committed alongside code on the same
   branch). Never `git init` a separate workspace. If a legacy sibling exists from a
   prior run, migrate its contents into the in-tree folder.

3. BE AMBITIOUS. A polite scorecard is a failure. Target ≥ 10 substantive landed
   changes for a non-trivial CLI (≥ 5 for tiny), covering ≥ 3 of the 11 dimensions,
   with at least one each of: mega-command (`--robot-triage`-style), capabilities or
   robot-docs surface, `--json` output on a read-side command, error-message rewrite
   that names the exact corrected command, intent-inference handler for the most
   common wrong invocation. After Phase 5, run the verbatim "That's it??"
   self-prompt and re-enter Phase 4/5 once more if the bar is unmet.

Phases run: 0 (input + bootstrap) → 1 (surface inventory) → 2 (rubric scoring) →
3 (intent-inference stress) → 4 (recommendation synthesis + triangulation) →
5 (apply changes — current branch, NO new branch) → 6 (re-score + uplift) →
7 (fresh-eyes review until clean twice) → 8 (self-doc hardening) →
9 (agent-in-the-loop simulation) → 10 (handoff + push current branch).

Constraints I'll respect: AGENTS.md (no file deletion, no destructive git, no _v2
files, no script-driven code transforms), my scope guardrails (`<SCOPE_GUARDRAILS>`),
and the kernel's 19 axioms.

Proceed. I'll check in only at end of Phase 6 (with uplift evidence) and end of
Phase 9 (with simulation outcomes). Do NOT pause for confirmation between phases
unless an axiom is in conflict.
```

This prompt is calibrated to the kernel's 19 axioms; modifying it (especially weakening any of the three "non-negotiable policies") regresses to the failure modes those axioms were designed to defeat. If a future model wants to "improve" this prompt, the canonical version is in [VARIANT-PROMPTS.md § Mega-Prompt](references/methodology/VARIANT-PROMPTS.md) — make changes there with rationale, don't silently rephrase here.

---

## Sibling Skills Map (composition graph)

This skill rarely runs alone. Common compositions:

| Want to … | Use | Relationship |
|-----------|-----|--------------|
| Mine prior agent sessions for places this CLI's ergonomics failed | [`/cass`](../cass/SKILL.md) + this skill (`CASS appetite = deep`) | Phase 4 priority is weighted by CASS frequency |
| Run a bug-hunt before/after the ergonomics pass | [`/multi-pass-bug-hunting`](../multi-pass-bug-hunting/SKILL.md) | Phase 7 fresh-eyes already does a slim version of this; the full skill goes deeper |
| Static-analyze every applied change | [`/ubs`](../ubs/SKILL.md) | Phase 5 + Phase 7 invoke `ubs` if available; falls back gracefully if not |
| Block destructive commands during the pass | [`/dcg`](../dcg/SKILL.md) | Phase 0 verifies dcg is hooked; the kernel's Axioms 1, 2, 11 align with dcg's rule set |
| Coordinate parallel appliers in Phase 5 | [`/agent-mail`](../agent-mail/SKILL.md) | File reservations are the **only** coordination mechanism for parallel writes |
| Track per-recommendation work as issues | [`/beads-br`](../beads-br/SKILL.md) + [`/beads-bv`](../beads-bv/SKILL.md) | One bead per Phase 5 rec; bv-triage helps order them |
| Spawn a Squad/Swarm tier audit | [`/ntm`](../ntm/SKILL.md) + [`/vibing-with-ntm`](../vibing-with-ntm/SKILL.md) | NTM panes for ≥ 4 workers; vibing-with-ntm tends them |
| Get a second opinion on Phase 4 recs | [`/multi-model-triangulation`](../multi-model-triangulation/SKILL.md) | Use for top-10 recs + Phase 7 fresh-eyes when stakes are high |
| Build initial canonical exemplars from sessions | [`/operationalizing-expertise`](../operationalizing-expertise/SKILL.md) | This skill IS a Track A artifact; track-A-discipline.md catalogs how |
| Surface second-order improvements after Phase 10 | [`/idea-wizard`](../idea-wizard/SKILL.md) | The handoff uses idea-wizard to seed Pass N+1 |
| Audit a Claude Code skill (self-application) | [`/sw`](../sw/SKILL.md) + Phase 11 of this skill | `sw` validates the skill; this skill scores it agent-ergonomic dimensions |
| Validate a CLI's regression-test surface before publishing | [`/testing-golden-artifacts`](../testing-golden-artifacts/SKILL.md) | Phase 5/8 regression tests are golden-style |
| Fix the underlying CLI's hot-path performance | [`/extreme-software-optimization`](../extreme-software-optimization/SKILL.md) | Out-of-scope here; file as bead for follow-up |
| Audit closed beads to verify they were really completed | [`/beads-compliance-and-completion-verification`](../beads-compliance-and-completion-verification/SKILL.md) | Useful between passes if any rec was closed without an audit-trail |

Anti-composition (these don't compose well):

| Don't combine | Reason |
|---------------|--------|
| This skill + `/simplify-and-refactor-code-isomorphically` in one pass | Two LOC-affecting passes at once muddies the diff. Run sequentially with separate commits. |
| This skill + a feature-development task | Feature work belongs in beads, not bundled into an ergonomics pass. Land features first OR queue them after. |
| This skill + a CI/release pass on the same branch | Phase 5 + a release commit on `main` → unclear which commit set is "the release." Run release-preparations skill before or after the pass, not concurrently. |

Full cross-skill matrix with invocation order: see [SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md) for fallback playbooks when a sibling skill isn't installed.

---

## Lessons From Real Sessions (what we learned the hard way)

This section captures durable failures-and-fixes from actual applied passes. Each entry pairs a symptom (what the user observed) with the kernel axiom that prevents it. Modeled on `reality-check-for-project`'s `LESSONS-FROM-SESSIONS.md` pattern — except inline here for visibility.

### Session: bv dogfood (2026-05-07)

**Surfaces:** `bv` v0.16.0, three flagship verbs (`--robot-triage`, `--robot-next`, `--robot-plan`).

**Pattern that emerged.** The first dogfood exposed the now-canonical mega-command shape (`bv --robot-triage` returning `quick_ref + recommendations + commands + project_health` in one call). Σ Mega-Command operator codified from this run.

**Real bugs found by real scoring (not LLM-only):**
- Bare `bv` in non-TTY emits "could not open a new TTY" with no fallback hint → Polish Bar fail (TUI-on-bare-invocation, Axiom 15 violation).
- No Levenshtein-1 typo correction on any flag → a single typo wedges the agent (Axiom 7 violation).
- Sibling flags use inconsistent units (int 0-100 vs float 0.0-1.0) → schema fragility.
- `regression_resistance` scored 0 across all 3 surfaces → no ergonomic test suite (Axiom 17 violation).

**Calibration data persisted at:** `references/calibration-fixtures/bv-dogfood-2026-05-07.jsonl`. Used as a re-scoring sanity check for Phase 2 changes to the rubric.

### Session: bv apply (2026-05-08, Codex)

**User prompt:** "First read ALL of AGENTS.md and README.md... apply $agent-ergonomics-and-intuitiveness-maximization-for-cli-tools comprehensively to the project. **DO NOT CREATE A NEW BRANCH**, do all work on `main` (any existing new branch made for this must be folded into main)."

**What went wrong on Pass 1.** The skill (legacy version) created `agent-ergonomics-pass-1` and tried to land changes there. The user reacted strongly: "DO NOT CREATE A NEW BRANCH." Required folding the work back into `main`.

**Permanent fix:** Axiom 1 + Anti-Pattern row. The skill never creates a branch.

**Second failure on Pass 2.** The skill produced a comprehensive scorecard + playbook + recommendations, then stopped. User reacted: "that's it?? I was hoping you would get a lot more practical value out of this skill. Where are the dramatic improvements???". Required prodding for a second apply round.

**Permanent fix:** Axiom 3 + the Ambition Bar self-prompt baked into Phase 10 gate.

**What worked after Pass 2 (durable wins):**
- Intent-corpus generated 272 reasonable-but-wrong invocations.
- Pre-Pass 2: 271 useful_hint + 1 useless_error. Post-Pass 2: 272 useful_hint + 0 useless_error.
- Triage robot JSON deterministic under `SOURCE_DATE_EPOCH`.
- `verify-stdout-stderr-split.sh` and `verify-determinism.sh` both green.
- 14+ commits accepting agent intent aliases (`bv triage --json`, `bv plan --json`, etc.) normalize to the correct `--robot-*` form.

### Session: agent-ergonomics revision (2026-05-09, the meta-pass)

**User prompt:** "this skill should NEVER be making whole new sibling directories like this!!! it should do all this stuff INSIDE THE REPO PROPER!!!".

**What went wrong.** The skill's legacy design used `<target>__agent_ergonomics_audit/` as a sibling directory, `git init`-ed separately. Created two parallel git histories (target + workspace) where the user wanted one.

**Permanent fix:** Axiom 2 + Workspace Policy callout + the in-tree layout. The scaffold script no longer runs `git init`; it warns if `<sibling>` is outside the target.

### Pattern: "polite scorecard, stop"

Across at least three independent applications, the agent's natural attractor is to deliver a thorough scorecard and recommendations, then declare done. The user wants action, not analysis. The Ambition Bar gate exists specifically to defeat this attractor — without an explicit verbatim self-prompt, the agent reverts to "polite scorecard" within a few re-runs.

**Prevention:** Axiom 3 + the verbatim "That's it??" self-prompt is the ONLY mechanism that has reliably broken this pattern across re-runs.

### Pattern: "branch creation feels safer"

Agents trained on standard git workflows reflexively want to branch before risky changes. For *this* skill specifically, branching is the wrong move — the user has explicitly stated this preference enough times that it's a kernel axiom. Cross-skill bleed (an agent that ran `simplify-and-refactor-code-isomorphically` an hour ago might think "create a refactor branch") is the most common cause.

**Prevention:** Axiom 1 + Branch Policy callout + Anti-Pattern row + the kickoff prompt explicitly bans it. Three redundant guards because cross-skill bleed is sneaky.

### Pattern: "size-driven downshift"

When the surface count is large (gh, docker, kubectl), the agent has a strong attractor toward `audit-only` — "this is too much to fix in one pass, let me deliver a scorecard". Per Rule 4, this is the wrong reflex. The right move is to tighten Phase 4 prioritization to the top-N highest-leverage surfaces and run `full` on those.

**Prevention:** Axiom 3 + Mode-default heuristic explicitly calls this out + the auto-detect heuristic table now defaults `full` for ambiguous-intent prompts regardless of size.

Full session corpus + per-pattern reproduction recipes: see [LESSONS-FROM-SESSIONS.md](references/methodology/LESSONS-FROM-SESSIONS.md) (companion file).

---

## Hand-off Template (when the pass completes)

When Phase 10 completes successfully, emit this short summary to the user. Modeled on `simplify-and-refactor-code-isomorphically`'s hand-off pattern. The full HANDOFF.md is the deeper artifact; this is the one-screen "did the pass succeed?" digest.

```markdown
## agent-ergonomics pass <N> complete (<MODE>)

**Target.** `<TOOL>` at `<TARGET_SHA_AT_END>` on branch `<TARGET_BRANCH>` (no new branch created).
**Workspace.** `<TARGET>/agent_ergonomics_audit/` (in-tree).

### Scorecard
| Pass | Median dim score | Surfaces ≥ 700 | Surfaces < 500 |
|------|------------------|---------------|---------------|
| Pre   | <X>              | <N>           | <N>           |
| Post  | <Y>              | <N>           | <N>           |
| Δ     | **+<Z>** ↑       | +<N>          | -<N>          |

### Ambition Bar
- Substantive commits: **<N>** (target: ≥ 10 / ≥ 5 for tiny)
- Dimensions touched: **<N>** (target: ≥ 3)
- Required surface types added (when missing):
  - Mega-command: ✓ / ✗ / pre-existing
  - Capabilities or robot-docs: ✓ / ✗ / pre-existing
  - --json or --robot-* on read-side: ✓ / ✗ / pre-existing
  - Error rewrite: ✓ / ✗ / pre-existing
  - Intent-inference handler: ✓ / ✗ / pre-existing
- Self-prompt round run: yes / no
- **Bar met:** yes / no (if no, deferred items listed in HANDOFF.md)

### Verification
- [ ] `cargo test` / `go test` / `pytest` / `vitest`: green
- [ ] `tsc --noEmit` / `cargo clippy` / linters: green
- [ ] `audit/regression_tests/*`: <N> tests, all green
- [ ] `verify-stdout-stderr-split.sh`: pass
- [ ] `verify-determinism.sh`: pass
- [ ] `verify-non-tty-discipline.sh`: pass

### What's queued for Pass <N+1>
- <Bead-id>: <short title>
- <Bead-id>: <short title>

### Next reviewer can re-open the loop by:
1. Reading `<TARGET>/agent_ergonomics_audit/audit/HANDOFF.md` for full detail.
2. Running `re-score-only` on the post-pass binary to confirm scores held.
3. Picking up beads in `br ready` priority order.
```

If the bar is unmet AND the self-prompt was run AND the second apply round didn't close the gap, that's a signal to STOP — diminishing returns. File the residual as Pass-N+1 beads and hand off honestly.

---

## Failure Modes (and Recovery)

| Symptom | Root cause | Recovery |
|---------|------------|----------|
| Phase 1 inventory has < 5 surfaces for a non-trivial CLI | `--help` not invoked recursively; subcommand walk shallow | Re-run with `scripts/inventory_surfaces.sh <tool-binary> --depth=999`; verify against `cargo run -- --help` etc. |
| Phase 2 reconciliation reports many tiebreakers or any escalations | Scorers using different rubric versions or rubric anchors are too loose | Pin `rubric_version` in `manifest.json`; re-score; handle tiebreaker/escalation rows per `references/methodology/RECONCILIATION-POLICY.md` |
| Phase 3 corpus has only "obvious" typos | Naive-agent prompt too constrained | Re-run with full `references/methodology/INTENT-CORPUS-GENERATION.md` prompt; add "savvy" agent pass |
| Phase 4 recommendations contradict each other | No synthesis pass | Run `subagents/synthesizer.md` to merge; resolve contradictions in `playbook.md` |
| Phase 5 applied change broke an existing user workflow | Missing deprecation path | Revert change; file as recommendation requiring `--legacy-<name>` flag with deprecation warning |
| Phase 6 shows a regression > 50 pts | Side-effect of unrelated change | **Hard stop**. Diagnose root cause before continuing. Investigate at `audit/regression_alerts.md`'s cited file:line. |
| Phase 7 fresh-eyes never goes quiet | Loop is touching cosmetic surfaces | Tighten "trivial change" definition: only typo/whitespace counts as trivial; rephrasing IS a change |
| Phase 9 simulation agent gets stuck on canonical task | Real intent-inference gap, not a Phase 3 oversight | File as P0 bead for next pass; **do not** mark Phase 9 complete |
| `--help` walk crashes the binary | Tool segfaults or panics on `--help` after some subcommand | This IS a finding (intuitiveness=0); record as critical; file in beads |
| Tool requires network for `--help` | Bad design (non-deterministic; agents may have no net) | Score 0 on determinism + composability; file as P0 |
| Tool prints to stdout *and* stderr for the same data | Stdout/stderr split violation | Score 0 on output_parseability; flag as Polish Bar fail |

Full failure-mode catalog with recovery scripts: **[references/methodology/TROUBLESHOOTING.md](references/methodology/TROUBLESHOOTING.md)**.

---

## Anti-Patterns (Never Do)

| ✗ | Why | Fix |
|---|-----|-----|
| Score a surface > 700 without evidence | Rubric is meaningless if anchored to vibes | `tools/validate_scorecard.sh` rejects unsourced high scores |
| Apply a change that breaks an existing working surface "to improve ergonomics" | Regression > 50 pts is the single hard-stop trigger | Add a deprecation path: keep old flag, emit warning, ship new flag |
| Write a recommendation without a minimal diff sketch | Phase 5 implementer can't tell intent from a vague "improve error message" | Recommendation block requires diff sketch + expected per-dim uplift + risk + test |
| Pass-1 audit overrides AGENTS.md ("just rm -rf the cache to start clean") | Per AGENTS.md, no destructive ops | Use the repo-approved safe path: inspect, back up, or ask; never stash/revert/delete peer work unless the local AGENTS.md and user explicitly allow it |
| Bundle feature work into an ergonomics pass | Conflates uplift measurement with feature scope | Feature work goes to beads for follow-up; never lands in pass-N |
| Score the same surface twice with different `surface_id` | Cumulative scoring across passes breaks | `surface_id` is content-derived (subcommand + flag + arg-name); use `tools/compute_surface_id.sh` |
| Generate the heatmap before scoring is done | Heatmap colors mislead recommendations | Make heatmap a Phase 2-end artifact, never mid-Phase-2 |
| Land Phase 5 changes without a regression test | The next pass can't tell "fixed" from "regressed-back" | `regression_tests/` is mandatory; `scripts/validate_pass.sh` checks this |
| Run Phase 9 against a simulator agent that has the audit's context | Defeats the purpose of "fresh eyes" | Spawn a fresh subagent (Agent tool, no prior context); record context-isolation in transcript |
| **Create a new branch (e.g. `agent-ergonomics-pass-N`) for the apply phase** | The user explicitly detests this; multi-agent swarms coordinate via Agent Mail + Beads, not branches | **Always commit directly to the current branch (typically `main`)**. If you arrive on a stale auto-created branch, fold it back into `main` first. See [Branch Policy](#branch-policy-not-a-question--fixed). |
| Stop after Phase 4 (recommendations only) when the user asked for `full` | Recommendations without applied commits are the slop pattern this skill exists to defeat | Phase 5 is mandatory in `full`. If recommendations look insufficient, that's a Phase 4 prioritization problem, not a stop condition. |
| Declare a `full` pass complete after 1–3 trivial commits | The Ambition Bar exists for this exact failure | Run the [Ambition Bar self-prompt](#ambition-bar-the-thats-it-gate) verbatim; re-enter Phase 4/5 for one more round before Phase 10 |
| Auto-downgrade `full` → `audit-only` because "the surface count is large" | This is the "polite scorecard" failure mode | Tighten Phase 4 prioritization to a focused top-N; keep mode = `full`; ship the top-N |
| Bundle `audit/` workspace updates into the same commit as a Phase 5 source change | Mixing measurement updates and code edits muddles `git log`/`git blame` for the source diff | Source-change commits touch only the implementation files; workspace updates (`applied_changes.jsonl` append, `recommendations.jsonl` flip, regression test) go in a follow-up commit. Both land on the same branch — that's fine. |
| Treat "no `--robot-*` mode" as a feature gap rather than a finding | The methodology IS to find these gaps | If `--robot-*` is missing, that's a P0 finding scored under self_documentation + output_parseability |

Full anti-pattern catalog: **[references/methodology/ANTI-PATTERNS.md](references/methodology/ANTI-PATTERNS.md)**.

---

## Pre-Flight & End Checklist

- [ ] Target CLI path confirmed; in-tree audit workspace `<target>/agent_ergonomics_audit/` scaffolded (NOT a sibling, NOT a separate git repo)
- [ ] Mode confirmed (`audit-only` | `full` | `re-score-only` | `simulate-only` | `single-surface-rescore`)
- [ ] Pass number determined (auto-incremented from manifest if resuming)
- [ ] Helper skills inventoried; missing ones offered via `jsm install` (non-blocking)
- [ ] CLI language + binaries discovered and recorded in `phase0_cli.json`
- [ ] Phase 1 produced `surface_inventory.jsonl` with ≥1 record per `--help` line; spot-check against runtime `--help` output
- [ ] Phase 2 produced `agent_surfaces.jsonl` with median scores + spreads; outliers tiebroken; rubric_version pinned
- [ ] Phase 3 produced `intent_inference_corpus.jsonl` with naive + savvy entries; per-entry outcome classified (silent-fail / useless-error / useful-hint / inferred-and-acted / skipped)
- [ ] Phase 4 produced `recommendations.jsonl` ranked by priority + `playbook.md` for top-10; multi-model triangulation if available
- [ ] Phase 5 (full mode) — applied commits are on the **current branch** of the target repo (typically `main`); NO new branch was created for this skill; one commit per applied recommendation; reservations via Agent Mail; `applied_changes.jsonl` populated; regression tests added per recommendation
- [ ] Phase 6 — `scorecard_pass_<N+1>.md` shows median uplift ≥ 25 pts AND no surface regressed > 50 pts
- [ ] Phase 7 fresh-eyes ran ≥ 2 times clean; `ubs` clean (if available); typecheck/lint/tests green; `audit/regression_tests/*.test.sh` green
- [ ] Phase 8 — `<tool> capabilities --json`, `<tool> robot-docs guide`, `<tool> --robot-*` for read-side commands all exist (or beads filed for missing ones)
- [ ] Phase 9 — `agent_simulations/post_pass_<N>/` populated with fresh-agent transcripts; per-task pass/fail/round-trip counts recorded
- [ ] **Ambition Bar self-check** — full-mode pass shipped ≥ 5 substantive landed changes (≥ 10 for non-trivial CLIs), touching ≥ 3 dimensions, with at least one each of: mega-command, capabilities/robot-docs, --json/--robot-*, error rewrite, intent-inference handler — OR the verbatim "That's it??" self-prompt was run and one more apply round was attempted before Phase 10. The HANDOFF.md must explicitly list any deferred items.
- [ ] Phase 10 — `HANDOFF.md` written; beads filed for queued work; target's current branch (typically `main`) is pushed (the workspace lives inside the target, so a single push covers code + audit artifacts)
- [ ] `audit/manifest.json` updated with new `pass`, `target_sha`, summary stats, artifact list

---

## Reference Index

### Core methodology
| Need | File |
|------|------|
| Mode definitions + exit criteria | [methodology/OPERATING-MODES.md](references/methodology/OPERATING-MODES.md) |
| Per-phase playbook with exit criteria | [methodology/PHASES.md](references/methodology/PHASES.md) |
| Exact prompts for each parallel subagent | [methodology/AGENT-PROMPTS.md](references/methodology/AGENT-PROMPTS.md) |
| Per-mode kickoff prompts (verbatim) | [methodology/KICKOFF-PROMPTS.md](references/methodology/KICKOFF-PROMPTS.md) |
| Calibrated user prompt variants by intent and mode | [methodology/VARIANT-PROMPTS.md](references/methodology/VARIANT-PROMPTS.md) |
| Real-session lessons and durable failure patterns | [methodology/LESSONS-FROM-SESSIONS.md](references/methodology/LESSONS-FROM-SESSIONS.md) |
| One-page agent quick reference | [QUICKREF.md](references/QUICKREF.md) |
| Concrete ambition patterns for shipping 10+ substantive changes | [methodology/AMBITION-PLAYBOOK.md](references/methodology/AMBITION-PLAYBOOK.md) |
| **33 cognitive operators** (composition cheat-sheet by failing dim) | [methodology/OPERATORS.md](references/methodology/OPERATORS.md) |
| Polish Bar verification queries | [methodology/POLISH-BAR.md](references/methodology/POLISH-BAR.md) |
| Multi-agent orchestration tiers | [methodology/ORCHESTRATION.md](references/methodology/ORCHESTRATION.md) |
| Inline fallbacks for missing skills | [methodology/SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md) |
| Multi-model triangulation harness | [methodology/TRIANGULATION.md](references/methodology/TRIANGULATION.md) |
| IO contracts for every JSONL artifact | [methodology/IO-CONTRACTS.md](references/methodology/IO-CONTRACTS.md) |
| Intent-inference corpus generation prompts | [methodology/INTENT-CORPUS-GENERATION.md](references/methodology/INTENT-CORPUS-GENERATION.md) |
| Anti-pattern catalog | [methodology/ANTI-PATTERNS.md](references/methodology/ANTI-PATTERNS.md) |
| Failure-mode + recovery catalog | [methodology/TROUBLESHOOTING.md](references/methodology/TROUBLESHOOTING.md) |
| Real-audit checklist for applied, evidence-backed passes | [REAL-AUDIT-CHECKLIST.md](references/REAL-AUDIT-CHECKLIST.md) |
| Recommendation pattern library | [REC-PATTERNS.md](references/REC-PATTERNS.md) |
| LLM dry-run harness guide | [methodology/DRYRUN-LLM.md](references/methodology/DRYRUN-LLM.md) |
| Pipeline recovery playbook | [methodology/PIPELINE-RECOVERY.md](references/methodology/PIPELINE-RECOVERY.md) |

### Implementation cookbooks (the agent-ergonomic uplift content)
| Need | File |
|------|------|
| **Per-language framework recipes** (Rust+clap, Go+cobra, Python+click/typer/argparse, TypeScript+commander/yargs/oclif, Bash, Ruby+thor) — concrete code for adding `--json`/`--robot-*`/`capabilities`/`robot-docs`/typo-correction to every framework | [methodology/LANGUAGE-RECIPES.md](references/methodology/LANGUAGE-RECIPES.md) |
| **Mega-command design library** (TRIAGE / DIAGNOSE / PLAN / CAPABILITIES shapes + JSON schemas + decision tree + per-language scaffolding) | [methodology/MEGA-COMMAND-DESIGN.md](references/methodology/MEGA-COMMAND-DESIGN.md) |
| **Error-message rewriting cookbook** (17 before/after translations: typo, missing arg, destructive op, network failure, lock conflict, etc.) | [methodology/ERROR-REWRITING-COOKBOOK.md](references/methodology/ERROR-REWRITING-COOKBOOK.md) |
| **JSON schema patterns** (universal envelope, meta field, capabilities schema, NDJSON, pagination, schema-pin tests) | [methodology/JSON-SCHEMA-PATTERNS.md](references/methodology/JSON-SCHEMA-PATTERNS.md) |
| **Observability + telemetry surfaces** (log levels, progress bars, NO_COLOR/CI/non-TTY, telemetry opt-out, trace files, crash dumps) | [methodology/OBSERVABILITY-AND-TELEMETRY-SURFACES.md](references/methodology/OBSERVABILITY-AND-TELEMETRY-SURFACES.md) |

### Specialty audits + advanced playbooks
| Need | File |
|------|------|
| **CLI archetype defaults** (15 archetypes: search tool, package manager, build tool, test runner, SCM, daemon, scaffolder, hook tool, issue tracker, etc. — per-archetype dimension weights, mega-command shape, anti-patterns) | [methodology/CLI-ARCHETYPES.md](references/methodology/CLI-ARCHETYPES.md) |
| **MCP server audit extension** (auditing MCP tools, resources, prompts; MCP-CLI parity checks; MCP-specific recommendations) | [methodology/MCP-SERVER-AUDIT.md](references/methodology/MCP-SERVER-AUDIT.md) |
| **Multi-tool family audit** (cargo + cargo-audit + cargo-deny family; cross-cut consistency; family-level recommendations) | [methodology/MULTI-TOOL-FAMILY-AUDIT.md](references/methodology/MULTI-TOOL-FAMILY-AUDIT.md) |
| **Deprecation patterns** (6 patterns for safe breaking changes: rename flag, rename verb, change exit code, change schema, change default, remove feature; staged rollout) | [methodology/DEPRECATION-PATTERNS.md](references/methodology/DEPRECATION-PATTERNS.md) |
| **Schema evolution** (versioning capabilities + tool contracts; contract_version semantics; migration tools; old-version client support) | [methodology/SCHEMA-EVOLUTION.md](references/methodology/SCHEMA-EVOLUTION.md) |

### Continuous improvement + drift guards
| Need | File |
|------|------|
| **Pre-commit drift guards** (cc-hooks / pre-commit / husky / lefthook recipes for capabilities-pin, --help footer, mutating-verb gates, stdout/stderr split) | [methodology/HOOKS-INTEGRATION.md](references/methodology/HOOKS-INTEGRATION.md) |
| **CI integration recipes** (GitHub Actions, GitLab CI workflows for regression_tests + scheduled re-audits; PR-time annotations) | [methodology/CI-INTEGRATION.md](references/methodology/CI-INTEGRATION.md) |
| **Continuous improvement playbook** (PR-time → weekly → monthly → quarterly → annual cadence; metrics timeseries; sunset criteria) | [methodology/CONTINUOUS-IMPROVEMENT.md](references/methodology/CONTINUOUS-IMPROVEMENT.md) |
| **Deep CASS mining recipes** (38+ targeted queries by failure class; per-archetype probe templates; frequency signal extraction) | [methodology/CASS-MINING-RECIPES-DEEP.md](references/methodology/CASS-MINING-RECIPES-DEEP.md) |

### Track A discipline + meta (operationalizing-expertise patterns)
| Need | File |
|------|------|
| **Track A artifact mapping** (this skill IS a Track A artifact: corpus + quote bank + triangulated kernel + operator library + validators; how to extend each) | [methodology/OPERATIONALIZING-EXPERTISE-TRACK-A.md](references/methodology/OPERATIONALIZING-EXPERTISE-TRACK-A.md) |
| **Agent API design first principles** (cognitive load, working memory, retry semantics, no-telepathy, least-surprise-on-failure, graceful degradation, deterministic-by-default, machine-first) | [methodology/AGENT-API-DESIGN-PRINCIPLES.md](references/methodology/AGENT-API-DESIGN-PRINCIPLES.md) |
| **Verification-first discipline** (don't claim a behavior without verifying; per-claim verification protocol; verification log; cross-pass freshness) | [methodology/VERIFICATION-FIRST.md](references/methodology/VERIFICATION-FIRST.md) |
| **Self-application meta-doc** (applying this skill to itself; applying to any Claude Code skill; Track A Level 6) | [methodology/SELF-APPLICATION.md](references/methodology/SELF-APPLICATION.md) |
| **Multi-pass bug-hunting for ergonomics** (audit-fix-rescan cycle applied to ergonomics; the three calibrated prompts; diminishing-returns curve) | [methodology/MULTI-PASS-BUG-HUNTING-FOR-ERGONOMICS.md](references/methodology/MULTI-PASS-BUG-HUNTING-FOR-ERGONOMICS.md) |
| **Worked operator compositions** (6 worked examples: applying 5+ operators to one surface as a single composed recommendation) | [methodology/WORKED-OPERATOR-COMPOSITIONS.md](references/methodology/WORKED-OPERATOR-COMPOSITIONS.md) |
| **Decision trees** (19 decision trees for "what next?" at common audit decision points: mode, tier, archetype, triangulation, defer/apply, operators, termination, verification, family, MCP, deprecation, Phase 9, cheat sheet, NTM, beads, HARD STOP, handoff) | [methodology/DECISION-TREES.md](references/methodology/DECISION-TREES.md) |
| **Failure mode catalog** (8 themes × ~30 failure modes: methodology drift, workflow drift, verification gap, apply failure, subagent confusion, cross-pass coherence, external skill drift, AGENTS.md violations) | [methodology/FAILURE-MODE-CATALOG.md](references/methodology/FAILURE-MODE-CATALOG.md) |
| **Polish Bar deep verification** (per-row jq + bash queries, weighted criticality, when bar can be relaxed) | [methodology/POLISH-BAR-DEEP.md](references/methodology/POLISH-BAR-DEEP.md) |
| **Beads workflow integration** (bead-per-rec, dependency staging, bv triage, mail thread alignment, br sync discipline, deferred work tracking) | [methodology/BEADS-WORKFLOW.md](references/methodology/BEADS-WORKFLOW.md) |
| **NTM + Agent Mail integration** (Squad/Swarm orchestration; spawning audit swarms; reservations; convergence detection; tending the swarm) | [methodology/NTM-AND-AGENT-MAIL-INTEGRATION.md](references/methodology/NTM-AND-AGENT-MAIL-INTEGRATION.md) |
| **Metrics + time series** (per-pass JSONL; cross-pass medians; per-dim trends; sparklines; archetype baselines; dashboard) | [methodology/METRICS-AND-TIMESERIES.md](references/methodology/METRICS-AND-TIMESERIES.md) |
| **TUI-mode audit extension** (gating bare invocation; charmbracelet/ratatui/frankentui patterns; TUI-CLI hybrid architectures) | [methodology/TUI-MODE-AUDIT.md](references/methodology/TUI-MODE-AUDIT.md) |
| **DSL-and-SDK audit** (auditing tools with embedded DSL like jq filters / kubectl JSONPath; auditing library/SDK surfaces; CLI-DSL-SDK alignment) | [methodology/DSL-AND-SDK-AUDIT.md](references/methodology/DSL-AND-SDK-AUDIT.md) |

### Agent profiles + advanced surface types
| Need | File |
|------|------|
| **Agent profiles** (Claude Code, Codex CLI, Gemini, smaller models, IDE-integrated; per-profile rubric weight overrides) | [methodology/AGENT-PROFILES.md](references/methodology/AGENT-PROFILES.md) |
| **Config-as-code patterns** (TOML/YAML config design for agents; schema export, config validate / show / set / get with `--json`; profiles, hierarchical configs, sensitive values) | [methodology/CONFIG-AS-CODE-PATTERNS.md](references/methodology/CONFIG-AS-CODE-PATTERNS.md) |
| **Plugin and extension surfaces** (auditing plugin-aware tools like cargo + cargo-audit; plugin manifests; cross-plugin alignment) | [methodology/PLUGIN-AND-EXTENSION-SURFACES.md](references/methodology/PLUGIN-AND-EXTENSION-SURFACES.md) |
| **Crash recovery and resumability** (long-running ops; idempotency tokens; state files; doctor-aware resume; transactional mutations; heartbeats) | [methodology/CRASH-RECOVERY-AND-RESUMABILITY.md](references/methodology/CRASH-RECOVERY-AND-RESUMABILITY.md) |

### Rubric
| Need | File |
|------|------|
| 11-dimension rubric with 0/250/500/750/1000 anchors | [rubric/SCORING-RUBRIC.md](references/rubric/SCORING-RUBRIC.md) |
| Priority formula (frequency × score_gap × blast_radius) | [rubric/PRIORITY-FORMULA.md](references/rubric/PRIORITY-FORMULA.md) |
| Per-surface-class scoring guidance (verb / flag / env var / exit code / error msg / config / lockfile / signal) | [rubric/SURFACE-CLASSES.md](references/rubric/SURFACE-CLASSES.md) |
| Regression-test patterns per dimension | [rubric/REGRESSION-TEST-PATTERNS.md](references/rubric/REGRESSION-TEST-PATTERNS.md) |
| **Rubric extensions** (per-project additional dims: security, performance, accessibility, internationalization, telemetry transparency, cross-platform consistency, SDK consistency) | [rubric/RUBRIC-EXTENSIONS.md](references/rubric/RUBRIC-EXTENSIONS.md) |
| Rubric changelog and calibration history | [rubric/CHANGELOG.md](references/rubric/CHANGELOG.md) |

### Exemplars (Track A corpus — the source of truth for "what good looks like")
| Need | File |
|------|------|
| Canonical CLI exemplars distilled (`dcg`, `bv`, `am`, `ubs`, `cass`) — 25 numbered patterns | [exemplars/CANONICAL-EXEMPLARS.md](references/exemplars/CANONICAL-EXEMPLARS.md) |
| Counter-examples (CE-1 to CE-20 — real CLI anti-patterns to recognize) | [exemplars/COUNTER-EXAMPLES.md](references/exemplars/COUNTER-EXAMPLES.md) |
| CASS findings — surprising patterns from prior agent sessions | [exemplars/CASS-FINDINGS.md](references/exemplars/CASS-FINDINGS.md) |
| **Worked end-to-end audits** — Phase-by-phase walkthroughs of dcg / bv / am / ubs / cass + 10 widely-deployed CLIs (jq, ripgrep, gh, kubectl, npm, cargo, ffmpeg, terraform, aws, docker) | [exemplars/WORKED-EXAMPLES.md](references/exemplars/WORKED-EXAMPLES.md) |
| **Canonical task library** — pre-built task corpora per CLI archetype (15 archetypes × 4-5 tasks each) + 8 universal U-Tasks for Phase 9 simulators | [exemplars/CANONICAL-TASK-LIBRARY.md](references/exemplars/CANONICAL-TASK-LIBRARY.md) |
| **Canonical exemplars (deep)** — code-level analysis of dcg/bv/am/ubs/cass with real `--help` excerpts, capabilities snippets, code idioms (quick-reject filter, two-phase analysis, stable handles, provenance fields, recommended-action) | [exemplars/CANONICAL-EXEMPLARS-DEEP.md](references/exemplars/CANONICAL-EXEMPLARS-DEEP.md) |
| **Tier-scoped case studies** — T1 through T5 audit summaries; right-sizing the audit; ROI by tier; common audit shapes per tier | [exemplars/CASE-STUDIES.md](references/exemplars/CASE-STUDIES.md) |

### Source corpus (read-only evidence)
| Need | File |
|------|------|
| Source quote bank (Q-001 … Q-NNN) | [exemplars/QUOTE-BANK.md](references/exemplars/QUOTE-BANK.md) |
| Calibration fixture set for self-tests and validator checks | [calibration-fixtures/README.md](references/calibration-fixtures/README.md) |
| AGENTS.md compliance checklist (live link) | [`AGENTS.md`](../../../AGENTS.md) (from the source corpus, not shipped with this skill) |

---

## Scripts

These run as part of the phase loop. They are reusable across passes; they all read `audit/manifest.json` to know which pass + target they're operating on.

> **Self-documentation contract.** Every script in `scripts/` and `tools/` responds to `--help` (or `-h`) with a clean usage block: synopsis, args, output, exit codes, and an example. The skill practices what it preaches — if you forget the args for any script, just append `--help`. Running with missing required args prints the same usage to stderr and exits 1 (no shell-jargon error, no stack trace).
>
> **`scripts/` vs `tools/`.** Files in `scripts/` are the explicit-arg phase-loop building blocks (every required path is a positional arg). Files in `tools/` are smart wrappers that auto-detect the in-tree audit workspace (legacy arg name: sibling) and current pass from `audit/manifest.json` — typically what you reach for ad-hoc once an audit is underway. Same-named pairs (`scripts/diff_scorecards.sh` / `tools/diff_scorecards.sh`) share behavior; the `tools/` version exec's the `scripts/` one with auto-resolved arguments.

| Script | Purpose |
|--------|---------|
| `scripts/check-skills.sh` | Detect referenced helper skills + jsm state; write `phase0_skill_inventory.json` |
| `scripts/install-referenced-skills.sh` | Bulk-install missing skills via jsm |
| `scripts/discover-cli.sh` | Detect language, build system, binary entry points, completion-script paths, embedded man pages |
| `scripts/scaffold-workspace.sh` | Create `audit/`, `regression_tests/`, `agent_simulations/` etc. inside `<target>/agent_ergonomics_audit/`. Does NOT run `git init` — the workspace lives inside the target repo and uses the target's existing git history. |
| `scripts/inventory_surfaces.sh` | Phase 1: recursive `--help` walk; emit `surface_inventory.jsonl` skeleton with surface_ids |
| `scripts/score_surface.sh` | Phase 2 **stub**: emits a placeholder partial JSONL line (all 500s, no evidence) for plumbing tests. Real scoring is LLM-driven via `subagents/scorer.md`; final aggregated rows are produced by `scripts/aggregate_scores.sh`. |
| `scripts/aggregate_scores.sh` | Phase 2: read per-scorer partials and emit final `agent_surfaces.jsonl` rows (median + spread + score_confidence) per IO-CONTRACTS schema |
| `scripts/generate_intent_corpus.sh` | Phase 3: deterministically generates the **naive** corpus (categories A/C/D/G — flag typos, spelling variants, tool-family confusion, env-var typos) from `surface_inventory.jsonl` into `audit/partial/intent_naive.jsonl`, then prints the spawn instruction for the LLM-driven savvy generator (categories H–M; needs source-level evidence). |
| `scripts/run_intent_corpus.sh` | Phase 3: invoke each corpus entry against the binary; classify outcome |
| `scripts/synthesize_recommendations.mjs` | Phase 4: deterministically **merge** recs with identical `diff_sketch` (union surface_ids, max per-dim uplift, max-component priority, shortest title), assign sequential R-NNN IDs, sort by priority desc. For semantic merging where prose differs but intent matches, follow up with `subagents/synthesizer.md`. |
| `scripts/render_heatmap.sh` | Render `agent_surfaces.jsonl` → `heatmap.svg` (surfaces × dims, hot=low) |
| `scripts/render_scorecard.sh` | Render `agent_surfaces.jsonl` → `scorecard.md` |
| `scripts/diff_scorecards.sh` | Compare two passes; emit `uplift_diff.md` + `regression_alerts.md` |
| `scripts/run_simulation.sh` | Phase 3/9 **stub orchestrator**: creates `audit/agent_simulations/<stage>_pass_<N>/` and prints the spawn instruction for `subagents/canonical-task-simulator.md`. The simulator subagent (LLM-driven, fresh context) attempts the canonical tasks and writes the transcripts. |
| `scripts/replay_simulation.sh` | Re-run a captured simulation transcript against the current binary |
| `scripts/validate_pass.sh` | Pre-flight + end checklist enforcement; exits non-zero if checklist incomplete |
| `scripts/manifest_update.sh` | Atomically update `audit/manifest.json` with new artifacts/scores/pass |
| `scripts/extract-known-flags.sh` | Extract canonical KNOWN_FLAGS list from source (Rust+clap, Go+cobra, Python+argparse/click, TS+commander, Bash) — keeps typo-correction in sync |
| `scripts/verify-stdout-stderr-split.sh` | Verify a tool's stdout is data-only and stderr is diagnostics-only |
| `scripts/verify-determinism.sh` | Verify --json output is byte-identical across re-runs (with SOURCE_DATE_EPOCH pinned) |
| `scripts/verify-non-tty-discipline.sh` | Verify NO_COLOR / CI=true / TERM=dumb / piped-stdout are honored; no prompts in non-TTY |
| `scripts/build-canonical-tasks.sh` | Generate audit/canonical_tasks.md for Phase 9 simulator from archetype + library |
| `scripts/sw-self-audit.sh` | Self-audit any Claude Code skill against the agent-ergonomics methodology |
| `scripts/measure-help-readtime.sh` | Estimate agent reading time for `--help` (lines + tokens + structural signals) |
| `scripts/audit-readme-vs-help.sh` | Detect README → `--help` drift (commands documented but missing; or vice versa) |

Each script either writes its documented phase artifact or emits documented stdout for redirection. JSON-only behavior is called out per script. All scripts honor `NO_COLOR`, exit 0 on success, ≥1 on failure with a stderr error message naming the next remediation step. The skill practices what it preaches.

## Tools (per-workspace utilities; reusable across passes)

| Tool | Purpose |
|------|---------|
| `tools/rescore_surface.sh <surface_id>` | Re-run Phase 2 scoring for one surface; useful after a targeted change |
| `tools/diff_scorecards.sh [sibling-dir]` | Print per-dimension delta table; auto-detects sibling + reads `current_pass` from manifest, diffs `(current_pass - 1)` → `current_pass`. For non-adjacent passes use `scripts/diff_scorecards.sh` directly. |
| `tools/render_heatmap.sh [sibling-dir] [pass]` | Render heatmap for the given pass (defaults to `current_pass`); writes `audit/heatmap.svg` |
| `tools/replay_simulation.sh <task-slug-or-id> [sibling-dir]` | Replay a captured Phase 9 simulation transcript against the current binary |
| `tools/compute_surface_id.sh <kind> [<subtree>] <name>` | Compute deterministic surface_id from descriptor (used by validators) |
| `tools/validate_scorecard.sh <agent_surfaces.jsonl>` | Reject scorecards with > 700 scores lacking evidence; also enforces `score_confidence` + `scored_at` per IO-CONTRACTS |
| `tools/flip_applied.sh <RECOMMENDATION_ID> [<COMMIT_SHA>] [<sibling>]` | Flip a recommendation's `applied` to `true` in `audit/recommendations.jsonl` (concurrent-safe via flock); used by `applier.md` Step 8 |

---

## Subagents

| Subagent | Phase | Purpose |
|----------|-------|---------|
| `subagents/cass-miner.md` | 0 | Mines user's prior cass sessions for tool-specific ergonomic complaints |
| `subagents/surface-inventorist.md` | 1 | Walks one subcommand subtree; emits surface records with citations |
| `subagents/scorer.md` | 2 | Scores one surface across all 11 dimensions with evidence |
| `subagents/scorer-tiebreaker.md` | 2 | Resolves per-dim spreads ≥ 300 between two scorers |
| `subagents/intent-stresser-naive.md` | 3 | Generates wrong invocations using only `--help` access (no source) |
| `subagents/intent-stresser-savvy.md` | 3 | Generates wrong invocations with full source access |
| `subagents/intent-runner.md` | 3 | Invokes each corpus entry; classifies outcome (silent-fail / useless-error / useful-hint / inferred-and-acted / skipped) |
| `subagents/recommender.md` | 4 | Proposes recommended_fix blocks for below-quartile surfaces |
| `subagents/synthesizer.md` | 4 | Merges overlapping recs, removes contradictions, ranks by priority |
| `subagents/triangulator.md` | 4 / 7 | Multi-model verification (Claude + Codex + Gemini) for top recs |
| `subagents/applier.md` | 5 | Implements one recommendation by committing directly to the target's current branch (typically `main`); never creates a new branch |
| `subagents/regression-test-author.md` | 5 / 8 | Writes the golden/snapshot test that pins the recommendation |
| `subagents/re-scorer.md` | 6 | Re-runs Phase 2 against the post-apply binary; computes uplift |
| `subagents/fresh-eyes.md` | 7 | Generic fresh-eyes review using the three calibrated prompts |
| `subagents/self-doc-hardener.md` | 8 | Adds missing `capabilities`, `robot-docs`, `--robot-*` surfaces |
| `subagents/canonical-task-simulator.md` | 9 | Fresh-context agent attempts canonical tasks against the binary; emits transcript |
| `subagents/handoff-writer.md` | 10 | Writes `HANDOFF.md` for the next pass |
| `subagents/idea-generator.md` | 10 | Surfaces second-order ergonomic improvements via `/idea-wizard` |
| `subagents/cli-archetype-classifier.md` | 0 | Classifies target CLI into archetype(s); picks dimension-weight overrides + canonical-task corpus |
| `subagents/parity-auditor.md` | 1 / 4 | For tools with both MCP server + CLI; audits MCP-CLI parity; files parity-gap recs |
| `subagents/family-cross-cut-auditor.md` | 1 / 4 | For multi-tool families; cross-cut consistency dimensions; family-level recs |
| `subagents/migration-planner.md` | 4 / 5 | Plans deprecation rollouts; sequences stages 0→1→2→3 across passes; produces migration scripts |
| `subagents/canonical-task-author.md` | 0 | Generates canonical task definitions from archetype + README + CASS for Phase 9 simulator |
| `subagents/skill-self-applier.md` | 11 (meta) | Applies this skill to itself or to other Claude Code skills |
| `subagents/cheat-sheet-builder.md` | 8 / 10 | Generates project-specific CHEAT-SHEET.md / agent quickref tailored to the audited tool |
| `subagents/benchmark-collector.md` | 10 | Appends per-pass metrics to `audit/metrics_timeseries.jsonl`; renders `metrics_timeseries.md` |
| `subagents/decision-tree-walker.md` | (helper) | Walks DECISION-TREES.md trees deterministically; returns "what next?" recommendations |

## Subagent spawn-args reference

When the main agent spawns a subagent via the Agent tool, it MUST pass these required arguments verbatim in the prompt's "Inputs" section. Args not listed here are filled by the subagent from sources stated in its own `## Inputs` block (e.g., reading `<SIBLING>/audit/manifest.json` for `<PASS>`).

| Subagent | Required spawn args |
|---|---|
| `applier` | `<RECOMMENDATION_ID>` `<SIBLING>` `<TARGET>` `<TARGET_SHA>` (NO `<FEATURE_BRANCH>` — applier commits to the target's current branch) |
| `benchmark-collector` | `<SIBLING>` `<N>` (pass number) |
| `canonical-task-author` | `<SIBLING>` `<TARGET>` |
| `canonical-task-simulator` | `<TOOL>` `<PASS>` `<TASK_LIST>` `<TRANSCRIPT_DIR>` `<SIBLING>` `<N>` |
| `cass-miner` | `<TOOL>` `<SIBLING>` |
| `cheat-sheet-builder` | `<SIBLING>` |
| `cli-archetype-classifier` | `<TARGET>` `<SIBLING>` |
| `decision-tree-walker` | `<DECISION_POINT>` `<SIBLING>` |
| `family-cross-cut-auditor` | `<SIBLING>` |
| `fresh-eyes` | `<TARGET>` `<SIBLING>` |
| `handoff-writer` | `<SIBLING>` `<N>` |
| `idea-generator` | `<TOOL>` `<SIBLING>` |
| `intent-runner` | `<TOOL>` `<SIBLING>` |
| `intent-stresser-naive` | `<TOOL>` |
| `intent-stresser-savvy` | `<TOOL>` `<TARGET_SHA>` `<SIBLING>` |
| `migration-planner` | `<SIBLING>` |
| `parity-auditor` | `<TARGET>` `<SIBLING>` |
| `recommender` | `<SURFACE_ID>` `<SIBLING>` |
| `regression-test-author` | `<RECOMMENDATION_ID>` `<TARGET>` `<POST_APPLY_BINARY>` `<SIBLING>` |
| `re-scorer` | `<SURFACE_ID>` `<TARGET_SHA>` `<RUBRIC_VERSION>` `<SIBLING>` |
| `scorer` | `<SURFACE_ID>` `<SCORER_ID>` `<TARGET_SHA>` `<RUBRIC_VERSION>` `<PASS>` `<SIBLING>` |
| `scorer-tiebreaker` | `<SURFACE_ID>` `<DIMENSION>` `<PASS>` `<SIBLING>` |
| `self-doc-hardener` | `<TOOL>` `<TARGET>` `<SIBLING>` |
| `skill-self-applier` | `<TARGET_SKILL>` `<SIBLING>` |
| `surface-inventorist` | `<TOOL>` `<SUBTREE>` `<TARGET_SHA>` `<SIBLING>` |
| `synthesizer` | `<SIBLING>` |
| `triangulator` | `<SUBJECT>` `<TARGET>` `<TRIANGULATION_ID>` `<SIBLING>` |

**Spawn pattern (parallel subagents).** When a phase calls for multiple subagents to run in parallel (e.g. Phase 2 spawns scorer-A + scorer-B for the same surface), invoke the Agent tool with **multiple tool-use blocks in a single message** — Claude Code runs them concurrently. Don't spawn them sequentially across multiple turns; that loses the parallelism the phase budget assumes.

## Assets

| Asset | Purpose |
|-------|---------|
| `assets/intake-prompt.md` | Use at very start of skill invocation to gather inputs |
| `assets/manifest-template.json` | Initial `audit/manifest.json` structure |
| `assets/surface-record-template.jsonl` | One-line example for `surface_inventory.jsonl` / `agent_surfaces.jsonl` |
| `assets/recommendation-template.jsonl` | One-line example for `recommendations.jsonl` |
| `assets/applied-change-template.jsonl` | One-line example for `applied_changes.jsonl` |
| `assets/scorecard-template.md` | Markdown template for human-readable scorecard |
| `assets/handoff-template.md` | Template for `HANDOFF.md` |
| `assets/regression-test-template.sh` | Template for golden/snapshot test in `audit/regression_tests/` |
| `assets/canonical-task-template.md` | Template for a Phase 9 canonical-task definition |

---

## Self-Test

Trigger phrases that should activate this skill:

- "Audit this CLI for agent ergonomics"
- "Make `<tool>` agent-friendly"
- "Score `<tool>` for how usable it is by an AI agent"
- "Add a `--robot-*` mode to my CLI"
- "Add `capabilities --json` and `robot-docs` to this tool"
- "Why does an agent always pick the wrong flag for `<tool>` — fix the intent inference"
- "Re-run the agent-ergonomics audit on `<tool>` and tell me which surfaces regressed"
- "Compare the pre-pass and post-pass agent simulations and tell me what got better"
- "Mine my prior agent sessions for places where this CLI's error messages didn't teach me anything, and prioritize those"
- "Build me a scorecard with a heatmap of every flag and exit code in this binary"
- "First command an agent tries should just work — make it so for `<tool>`"

Trigger-phrase probe + smoke test on a tiny CLI: [SELF-TEST.md](SELF-TEST.md).
