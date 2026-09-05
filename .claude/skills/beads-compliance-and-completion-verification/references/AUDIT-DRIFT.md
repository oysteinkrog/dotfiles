# AUDIT-DRIFT.md — When the audit's own quality is the regression

The skill catches false-closed beads. But what catches a false-clean audit — a pass that says "everything is fine" when in fact the audit's *own* rigor has slipped?

This is "audit-of-audit" at the time-series scale. Phase 10 catches single-pass inconsistency; this doc is about cross-pass quality drift.

---

## Symptoms of audit drift

| Symptom | What it usually means |
|---------|------------------------|
| False-closed count drops over consecutive passes despite no remediation merging | Rubric softened (intentional?) OR scorer became more generous |
| Score median climbs without remediation | Same |
| Phase 5 BLOCKING findings drop while Phase 4 PASS rate climbs | Theater scan is missing patterns the project actually uses now |
| Convergence reached suspiciously fast (1-2 passes for a new project) | Rubric is too loose for this project's complexity |
| Pass-over-pass scorecard deltas are universally tiny (< 5 points) on every bead | Rubric is insensitive — too coarse to detect changes |
| Newly-claimed beads in spec-quality-gate score consistently high | Either authors got better OR the gate's heuristics softened |
| Red-team adversary's success rate trends up | Rubric isn't keeping pace with attack patterns |
| Same agent's false-closed rate trends down dramatically | Could be improvement OR could be that the audit no longer catches their style |

None of these is conclusive alone. Stack them with provenance to discriminate.

---

## Quantitative drift signals

### `scripts/dashboard.py` extension

Add a "Drift Watch" panel that overlays:

- **Score-band proportions over time** — if the % of beads in 🟢 950-1000 grows monotonically over 12 weeks, the rubric is loosening (or the project is improving consistently — disambiguate with Phase 5 findings count).
- **Theater finding density per evidence file** — should be roughly constant if the catalog covers the project; trending down without rubric tightening = drift.
- **Convergence delta over time** — should plateau then stay constant; if it shrinks every pass, the audit is converging on a moving target.
- **Phase 10 disagreement rate** — fresh-eyes review catches consistency; if rate drops to ~0% across many passes, the reviewer may have over-fit to the scorer.

### `scripts/drift-check.py` (shipped — see `--help` for full options)

```bash
$ python3 scripts/drift-check.py audit-dir --window 8
{
  "window_passes": 8,
  "drift_signals": [
    {"name": "score_median_trend", "value": "+22 pts/pass", "threshold": "+5", "verdict": "DRIFTING"},
    {"name": "phase_5_blocking_density", "value": "-0.4/file/pass", "threshold": "-0.1", "verdict": "DRIFTING"}
  ],
  "verdict": "DRIFT_DETECTED",
  "recommended_action": "run red-team-adversary; tighten rubric; re-baseline"
}
```

The script is documented here but is a follow-up bead in the skill's own backlog.

---

## Causes (in order of frequency)

### 1. Catalog rot

The default `references/FAILURE-MODES.md` catalog covers ~30 patterns. Real projects develop new patterns over time (new languages, new frameworks, new agents). If `cass-pattern-miner` doesn't run regularly, the project-specific block in `rubric.md` ages out of relevance.

**Fix:** Re-run cass-pattern-miner quarterly even on mature projects. Rotate stale patterns out (no hits in 60 days).

### 2. Rubric softened to reduce friction

Someone tweaked weights to make daily tripwire less alarmist. The intent was usability; the effect is loss of signal.

**Fix:** Treat weight changes as bead-author deltas — record in CHANGELOG.md. `validate-rubric.py` flags weight-sum-not-1000 errors but doesn't flag intentional re-weighting; cross-pass diff of `rubric.md` is the audit trail.

### 3. Scorer prompt drift

If the scoring subagent's prompt evolves over time (engineer A clarifies a wording, engineer B "improves" an edge case), the LLM's calibration shifts. `score-bead.py` is deterministic, so this only applies if the *prompts inside* its data flows have changed.

**Fix:** Treat subagent prompt files (`subagents/*.md`) as part of the rubric — their SHA goes into `manifest.json#prompt_shas` and `validate-audit-dir.py` flags drift.

### 4. Compliance check stubbing

Phase 4 stubs (`compliance-verifier` subagent didn't run; `wrapper` left empty `compliance.json`) accumulate; the scorer treats absence-of-failure as PASS. Over 5 passes, every bead's compliance dimension drifts toward max.

**Fix:** Phase 4 verdict accounting must distinguish PASS from MISSING. `validate-evidence.py` already enforces this; fail loudly when a pass has > 10% MISSING checks.

### 5. Re-verification false-cache

Differential auditing skips beads whose evidence files didn't change. But if a bead's *runtime behavior* changed (a dep upgrade silently broke it), the evidence file SHA matches but the test would now FAIL. False cached PASS.

**Fix:** Periodically invalidate the cache (every Nth pass, every release, every manual trigger). Don't trust differential audit forever.

---

## Drift detection wired into the workflow

```
Every pass:                Every Nth pass (default N=10):     On any release:
  - validate-audit-dir.py   - drift-check.py                   - red-team-adversary
  - validate-rubric.py      - cass-pattern-miner               - rubric_sha256 freeze gate
  - reproducibility-check   - full Phase 4 cache invalidation  - committee-mode for Phase 4/5
```

`audit-policy.yaml` controls the cadence:

```yaml
drift_check:
  every_n_passes: 10
  red_team_on_release: true
  cache_invalidation_n_passes: 10
  cass_remine_days: 90
```

---

## Anti-patterns

- **Treating a smooth, monotonic improvement curve as proof the project is healthy.** Reality is jagged. Suspicious smoothness is drift.
- **Disabling Phase 10 because "the rubric is stable now."** The whole point of Phase 10 is catching the moment it stops being stable.
- **Skipping cass-pattern-miner because "we already mined patterns 6 months ago."** Patterns evolve; mining is recurring maintenance.
- **Ignoring the red-team's increasing success rate.** That's the canary — listen.

---

## Operator pairing

`⟳ REPEAT-UNTIL-QUIET` (multi-pass discipline) and `⊘ SELF-POLICE` (Phase 10's role); add the explicit drift-check operator `⌗ DRIFT-CHECK` (Phase 10.5, recurring not per-pass) on the calendar.

This is the closest the skill gets to a meta-meta level — the audit-of-the-audit-of-the-audit. Useful precisely because the alternative is silent rot.
