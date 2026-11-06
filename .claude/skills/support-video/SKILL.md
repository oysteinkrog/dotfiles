---
name: support-video
description: Read a bug video or screen recording posted in Slack (#support or any channel) as frames plus a transcript. Use when the user shares a Slack file id or permalink to a video, or says "video in Slack", "support video", "bug video", "screen recording in Slack".
allowed-tools:
  - Bash
  - Read
---

# support-video

`slack_read_file` only works under 10 MB, so use this script for Slack videos.

```bash
support-video [--frames N] [--no-asr] [--asr-long] [--keep] <file id | file permalink | message permalink>
support-video --clean <file id>
```

- Input: a file id (`F0...`), a file permalink, or a message permalink (`/archives/<channel>/p<ts>`, takes the first video on that message).
- Output goes to `/var/tmp/claude/support-videos/<id>/`: `frame-<mm>m<ss>s.jpg` (default 12, 1280 px wide), `transcript.txt` (`[mm:ss] text`, faster-whisper `small`), `video.<ext>`.
- Videos over 10 minutes skip the transcript unless you pass `--asr-long`. `--no-asr` skips it always.
- A silent audio track gives "(no speech detected)". That is normal for screen recordings.

Then:
1. Read the frames in order, and read `transcript.txt`.
2. For key frames, run `/codex-look` for a second read.
3. Delete the folder when done: `support-video --clean <id>`. Support videos can contain customer data. Never post frames or transcript outside the task.
