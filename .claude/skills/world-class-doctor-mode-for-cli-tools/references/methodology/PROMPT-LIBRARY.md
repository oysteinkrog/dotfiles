# Prompt Library — Copy-Paste Recipes

This file is the doctor methodology's prompt library: pre-built prompts you can paste into a Claude Code session (or any agent) to make the methodology actionable. Each prompt is calibrated; use verbatim unless you need a project-specific substitution.

Organization: by goal (what the user wants to do), not by phase. The phase-specific subagent prompts live in [AGENT-PROMPTS.md](AGENT-PROMPTS.md); this file is for higher-level "I want the agent to ___" intents.

---

## I want to apply the skill to a project (full pass)

```
Apply the world-class-doctor-mode-for-cli-tools skill to {{project-path}}.

Read these in this order before starting:
1. {{skill}}/SKILL.md (full)
2. {{skill}}/references/methodology/KERNEL.md (the 24 axioms)
3. {{skill}}/references/methodology/COOKBOOK.md (15 patterns)
4. {{skill}}/references/methodology/WORKED-EXAMPLE.md (concrete pass)
5. {{skill}}/references/recipes/{{language}}.md

Then walk through Phase 0 confirmations with me. Defaults:
- Mode: auto-detect (you choose; ask if ambiguous)
- Operating location: worktree (default; doctor-mode-pass-1 branch)
- Triangulation: peer-claude
- CASS mining: quick (Phase 0 canned queries)
- Online: offline-only

Hard-stop on any axiom violation. Don't push to main without explicit approval.
At the end of each phase, summarize state and pause for review.
```

---

## I want a quick audit (no code changes)

```
Apply world-class-doctor-mode-for-cli-tools in audit-only mode to {{project-path}}.

Run Phases 0, 1, and 6 (scoring only). Produce:
- {{workspace}}/scorecard.md
- {{workspace}}/heatmap.svg
- {{workspace}}/recommendations.jsonl
- {{workspace}}/playbook.md

Do not modify any code in the target. Report:
- Aggregate score (0-1000)
- Top 5 below-quartile findings with priority
- Estimated effort to lift each top-5 to >= 850
```

---

## I want to check a specific failure mode

```
Single-failure-mode-rescore for {{tool}}'s doctor:
- Target: {{path}}
- FM id: {{fm-id}}

Re-mine evidence for {{fm-id}} (Phase 1 scoped). Re-score across all 10 dimensions
(Phase 6 scoped). Append one row to failure_mode_scores.jsonl.

Hard-stop if regressed > 50 pts vs. previous pass. Report aggregate + cited
file:line for any score >= 700.
```

---

## I want to absorb a manual playbook

```
Apply world-class-doctor-mode-for-cli-tools in absorb-playbook mode:
- Target repo: {{target-repo}}
- Source playbook skill: {{playbook-skill-path}}
- Mode: absorb-playbook
- Triangulation: multi-model

Convert each step of the source playbook into a Repair Spec. Run all 10 phases.
Phase 8 demotes the source playbook to "fallback" status without deleting any
of its content (per AGENTS.md no-delete rule).

For each absorbed step, produce a fixture in tests/doctor_fixtures/
that reproduces the broken state and asserts the new fixer handles it.
```

---

## My agent invoked the doctor and got exit 4 — what now?

```
The doctor at {{path}} returned exit 4 with this output:
{{paste --json output here}}

Read the finding's evidence carefully. Then:
1. State which precondition failed (cite the precondition name from the finding).
2. State whether the precondition is intent-bearing (user must act) or
   incidentally-failed (could be retried).
3. If intent-bearing: surface the manual remediation to the user verbatim.
4. If incidentally-failed: explain what would clear it and ask for permission to retry.

Do NOT use --force without my explicit "yes I want --force" reply.
```

---

## My agent invoked the doctor and got exit 5 (concurrency lost)

```
The doctor returned exit 5; another doctor holds the lock.

1. Run `<tool> doctor ls --json` to see the holder's run-id.
2. If holder_pid is alive: wait 10s and retry once.
3. If holder_pid is dead: this is a stale lock; surface to me; do NOT force-release without my approval.
4. If retry succeeds: report the result. If retry also exits 5: surface to me with full details.
```

---

## My agent invoked the doctor and got exit 3 (fix failed and rolled back)

```
The doctor returned exit 3. The mutation was rolled back per Axiom 3.

Read the {{run-dir}}/report.json::error and {{run-dir}}/actions.jsonl in detail.

Report:
1. Which fixer failed (fixer_id from the last actions.jsonl line).
2. What the failure was (error string).
3. Whether the rollback completed cleanly (look for `rolled_back: true` lines).
4. Whether the workspace is back to its pre-fix state (compare hashes).

Do NOT retry the same fixer; the fix path is broken until the fixer is patched.
```

---

## I want to extend the doctor with a new failure mode

