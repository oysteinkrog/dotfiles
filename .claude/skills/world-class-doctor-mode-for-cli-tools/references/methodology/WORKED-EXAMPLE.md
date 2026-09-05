# Worked Example — Applying the Skill to `/dp/beads_rust`

A full pass through every phase, applied to a real project from the user's repos. Names are real; quoted source lines are verbatim. Where a phase produced a long artifact, this file shows the *shape* with two or three concrete entries — full artifacts would live in `<workspace>/`.

The `beads_rust` project (binaries `br` + `bv`) was chosen because:

- It already has an existing `br doctor` (Pattern → `upgrade` mode, not `add`).
- It's multi-binary (Pattern 2).
- It has a related manual playbook skill, `fixing-beads-problems` (Pattern 10 — absorb-playbook, partially).
- It's the user's most-cited cass-mining target.
- The user has lived with its failure modes long enough that ground truth is rich.

This worked example is **illustrative**, not a real workspace. Numbers are realistic but synthetic for clarity.

---

## Intake

```
Target: /dp/beads_rust_c49_72yf27 (sha=cb1c49e7..., default branch=main)
Binaries: br, bv
Mode: upgrade  (existing `br doctor` detected)
Operating location: worktree at /dp/beads_rust_c49_72yf27__doctor_workspace/worktree
                    on branch doctor-mode-pass-1 (from main)
Triangulation: multi-model (Claude + Codex + Gemini)
CASS: deep (38+ canned queries; this is a heavily-used tool)
Online: offline-only
Must-not-touch: src/storage/sqlite_legacy.rs (deprecated; awaiting removal in 0.5)
```

---

## Phase 0 — Bootstrap

`scripts/check-skills.sh` reports 28/29 referenced helpers installed; `testing-conformance-harnesses` missing. `jsm install testing-conformance-harnesses` succeeds.

`scripts/discover-cli.sh /dp/beads_rust_c49_72yf27 --probe-doctor` returns:

```jsonc
{
  "schema_version": "1.0",
  "target_sha": "cb1c49e7...",
  "default_branch": "main",
  "language": "rust",
  "build_system": "cargo",
  "binaries": ["br", "bv"],
  "existing_doctor_subcommand": "doctor",
  "existing_diagnostic_subcommands": ["doctor"],
  "probe_doctor": 1
}
```

`subagents/baseline-snapshotter.md` runs:

- Captures `br doctor --help` (300 lines).
- Captures `br doctor --json` against a healthy `/dp/beads_rust_c49_72yf27/.beads/` (exits 0; report has 0 findings).
- Captures `br doctor --json` against a fixture from `/dp/beads_rust_c49_72yf27/sample_beads_db_files/ntm/` (exits 1; 4 findings — all currently auto-detected, 2 auto-fixed).
- Hash-snapshots every file in the target outside `.git/` and `target/`. Re-hashes after the snapshot phase. **Drift detected on `.beads/.gitignore`** — the existing `br doctor` auto-mutates `.gitignore` without `--fix`. Filed as P0 bead `br-doctor-pass1-existing-auto-mutates-gitignore`.

`subagents/cass-miner.md` runs the 13 canned queries, returns 187 quotes classified into:

- 47 SYMPTOM
- 33 ROOT_CAUSE
- 26 MANUAL_FIX (gold)
- 18 INCIDENT
- 63 WISH_THIS_EXISTED

The MANUAL_FIX set heavily overlaps with the `fixing-beads-problems` skill's "Recovery Loop" — confirming the `absorb-playbook` opportunity.

---

## Phase 1 — Failure-Mode Inventory (parallel by subsystem)

The archaeologist subagent dispatched 6 times in parallel. Output sample from `state_files`:

