# First 30 Minutes — Onboarding Runbook

You've decided to apply the skill to a project. This file is the minute-by-minute walkthrough of the first 30 minutes. It assumes:

- The project is on this machine (not a fresh clone).
- You have `cass`, `br`, `bv`, `gh` installed (or you're OK with reduced fidelity).
- You have NO prior context on this skill (or it's been 6+ months and you're refreshing).

Time-box each section. If you're going over budget, surface it; the methodology can adapt.

---

## Minute 0–2: Decide if this is the right skill

Read [assets/skill-card.md](../../assets/skill-card.md). It's one page. By minute 2 you should know:
- What the skill produces (a `<tool> doctor` subcommand + ongoing scoring).
- What the skill costs (1–8 hours wall time depending on tier).
- What the skill won't do (delete files, run destructive shell, push to main).

If the answer is "this isn't what I need", stop here. If it is, continue.

---

## Minute 2–5: Confirm your project's shape

Run:

```bash
cd /path/to/your/project
ls -la
```

Look for:
- `Cargo.toml` / `go.mod` / `pyproject.toml` / `package.json` / `Gemfile` / `mix.exs` → language identified.
- `cmd/*/` (Go) or `crates/*/` (Rust) or `bin/*` (TS) → multi-binary toolkit.
- `wrangler.toml` / `vercel.json` / `.gh/` → distributed CLI.
- A `Dockerfile` running long-lived → daemon-pattern.
- An existing `<tool> doctor` / `<tool> health` / `<tool> verify` subcommand → upgrade mode.

Match against [COOKBOOK.md](COOKBOOK.md) patterns 1–15. Most projects match 1–3 patterns simultaneously.

If you're not sure, run:

```bash
# Set SKILL to wherever this skill is checked out — typically one of:
#   ~/.claude/skills/world-class-doctor-mode-for-cli-tools  (system-wide)
#   <repo>/.claude/skills/world-class-doctor-mode-for-cli-tools  (project-local)
SKILL="${SKILL:-$HOME/.claude/skills/world-class-doctor-mode-for-cli-tools}"
bash "$SKILL/scripts/discover-cli.sh" . --probe-doctor
```

Returns a JSON with binaries, language, build system, existing doctor.

---

## Minute 5–10: Fill in the intake worksheet

Open [assets/intake-worksheet.md](../../assets/intake-worksheet.md). Fill in:

```
project_name: <real name>
target_repo: $(pwd)
target_sha: $(git rev-parse HEAD)
default_branch: $(git symbolic-ref --short HEAD)
binaries: <list>
existing_doctor_subcommand: <doctor | health | verify | check | none>
mode: <add | upgrade | audit-only | absorb-playbook>
operating_location: worktree
patterns: <comma-separated cookbook pattern numbers>
```

Skip the parts that don't yet apply (subsystems, FMs, must-not-touch — those come in later phases).

---

## Minute 10–12: Mine cass for the most-recent failures

```bash
cass search "<your-tool>" --robot --limit 30 --days 30 \
    | jq -r '.hits[] | select(.kind=="MANUAL_FIX" or .kind=="SYMPTOM") | .snippet'
```

Read the top 10. You're looking for "I had to manually fix X" patterns. Note the symptoms; they're your seed FM list.

If `cass` returns 0 hits, that's data — the project is either new or its failures don't surface in your sessions. Skip cass-mining; rely on bug-tracker + git log instead.

---

## Minute 12–15: Decide tier

| Project size | Tier | Wall time | Triangulation |
|--------------|------|-----------|---------------|
| < 5 FMs, simple | Solo | 1-2 h | none |
| 5-30 FMs, typical | Pair | 2-4 h | peer-claude |
| 30-60 FMs, mature | Squad | 4-8 h | multi-model |
| 60+ FMs, multi-binary | Swarm | 8-16 h | multi-model |

Pick a tier you can finish today (or this week, depending on appetite). Solo and Pair are achievable in a single session; Squad and Swarm need multiple agents and possibly NTM orchestration.

---

## Minute 15–18: Set up the workspace

```bash
# Set SKILL to wherever this skill is checked out — typically one of:
#   ~/.claude/skills/world-class-doctor-mode-for-cli-tools  (system-wide)
#   <repo>/.claude/skills/world-class-doctor-mode-for-cli-tools  (project-local)
SKILL="${SKILL:-$HOME/.claude/skills/world-class-doctor-mode-for-cli-tools}"
WORKSPACE="$(pwd)__doctor_workspace"

# Bootstrap.
bash "$SKILL/scripts/check-skills.sh" "$WORKSPACE"
bash "$SKILL/scripts/discover-cli.sh" . --probe-doctor > "$WORKSPACE/phase0_cli.json"
bash "$SKILL/scripts/scaffold-workspace.sh" "$WORKSPACE" "$(pwd)" --worktree --pass=1
```

You now have:
- `$WORKSPACE/phase0_skill_inventory.json` (which helper skills are installed).
- `$WORKSPACE/phase0_cli.json` (project shape).
- `$WORKSPACE/worktree/` (a git worktree on `doctor-mode-pass-1` branch).
- `$WORKSPACE/{analysis,baseline,agent_simulations,recommendations}/`.

---

## Minute 18–22: Create the manifest

Copy [assets/manifest-template.json](../../assets/manifest-template.json) to `$WORKSPACE/manifest.json`. Edit:

```json
{
  "schema_version": "1.0",
  "run_started_at": "<now-ISO8601>",
  "target_repo": "<absolute path>",
  "target_sha": "<git rev-parse HEAD>",
  "binary_names": ["<your-tool>"],
  "language": "<from phase0_cli.json>",
  "build_system": "<from phase0_cli.json>",
  "mode": "add|upgrade",
  "pass": 1,
  "worktree_path": "<workspace>/worktree",
  "branch_name": "doctor-mode-pass-1",
  "triangulation_appetite": "peer-claude",
  "online_appetite": "offline-only",
  "cass_mining_appetite": "quick",
  "must_not_touch": [],
  "phases_completed": []
}
```

---

## Minute 22–25: Send the kickoff prompt

Open [references/methodology/KICKOFF-PROMPTS.md](KICKOFF-PROMPTS.md). Find the verbatim kickoff prompt for your mode.

Send it to the lead agent (you, in the next prompt OR a subagent you dispatch). The prompt sets up shared context.

---

## Minute 25–30: Start Phase 1

The kickoff lands you in Phase 1: archaeology. Per [PHASES.md § Phase 1](PHASES.md):

```bash
# Phase 1 dispatches one archaeologist per subsystem.
# At Solo tier: you do it serially, one subsystem at a time.
# At Pair+ tier: parallel via Agent Mail reservations.
```

The first subsystem to mine is typically `state_files` (most projects' biggest FM source). Use the verbatim archaeologist prompt from [AGENT-PROMPTS.md § archaeologist](AGENT-PROMPTS.md).

By minute 30, you should have:
- A first draft of `$WORKSPACE/analysis/failure_modes/state_files.md` with 3+ FMs.
- An understanding of what subsystems remain (configs, schemas, caches, ...).
- Confidence that the methodology is tractable for this project.

---

## Time-box check

| At minute | Expected state |
|-----------|----------------|
| 5 | Decided pattern + read skill-card |
| 10 | Worksheet filled |
| 18 | Workspace scaffolded |
| 25 | Kickoff prompt sent |
| 30 | Phase 1 archaeology started, ≥ 3 FMs in state_files.md |

If you're behind:
- At minute 30 with < 3 FMs: the project may need broader subsystem partition. Re-read [recipes/failure_mode_catalog.md](../recipes/failure_mode_catalog.md) and try a different subsystem.
- At minute 30 with no workspace: the bootstrap scripts may have errored. Check `$WORKSPACE/phase0_skill_inventory.json` exists.
- At minute 30 with no kickoff sent: the mode may be ambiguous. Default to `add` if no existing doctor; `upgrade` if any.

---

## What "done with first 30" means

- ✅ You know the project's pattern.
- ✅ You know your tier.
- ✅ Workspace is scaffolded.
- ✅ Phase 1 is started.
- ✅ You've read enough of the methodology to keep going.

What you DON'T need yet:
- A complete FM inventory (that's the rest of Phase 1).
- Repair specs (that's Phase 2).
- Code (that's Phase 4).
- Scorecard (that's Phase 6).

---

## After minute 30

Continue with Phases 1-10 per [PHASES.md](PHASES.md). The skill is paced for 1-16 hours total (per tier). Take breaks between phases; the workspace is durable.

When you resume, run `bv --robot-triage --label=doctor-pass-1` to find your next bead. Run `cat $WORKSPACE/manifest.json | jq .phases_completed` to confirm where you left off.

---

## When to stop and ask

- The project's pattern doesn't match any of the 15 cookbook patterns. → Read [COOKBOOK.md](COOKBOOK.md)'s "How to choose" section; if still no match, propose a new pattern in beads at priority 3.
- You're at minute 30 with no FMs at all. → The project may be too small for this skill. Re-read the [skill-card.md](../../assets/skill-card.md) "When NOT to use" section.
- Cass returns nothing useful. → Skip cass; rely on bug tracker + git log + first principles.
- The agent reading this file isn't sure where to start. → Read [SKILL.md](../../SKILL.md)'s "Quick start" pointer at the top.

---

## After your first complete pass

Read [GROWTH-LADDER.md](GROWTH-LADDER.md) to plan pass-2's target. Read [OPS-RUNBOOK.md](OPS-RUNBOOK.md) for the cadence after that.

The first pass is an investment; each subsequent pass amortizes it.
