# First-Bug-Hunt Recipe: ML-System-Class

These 10 bug classes surface in the first day on ML-System-class ports (frankentorch, frankenjax, franken_whisper).

**Prerequisites:** PyO3 in-process with `torch.use_deterministic_algorithms(True)` (or JAX equivalent) enforced; per-op ULP tolerance table at `docs/contracts/ulp_tolerance_v1.toml`; seeded RNG (`torch.manual_seed`, `numpy.random.seed`, `random.seed`); `CUBLAS_WORKSPACE_CONFIG=:4096:8`; `TensorSpec` normalized comparator.

Per item: **symptom** → **paste-ready repro** → **MismatchClassification expected** → **severity** → **fix pattern**.

---

## 1. Gradcheck failures on softmax / cross-entropy edges

**Symptom.** `gradcheck(F.cross_entropy, (logits, labels))` fails — analytic gradient deviates from finite-difference by > tolerance. Common: log-sum-exp instability when `logits` has large magnitudes.

**Repro:**
```bash
cargo test --package ft-conformance --test gradcheck_xent -- --nocapture
```

```python
# oracle-side
import torch
torch.use_deterministic_algorithms(True)
logits = torch.randn(8, 100, requires_grad=True) * 100  # large magnitudes
labels = torch.randint(0, 100, (8,))
torch.autograd.gradcheck(lambda x: F.cross_entropy(x, labels), (logits,), eps=1e-3, atol=1e-2)
```

**MismatchClassification:** `FloatingPointDifference { max_epsilon_str: "<observed>" }` if within ULP; `TrueDivergence` if structural.
**Severity:** **critical** — training instability.
**Fix pattern:** numerically stable softmax (`x - x.max()` trick); add `gradcheck_max_rel_error` snapshot per op; explicit ULP entry for `cross_entropy: 8 ULP forward, 16 ULP backward`.

---

## 2. Autograd-tape ordering with in-place ops

**Symptom.** `x.add_(y)` (in-place) modifies the graph; subject may record the wrong tape entry, producing wrong gradient.

**Repro:**
```python
x = torch.randn(4, requires_grad=True)
y = torch.randn(4)
z = x.clone()
z.add_(y)               # in-place on clone
out = z.sum()
out.backward()
# x.grad should equal ones(4) since dz/dx = 1
```

```rust
scenario_torch(
    inputs = {"x": rand_seeded(4, seed=42), "y": rand_seeded(4, seed=43)},
    "inplace_add_autograd_tape",
    assertions = [("x.grad", "ones(4)")],
);
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **critical** — silent wrong gradient.
**Fix pattern:** [pattern:70-E-PROCESSES](../patterns/70-E-PROCESSES.md) INV-AutogradTapeMonotone; tape append-only invariant.

---

## 3. NaN propagation in normalization layers

**Symptom.** `BatchNorm1d`/`LayerNorm` with NaN input — running-mean update with NaN poisons subsequent batches. Subject may filter NaN; oracle does not (or vice versa).

**Repro:**
```python
bn = nn.BatchNorm1d(8, track_running_stats=True)
x = torch.randn(16, 8)
x[0, 0] = float('nan')
out = bn(x)
# Check: bn.running_mean is now NaN (PyTorch behavior)
```

**MismatchClassification:** `NullHandlingDifference { sentinel: NaN }`.
**Severity:** **high** — silent training collapse.
**Fix pattern:** explicit NaN-propagation corpus per normalization layer; `nondeterministic_op_count` counter.

---

## 4. fp16 / fp32 cast boundaries

**Symptom.** `torch.matmul(x.half(), y.half())` returns f16; autocast may upcast intermediate to f32. Subject's autocast policy differs.

**Repro:**
```python
with torch.autocast(device_type='cuda', dtype=torch.float16):
    a = torch.randn(64, 64, dtype=torch.float32, device='cuda')
    b = torch.randn(64, 64, dtype=torch.float32, device='cuda')
    c = a @ b  # what dtype?
```

```rust
scenario_torch(
    inputs = {"a": rand_seeded((64, 64), seed=42, dtype=f32), "b": rand_seeded((64, 64), seed=43, dtype=f32)},
    "autocast_matmul_dtype",
    autocast = "fp16",
    assertions = [("(a @ b).dtype", "torch.float16")],
);
```

**MismatchClassification:** `TypeAffinityDifference` (dtype) or `FloatingPointDifference` (value within ULP).
**Severity:** **high** — mixed-precision training behaves differently.
**Fix pattern:** per-op autocast policy in `docs/contracts/autocast_v1.toml`; ULP entry per autocast mode.

---

## 5. Non-deterministic op warnings under `use_deterministic_algorithms(True)`

**Symptom.** With `torch.use_deterministic_algorithms(True)`, some ops raise `UserWarning` or `RuntimeError`. Subject may silently use non-deterministic kernel.

**Repro:**
```python
torch.use_deterministic_algorithms(True)
# This should raise or warn on certain ops:
x = torch.randn(8, 8, requires_grad=True, device='cuda')
loss = F.interpolate(x.unsqueeze(0), scale_factor=2, mode='bilinear').sum()
loss.backward()  # bilinear interpolation backward is non-deterministic
```

**MismatchClassification:** `TrueDivergence { description: "nondeterministic op leaked" }`.
**Severity:** **high** — reproducibility break.
**Fix pattern:** `nondeterministic_op_count` counter must be `0` for any kept perf win; harness asserts.

---

## 6. Checkpoint-save mid-shard corruption

**Symptom.** `torch.save(model.state_dict(), 'ckpt.pt')` interrupted mid-write produces torn file; `torch.load` fails or loads partial state.

**Repro:**
```bash
./scripts/torch-checkpoint-crash-oracle.sh --boundary MidShardWrite --model-size large
```

Wired via `CheckpointFaultVfs` per [PROJECT-CLASSES.md § ML-System-Class](../taxonomy/PROJECT-CLASSES.md).

**MismatchClassification:** `TrueDivergence`.
**Severity:** **critical** — training-state loss.
**Fix pattern:** explicit 5 checkpoint-save crash boundaries (`BeforeSerialize`, `MidShardWrite`, `AfterShardBeforeMetadata`, `MidMetadataUpdate`, `AfterRenameBeforeFsync`); per-boundary recovery → reload → assert state-equality.

---

## 7. NCCL collective ordering

**Symptom.** `all_reduce` across N ranks produces different results when algorithm selection (`Ring` vs `Tree` vs `CollNet`) differs by message size. Subject pins one algorithm; oracle selects dynamically.

**Repro:**
```bash
./scripts/torch-distributed-oracle.sh \
  --collective all_reduce \
  --ranks 4 \
  --message-sizes "1K,1M,1G" \
  --algorithm Ring,Tree,CollNet