```markdown
# Failure Modes — state_files (br + bv)

# FM-fm-state-files-jsonl-tombstone-drift
id: fm-state-files-jsonl-tombstone-drift
title: Issues tombstoned in DB still present in issues.jsonl
severity: P2
subsystem: state_files
symptoms:
  - `br show <id>` returns "issue not found" but `grep <id> .beads/issues.jsonl` returns matches
  - `br sync --status` reports JSONL has unsynced rows
  - `bv` shows ghost issues that disappear on refresh
root_cause: |
  Sync writes the tombstone table to the DB but the JSONL flush hasn't
  happened (or partially failed). The next `br show` reads from DB (tombstone
  applies) but legacy JSONL parsers see the row.
observable_signals:
  - file:line — `.beads/issues.jsonl:142,187` (example offending row indexes)
  - query — `select issue_id from tombstones except select issue_id from issues_in_jsonl`
  - hash — `sha256(.beads/issues.jsonl)` differs from DB-derived expected hash
prior_incidents:
  - git_sha:abc1234 (commit "fix(sync): ensure tombstone flush survives JSONL write failure")
  - br-127 (bead title: "Sync drift: tombstones in DB but rows in JSONL")
  - cass:".../session-2025-11-15.json#42" — user said "I had to manually grep and delete the rows"
currently_auto_detected: yes (existing `br doctor` detects)
currently_auto_fixed: yes (existing `br doctor --fix` rewrites JSONL)
evidence:
  - src/storage/sqlite/tombstones.rs:78-95 (the tombstone table semantics)

# FM-fm-state-files-db-family-partial-presence
id: fm-state-files-db-family-partial-presence
title: SQLite DB family files (.db / .db-wal / .db-shm / .db-journal) inconsistent
severity: P0
subsystem: state_files
symptoms:
  - `.beads/beads.db-wal` exists but `.beads/beads.db` doesn't
  - `pragma integrity_check` returns OK but query results are stale
root_cause: |
  Cleanup ops (e.g., a manual `rm` or a backup-restore that skipped the
  family) handled the family inconsistently. SQLite's WAL mode means the
  -wal file IS authoritative for some recent writes; missing the .db
  file but having the -wal is a recipe for silent data loss.
observable_signals:
  - file existence — list of expected family members
  - log_pattern — `WAL frame N missing parent` in journal_mode=WAL output
prior_incidents:
  - cass:".../session-2025-12-03.json#88" (user described losing 3 days of issues)
  - git_sha:def5678 (commit "fix(backup): include .db-journal in family")
currently_auto_detected: NO  ← gap
currently_auto_fixed: NO  ← gap

# FM-fm-state-files-stale-doctor-lock
... (etc; total 7 FMs in this subsystem)
```

Total inventory after Phase 1: **28 failure modes across 6 subsystems**.

---

## Phase 2 — Repair Specs (parallel; same agent per subsystem)

The state_files spec author writes 7 specs. One sample for the new FM:

