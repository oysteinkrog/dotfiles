#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <export-dir> <output-zip> [extra slackdump args...]" >&2
  exit 1
fi

export_dir="$1"
output_zip="$2"
shift 2

slackdump_bin="${SLACKDUMP_BIN:-slackdump}"
with_files="${SLACKDUMP_WITH_FILES:-1}"

if ! command -v "${slackdump_bin}" >/dev/null 2>&1; then
  echo "error: slackdump binary not found: ${slackdump_bin}" >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "error: zip not found in PATH" >&2
  exit 1
fi

mkdir -p "${export_dir}"
mkdir -p "$(dirname "${output_zip}")"
if [[ -f "${output_zip}" ]]; then
  backup_zip="${output_zip}.$(date -u +%Y%m%dT%H%M%SZ).bak"
  mv "${output_zip}" "${backup_zip}"
  echo "warning: existing output zip moved to ${backup_zip}" >&2
fi

declare -a cmd
cmd=("${slackdump_bin}" export --output "${export_dir}")
if [[ "${with_files}" == "1" ]]; then
  cmd+=(--files)
fi

if [[ -n "${SLACKDUMP_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_env_args=(${SLACKDUMP_ARGS})
  cmd+=("${extra_env_args[@]}")
fi
if [[ $# -gt 0 ]]; then
  cmd+=("$@")
fi

"${cmd[@]}"

(
  cd "${export_dir}"
  zip -qr "$(cd "$(dirname "${output_zip}")" && pwd)/$(basename "${output_zip}")" .
)

if [[ ! -f "${output_zip}" ]]; then
  echo "error: expected output zip was not created: ${output_zip}" >&2
  exit 1
fi

echo "wrote ${output_zip}"
