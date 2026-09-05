# Case Study: FrankenJAX — `/dp/frankenjax`

The most combinatorially-exploded conformance surface in the family. Transform composition (jit × grad × vmap × pmap × shard_map × ...) creates a matrix where every cell is a distinct correctness contract. JAX oracle exists implicitly; foundational discipline is absent.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | ML-System-class ([PROJECT-CLASSES.md § ML-System-Class](../taxonomy/PROJECT-CLASSES.md)) |
| **Tier** | **T3 — Workspace borderline T4** (compile-time-codegen + numerical-determinism overlays effectively bump to T4 for those features). Crates: `fj-ad`, `fj-api`, `fj-backend-cpu`, `fj-backend-gpu`, `fj-cache`, `fj-conformance`, `fj-core`, `fj-dispatch`, `fj-egraph`, `fj-ffi`, `fj-interpreters`, `fj-lax`, `fj-ledger`, `fj-py`, `fj-runtime`, `fj-test-utils`, `fj-trace` |
| **Recommended mode** | `gauntlet-full` — first proper application |
| **Reference pinning** | `docs/contracts/jax_version_contract.toml` to be created at `jax-0.4.Y`; preflight verifies `jax.__version__`, `jax.devices()` reports CPU/GPU as expected, `jax.config.update("jax_enable_x64", True)` is the default, `XLA_FLAGS=--xla_gpu_deterministic_ops=true` set |
| **README claims summary** | "JAX primitive + transform parity in Rust; jaxpr-level oracle." Recent commits (`bbad67f7`, `bd0e02c0`) show property-sweep parity for Sqrt/Exp/Log dtype variants — the per-primitive-dtype matrix is the active workhorse. |

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance | ✅ implicit | passes JAX oracle for primitives + transforms; **no formal differential-V2-style envelope** |
| Negative ledger | ❌ | absent |
| cass | ⚠️ | partial |
| Agent Mail | ⚠️ | partial |
| bv | ⚠️ | partial |
| Math layer (§75–76) | ❌ | absent |
| MT-scale harness | ❌ | absent |
| RaptorQ | ❌ | not applicable |
| `TensorSpec` analog | ⚠️ | implicit via jaxpr; not formalized |
| `EngineIdentity` discriminator | ❌ | risk of oracle-on-oracle false greens |
| Per-primitive ULP tolerance table | ❌ | per-test tolerances |
| Crash-boundary enumeration | ❌ | not enumerated |
| Trace Transform Ledger | ✅ | jaxpr IR comparison exists |
| `comprehensive_bench.rs` analog | ❌ | per-primitive benches present; no weighted aggregate |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** Per-primitive benches exist. XLA compilation cost (cold vs warm) is implicit. Transform-composition cost (e.g., `vmap(jit(grad(f)))`) not measured at the gauntlet level.

**First 3 gaps:**
1. **`xla_compile_time_ns` not exposed as counter** — JIT compilation is the dominant cold-start cost; without the counter, "fast" and "compiled" benchmarks are indistinguishable.
2. **`tracer_construct_time_ns` invisible** — tracer construction is sensitive to abstract-value cache hits; regressions here are large but invisible without instrumentation.
3. **`primitive_dispatch_count` per-transform-stack not reported** — under `vmap(jit(grad(f)))`, the inner primitive count differs from the outer; without per-layer counts, an inadvertent un-rolling shows as "slow" with no root cause.

### (b) Conformance — current state + first 3 gaps

**Current state.** Implicit oracle parity via live JAX; jaxpr IR comparison exists; transform-stack signatures captured. Per-primitive parity exercised via property sweeps (recent Sqrt/Exp/Log dtype sweep is canonical). But — no `EngineIdentity` discriminator; no `ExecutionEnvelope` with `artifact_id`; no MismatchClassification.

**First 3 gaps:**
1. **`jit(grad(f)) == grad(jit(f))` not always tested as metamorphic relation.** Where this commutativity holds (mathematically well-defined cases), the property is invariant; where it doesn't (e.g., functions with traced control flow), the failure to commute IS the contract. First-pass enumeration likely reveals 5–10 untested invariant pairs.
2. **Transform-cache key collisions.** Two different traced functions with the same input shape + dtype may collide in a cache keyed on insufficient information; surfaces as "incorrect compiled result for a function we've never run". Cass-mining for "trace cache" terms would surface historical instances.
3. **Higher-order gradient correctness.** `grad(grad(f))` (Hessian) and `vmap(grad(grad(f)))` (per-sample Hessian) typically break first when an AD shortcut is wrong-but-undetected at first-order.

### (c) Surface — current state + first 3 gaps

**Current state.** `fj-api` enumerates implemented primitives. `fj-lax` is the lax API surface. Transform stack (jit/grad/vmap/pmap/shard_map) variants implemented progressively.