```markdown
# RS-fm-state-files-db-family-partial-presence — SQLite DB family inconsistent

**Failure mode:** fm-state-files-db-family-partial-presence
**Subsystem:** state_files
**Severity:** P0
**Currently auto-detected:** no
**Currently auto-fixed:** no

> Operators applied: 🩺 🚪 💾 ↩ 🔁 🔒 🧪 🛡

## Detector (pure)

```rust
fn detect_db_family_partial(repo: &Path) -> Option<Finding> {
    let family = [
        repo.join(".beads/beads.db"),
        repo.join(".beads/beads.db-wal"),
        repo.join(".beads/beads.db-shm"),
        repo.join(".beads/beads.db-journal"),
    ];
    let presence: Vec<bool> = family.iter().map(|p| p.exists()).collect();
    let core_present = presence[0];
    let any_sidecar_present = presence[1..].iter().any(|&p| p);
    if !core_present && any_sidecar_present {
        return Some(Finding { /* P0; cite which sidecars are present */ });
    }
    if core_present && family[2].exists() && !family[1].exists() {
        // .db-shm without .db-wal in WAL mode is anomalous
        return Some(Finding { /* P0; suggest `pragma journal_mode=delete` reset */ });
    }
    None
}
```

## Fixer (mutates via mutate())

If `.db` is missing but sidecars exist: refuse with exit 4 — the sidecars contain unflushed data we shouldn't discard. Manual remediation: open the WAL with `sqlite3 .beads/beads.db-wal` and reconstruct (this is genuinely the user's call).

If `.db-shm` exists but `.db-wal` doesn't: quarantine `.db-shm` via `Op::Rename` (it's stateless without -wal). Backup first.

```rust
fn fix_db_family_partial(repo: &Path, ctx: &MutateContext) -> Result<()> {
    let family = [/* same as detector */];
    let presence: Vec<bool> = family.iter().map(|p| p.exists()).collect();
    if !presence[0] {
        anyhow::bail!("refused: .db missing but sidecars present; manual recovery via sqlite3");
    }
    if presence[2] && !presence[1] {
        let quarantine = ctx.run_dir.join("quarantine/db-family/beads.db-shm");
        mutate(ctx, &family[2], Op::Rename { from: family[2].clone(), to: quarantine })?;
    }
    Ok(())
}
```

## Preconditions
- `lock_acquired` (the project's existing `.beads/.git-like-lock`)
- `backup_dir_writable`

## Invariants preserved
- The `.db` file (if present) is unchanged by this fixer.
- Any unflushed -wal data is not discarded — only -shm (which has no unique data without -wal) is quarantined.

## Backup spec
- `.beads/beads.db-shm` (the file being quarantined)

## Inverse
`<tool> doctor undo <run-id>` restores `.beads/beads.db-shm` from `backups/`. The `Op::Rename` undo is a reverse rename + a pre-existence-marker check.

## Idempotence proof sketch
After a successful fix: `.beads/beads.db-shm` is at `<run-dir>/quarantine/`. Detector re-run finds `.db-shm == false`; the offending `core_present && shm && !wal` predicate is false; detector returns None.

## Fixture spec
`tests/doctor_fixtures/fm-state-files-db-family-partial-presence/`:
- `corrupt.sh` — initialize `.beads/`, then `mv beads.db-shm beads.db-shm` (no-op) — wait, this needs work. Actually: write a fresh `.db-shm` and remove `.db-wal`. Reproducible via:
  ```bash
  br init && br create -t task --title="seed" && \
      cp .beads/beads.db-shm /tmp/preserved && \
      mv .beads/beads.db-wal /tmp/discarded
  ```
- `assert.sh` — assert `.db-shm` is in `.doctor/runs/.../quarantine/db-family/`.

## Open questions
- For partial-presence cases beyond the two we've enumerated: Phase 3 synthesizer should decide if we add more cases or refer all of them to manual remediation.
```

(The other 27 specs follow similarly. Total Phase 2 output: 28 specs × ~120 lines = ~3,400 lines of spec markdown.)

---

## Phase 3 — Synthesis

The synthesizer produces:

- **`taxonomy.md`**: 28 FMs grouped by subsystem; severity bucket counts (P0:5, P1:8, P2:11, P3:4); cross-cutting concerns named (e.g., "every state_files fixer must hold the project's existing `.beads/.git-like-lock` first").

- **`dependency_graph.json`**: DAG with 31 edges. Validated by `validate-dag.py`. Highlights:
  - `fm-state-files-db-family-partial-presence` → `fm-state-files-jsonl-tombstone-drift` (must fix DB before reasoning about JSONL drift)
  - `fm-schemas-db-version-mismatch` → ALL state-files fixers (schema must be current first)

- **`conflict_matrix.md`**: 4 forbidden pairs. Highlight: `(fm-state-files-db-rebuild, fm-state-files-jsonl-tombstone-drift)` — rebuilding the DB invalidates the tombstone evidence basis.

- **`safety_envelope.md`**: extends universal envelope. Project-specific:
  - Write scopes: `.beads/`, `.doctor/`, `~/.config/br/` (if present).
  - Lock primitive: project's existing `.beads/.git-like-lock` (acquired by `mutate()`).
  - Doctor MUST NOT touch `src/storage/sqlite_legacy.rs` (per intake).

