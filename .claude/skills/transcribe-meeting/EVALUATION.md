# Engine evaluation (2026-08-19)

Benchmark: real 48-min Google Meet screen recording (6 speakers: 4 Norwegian
males + 1 US male + 1 presenter; one speaker leaves at 35:00; one speaks only
7 seconds). Ground truth: frame-verified active-speaker labels (~25 Meet
highlight frames, 2+ anchors per speaker), 62 turns. Metric: time-weighted
speaker accuracy at 1 Hz over unambiguous ground-truth seconds (3 s boundary
guard), best-case label mapping. Hardware: mizar (Ryzen 7 5800X, 16 threads,
no GPU), CPU-only.

| Engine | Accuracy | Failure mode | Wall (48 min audio) | Token | Speakers |
|---|---|---|---|---|---|
| WhisperX large-v3-turbo + pyannote community-1 | pending token fix | (run blocked on HF fine-grained token lacking the gated-repos permission; literature: best-in-class DER, used by WhisperX as default backend) | ASR leg measured 14:35 | HF (gated) | unlimited |
| senko, auto speaker count | 0.935 | found only 3 of 6 speakers; Jonatan/Nils/Adrian merged (0%) | 2:10 | none | auto (under-counts) |
| **senko + oracle count from video roster** | **0.972** | only the 7-second speaker (Adrian) merges away; Daniel/Scott 99%, Espen 93%, Nils 87%, Jonatan 75% | 6:18 | none | caller-supplied |
| franken_whisper 0.9.3 native (Sortformer) | 0.832 | Nils 0%, Adrian 0% — hard 4-speaker cap | 7:55 | none | max 4 |
| franken_whisper acoustic / ecapa, unhinted | n/a | collapses to 1 speaker (status "unresolved", refuses to force occupancy) | 4:17 | none | unbounded |
| franken_whisper ecapa(+fused) + 6 hard video-anchor hints | 0.553 | wrong name bindings (its "Espen" tracks Daniel, "Daniel" tracks Adrian); much of Scott unresolved; ecapa and ecapa-fused byte-identical | 4:16-4:37 | none | unbounded |
| faster-whisper small + ECAPA clustering (2-stage) | 0.827 | Espen 1%, Nils 0% — similar voices merge | ~25 min (WSL1 box) | none | estimated |

Key lesson: overall accuracy flatters every engine because two speakers hold
~80% of the airtime. The metric that matters for meetings is per-speaker
recall on the minor speakers, and the token-free CPU engines all collapse
there. Video-based name mapping (the Meet active-speaker highlight) is not a
nice-to-have; it is the only thing that rescued the low-airtime speakers.

Rejected without benchmarking:
- whisper.cpp --diarize: stereo-only heuristic, not real diarization.
- NVIDIA NeMo MSDD (whisper-diarization repo): ~10 GB VRAM class; no GPU in
  the tech pool since the VFIO change (2026-08-01).
- Cloud APIs (AssemblyAI, Deepgram, pyannote precision-2): accuracy is
  excellent but meeting recordings do not leave company machines.
- speakrs (Rust): Apple Silicon / CUDA focus; no CPU x86 story at eval time.

franken_whisper notes: install is one curl|bash (~2.1 GB models), zero Python,
JSON output with turns + confidence. ASR (native large-v3-turbo GGML) made
more domain mistakes than faster-whisper small on this audio ("loss monitor",
"pretter") and its per-segment confidence field looked unreliable (0.004 on a
clean segment). Its Sortformer boundary at 0-503 s exactly matched ground
truth, so segmentation is good; capacity (4 lanes) is the disqualifier for
meetings.

Can franken_whisper do >4 speakers? Mechanically yes: the `acoustic` and
`ecapa`/`ecapa-fused` engines are unbounded, and speaker-hints-v1
(`hard_must_link` enrollment intervals, which our video anchors supply
perfectly) makes it emit real names. Qualitatively no, as of 0.9.3: unhinted,
those engines refuse to commit and collapse to 1 speaker; hinted, they bind
several names to the wrong voices and score 0.553, worse than every other
candidate. All non-Sortformer paths are explicitly "development_uncertified".
Revisit on future releases; the hints-from-video-anchors idea itself is sound
and is used with pyannote instead (min/max_speakers from the tile roster).