```
Add a new failure mode to {{tool}}'s doctor:
- FM id: fm-{{subsystem}}-{{symptom-slug}}
- Severity: P{{0|1|2|3}}
- Symptoms (from cass mining): {{paste evidence}}

Steps:
1. Append to {{workspace}}/analysis/failure_modes/{{subsystem}}.md.
2. Write a Repair Spec at {{workspace}}/analysis/repair_specs/{{fm_id}}.md
   per the template in {{skill}}/assets/repair-spec-template.md.
3. Implement the detector (pure) and fixer (through mutate()) per
   {{skill}}/references/recipes/{{language}}.md.
4. Build the fixture at tests/doctor_fixtures/{{fm_id}}/{corrupt.sh, assert.sh, README.md}.
5. Run all Phase 5 verifiers (verify-undo, verify-idempotence, verify-crash-recovery, verify-concurrency, verify-metamorphic).
6. Update capabilities --json so the new FM is declared.
7. Re-score; assert no regression > 50 pts.

Hard-stop if any safety harness test fails.
```

---

## I want to retire an old fixer (Axiom 21 decay)

```
Retire fixer {{fm_id}} from {{tool}}'s doctor.

Per Axiom 21 (Decay-Aware) and per AGENTS.md no-delete:
1. Mark `deprecated: true` in capabilities --json::fixers[] for this id.
2. Skip it in the runtime registry; do NOT delete the source code.
3. Keep the fixture (it documents the historical FM).
4. Add a CHANGELOG entry: "Retired fm-{{fm_id}}; not invoked since {{date}}."
5. After 1 year of zero invocations the file MAY be moved to a `deprecated/`
   subdirectory (still NOT deleted).

Cite the scorecard_history.jsonl evidence showing zero recent invocations.
```

---

## I want to add a Cookbook pattern

```
Propose Cookbook pattern N for the doctor methodology:
- Pattern title: {{name}}
- Examples (existing CLIs that match): {{list}}
- Failure-mode classes specific to this pattern: {{list}}
- Surface variations: {{flag changes / new subcommands}}

Per the existing cookbook style:
1. Add a new section to {{skill}}/references/methodology/COOKBOOK.md.
2. Add a row to the SKILL.md "Cookbook" table.
3. Update CHANGELOG.md.
4. If a recipe is needed (per-language specifics), add to references/recipes/.
5. Identify at least 2 /dp/ projects that would benefit from this pattern.
```

---

## My doctor's score regressed — investigate

```
The doctor's score dropped from {{N-1}} to {{N}} at {{run-id}}.

1. Run `python3 {{skill}}/scripts/diff-scorecards.py {{workspace}} {{N-1}} {{N}}`.
2. Identify the FM(s) that regressed.
3. For each, run `git log --since={{prior-pass-date}} -- {{relevant-source-files}}` to
   find the commit that introduced the regression.
4. Report:
   - FM id + dimension that regressed
   - Suspected commit SHA + author + message
   - Whether the regression is intentional (trade-off) or a bug
5. If intentional: write the ACK in {{workspace}}/regression_alerts.md.
   If a bug: revert the commit and re-run Phase 6.
```

---

## I want to apply the skill to a tool I don't own (Pattern 8)

```
Apply Pattern 8 (doctor for a tool you don't own):

The CLI is {{tool}}; we don't own its source. Build a wrapper at
{{wrapper-name}}-doctor that:

1. Probes {{tool}}'s state via its existing read-only commands (e.g.,
   `{{tool}} status --json`, `{{tool}} list`).
2. Wraps any mutations via {{wrapper-name}}-doctor's own mutate() chokepoint
   for {{tool}}'s config files (which we DO own and can modify).
3. Refers to {{tool}}'s own remediation commands as `manual_remediations`
   in capabilities --json — never invoke {{tool}}'s mutating commands directly.

Failure modes are externally-observed only; we cannot probe {{tool}}'s
internals beyond what its CLI exposes.
```

---

## I'm an agent and I want to use the doctor (zero-context start)

```
You're an agent in a fresh session. The project at {{path}} may be broken.

First, run:
  {{tool}} doctor robot-docs

This is your contract. Read it in 30 seconds. Then run:
  {{tool}} doctor --robot-triage --json

This returns {summary, findings, actions_planned, recommended_command, capabilities_url} in one call.

Decision tree:
1. summary.ok == true → nothing to do; exit.
2. summary.auto_fixable == summary.total_findings → run recommended_command.
3. else → for each finding where remediation.auto_fixable == false, surface
   the manual_remediation to the user; act on the auto-fixable rest only.

Never invoke --fix without diagnose first. Never use --force without --yes.
On exit 4: surface; do not retry. On exit 5: wait + retry once.
```

---

## I want to dogfood the methodology (smoke-test on a tiny CLI)

