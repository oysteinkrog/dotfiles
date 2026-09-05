# CASS Evidence Index — Comprehensive Cross-Reference

Quotes mined from `cass search` queries during the user's prior agent sessions, indexed by theme. Each entry has a short paraphrase, the source citation, and the Q-NNN ID in [QUOTE-BANK.md](../methodology/QUOTE-BANK.md) (when one is allocated).

This file is the "long" version of [CASS-FINDINGS.md](CASS-FINDINGS.md) — that file has the durable, recurring patterns; this one indexes a wider net for archaeology reference.

---

## Theme 1 — "I had to manually fix X" (gold for absorb-playbook)

> "I now have the complete diff. Here is a detailed summary of all changes ... SQLite Rollback Journal Support (`.db-journal`) ... Adds `.beads/*.db-journal` to the stale lock file cleanup command ..."

— beads_rust diff review session (Q-018). Evidence for the SQLite-DB-family failure-mode catalog item; informs the absorb of `fixing-beads-problems` skill steps 4–6.

> "The codebase has been comprehensively reviewed, diagnosed, and repaired ... `cm doctor`: Implemented system health checks for storage, dependencies, and config ... `cm doctor`: ✅ Diagnoses system state (correctly identified missing API keys in current environment)."

— gemini session 2025-12-07T23-37 (Q-019). Evidence for the manual-remediations pattern: missing env var is detected, NOT auto-fixed; user action required.

> "ANTHROPIC_API_KEY not set"

— recurring across multiple sessions. Pattern: a P1 finding with a structured `manual_remediations[].instruction` field (`"export ANTHROPIC_API_KEY=..."`).

---

## Theme 2 — Robot mode and agent ergonomics (validates Axioms 8, 11)

> "`caam robot status` ... `caam robot next` ... `caam robot health` ... `caam robot watch` ... Stream status updates as newline-delimited JSON ... Exit codes: 0=success, 1=error, 2=partial success."

— caam analysis session (Q-017, Q-014, Q-015). The strongest agent-ergonomic surface in /dp/. Validates the four-verb shape and the standard envelope.

> "stdout is data-only, stderr is diagnostics; exit code 0 means success."

— from cass's own AGENTS.md section (Q-005). Adopted as Axiom 8.

> "Use ONLY `--robot-*` flags. Bare `bv` launches an interactive TUI that blocks your session."

— from bv's AGENTS.md section (Q-006). Validates the never-launch-TUI-for-agents rule (Pattern 6).

---

## Theme 3 — Sub-millisecond hot path (validates PERFORMANCE.md)

> "Sub-millisecond execution for typical commands. Quick rejection filter eliminates 99%+ of commands before regex. Lazy-initialized static regex patterns (compiled once, reused). Zero allocations on the hot path for safe commands."

— from dcg's AGENTS.md (Q-008). Sets the bar for `<tool> doctor health` budget (< 200ms; aspirational < 50ms for cheap subcommands).

---

## Theme 4 — Two-phase analysis (informs detector tiering)

> "Two-phase analysis: **Phase 1 (instant):** degree, topo sort, density. **Phase 2 (async, 500ms timeout):** PageRank, betweenness, HITS, eigenvector, cycles."

— bv's AGENTS.md (Q-007). Informs the `tier: quick | default | deep | online` partition in detector budgeting.

---

## Theme 5 — Quarantine over delete (validates AGENTS.md RULE 1)

> "Removed offending .beads ignore pattern(s) from root .gitignore"

— `br doctor` source code: the doctor renames `.gitignore` to a backup, writes the new one. Doesn't delete the old. Pattern: every "remove" is implemented as `Op::Rename` to backup or quarantine.

> "quarantined_artifacts: Vec<PathBuf>"

— `br doctor` source code (Q-011). The first-class field in the doctor's audit record for files moved aside but not deleted.

---

## Theme 6 — Concurrent agent reality (validates AGENTS.md Codex/GPT-5.5 footnote)

> "Those are changes created by the potentially dozen of other agents working on the project at the same time. This is not only a common occurence, it happens multiple times PER MINUTE."

— AGENTS.md (Q-009). The justification for Agent Mail file reservations and the never-stash-other-agents-work rule. The doctor's lock primitive serializes against itself; concurrent edits to non-doctor files are the user's reality, not a problem the doctor solves.

---

## Theme 7 — Lock-file management (informs concurrency_primitives subsystem)

> "Adds `.beads/*.db-journal` to the stale lock file cleanup command."

Recurring across multiple beads_rust sessions. Pattern: lockfiles outlive their holders. The doctor detects via PID liveness; quarantines via `Op::Rename`.

