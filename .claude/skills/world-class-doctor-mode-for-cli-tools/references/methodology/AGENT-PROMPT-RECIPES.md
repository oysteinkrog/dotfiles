# Agent-Prompt Recipes — Calibrated Prompts for Each Doctor Situation

[PROMPT-LIBRARY.md](PROMPT-LIBRARY.md) holds copy-paste prompts for the user. This file holds prompts the user gives to AGENTS that need to use the doctor. Tighter, structured, and always state the agent's role explicitly.

Use when you're the orchestrator and you need a sub-agent or peer agent to act.

---

## Recipe R-001 — Send a fresh agent at a doctor-broken project

```
You are a remediation agent. The project at {{path}} appears to have state issues.

Your tools:
- Run `<tool> doctor robot-docs` once. Read it.
- Run `<tool> doctor --robot-triage --json`. Parse it.

Your decision tree:
- If `summary.ok == true` → report "no action needed" and exit.
- If `summary.auto_fixable == summary.total_findings` → run the recommended_command, then re-run `<tool> doctor --json` and report.
- If any finding has `remediation.auto_fixable == false` → list those manual remediations to me; do NOT touch them.
- If exit code is 4 → list the precondition that failed; ask me before any --force.
- If exit code is 5 → wait 10 seconds, retry once; if still 5, surface to me.

Constraints:
- Never use `--force --yes` without my explicit "yes apply --force" reply.
- Never modify files outside `<tool> doctor capabilities --json::write_scopes`.
- Always read `--json` output, not human prose.

Acknowledge by replying with the first three lines of robot-docs you read.
```

---

## Recipe R-002 — Have an agent extend a doctor with a new FM

```
You are an implementer. Add a new failure mode to {{tool}}'s doctor.

Inputs:
- Symptom: {{paste cass evidence or bug-tracker excerpt}}
- Severity: P{{0|1|2|3}}
- Subsystem: {{state_files | configs | schemas | ...}}

Steps (do them IN ORDER; pause for review at each *):

1. Compute fm_id via `python3 {{skill}}/scripts/compute-fm-id.py --subsystem {{subsystem}} --symptom "{{slug}}"`.

2. Add to `{{workspace}}/analysis/failure_modes/{{subsystem}}.md` the new FM block per `{{skill}}/assets/failure-mode-template.md`. *

3. Write a Repair Spec at `{{workspace}}/analysis/repair_specs/{{fm_id}}.md` per `{{skill}}/assets/repair-spec-template.md`. Run `python3 {{skill}}/scripts/validate-spec.py {{workspace}}/analysis/repair_specs/{{fm_id}}.md` against it. *

4. Implement the detector (PURE — no mutate() calls) in `<doctor-source>/detectors/{{fm_id}}.{{ext}}`.

5. Implement the fixer (every write through mutate()) in `<doctor-source>/fixers/{{fm_id}}.{{ext}}`. Read `{{skill}}/references/methodology/MUTATE-CHOKEPOINT.md` first.

6. Build the fixture at `tests/doctor_fixtures/{{fm_id}}/`:
   - `corrupt.sh` (deterministic; no $RANDOM, no $$, no `date`)
   - `assert.sh` (asserts post-fix state is healthy)
   - `README.md`

7. Run all Phase 5 verifiers from the target repo root, with the tool binary exported:
   - `export TOOL={{tool}}`
   - `bash {{skill}}/scripts/verify-undo.sh {{fm_id}}`
   - `bash {{skill}}/scripts/verify-idempotence.sh {{fm_id}}`
   - `bash {{skill}}/scripts/verify-crash-recovery.sh {{fm_id}}`
   - `bash {{skill}}/scripts/verify-concurrency.sh {{fm_id}}`
   - `bash {{skill}}/scripts/verify-metamorphic.sh {{fm_id}}`

   ALL FIVE must exit 0. If any fail, stop and report. *

8. Update `<tool> doctor capabilities --json` so the new FM is declared. Run `bash {{skill}}/scripts/verify-capabilities.sh {{tool}}` to confirm.

9. Commit with message: `doctor({{subsystem}}): {{fm_id}}: detect + fix + fixture (br-{{bead-id}})`.

Constraints:
- Per AGENTS.md no-delete: never delete existing files. Quarantine via Op::Rename if needed.
- Per AGENTS.md: no rm -rf, no git reset --hard, no destructive shell.
- Pre-commit per AGENTS.md: stage code AND .beads AND tests; commit together.

Confirm understanding by listing the 8 steps above with their pause-points marked.
```

---

## Recipe R-003 — Have an agent run a quarterly doctor pass

