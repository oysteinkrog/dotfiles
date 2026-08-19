---
name: transcribe-meeting
description: |
  Transcribe a meeting screen recording (or plain audio) with full speaker
  diarization, producing a speaker-labeled, timestamped transcript plus summary.
  Use when the user says "transcribe this video/recording/meeting", "who said
  what", "diarize", or drops a Meet/Teams/Zoom recording. Combines ASR
  (WhisperX / faster-whisper) + voice diarization (pyannote community-1 or
  ECAPA clustering) + the recording's own meeting UI (name tiles, active-speaker
  highlight) to map voices to real names. Supports local CPU/GPU and remote
  offload (tech-pool CPU boxes; rigel/vega for GPU if the data class allows).
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# transcribe-meeting — screen-recording transcription with speaker names

Produce: (1) a timestamped transcript labeled with **real participant names**,
(2) a summary with per-speaker attribution. The differentiator over plain
whisper+pyannote is step 4: a screen recording of a meeting *shows* who is
speaking; use the pixels to name the voices.

## Pipeline overview

1. **Probe + extract audio** (ffmpeg, always local, seconds)
2. **ASR** — engine picked by accuracy need and available compute
3. **Voice diarization** — who-spoke-when as anonymous speaker IDs
4. **Name mapping from video** — meeting-UI tiles + active-speaker highlight
5. **Merge + human-check** — labeled transcript, then summary

Never upload the recording to an external service. Everything here is local or
on company machines.

## Step 1 — Probe and extract

```bash
ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,codec_name -of default=noprint_wrappers=1 "$VIDEO"
ffmpeg -y -v error -i "$VIDEO" -vn -ac 1 -ar 16000 "$SCRATCH/audio.wav"
```

Also grab 4-6 probe frames spread across the file (`scripts/frames.sh`) and
Read them: identify the meeting app (Meet/Teams/Zoom), read the **participant
names from the tile labels**, and note layout phases (screen-share vs gallery;
layout reflows when someone joins/leaves). Record the roster now — it
constrains everything later.

## Step 2 + 3 — Choose the engine (decision table)

