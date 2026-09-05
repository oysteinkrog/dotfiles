# DEBUGGING-THE-AUDIT.md — When The Audit Itself Looks Wrong

<!-- TOC: Symptom flowchart | Phase-specific symptoms | Decoding raw/ logs | The audit's own audit | Debug commands | Common gotchas | When to escalate -->

> Sometimes the audit produces unexpected results: scores look too generous, false-closed list seems wrong, convergence won't happen, raw outputs are missing. This file is the troubleshooting flowchart. Adapted from `/gdb-for-debugging`'s symptom-driven structure.

---

## Symptom flowchart

```
                          AUDIT RESULT LOOKS WRONG
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
       Scores too low       Scores too high      Won't converge
              │                    │                    │
              ▼                    ▼                    ▼
   Phase 4 fail-cascade?    Phase 5 too lenient?   Rubric drift?
   Phase 6 threshold off?   Theater scan missed?   Real regression?
   Bead body too thin?      Generosity bias?       Threshold too tight?
              │                    │                    │
              ▼                    ▼                    ▼
   See §"Scores low"     See §"Scores high"    See §"Won't converge"
```

> **Bootstrap aborted with "br doctor reports unhealthy state"?** First check
> whether the doctor JSON has any `checks[*].status == "fail"` or any
> `reliability_audit.anomalies[*].severity == "error"` entries. If neither —
> only `workspace_health: "degraded"` and warn-level checks (preserved
> recovery WAL artifacts in `.br_recovery/`, "Page N: never used" SQLite
> notes) — the new gate (since the v1.x bootstrap fix) lets these through.
> If you are pinned to an older bootstrap, set `BCV_REQUIRE_HEALTHY=0`
> doesn't exist — instead unblock by setting `BCV_ALLOW_DEGRADED_FAIL=1`
> only if you've manually confirmed the failures are benign, OR (preferred)
> hand off to `/fixing-beads-problems` to fix the underlying anomaly.

> **Master report shows ⚠ DETERMINISTIC-ONLY PASS banner with N false-closed
> beads?** That banner is critical: it means Phase 4/6 ran in stub mode (no
> compliance-verifier / test-depth-auditor subagent in the loop). The scorer
> WAIVED those dimensions with full credit, but a "false-closed" verdict in
> this mode is most often a Phase 3 evidence-extraction gap — NOT real
> theater. Do not reopen beads or create completion-debt off a stub-mode
> report; re-run with the real subagents wired in.

---

## Symptom: Scores systematically too low

**Quick check.** Look at one bead's scorecard. Which dimension is scored low?

| Low dimension | Likely cause | Fix |
|---------------|--------------|-----|
| Implementation (1) | spec.json has too many checklist items, OR evidence.json has too many MISSING | Re-run Phase 2 with `★ ENUMERATE` operator more carefully — was the bead body parsed correctly? |
| Tests (2) | Phase 4 verdicts are MISSING / FAIL across the board | Was the test runner reachable? Check `raw/tests.stdout`. |
| Anti-theater (3) | Many BLOCKING findings | Are they real, or false positives from the theater-scan patterns? See `FAILURE-MODES.md` per-pattern false-positive guidance. |
| Test depth (4) | Coverage at 0% across many beads | Was the coverage tool installed? Check `manifest.json#tools` for missing `cargo-llvm-cov` / `vitest --coverage` etc. |
| Docs/etc (5) | Many spec items but few citations | Was Phase 3 evidence-gather able to reach the docs? Check rg patterns. |
| Cross-bead (6) | Many synthesis findings | Did Phase 7 over-flag? Read synthesis.md cross-refs section. |

**Diagnostic command:**
```bash
# What's the score distribution?
jq '.checks[] | .verdict' "$PASS_DIR"/beads/*/compliance.json | sort | uniq -c
# If MISSING dominates → Phase 4 didn't run / no test runner
# If FAIL dominates → tests legitimately broken on HEAD
# If PASS dominates but scores low → Phase 5 anti-theater is dinging
```

