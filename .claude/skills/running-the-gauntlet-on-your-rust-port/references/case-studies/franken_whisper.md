# Case Study: franken_whisper — `/dp/franken_whisper`

The audio-tolerance + tokenizer-edge + FrankenTorch-shape-parity class. ASR is fundamentally lossy and tolerance-bound; the discipline of per-op ULP + per-output WER tolerance is the central engineering challenge.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | ML-System-class with audio + tokenizer + WER-tolerance overlays ([PROJECT-CLASSES.md § ML-System-Class](../taxonomy/PROJECT-CLASSES.md)) |
| **Tier** | **T3 — Workspace** with numerical-determinism overlay |
| **Recommended mode** | `gauntlet-full` (first proper application) — "Day 1" of bootstrapping per [SIBLING-PROJECTS-STATUS.md § franken_whisper](../exemplars/SIBLING-PROJECTS-STATUS.md) |
| **Reference pinning** | `docs/contracts/whisper_version_contract.toml`: OpenAI Whisper Python reference (commit or pip version), model weights SHA-256 per size (tiny/base/small/medium/large), tokenizer version (BPE vocab hash) |
| **README claims summary** | Rust Whisper inference with per-op ULP + per-output WER tolerance vs OpenAI reference. Recent activity (commits `a3b4d4e`, `770221c`, `eede00a`) shows storage durability tightening + CHANGELOG/README catchup after the upstream fsqlite MVCC fix — Whisper port depends on FrankenSQLite for storage. |

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance | ❌ | "Day 1" status |
| Negative ledger | ❌ | absent |
| cass | ⚠️ partial | |
| Agent Mail | ⚠️ partial | |
| bv | ⚠️ partial | |
| Math layer (§75–76) | ❌ | absent |
| MT-scale harness | ❌ | absent (single-inference) |
| RaptorQ | ❌ | inherited from fsqlite if used for model storage |
| Audio fixture corpus | ⚠️ | partial; per-language/accent/noise classification informal |
| Per-op ULP tolerance table | ❌ | inherits Torch's if/when frankentorch lands one |
| Per-output WER tolerance | ❌ | not formalized |
| Tokenizer golden | ⚠️ | partial; multilingual edges uncovered |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** Per-model inference benches likely exist (RTF — real-time-factor). No aggregate.

**First 3 gaps:**
1. **No RTF (real-time factor) primary score** per model-size × audio-length × language matrix.
2. **No `mel_spectrogram_time_ns` / `attention_time_ns` / `decoder_step_time_ns` hot-path counters** — per-phase attribution missing.
3. **Beam search candidate count** not measured — beam width × heuristic interaction with quality/speed tradeoff invisible.

### (b) Conformance — current state + first 3 gaps

**Current state.** Audio fixtures exist; output WER vs reference checked ad-hoc.

**First 3 gaps:**
1. **Tokenizer BPE for non-Latin scripts** — port's tokenizer may differ from Whisper's BPE for low-resource languages; surfaces as WER spike on non-English audio.
2. **Mel-spectrogram numerical precision** — window-function + FFT + log-mel ordering may differ by ULP; cascades through all decoder steps.
3. **Beam search tie-breaking** — when two candidates have equal score, ordering determines output; not in contract.

### (c) Surface — current state + first 3 gaps

