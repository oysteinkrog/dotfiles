# Case Study: FrankenTorch — `/dp/frankentorch`

ML-class port with the deepest numerical-correctness surface in the family. PyTorch oracle is live; what's missing is the per-op ULP tolerance table, determinism-as-test-invariant, and the formal `TensorSpec` comparator.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | ML-System-class ([PROJECT-CLASSES.md § ML-System-Class](../taxonomy/PROJECT-CLASSES.md)) |
| **Tier** | **T4 — Platform** with GPU-dependence overlay (+1 effective tier). Crates: `ft-api`, `ft-autograd`, `ft-conformance`, `ft-core`, `ft-data`, `ft-device`, `ft-dispatch`, `ft-kernel-cpu`, `ft-nn`, `ft-optim`, `ft-runtime`, `ft-serialize` |
| **Recommended mode** | `gauntlet-full` — first formalization pass; subsequent runs `incremental-rebase` for nightly drift, `harden-pillar conformance` after a kernel-fusion landing |
| **Reference pinning** | `docs/contracts/torch_version_contract.toml` to be created at `torch-2.X.Y` (pick the LTS available on rch workers); contract must include CUDA version, cuDNN version, NCCL version, NVIDIA driver version, and `CUBLAS_WORKSPACE_CONFIG=:4096:8` policy |
| **README claims summary** | "Rust re-implementation of PyTorch with `aten::`-level op parity and per-op ULP-tolerant numerical agreement." Recent activity (commit `5c1c03f` closing `ft-tf10` for `tensor_addcmul`/`tensor_addcdiv`) shows op-by-op parity is the workhorse loop. |

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance | ✅ | Live PyTorch oracle; bead-driven per-op coverage |
| Negative ledger | ⚠️ implicit | Kernel-fusion experiments, memory-format changes, allocator pooling discussed in commits and chat; no central record |
| cass | ✅ | wired |
| Agent Mail | ✅ | wired |
| bv | ✅ | wired |
| Math layer (§75–76) | ⚠️ partial | Gradient checking via finite differences; autograd JVP/VJP consistency; **no e-process invariants** for "softmax sums to 1.0"; **no BOCPD** for kernel-time regime detection |
| MT-scale harness | ⚠️ distributed only | Multi-GPU/multi-rank workloads via NCCL collectives + rendezvous; **no `mt_mvcc_bench` analog** because PyTorch hot paths are GPU kernel launches |
| RaptorQ | ❌ | not applicable |
| `TensorSpec { shape, dtype, device, requires_grad, data_hash }` comparator | ❌ | per-op ad-hoc tolerances |
| Per-op ULP tolerance table (`ulp_tolerance_v1.toml`) | ❌ | each op uses ad-hoc tolerances; brittle |
| `torch.use_deterministic_algorithms(True)` as cargo-test invariant | ❌ | optional; should be a harness-enforced default |
| `determinism_default_guard.txt` per artifact lane | ❌ | analogue of `concurrent_mode_default_guard.txt` |
| `CheckpointFaultVfs` for save/load fault injection | ❌ | no equivalent |
| 5 checkpoint-save + 2 distributed-collective crash boundaries | ❌ | not enumerated |
| `comprehensive_bench.rs` equivalent | ❌ | per-op microbenchmarks scattered; no weighted-category structure |
| Metamorphic transform-equivalence tests | ❌ | absent |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** Per-op microbenchmarks exist on a per-bead basis. GPU profiling story is the right one (NVTX + nsys + `kernel_launch_time_ns`), distinct from CPU-side flamegraph. No weighted-category aggregate score. No pass-over-pass ratchet. `aten_dispatch_time_ns` likely exposed but not all hot-path counters from MINING-3 §23.6 are.

**First 3 gaps:**
1. **No `.bench-history/comprehensive_bench.latest.json` with the ML-class weights** (`Elementwise 0.15 / Reductions 0.10 / MatMul 0.20 / Conv 0.10 / Attention 0.10 / Normalization 0.05 / Optimizer 0.10 / Autograd 0.10 / DataPipeline 0.05 / nn_Modules 0.05`). Every perf claim is unprovable across versions.
2. **`memcpy_h2d_bytes` / `memcpy_d2h_bytes` not exposed as counters** — H2D/D2H bandwidth is the dominant non-compute cost for small-tensor kernels; without the counter, a kernel-fusion change appears free even when it pushes work to D2H.
3. **`jit_cache_{hits,misses}` not measured** — TorchScript/torch.compile-style caching has self-time impact at first-call; cold-start vs warm-cache ratios are not separable.

### (b) Conformance — current state + first 3 gaps

