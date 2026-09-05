# Operating Modes

**Source axiom:** Axiom 21. The skill ships 9 operating modes that compose orthogonally with the 5 orchestration tiers (Solo / Pair / Squad / Swarm / Council) and the 5 size tiers (T1–T5). A mode declares phases-run, required artifacts, stop conditions, forbidden actions, and the mode-handoff template.

---

## Decision tree — which mode?

```
First time on this repo? ────────── YES ──→ full
                                 ──── NO ──→ continue

Did the previous run halt mid-phase? ── YES ──→ resume (same mode)
                                    ──── NO ──→ continue

Want to see the plan only, no actions? ── YES ──→ triage-only
                                       ──── NO ──→ continue

Phase 2.5 surfaced a real secret? ───── YES ──→ harden-secret-leak  (escalation; auto-suggested)
                                    ─── NO ──→ continue

Want to relocate files but not delete? ── YES ──→ move-only
                                       ──── NO ──→ continue

Want to delete junk but not relocate? ── YES ──→ delete-only
                                     ──── NO ──→ continue

Just want to add `.gitignore` patterns? ── YES ──→ gitignore-only
                                       ──── NO ──→ continue

Adding a new repo archetype to the skill? ── YES ──→ add-archetype-profile  (skill-extension)
                                          ── NO ──→ continue

Recovering from a previous bad cleanup? ── YES ──→ recover-from-bad-cleanup
                                        ─── NO ──→ continue

Re-running on a previously-cleaned repo? ── YES ──→ maintenance-review
                                         ─── NO ──→ continue

Multi-repo run across 2+ repos? ───────── YES ──→ batch (chain mode invocations)
                                        ──── NO ──→ default to `full`
```

---

## Mode catalogue

### 1. `full` (default)

| Field | Value |
|-------|-------|
| **When** | First-time cleanup; repo has 5+ candidates; user wants the complete sweep |
| **Phases run** | 0, 0.5, 1, 2, 2.5, 3, 4, 5, 6, 7, 8, 9, 10 (and 11 if user asks) |
| **Required artifacts** | All workspace files; complete bundle; recovery branch with cleanup commits |
| **Stop condition** | Phase 9 fresh-eyes ≥2 clean rounds AND Phase 10 handoff filed |
| **Forbidden actions** | Pushing the recovery branch; deleting the bundle; force-pushing; running `git filter-repo` (without `harden-secret-leak` escalation) |
| **Mode handoff** | "Full cleanup complete on `<repo>`. <N> commits on `<branch>`. Push command: `git push origin <branch>`" |

### 2. `triage-only`