**First 3 gaps:**
1. **Model size coverage** — tiny/base/small/medium/large/large-v2/large-v3 — per-model `present|partial|missing|excluded`.
2. **Language coverage** — 99 languages in Whisper; per-language `present|partial`.
3. **Task surface** — `transcribe` vs `translate` vs `language detection` — per-task partial.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/franken_whisper /dp/franken_whisper__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: whisper-20240930 + model corpus hashes
# - oracle mode: PyO3 in-process OpenAI Whisper
# - perf weights: MelSpectrogram=0.10, Encoder=0.30, Decoder=0.40,
#   Tokenizer=0.10, BeamSearch=0.10
# - conformance floor: TensorSpec comparator, ULP table, WER tolerance,
#   per-language/per-accent/per-noise audio corpus
# - failure terms: mel-spectrogram drift, attention NaN, decoder loop divergent,
#   tokenizer BPE edge, beam search tie-break, WER spike per language,
#   model weights checksum mismatch, fsqlite storage roundtrip

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/franken_whisper /dp/franken_whisper__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 72
```

Wall time T3 × `gauntlet-full`: **14–28 days.**

---

## 5. Expected Pillar Findings

### Performance
1. **Mel-spectrogram FFT not amortized across windows** — recompute opportunity.
2. **Decoder attention KV-cache miss** on prompt-then-generation transition.
3. **Beam-search candidate sort O(N log N) per step** — partial-sort or heap opportunity.
4. **Tokenizer regex pre-tokenization** allocates per chunk — `OnceLock` regex (pattern 9).
5. **Model weight load latency** — mmap + lazy-load opportunity for large model.
6. **Greedy-vs-beam mode dispatch** — branch prediction cost.

### Conformance
1. **WER spike on Mandarin / Japanese / Arabic** — non-Latin tokenizer divergence.
2. **Mel-spectrogram log-mel computation order** — `log(mel(x))` vs `log_mel(x)` numerically distinct.
3. **Window function choice** — Hann vs Hamming — must match Whisper exactly.
4. **FFT normalization** — `'backward'` vs `'forward'` vs `'ortho'`.
5. **Attention softmax precision** — fp16 softmax loses precision on long sequences.
6. **LayerNorm epsilon** — `1e-5` vs `1e-6` differences cascade.
7. **Positional embedding off-by-one** for audio length not multiple of 30s.
8. **Beam search tie-breaking** — equal-score candidates ordering.
9. **Temperature sampling RNG state** — `torch.multinomial` byte-identity with Whisper's RNG.
10. **`<|notimestamps|>` token handling** — special-token behavior in decoder.

### Surface
1. **Per-model size coverage** — tiny/base/small/medium/large.
2. **Per-task** — transcribe + translate + language-detect.
3. **Per-feature** — VAD, word-timestamps, prompt conditioning.

---

## 6. Patterns to Apply First

1. **Full FrankenSQLite floor adapted for ML-System-class.**
2. **Per-op ULP tolerance table** — Mel-spectrogram, attention, layer-norm each have per-op ULP budgets; inherit from frankentorch where applicable.
3. **Per-output WER tolerance table** — WER between port output and reference must be below declared threshold per audio class (`docs/contracts/wer_tolerance_v1.toml`).
4. **Audio-fixture corpus** — per language × per accent × per noise-condition; Tier 3 (WER ≤ ε); Tier 2 (identical token IDs); Tier 1 (identical waveform preprocessing).
5. **5 checkpoint-save crash boundaries** + 2 distributed-collective (if distributed inference).
6. **E-process invariants** — INV-SoftmaxSumsToOne, INV-AttentionScoresNonPositive (`scores ∈ (-∞, 0]`), INV-BeamSearchTopKMonotone.

---

## 7. Estimated Rounds to Convergence

**10–15 rounds.** Audio variance + numerical drift + tokenization edge cases conspire.

---

## 8. Risk Register

1. **OpenAI Whisper reference is not a single version** — multiple model checkpoints, multiple tokenizer versions. *Mitigation:* `model_corpus.toml` with SHA-256 per checkpoint.
2. **Audio-fixture licensing** — many speech corpora have non-commercial licenses. *Mitigation:* use freely-licensed (LibriSpeech, Common Voice with attribution).
3. **WER computation library divergence** — `jiwer` vs hand-rolled. *Mitigation:* pin WER library; document algorithm.
4. **FrankenSQLite storage dependency** (recent commit `eede00a` shows the link) — fsqlite MVCC bugs cascade into Whisper test reliability. *Mitigation:* pin fsqlite version + add fsqlite-roundtrip test to franken_whisper's conformance harness.

---

## 9. What Ships from Convergence

`certification_bundle/`:
- Universal floor
- `ulp_tolerance_compliance.json` — per-op (mel, encoder, decoder)
- `wer_compliance.json` — per-(language, accent, noise) WER vs tolerated
- `tokenizer_compliance.json` — per-language tokenization byte-identity
- `mel_spectrogram_compliance.json` — log-mel byte-identity for reference audio
- `checkpoint_roundtrip.json` — model weights load/save

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § franken_whisper](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § ML-System-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/ml-system-class.md](../first-bug-hunt/ml-system-class.md)
- [case-studies/frankentorch.md](frankentorch.md) — inherited ML-class tolerance discipline
- [case-studies/frankensqlite.md](frankensqlite.md) — inherited storage dependency