---

## Symptom: Scores systematically too high

**Quick check.** Are there any false-closed flags? If 0 across N closed beads, something is off.

| Possibility | Detection | Fix |
|-------------|-----------|-----|
| Threshold too low | rubric.md `score_threshold: 500` | Raise to 700 (default) or higher |
| Phase 5 isn't running | theater.json all empty | Check `theater-scan.sh` output; ensure `anomaly-scan.sh` runs |
| Phase 6 always WAIVED | test_depth.json all WAIVED | Check spec extraction — were test types parsed correctly? |
| Cross-bead always max | synthesis.md never produces findings | Run `synthesize.py` manually; check for orphan ACs |
| Generosity bias | Same scorer agent across all beads | Run Phase 10 spot-check; if 5 random beads show > 50 deviation, the rubric is too lenient |

**Diagnostic command:**
```bash
# How many BLOCKING findings across all theater.json files?
jq '.summary.BLOCKING' "$PASS_DIR"/beads/*/theater.json | paste -sd+ | bc
# If 0 → theater scan isn't working OR project genuinely has zero theater
```

---

## Symptom: Won't converge

**Convergence requires:** delta ≤ ±10, zero new false-closed, zero new synthesis findings, rubric consistency, all remediation beads exist.

| Failing criterion | Cause | Fix |
|-------------------|-------|-----|
| max_score_delta > 10 | Real change in project code OR rubric drift | If `manifest.json#rubric_sha256` changed → that's expected; one more pass on stable rubric will converge |
| new_false_closed > 0 | Project regressed OR new beads were closed | Identify the new ones; investigate `closed_by_session` |
| new_synthesis_finding_count > 0 | Cross-bead drift introduced | Walk synthesis.md; was a bead's contract changed? |
| rubric_consistency_pass false | Phase 10 spot-check disagreed with scorer | Tighten the rubric OR retrain scorer (audit-reviewer subagent) |
| missing_remediation_beads non-empty | Prior pass's remediation didn't land | Verify `br list --status=open` includes the expected completion-debt beads |

**Convergence trace command:**
```bash
jq '.criteria' "$PASS_DIR/convergence.json"
```

---

## Phase-specific symptoms

### Phase 1: br doctor exit non-zero

Hand off to `/fixing-beads-problems`. Don't proceed.

### Phase 1: inventory.jsonl is empty

```bash
br --db .beads/*.db list --json | jq '.issues | length'
# If 0 → no closed beads; project may not be using beads yet
# If > 0 but inventory empty → script bug; check inventory-beads.sh shape detection
```

### Phase 2: spec.json missing for some beads

```bash
# Find which beads lack spec.json
for d in "$PASS_DIR"/beads/*/; do
  [ -f "$d/spec.json" ] || echo "Missing: $(basename $d)"
done
```

If extract-spec.py crashed on a bead, check its `show.json` — the bead body may have unexpected structure (custom issue_type, malformed AC).

### Phase 3: evidence.json all MISSING

Probably one of:
- `expected_path_hints` from spec.json don't match real file paths.
- Project doesn't use `git log --grep=<bead-id>` convention.
- TOUCHED_FILES is empty because git history is shallow.

```bash
git -C <PROJECT> log --all --grep="<bead-id>" | head
# If empty: closer didn't reference bead in commits
git rev-parse --is-shallow-repository
# If true: shallow clone; deepen with `git fetch --unshallow`
```

### Phase 4: every check is MISSING / ERROR

Test runner didn't run. Check:

```bash
# Is the runner installed?
command -v cargo  # or npm, pytest, go
# Is there a test config?
ls Cargo.toml package.json pytest.ini setup.cfg pyproject.toml
# Did the test command itself fail?
cat "$PASS_DIR/beads/<id>/raw/tests_unit.stdout"
```

### Phase 4: tests TIMEOUT

