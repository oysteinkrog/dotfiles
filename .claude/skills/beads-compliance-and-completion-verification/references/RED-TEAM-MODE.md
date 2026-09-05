# RED-TEAM-MODE.md — Adversarially probe the audit itself

The audit's job is to make the bead graph truthful. Red-team mode's job is to make the *audit* truthful — to find the cheap fakes a savvy closer could ship that would still pass review.

> **Premise:** every defense becomes a target. The audit catches stubs and mocks-where-forbidden today; tomorrow a closer learns the patterns and routes around them. Red-team mode pre-discovers those routes so the rubric tightens BEFORE production teaches us the lesson.

This doc is the playbook for `subagents/red-team-adversary.md`.

---

## When to invoke

- **Comprehensive mode** — always (it's part of the deal).
- **Standard mode** — opt-in if `audit-policy.yaml#subagents.red-team-adversary: true`.
- **Tripwire mode** — never (autonomous tripwire shouldn't write rubric patches).
- **After a real false-closed bead is found** — always run a red-team pass to seed the rubric with the new attack vector.
- **After a major rubric change** — always (the change might have opened new gaps).
- **Quarterly hygiene** — recommended, even if the audit is healthy.

---

## Attack catalog (the seed list)

The subagent considers each attack against the current rubric and reports which would still succeed. This is the seed; mature projects extend it from CASS history.

### Coverage attacks

| Attack | What it does | Default detection |
|---|---|---|
| **Coverage-via-import** | A test that imports every module so coverage hits 100%, but assertions are absent. | Phase 6 should require non-trivial assertion density (≥ 1 assert per 30 LoC of test code) — codify in rubric. |
| **Coverage of dead branches** | Tests exercise branches that are unreachable in production (guarded by an env var nobody sets). | Anti-pattern; flag dead-branch coverage by intersecting coverage with reachability analysis. |
| **Branch-flip in test only** | Production has `if rare_case` returning unimplemented; test sets `rare_case=False` so the branch is never taken. | Cross-reference: every branch in production must have ≥ 1 test that takes BOTH sides. |

### Test-presence attacks

| Attack | What it does | Default detection |
|---|---|---|
| **Test that asserts only `true`** | Caught by current `theater-scan.sh`. Variant: `assert(2+2 == 4)`. | Add specific pattern: trivially-true assertions (constants only). |
| **Test that always returns early** | `if (env.SKIP) return;` then `SKIP=1` in CI. | Flag conditional `return` / `skip` near the top of test functions. |
| **`#[ignore]` re-introduced after merge** | Bead closed with the test enabled; subsequent commit re-adds `#[ignore]` claiming flakiness. | Cross-pass diff: any added `#[ignore]` against an audited bead's tests → flag. |
| **Test in a directory not run by CI** | Test exists, would pass, but `cargo test --test ignored_dir/*` is never invoked. | Phase 4 must compute the union of tests CI runs and tests the bead claims; mismatch → flag. |

### Anti-theater bypass

| Attack | What it does | Default detection |
|---|---|---|
| **Replace `unimplemented!()` with `panic!("...")`** | Same effect; theater-scan keyword regex misses panic with arbitrary string. | Add: `panic!\(.*not\s*(implemented\|done\|wired)` to scan; also flag `panic!()` in production paths from beads tagged feature/api. |
| **Stub disguised as helper** | Function `compute_charge` returns `Decimal::zero()`. Looks like real code. | Need flow analysis: function body that ignores all inputs and returns a constant → flag. |
| **Side-channel via env var** | Real implementation behind `os.getenv('REAL_IMPL')`; tests don't set it; only prod does. | Flag: branching on env vars in non-config paths. |

### Status / metadata attacks

| Attack | What it does | Default detection |
|---|---|---|
| **Future-dated `closed_at`** | Set `closed_at` to 2099 so time-to-close anomaly check sees a "long" close. | Bound `closed_at` to ≤ now — flag future timestamps. |
| **Apologetic close that says "actually shipped"** | Long, sincere close reason that mentions tests + commits but doesn't link them. | The anomaly-scan already flags apologies; tighten by requiring file:line citations in long close reasons. |
| **Batch-close masked by sleep-between-closes** | Closer adds `sleep 30` between each close to dodge the batch-close detector. | Add: closes by same agent within same session window (transcript timestamps), not just wall-clock between closes. |

### Citation attacks

| Attack | What it does | Default detection |
|---|---|---|
| **Citation salting** | Pad `evidence.json` with citations to *unrelated* files so the citation-density check passes. | Require: each cited file:line range must contain at least one identifier from the spec's checklist (function/struct names). |
| **Stale-commit citation** | Cite a commit SHA that's old; the file at that SHA had the implementation, but it was reverted later. | `git log --follow` the cited file:line; if the line was deleted before the audit pass, the citation is stale. |

### Migration attacks

| Attack | What it does | Default detection |
|---|---|---|
| **Reverse-migration spoof** | Reverse migration is syntactically valid but logically a no-op. | Migration-safety reviewer must EXECUTE the reverse against a clone and assert state diff. |
| **Backfill with `LIMIT 100`** | Spec says "backfill all rows"; impl backfills 100 then exits cleanly. | Require: post-migration `COUNT(*) WHERE backfill_marker IS NULL` = 0. |

### Performance attacks

| Attack | What it does | Default detection |
|---|---|---|
| **Bench in `--release` only** | `cargo bench` builds `--release`; meanwhile production has different feature flags. | Bench harness must use the same feature-flag set as production. |
| **Single-sample bench** | Reports "p95 = X ms" from 1 run. | Performance-auditor enforces n_samples ≥ 30 for percentile metrics. |

### CASS / historical-evidence attacks

| Attack | What it does | Default detection |
|---|---|---|
| **CASS poisoning** | Salt prior session quotes with phrases that look like project-specific theater patterns to skew the rubric. | CASS pattern miner must require ≥ 2 verbatim quotes from ≥ 2 sessions per pattern. |

---

## Output: `audit_resilience.json`

```json
{
  "computed_at": "2026-05-06T15:00:00Z",
  "auditor": "red-team-adversary",
  "rubric_sha256": "abc123…",
  "attacks_attempted": 18,
  "attacks_that_would_succeed": 4,
  "attacks": [
    {
      "id": "RA-007",
      "name": "Coverage-via-import",
      "premise": "test imports every module; assertion density < 1/30 LoC; coverage hits 92%",
      "fixture_path": "fixtures/RA-007/",
      "would_score": "880 (false positive)",
      "rubric_patch": "Phase 6: enforce assertion-density floor; cite test_depth.json#assertion_density",
      "patch_severity": "BLOCKING"
    }
  ]
}
```

---

## Closing the loop

Red-team output is **input** to the rubric-tuning agent (Phase 10 senior reviewer). The patches it proposes are *recommendations*; the rubric is updated through the standard tuning process (do not tune mid-pass — `☖ STAKE-RUBRIC` operator).

After patches land:

1. The next pass should re-run red-team and verify the patched attacks no longer succeed.
2. The fixture under `fixtures/RA-NN/` becomes a regression test for the patch — if a future rubric change breaks the patch, the fixture catches it.

This is "audit-of-audit-of-audit": the discipline that makes the skill *itself* converge.