```
Run the SELF-TEST.md procedure to dogfood the skill:

1. Create a tiny throwaway CLI at /tmp/tinycli.{{date}}/.
2. Apply Phases 0-1 against it (won't get to Phase 4+ because the CLI is too
   small to need real fixers).
3. Verify the workspace was scaffolded correctly.
4. Verify discover-cli.sh detected the language.
5. Run validate-skill.sh against this skill itself; expect OK.
6. Report any deviations.

The smoke test is documented at {{skill}}/SELF-TEST.md.
```

---

## I want to write the doctor's own CHANGELOG entry

```
Append a CHANGELOG entry for {{tool}}'s doctor:

- Version bump per [VERSIONING.md]: minor for new fixers, major for breaking
  changes to the contract.
- Sections: Added / Changed / Bug fixes.
- For each entry, cite the bead ID and the commit SHA.
- For breaking changes, include a migration note (per [VERSIONING.md] strategy
  A or B).

Per /changelog-md-workmanship discipline: this entry takes precedence over
auto-generated content.
```

---

## I want to spawn an NTM swarm to apply the skill in parallel

```
Spawn an NTM swarm for doctor-mode-pass-{{N}}:

- 4 panes (Squad tier) — see {{skill}}/references/methodology/ORCHESTRATION.md
- Pane 1: archaeologist for state_files + configs subsystems
- Pane 2: archaeologist for schemas + caches subsystems
- Pane 3: archaeologist for sockets + hooks + plugins subsystems
- Pane 4: lead orchestrator + Phase 3 synthesizer

Marching orders per pane should reference:
- {{skill}}/SKILL.md
- {{skill}}/references/methodology/AGENT-PROMPTS.md (verbatim per-phase prompts)
- {{skill}}/references/methodology/AGENT-MAIL-INTEGRATION.md (file reservations)
- {{skill}}/references/methodology/BEADS-INTEGRATION.md (task graph)

Use Agent Mail thread `doctor-pass-{{N}}-archaeology`. Beads pre-filed with
priorities matching FM severity.
```

---

## I want the agent to preserve uncommitted edits while applying the skill

```
Apply the skill to {{path}}, BUT:

Per AGENTS.md § Codex/GPT-5.5 footnote: there are likely uncommitted edits
made by other agents. Treat them as if I made them. Do NOT git stash, git
reset, or git clean. Doctor's --fix is scoped to write_scopes
({{capabilities-json::write_scopes}}); the source code is OUT of scope.

If a file in write_scopes is currently being edited by another agent (Agent
Mail reservation showing exclusive=true), refuse to proceed. Surface the
conflict to me.
```

---

## I want to make the doctor's robot-docs even better

```
Audit {{tool}}'s doctor robot-docs output:

1. Compare against the canonical sections in {{skill}}/references/methodology/CLI-SURFACE.md.
2. Check the negative-space spec ("things this doctor will NEVER do") includes:
   - Delete files (per AGENTS.md RULE 1)
   - Run rm -rf, git reset --hard, git clean -fd
   - Touch out-of-scope paths
   - Probe network without --online
   - Mutate when lock held
   - Mutate without backup
   - Push to main
   - Interactive prompts under --robot
   - ANSI to stdout under --robot

3. Check examples cover: healthy state, findings present, --fix flow, undo flow, --explain flow.

4. Verify schema URLs in capabilities --json point at machine-readable schemas.

5. Score the current robot-docs against the agent-ergonomics rubric (subagents/agent-ergo-grader.md).
```

---

## I want to know whether my project is "ready" for the skill

```
Pre-flight check for {{path}}:

1. Does the project have ≥ 3 recurring failure modes (per cass mining or bug tracker)?
2. Does the project's contributors actually run the CLI (vs. just maintain it)?
3. Is there an existing diagnostic surface (doctor / health / verify / repair / check / diagnose / fix — the 7 verbs `discover-cli.sh --probe-doctor` looks for)?
4. Are there manual recovery commands documented anywhere (READMEs, AGENTS.md)?
5. Does the project have multi-agent activity (Q-009 — uncommitted edits "per minute")?

If yes to ≥ 3: ready for an `add` or `upgrade` pass.
If yes to ≤ 2: probably too early. Document recurring incidents first; come back later.
```

---

## How to use these prompts

- **Substitute** `{{...}}` placeholders with project-specific values.
- **Verbatim** — don't paraphrase. The prompts are calibrated against the user's session history.
- **Composable** — chain prompts together when an agent's response naturally leads to the next.
- **Cite back** — when a prompt directs the agent to a methodology file, the agent should cite the file in its response (helps with audit trail).

When you find yourself writing a recurring prompt that isn't here, add it. The library grows over time; new prompts replace ad-hoc ones.

---

## When NOT to use a prompt from here

- The situation is genuinely novel. Use first-principles reasoning + KERNEL.md.
- The prompt would force a destructive action without user consent. NEVER include `rm -rf`, `git reset --hard`, etc. in any prompt.
- The prompt would invoke `--force --yes` without an explicit user-typed authorization.

The library is a starting point, not a substitute for thought.
