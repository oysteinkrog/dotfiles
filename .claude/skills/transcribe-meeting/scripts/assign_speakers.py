"""Merge an ASR segment file with a diarization segment file.

Usage: python3 assign_speakers.py <asr.json> <diar.json> <out.md> [names.json]

Each ASR segment gets the diarization speaker with the largest time overlap
(falling back to the nearest segment when there is no overlap). Consecutive
same-speaker segments merge into turns: "**[mm:ss] SPEAKER_01:** text".
names.json (optional) maps diarization labels to real names once the video
anchors are verified: {"SPEAKER_01": "Daniel", ...}. Unmapped labels pass
through unchanged. Plain python3, no dependencies.
"""
import json
import sys

asr = json.load(open(sys.argv[1]))["segments"]
diar = json.load(open(sys.argv[2]))["segments"]
out_path = sys.argv[3]
names = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else {}


def speaker_for(a):
    best, best_ov = None, 0.0
    for d in diar:
        ov = min(a["end"], d["end"]) - max(a["start"], d["start"])
        if ov > best_ov:
            best, best_ov = d["speaker"], ov
    if best is None:
        mid = (a["start"] + a["end"]) / 2
        d = min(diar, key=lambda d: min(abs(d["start"] - mid), abs(d["end"] - mid)))
        best = d["speaker"]
    return names.get(best, best)


turns = []
for a in asr:
    sp = speaker_for(a)
    if turns and turns[-1][0] == sp:
        turns[-1][2].append(a["text"])
    else:
        turns.append([sp, a["start"], [a["text"]]])

with open(out_path, "w", encoding="utf-8") as f:
    for sp, start, texts in turns:
        ts = f"{int(start)//60:02d}:{int(start)%60:02d}"
        f.write(f"**[{ts}] {sp}:** " + " ".join(texts) + "\n\n")
print(f"{len(turns)} turns, {len(set(t[0] for t in turns))} speakers -> {out_path}")