Either the test budget is too tight OR the test is genuinely hung. Check:

```bash
# How long did each test run?
jq '.checks[] | {id: .spec_item_id, duration_ms, verdict}' "$PASS_DIR/beads/<id>/compliance.json"
```

If duration > 10× the bead's stated budget, it's hung. Use `/gdb-for-debugging` to attach to the running test.

### Phase 5: every theater.json is empty

```bash
# Are evidence files actually being scanned?
jq '.scanned_files | length' "$PASS_DIR/beads/<id>/theater.json"
# Should match evidence.json#checks.citations count
```

If scanned_files is empty → evidence.json had no FOUND items → Phase 3 was vacuous.

### Phase 7: synthesis.md is mostly "(none)"

Possibly correct (project has no cross-bead drift). Verify by spot-checking one obvious cross-reference (e.g., "find a bead that says 'see bd-X' in its body"):

```bash
rg -l 'bd-' "$PASS_DIR/beads/"*/show.json | head
```

### Phase 8: scorecard.md missing for some beads

```bash
for d in "$PASS_DIR"/beads/*/; do
  [ -f "$d/scorecard.md" ] || echo "No scorecard: $(basename $d)"
done
```

Re-run `score-bead.py` manually on the failing one to see the error.

### Phase 9: remediation didn't act on flagged beads

```bash
# Did the FC_IDS array populate?
awk '/^## False-closed list/,/^## /' "$PASS_DIR/REPORT.md" | grep '^|'
```

If the awk shows rows but `remediation.md` is empty → the bead-id regex in `remediate.sh` is too narrow; broaden it.

### Phase 10: convergence.json says first pass

This is normal for a fresh audit dir. Convergence requires two consecutive passes.

---

## Decoding raw/ logs

Every Phase 4 check captures `raw/<test-type>.stdout` and `raw/<test-type>.stderr`. To diagnose a failing test:

```bash
RAW_DIR="$PASS_DIR/beads/<bead-id>/raw"
ls "$RAW_DIR"
# Common files: tests_unit.stdout, fuzz.stdout, coverage.json, build.stdout
cat "$RAW_DIR/tests_unit.stdout"
# Last few lines usually have the failure summary
tail -30 "$RAW_DIR/tests_unit.stdout"
```

**Coverage debugging:**
```bash
jq '.data[0].files | map(select(.summary.lines.percent < 80)) | length' "$RAW_DIR/coverage.json"
# Files below 80% line coverage
```

**Fuzz debugging:**
```bash
grep "crash\|panic\|fail" "$RAW_DIR/fuzz.stdout"
# If output, fuzzer found a crash
```

---

## The audit's own audit

Phase 10's fresh-eyes pass is the audit's audit. To debug Phase 10 itself:

```bash
# What did the fresh-eyes agent find?
jq '.criteria.generosity_flags // empty' "$PASS_DIR/convergence.json"
# Spot-check sample
jq '.criteria.spot_check_samples // empty' "$PASS_DIR/convergence.json"
```

If Phase 10 disagrees with Phase 8 on > 20% of spot-checks, run the `audit-reviewer` subagent (see `subagents/audit-reviewer.md`) on the pass — it produces a third-party review of the entire audit.

---

## Debug commands cheat-sheet

```bash
# What's in the audit dir?
find "$AUDIT_DIR" -type f | sort

# Manifest summary
jq '{mode, threshold: .score_threshold, rubric_sha256, bead_counts, phase_status, convergence}' \
  "$AUDIT_DIR/manifest.json"

# Score histogram from latest pass
PASS_DIR="$AUDIT_DIR/passes/$(ls "$AUDIT_DIR/passes" | sort | tail -1)"
for sc in "$PASS_DIR"/beads/*/scorecard.md; do
  grep -oP 'Score:\s+\K\d+' "$sc"
done | sort -n | awk '{print int($1/100)*100}' | uniq -c

# Top false-closed
sed -n '/False-closed list/,/^## /p' "$AUDIT_DIR/REPORT.md" | head -20

# Remediation status
cat "$AUDIT_DIR/remediation.md" | head -30

# Trends
tail -30 "$AUDIT_DIR/trends.md"

# Per-bead deep-dive
ID="bd-XXX"
ls "$PASS_DIR/beads/$ID/"
cat "$PASS_DIR/beads/$ID/scorecard.md"

# What changed between passes
diff -r "$AUDIT_DIR/passes/<old>/beads/$ID/" "$AUDIT_DIR/passes/<new>/beads/$ID/" | head
```

