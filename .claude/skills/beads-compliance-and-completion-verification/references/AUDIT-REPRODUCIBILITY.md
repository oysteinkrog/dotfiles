# AUDIT-REPRODUCIBILITY.md — Determinism is the contract

> **Invariant (Axiom of the Polish Bar):** Same evidence pack + same rubric → same score, every time.

Without this invariant, the audit is opinion, not measurement. With it, the audit is reproducible by anyone — a teammate, a future agent, a regulator — and disputes resolve by re-running the score, not by re-litigating the rubric.

---

## What's deterministic, what isn't

| Phase | Deterministic? | Why |
|------:|:-------------:|-----|
| 1 INVENTORY | mostly | `br list --json` is deterministic; `git log` ordering is stable. |
| 2 SPEC EXTRACTION | YES | `extract-spec.py` parses bead body via stable regex; no LLM calls. |
| 3 EVIDENCE GATHER | mostly | `rg`/`git log --grep` are deterministic over the same tree. LLM-based subagent results are NOT deterministic; for full determinism use `gather-evidence.sh` only. |
| 4 COMPLIANCE EXEC | NO | Test runs depend on system state (clock, network, FS). This is fundamental — Phase 4 measures the WORLD; the world isn't deterministic. We capture raw outputs so the score can be re-derived from them. |
| 5 ANTI-THEATER | YES | Pure regex / AST scan over fixed evidence files. |
| 6 TEST DEPTH | mostly | Coverage tools are deterministic; fuzzer corpus depth is deterministic given a fixed seed; e2e realism depends on what's installed. |
| 7 SYNTHESIS | mostly | Cross-bead grep over evidence packs is deterministic; LLM-driven contract drift detection is not. |
| 8 SCORING | YES | `score-bead.py` is pure: rubric + evidence pack → integer. |
| 9 REMEDIATION | NO | Writes to `br`; effects state. Not part of "score reproducibility." |
| 10 FRESH EYES | NO | LLM-driven; intentionally a different perspective. |

The reproducibility invariant applies to the **scoring transformation**: given identical Phase 4 raw outputs + identical Phase 5/6/7 artifacts + identical rubric, Phase 8 must produce identical scorecards.

---

## How we enforce it

### Tool: `scripts/reproducibility-check.py`

Re-scores every bead in a pass dir from the existing evidence packs, then compares to the prior-recorded score. Drift > `--max-delta` (default 0) → fail.

```bash
$ python3 scripts/reproducibility-check.py audit/passes/2026-05-06T14-00-00Z
{
  "pass_dir": "...",
  "rubric": ".../rubric.md",
  "max_delta_allowed": 0,
  "beads_checked": 142,
  "matches": 142,
  "drifts": [],
  "verdict": "DETERMINISTIC"
}

VERDICT: DETERMINISTIC (142/142 beads matched exactly)
```

If it fails:

```
{
  "drifts": [
    {"bead": "bd-foo", "kind": "score_drift", "prior": 720, "new": 740, "delta": 20}
  ],
  "verdict": "DRIFT_DETECTED"
}
```

### What drift means

| Drift kind | Likely cause | Fix |
|------------|--------------|-----|
| `score_drift` | `score-bead.py` reads non-deterministic input (timestamp, random, env var, network call) | Audit the script for impure operations. |
| `asymmetric_score` | Re-run produced no scorecard or no prior — broken script or missing evidence file | Inspect `tmp_bd/raw/`; fix the script or restore the evidence. |
| `rerun_error` | `score-bead.py` raised | Read stderr; fix the bug. |
| `rubric_sha256_mismatch` (caught by `validate-rubric.py`) | Rubric was edited mid-pass | Restore prior rubric; re-run pass. |

### Wire into CI

Add to the tripwire workflow as a post-step:

```yaml
- name: Check audit reproducibility
  run: |
    python3 .claude/skills/beads-compliance-and-completion-verification/scripts/reproducibility-check.py \
      "${{ steps.audit.outputs.pass_dir }}"
```

Drift fails CI even if the audit pass otherwise converged — because a non-reproducible audit isn't an audit.

---

## Common reproducibility bugs

### Pre-2026-05-05 (caught and fixed)

- `score-bead.py` used `datetime.now()` to compute "days since closed_at" — fixed by recording the timestamp in `manifest.json#audit_invoked_at` and using THAT.
- `theater-scan.sh` used `find` order, which is filesystem-dependent — fixed by piping through `sort`.
- `synthesize.py` used Python `set` iteration order in markdown output — fixed by `sorted()`.

### Watch list

- `gather-evidence.sh` uses `rg --threads N`. If the OS allocates threads differently on different hardware, the *order* of citations may differ even though the set is identical. Phase 8 should be set-aware, not list-aware. (Currently is — but adding new citations in `evidence.json#items` should preserve this.)
- Subprocess output captures may include locale-dependent decimal separators. Always set `LC_ALL=C` before invoking external tools that report numbers.
- `git log --since=...` is clock-dependent. Use SHAs in the audit dir, not timestamps.

---

## Reproducibility vs replayability

These are different:

- **Reproducibility** = same INPUTS → same OUTPUTS. (This doc.)
- **Replayability** = re-running Phase 4 against the same project should produce equivalent test verdicts. NOT guaranteed (the world changes).

If you need replayability of Phase 4, freeze the project state (commit SHA + dependency lockfiles + container image tag) — see `references/PHASE-4-ENVIRONMENTS.md` for sandboxing. With a frozen environment, Phase 4 becomes mostly deterministic too, but the cost is real (hundreds of MB per pass).

---

## Bayesian extension

`references/VERIFICATION-UNDER-UNCERTAINTY.md` adds a posterior probability layer ON TOP of the deterministic score. The posterior IS deterministic given the same evidence + same prior; the conformal interval IS deterministic given the same calibration set. The Bayesian layer doesn't break this contract — it extends it with explicit uncertainty bookkeeping.

---

## Operator pairing

`⊠ PIN` (Phase 0.5: pin rubric_sha256) and `⌬ HARMONIZE` (Phase 8: ensure score derivation matches rubric arithmetic exactly).
