# Measurement — Per-Phase SLOs and Quality Metrics

How to know if the skill is performing well over time. Skill maintainers use these to detect regressions; users use them as a quality bar.

---

## Per-phase SLOs

| Phase | Quick (median) | Standard (median) | Comprehensive (median) |
|-------|----------------|-------------------|------------------------|
| 0 | 1 min (user input) | 1 min | 1 min |
| 1 Profile | 5 min | 10 min | 15 min |
| 2 Inventory | 3 min | 5 min | 10 min |
| 2.5 Secret scan | 1 min | 2 min | 3 min |
| 3 Bundle | 3 min | 8 min | 15 min |
| 4 Triage | 5 min | 30 min | 90 min |
| 5 Merge & confirm | 5 min (user gate) | 10 min | 20 min |
| 6 Apply moves | 10 min | 30 min | 60 min |
| 7 Apply deletes | 5 min (gate + execute) | 10 min | 20 min |
| 8 Apply gitignore | 2 min (gate + execute) | 5 min | 10 min |
| 9 Fresh-eyes | 10 min | 30 min | 90 min |
| 10 Handoff | 5 min | 5 min | 10 min |
| Total | 50 min | 2.5 h | 5.5 h |

These are budgets; under-running is fine. Over-running by >2x in any phase suggests an investigation.

---

## Quality metrics

| Metric | Target | How to measure |
|--------|--------|----------------|
| **Verdict accuracy** | ≥95% | Count Phase 5 user overrides as inverse of accuracy. <5% overrides = >95% accuracy. |
| **False-positive deletes** | 0 | Phase 9 fresh-eyes catches these; if any reach Phase 10, it's a regression. |
| **Broken references after Phase 9** | 0 | `cargo check` (or equivalent) green at Phase 10. Fresh-eyes catches these. |
| **Per-commit gate failures** | <10% | If gates fail >10% of the time, the project's gate suite is too sensitive or the skill is making bad decisions. |
| **Reference rewrite first-pass coverage** | ≥85% | Track first-grep-after-Phase-6 results: how many refs survived? Should be <15% (then a re-grep catches the rest). |
| **`.gitignore` shadowing surprises** | 0 | SHADOWING-AUDIT should never miss a tracked-file shadow at Phase 8 commit time. |
| **Bundle byte-equality verification** | 100% pass | Phase 3 must report 0 mismatches. |
| **Idempotence on clean repo** | 0 commits, 0 deletes, 0 gitignore changes | The skill should be a no-op on a clean repo. |
| **Resumability** | Re-run after Phase 6 interruption produces 0 duplicate commits | apply_log.tsv is the source of truth. |
| **Phase 2.5 sensitivity** | ≥99% recall on real secrets | A real secret in a public repo MUST be surfaced. |
| **Phase 2.5 specificity** | ≥80% precision | False-positive secret-leak halts should be rare. |

---

## Per-run report card

The skill's `polish-bar-check.sh` script outputs a report card at Phase 10:

```
Polish Bar Report — repo-janitor-2026-04-27 on /data/projects/<repo>

Dimension                                Status   Notes
1.  Recovery completeness                ✓ PASS   87/87 candidates bundled
2.  Verdict evidence                     ✓ PASS   87/87 rows have non-empty evidence
3.  No false-positive deletes            ✓ PASS   0 delete rows had inbound refs > 0
4.  No silently-broken references        ✓ PASS   0 stale refs found in Phase 9 grep
5.  Per-commit gates                     ✓ PASS   8/8 commits had passing gates
6.  .gitignore shadowing audit           ✓ PASS   5 patterns added; 0 unintended shadowing
7.  Focused commit messages              ✓ PASS   8/8 commits have categorical body
8.  Order of operations                  ✓ PASS   moves → deletes → gitignore
9.  Verbatim authorization               ✓ PASS   cleanup_authorization.txt populated
10. Idempotent on clean repo             ✓ PASS   tested via re-run
11. Resumable                            (untested)
12. Build still works                    ✓ PASS   cargo check passed
13. No secrets                           ✓ PASS   secret_findings.tsv empty
14. Audit trail intact                   ✓ PASS   all logs populated; backup ref + bundle exist

OVERALL: 13/14 PASS, 1 untested (Resumable)
```

---

## Per-phase debug logging

When `DEBUG=1` is set, each phase emits structured logs:

```
[2026-04-27T15:00:00Z] phase=2 worker=main candidates_found=87 elapsed_s=180
[2026-04-27T15:00:01Z] phase=2 worker=main reference_graph_built=87
[2026-04-27T15:01:00Z] phase=2.5 worker=leak-scanner suspects=0 leaks=0 elapsed_s=60
[2026-04-27T15:05:00Z] phase=3 worker=bundle-builder copies=87 verifications=87 mismatches=0 elapsed_s=240
[2026-04-27T15:35:00Z] phase=4 worker=triage-worker-A batch=001 candidates=29 verdicts=29 elapsed_s=1800
...
```

These logs feed into `<workspace>/run_metrics.jsonl` for cross-run analysis.

---

## Cross-run analysis

After 5+ runs against different repos, the skill maintainer can answer:

1. **Which smell categories have the highest false-positive delete rates?** Adjust the smell rules.
2. **Which archetype detection is wrong most often?** Improve detection heuristics.
3. **Where does Phase 9 fresh-eyes typically find new findings (vs. Phase 1's catches)?** Promote those checks earlier.
4. **What's the typical reference-rewrite first-pass coverage?** If consistently <85%, the REFERENCE-GREP grep-include list needs widening.
5. **What are the most common Phase 5 user overrides?** Patterns of override = patterns of skill weakness.

The Phase 11 user-lens review formalizes some of this; cross-run analysis aggregates it.