> "Pre-commit guard install/uninstall idempotence"

— mcp_agent_mail's `install_precommit_guard` semantics. Adopted by Phase 8's integration-wirer for our doctor's pre-commit installation.

---

## Theme 8 — Schema versioning (informs schemas subsystem)

> "fix(sync): ensure tombstone flush survives JSONL write failure" — git commit referenced in beads_rust session.

The pattern: schema migrations CAN partially fail; the doctor must detect the partial state and either complete or refuse.

> "br doctor --json --db <temp>"

— from `fixing-beads-problems` skill. Pattern: rebuild into a TEMP DB; verify; promote to canonical only after `show + status + doctor` all pass against the temp.

---

## Theme 9 — JSON output discipline (informs Axioms 8, 11)

> "robot mode interface ... Standard response wrapper for all robot commands: success, command, timestamp, data, error, suggestions, timing"

— caam robot session (Q-014). The envelope adopted by our `--robot` mode.

> "stdout is data, stderr is diagnostics"

— recurring across cass, br, ubs, bv sessions. The single most important output discipline.

---

## Theme 10 — Refusal as a feature (informs Axiom 7, 10; exit-4 pattern)

> "Cannot repair: JSONL authority is unsafe"
> "Cannot repair: previous JSONL rebuild verification failed"

— br doctor source code (Q-012). Hard-coded sentinel error prefixes for known unsafe states. Pattern: agents pattern-match on prefix.

> "Force-release file reservation"

— mcp_agent_mail. Pattern: explicit override for trapped reservations, with audit trail. Adopted by `--force --yes` flag combo with logged justification.

---

## Theme 11 — Sandbox / no-network (validates Axiom 12)

> "I deleted my .config and reinstalled" — recurring user action across cass sessions.

The pattern: when the user resorts to "delete the config and start over", that's a doctor failure. The doctor should detect "config drift from a known-good baseline" and offer remediation BEFORE the user reaches for nuclear options.

> "Doctor in CI fails because the test environment has no network"

— recurring frustration across cass sessions. Validates `--online` opt-in default-off.

---

## Theme 12 — Status taxonomy (informs scoring rubric)

> "pass / warn / fail / fixed"

— caam doctor (Q-013). The four-status taxonomy with `fixed` as a first-class outcome.

> "Status: 'computed | approx | timeout | skipped'"

— bv's per-metric status (Q-007). Pattern: each detector reports its own status; the runtime aggregates.

---

## Theme 13 — Capabilities reflection (validates Axiom 11)

> "cass capabilities --json"
> "cass robot-docs guide"

— AGENTS.md § cass (Q-005). The four-verb shape: `health | capabilities --json | robot-docs | --robot-triage`. Adopted verbatim.

---

## Theme 14 — Test-fixture discipline (validates Axiom 15)

> "Tests at /dp/beads_rust_*/tests/e2e_workspace_scenarios.rs"
> "Tests at /dp/xf/tests/cli_e2e.rs"

The user's repos already practice extensive E2E testing. The doctor's `tests/doctor_fixtures/run_all.sh` slots into this pattern; existing scaffolding (cargo's test harness, Go's `go test`, pytest) handles the runner.

---

## Theme 15 — The "robot-docs negative space" insight

> Across multiple sessions, agents that successfully use a new tool *without* asking for help have read its `robot-docs` (or equivalent) FIRST. Agents that struggle haven't.

The doctor's `robot-docs` MUST include:
- Capabilities (positive space).
- Negative space ("things this doctor will NEVER do").
- Examples (canonical happy + canonical broken).
- Schema URLs (machine-readable).

This is what makes an agent willing to run unsupervised.

---

## Maintaining this index

When the cass-miner subagent runs in Phase 0 of a new pass, it produces `<workspace>/cass_findings.{md,jsonl}` with the latest 187+ quotes. The strongest 10–20 from each canonical query graduate to [CASS-FINDINGS.md](CASS-FINDINGS.md); themes that recur across passes graduate further to QUOTE-BANK.md with stable Q-NNN IDs.

This file (CASS-EVIDENCE-INDEX.md) is the bridge: it indexes the *theme* of evidence rather than individual quotes. New themes that emerge in cass mining should be added here even before they have a stable Q-NNN.

---

## How to read this index

For Phase 1 archaeology in a new project:
1. Skim themes 1–15 to internalize the user's experience.
2. For your subsystem, find the relevant themes (e.g., `state_files` → themes 1, 2, 5, 7, 8).
3. Cross-reference the cited /dp/ source files for concrete patterns.
4. Mine the user's CASS for project-specific quotes that match these themes.

The themes don't replace per-project mining — they accelerate it.