**Current state.** Live PyTorch oracle via PyO3; per-op parity beads close as ops land. The recent `ft-tf10` (`tensor_addcmul`/`tensor_addcdiv`) is canonical — file the bead, implement the op, verify against PyTorch, close. But — tolerance per op is set in the test, not in a contract; `torch.use_deterministic_algorithms(True)` is optional; metamorphic transform tests don't exist.

**First 3 gaps:**
1. **Tolerance set in test body, not contract.** A `1e-6` rtol in test_addcmul.rs is invisible to the contract-aware certifier. First-pass review: ≥40 ops have in-test tolerances that should live in `ulp_tolerance_v1.toml`.
2. **Determinism flags not enforced at harness entry.** A test that forgets `torch.use_deterministic_algorithms(True)` can pass against a non-deterministic PyTorch kernel and "agree" by coincidence. First-pass: detect with `nondeterministic_op_count` counter; many fail.
3. **No `gradcheck` for newly-added ops.** `tensor_addcmul` has a backward; `gradcheck_max_rel_error` snapshot likely absent. Differential gradient check (analytic vs finite-difference) against PyTorch's `torch.autograd.gradcheck` is missing.

### (c) Surface — current state + first 3 gaps

**Current state.** `ft-api` surface exposes the aten-level dispatch table. Implemented ops are tracked in beads. No formal FeatureUniverse with weights × per-op `present|partial|missing|n/a|excluded`.

