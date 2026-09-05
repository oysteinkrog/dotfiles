# Operating Modes

The phase loop is the same across modes; the **stop conditions and required artifacts** differ.

| Mode | Trigger | Phases run | Required outputs | Stop condition |
|------|---------|------------|------------------|----------------|
| `add` | No existing `doctor`/`health`/`verify`/`repair`/`check`/`diagnose`/`fix` subcommand detected | 0 → 10 | full skill output: `<tool> doctor` exists with all subcommands; `tests/doctor_fixtures/` populated; scorecard ≥ 700 aggregate; HANDOFF.md | Two clean fresh-eyes passes + every fixture round-trips |
| `upgrade` | Existing diagnostic surface detected | 0 → 10 (with baseline snapshot) | `baseline/` snapshot; uplift_diff.md vs baseline; no FM regressed > 50 pts; existing flags preserved or deprecated through warning | Two clean passes + baseline regression check |
| `audit-only` | User wants scoring with no code changes | 0 → 3, 6 (scoring only) | `scorecard.{md,json}`, `heatmap.svg`, `recommendations.jsonl`, `playbook.md` | Phase 6 scorecard committed |
| `re-score-only` | Resumed; rescore against current target HEAD | 0, 6 | `scorecard_pass_<N+1>.{md,json}`, `uplift_diff.md`, `regression_alerts.md` | Phase 6 done |
| `single-failure-mode-rescore` | Targeted; one detector/fixer changed | 0, 1 (FM only), 6 (FM only) | one row in `failure_mode_scores.jsonl`; rest unchanged | Phase 6 row committed |
| `absorb-playbook` | Convert manual playbook skill to automated doctor | 0 → 10, with Phase 1 sourcing FMs from the playbook | full skill output + the source playbook skill demoted to fallback | Two clean passes + source skill updated |

---

## `add` mode

### Triggers

- `scripts/discover-cli.sh --probe-doctor` finds NO existing subcommand named `doctor`, `health`, `verify`, `repair`, `check`, `diagnose`, or `fix`.
- The user explicitly says "add a doctor command".

### Distinct behaviors vs `upgrade`

- No `baseline/` snapshot.
- Phase 1's archaeology can't be cross-referenced against an existing detector list — failure modes are mined from bug tracker + git log + cass + AGENTS.md only.
- Phase 6's scorecard establishes the baseline (all FMs at 0 for "automation_degree" except those that the project happens to handle through other means).

### Required artifacts

- `<tool> doctor` (default = diagnose)
- `<tool> doctor --fix`
- `<tool> doctor --dry-run --fix`
- `<tool> doctor undo <run-id>` and `undo latest`
- `<tool> doctor --explain <finding-id>`
- `<tool> doctor capabilities --json`
- `<tool> doctor health`
- `<tool> doctor robot-docs`
- `<tool> doctor --robot-triage`
- `<tool> doctor ls`
- `<tool> doctor gc --before <date> --yes`
- `tests/doctor_fixtures/` populated for every failure mode
- `scripts/scorecard.py` integrated; `<workspace>/scorecard.md` written
- Pre-commit + CI wiring (Phase 8)
- `HANDOFF.md` (Phase 10)

### Stop condition

ALL of:
- Phase 7 ran clean two consecutive rounds.
- Every fixture in `tests/doctor_fixtures/run_all.sh` round-trips.
- `scripts/validate-doctor.sh` exits 0.
- Aggregate scorecard ≥ 700.
- Phase 10 cold-prober found ≤ 3 P1+ issues; the polish pass addressed them.

---

## `upgrade` mode

### Triggers

- `discover-cli.sh --probe-doctor` finds an existing subcommand.
- The user explicitly says "upgrade `<tool>`'s doctor".

### Distinct behaviors

- Phase 0 includes `subagents/baseline-snapshotter.md`. The baseline is **inviolate** — Phase 6 compares against it; any score regression > 50 pts is a hard stop.
- Phase 1 mines existing detectors and fixers as a starting point; the synthesizer in Phase 3 reconciles them with the new ones.
- Phase 4 implementers MUST preserve every existing flag/subcommand unless the user explicitly approves a deprecation. Deprecations emit a warning to stderr ("`--repair` is deprecated; use `--fix`") and forward to the new spelling. (Per AGENTS.md, no backwards-compat shims long-term — once the user approves, remove the old flag.)
- Phase 7's fresh-eyes pays special attention to compatibility with downstream callers: existing CI scripts, pre-commit hooks, agent prompts that already reference the old surface.

### Required artifacts

