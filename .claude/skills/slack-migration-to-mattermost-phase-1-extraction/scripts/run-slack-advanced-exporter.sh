#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <fetch-emails|fetch-attachments|copy> <input-archive> <output-archive> [extra args...]" >&2
  exit 1
fi

mode="$1"
input_archive="$2"
output_archive="$3"
shift 3

exporter_bin="${SLACK_ADVANCED_EXPORTER_BIN:-slack-advanced-exporter}"

if [[ ! -f "${input_archive}" ]]; then
  echo "error: missing input archive: ${input_archive}" >&2
  exit 1
fi

mkdir -p "$(dirname "${output_archive}")"

if [[ "${mode}" == "copy" ]]; then
  cp "${input_archive}" "${output_archive}"
  echo "wrote ${output_archive}"
  exit 0
fi

if ! command -v "${exporter_bin}" >/dev/null 2>&1; then
  echo "error: slack-advanced-exporter binary not found: ${exporter_bin}" >&2
  exit 1
fi
if [[ -z "${SLACK_TOKEN:-}" ]]; then
  echo "error: SLACK_TOKEN must be set for ${mode}" >&2
  exit 1
fi

declare -a cmd
cmd=(
  "${exporter_bin}"
  --input-archive "${input_archive}"
  --output-archive "${output_archive}"
  "${mode}"
  --api-token "${SLACK_TOKEN}"
)
if [[ $# -gt 0 ]]; then
  cmd+=("$@")
fi

"${cmd[@]}"
echo "wrote ${output_archive}"
