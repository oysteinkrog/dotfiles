# Skill Fallbacks

Inline fallbacks for every helper skill referenced from this skill. Use when the helper isn't installed and `jsm install` isn't available (no jsm, or no auth, or no subscription).

The pipeline degrades gracefully — every helper has a fallback. The fallback is usually a one-liner script or a paste-ready prompt.

---

## Skill build / validate (manual fallback)

Fallback: write the skill file manually using the structure of an existing skill in this repo (e.g., this one). The scaffold pattern is just a directory tree (`SKILL.md`, `references/`, `scripts/`, `assets/`, `subagents/`, `SELF-TEST.md`) plus boilerplate. To validate: read SKILL.md aloud (with the agent), check that frontmatter `name`, `description` are present, that referenced files exist (`ls subagents/ scripts/ assets/ references/`), that `SELF-TEST.md` runs.

## `/operationalizing-expertise` (corpus / kernel / operators)

Fallback: this skill already operationalizes; the `OPERATORS.md` and `SCORING-RUBRIC.md` are the operationalized form.

## `/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools`

Fallback: use the 10-dim rubric in `references/rubric/SCORING-RUBRIC.md` as the grading rubric. Note the substitution in `agent_ergo_grade.md`.

## `/codebase-archaeology`

Fallback: the `subagents/archaeologist.md` prompt is a self-contained archaeology procedure. Just dispatch it.

## `/codebase-report`

Fallback: skip the report — Phase 3's synthesizer produces the equivalent narrative chapters in `playbook.md`.

## `/multi-pass-bug-hunting`

Fallback: Phase 7 fresh-eyes IS the multi-pass bug hunting loop, calibrated.

## `/multi-model-triangulation`

Fallback: peer-claude triangulation (two Claude subagents). Note in the workspace that the `multi-model` claim degraded.

## `/ubs`

Fallback: skip UBS in Phase 7. Note in `fresh_eyes_round_<N>.md` that UBS wasn't run. The lint/typecheck/test suite still runs.

## `/dcg`

Fallback: not strictly needed — `validate-doctor.sh` enforces the same rules locally for the doctor module.

## `/agent-mail`

Fallback: serial Phase 4 (no concurrent implementers; one agent does each subsystem in order). Loses parallelism but preserves correctness.

## `/beads-br`, `/beads-bv`

Fallback: track bead-equivalents in `<workspace>/beads_pending.md` (a Markdown checklist). The implementer reads it; closes via TaskUpdate or strikethrough.

## `/cass`

Fallback: skip CASS mining (Phase 0). Phase 1 mines bug tracker + git log + AGENTS.md. CASS adds the most leverage but is not strictly required.

## `/idea-wizard`

Fallback: Phase 10 idea-generator dispatches a generic idea-generation prompt without the wizard. Lower yield but still functional.

## `/testing-fuzzing`, `/testing-metamorphic`, `/testing-conformance-harnesses`, `/testing-golden-artifacts`, `/testing-real-service-e2e-no-mocks`

Fallback: the five built-in Phase 5 tests (verify-undo, verify-idempotence, verify-crash-recovery, verify-concurrency, verify-metamorphic) cover the core safety surface. The testing-* skills are bonus rounds; skip without breaking the gate.

## `/cc-hooks`

Fallback: skip pre-commit hook installation. CI still runs `<tool> doctor health` per the `gh-actions` reference.

## `/gh-actions`

Fallback: write the workflow file by hand using the snippet in `subagents/integration-wirer.md`. Only ~30 lines of YAML.

## `/gh-cli`

Fallback: shell `gh issue list --json number,title,state,labels --limit 200` directly. The `/gh-cli` skill is mostly a wrapper.

---

## Bootstrap detail

If `jsm` isn't installed:

```bash
# Linux/macOS:
curl -fsSL https://jeffreys-skills.md/install.sh | bash
# Then:
jsm login   # Browser OAuth — requires a paid jeffreys-skills.md subscription
```

For headless OAuth (e.g., a server with no browser):

```bash
jsm login --device-code
# Open the URL in any browser; enter the code; authentication completes server-side.
```

If the subscription isn't paid, every helper has a fallback above and the pipeline still completes.

---

## When ALL helper skills are missing

Solo tier with peer-claude triangulation works fine using only the bash/python scripts shipped with this skill. The full output is reduced (no CASS findings, no `--ubs` clean), but the contract is preserved: `mutate()` chokepoint, backups, undo, scorecard, fixtures, fresh-eyes rounds.

Note in `<workspace>/HANDOFF.md` which fallbacks were used so the next pass can re-mine with the helpers when they're available.