---

## Common gotchas

1. **`br doctor` exit 0 but the audit fails at Phase 1.** The HEALTHY check found a `.checks[].status == "fail"` even though the top-level `.ok` was true. Read `passes/<UTC>/doctor.json` for the failing check.

2. **Audit dir from a different br version.** `manifest.json#tools.br` shows version drift. Either rebootstrap (creates a new audit dir) or accept the version mismatch.

3. **Bead IDs with periods.** br generates ids like `bd-foo.1` for child beads. The bead-id regex includes period support; test with `[a-z][a-z0-9_.]+(-[a-z0-9_.]+)+`.

4. **Audit dir's `.git` interferes with project's `.git`.** Even though the audit dir lives INSIDE the project at `<project>/beads_compliance_audit/`, the two `.git/` directories don't see each other: bootstrap-audit.sh adds `/beads_compliance_audit/` to the project's `.gitignore` so the project's git ignores the audit subtree entirely. If you ever see audit-pass artifacts showing up in `git status` on the project, the .gitignore entry is missing — re-run bootstrap-audit.sh to restore it.

5. **CASS is unindexed; mining produces nothing.** Run `cass index --full` first; expect first index to take several minutes.

6. **`/agent-mail` reservations not released.** If parallel subagents leave stale reservations, future passes can deadlock. `release_file_reservations(...)` cleanup; or `force_release_file_reservation` if needed.

7. **Phase 4 hangs on a missing test fixture file.** Use `timeout` wrappers (already in `compliance-verifier.md` template).

---

## When to escalate

Escalate to a human (or higher-level orchestrator) when:

- Two consecutive passes have rubric inconsistency on the same beads (the rubric needs human judgment to tighten).
- A T0-fire bead has been remediated and re-scored < 700 in three subsequent passes (the AC may be unimplementable as scoped).
- The audit dir's git history shows commits made by humans (someone is editing the audit dir manually — generally bad).
- The project's `.beads/` is changing during a pass (race condition; serialize or reschedule).
- Phase 10 spot-checks disagree on > 50% of samples (the scorer subagent has drifted; retrain its prompt).

---

## When debugging the audit succeeds, document it

If you find a real bug or a real false-positive in the audit's own logic, update `FAILURE-MODES.md` and (if appropriate) the rubric. The next pass benefits.

The skill is supposed to converge — including converging on its own quality.

---

## v1.1 known issues (all FIXED in v1.1, kept here as recognition guide)

If you observe any of these symptoms, the operator probably has a stale skill checkout. The fix is to update to v1.1+ — the symptoms below are exactly what v1.1's CHANGELOG addresses.

### Symptom: every Rust bead gets a 🚨 Theater verdict on Implementation

**Recognition.** Scorecard shows Implementation ≈ 11/300 even though `evidence.json` has many FOUND items. Fixed in v1.1 by falling back to evidence-based credit when `compliance.json` is a stub pack.

**Workaround on v1.0.x:** Manually rewrite each bead's `compliance.json` with `executor: "stub-wrapper"` (the magic literal that triggers the WAIVED branch).

### Symptom: theater.json full of `return None;` flagged as `hardcoded_return MAJOR`

**Recognition.** Hundreds of `hardcoded_return` findings per bead in Rust projects. v1.0 flagged every `return None;` (idiomatic Option<T> early return) and every `return Ok(());` (idiomatic Result<()>). Fixed in v1.1 with language-aware patterns: Rust files only flag `Default::default()`.

