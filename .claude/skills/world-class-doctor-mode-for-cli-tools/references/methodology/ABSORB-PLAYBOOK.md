# Absorbing Manual Playbook Skills

`absorb-playbook` mode converts a manual repair playbook skill (e.g., `fixing-beads-problems`, `system-performance-remediation`) into automated `<tool> doctor --fix` capabilities. The original playbook is not deleted (per AGENTS.md no-delete); it's demoted to a fallback for unusual cases doctor doesn't yet handle.

---

## Source playbooks worth absorbing

In this skill repo, candidates include:

- **`fixing-beads-problems`** → `br doctor --fix`
  Manual recovery for malformed beads DB / JSONL drift. Section "60-Second Workflow" enumerates 6 steps that map directly to detectors + fixers.

- **`system-performance-remediation`** → potentially a new `pt doctor` (the `process-triage` `pt` wrapper already has agent-friendly modes).

- **`dcg`** (the destructive-command guard) → `dcg doctor` would scan project hook configs and validate the dcg patterns are still up to date.

- **fleet-provisioning playbook** → a `acfs doctor --fix` (where `acfs` is the agentic-coding-flywheel-setup CLI).

- **`path-rationalization`** → `pr doctor --fix` (an installer-style doctor for shell PATH state).

---

## Procedure (how the absorb-playbook mode runs)

### Phase 1 (with playbook input)

The archaeologist receives an additional input: the source playbook's `SKILL.md`. The agent parses the skill for:

- Named "step" / "command" / "fix recipe" sections.
- "Anti-patterns" sections — these become refusal-with-redirect findings.
- "Escalate when" sections — these become exit-4 paths.

Each parsed step is a candidate failure mode. The archaeologist:

1. Extracts the symptom (typically the section heading).
2. Extracts the root-cause (the "Why" or "Diagnosis" prose).
3. Extracts the manual fix command sequence.
4. Files an FM with `currently_auto_detected: no, currently_auto_fixed: no` and the manual fix in the `prior_incidents` field.

### Phase 2 (with playbook in mind)

The repair-spec-author re-uses the manual fix as the **fixer's algorithmic shape**. The challenge: convert "shell + jq + sqlite3" pipelines into language-native code that goes through `mutate()`.

For each step in the manual fix:
- A shell command that READS state → maps to a detector.
- A shell command that WRITES state → maps to a `mutate(path, op)` call inside a fixer.
- A `mv X Y` for quarantine → maps to `Op::Rename`.

The `fixing-beads-problems` skill's "Recovery Loop" (10 numbered steps) is a good worked example. Each numbered step becomes one `mutate()` call in `br doctor --fix`'s fixer for the relevant FM.

### Phase 8 (the demote step)

After Phase 4–7 land the new fixers, Phase 8's `subagents/integration-wirer.md` updates the source playbook's `SKILL.md`:

```markdown
> **First, run `<tool> doctor --fix`.** It absorbs most of this playbook's steps.
> If `<tool> doctor --fix` doesn't help, the manual playbook below remains as
> a fallback for unusual cases.

# Original playbook content (preserved per AGENTS.md no-delete) ...
```

The original content stays. The new top-of-file recommendation makes the skill a fallback rather than the primary path. The skill's frontmatter description is updated to mention the doctor.

### Phase 9 (fixtures map to playbook scenarios)

Each fixture in `tests/doctor_fixtures/` corresponds to one scenario the manual playbook handled. The fixture's `corrupt.sh` reproduces the broken state the playbook addresses; the round-trip test asserts the new doctor handles it without invoking the manual steps.

### Phase 10 (cold prober reads the OLD playbook)

The cold-agent-prober's canonical_tasks.md is built from the source playbook's "Start Here" / "60-Second Workflow" / "Exact Prompts" sections. The prober attempts each task using ONLY `<tool> doctor` and `<tool> doctor robot-docs`. If the prober gets stuck on a task the playbook handles, that's a Phase 4 gap to fix in the next pass.

---

## Worked example: `fixing-beads-problems` → `br doctor`

### Step 1 in the playbook: "Snapshot `.beads/` into a timestamped recovery directory."

Maps to:
- **Detector**: none (this is the user's recommended pre-action; it's not a "broken state").
- **Fixer**: NOT a doctor fixer. This is what `<tool> doctor` ITSELF does as part of its standard run-artifact emission — `mutate()` writes verbatim backups to `.doctor/runs/<run-id>/backups/` automatically.
- **Lift**: the user no longer needs to manually snapshot; doctor does it.

### Step 2: "Confirm the configured DB path and whether the canonical filename is wrong."

Maps to FM `fm-state-files-db-path-mismatch`:
- **Detector**: read `<tool> config get db --json`. If path differs from `.beads/beads.db`, emit finding.
- **Fixer**: rewrite the config via `mutate(<config-path>, WriteFile)` to point at the canonical `.beads/beads.db`. Backup first.

### Step 3: "Check `br doctor`, `br sync --status`, and `br show <known-issue-id>`."

Maps to no new FM — this is exactly what `<tool> doctor` does under `--quick`.

### Step 4: "If the DB still opens read-only, extract the dirty issue set from `dirty_issues`."

Maps to FM `fm-state-files-db-readonly-with-dirty-issues`:
- **Detector**: open the DB read-only; check for `dirty_issues` table; if non-empty, emit finding.
- **Fixer**: extract `dirty_issues` rows; merge them into JSONL (with conflict resolution per repair spec); rebuild DB from harmonized JSONL — all writes through `mutate()`. Backup the DB family + JSONL first.

### Step 5: "Reapply or document valuable DB-only changes."

Maps to FM `fm-state-files-db-only-changes-not-in-jsonl`:
- **Detector**: diff DB-derived issue states against JSONL-derived issue states; emit finding for each divergence.
- **Fixer**: reapply DB-only state into JSONL via `mutate()`. Conflict resolution rules in the repair spec.

### Step 6: "Rebuild into an isolated temp DB with `--no-auto-import --no-auto-flush`."

Maps to FM `fm-state-files-db-rebuild-staging`:
- **Detector**: detect when a rebuild is needed (e.g., `pragma integrity_check` fails).
- **Fixer**: rebuild into a temp DB, verify, then `mutate(.beads/beads.db, Rename)` from temp to canonical. Backup the original DB family first (so undo restores).

### Result

After Phase 4 lands, `br doctor --fix` automates Steps 1–6 of the manual playbook. Steps 7–10 (verification + promotion) are done by `<tool> doctor`'s normal run-artifact emission. The user's typical interaction becomes:

```bash
br doctor                # See findings.
br doctor --fix          # Apply repairs with backups.
br doctor undo latest    # If anything went sideways.
```

The original `fixing-beads-problems` skill stays in the repo, demoted to fallback for the rare cases doctor doesn't handle.