**First 3 gaps:**
1. **`torch.nn.functional` enumerated separately from `torch.Tensor.*` methods** — many ops are accessible at both surfaces; without canonical IDs, double-counting is likely.
2. **Quantization ops (`torch.quantization`, `aten::_q_*`) likely `excluded` collectively** — strict-100% claim is hollow.
3. **Sparse tensor surface (`torch.sparse_coo`, `torch.sparse_csr`)** partial; type-system implications (sparse × dense matmul fallback path) need explicit `partial` classification.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankentorch /dp/frankentorch__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: torch-2.X.Y + CUDA/cuDNN/NCCL identities
# - oracle mode: PyO3 in-process PyTorch; deterministic algorithms and CUBLAS config pinned
# - GPU workers: required for full baseline and soak
# - perf weights: Elementwise=0.15, Reductions=0.10, MatMul=0.20, Conv=0.10,
#   Attention=0.10, Normalization=0.05, Optimizer=0.10, Autograd=0.10,
#   DataPipeline=0.05, nn_Modules=0.05
# - failure terms: kernel-fusion broke gradient, memory-format change altered ULP,
#   allocator-pool churn, autograd-tape shortcut broke higher-order,
#   NCCL collective non-deterministic, JIT cache key collision, gradcheck failed,
#   nondeterministic op leaked

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankentorch /dp/frankentorch__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 120
```

Wall time T4+ × `gauntlet-full`: **30–60 days.** GPU resources mandatory for soak; multi-model triangulation mandatory on Phase 14.

---

## 5. Expected Pillar Findings

### Performance
1. **`memcpy_h2d_bytes` saturating small-batch inference** — fusing kernels increases H2D unless the data is staged.
2. **`autograd_tape_append_time_ns` non-negligible** for small operators — `requires_grad=True` paths have measurable per-op overhead.
3. **`kernel_launch_time_ns` dominates for batch=1 inference** — kernel-launch-fusion candidate.
4. **`jit_cache_misses` spike** on first-call paths — cache warming missing in benches.
5. **`cuda_stream_sync_time_ns` measurable** on benchmark teardown — sync-outside-timed-window discipline.
6. **`nccl_collective_time_ns` non-deterministic** — algorithm selection (Ring vs Tree) varies by message size; pin via env.
7. **DataLoader `num_workers` not documented** in bench reports — worker count affects throughput by 2×+.
8. **F16/BF16 matmul tolerance loose** — using f32 atol/rtol on f16 outputs hides 100×-ULP errors.

### Conformance
1. **`gradcheck` failures on `softmax` + `cross_entropy` edges** — log-sum-exp instability.
2. **Autograd-tape ordering changes with in-place ops** (`x.add_(y)` vs `x = x + y`) — subtle topological order differences.
3. **NaN propagation in `BatchNorm` / `LayerNorm`** — running-mean update with NaN input differs.
4. **`F.dropout` deterministic mode** with seeded RNG — RNG state advance differs from PyTorch.
5. **`Conv2d` padding-mode edges** (`'reflect'`, `'replicate'`, `'circular'`) — boundary computation drift.
6. **Optimizer `step()` state-dict key set** — Adam/AdamW `exp_avg_sq` vs `exp_avg` ordering.
7. **`F.interpolate` `align_corners=False` for `'bilinear'`** — known floating-point corner.
8. **`bf16 → f32` cast boundary** in mixed-precision training — autocast rules subtle.
9. **`torch.save` / `torch.load` with mid-shard NCCL drop** — checkpoint torn-write recovery.
10. **`torch.compile`-equivalent JIT key collision** — schema-hash vs input-shape-hash cache key bug (pattern 10 lesson).

### Surface
1. **`torch.func` (functional vmap/grad) likely partial-present** but classified `present`.
2. **`torch.distributed.rpc` likely `excluded` collectively**.
3. **CUDA Graph capture (`torch.cuda.graph`) likely missing**.
4. **Per-aten-op `.default` vs `.out` vs `.out_mode` variants** under-enumerated.
5. **`torch.utils.checkpoint` (gradient checkpointing)** state machine partial.

---

## 6. Patterns to Apply First

1. **Per-op ULP tolerance table as `docs/contracts/ulp_tolerance_v1.toml`** — see [PROJECT-CLASSES.md § ML-System-Class § Per-op tolerance table](../taxonomy/PROJECT-CLASSES.md). One row per `aten::` op with default + exceptions; `softmax: 8 ULP`, `log: 16 ULP`, matmul: `4 ULP f32`.
2. **[pattern:05-SUBJECT-ORACLE-COMPARATOR](../patterns/05-SUBJECT-ORACLE-COMPARATOR.md)** — `TensorSpec { shape, dtype, device, requires_grad, data_hash }` normalized type.
3. **[pattern:180-NEGATIVE-LEDGER](../patterns/180-NEGATIVE-LEDGER.md)** — `docs/progress/perf-negative-results.md` with the verbatim header; mine 90 days of chat/commits to seed initial entries.
4. **`determinism_default_guard.txt` per artifact lane** — analogue of `concurrent_mode_default_guard.txt`; embeds `TORCH_USE_DETERMINISTIC_ALGORITHMS=true`, `CUBLAS_WORKSPACE_CONFIG=:4096:8`, `CUDNN_DETERMINISTIC=1`, `CUDA_DEVICE_COUNT=<n>`, git SHA, timestamp.
5. **[pattern:70-E-PROCESSES](../patterns/70-E-PROCESSES.md)** — INV-SoftmaxSumsToOne (hardware-enforced `p₀=1e-9` since fp arithmetic is deterministic under fixed kernel), INV-GradientNormBounded (software `p₀=1e-6`), INV-AutogradTapeMonotone (hardware).

---

## 7. Estimated Rounds to Convergence

**12–18 rounds.** Distributed coordination + GPU determinism + per-op ULP variability conspire to surface findings deep into the loop. Each new dtype × shape × device combination is a new attack surface; cross-platform soak (CPU + CUDA, optionally Metal) typically reveals 2–4 new findings per platform.

---

## 8. Risk Register

1. **CUDA driver / cuDNN version drift across `rch` worker pool.** Determinism flags don't always pin reliably across driver versions. *Mitigation:* `oracle-preflight-doctor.sh` checks driver + cuDNN + NCCL on every worker; refuse to certify if any worker disagrees.
2. **`torch.use_deterministic_algorithms(True)` does NOT cover all ops.** Some ops will raise `UserWarning` (caught by `nondeterministic_op_count`); some will silently use non-deterministic kernels. *Mitigation:* harness asserts `nondeterministic_op_count == 0` for every kept perf win.
3. **Mixed-precision (autocast) interacts with tolerance table.** A `f16 matmul` in autocast context produces f32 output; tolerance must be looked up by *kernel-actually-used*, not requested dtype. *Mitigation:* tolerance lookup keyed on `(op, kernel_variant, input_dtype, output_dtype)`.

---

## 9. What Ships from Convergence

`certification_bundle/`:
- `confidence_gate.json`, `verification_contract.json`, `release_certificate.json` (per universal floor)
- `ulp_tolerance_compliance.json` — per-op observed ULP vs tolerated
- `gradcheck_compliance.json` — per-op `gradcheck_max_rel_error`
- `checkpoint_roundtrip.json` — `torch.save` / `torch.load` byte-identity proof
- `distributed_collective_proof.json` — NCCL determinism proof
- `nondeterministic_op_count.json` — must be 0 for every kept lane

Plus `FINAL_GAUNTLET_REPORT.md`, `PARITY_RUNBOOK.md`, `RELEASE_CERTIFICATION_TEMPLATE.md`, and bead graph.

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § FrankenTorch](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § ML-System-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/ml-system-class.md](../first-bug-hunt/ml-system-class.md)
- [math/conformal-band-worked.md](../math/conformal-band-worked.md) — applies to per-op pass-rate aggregation