**Workaround on v1.0.x:** Filter out hardcoded_return findings from .rs files before scoring.

### Symptom: every production sleep call is BLOCKING `sleep_as_fake_work`

**Recognition.** Lines like `thread::sleep(Duration::from_millis(50))` for retry/backoff are flagged. Fixed in v1.1 by requiring duration ≥ 1s AND no surrounding retry/backoff context. Severity also downgraded from BLOCKING to MAJOR.

**Workaround on v1.0.x:** Whitelist the sleep_as_fake_work category for projects with retry-heavy production paths.

### Symptom: `gather-evidence.sh` aborts with `jq: invalid JSON text passed to --argjson`

**Recognition.** Some beads' `evidence.json` is missing entirely; others have FOUND items with line_end=0. Cause: `wc -l < <directory>` returns nothing when a path hint resolves to a directory. Fixed in v1.1 with explicit file-vs-directory check and a `${LINES:-0}` fallback.

**Workaround on v1.0.x:** Avoid path hints that resolve to directories (use specific filenames).

### Symptom: `theater-scan.sh` fails with `Argument list too long`

**Recognition.** Scanning a bead with many cited paths (>40) crashes the final jq invocation. Fixed in v1.1 by switching to disk-backed `--slurpfile` JSONL.

**Workaround on v1.0.x:** Reduce the number of cited paths per bead by tightening Phase 3 evidence extraction.

### Symptom: `scorecard.md` line 1 is JSON envelope, line 2 is title fragment like `ns`

**Recognition.** Scorecard begins with `{"bead_id": ..., "score": ..., ...}` rather than `# Scorecard — <id>`. Cause: an operator ran `python3 score-bead.py BD > BD/scorecard.md` to capture stdout summary, but score-bead.py writes scorecard.md itself via `write_text()`. Bash's `>` truncates the file BEFORE python runs; python's `print(json.dumps(...))` lands at offset 0 of the bash-redirected fd, racing the script's own write. Fixed in v1.1 with atomic rename — bash's fd ends up pointing at an orphaned inode.

**Workaround on v1.0.x:** Don't redirect score-bead.py's stdout to scorecard.md; capture it elsewhere (`>(jq -c '.' >> summary.jsonl)`, etc.).

### Symptom: `master-report.py` REPORT.md has empty Title cells everywhere

Downstream of the scorecard.md corruption above. Once scorecards are valid, master-report's TITLE_RE matches correctly.

### Symptom: every closed bead gets `anomaly_no_git_xref` MAJOR

**Recognition.** Project uses topic-style commit messages (e.g. `feat: add foo`) without bead IDs. Every bead loses 15 anti-theater points. Fixed in v1.1: `inventory-beads.sh` writes `git_xref_coverage.json`; if < 30% of closed beads have any xref, `anomaly-scan.sh` demotes the per-bead finding from MAJOR to NOTE (project-wide convention gap rather than per-bead defect).

**Workaround on v1.0.x:** Adjust the rubric to weight anti-theater lower for projects without a bead-ID commit convention.

### Symptom: `synthesize.py` quietly audits only 500 of 1644 beads for dep anomalies

**Recognition.** `synthesis.md` says "(none)" for dep anomalies in a project that obviously has them; the footer reveals the cap. Fixed in v1.1 with a stderr warning at runtime, programmatic `synthesis_coverage.json`, and `SYNTHESIZE_MAX_PROBES` env var override.

**Workaround on v1.0.x:** Edit `MAX_PROBES` directly in `scripts/synthesize.py`.

### Symptom: `inventory-beads.sh` errors with `inventory-beads.sh: line 18: 2: pass dir`

**Recognition.** You called the script with one arg instead of two. Fixed in v1.1 with a friendly usage message.

**Workaround on v1.0.x:** Pass both `<project>` and `<pass-dir>` as positional args.