| Field | Value |
|-------|-------|
| **When** | User wants the plan but isn't ready to commit time/risk to mutations |
| **Phases run** | 0, 0.5, 1, 2, 2.5, 3, 4, 5, then halt |
| **Required artifacts** | `triage_decision.md`, `move_plan.md`, `delete_plan.md`, `gitignore_plan.md`, bundle (still built — it's the audit trail) |
| **Stop condition** | Phase 5 user-facing decision table presented |
| **Forbidden actions** | Any `git mv` / `git rm` / `.gitignore` edit / Phase 6+ work |
| **Mode handoff** | "Triage complete on `<repo>`. Plan at `<workspace>/triage_decision.md`. Recommended next mode: `full` if you want to apply, `move-only` for safe relocations only, `harden-secret-leak` if Phase 2.5 found a real key" |

### 3. `move-only`

| Field | Value |
|-------|-------|
| **When** | User trusts the move plan but wants to defer deletes (e.g., review burn-in for 1 week before deletes) |
| **Phases run** | 0–6, then handoff |
| **Required artifacts** | `move_plan.md`, `apply_log.tsv`, `reference_rewrite_log.tsv`; recovery branch with move commits only |
| **Stop condition** | Phase 6 complete; gates green |
| **Forbidden actions** | Phase 7 `git rm`; Phase 8 `.gitignore` adds (for cleanups; informational additions OK) |
| **Mode handoff** | "Moves applied on `<branch>`. Run `delete-only` mode in 1 week to finalize, or run `full` from here to continue immediately" |

### 4. `delete-only`

| Field | Value |
|-------|-------|
| **When** | The repo has clear junk only (no plan-doc moves needed); user wants surgical deletes |
| **Phases run** | 0–4, 7, 8, 9, 10 (skip Phase 5 plan if obvious; skip Phase 6 entirely) |
| **Required artifacts** | `delete_plan.md`, `gitignore_plan.md`, `cleanup_authorization.txt`, `apply_log.tsv` |
| **Stop condition** | Phase 9 fresh-eyes ≥2 clean rounds |
| **Forbidden actions** | `git mv`; reference rewrites |
| **Mode handoff** | "Deletes applied on `<branch>`. <N> files removed; <M> .gitignore patterns added" |

### 5. `gitignore-only`

| Field | Value |
|-------|-------|
| **When** | User has already cleaned the working tree manually; just wants to formalize patterns |
| **Phases run** | 0, 1, 2, 5 (gitignore-plan only), 8, 10 |
| **Required artifacts** | `gitignore_plan.md` with SHADOWING-AUDIT, the new `.gitignore` |
| **Stop condition** | Phase 8 commit lands; `git check-ignore -v` confirms each pattern fires |
| **Forbidden actions** | Any `git rm`; any `git mv` |
| **Mode handoff** | "Gitignore patterns added: <list>. <K> tracked files were shadow-checked; <X> required `git rm --cached`" |

### 6. `harden-secret-leak` (escalation mode)

| Field | Value |
|-------|-------|
| **When** | Phase 2.5 found a real secret (filename + content fingerprint match). Auto-suggested by the skill |
| **Phases run** | INCIDENT-PLAYBOOK § Secret Leak — full 10-step flow |
| **Required artifacts** | `secret_findings.tsv` with resolution per row; mirror backup at `/tmp/<repo>-backup-<TS>.git`; `cleanup_authorization.txt` for the filter-repo run; `.githooks/pre-commit` installed; AGENTS.md updated |
| **Stop condition** | Origin verified clean (`git log origin/<branch> -- <secret-path>` empty); pre-commit hook smoke-tested |
| **Forbidden actions** | Any work outside the secret-leak flow until the user confirms rotation; `git push --force` (only `--force-with-lease`); deleting the mirror backup |
| **Mode handoff** | "Secret leak hardened on `<repo>`. Key rotated by user; history rewritten; pre-commit guard installed. Next mode: `full` to resume routine cleanup, or `maintenance-review` if this was the only issue" |

### 7. `recover-from-bad-cleanup`

| Field | Value |
|-------|-------|
| **When** | A previous cleanup landed bad commits (false-positive deletes, broken refs, dropped LFS pointers) and the user needs surgical recovery |
| **Phases run** | Custom: 0, 1, then INCIDENT-PLAYBOOK § appropriate-section, then verification |
| **Required artifacts** | `incident_<ts>.md` with diagnosis; per-recovery `git revert` or `git checkout` commits; `recovery_log.tsv` |
| **Stop condition** | Build green; user confirms recovered files match original intent |
| **Forbidden actions** | Forward cleanup work (this mode is purely backward-looking) |
| **Mode handoff** | "Recovery complete: <N> commits reverted; <M> files restored. Next mode: `triage-only` to re-plan with the issues now known" |

### 8. `add-archetype-profile` (skill-extension mode)

| Field | Value |
|-------|-------|
| **When** | User wants to extend the skill with a new repo archetype (Elixir, Rails, .NET, embedded C, ML training, etc.) |
| **Phases run** | Reading the existing REPO-ARCHETYPES.md → drafting the new archetype's protected_globs + smell adjustments → adding to `discover-project.sh` detection → adding to FILE-SMELLS.md per-archetype table → smoke-testing on a sample repo |
| **Required artifacts** | Updated REPO-ARCHETYPES.md, FILE-SMELLS.md, LANGUAGE-PROFILES.md; updated `scripts/discover-project.sh` |
| **Stop condition** | New archetype detected on a real sample repo; protected_globs fire correctly; smell rules don't false-positive on archetype-standard files |
| **Forbidden actions** | Any cleanup operations on the sample repo (this is meta-work) |
| **Mode handoff** | "Archetype `<name>` added to the skill. Run `full` mode on a real repo of that archetype to validate" |

### 9. `maintenance-review`

| Field | Value |
|-------|-------|
| **When** | Re-running on a previously-cleaned repo (typical: monthly/quarterly drift check) |
| **Phases run** | 0, 1, 2, 2.5, then if no candidates: short-circuit to handoff. If candidates: `full` |
| **Required artifacts** | Coverage matrix showing "drift since last cleanup"; the previous run's apply_log for diffing |
| **Stop condition** | Either "nothing to do" handoff OR full re-run completes |
| **Forbidden actions** | Re-applying patterns from the previous run without confirming they're still valid |
| **Mode handoff** | "Maintenance review on `<repo>`: <N> new candidates since <last-run-date>. Recommended next mode: `<verdict-driven>`" |

---

## Tier triage (orthogonal to mode)

Tiers scale with repo size. Pick a tier from the [TIER-TRIAGE.md](TIER-TRIAGE.md) table once mode is decided.

| Tier | Repo size | Mode adjustments |
|------|-----------|------------------|
| T1 | <100 tracked files | All modes default to Quick / Solo orchestration |
| T2 | 100–1k | Quick or Standard / Pair |
| T3 | 1k–20k | Standard / Squad |
| T4 | 20k–100k | Comprehensive / Swarm |
| T5 | 100k+ | Comprehensive + Council; `full` mode strongly discouraged without sub-tree partitioning |

---

## Mode-handoff template

At end-of-mode, the skill emits this verbatim block (filled in):

```
## Mode handoff: `<mode>` → `<recommended-next-mode>`

**Run:** repo-janitor-<DATE> on `<project>`
**Mode just ran:** `<mode>`
**Status:** `<complete | partial | halted>`

**What's done:**
- <bulleted list of completed phases + counts>

**What's open (deferred to next mode):**
- <bulleted list with rationale>

**Recommended next mode:** `<mode>`
**Why:** <one-line reason>
**Estimated scope:** <minutes / hours / sessions>
**Blocking gates:** <if any — e.g., "user must rotate signing key before harden-secret-leak Step 3">
**Files needed by next mode:**
- `<workspace>/triage.tsv`
- `<workspace>/move_plan.md`
- ...

**Reminder:** <one-line context the user shouldn't lose>
```

The user (or another agent) can hand the next mode the workspace + the handoff block and resume seamlessly.

---

## Blast-radius escalator

When mode-specific work reveals a wider problem, the skill auto-suggests escalation. Auto-escalation is *suggested*, never silently applied — the user types verbatim "yes proceed with escalation to `<new-mode>`" before any phase starts.

| Triggering condition | From mode | Escalate to |
|----------------------|-----------|-------------|
| Phase 2.5 finds a real secret | any | `harden-secret-leak` |
| Phase 4 finds 200+ broken refs in move plan | `move-only` / `full` | `triage-only` (re-plan with awareness) |
| Phase 6 build breaks repeatedly | `full` | `recover-from-bad-cleanup` (then back to `triage-only`) |
| Phase 9 fresh-eyes finds 10+ false-positive deletes | any with deletes | `recover-from-bad-cleanup` |
| User runs `gitignore-only` and SHADOWING-AUDIT shows 50+ shadowed tracked files | `gitignore-only` | `triage-only` (the cleanup is much bigger than the user thought) |
| Phase 1 detects 162 repos worth of work in `/data/projects` | any single-repo mode | `batch` (multi-repo orchestrator; see BATCH-MODE.md) |

The escalation decision is recorded in `mode_escalation_decision.md`:

```markdown
## Mode escalation: triage-only → harden-secret-leak

**Triggered at:** 2026-05-08T17:00:00Z
**By:** Phase 2.5 (leak-scanner subagent)
**Reason:** signing-cafef00d.key found at root; 32 bytes; pushed to origin/main 8 days ago
**User authorization:** "yes proceed with escalation to harden-secret-leak"
**Authorization received at:** 2026-05-08T17:01:23Z
**New phase plan:** INCIDENT-PLAYBOOK § Secret Leak Recovery (10 steps)
**Original mode work:** SUSPENDED (will resume after secret-leak hardening)
```

Without this decision file, the next phase refuses to start.

---

## Forbidden-actions enforcement

Each mode's forbidden-actions block is enforced by the main agent:

```python
# Pseudocode of the gate
def can_run(action, mode):
    forbidden = MODES[mode]["forbidden"]
    if any(action.matches(f) for f in forbidden):
        return False, f"Action '{action.kind}' is forbidden in mode '{mode}'"
    return True, None
```

When `can_run` returns False, the main agent surfaces the conflict to the user and either escalates the mode or refuses the action.

---

## Resumability across modes

Mode is captured in `<workspace>/run_state.json`:

```json
{
  "run_id": "repo-janitor-20260508T170000Z",
  "mode": "triage-only",
  "phase_completed": "5",
  "next_phase": "halt",
  "resumable": true,
  "mode_history": ["triage-only"],
  "escalations": []
}
```

On re-entry, the main agent reads `run_state.json` and confirms with the user:
- Same mode? Resume from `phase_completed + 1`.
- New mode? Verify the previous mode's stop condition was met; if not, ask the user whether to revert or continue.

---

## Why named modes matter

The four output-modes the skill originally shipped (`triage-only / move-only / delete-only / full`) were too thin: they didn't capture escalation paths, didn't have stop conditions, and didn't formalize handoffs between runs.

The 9-mode catalogue makes the skill's behavior predictable: a user knows what each mode will and won't do, what artifacts to expect, what to type next. The user can compose modes (`triage-only` → `harden-secret-leak` → `full`) and the skill maintains state across the chain.

This is the pattern from `wills-and-estate-planning-skill` (9 modes) and `saas-billing-patterns-for-stripe-and-paypal` (7 modes); both proved that mode-router rigor scales the skill from "agent reads SKILL.md" to "agent reasons about which mode to be in next."
