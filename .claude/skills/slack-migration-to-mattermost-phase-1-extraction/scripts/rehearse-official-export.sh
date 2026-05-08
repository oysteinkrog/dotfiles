#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"
tmp_root="${PHASE1_EXPORT_REHEARSAL_ROOT:-}"
if [[ -z "${tmp_root}" ]]; then
  tmp_root="$(mktemp -d -t phase1-export-rehearsal-XXXXXX)"
else
  mkdir -p "${tmp_root}"
fi

source_dir="${tmp_root}/source"
mailbox_dir="${tmp_root}/mailbox"
raw_dir="${tmp_root}/raw"
reports_dir="${tmp_root}/reports"
archive_path="${source_dir}/slack-export.zip"
channel_audit_csv="${source_dir}/channel-audit.csv"
member_csv="${source_dir}/member-list.csv"
manifest_out="${raw_dir}/manifest.raw.json"
summary_out="${reports_dir}/official-intake.json"
provenance_out="${reports_dir}/official-export-provenance.json"

mkdir -p "${source_dir}" "${mailbox_dir}" "${raw_dir}" "${reports_dir}"

(
  cd "${skill_dir}/assets/fixtures/slack-export-sample"
  zip -qr "${archive_path}" .
)

cat > "${channel_audit_csv}" <<'EOF'
channel_id,channel_name,is_private,is_archived,member_count
C01,announcements,false,false,3
EOF

cat > "${member_csv}" <<'EOF'
email,username,real_name,status
alex@example.com,alex,Alex Example,active
EOF

port="$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"

server_log="${reports_dir}/fixture-server.log"
python3 "${script_dir}/serve-official-export-fixture.py" \
  --host 127.0.0.1 \
  --port "${port}" \
  --archive "${archive_path}" \
  --channel-audit-csv "${channel_audit_csv}" \
  --member-csv "${member_csv}" > "${reports_dir}/fixture-server.url" 2> "${server_log}" &
server_pid="$!"
cleanup() {
  if kill -0 "${server_pid}" >/dev/null 2>&1; then
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

export_page_url="http://127.0.0.1:${port}/services/export"
python3 - <<PY
from time import sleep
from urllib.request import urlopen

url = "${export_page_url}"
for _ in range(50):
    try:
        with urlopen(url) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        sleep(0.1)
raise SystemExit(1)
PY

python3 - <<PY
from email.message import EmailMessage
from email.utils import format_datetime
from datetime import datetime, timezone
from pathlib import Path

message = EmailMessage()
message["Subject"] = "Your Slack data is ready"
message["From"] = "feedback@slack.com"
message["To"] = "admin@example.com"
message["Date"] = format_datetime(datetime.now(timezone.utc))
message.set_content(
    "The export is ready. Open this page to download it:\\n\\n${export_page_url}\\n"
)
for source in ("${channel_audit_csv}", "${member_csv}"):
    path = Path(source)
    message.add_attachment(
        path.read_bytes(),
        maintype="text",
        subtype="csv",
        filename=path.name,
    )
Path("${mailbox_dir}/ready.eml").write_bytes(message.as_bytes())
PY

python3 "${script_dir}/automate-official-export.py" \
  --workspace rehearsal-phase1 \
  --output-dir "${raw_dir}" \
  --manifest-out "${manifest_out}" \
  --summary-out "${summary_out}" \
  --provenance-out "${provenance_out}" \
  --archive-out "${raw_dir}/slack-export.zip" \
  --channel-audit-out "${raw_dir}/channel-audit.csv" \
  --member-csv-out "${raw_dir}/member-list.csv" \
  --export-page-url "${export_page_url}" \
  --mailbox-dir "${mailbox_dir}" \
  --trigger-mode http-form \
  --poll-interval-seconds 1 \
  --timeout-seconds 20

python3 - <<PY
import json
from pathlib import Path
import sys

manifest = json.loads(Path("${manifest_out}").read_text(encoding="utf-8"))
artifacts = manifest.get("artifacts", [])
if len(artifacts) < 3:
    print("error: expected at least 3 quarantined artifacts from official export rehearsal", file=sys.stderr)
    raise SystemExit(1)
provenance = json.loads(Path("${provenance_out}").read_text(encoding="utf-8"))
if provenance.get("status") != "completed":
    print("error: official export rehearsal did not complete successfully", file=sys.stderr)
    raise SystemExit(1)
PY

echo "phase1 official export rehearsal artifacts: ${tmp_root}"
