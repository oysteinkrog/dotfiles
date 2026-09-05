# Quote Bank

Stable-ID quotes from the corpus, citable from any artifact in this skill. Every quote is verbatim from its source with full attribution. Per `/operationalizing-expertise`, a quote bank turns "common wisdom" into auditable evidence — we don't guess what the corpus says, we cite it.

Citation format: **`Q-NNN`** (stable across pass updates; new quotes get the next available ID, never reusing a retired one).

---

## A. AGENTS.md (the gravitational center)

### Q-001 — The no-delete rule
> **YOU ARE NEVER ALLOWED TO DELETE A FILE WITHOUT EXPRESS PERMISSION.** Even a new file that you yourself created, such as a test code file. You have a horrible track record of deleting critically important files or otherwise throwing away tons of expensive work. As a result, you have permanently lost any and all rights to determine that a file or folder should be deleted.

**Source:** `AGENTS.md` § RULE NUMBER 1 (from the source corpus, not shipped with this skill).
**Why we cite:** Axiom 3 (`doctor --fix` has no deletion operation; `gc` is a separate, explicitly gated retention command). The `Op` enum has no `DeletePath` variant. Quarantine-instead-of-delete is the AGENTS.md no-delete rule operationalized in fixer code.

### Q-002 — The destructive-shell ban
> Absolutely forbidden commands: `git reset --hard`, `git clean -fd`, `rm -rf`, or any command that can delete or overwrite code/data must never be run unless the user explicitly provides the exact command and states, in the same message, that they understand and want the irreversible consequences.

**Source:** AGENTS.md § Irreversible Git & Filesystem Actions.
**Why we cite:** The Polish Bar "no destructive shell" item; the validator's forbidden-pattern list; the safety envelope's universal invariant 2.

### Q-003 — The no-script-edits rule
> **NEVER** run a script that processes/changes code files in this repo. Brittle regex-based transformations create far more problems than they solve. Always make code changes manually, even when there are many instances.

**Source:** AGENTS.md § Code Editing Discipline.
**Why we cite:** Phase 4 implementer instruction "manual edits or targeted Edit-tool calls only"; rules out auto-rewrites.

### Q-004 — The no-shims rule
> We do not care about backwards compatibility — we're in early development with no users. We want to do things the **RIGHT** way with **NO TECH DEBT**. Never create "compatibility shims". Never create wrapper functions for deprecated APIs. Just fix the code directly.

**Source:** AGENTS.md § Backwards Compatibility.
**Why we cite:** `upgrade` mode rule on deprecating old flags via warning then removing — not via permanent shim. The skill itself follows this when reorganizing existing files.

### Q-005 — The cass shape
> stdout is data-only, stderr is diagnostics; exit code 0 means success. Treat cass as a way to avoid re-solving problems other agents already handled.

**Source:** AGENTS.md § cass.
**Why we cite:** Axiom 8 (stdout=data, stderr=progress); the Polish Bar item on output discipline; the expectation that the doctor is a "stop-re-solving" tool.

### Q-006 — The bv robot-mode lesson
> **CRITICAL: Use ONLY `--robot-*` flags. Bare `bv` launches an interactive TUI that blocks your session.** ... `bv --robot-triage` is your single entry point.

**Source:** AGENTS.md § bv.
**Why we cite:** The mega-command pattern (`<tool> doctor --robot-triage`); the explicit non-interactive rule for agent invocation.

### Q-007 — The bv data_hash discipline
> All robot JSON includes: `data_hash` — Fingerprint of source beads.jsonl ... `status` — Per-metric state: `computed|approx|timeout|skipped` + elapsed ms ... Two-phase analysis: **Phase 1 (instant):** degree, topo sort, density. **Phase 2 (async, 500ms timeout):** PageRank, betweenness, HITS, eigenvector, cycles.

**Source:** AGENTS.md § bv.
**Why we cite:** The `schema_version` + `data_hash` discipline in our doctor's JSON output; the bounded-cost detector budget (`<tool> doctor health` < 200ms; `--quick`).

### Q-008 — The dcg performance ceiling
> Every Bash command passes through this hook. Performance is critical: Quick rejection filter eliminates 99%+ of commands before regex; Lazy-initialized static regex patterns (compiled once, reused); Sub-millisecond execution for typical commands; Zero allocations on the hot path for safe commands.

