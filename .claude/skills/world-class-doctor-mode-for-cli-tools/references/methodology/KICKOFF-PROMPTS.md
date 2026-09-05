# Kickoff Prompts (verbatim)

After the user answers the intake, send the matching kickoff prompt below verbatim. The prompt names the mode, restates the inputs, and queues Phase 0.

---

## Mode `add`

```
Confirmed:
- Target: {{target_repo}} (sha={{target_sha}}, default branch={{default_branch}})
- Binaries: {{binaries}}
- Mode: add (no existing doctor surface detected)
- Operating location: {{worktree_or_in_place}} (branch: {{branch}})
- Triangulation: {{triangulation_appetite}}
- CASS: {{cass_appetite}}
- Online: {{online_appetite}}

Starting Phase 0: bootstrap + cass mining.

Reading: SKILL.md, references/methodology/PHASES.md, references/methodology/MUTATE-CHOKEPOINT.md,
references/recipes/{{language}}.md, references/exemplars/exemplars.md.

I'll dispatch:
- subagents/cass-miner.md (Phase 0 — mining your prior agent sessions)
- scripts/check-skills.sh + scripts/discover-cli.sh + scripts/scaffold-workspace.sh

Phase 1 starts after Phase 0 artifacts are in {{workspace}}/.

I won't push to main, won't delete files, won't run destructive shell. Per AGENTS.md.
```

---

## Mode `upgrade`

```
Confirmed:
- Target: {{target_repo}} (sha={{target_sha}}, default branch={{default_branch}})
- Binaries: {{binaries}}
- Mode: upgrade (existing diagnostic subcommand detected: {{existing_doctor_subcommand}})
- Operating location: {{worktree_or_in_place}} (branch: {{branch}})
- Triangulation: {{triangulation_appetite}}
- CASS: {{cass_appetite}}
- Online: {{online_appetite}}
- Must-not-touch: {{must_not_touch_list}}

Starting Phase 0: bootstrap + baseline snapshot + cass mining.

Phase 0 includes:
- subagents/baseline-snapshotter.md — captures the existing doctor's behavior into baseline/.
  CRITICAL: I'll detect any auto-mutation by the existing doctor (running it should NOT
  change any file). If it does, that's the highest-priority finding for Phase 4.
- subagents/cass-miner.md — mining prior agent sessions for failure-mode evidence.
- scripts/check-skills.sh + scripts/discover-cli.sh + scripts/scaffold-workspace.sh.

Phase 1 starts after Phase 0 artifacts are in {{workspace}}/.

I'll preserve every existing flag/subcommand unless you explicitly approve a deprecation.
Per AGENTS.md: no destructive shell, no file deletion, no backwards-compat shims long-term.
```

---

## Mode `audit-only`

```
Confirmed:
- Target: {{target_repo}}
- Mode: audit-only (no code changes will be made)
- Output: {{workspace}}/scorecard.{md,json}, heatmap.svg, recommendations.jsonl, playbook.md

I'll run Phases 0, 1, and 6 (scoring only). No worktree, no commits, no Phase 4 implementation.

Starting Phase 0.
```

---

## Mode `re-score-only`

```
Confirmed:
- Target: {{target_repo}} (sha={{target_sha}})
- Mode: re-score-only
- Previous pass: {{previous_pass_n}} (aggregate: {{previous_aggregate_score}})

I'll re-run Phase 6 against the current target HEAD using the existing
scoring methodology. Output: scorecard_pass_{{N+1}}.{md,json}, uplift_diff.md,
regression_alerts.md.

If any FM regressed > 50 pts, I'll hard-stop and surface the regression for
your review before continuing.
```

---

## Mode `single-failure-mode-rescore`

```
Confirmed:
- Target: {{target_repo}}
- Mode: single-failure-mode-rescore
- Failure mode: {{fm_id}}

I'll re-mine evidence for {{fm_id}} (Phase 1 scoped) and re-score it
(Phase 6 scoped). One row appended to failure_mode_scores.jsonl; rest unchanged.

If the FM regressed > 50 pts vs. previous pass, hard stop.
```

---

## Mode `absorb-playbook`

```
Confirmed:
- Target: {{target_repo}}
- Mode: absorb-playbook
- Source playbook skill: {{source_playbook_path}}
- Operating location: {{worktree_or_in_place}} (branch: {{branch}})

I'll convert each named step / command / fix recipe in
{{source_playbook_path}}/SKILL.md into a Repair Spec, then run the standard
phase loop.

Phase 8 will update the source playbook's SKILL.md so its first
recommendation is `<tool> doctor --fix`. Per AGENTS.md no-delete: existing
playbook content stays as a fallback; I'll add the new top-level recommendation
without removing the prior steps. Demote, don't delete.

Starting Phase 0.
```