**First 3 gaps:**
1. **`pjit` + `shard_map` likely partial** — distributed/sharded execution surface usually behind primitive surface.
2. **`jax.experimental.*` modules** likely `excluded` collectively.
3. **Custom primitive definition API (`jax.core.Primitive`, `jax.interpreters.ad`)** — extension surface usually under-enumerated.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankenjax /dp/frankenjax__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: jax-0.4.Y
# - oracle mode: PyO3 in-process JAX; x64 and deterministic XLA flags pinned
# - perf weights: PrimitiveEval=0.25, ADForward=0.15, ADReverse=0.15,
#   TransformCompose=0.20, XlaCompile=0.10, VmapPmap=0.10, Sharding=0.05
# - conformance floor: TensorSpec comparator + JAXPR diff + PyTree-aware comparator
# - failure terms: traced incorrectly, jit cache miss spike, transform unrolled wrong,
#   e-graph rewrite rejected, AD shortcut numerically wrong, transform cache key collision,
#   pjit partition mismatch, shard_map ordering wrong

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankenjax /dp/frankenjax__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 96
```

Wall time T3+ × `gauntlet-full`: **21–45 days.** `rch`-offload recommended.

---

## 5. Expected Pillar Findings

### Performance
1. **XLA compile time scales super-linearly with jaxpr size** — quadratic in trace length on some passes.
2. **`vmap` unrolls when batch dim is small** — `vmap(f, batch=1)` may unroll to scalar code; perf cliff at batch=2.
3. **`jit` cache fills with shape-specialized variants** — long-running training loops with varying shapes evict the cache; `jit_cache_misses` spike.
4. **`grad(grad(f))` constructs the jaxpr twice when it could memoize** — known JAX inefficiency; the port may have inherited it.
5. **Transform stack depth ≥3 has measurable dispatch overhead** — `vmap(jit(grad(f)))` dispatches through 3 transform layers per primitive call.
6. **`pjit` partitioning recomputed per call** when sharding spec unchanged — caching opportunity.
7. **E-graph rewrite pass cost not amortized** — every `jit` compile re-runs e-graph; result is deterministic but expensive.

### Conformance
1. **`jit(grad(f))` ≠ `grad(jit(f))` for `f` with traced control flow** — JAX itself handles this; the port may not.
2. **`vmap(grad(f))` axis-broadcasting edge** — when `f` has reductions, axis-handling subtle.
3. **Higher-order grad with `custom_vjp`** — second-order through custom rule is a common bug class.
4. **`pmap` vs `pjit` partial-result aggregation** — `psum` ordering across devices.
5. **`jax.random.split` determinism** — RNG key splitting must be byte-identical to JAX.
6. **`scan` carry-state correctness under `vmap`** — vmap-over-scan vs scan-over-vmap.
7. **`while_loop` with traced condition** — concrete vs abstract bool handling.
8. **Mixed f32/f64 promotion** — under `jax_enable_x64=True` vs `False`.
9. **Float-precision flags** (`jax.config.update("jax_default_matmul_precision", "highest")`) — must be pinned.
10. **`jax.experimental.host_callback` semantics** — likely partial/excluded.

### Surface
1. **`jax.numpy` vs `numpy` API gap** — surface coverage typically partial.
2. **`jax.lax` primitive set** — completeness varies.
3. **`jax.nn` module** — typically partial.
4. **PyTree registration API** — third-party extensibility surface.
5. **`jax.export` (serialization)** — typically excluded.

---

## 6. Patterns to Apply First

1. **Entire FrankenSQLite floor** — `oracle.rs`, `differential_v2.rs`, `ratchet_policy.rs`, `failure_bundle.rs`, `e2e_log_schema.rs`, `comprehensive_bench.rs`, `.bench-history/<primary_bench>.latest.json`, AGENTS.md mandate paragraph. See [methodology/CASE-STUDIES.md § FrankenJAX](../methodology/CASE-STUDIES.md).
2. **JAX-specific `ExecutionEnvelope`** — `(primitive, jaxpr signature, transform stack, expected output shape/dtype)` keyed on `artifact_id = SHA-256 of canonical JSON excluding run_id`.
3. **Per-primitive ULP tolerance table** — similar to FrankenTorch but at the JAXPR level; per-primitive default + per-dtype overrides.
4. **[pattern:40-METAMORPHIC-TRANSFORMS](../patterns/40-METAMORPHIC-TRANSFORMS.md)** — JAX-specific TransformFamily: `TransformCommutativity` (`jit(grad(f)) ≡ grad(jit(f))` where defined), `TransformAssociativity` (`vmap(vmap(f)) ≡ vmap(f, in_axes=(0,0))`), `TransformIdentity` (`jit(f)(x) ≡ f(x)`).
5. **[pattern:70-E-PROCESSES](../patterns/70-E-PROCESSES.md)** — INV-JIT-Determinism ("same input → same jaxpr regardless of trace history", hardware-enforced), INV-EgraphRewriteSound (software-enforced), INV-TransformCacheKeyComplete (software).

---

## 7. Estimated Rounds to Convergence

**15–25 rounds.** The transform composition matrix is exponential in stack depth. Each round typically closes one "transform-pair commutativity" gap and surfaces 1–2 more. Convergence is later than other ML-class siblings.

---

## 8. Risk Register

1. **JAX version churn.** JAX moves quickly; pinning to `0.4.Y` requires accepting that `0.4.(Y+1)` may invalidate some traces. *Mitigation:* `migration` mode is the only path forward.
2. **GPU determinism flags don't always pin reliably** across CUDA driver / XLA version combinations. *Mitigation:* preflight verifies; multi-host soak surfaces divergence.
3. **PyTree registration cache poisoning.** Custom PyTrees registered in one test can leak into another; isolation requires per-test interpreter teardown. *Mitigation:* PyO3 GIL discipline + per-test scope.

---

## 9. What Ships from Convergence

`certification_bundle/`:
- Universal floor
- `ulp_tolerance_compliance.json` per primitive
- `transform_commutativity_proof.json` — every tested commutativity pair
- `jaxpr_diff_compliance.json` — per-function jaxpr byte-identity (Tier-1) where possible
- `xla_compile_determinism.json` — repeated compile produces byte-identical HLO

Plus standard triple + bead graph.

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § FrankenJAX](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § ML-System-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/ml-system-class.md](../first-bug-hunt/ml-system-class.md)
- [case-studies/frankentorch.md](frankentorch.md) — sibling ML-class for tolerance-table inheritance