**Source:** AGENTS.md § dcg.
**Why we cite:** Sets the bar for `<tool> doctor health` (< 200ms target). The "fast-path detector" notion in `--quick` mode.

### Q-009 — The Codex/GPT-5.5 footnote (concurrent-edits reality)
> Those are changes created by the potentially dozen of other agents working on the project at the same time. This is not only a common occurence, it happens multiple times PER MINUTE. The way to deal with it is simple: you NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents.

**Source:** AGENTS.md § Note for Codex/GPT-5.5.
**Why we cite:** Phase 4 implementer rule to use Agent Mail file reservations for concurrent work; never `git stash`/`reset` the workspace; merge-by-cooperation rather than conflict-resolution-by-overwrite.

---

## B. `/dp/` exemplar source code

### Q-010 — `xf doctor` typed status
> ```rust
> #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
> #[serde(rename_all = "snake_case")]
> pub enum CheckStatus { Pass, Warning, Error }
>
> #[derive(Debug, Clone, Serialize)]
> pub struct HealthCheck {
>     pub category: CheckCategory,
>     pub name: String,
>     pub status: CheckStatus,
>     pub message: String,
>     #[serde(skip_serializing_if = "Option::is_none")]
>     pub suggestion: Option<String>,
> }
> ```

**Source:** `/dp/xf/src/doctor.rs:18-44`.
**Why we cite:** Typed `Finding`/`CheckStatus` in our schema; `suggestion: Option<String>` informs our `remediation.command` field; `#[serde(rename_all = "snake_case")]` for stable JSON.

### Q-011 — `br doctor` quarantine + audit
> ```rust
> #[derive(Debug, Clone, Serialize)]
> struct RecoveryAuditRecord {
>     phase: String,
>     action: String,
>     outcome: String,
>     #[serde(skip_serializing_if = "Vec::is_empty")]
>     applied_actions: Vec<String>,
>     #[serde(skip_serializing_if = "Vec::is_empty")]
>     quarantined_artifacts: Vec<String>,
>     #[serde(skip_serializing_if = "Vec::is_empty")]
>     verified_backups: Vec<config::RecoveryBackupVerification>,
>     ...
> }
> ```

**Source:** `/dp/beads_rust_*/src/cli/commands/doctor.rs:81-100`.
**Why we cite:** Quarantine-instead-of-delete (Axiom 3); the audit-record shape directly informs our `actions.jsonl` line schema (path/op/before_hash/after_hash/run_id/fixer_id/ok).

### Q-012 — `br doctor` refusal-on-prior-failure
> ```rust
> #[derive(Debug, Clone, PartialEq, Eq)]
> struct PriorJsonlRebuildFailureEvidence {
>     path: PathBuf,
>     artifact_count: usize,
> }
>
> const JSONL_REBUILD_AUTHORITY_ERROR_PREFIX: &str = "Cannot repair: JSONL authority is unsafe";
> const JSONL_REBUILD_REPEAT_ERROR_PREFIX: &str =
>     "Cannot repair: previous JSONL rebuild verification failed";
> ```

**Source:** `/dp/beads_rust_*/src/cli/commands/doctor.rs:102-115`.
**Why we cite:** The state-doesn't-get-worse-on-retry pattern; the sentinel-error-prefix-for-known-unsafe-states pattern (agent pattern-matches on prefix); inspires Axiom 5's exit-4-on-unsafe and the structured `error.code` field in our `--robot` envelope.

### Q-013 — `caam doctor` four-status taxonomy
> ```go
> type CheckResult struct {
>     Name    string `json:"name"`
>     Status  string `json:"status"` // "pass", "warn", "fail", "fixed"
>     Message string `json:"message"`
>     Details string `json:"details,omitempty"`
> }
> ```

**Source:** `/dp/coding_agent_account_manager/cmd/caam/cmd/doctor.go:27-32`.
**Why we cite:** `fixed` as a first-class outcome distinct from `pass`; informs our `actions_taken` field and the post-fix exit-0 with `actions_taken > 0` semantic.

### Q-014 — `caam robot` envelope (the agent-ergonomic gold standard)
> ```go
> // RobotOutput is the standard response wrapper for all robot commands.
> type RobotOutput struct {
>     Success     bool        `json:"success"`
>     Command     string      `json:"command"`
>     Timestamp   string      `json:"timestamp"`
>     Data        interface{} `json:"data,omitempty"`
>     Error       *RobotError `json:"error,omitempty"`
>     Suggestions []string    `json:"suggestions,omitempty"`
>     Timing      *RobotTiming `json:"timing,omitempty"`
> }
> ```

