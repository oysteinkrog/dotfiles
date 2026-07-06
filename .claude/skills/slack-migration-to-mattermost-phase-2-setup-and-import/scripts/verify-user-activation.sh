#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <mattermost-url> <test-email> <output-json> [output-md]" >&2
  exit 1
fi

mm_url="$1"
test_email="$2"
output_json="$3"
output_md="${4:-}"
response_file="${output_json%.json}.response.json"
smtp_proof_file="${SMTP_PROOF_FILE:-}"

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl not found in PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "${output_json}")"

status="passed"
note="password reset trigger accepted"
http_code="000"
if ! http_code="$(
  curl -sS \
    -o "${response_file}" \
    -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${test_email}\"}" \
    "${mm_url%/}/api/v4/users/password/reset/send"
)"; then
  status="failed"
  note="password reset trigger request failed"
elif [[ "${http_code}" != "200" && "${http_code}" != "201" && "${http_code}" != "204" ]]; then
  status="failed"
  note="password reset trigger returned HTTP ${http_code}"
fi

if [[ -n "${smtp_proof_file}" && ! -f "${smtp_proof_file}" ]]; then
  status="failed"
  note="${note}; smtp proof file missing"
fi

cat > "${output_json}" <<EOF
{
  "status": "${status}",
  "mattermost_url": "${mm_url}",
  "test_email": "${test_email}",
  "http_code": "${http_code}",
  "response_file": "${response_file}",
  "smtp_proof_file": "${smtp_proof_file}",
  "note": "${note}"
}
EOF
echo "wrote ${output_json}"

if [[ -n "${output_md}" ]]; then
  mkdir -p "$(dirname "${output_md}")"
  cat > "${output_md}" <<EOF
# User Activation Verification

- Status: ${status}
- Mattermost URL: \`${mm_url}\`
- Test email: \`${test_email}\`
- HTTP code: ${http_code}
- Response file: \`${response_file}\`
- SMTP proof file: \`${smtp_proof_file}\`
- Note: ${note}
EOF
  echo "wrote ${output_md}"
fi

if [[ "${status}" != "passed" ]]; then
  echo "error: ${note}" >&2
  exit 1
fi