All of `add` mode + `<workspace>/baseline/`, `uplift_diff.md`, `regression_alerts.md`.

### Stop condition

ALL of `add` mode + `scripts/diff-scorecards.py <workspace> baseline <N>` reports no regression > 50 points.

---

## `audit-only` mode

### Triggers

- User wants a scorecard without code changes ("just tell me how good the doctor is").

### Phases that run

- Phase 0 (bootstrap, optional baseline if upgrade-flavored audit).
- Phase 1 (failure-mode inventory).
- Phase 6 (scorecard, but NO scorecard generator integration in the target — write the generator into the workspace only).

### Phases skipped

- 2 (no repair specs needed for read-only audit).
- 4 (no implementation).
- 5 (no fixers to harness).
- 7 (no code to fresh-eye).
- 8 (no integration).
- 9 (no fixtures).
- 10 (no UX pass).

### Required artifacts

- `<workspace>/scorecard.{md,json}` with per-FM × per-dimension scores against the **current** binary.
- `<workspace>/heatmap.svg`.
- `<workspace>/recommendations.jsonl` ranked by priority.
- `<workspace>/playbook.md` summarizing what an upgrade pass would do.

### Stop condition

Scorecard, heatmap, recommendations, and playbook committed; no code changes in the target.

---

## `re-score-only` mode

### Triggers

- A previous pass exists (`<workspace>/manifest.json::pass >= 1`).
- User wants to know the score against the current `target_sha` without running a new pass.

### Phases that run

- Phase 0 (bootstrap; reads existing manifest).
- Phase 6 (scorecard only).

### Required artifacts

- `<workspace>/scorecard_pass_<N+1>.{md,json}`.
- `<workspace>/uplift_diff.md`.
- `<workspace>/regression_alerts.md`.

### Stop condition

Phase 6 row committed. If `regression_alerts.md` is non-empty, recommend the user re-run with mode `add`/`upgrade` to address.

---

## `single-failure-mode-rescore` mode

### Triggers

- User changed exactly one detector/fixer (e.g., "I just rewrote `fm-jsonl-tombstone-drift`'s fixer; tell me the new score").

### Phases that run

- Phase 0 (bootstrap).
- Phase 1 — only the FM in question (re-mine).
- Phase 6 — score only that FM.

### Required artifacts

- One new line appended to `<workspace>/failure_mode_scores.jsonl` for that FM.
- `<workspace>/scorecard_pass_<N+1>.md` includes only that row's delta.

### Stop condition

That FM's score is ≥ its previous value (no regression). If regressed > 50 pts, hard stop.

---

## `absorb-playbook` mode

### Triggers

- User says "absorb `<playbook-skill>` into `<tool> doctor`."
- Common targets: `fixing-beads-problems` → `br doctor`, `system-performance-remediation` → `pt doctor` (if a `pt` doctor existed), `dcg`'s help-text playbook → `dcg doctor`.

### Distinct behaviors

- Phase 1's archaeology has an additional input: parse the source playbook skill's `SKILL.md`, extract every named "step" / "command" / "fix recipe" as a candidate failure mode. Each parsed step gets a Repair Spec in Phase 2.
- Phase 8 includes updating the source playbook skill's `SKILL.md` to demote the manual playbook: "First, run `<tool> doctor --fix`. If that doesn't help, the steps below remain as a fallback." Per AGENTS.md no-delete, the original steps stay, just relabeled.
- Phase 10 cold-prober uses the playbook skill's trigger phrases verbatim ("doctor / show fails", "DB and JSONL both changed") and asserts the new doctor handles them without escalation.

### Required artifacts

All of `add`/`upgrade` mode + an updated `<source-playbook-skill>/SKILL.md` whose first recommendation is `<tool> doctor --fix`.

### Stop condition

All of `add` mode + the source playbook skill's update is committed (in this skill repo, via a separate commit on the same branch).

---

## Auto-detection (`scripts/discover-cli.sh`)

```bash
./scripts/discover-cli.sh <target> --probe-doctor > <workspace>/phase0_cli.json
```

`--probe-doctor` is REQUIRED for the upgrade-mode heuristic — without it, the existing-doctor probe is skipped and the script can't classify between `upgrade` and `add` based on the target's existing subcommands.

Heuristics:

- If `<workspace>/manifest.json` exists, default mode = `re-score-only` (or the user-supplied override).
- Else if `<target>` has a `doctor` / `health` / `verify` / `repair` / `check` / `diagnose` / `fix` subcommand (probed via recursive `--help` walk), default mode = `upgrade`.
- Else default mode = `add`.

The detector posts its reasoning to stderr; the user can override at intake.