**Source:** `/dp/coding_agent_account_manager/cmd/caam/cmd/robot.go:37-46`.
**Why we cite:** The standard envelope for `<tool> doctor --robot` mode; `Suggestions[]` → our `next_steps[]`; `Timing` → mandatory in the JSON output; `Error.Code` → maps to our `exit_codes` dictionary entry name.

### Q-015 — `caam robot` design principles in source
> Design principles:
> - JSON output by default (no --json flag needed)
> - Structured errors with error_code field
> - Actionable suggestions in output
> - Exit codes: 0=success, 1=error, 2=partial success
> - Compact but complete information

**Source:** `/dp/coding_agent_account_manager/cmd/caam/cmd/robot.go:30-35`.
**Why we cite:** This is the manifesto for agent-ergonomic CLI design at the user's repos. Our Polish Bar adopts the same principles, expanded.

### Q-016 — `dcg` block-with-redirect
> Pattern System: 34 safe patterns (whitelist), 16 destructive patterns (blacklist), default allow ... When `dcg` blocks, it emits a structured error naming the safer alternative.

**Source:** AGENTS.md § dcg + `/dp/destructive_command_guard/src/main.rs`.
**Why we cite:** Our exit-4 unsafe-refused path adopts the same shape: `{decision: "refused", reason: "schema_version_unknown", observed_version: ..., alternative_command: "..."}`. Errors teach (Axiom 10). Lock-held refusals use exit 5.

---

## C. CASS-mined sessions (real-world evidence)

### Q-017 — `caam robot` is the strongest agent-ergonomic surface
> `caam robot status [provider]` - Full system overview with profiles, health, cooldowns
> `caam robot next <provider>` - Scoring algorithm to recommend best profile
> `caam robot act` - Execute actions (activate, cooldown, uncooldown, backup, refresh, delete)
> `caam robot health` - Quick health check (vault, database, profiles)
> `caam robot watch` - Stream status updates as newline-delimited JSON
> `caam robot limits <provider>` - Rate limits and burn rate data

**Source:** cass session "Analyze the Dicklesworthstone/coding_agent_account_manager repo (caam) for robot mode interface".
**Why we cite:** Maps the doctor's verb space onto the user's existing agent-ergonomic vocabulary. `health` (Axiom 11), `watch` (NDJSON streaming, future enhancement), `triage`/`act` mapping.

### Q-018 — Stale-lock cleanup is a recurring manual fix
> SQLite Rollback Journal Support (`.db-journal`) ... Adds `.beads/*.db-journal` to the stale lock file cleanup command ... renames "WAL files" to "SQLite sidecar files" ... Removes `beads.db-journal` during workspace copy.

**Source:** cass session "I need to examine the git diff in /data/projects/beads_rust to understand all the changes".
**Why we cite:** The DB-family-as-a-unit lesson (`.db`, `.db-wal`, `.db-shm`, `.db-journal`); informs the `state_files` failure-mode catalog and the `br doctor` absorbed playbook.

### Q-019 — `cm doctor` first-run V1 verb list
> The system is now fully functional with the V1 core command set (`context`, `mark`, `playbook`, `stats`, `doctor`, `reflect`) operational... `cm doctor`: Implemented system health checks for storage, dependencies, and config. ... `cm doctor`: ✅ Diagnoses system state (correctly identified missing API keys in current environment).