- **`playbook.md`** with 3 narrative chapters. Highlights from "What you should back up first":
  > Before applying a Phase-1 doctor pass on beads_rust, the user is encouraged to (a) `git stash` any in-progress edits, (b) tar the entire `.beads/` to `~/beads-backup-<date>.tar`. Even though the doctor backs up before mutation, a separate manual snapshot guards against the meta-failure of the doctor itself going wrong on its first pass.

---

## Phase 4 — Implementation

The lead implementer claims `crates/doctor-core/src/mutate.rs` (the chokepoint for both `br` and `bv`). 4 subsystem implementers run in parallel via Squad tier with multi-model triangulation on the chokepoint and the new P0 fixer.

Sample commits on `doctor-mode-pass-1`:

```
cb1c49e7 doctor(core): add mutate() chokepoint with verbatim backup + actions.jsonl
a8f3b2d1 doctor(state_files): fm-state-files-jsonl-tombstone-drift: refactor through mutate()
b1c4e6f2 doctor(state_files): fm-state-files-db-family-partial-presence: detect + fix + fixture (br-201)
c2d5f7e3 doctor(schemas): fm-schemas-db-version-mismatch: add fixer + migrate path (br-202)
d3e6a8b4 doctor(concurrency_primitives): fm-stale-doctor-lock: detect + quarantine fixer (br-203)
e4f7b9c5 doctor(surface): wire --robot-triage and capabilities --json
f5a8c0d6 doctor(surface): wire health command with sub-200ms budget
06b9d1e7 doctor(surface): wire robot-docs with negative-space spec
```

Total: 23 commits over Phase 4 (10 fixers added, 6 existing refactored, 7 surface additions).

`scripts/validate-doctor.sh /dp/beads_rust_c49_72yf27` exits 0.

---

## Phase 5 — Safety Harness

For each fixer, run the five verifiers:

```
verify-undo.sh fm-state-files-jsonl-tombstone-drift                   PASS
verify-idempotence.sh fm-state-files-jsonl-tombstone-drift            PASS
verify-crash-recovery.sh fm-state-files-jsonl-tombstone-drift          PASS at all K
verify-concurrency.sh fm-state-files-jsonl-tombstone-drift            PASS
verify-metamorphic.sh fm-state-files-jsonl-tombstone-drift            PASS
verify-undo.sh fm-state-files-db-family-partial-presence              PASS
verify-idempotence.sh fm-state-files-db-family-partial-presence       PASS
verify-crash-recovery.sh fm-state-files-db-family-partial-presence    FAIL at K=5ms (orphan .doctor.tmp.1234567)
...
```

The K=5ms failure on the new P0 fixer triggers a hard-stop. Bead filed: `br-204 doctor: phase5: crash-recovery: fm-state-files-db-family-partial-presence: orphan tempfile at K=5ms`. Spec author re-enters Phase 4 with the proposed fix (atomic-write the rename target into a single `Op::Rename` rather than two-step copy+delete). Re-run: PASS.

After 2 iteration cycles in Phase 4/5, all 24 fixers pass all Phase 5 verifiers.

`testing-fuzzing` extension run for 60 seconds on `mutate()`: 0 crashes. `testing-metamorphic` derives 8 properties; all hold against 1000 inputs each.

---

## Phase 6 — Scorecard

`scripts/scorecard.py render <workspace>` produces:

```
Aggregate score: 893
Per-FM medians (top 5):
  fm-state-files-jsonl-tombstone-drift               950
  fm-schemas-db-version-mismatch                     940
  fm-state-files-db-family-partial-presence          910
  fm-concurrency-primitives-stale-doctor-lock        890
  fm-userland-state-config-dir-missing               750  ← manual_remediations only
```

Heatmap shows `automation_degree` is the weakest dimension (median 720) — there are 5 FMs the doctor detects but doesn't auto-fix. That's expected and acceptable; they're correctly listed under `manual_remediations` in capabilities.

`agent_ergo_grader` against the agent-ergonomics rubric: 11/11 dimensions ≥ 750. The new `--robot-triage` mega-command earns 1000 on `agent_ergonomics::macros-vs-granular`.

