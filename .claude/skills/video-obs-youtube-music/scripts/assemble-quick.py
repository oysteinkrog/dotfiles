#!/usr/bin/env python3
"""
Quick assembly - main video with music and song cards (no intro/outro)
Can be used while intro is still rendering
"""

import os
import subprocess
import tempfile
from pathlib import Path

# Paths
MOVIES_DIR = Path(os.environ.get("OBS_MOVIES_DIR", Path.home() / "Movies")).expanduser()
MUSIC_DIR = MOVIES_DIR / "ashra_music"
CARDS_DIR = MUSIC_DIR / "cards"

# Input files
MAIN_VIDEO = MOVIES_DIR / "screen_recording_2x_with_timer.mp4"
SONG_1 = MUSIC_DIR / "01_dont_trust_the_kids.mp3"
SONG_2 = MUSIC_DIR / "02_pas_de_trois.mp3"
CARD_1 = CARDS_DIR / "01_card.mp4"
CARD_2 = CARDS_DIR / "02_card.mp4"

# Output
OUTPUT = MOVIES_DIR / "multi_agent_workflow_quick.mp4"

def get_duration(path):
    result = subprocess.run([
        'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
        '-of', 'csv=p=0', str(path)
    ], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed for {path}: {result.stderr.strip()}")
    try:
        return float(result.stdout.strip())
    except ValueError as exc:
        raise RuntimeError(f"Could not parse duration for {path}: {result.stdout!r}") from exc

def validate_inputs():
    missing = [path for path in [MAIN_VIDEO, SONG_1, SONG_2, CARD_1, CARD_2] if not path.exists()]
    if missing:
        raise FileNotFoundError(
            "Missing required input files:\n" + "\n".join(f"  - {path}" for path in missing)
        )

def main():
    validate_inputs()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("Quick Assembly - Main Video with Music")
    print("=" * 60)

    main_dur = get_duration(MAIN_VIDEO)
    song1_dur = get_duration(SONG_1)

    print(f"\nMain video: {main_dur:.1f}s ({main_dur/60:.1f} min)")

    # Card overlay timing
    card_1_start = 2.0
    card_2_start = song1_dur + 2.0
    card_dur = 6.0

    # Card dimensions (scaled from 2280x480)
    scale = 0.4
    card_w = int(2280 * scale)
    card_h = int(480 * scale)
    margin = 48

    print("\nCard overlays:")
    print(f"  Card 1: {card_1_start:.1f}s - {card_1_start + card_dur:.1f}s")
    print(f"  Card 2: {card_2_start:.1f}s - {card_2_start + card_dur:.1f}s")

    # Step 1: Add card overlays to video
    print("\n[Step 1] Adding song credit card overlays...")

    filter_complex = f"""
[1:v]scale={card_w}:{card_h}[card1];
[2:v]scale={card_w}:{card_h}[card2];
[0:v][card1]overlay=W-w-{margin}:{margin}:enable='between(t,{card_1_start},{card_1_start + card_dur})'[v1];
[v1][card2]overlay=W-w-{margin}:{margin}:enable='between(t,{card_2_start},{card_2_start + card_dur})'[vout]
"""

    with tempfile.TemporaryDirectory(prefix="obs-assemble-quick-") as temp_dir:
        overlay_tmp = Path(temp_dir) / "overlay_video.mp4"
        audio_tmp = Path(temp_dir) / "mixed_audio.m4a"

        subprocess.run([
            'ffmpeg', '-y',
            '-i', str(MAIN_VIDEO),
            '-i', str(CARD_1),
            '-i', str(CARD_2),
            '-filter_complex', filter_complex,
            '-map', '[vout]',
            '-c:v', 'libx264', '-preset', 'fast', '-crf', '18',
            '-pix_fmt', 'yuv420p',
            str(overlay_tmp)
        ], check=True)

        # Step 2: Mix audio tracks
        print("\n[Step 2] Mixing music tracks...")

        fade_start = main_dur - 5.0

        audio_filter = f"""
[0:a]asetpts=PTS-STARTPTS[a1];
[1:a]asetpts=PTS-STARTPTS,adelay={int(song1_dur * 1000)}[a2];
[a1][a2]amix=inputs=2:duration=longest,afade=t=out:st={fade_start}:d=5[aout]
"""

        subprocess.run([
            'ffmpeg', '-y',
            '-i', str(SONG_1),
            '-i', str(SONG_2),
            '-filter_complex', audio_filter,
            '-map', '[aout]',
            '-c:a', 'aac', '-b:a', '192k',
            '-t', str(main_dur),
            str(audio_tmp)
        ], check=True)

        # Step 3: Combine video and audio
        print("\n[Step 3] Combining video and audio...")

        subprocess.run([
            'ffmpeg', '-y',
            '-i', str(overlay_tmp),
            '-i', str(audio_tmp),
            '-c:v', 'copy',
            '-c:a', 'copy',
            '-shortest',
            str(OUTPUT)
        ], check=True)

    # Get final info
    final_dur = get_duration(OUTPUT)
    final_size = OUTPUT.stat().st_size / (1024 * 1024)

    print("\n" + "=" * 60)
    print("Quick Assembly Complete!")
    print("=" * 60)
    print(f"  File: {OUTPUT}")
    print(f"  Duration: {final_dur:.1f}s ({final_dur/60:.1f} min)")
    print(f"  Size: {final_size:.1f} MB")
    print("\nNote: This version has no intro/outro.")
    print("Run assemble-workflow-video.py once intro finishes rendering.")

if __name__ == "__main__":
    main()
