# Source Corpus

The corpus is the body of evidence this skill operationalizes. Every claim in SKILL.md, every operator, every rubric anchor traces back to one or more corpus entries. When a future maintainer wants to know *why* the skill says what it says, they read this file.

Per `/operationalizing-expertise`, a corpus is *named*, *citable*, and *enumerable*. Citations are stable handles (file paths under `/dp/`, AGENTS.md sections, cass `source_path` URIs, and incident IDs in the user's bead trackers). Each corpus entry is referenced by stable IDs in [QUOTE-BANK.md](QUOTE-BANK.md).

---

## Layer 1 — Direct exemplars (`/dp` projects)

These are the user's own projects, mined for their existing doctor / health / verify / repair / check / diagnose / fix surfaces (the 7 verbs `discover-cli.sh --probe-doctor` looks for). Eight canonical exemplars are distilled in [../exemplars/exemplars.md](../exemplars/exemplars.md); the table below maps each to its source.

| Exemplar | Path | Role | Distilled in |
|----------|------|------|--------------|
| `xf doctor` | `/dp/xf/src/doctor.rs` | Typed `HealthCheck`/`CheckCategory`/`CheckStatus` records, suggestion field per finding | exemplars.md §1 |
| `br doctor` | `/dp/beads_rust_*/src/cli/commands/doctor.rs` | Most mature: `DoctorReport`, `RecoveryAuditRecord`, quarantine-instead-of-delete, `PriorJsonlRebuildFailureEvidence` (refusal on prior failure), sentinel error prefixes for known unsafe states | exemplars.md §2 |
| `caam doctor` | `/dp/coding_agent_account_manager/cmd/caam/cmd/doctor.go` | Status taxonomy `pass\|warn\|fail\|fixed`; declarative `DependencySpec`; `--auto + --yes` two-step gate | exemplars.md §3 |
| `caam robot` | `/dp/coding_agent_account_manager/cmd/caam/cmd/robot.go` | The gold standard agent-ergonomic surface: `RobotOutput` envelope with `Suggestions`, `Timing`, `Error.Code`; `robot status \| next \| act \| health \| watch \| limits` | exemplars.md §4 |
| `cm doctor` | (Bun/TS, mined via cass session 2025-12-07T23-37) | `cm` V1 verb set including `doctor`; subsystem partition (storage / dependencies / config); identifies env problems with named remediation | exemplars.md §5 |
| `cass health` | AGENTS.md § cass | Cheap-liveness pattern; `cass capabilities --json`; `cass robot-docs guide`; "stdout is data-only, stderr is diagnostics; exit code 0 means success" | exemplars.md §6 |
| `dcg explain` | AGENTS.md § dcg + `/dp/destructive_command_guard` | Block-with-redirect pattern: error names the safe alternative; `--json` returns `{decision, pattern_id, reason, suggestion}`; sub-millisecond hot path | exemplars.md §7 |
| `mcp_agent_mail` | `/dp/mcp_agent_mail_rust/` | `health_check` MCP tool; advisory file reservations as locks; pre-commit guard install/uninstall idempotence; `force_release_file_reservation` as opt-in override | exemplars.md §8 |

Extended exemplars (less core but informative) are catalogued in [../exemplars/DP-EXEMPLARS-EXTENDED.md](../exemplars/DP-EXEMPLARS-EXTENDED.md).

---

## Layer 2 — Manual repair playbooks worth absorbing

Skills in this same repo that document a *manual* repair playbook the doctor should absorb (per [ABSORB-PLAYBOOK.md](ABSORB-PLAYBOOK.md)):

| Skill | Tool target | Key playbook patterns extractable to detectors/fixers |
|-------|-------------|-----------|
| `fixing-beads-problems` | `br` | Snapshot `.beads/`, classify (DB-only/JSONL-only/drift/app-bug), harvest dirty issues from DB, rebuild into temp DB, promote with verification |
| `system-performance-remediation` | host system / `pt` wrapper | Process triage, scan vs. deep-scan, plan/apply workflows |
| `path-rationalization` | shell PATH state | Detect duplicates, junk dirs, wrong binary resolution; remediate via `.zshenv`/`.bashrc` rewrite |

---

## Layer 3 — AGENTS.md (the gravitational center)

`AGENTS.md` (from the source corpus, not shipped with this skill) is the single most important corpus document. Sections cited:

| AGENTS.md section | What we extracted |
|-------------------|-------------------|
| § RULE NUMBER 1: NO FILE DELETION | Axiom 3 (undo as the only "delete"); `Op` enum with no `DeletePath`; `mutate()`'s atomicity rule |
| § Irreversible Git & Filesystem Actions | Polish Bar "no destructive shell"; validator forbidden patterns; `safety_envelope.md` template |
| § Code Editing Discipline (no script-based) | Phase 4 implementer rule "manual edits or targeted Edit-tool calls only" |
| § Backwards Compatibility (no shims) | `upgrade` mode rule: deprecation through warning, but eventually remove the old flag |
| § Beads Workflow Integration | Phase 4 bead creation pattern; `br ready` → claim → close → sync workflow |
| § Landing the Plane | Phase 10 handoff requirements; `git push` mandatory |
| § cass | The four-verb shape `<tool> doctor health \| capabilities --json \| robot-docs \| --robot-triage` |
| § dcg | Block-with-redirect pattern adopted by exit-4 paths |
| § MCP Agent Mail | File reservations for shared-file coordination across implementers; `install_precommit_guard` idempotence pattern |

---

## Layer 4 — Cass-mined sessions

`cass search` over the user's prior agent sessions yields evidence about *real-world* failure modes the doctor needs to absorb. Mined via [../subagents/cass-miner.md](../../subagents/cass-miner.md) using the canonical query set in [PHASES.md § Phase 0](PHASES.md). Strongest finds organized in [../exemplars/CASS-FINDINGS.md](../exemplars/CASS-FINDINGS.md) and indexed by theme in [../exemplars/CASS-EVIDENCE-INDEX.md](../exemplars/CASS-EVIDENCE-INDEX.md).

Representative themes:
- `caam robot` is the strongest agent-ergonomic surface in the user's repos (validates Axiom 11)
- Stale-lockfile cleanup is the canonical "thing the user does manually that should be in `br doctor --fix`" (validates Axiom 5 + ABSORB-PLAYBOOK)
- "Missing API key" is a canonical NON-auto-fixable finding — listed in `manual_remediations` (validates Axiom 10's structured-remediation field)
- SQLite sidecar family (`.db-wal`, `.db-shm`, `.db-journal`) handling is a perennial trap (informs `state_files` failure-mode catalog)

---

## Layer 5 — Adjacent skills (informing methodology, not building blocks)

| Skill | What it informs |
|-------|-----------------|
| `agent-ergonomics-and-intuitiveness-maximization-for-cli-tools` | The 11-dim agent-ergonomics rubric (used by `agent-ergo-grader`); the "first command an agent guesses just works" principle |
| `operationalizing-expertise` | This document; KERNEL.md; QUOTE-BANK.md; OPERATORS.md formalism |
| `codebase-archaeology` | Phase 1 (subsystem partition + failure-mode enumeration) shape |
| `codebase-report` | Phase 3 (synthesis + narrative chapters) shape |
| `multi-pass-bug-hunting` | Phase 7 (audit-fix-rescan loop with calibrated prompts) |
| `multi-model-triangulation` | Phase 4/7 cross-validation harness; the three calibrated review prompts |
| `agent-mail` | Coordination for parallel Phase 4 implementers via file reservations |
| `br` + `bv` | Phase 4 task graph driven by beads; `br ready` for ordered work |
| `dcg` | Block-with-redirect for exit-4 unsafe-refused paths |
| `ubs` | Phase 7 static-analysis gate before declaring fresh-eyes clean |
| `cc-hooks` | Phase 8 pre-commit / post-tool-use integration |
| `gh-actions` | Phase 8 CI workflow generation |
| `idea-wizard` | Phase 10 second-order improvements generator |
| `testing-fuzzing` | Phase 5 fault-injection extension into `mutate()` |
| `testing-metamorphic` | Phase 5 property tests `fix(corrupt(x)) ≡ x` |
| `testing-conformance-harnesses` | Phase 5 round-trip backup/restore golden corpus |
| `testing-golden-artifacts` | Phase 9 fixture suite as snapshots |
| `testing-real-service-e2e-no-mocks` | Phase 5 online-detector tests with real vendor APIs |

Full integration playbook in [TESTING-INTEGRATION.md](TESTING-INTEGRATION.md).

---

## Layer 6 — Bug-tracker history

Per-project: `br ready --json`, `br list --json`, `gh issue list --json` for the *target* CLI's recent bugs. Phase 1's archaeologist mines this for failure modes. Findings flow to `<workspace>/analysis/failure_modes/<subsystem>.md` with bead/issue IDs as `prior_incidents`.

The doctor's automation_degree score weights `frequency` partly by bug-tracker count — failure modes that recur in tickets matter more than failure modes nobody has ever filed.

---

## Layer 7 — Git history

`git log --grep='fix\|panic\|corrupt\|race\|deadlock\|leak\|wedged' --since=180.days --oneline` for the target. Each match is a candidate FM. The implementer commit's diff often shows the manual repair recipe in commit form.

---

## How the layers compose

A typical Phase 1 archaeology pass for a single subsystem reads:

1. The subsystem's source code (Layer 1 corpus to derive structural FMs).
2. AGENTS.md (Layer 3 — invariants the doctor must respect).
3. The bug tracker filtered to that subsystem (Layer 6).
4. `cass_findings.jsonl` filtered to that subsystem (Layer 4).
5. Git log filtered to that subsystem (Layer 7).
6. Adjacent skill ABSORB-PLAYBOOK.md if the project has a related manual-repair skill (Layer 2).

The output (`<workspace>/analysis/failure_modes/<subsystem>.md`) cites every FM's evidence back to the layer it came from. Phase 6 scorecard validation rejects any score ≥ 700 without a citation; this is how the corpus stays load-bearing.

---

## Maintaining the corpus

When a new exemplar appears in `/dp/`, when a new manual-playbook skill is added, when AGENTS.md is updated, when cass adds a new strong finding — **update this file first**, then update the skill artifacts that depend on it. The corpus is the source-of-truth; everything else is derivative.

`scripts/check-skills.sh` doesn't validate corpus links yet. Future improvement: add a `validate-corpus.py` that checks every cited path in this file resolves on the local FS (or note it as missing).