`scripts/diff-scorecards.py <workspace> baseline 1`: 18 FMs improved by > 100 pts each; 0 regressions > 50 pts. Hard-stop check passes.

---

## Phase 7 — Fresh-Eyes (3 rounds, multi-model)

Round 1 (prompt 1, all 3 models):
- Claude finds: a panic on a malformed `.git-like-lock` file (P1; bead `br-205`).
- Codex finds: a TOCTOU between `lock acquire` and `read live file` in 2 fixers (P0; bead `br-206`).
- Gemini finds: a shadowed variable in the schema migration code (P2; bead `br-207`).

Round 2 after fixes:
- Claude (fresh) finds: race in symlink update (P1; bead `br-208`).
- Codex finds: nothing significant.
- Gemini finds: a comment typo (trivial).

Round 3 after fixes:
- All 3 find: nothing significant (only 1 typo across all 3 — trivial).

Loop terminates: 2 consecutive clean rounds (rounds 2 and 3, both with only trivial edits).

`ubs $(git diff --name-only HEAD~30 HEAD)`: clean.
`cargo clippy -- -D warnings`: clean.
`cargo test`: green.
`scripts/diff-scorecards.py <workspace> 1-mid 1-final`: no regression > 50 pts (one FM dropped 30 pts due to a TOCTOU fix that traded raw speed for correctness — explained in the commit; not flagged).

---

## Phase 8 — Integration

`subagents/integration-wirer.md` does:

1. Pre-commit hook: adds `br doctor --quick --json > /dev/null` to `.git/hooks/pre-commit`. Tested against `tests/doctor_fixtures/fm-state-files-jsonl-tombstone-drift/corrupt.sh`: pre-commit blocks. PASS.

2. CI workflow: adds `.github/workflows/doctor.yml` per the canonical pattern in [`subagents/integration-wirer.md`](../../subagents/integration-wirer.md) — uses the doctor's own scorecard.json + jq (NOT this skill's `./scripts/scorecard.py`, which doesn't exist on the target repo's CI runner):
```yaml
- run: br doctor health
- run: |
    br doctor --json > /tmp/run.json || rc=$?; case "${rc:-0}" in 0|1) ;; *) exit "${rc:-0}";; esac
    run_dir=$(jq -er .run_dir /tmp/run.json)
    curr=$(jq -er '.aggregate.score // .aggregate_score // 0' "$run_dir/scorecard.json")
    prev=$(jq -er '.aggregate.score // .aggregate_score // 0' .doctor/baseline-scorecard.json)
    [ "$((prev - curr))" -le 50 ] || { echo "FAIL: regression > 50 pts"; exit 1; }
```

3. Demote `fixing-beads-problems` skill: updates its `SKILL.md` top section:
```markdown
> **First, run `br doctor --fix`.** It absorbs most of this playbook's steps:
> stale-lock cleanup, JSONL tombstone drift, DB family family integrity,
> schema-version mismatch. If `br doctor --fix` doesn't help, the manual
> playbook below remains as a fallback for unusual cases.

# Fixing Beads Problems
[... existing content preserved per AGENTS.md no-delete ...]
```

---

## Phase 9 — Fixture Suite

`tests/doctor_fixtures/` populated with 28 per-FM directories + 7 combinatorial pair fixtures (the worst offenders): `fm-schemas-db-version-mismatch__fm-state-files-jsonl-tombstone-drift`, etc.

`tests/doctor_fixtures/run_all.sh` exits 0.

---

## Phase 10 — Cold UX

Fresh prober subagent receives:
- The `br` binary (v0.5.0-doctor-pass-1)
- `<workspace>/canonical_tasks.md` listing 7 tasks (e.g., "your `br show br-100` returns 'not found'; investigate")
- `<tool> doctor robot-docs` output

The prober attempts each task. Findings:

- **Confusing.** "The `--robot-triage` field `recommended_command` lists ONE command; for multi-FM cases I had to also call `--json` to see all FMs."  → P2 bead `br-209`.
- **Wished existed.** "`<tool> doctor explain --evidence-bytes` to dump raw bytes for a finding's evidence (useful when debugging)."  → P3 bead `br-210`.
- **All 7 tasks completed without escalation.** ✓

