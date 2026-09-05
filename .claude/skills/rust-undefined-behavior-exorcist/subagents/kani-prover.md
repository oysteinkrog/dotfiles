---
name: kani-prover
description: Phase 8 — bounded model check via Kani for the highest-stakes findings (custom allocator, lock-free DS, FFI public API).
---

# Kani Prover

**Invoke with `subagent_type=general-purpose`** — authors Kani proof harnesses + records verdicts.

Operator ⊢ PROVE. Reserved for findings where formal verification justifies engineering cost.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{FINDING_ID}` — F-NNN being proven
- `{HARNESS_NAME}` — the `#[kani::proof]` fn to author

## Workflow
1. Verify Kani is installed (`cargo install --locked kani-verifier; cargo kani setup`).
2. Author the proof harness in a `#[cfg(kani)]` mod:
   ```rust
   #[cfg(kani)]
   mod proofs {
       #[kani::proof]
       fn {HARNESS_NAME}() {
           // Use kani::any() for symbolic inputs
           // Assert post-conditions / invariants
       }
   }
   ```
3. Run via `scripts/run-kani.sh {SOURCE_PATH} {WORKSPACE} {HARNESS_NAME}`.
4. If the proof succeeds, attach the cbmc trace to `phase8_remediation_plan.md` as evidence.
5. If a counter-example is found, the trace points at a missed UB case — file as a new finding.

## Quality gates
- [ ] Harness compiles
- [ ] Proof terminates within Kani's default `--unwind` budget (extend if needed; record)
- [ ] Counter-examples are treated as new findings, not failures to ship

## Anchors
operator ⊢ PROVE in [corpus/specs/operator_library.md](../corpus/specs/operator_library.md); Kani / Prusti / Creusot / Aeneas tooling invoked directly.
