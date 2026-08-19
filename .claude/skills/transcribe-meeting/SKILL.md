---
name: transcribe-meeting
description: |
  Transcribe a meeting screen recording (or plain audio) with full speaker
  diarization and real participant names. Use when the user says "transcribe
  this video/recording/meeting", "who said what", "diarize", or drops a
  Meet/Teams/Zoom recording. Pipeline: ffmpeg extract -> roster from the
  meeting UI tiles -> faster-whisper ASR + senko diarization with the roster
  count (97% measured) or WhisperX + pyannote community-1 -> voice-to-name
  mapping verified against the UI's active-speaker highlight. Local CPU/GPU
  or tech-pool offload (mizar). Engines chosen by benchmark, not vibes: see
  EVALUATION.md.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# transcribe-meeting — screen recordings to named-speaker transcripts

Deliver (1) a timestamped transcript labeled with **real participant names**,
(2) a summary with per-speaker attribution. Two ideas carry this skill:

- **The video is ground truth.** A meeting recording shows who is speaking
  (name tiles + active-speaker highlight). Use it twice: up front for the
  roster and speaker count, and afterwards to bind voice clusters to names.
- **Give the diarizer the count.** Every engine tested under-serves
  low-airtime speakers when it must guess the speaker count. Counting the
  tiles and passing that number raised senko from 93.5% to 97.2% on the
  benchmark (EVALUATION.md in this directory has the full table and method).

Never upload the recording to an external service; everything runs locally or
on company machines. Internal meeting audio may go to tech-pool boxes; check
the data class before shipping anything more sensitive there.

## Step 1 — Probe, extract, roster

```bash
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1 "$VIDEO"
ffmpeg -y -v error -i "$VIDEO" -vn -ac 1 -ar 16000 "$SCRATCH/audio.wav"
scripts/frames.sh "$VIDEO" "$SCRATCH/frames" 30 600 1500 2400   # spread over the file
```

Read the frames. Record: meeting app, **participant names from tile labels**,
**human speaker count N** (exclude bots like the Fireflies notetaker; note
joins/leaves — the layout reflows), and the layout phases (screen-share vs
gallery). N drives engine configuration; the names constrain step 4.

## Step 2 — Transcribe + diarize (pick one row)

| Situation | Command |
|---|---|
| Default: known roster, no GPU (this is almost always the right row) | `asr_fw.py` (faster-whisper large-v3-turbo) + `diarize_senko.py audio.wav diar.json N` + `assign_speakers.py` |
| HF token available and set up, or a CUDA GPU | `transcribe_whisperx.py` (WhisperX large-v3-turbo + pyannote community-1, word-level alignment, one pass) |
| Quick triage of a short/low-stakes clip | `asr_fw.py ... small`, senko without N |

All scripts use uv inline deps. Run torch-dependent ones with the CPU wheel
pin or a GPU-less box downloads multi-GB CUDA wheels:

```bash
export UV_EXTRA_INDEX_URL=https://download.pytorch.org/whl/cpu UV_INDEX_STRATEGY=unsafe-best-match
```

**Where to run.** WSL1 (this laptop) is the slowest option and hits uv/wheel
quirks; prefer a tech-pool box (all CPU-only since the VFIO change, but a
Ryzen 5800X does ASR at ~3x realtime and senko in ~2-6 min for an hour of
audio). rigel/vega have GPUs but are the research cluster; only use them when
the data belongs there. Offload pattern:

```bash
ssh mizar 'mkdir -p /data/pool/$USER-transcribe'
scp "$SCRATCH/audio.wav" ~/.claude/skills/transcribe-meeting/scripts/*.py mizar:/data/pool/$USER-transcribe/
ssh mizar 'cd /data/pool/$USER-transcribe && export UV_EXTRA_INDEX_URL=... && uv run diarize_senko.py audio.wav diar.json 6'
```

Reference wall times, 48-min meeting on mizar: faster-whisper large-v3-turbo
ASR ~15 min; senko diarization 2:10 (auto) / 6:18 (oracle spectral);
WhisperX+pyannote see EVALUATION.md.