Idea-generator dispatches `/idea-wizard`; surfaces 14 priority-3 backlog beads.

---

## HANDOFF.md (excerpt)

```markdown
# HANDOFF — Pass 1

**Tool:** br + bv | **Doctor version:** 1.0.0 | **Branch:** doctor-mode-pass-1
**Started:** 2026-05-06T08:00:00Z | **Finished:** 2026-05-06T20:00:00Z | **Duration:** ~12h

## Pass summary
- Mode: upgrade
- FMs inventoried: 28
- Specs written: 28
- Implementations landed: 24 (10 new + 6 refactored + 8 surface; 4 went to manual_remediations)
- Phase 5: 120 verifications run, 120 passed (after 2 cycle iterations)
- Fresh-eyes rounds: 3 (last 2 clean)
- Fixtures added: 28 + 7 combinatorial = 35

## Scorecard before / after
| Metric | Before | After | Δ |
|--------|--------|-------|---|
| Aggregate | 624 | 893 | +269 |
| FMs P0 | 4 unhandled | 0 unhandled | -4 |
| FMs P1 | 6 unhandled | 0 unhandled | -6 |

## Top 5 improvements
| FM | Before | After | Δ |
|----|--------|-------|---|
| fm-state-files-db-family-partial-presence | 0 (missing) | 910 | +910 |
| fm-schemas-db-version-mismatch | 350 | 940 | +590 |
| fm-state-files-jsonl-tombstone-drift | 720 | 950 | +230 |
| ... | | | |

## Top regressions
none

## Next pass recommendations
1. Add `<tool> doctor explain --evidence-bytes` (br-210; P3).
2. Fix `--robot-triage` to list ALL FMs in `recommended_command` field (br-209; P2).
3. Build the meta-doctor pattern (Pattern 12) for the doctor's own internal validation.
4. Add `testing-conformance-harnesses` golden corpus for `actions.jsonl` schema stability.
5. Consider absorbing `path-rationalization` skill into `br doctor` for shell-RC-level FMs.
6. Re-mine cass after 90 days of pass-1 doctor in production; expect 5–10 new FMs surfaced.

## Open issues
br-209: doctor: --robot-triage recommended_command lists only one (P2)
br-210: doctor: explain --evidence-bytes (P3)
br-211 through br-225: idea-wizard backlog (P3)

## Files of interest
- /dp/beads_rust_c49_72yf27__doctor_workspace/scorecard_pass_1.md
- /dp/beads_rust_c49_72yf27__doctor_workspace/heatmap.svg
- /dp/beads_rust_c49_72yf27/.doctor/latest -> runs/2026-05-06T20-00-00Z__a3f9b2/
- /dp/beads_rust_c49_72yf27/tests/doctor_fixtures/run_all.sh

## Hand-off note
The most important context for the next pass: the `--robot-triage` field
shape is contract-governed. Bumping `doctor_contract_version` to handle
br-209 is acceptable but coordinate with downstream agents that have
cached behavior. The pass succeeded but the fresh-eyes rounds were
particularly productive — the TOCTOU bug Codex caught in Round 1 would
have been a P0 incident in production. Continue running multi-model
triangulation on the chokepoint and irreversible paths.
```

---

## What this example shows

- The 10 phases produce 11 distinct artifact classes.
- The five-test safety harness catches a real bug (the K=5ms orphan tempfile) before Phase 6 scoring.
- The fresh-eyes loop catches a real TOCTOU bug that the unit tests missed.
- Aggregate score lifts +269 pts (from a baseline of 624 to 893) — within the "production-grade" band.
- The pass takes ~12 hours of wall time at Squad tier with multi-model triangulation; faster tiers (Solo/Pair) are 2–4× shorter.
- Existing skills (`fixing-beads-problems`) are demoted, not deleted (AGENTS.md no-delete).
- Open beads carry to pass 2; the methodology IS the persistence (Axiom 16).