```
You are running a quarterly maintenance pass on {{tool}}'s doctor.

Read these first (in order):
1. `{{skill}}/references/methodology/OPS-RUNBOOK.md § Quarterly`
2. `{{workspace}}/HANDOFF.md` (from prior pass)
3. `{{skill}}/references/methodology/CASS-PLAYBOOK.md` (recipe 13: Quarterly trend mining)

Then run:

1. `cass search "{{tool}}" --robot --limit 50 --days 90` and analyze the results.
   - Group hits by KIND (SYMPTOM / MANUAL_FIX / ROOT_CAUSE / INCIDENT / WISH).
   - Identify any new recurring symptoms not in `{{workspace}}/analysis/failure_modes/`.

2. `<tool> doctor --json` against the user's typical workspace.
   - Compare against the prior pass's scorecard.
   - Run `python3 {{skill}}/scripts/diff-scorecards.py {{workspace}} {{prev}} {{curr}}`.

3. For each new FM identified in step 1:
   - Use Recipe R-002 to add it.

4. For any score regression > 50 pts:
   - Read `{{workspace}}/regression_alerts.md`.
   - If the regression is intentional, add an ACK.
   - If not, identify and revert the offending change.

5. Run the meta-doctor:
   `bash {{skill}}/scripts/validate-skill.sh {{skill}}`

6. Update `{{tool}}'s` CHANGELOG.md with the pass's outcome.

7. File HANDOFF.md for the next quarterly pass per `{{skill}}/assets/handoff-template.md`.

Estimated effort: 2-4 hours at Pair tier. Pause and report at each numbered step.
```

---

## Recipe R-004 — Have a fresh-context agent do Phase 7 fresh-eyes

```
You are a fresh-context reviewer for Phase 7. You have NO prior context about
{{tool}}'s doctor or its history. Read the current code as if you've never seen it.

Round 1 prompt (use VERBATIM):

"Reread the new doctor code with fresh eyes. Look for obvious bugs, races,
partial-write windows, unsafe `unwrap`/`expect`/panics on user paths, missing
backups, broken idempotence, or any place where exit codes lie about reality.
Carefully fix anything you uncover."

After your review:
1. List every issue you found, sorted by severity.
2. For each: file path : line number : issue.
3. Categorize: bug (incorrect behavior) / smell (code-quality concern) / clarification-needed.

Constraints:
- DO NOT modify code in this round; only report.
- DO NOT consult prior pass HANDOFF.md or CHANGELOG.md.
- DO NOT discuss with me before completing the review.

After your report, I'll dispatch a SEPARATE fresh-context agent for Round 2 with a different prompt. Each round is independent.
```

---

## Recipe R-005 — Have an agent triage a production incident

```
You are triaging a production incident with {{tool}}.

Steps (60 seconds each):

1. `<tool> doctor health` — record exit code and one-line output.

2. Based on health output, choose:
   - "ok ..." → not the doctor's problem; proceed to upstream investigation.
   - "findings ..." → run `<tool> doctor --robot-triage --json`; classify by P0/P1/P2/P3.
   - "unsafe ..." → read the structured `reason`; consult `{{skill}}/references/methodology/INCIDENT-RESPONSE.md § Tier 3`.
   - "concurrency ..." → another doctor active; INCIDENT-RESPONSE.md § Tier 2.

3. For P0 findings: surface to the user IMMEDIATELY. Do NOT auto-fix during incident response without explicit approval.

4. For P1+ findings WITH explicit approval:
   - Run `<tool> doctor --dry-run --fix --only fm-XXX` first.
   - Verify the planned mutations are bounded and within scope.
   - Then run `<tool> doctor --fix --only fm-XXX`.
   - Re-run health. Confirm.
   - On any unexpected exit code: revert via `<tool> doctor undo latest`.

5. After resolution, draft a Case Study entry per `{{skill}}/references/methodology/CASE-STUDIES.md`.

Constraints:
- Time-pressure does NOT relax safety. Ask before --fix.
- Document every command you run with the timestamp.
- Per AGENTS.md: never delete files; never run destructive shell.
```

---

## Recipe R-006 — Have an agent run a multi-model triangulation review

```
You are coordinating a multi-model review of {{patches}}.

Steps:

1. Invoke `/multi-model-triangulation` with:
   - Patches: {{paths}}
   - Question: "Does this preserve the kernel axioms? List any that may break."

2. Capture each model's response:
   - Claude (you): your independent reading.
   - Codex: invoke and capture.
   - Gemini: invoke and capture.

3. Compare the three responses:
   - Identical answers (consensus) → record as agreement.
   - Different answers (divergence) → quote each model's verbatim concern.

4. For each divergence that names a real bug:
   - File a P0/P1 bead via `br create`.
   - Cite all three model verbatims in the bead body.

5. For stylistic disagreements: note in the report; no bead.

6. Save report to `{{workspace}}/triangulation_{{phase}}_{{round}}.md`.

Constraints:
- Use models' verbatim words, not paraphrase.
- A consensus that you (Claude) disagree with: still record as model consensus, then add your dissenting note.

Confirm understanding by stating the three models' names and the question you'll triangulate on.
```

---

## Recipe R-007 — Have an agent migrate a legacy doctor

```
You are running a migration of {{tool}}'s legacy doctor to this methodology.

Read first:
1. `{{skill}}/references/methodology/MIGRATION-GUIDE.md` (full)
2. `{{skill}}/references/methodology/RFC.md` § Conformance checklist

Inventory phase:

1. Run `<tool> doctor --help` and capture the full output.
2. Run `<tool> doctor` (or its equivalent) on a healthy fixture; capture stdout, stderr, exit code.
3. Run on a known-broken fixture; capture stdout, stderr, exit code.
4. Snapshot all of the above to `{{workspace}}/baseline/`.
5. Hash every file under git in the target; re-hash after step 2 and step 3. Drift = the legacy doctor auto-mutates (= a critical migration concern).

Migration phase (do steps in order; pause after each):

For each axiom 0..16:
  - Map the legacy doctor's behavior to the axiom.
  - If axiom is NOT honored: file a bead at the relevant priority.

For each bead, choose the migration phase per MIGRATION-GUIDE.md (Phase A-J).

Constraints:
- Preserve legacy behavior as `<tool> doctor-legacy` during transition.
- Per AGENTS.md no-delete: never remove the legacy code; deprecate via flag.
- Per AGENTS.md: bump the major contract version on any breaking change.

After migration phase completes, run the conformance checklist from RFC.md § Appendix A. Report which boxes are checked.
```

---

## Recipe R-008 — Have an agent dogfood the meta-doctor on a foreign skill

```
You are dogfooding `{{skill}}/scripts/validate-skill.sh` against another skill.

Target skill: `{{path-to-other-skill}}`

Steps:

1. Read the target skill's SKILL.md to understand its structure.
2. Run: `bash {{skill}}/scripts/validate-skill.sh {{path-to-other-skill}}`
3. For each VIOLATION, classify:
   - Intentional design decision (target skill's choice; document but don't fix)
   - Real bug in target skill (file a bead in target skill's repo)
   - Real bug in our meta-doctor (file in our skill's repo)

4. Surface findings to the user.
5. Do NOT modify the target skill without explicit user approval.
6. Update {{skill}}/references/methodology/CASE-STUDIES.md with the dogfood result if it surfaces an interesting class of issue.

This is the recursive loop: our meta-doctor catches issues; we improve our methodology; the methodology catches more issues.
```

---

## Recipe R-009 — Have an agent generate a doctor's CHANGELOG entry

```
You are generating a CHANGELOG entry for {{tool}}'s doctor.

Steps:

1. Run `git log --oneline doctor-mode-pass-{{N-1}}..doctor-mode-pass-{{N}}`.
2. Group commits by:
   - Added (new fixers, new detectors, new flags)
   - Changed (modifications to existing surface)
   - Bug fixes (corrections to known regressions)
   - Deprecations
3. For each group, write 1-3 lines per commit citing the bead ID.
4. Bump version per `{{skill}}/references/methodology/VERSIONING.md`:
   - Minor for new fixers / new detectors.
   - Major for breaking contract changes.
5. Append to `{{tool}}/CHANGELOG.md` per `/changelog-md-workmanship` discipline.
6. If contract changed: document the migration in [VERSIONING.md] strategy A or B.

Constraints:
- Per AGENTS.md: don't delete prior CHANGELOG entries.
- Cite every commit + every bead.
```

---

## Recipe R-010 — Have an agent design a new Cookbook pattern

```
You are proposing Cookbook pattern N+1 for the doctor methodology.

Read first:
1. `{{skill}}/references/methodology/COOKBOOK.md` (full; understand the existing 15)
2. `{{skill}}/references/exemplars/exemplars.md` (the canonical exemplars)

Steps:

1. State the pattern:
   - Title (~5 words)
   - Examples (real CLIs that match)
   - Failure-mode classes specific to this pattern
   - Surface variations (flag changes / new subcommands)

2. Cite at least 2 /dp/ projects that would benefit.

3. For each existing pattern (1-15), explain how the new pattern differs:
   - Is this a strict superset of an existing pattern?
   - Is it orthogonal (combines additively)?
   - Is it a refinement of one we have?

4. If novel: propose adding to COOKBOOK.md with:
   - A new "## Pattern N+1" section
   - A new row in the SKILL.md cookbook table
   - A new recipe in `{{skill}}/references/recipes/` if needed

5. If a refinement: extend the existing pattern's description; don't add a new pattern.

Constraints:
- Per AGENTS.md no-delete: never remove existing patterns; only add.
- The bar for new patterns is HIGH. Most "new" patterns are actually refinements of existing ones.
- If you propose a new pattern, justify why it can't be expressed as an existing pattern + adjustments.
```

---

## How these recipes differ from PROMPT-LIBRARY

- **PROMPT-LIBRARY** is for the USER → agent. Higher-level intent.
- **AGENT-PROMPT-RECIPES** is for the ORCHESTRATOR-AGENT → SUB-AGENT. Tighter, structural.

Both are calibrated. Both compose. Both are starting points, not verbatim laws.

---

## Adding a recipe

When you find yourself crafting a particular agent prompt repeatedly:

1. Allocate the next R-NNN.
2. State the role explicitly ("You are a ___").
3. Pin reading prerequisites (which files first).
4. List numbered steps; mark pause-points with `*`.
5. State constraints (especially AGENTS.md ones).

The library grows; ad-hoc prompts shrink.