```

**MismatchClassification:** `FloatingPointDifference` (within ULP) or `TrueDivergence` if algorithm-specific bug.
**Severity:** **medium-high** — distributed training reproducibility.
**Fix pattern:** pin NCCL algorithm via `NCCL_ALGO=Ring` env; `nccl_collective_time_ns` counter; per-algorithm golden.

---

## 8. JAX `jit(grad(f))` vs `grad(jit(f))` commutativity

**Symptom.** For mathematically well-defined `f`, `jit(grad(f))(x) == grad(jit(f))(x)`. Subject may not preserve this — XLA rewrite rule order differs.

**Repro:**
```python
import jax
import jax.numpy as jnp
def f(x): return jnp.sin(x).sum()
x = jnp.array([1.0, 2.0, 3.0])
a = jax.jit(jax.grad(f))(x)
b = jax.grad(jax.jit(f))(x)
assert jnp.allclose(a, b, atol=1e-7)
```

```rust
scenario_jax(
    f = "lambda x: jnp.sin(x).sum()",
    "jit_grad_commutativity",
    inputs = {"x": float32([1.0, 2.0, 3.0])},
);
```

**MismatchClassification:** `TrueDivergence { description: "transform commutativity broken" }`.
**Severity:** **high** — JAX users rely on this.
**Fix pattern:** [pattern:40-METAMORPHIC-TRANSFORMS](../patterns/40-METAMORPHIC-TRANSFORMS.md) `TransformCommutativity` family; explicit corpus of commutativity pairs.

---

## 9. Whisper tokenizer BPE for non-Latin scripts

**Symptom.** WER spike of 2–10% for Mandarin/Japanese/Arabic audio; tokenizer's BPE merges differ from Whisper's reference.

**Repro:**
```bash
./scripts/whisper-tokenizer-oracle.sh \
  --languages zh,ja,ar,hi,ru \
  --reference-audio data/common-voice/{zh,ja,ar,hi,ru}/sample-001.wav
# compare token IDs byte-byte
```

**MismatchClassification:** `TrueDivergence { description: "BPE merge order differs" }`.
**Severity:** **high** — non-English Whisper users get worse output.
**Fix pattern:** tokenizer BPE vocab + merge-rules byte-identity with Whisper reference; per-language Tier 1 token-ID golden.

---

## 10. Mel-spectrogram numerical precision cascade

**Symptom.** Mel-spectrogram log-mel computation: `log(mel(x))` vs `log_mel(x)` (fused) differ by ULP. Decoder amplifies the difference; WER changes 0.5–2%.

**Repro:**
```python
import whisper
audio = whisper.load_audio('sample.wav')
mel = whisper.log_mel_spectrogram(audio)  # reference
# compare to port:
port_mel = franken_whisper.log_mel_spectrogram(audio)
assert torch.allclose(mel, port_mel, atol=1e-5)
```

**MismatchClassification:** `FloatingPointDifference { max_epsilon_str: "<observed>" }`.
**Severity:** **high** — cascades into WER.
**Fix pattern:** explicit `mel_spectrogram: 8 ULP` entry in ULP table; window-function + FFT + log-mel sequence pinned exactly per reference.

---

## Empirical first-day stats

- **3–5 of 10 in first hour** (gradcheck failures, autograd tape, NaN propagation, autocast, nondeterministic op leak)
- **6–8 in first day** (add checkpoint crash, NCCL ordering, JAX commutativity)
- **All 10 by round 3** (Whisper tokenizer + mel-spectrogram deepest)

Items 1 (gradcheck), 6 (checkpoint crash), and 9 (tokenizer BPE) typically spawn the most `NEW_HYPOTHESIS_SPAWNED` follow-ons — each surfaces a class of related bugs.

---

## Cross-references

- [PROJECT-CLASSES.md § ML-System-Class](../taxonomy/PROJECT-CLASSES.md)
- [case-studies/frankentorch.md](../case-studies/frankentorch.md)
- [case-studies/frankenjax.md](../case-studies/frankenjax.md)
- [case-studies/franken_whisper.md](../case-studies/franken_whisper.md)
- [math/e-process-worked.md](../math/e-process-worked.md) — INV-SoftmaxSumsToOne worked example