| Situation | Engine |
|---|---|
| GPU available (local `nvidia-smi` works, or rigel/vega and the recording's data class permits research-cluster storage) | **WhisperX** `large-v3` + pyannote `community-1` with `exclusive` diarization — the SOTA path, use it when accuracy matters |
| CPU only, accuracy matters, HF token present | WhisperX `large-v3-turbo` int8 + pyannote community-1 (slow: ~1-2x realtime on a good CPU; offload to tech-pool, not WSL1) |
| CPU only, no HF token (pyannote models are gated) | `scripts/transcribe_cpu.py`: faster-whisper (`small`→fast triage, `medium`→better) + ECAPA-TDNN embedding clustering. Expect the presenter and distinct-accent voices to separate; same-language same-mic voices often merge — step 4 fixes them |
| WSL1 host (this machine) | Do NOT run large models here. Either the CPU fallback with `small`, or ssh offload (below) |

**Remote offload.** tech-pool (`mizar`/`alcor`/`castor`/`spica`, tailnet
`tag:tech-pool`) is **CPU-only since 2026-08-01** (GPUs are VFIO-passed to the
QA VMs) but the Ryzens are far faster than WSL1 and safe for internal meeting
recordings (no-sensitive-data class: check before shipping anything
confidential there). rigel/vega have real GPUs but are the research cluster:
only use them if the data belongs there. Pattern:

```bash
scp "$SCRATCH/audio.wav" mizar:/data/pool/$USER-transcribe/
ssh mizar 'cd /data/pool/$USER-transcribe && UV_EXTRA_INDEX_URL=https://download.pytorch.org/whl/cpu UV_INDEX_STRATEGY=unsafe-best-match uv run transcribe_cpu.py audio.wav out.json medium'
scp mizar:/data/pool/$USER-transcribe/out.json "$SCRATCH/"
```

**Candidate engine — franken_whisper** (Dicklesworthstone/franken_whisper,
sister of franken_tts/franken_ocr): agent-first Rust ASR orchestrator routing
whisper.cpp / insanely-fast-whisper / whisper-diarization backends, NDJSON
streaming, SQLite persistence. Single-binary ergonomics would replace this
step's Python plumbing, and its whisper-diarization backend (NeMo-based) gives
speaker IDs without an HF token. Not yet trialed here; accuracy of its
diarization backend vs pyannote community-1 is unverified, and it does not
solve name mapping (step 4 still applies). If installed, prefer it for the
CPU path; benchmark against the fallback script once on a tech-pool box.

**HF token:** pyannote models (incl. community-1) are gated. Check
`secret --list` for `HF_TOKEN`; if absent, ask the user once to add it
(`https://hf.co/settings/tokens`, accept the model terms) rather than silently
degrading to the fallback when accuracy was requested.

**WSL1/uv gotchas** (hit in practice): `soundfile` manylinux_2_28 wheel fails
to install → read WAVs with stdlib `wave`; transient `Cannot allocate memory
(os error 12)` during `uv run` install corrupts the env → do NOT `rm -rf` the
uv cache (dcg blocks it), just `cp script.py script2.py` so uv hashes a fresh
environment. Pin `torch==X.Y.Z+cpu` with the pytorch cpu index or uv pulls
multi-GB CUDA wheels.

## Step 4 — Name the voices from the video (the load-bearing step)

Meeting UIs display the active speaker; use that as ground truth:

- **Meet**: colored rounded border around the speaking tile + small blue
  audio-bars icon in the tile corner; in share-phase there is also a green
  speaker chip in the top bar. Tile label = participant name.
- **Teams/Zoom**: equivalent border highlight; Zoom also puts the speaker name
  bottom-left of the main stage.

Procedure:
1. For each anonymous speaker cluster, take its 3-5 **longest** segments and
   extract a frame ~2s into each: `ffmpeg -ss <t> -i "$VIDEO" -frames:v 1 -vf scale=1280:-1 f.jpg`.
2. Read the frames; the consistently highlighted tile names that cluster.
3. Cross-check with content (who is addressed by name never speaks that line:
   "But Jonatan, I have another take" is NOT Jonatan; someone answering a
   question addressed to X probably is X) and with joins/leaves (a voice heard
   after person P left is not P).
4. If diarization merged two people (common for same-language colleagues on
   similar mics), split by frames: sample additional frames across the merged
   cluster's turns and relabel per turn. Prioritize turns the summary will
   quote or attribute.
5. Record 2+ independent anchors per speaker before trusting a label; note
   leftover uncertain turns as `[unverified]` rather than guessing.

Mind the mute-icon trap: a static mic/audio icon on a tile means unmuted, not
speaking. Only the border/highlight (or top-bar chip) marks the active speaker.

## Step 5 — Merge, clean, deliver

- Merge consecutive same-speaker segments into turns; keep `[mm:ss]` at turn
  granularity.
- ASR cleanup pass: fix obvious domain mis-hearings (product names, personal
  names, jargon) with targeted replacements; note the corrections in a header,
  never silently. Keep the raw output on disk.
- Header block: date, duration, source file, participants (from tiles, not
  guesswork), model + method used, known limitations.
- Summary: lead with outcome, per-speaker attribution only where anchored,
  actions table. Zero em dashes; run the humanizer checklist.
- Deliverables per the user's ask (files next to the recording, artifact,
  Slack thread + canvas...). For Slack: message limit is 5000 chars — summary
  as the reply, full transcript as a canvas linked from it.

## Scripts

- `scripts/frames.sh <video> <out-dir> <t1> [t2 ...]` — extract labeled frames.
- `scripts/transcribe_cpu.py <wav> <out.json> [model]` — faster-whisper +
  ECAPA clustering fallback, no gated models, pure CPU. Emits segments with
  `start/end/text/cluster`.
- `scripts/transcribe_whisperx.py <wav> <out.json> [model]` — WhisperX +
  pyannote community-1 (`exclusive` mode). Needs `HF_TOKEN` in env; run via
  `with-secrets HF_TOKEN -- uv run ...`. GPU if available, else CPU.

All scripts use uv inline-dep headers; no global installs.