**HF token setup (one-time, for the WhisperX row).** `HF_TOKEN` lives in the
secret store (`with-secrets HF_TOKEN -- ...`; copy to `~/.hf_token` mode 600
on a remote box). Two gates, both mandatory: the account must accept the
terms at hf.co/pyannote/speaker-diarization-community-1, AND a fine-grained
token needs the global "read access to public gated repos" permission.
Missing either produces `GatedRepoError: 403`. Verify with
`curl -H "Authorization: Bearer $HF_TOKEN" https://huggingface.co/api/whoami-v2`.

**Do not use** franken_whisper for meetings (native Sortformer caps at 4
speakers; its uncapped engines scored 55% with wrong name bindings at v0.9.3),
plain ECAPA-embedding clustering (similar-voice colleagues merge), or
whisper.cpp `--diarize` (stereo-channel heuristic). Details in EVALUATION.md.

## Step 3 — Merge

```bash
python3 scripts/assign_speakers.py asr.json diar.json transcript.md names.json
```

`assign_speakers.py` votes each ASR segment to the max-overlap diarization
segment and merges consecutive same-speaker segments into `**[mm:ss] Name:**`
turns. Run it once without `names.json` to get the anonymous transcript for
step 4, then again with the mapping.

## Step 4 — Bind names with the video (mandatory for screen recordings)

Meeting UIs mark the active speaker; treat that as ground truth:

- **Meet**: colored rounded border on the speaking tile; small blue
  audio-bars icon in the tile corner; green speaker chip in the top bar
  during screen-share. Tile label = name.
- **Teams/Zoom**: equivalent border highlight; Zoom names the stage speaker
  bottom-left.
- Trap: a static mic icon means unmuted, not speaking. Only the
  border/highlight or top-bar chip marks the active speaker.

Procedure:
1. For each anonymous SPEAKER_NN, extract a frame ~2 s into its 3-5 longest
   turns (`scripts/frames.sh`) and Read them. The consistently highlighted
   tile names the cluster. Require **2+ independent anchors** per speaker.
2. Cross-check with content: someone addressed by name did not say that line;
   the person answering a question addressed to X probably is X; a voice
   heard after P left the call is not P.
3. Diarizers under-serve speakers with seconds of airtime even with the right
   count (measured: a 7-second speaker vanished at 97% overall accuracy).
   Sweep the transcript for short unattributed or suspicious turns and verify
   those moments with frames directly.
4. Leftover uncertainty is marked `[unverified]` in the transcript, never
   guessed silently.

## Step 5 — Clean and deliver

- ASR cleanup: fix domain mis-hearings (product names, people, jargon) with
  targeted replacements; list the corrections in the header; keep the raw
  output on disk. Watch for errors split across segment boundaries.
- Header: date, duration, source file, participants (from tiles), models and
  method, known limitations.
- Summary: outcome first, per-speaker attribution only where anchored,
  actions table. No em dashes; humanizer checklist applies.
- Slack delivery: 5000-char message limit — post the summary as the reply
  and the full transcript as a canvas linked from it.

## Environment traps (all hit in practice)

- WSL1: `soundfile` manylinux_2_28 wheel fails to install (read WAVs with
  stdlib `wave`); transient `os error 12` during `uv run` corrupts the env —
  do NOT `rm -rf` the uv cache (dcg blocks it), copy the script to a new name
  so uv builds a fresh environment.
- A `pgrep -f` wait-loop matches its own or a sibling job's wrapper command
  line; two such loops deadlock each other. Chain sequential remote steps in
  one command instead.
- senko pins `torch==2.8.0`; without the CPU index pin, torchaudio arrives
  CUDA-linked and dies at import (`libcudart.so`) on GPU-less boxes.
- whisperx renamed its diarization kwarg (`use_auth_token` -> `token`).
- Remote boxes need `ffmpeg` installed (whisperx shells out to it).

## Scripts

| Script | Purpose |
|---|---|
| `frames.sh <video> <dir> <t...>` | Extract labeled frames at timestamps |
| `asr_fw.py <wav> <out.json> [model]` | faster-whisper ASR only |
| `diarize_senko.py <wav> <out.json> [N]` | senko diarization, oracle count N from the roster |
| `assign_speakers.py <asr> <diar> <out.md> [names.json]` | Overlap-vote merge into named turns |
| `transcribe_whisperx.py <wav> <out.json> [model]` | One-pass WhisperX + pyannote community-1 |
