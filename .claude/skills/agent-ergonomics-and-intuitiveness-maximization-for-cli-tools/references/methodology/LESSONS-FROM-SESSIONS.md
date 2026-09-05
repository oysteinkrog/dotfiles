# LESSONS-FROM-SESSIONS — Durable failures-and-fixes from real applied passes

## Table of Contents

- [Format](#format)
- [Session: bv dogfood (2026-05-07, claude code, multi-agent)](#session-bv-dogfood-2026-05-07-claude-code-multi-agent)
- [Session: bv apply, Pass 1 (2026-05-08, codex)](#session-bv-apply-pass-1-2026-05-08-codex)
- [Session: bv apply, Pass 2 ("that's it??", 2026-05-08, codex)](#session-bv-apply-pass-2-thats-it-2026-05-08-codex)
- [Session: agent-ergonomics revision (2026-05-09, claude opus 4.7, the meta-pass)](#session-agent-ergonomics-revision-2026-05-09-claude-opus-47-the-meta-pass)
- [Session: agent-ergonomics expansion (2026-05-09, claude opus 4.7, after the meta-pass)](#session-agent-ergonomics-expansion-2026-05-09-claude-opus-47-after-the-meta-pass)
- [Pattern: "polite scorecard, stop"](#pattern-polite-scorecard-stop)
- [Pattern: "branch creation feels safer"](#pattern-branch-creation-feels-safer)
- [Pattern: "size-driven downshift"](#pattern-size-driven-downshift)
- [Pattern: "scorer drift between passes"](#pattern-scorer-drift-between-passes)
- [Pattern: "TUI-on-bare-invocation"](#pattern-tui-on-bare-invocation)
- [Pattern: "stdout/stderr split violation"](#pattern-stdoutstderr-split-violation)
- [Pattern: "no Levenshtein-1 typo correction"](#pattern-no-levenshtein-1-typo-correction)
- [Pattern: "non-TTY/CI/NO_COLOR not honored"](#pattern-non-ttycinocolor-not-honored)
- [Pattern: "missing capabilities endpoint"](#pattern-missing-capabilities-endpoint)
- [How to add an entry to this file](#how-to-add-an-entry-to-this-file)

This file is the long-form complement to the SKILL.md "Lessons From Real Sessions" inline summary. Every entry pairs a symptom (what the user observed) with the kernel axiom that prevents it. Each session is a calibration data point — when a pattern recurs across sessions, it gets promoted to a kernel axiom or an anti-pattern row.

> **Why this file exists.** Without a session corpus, we re-discover the same regressions every few weeks. The user has prodded multiple times with phrasings that became kernel axioms ("DO NOT CREATE A NEW BRANCH" → Axiom 1; "this skill should NEVER be making whole new sibling directories" → Axiom 2; "that's it??" → Axiom 3). Recording the prompts, the failures, and the fixes is how the methodology evolves.

---

## Format

Each session entry has this structure:

```
### Session: <name> (<date>, <agent: claude / codex / gemini>)

**User prompt (verbatim):** <quote>

**What went wrong:** <symptom the user observed>

**Why it went wrong:** <root cause analysis>

**Permanent fix:** <which axiom/rule/anti-pattern prevents this now>

**Durable wins (if any):** <what the session produced that's still valuable>

**Calibration data:** <pointer to fixture file if one was preserved>
```

Sessions are listed chronologically; the most recent are most influential because the methodology evolved through them.

---

## Session: bv dogfood (2026-05-07, claude code, multi-agent)

**User prompt:** "Apply the skill to bv to dogfood the methodology against a real CLI."

**What went wrong:** Nothing catastrophic — this was the first synthetic dogfood. The lessons are about what the methodology surfaced when run against a real tool.

**Why it ran well:** `bv` was already mid-development with clear `--robot-*` ambitions; the methodology had high signal-to-noise.

**Permanent fix:** Multiple — the bv dogfood is the calibration baseline. Every later run that violates a finding from this session is treated as a regression.

**Durable wins:**
- Confirmed the Σ Mega-Command operator (`bv --robot-triage`) as the single highest-leverage uplift across read-side commands.
- Surfaced that scorers genuinely diverge on `agent_ease_of_use` (one rewards help-text discoverability, another penalizes wall-clock-timestamp leaks). Tiebreaker process resolves these decisively when given evidence (not raw scores).
- Identified that recommenders show real judgment — one explicitly chose units-unification over the obvious Levenshtein answer because "the typo path applies to all flags and belongs in a global rec".
- **Real bugs found:** bare `bv` in non-TTY emits "could not open a new TTY" with no fallback hint (Axiom 15 violation). No Levenshtein-1 typo correction on any flag (Axiom 7 violation). Sibling flags use inconsistent units (int 0-100 vs float 0.0-1.0). `regression_resistance` scored 0 across all 3 surfaces (no ergonomic test suite, Axiom 17 violation).

**Calibration data:** `references/calibration-fixtures/bv-dogfood-2026-05-07.jsonl` — used as scorer-prompt-drift detection in future runs.

---

## Session: bv apply, Pass 1 (2026-05-08, codex)

**User prompt:**

```
First read ALL of the AGENTS.md file and README.md file super carefully and understand
ALL of both! Then use your code investigation agent mode to fully understand the code
and technical architecture and purpose of the project. Then apply
$agent-ergonomics-and-intuitiveness-maximization-for-cli-tools comprehensively to the
project. DO NOT CREATE A NEW BRANCH, DO ALL WORK ON main (any existing new branch
made for this must be folded into main)
```

**What went wrong:** The skill (legacy version) ran Phase 0 step 7 which says "create + checkout `agent-ergonomics-pass-<N>` branch in the target repo" and immediately created `agent-ergonomics-pass-1`. Then the user reacted: **"DO NOT CREATE A NEW BRANCH"**.

**Why it went wrong:** The Phase 0 step was hardcoded to branch creation as a "safety" measure. There was no kernel axiom that said "don't auto-branch." The legacy methodology assumed feature branches were always good. The user has different preferences for this skill specifically.

**Permanent fix:** **Axiom 1** (Branch policy is fixed; never auto-branch). Three redundant guards: kernel axiom + Branch Policy callout in SKILL.md + Anti-Pattern row + the kickoff prompt explicitly bans it. Plus the scaffold script no longer accepts a `<FEATURE_BRANCH>` argument; the applier subagent's input list explicitly says "NO FEATURE_BRANCH"; the manifest's `feature_branch` field is deprecated.

**Permanent fix part 2:** When a stale auto-branch from a prior version of this skill is detected, the correct move is to fold it back into `main` (with user confirmation if conflicts), not to add another branch on top.

**Durable wins:** None from Pass 1; the user had to abort and restart.

---

## Session: bv apply, Pass 2 ("that's it??", 2026-05-08, codex)

**User prompt (after Pass 1 abort + restart):** Same as Pass 1, plus the in-conversation correction "DO NOT CREATE A NEW BRANCH".

**What went wrong on Pass 2:** The skill produced a comprehensive scorecard + 47-rec playbook + recommendations.jsonl, then declared Phase 4 done and stopped. Phase 5 (apply) was skipped because the recs were "already documented." The user reacted:

```
that's it?? I was hoping you would get a lot more practical value out of this skill.
Where are the dramatic improvements???
```

**Why it went wrong:** The skill's natural attractor is "polite scorecard, stop." Phase 4's exit criterion was "playbook.md written" without a downstream gate that demanded Phase 5 actually happen. The mode was `full` but the Phase 5 step had no mandatory minimum.

**Permanent fix:** **Axiom 3** (Be ambitious. A polite scorecard is a failure.) + the Ambition Bar gate baked into Phase 10 as a verbatim "That's it??" self-prompt. Mode-default heuristic was rewritten so size never downgrades `full` to `audit-only`. Anti-pattern row added: "Stop after Phase 4 (recommendations only) when the user asked for `full`".

**Durable wins (after Pass 2 was forced):**
- 14+ commits accepting agent intent aliases (`bv triage --json`, `bv plan --json`, `bv next --json`, etc.) normalize to the correct `--robot-*` form.
- Intent-corpus generated 272 reasonable-but-wrong invocations.
- Pre-Pass: 271 useful_hint + 1 useless_error. Post-Pass: 272 useful_hint + 0 useless_error.
- Triage robot JSON now deterministic under `SOURCE_DATE_EPOCH`.
- `verify-stdout-stderr-split.sh` and `verify-determinism.sh` both green.

**Critical lesson:** Without the verbatim "That's it??" prompt baked in, the agent reverts to "polite scorecard" within a few re-runs. It's the ONLY mechanism that has reliably broken this attractor across re-runs.

---

## Session: agent-ergonomics revision (2026-05-09, claude opus 4.7, the meta-pass)

**User prompt:**

```
this skill should NEVER be making whole new sibling directories like this!!! it should
do all this stuff INSIDE THE REPO PROPER!!!
```

**What went wrong:** The legacy design used `<target>__agent_ergonomics_audit/` as a sibling directory next to the target, `git init`-ed separately. This created two parallel git histories — one for the code, one for the workspace — where the user wanted one. Plus, the sibling location confused `cd` operations across subagents (some thought `<sibling>` was a sub-directory of the target).

**Why it went wrong:** The legacy methodology assumed that "audit workspace = measurement record = separate concern from code = separate repo." But the user's mental model is "one repo, one history, one place to look." The methodology was over-engineered for a separation that didn't match how the user reasons about the work.

**Permanent fix:** **Axiom 2** (Workspace is in-tree; never a sibling.) + Workspace Policy callout + the in-tree layout. The scaffold script was rewritten to:
- Refuse to `git init` the workspace.
- Warn loudly if `<sibling>` is outside the target.
- Migrate any legacy sibling directory into the in-tree location with a `migrated_from_sibling: true` marker in the manifest.

**Durable wins:** The 19-axiom kernel was assembled from this revision pass; the variant-prompt corpus was extracted from real prior sessions; the lessons-from-sessions file (this one) was created as a permanent record so future revisions don't lose context.

---

## Session: agent-ergonomics expansion (2026-05-09, claude opus 4.7, after the meta-pass)

**User prompt:** "I REALLY STILL continue to think that you are barely scratching the surface of what is possible here with this skill and need to dramatically enhance and expand the scope and depth and breadth and usefulness of this skill."

**What went wrong:** The first revision pass added the three policy axioms (no branch, in-tree workspace, ambition bar) but didn't expand the *substance* of the skill — variant prompts, operator rules, lessons-from-sessions, sibling-skills map, mega-prompt, decision tree, kernel axioms. The user explicitly noted this was a missed opportunity.

**Why it went wrong:** The first pass treated the prompt as "fix three bugs" rather than "deliver a Track-A-grade artifact." The agent-ergonomics methodology IS a Track A artifact (per `OPERATIONALIZING-EXPERTISE-TRACK-A.md`); fixing bugs without adding the missing artifact slots leaves the artifact incomplete.

**Permanent fix:** This expansion pass added (in priority order):
1. The 19-axiom kernel (modeled on `git-worktree-branch-rationalization`'s rationalization kernel).
2. The 12-variant prompt corpus (modeled on `reality-check-for-project`'s Variants A–H).
3. The 7 operator rules distilled from sessions (modeled on `reality-check-for-project`'s "Operator Rules").
4. The sibling-skills composition map (which skills compose well, which conflict).
5. The Mega-Prompt verbatim copy-paste.
6. The Lessons-From-Sessions corpus (this file).
7. The Hand-off Template.
8. The Decision Tree at the top of SKILL.md.

**Durable wins:** This file. The methodology now has all five Track A artifacts (corpus + quote bank + triangulated kernel + operator library + validators) populated.

**Critical lesson:** When the user says "expand," they mean Track A artifact slots, not "add more anti-patterns." The skill is calibrated by the corpus + variants + lessons; expanding those is what makes the skill more useful.

---

## Pattern: "polite scorecard, stop"

**Frequency:** Observed in ≥ 3 independent sessions (bv Pass 2, two unnamed sessions in CASS).

**Symptom:** The agent runs Phase 0–4 with care, produces a thorough playbook, and stops without applying anything. The user reacts with "that's it??" or similar.

**Root cause:** The agent's natural attractor is "deliver analysis, decline implementation." Recommendations feel safer than commits; the agent has no internal pressure to ship.

**Prevention:** Axiom 3 + the verbatim "That's it??" self-prompt. NOT a paraphrase — the verbatim phrasing carries weight. Tested across re-runs: paraphrasing the prompt (e.g. "be more ambitious") does NOT defeat the attractor; verbatim quoting does.

**Why verbatim matters:** The phrasing the user originally used to break the attractor is the phrasing that breaks it again. Substituting "be more ambitious" for "that's it??" loses the implicit quality bar; "I was hoping you would get a lot more practical value out of this skill" is the disappointment-frame that triggers a different response than "you should ship more changes" (which the agent reads as a normal ambition target).

---

## Pattern: "branch creation feels safer"

**Frequency:** Observed in ≥ 2 sessions (bv Pass 1; one unnamed earlier session).

**Symptom:** Agent reflexively creates `agent-ergonomics-pass-1` or similar. User reacts with "DO NOT CREATE A NEW BRANCH".

**Root cause:** Cross-skill bleed. Agents trained on standard git workflows or skills that DO use feature branches (e.g. `git-worktree-branch-rationalization` with its rationalization branch) reflexively want to branch before risky changes. For this specific skill, the user's preference is the opposite.

**Prevention:** Axiom 1 + Branch Policy callout + Anti-Pattern row + kickoff prompt explicitly bans it + applier subagent's input list explicitly drops `<FEATURE_BRANCH>`. Five redundant guards because cross-skill bleed is sneaky.

**Edge case:** If the user *explicitly* says "use a branch called X" in their prompt, honor that — but the default and silent behavior is "current branch." Detected with a simple regex check on the user's prompt for `branch` + a name.

---

## Pattern: "size-driven downshift"

**Frequency:** Observed when discussing large CLIs (gh: 1900+ surfaces, docker: 1100+, kubectl: 800+). User asks for `full`; the agent reflexively suggests `audit-only` first because the surface count is "too much."

**Symptom:** "I'd recommend `audit-only` first since this is a large CLI; we can do `full` once we know what to focus on."

**Root cause:** The agent treats surface count as a complexity proxy, when in fact it's a prioritization input. Phase 4's job is to rank the recs and pick the top 10–20; the apply phase ships the top-N. Size doesn't change the mode; it changes the prioritization tightness.

**Prevention:** Mode-default heuristic explicitly calls this out. Auto-detect heuristic table now defaults `full` for ambiguous-intent prompts regardless of size. Anti-pattern row added: "Auto-downgrade `full` → `audit-only` because 'the surface count is large'".

**Counter-example test:** When applied to a synthetic 1500-surface CLI, the methodology should still default to `full` and pick the highest-leverage 15 surfaces in Phase 4.

---

## Pattern: "scorer drift between passes"

**Frequency:** Observed across re-runs of the bv dogfood (calibration check).

**Symptom:** Pass 2's scorer assigns a surface 750/1000 on a dimension where Pass 1's scorer assigned 875/1000. No code change. Just scorer prompt drift.

**Root cause:** The rubric anchors at 0/250/500/750/1000 are calibrated through worked examples; if the examples drift (e.g. due to a refactor of `references/rubric/SCORING-RUBRIC.md`), scorers re-anchor at slightly different points.

**Prevention:** Pin `rubric_version` (git SHA of `SCORING-RUBRIC.md`) in `manifest.json` for every scoring run. Calibration fixtures (`bv-dogfood-2026-05-07.jsonl`) detect drift — re-run the scorer against the fixture and verify scores match within ±50 pts. If they don't, the rubric drifted; investigate before continuing.

**Permanent fix:** The Phase 0 manifest seed always records `rubric_version`. Phase 6 (re-score) compares against the same `rubric_version` as Phase 2 (initial score) — if the rubric changed between, the comparison is logged as `rubric_version_drift: true` and the uplift number is annotated as "may be partially attributable to rubric change."

---

## Pattern: "TUI-on-bare-invocation"

**Frequency:** Observed in ≥ 4 tools (bv, br, certain Tauri CLIs, certain monorepo tools).

**Symptom:** Bare `<tool>` (no args) launches an interactive TUI. Agent invocations get stuck waiting for keyboard input that never comes; piped invocations hang or emit "could not open a new TTY."

**Root cause:** Designers assume bare-invocation = "user wants to explore," when for agents bare-invocation = "show me the help / capabilities so I can decide what to do."

**Prevention:** Axiom 15. The fix is one of:
1. Bare `<tool>` shows useful help/triage and exits.
2. Bare `<tool>` in non-TTY mode emits the help; in TTY mode emits the TUI.
3. `<tool>` requires a subcommand; `<tool> tui` is the explicit interactive entry point.

Pattern (1) is the simplest. Pattern (2) is more forgiving but requires non-TTY detection (`isatty(STDOUT_FILENO)`). Pattern (3) is the most explicit but requires a breaking change.

**Phase 5 fix sketch:** Add `if !isatty(stdout) || env::var("NO_COLOR").is_ok() || env::var("CI").is_ok() { print_help(); return; }` at the top of the bare-invocation handler.

---

## Pattern: "stdout/stderr split violation"

**Frequency:** Almost universal — every audit catches at least one CLI doing this.

**Symptom:** `<tool> X --json | jq …` requires `grep -v ' INFO '` (or similar) on stdout to filter out log lines that should have been on stderr.

**Root cause:** The implementation uses `println!` / `print()` / `console.log()` for everything, including diagnostic output. The split between data (stdout) and diagnostics (stderr) wasn't a design decision; it accumulated from the path of least resistance.

**Prevention:** Axiom 4. The Polish Bar explicitly tests this with `verify-stdout-stderr-split.sh` (re-runs the binary with stdout piped to a file and stderr to another, then validates that stdout is parseable as the documented format).

**Phase 5 fix sketch:** Replace `println!` with `eprintln!` for everything that isn't the requested data. Audit log levels, progress bars, deprecation warnings, debug output — all to stderr. The `tracing` / `log` / `pino` crates make this explicit; raw `println!` is the smell.

---

## Pattern: "no Levenshtein-1 typo correction"

**Frequency:** Observed in nearly every CLI on first audit.

**Symptom:** Agent types `<tool> command --jsno foo` (typo for `--json`), gets `error: unrecognized argument '--jsno'` with no suggestion, and now has to search docs to figure out the right spelling.

**Root cause:** Most CLI frameworks (clap, cobra, click, commander) emit "unknown flag" without computing edit distance to known flags. The frameworks support typo correction but it's an opt-in feature.

**Prevention:** Axiom 7. The Phase 5 fix sketch is in `LANGUAGE-RECIPES.md` per language:
- Rust + clap: enable `infer_subcommands(true)` + `infer_long_args(true)` + custom error formatter that emits "did you mean: `--json`?".
- Go + cobra: register `cobra.SuggestionsMinimumDistance = 1` + `cobra.NoErrors`.
- Python + click: use `click.Context.fail` with a suggestion derived from `difflib.get_close_matches()`.
- TypeScript + commander: use `program.allowUnknownOption(false).showSuggestionAfterError()`.

`scripts/extract-known-flags.sh` keeps the suggestion list in sync with source — adds a regression test that fails if a new flag is added without being in the suggestion list.

---

## Pattern: "non-TTY/CI/NO_COLOR not honored"

**Frequency:** Common — every audit catches at least one CLI emitting ANSI codes into a piped stdout.

**Symptom:** `<tool> list | tee output.txt` produces output with `\x1b[31m` color codes embedded; downstream parsers choke.

**Root cause:** Color is emitted unconditionally. The fix is to detect non-TTY (`!isatty(STDOUT_FILENO)`) and / or honor `NO_COLOR=1` / `CI=true` / `--no-color`.

**Prevention:** Axiom 13. `verify-non-tty-discipline.sh` re-runs the binary with `< /dev/null` and `NO_COLOR=1` and `CI=true` and `TERM=dumb` and verifies no ANSI codes appear in stdout.

---

## Pattern: "missing capabilities endpoint"

**Frequency:** Almost universal on first audit.

**Symptom:** Agent has to *remember* the tool's contract (subcommand list, flag list, exit-code dictionary, env-var list) instead of asking the tool. Out-of-band doc lookup required, fragile across versions.

**Root cause:** `<tool> capabilities --json` is a Claude-Code-era idea; older CLIs predate the convention.

**Prevention:** Axiom 9. The fix is to add `capabilities` as a subcommand returning a documented JSON schema. `MEGA-COMMAND-DESIGN.md` has the canonical shape.

**Schema essentials:**
```json
{
  "version": "0.16.0",
  "contract_version": "1.1.0",
  "feature_flags": ["robot-triage", "json-output", "non-tty-discipline"],
  "commands": [{"name": "list", "verb": "read", "supports_json": true}, ...],
  "exit_codes": {"0": "success", "1": "user-input-error", "2": "safety-block", ...},
  "env_vars": {"BV_OUTPUT_FORMAT": "json|toon", ...}
}
```

A `capabilities` schema is what makes the rest of the methodology stable — every other surface can reference it.

---

## How to add an entry to this file

When a session reveals a new pattern (or contradicts an existing one), add an entry following the format at the top. Required fields:

1. **Session name + date + agent.**
2. **User prompt verbatim** — the actual phrasing that drove the failure or the win. Don't paraphrase; the calibration depends on exact wording.
3. **What went wrong.**
4. **Why it went wrong.**
5. **Permanent fix** — which axiom/rule/anti-pattern prevents it now. If the fix didn't yet exist, add it as part of the entry and cross-reference.
6. **Durable wins** — what survives. Often a calibration fixture or a new operator.
7. **Calibration data pointer** — if a fixture was preserved.

If the pattern has been observed ≥ 3 times across distinct sessions, promote it to a kernel axiom (in SKILL.md) AND keep the long-form entry here.
