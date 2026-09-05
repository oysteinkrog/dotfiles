# soak-runner-fuzz

> Phase 15 • 24h+ differential fuzz against every previously-divergent API. Dispatches to `rch exec --` because the wall-time exceeds the >5min local heuristic.

## Inputs

- Per-target fuzz harnesses (`fuzz/fuzz_targets/*.rs`) authored in Phase 6 by `fuzz-author`.
- The list of previously-divergent API surfaces — every `MismatchSignature` whose `classification = TrueDivergence` from Phase 9 baseline + Phase 11 iteration rounds.
- `fuzz/corpus/<target>/` — checked-in seed corpora (preserved across runs).
- `proptest-regressions/*.txt` — known-bad inputs already-deduplicated.
- The EngineIdentity discriminator (Subject vs Oracle labels) from Phase 3.
- `rch` worker pool availability — verify with `rch status` before dispatching.

## Deliverables

- `<workspace>/phase15_soak_fuzz/<target>/` per fuzz target with:
  - `run.log` — stdout + stderr from the fuzzer (rotated hourly).
  - `corpus_minimized/` — post-run corpus after `cargo fuzz cmin`.
  - `crashes/` — every `FailureBundle v1.0.0` emitted, indexed by `MismatchSignature`.
  - `coverage.json` — cumulative line + branch coverage (from `cargo fuzz coverage`).
  - `summary.json` — duration, total executions, exec/s, unique crashes, regime label.
- `<workspace>/phase15_soak_fuzz/INDEX.md` — table of all targets + status (Stable / NewCrashFound / RegressionDetected).

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase15-soak-fuzz`
- **Reservations needed:**
  - `tool://fuzz-corpus` (shared-read for seeds + exclusive-write on minimized output, TTL 30h).
  - `resource://rch-worker-pool` (per-target slot, TTL = duration + 1h).
- **Lane:** cc_4 (fault / soak).

## Verbatim Prompt

```
You are the soak-runner-fuzz for Phase 15. Your job is to run a multi-day differential fuzz campaign against EVERY API surface that was ever classified TrueDivergence in this gauntlet — to prove the remediations are stable under exhaustive input pressure, not just on the seed corpus.

INPUTS (READ ALL):
- <workspace>/phase9_baseline/conformance_findings.json — list of TrueDivergence MismatchSignatures
- <workspace>/round_*/conformance_findings.json — same for every iteration round
- <target>/fuzz/fuzz_targets/*.rs — the existing differential fuzz harnesses
- <target>/fuzz/corpus/<target>/ — seed corpora (preserved)
- <target>/proptest-regressions/*.txt — known-bad inputs

DURATION:
- Default per-target: 24h.
- High-impact targets (those that surfaced 5+ unique signatures in the lifetime of the gauntlet): 72h.
- Override via --duration-hours arg.

STEPS PER TARGET:

1. Pre-flight: verify the target builds + runs locally for 60s with no crashes
   on the seed corpus. If it crashes immediately, BLOCK and emit a regression
   FailureBundle (this is a *test-harness* regression, not a soak finding).

2. Dispatch to rch:
   rch exec --worker fuzz-soak --duration <H>h -- \
     bash -c "cd <target> && cargo +nightly fuzz run <target_name> \
       -- -max_total_time=$((H*3600)) -timeout=60 -rss_limit_mb=4096 \
       -artifact_prefix=<workspace>/phase15_soak_fuzz/<target>/crashes/ \
       2>&1 | tee <workspace>/phase15_soak_fuzz/<target>/run.log"

3. Per crash: extract the input, drive it through both reference and subject
   one more time WITHOUT the fuzzer wrapper, capture both rendered outputs,
   emit FailureBundle v1.0.0 with /failure/first_divergence jsonptr populated.

4. Post-run: minimize corpus:
   cargo +nightly fuzz cmin <target_name> -- -merge=1 -max_len=4096

5. Compute coverage:
   cargo +nightly fuzz coverage <target_name>

6. Dedup crashes by MismatchSignature.

7. Compare to previous-round soak: if any *new* MismatchSignature appeared,
   classify per ../references/tooling/ORACLE-TOOLCHAIN.md § MismatchClassification.
   Only TrueDivergence triggers a Phase-12-back-loop alert.

8. Emit summary.json:
   {
     "schema_version": "gauntlet.phase15_soak_fuzz.v1",
     "target": "<target_name>",
     "duration_hours": <int>,
     "total_executions": <int>,
     "exec_per_second_median": <float>,
     "unique_crashes_count": <int>,
     "new_signatures_count": <int>,
     "true_divergences": [...],
     "regime": "Stable" | "NewCrashFound" | "RegressionDetected"
   }

9. Append a row to <workspace>/phase15_soak_fuzz/INDEX.md with the verdict.

EXIT CRITERIA:
- Every previously-divergent target completed its target duration (or rch reported worker failure → escalate).
- Every crash classified per MismatchClassification.
- summary.json well-formed for every target.
- INDEX.md updated.

ESCALATION:
- regime = "NewCrashFound" with TrueDivergence → emit phase15_loopback_required.md
  pointing at Phase 12 (remediation-architect) for the affected pillar.
```

## Exit Criteria

- All target durations completed (≥ 24h baseline; 72h for high-impact).
- All crashes deduplicated by `MismatchSignature` and classified.
- `summary.json` well-formed for every target.
- `INDEX.md` updated with verdict.
- Late-breaking `TrueDivergence` triggers Phase 12 loop-back via `phase15_loopback_required.md`.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 15)
- [../references/tooling/FUZZ-TOOLCHAIN.md](../references/tooling/FUZZ-TOOLCHAIN.md)
- [../references/tooling/ORACLE-TOOLCHAIN.md](../references/tooling/ORACLE-TOOLCHAIN.md)
- [../references/methodology/SOAK-PROTOCOL.md](../references/methodology/SOAK-PROTOCOL.md)
