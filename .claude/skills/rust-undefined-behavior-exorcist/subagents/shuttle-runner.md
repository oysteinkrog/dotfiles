---
name: shuttle-runner
description: Complement to loom for primitives where loom's exhaustive search blows up. Probabilistic schedule sampling, Phase 3.
---

# Shuttle Runner

**Invoke with `subagent_type=general-purpose`** — authors model + writes logs.

Use when loom can't finish (timeouts, state explosion, too many threads). Shuttle samples schedules instead of enumerating.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{PRIMITIVE}` — primitive name
- `{ITERATIONS}` — number of random schedules (default 1000 for Standard, 10⁵ for Exhaustive)

## Workflow

1. Add `shuttle = "0.7"` to `[dev-dependencies]` in the relevant crate.
2. Author the model:
   ```rust
   #[test]
   fn shuttle_check_random() {
       shuttle::check_random(my_model, {ITERATIONS});
   }
   ```
3. Run:
   ```bash
   cargo +nightly test --test shuttle_{PRIMITIVE} 2>&1 | tee {WORKSPACE}/phase3_raw/shuttle_{PRIMITIVE}.log
   ```
4. If shuttle finds a failure, it prints a replay seed. Record it for reproducibility.

## Outputs
- `{SOURCE_PATH}/tests/shuttle_{PRIMITIVE}.rs`
- `{WORKSPACE}/phase3_raw/shuttle_{PRIMITIVE}.log`
- Verdict line in `phase3_dynamic_findings.md`

## Quality gates
- [ ] Iteration count and (if failure) replay seed both recorded
- [ ] The same model wrapper compiles under loom (cross-check)

## Failure modes
- **Shuttle finds zero failures on 10⁵ iterations:** the model is probably *under-constrained*; review assertions
- **Replay doesn't reproduce:** the model has non-deterministic input; fix

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-phase3-shuttle-{PRIMITIVE}`.