**Source:** cass session 2025-12-07T23-37 (gemini) reviewing the cm CLI.
**Why we cite:** The "missing API key" finding is a canonical NON-auto-fixable case — `manual_remediations` in capabilities (Axiom 10's structured remediation field).

---

## D. Scoring rubric anchors

### Q-020 — The agent-ergonomics first-try test
> The first command an agent guesses (`<tool> doctor`, `<tool> doctor --json`, or `<tool> doctor --help`) returns useful output. Common typos (`<tool> dr`, `<tool> doc`, `<tool> doctore`) emit a "did you mean: doctor" hint with the corrected command.

**Source:** [../rubric/SCORING-RUBRIC.md § agent_intuitiveness §1000 anchor](../rubric/SCORING-RUBRIC.md).
**Why we cite:** The score-1000 bar for dimension 1; informs the typo-handler regression test.

### Q-021 — The byte-for-byte reversibility test
> All fixers back up byte-identically through `mutate()`; permissions and mtime preserved; `cmp -s` between live file and backup at the moment of backup succeeds.

**Source:** [../rubric/SCORING-RUBRIC.md § data_safety §750 anchor](../rubric/SCORING-RUBRIC.md).
**Why we cite:** Pins the verbatim-backup invariant; rejected-without-evidence threshold of 700.

### Q-022 — The fixture round-trip test
> Round-trip (corrupt → fix → assert healthy → undo → byte-identical) passes for each.

**Source:** [../rubric/SCORING-RUBRIC.md § test_coverage_of_repair §750 anchor](../rubric/SCORING-RUBRIC.md).
**Why we cite:** Axiom 15's CI gate; implemented by `tests/doctor_fixtures/run_all.sh` and `scripts/verify-undo.sh`.

---

## E. Phase-7 fresh-eyes calibration

### Q-023 — Fresh-eyes prompt 1 (verbatim)
> Reread the new doctor code with fresh eyes. Look for obvious bugs, races, partial-write windows, unsafe `unwrap`/`expect`/panics on user paths, missing backups, broken idempotence, or any place where exit codes lie about reality. Carefully fix anything you uncover.

**Source:** [PHASES.md § Phase 7](PHASES.md).
**Why we cite:** Calibrated; the user has used variations of this prompt across many sessions; not to be paraphrased.

### Q-024 — Fresh-eyes prompt 2 (verbatim)
> Randomly pick three detectors and three fixers; trace their full execution including the `mutate()` chokepoint, backup write, and undo path. Construct a scenario that would corrupt user data and prove the code prevents it — or fix it.

**Source:** PHASES.md § Phase 7.
**Why we cite:** Same as above; calibrated.

### Q-025 — Fresh-eyes prompt 3 (verbatim)
> Review your fellow agents' code without restricting to recent commits. Find root causes via first-principles analysis. Pay special attention to: TOCTOU between detect and fix, signal handling, FS atomicity (rename vs write), interaction with the project's existing locks, and any path that bypasses `mutate()`.

**Source:** PHASES.md § Phase 7.
**Why we cite:** Same as above; calibrated.

---

## F. Adjacent-skill principles

### Q-026 — Skill description economy
> The frontmatter description is the only thing the harness uses to decide when to load a skill. It must answer: "what does this skill produce, and when does an agent reach for it?" — in under 220 characters.

**Source:** Skill-authoring discipline (paraphrased canonical guidance).
**Why we cite:** The frontmatter on this skill's SKILL.md is calibrated against this guidance; the description triggers ranges from "Add a `doctor`" to "Score this CLI's doctor".

### Q-027 — Operationalized expertise (`/operationalizing-expertise`)
> Distill expert methods into corpus, quote bank, triangulated kernel, operator library, and validators. The artifact is reusable; the kernel is the lens; the operators are the moves; the validators turn judgment into a CI gate.

**Source:** `operationalizing-expertise/SKILL.md` (paraphrased).
**Why we cite:** This skill's structure follows the canonical 5 artifacts: CORPUS.md (corpus), QUOTE-BANK.md (quotes), KERNEL.md (kernel), OPERATORS.md (operators), `scripts/validate-*.{sh,py}` (validators).

### Q-028 — Skill creation discipline
> A skill is built bottom-up from real artifacts you already have, not top-down from imagined needs. The corpus precedes the kernel; the kernel precedes the operators; the operators precede the rubric; the rubric precedes the scripts.

**Source:** Skill-authoring discipline (paraphrased canonical guidance).
**Why we cite:** The order this skill was built in matches: exemplar mining → kernel axioms → 20 operators → 10-dim rubric → verification scripts and validators. Each layer cites the one below.

---

## How to use the quote bank

When writing or revising any artifact in this skill, **cite by ID**. Don't paraphrase corpus content into prose — paraphrasing rots, citations don't. The validator (future enhancement) will check that every claim in SKILL.md / KERNEL.md / SCORING-RUBRIC.md that says "per the exemplars" or "per AGENTS.md" has a `Q-NNN` reference.

When mining new evidence (cass, new exemplars), allocate the next free Q-NNN and append it here. **Never reuse a retired ID** — agents may have memorized older citations.

When a quote becomes wrong (project moves, code is rewritten), mark it `**RETIRED:** <reason>` in this file rather than deleting it (per AGENTS.md no-delete; also: future readers want to know what the corpus *used to say*).
