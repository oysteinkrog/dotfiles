# ML-System-class Adoption Checklist

For ports in the ML-System class (frankentorch, frankenjax, franken_whisper).

## Phase 0 — Workspace
- [ ] `<workspace>/` git-init'd
- [ ] `docs/contracts/<ref>_version_contract.toml` pins (e.g., `torch=2.1.2`)
- [ ] `[reference.extras]`: `cuda_version`, `cudnn_version`, `driver_version`, `determinism_flags=["torch.use_deterministic_algorithms(True)"]`, `dtype_policy`, `rng_seed_policy`
- [ ] PyO3 + `tch`/`burn-tch` deps

## Phase 3 — Oracle wiring
- [ ] PyO3 in-process bridge
- [ ] Determinism flags pinned: `torch.use_deterministic_algorithms(True)`, `torch.backends.cudnn.deterministic=True`, `torch.backends.cudnn.benchmark=False`, `CUBLAS_WORKSPACE_CONFIG=:4096:8`
- [ ] `TensorSpec { shape, dtype, device, requires_grad, data_hash }` normalized comparator
- [ ] **Per-op ULP tolerance table** in `docs/contracts/ulp_tolerance_v1.toml` (defaults: 4 ULP f32 matmul, 2 ULP elementwise)
- [ ] **`gradcheck_max_rel_error` as a `cargo test` invariant** (via `scripts/gradcheck.sh`)
- [ ] EngineIdentity strict-distinct (`<port>` vs `torch-oracle` / `jax-oracle`)
- [ ] Oracle preflight: PyTorch version + CUDA/cuDNN/driver fingerprint + determinism flags + dtype policy + RNG seed policy + model corpus hashes

## Phase 4 — Golden capture
- [ ] Tensor input/output bundles
- [ ] Gradient bundles (autograd-chain captured + replayed)
- [ ] state_dict fixtures
- [ ] Model corpus: at least one transformer block + one CNN + one RNN
- [ ] (JAX) PyTree-aware fixture canonicalization

## Phase 5 — Performance
- [ ] Operator microbenches per op family (matmul, conv, attention, layernorm, softmax)
- [ ] fwd-only / fwd+back / optimizer-step axes
- [ ] Distributed-collective bench (all-reduce / all-gather / reduce-scatter)
- [ ] `release-perf` profile
- [ ] `cuda_device_guard.txt` analog of concurrent_mode_default_guard
- [ ] HotPath counters: `aten_dispatch_time_ns, autograd_tape_append_time_ns, kernel_launch_time_ns, memcpy_h2d_bytes, memcpy_d2h_bytes, jit_cache_{hits,misses}, nccl_collective_time_ns, cuda_stream_sync_time_ns, gradcheck_max_rel_error, nondeterministic_op_count`

## Phase 6 — Conformance
- [ ] Oracle E2E per op-class: dtype promotion, broadcasting, gradient accumulation, autograd chain, device placement, memory format, NaN/Inf propagation
- [ ] Differential V2 with `TensorSpec` canonicalization
- [ ] Metamorphic transforms: `jit(grad(f))(x) ≡ grad(jit(f))(x)`, `vmap`-equivalence, transpose-roundtrip
- [ ] Per-op ULP tolerance verified per call; `FloatingPointPrecision[ULP=N]` EquivalenceExpectation
- [ ] CheckpointFaultVfs: partial `torch.save`, mid-shard NCCL drops, `CUDA_ERROR_LAUNCH_FAILED` mid-collective
- [ ] **5 checkpoint-save crash boundaries**: BeforeSerialize, MidShardWrite, AfterShardBeforeMetadata, MidMetadataUpdate, AfterRenameBeforeFsync
- [ ] **2 distributed-collective crash boundaries**: MidAllReduce, BeforeRendezvousAck
- [ ] Differential fuzz: `arbitrary` TensorSpec generator → both engines
- [ ] E-processes: softmax-sum-to-1.0-within-ε, autograd-JVP-matches-VJP-within-ε, deterministic-ops-warning-rate

## Phase 7 — Surface
- [ ] FeatureUniverse covers every `torch.__all__` entry (or jax primitive catalog, or whisper public-API)
- [ ] (JAX) primitive catalog: 118 primitives, 113 VJP+JVP coverage
- [ ] Per-op classification: `present | partial | missing | n/a | excluded` with ULP tolerance per partial

## Phase 8 — Negative ledger
- [ ] AGENTS.md mandate with ML-class failure terms: `kernel fusion changes, memory format changes, allocator pooling, graph capture, autograd tape shortcuts, AD shortcuts breaking higher-order gradients`

## Class-specific extras
- [ ] **frankentorch**: "Absolute parity doctrine"; per-op ULP table (gold standard)
- [ ] **frankenjax**: 113/113 VJP+JVP; 861 oracle fixtures; PyTree-aware comparator; `jit(grad(f)) ≡ grad(jit(f))` metamorphic
- [ ] **franken_whisper**: speech recognition with frankentorch-shape parity; per-audio-fixture transcript equivalence
- [ ] CUDA/cuDNN/driver fingerprint baked into every artifact
