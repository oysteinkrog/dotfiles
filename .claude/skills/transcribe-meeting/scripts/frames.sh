#!/usr/bin/env bash
# Extract single frames from a video at given timestamps (seconds).
# Usage: frames.sh <video> <out-dir> <t1> [t2 ...]
set -euo pipefail
video=$1; out=$2; shift 2
mkdir -p "$out"
for t in "$@"; do
  ffmpeg -y -v error -ss "$t" -i "$video" -frames:v 1 -vf scale=1280:-1 "$out/f-$t.jpg"
  echo "$out/f-$t.jpg"
done
