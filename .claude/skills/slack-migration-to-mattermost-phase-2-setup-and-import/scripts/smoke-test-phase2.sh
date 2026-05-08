#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"
tmp_root="$(mktemp -d -t phase2-smoke-XXXXXX)"
handoff_json="${tmp_root}/handoff.json"
manifest_json="${tmp_root}/phase1-manifest.json"
import_zip="${tmp_root}/mattermost-bulk-import.zip"
rendered_config="${tmp_root}/config.json"
intake_manifest="${tmp_root}/phase2-intake-manifest.json"
intake_report="${tmp_root}/phase2-intake-report.json"
config_report="${tmp_root}/config-report.json"
live_report="${tmp_root}/live-report.json"
staging_report="${tmp_root}/staging-report.json"
smoke_report="${tmp_root}/smoke-report.json"
restore_report="${tmp_root}/restore-report.json"
activation_report="${tmp_root}/activation-report.json"
reconcile_report="${tmp_root}/reconcile-report.json"
cutover_report="${tmp_root}/cutover-report.json"
score_json="${tmp_root}/readiness-score.json"
score_md="${tmp_root}/readiness-score.md"
readiness_md="${tmp_root}/phase2-readiness.md"
smoke_report_md="${tmp_root}/smoke-report.md"
ping_server_pid=""
cleanup() {
  if [[ -n "${ping_server_pid}" ]] && kill -0 "${ping_server_pid}" >/dev/null 2>&1; then
    kill "${ping_server_pid}" >/dev/null 2>&1 || true
    wait "${ping_server_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

python3 - <<PY
from pathlib import Path
import json
import zipfile

root = Path("${tmp_root}")
jsonl_path = root / "mattermost_import.jsonl"
jsonl_path.write_text(
    "\n".join(
        [
            '{"type":"version","version":1}',
            '{"type":"team","team":{"name":"sample-team","display_name":"Sample Team","type":"O","allow_open_invite":true}}',
            '{"type":"channel","channel":{"team":"sample-team","name":"general","display_name":"General","type":"O"}}',
            '{"type":"user","user":{"username":"alex","email":"alex@example.com","teams":[{"name":"sample-team","roles":"team_user","channels":[{"name":"general","roles":"channel_user","favorite":false}]}]}}',
            '{"type":"user","user":{"username":"blair","email":"blair@example.com","teams":[{"name":"sample-team","roles":"team_user","channels":[{"name":"general","roles":"channel_user","favorite":false}]}]}}',
            '{"type":"post","post":{"team":"sample-team","channel":"general","user":"alex","message":"hello","create_at":1764547200000,"attachments":[{"path":"data/bulk-export-attachments/example.txt"}]}}',
            '{"type":"direct_channel","direct_channel":{"members":["alex","blair"],"header":""}}',
            '{"type":"direct_post","direct_post":{"channel_members":["blair","alex"],"user":"alex","message":"direct hello","create_at":1764547201000}}',
            '{"type":"emoji","emoji":{"name":"party","image":"data/emoji/party.png"}}',
        ]
    )
    + "\n",
    encoding="utf-8",
)
with zipfile.ZipFile("${import_zip}", "w", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.write(jsonl_path, "mattermost_import.jsonl")
    archive.writestr("data/bulk-export-attachments/example.txt", "hello")
    archive.writestr("data/emoji/party.png", "png")
Path("${handoff_json}").write_text(
    json.dumps(
        {
            "workspace": "smoke-phase2",
            "final_package": {"path": str(Path("${import_zip}").resolve()), "sha256": ""},
            "counts": {
                "users": 2,
                "channels": 1,
                "posts": 1,
                "direct_channels": 1,
                "direct_posts": 1,
                "emoji": 1,
                "attachments": 1,
            },
            "known_gaps": [],
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY

python3 - <<PY
import hashlib
import json
from pathlib import Path

handoff_path = Path("${handoff_json}")
manifest_path = Path("${manifest_json}")
handoff = json.loads(handoff_path.read_text(encoding="utf-8"))
zip_path = Path("${import_zip}")
digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
handoff["final_package"]["sha256"] = digest
handoff["manifests"] = [str(manifest_path.resolve())]
handoff["sidecar_channels"] = ["slack-export-admin"]
handoff_path.write_text(json.dumps(handoff, indent=2) + "\n", encoding="utf-8")
manifest = {
    "schema_version": 1,
    "base_dir": str(Path("${tmp_root}").resolve()),
    "artifacts": [
        {
            "path": str(zip_path.resolve()),
            "sha256": digest,
            "bytes": zip_path.stat().st_size,
        }
    ],
}
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

python3 "${script_dir}/build-phase2-intake-manifest.py" \
  --workspace smoke-phase2 \
  --environment staging \
  --output "${intake_manifest}" \
  "${handoff_json}" "${import_zip}"
python3 "${script_dir}/validate-phase2-intake.py" \
  --handoff-json "${handoff_json}" \
  --intake-manifest "${intake_manifest}" \
  --output-json "${intake_report}"
python3 "${script_dir}/materialize-mattermost-config.py" \
  --output "${rendered_config}" \
  --site-url "https://chat.example.com" \
  --listen-address "127.0.0.1:8065" \
  --data-source "postgres://mmuser:password@localhost:5432/mattermost?sslmode=disable" \
  --open-server \
  --signup-enabled \
  --disable-email-verification
python3 "${script_dir}/validate-mattermost-config.py" \
  "${rendered_config}" \
  --expected-site-url "https://chat.example.com" \
  --expected-listen "127.0.0.1:8065" \
  --require-open-server \
  --require-signup-enabled \
  --require-email-verification-disabled \
  --output-json "${config_report}"

cat > "${live_report}" <<EOF
{"status":"passed","checks":{"http_ping":{"ok":true},"websocket":{"ok":true}},"errors":[]}
EOF
cat > "${staging_report}" <<EOF
{"status":"success","errors":[]}
EOF
bin_dir="${tmp_root}/bin"
mkdir -p "${bin_dir}"
cat > "${bin_dir}/psql" <<'EOF'
#!/usr/bin/env python3
import sys

sql = sys.argv[-1]
if "FROM Users" in sql:
    print("2")
elif "FROM Channels c" in sql and "JOIN Teams t" in sql and "COUNT(*)" in sql:
    print("1")
elif "FROM Posts p" in sql and "JOIN Channels c" in sql:
    print("1")
elif "string_agg(u.Username" in sql:
    print("DM123\talex,blair")
elif "FROM Posts WHERE DeleteAt = 0 AND ChannelId IN ('DM123')" in sql:
    print("1")
elif "FROM Emoji" in sql:
    print("1")
elif "FROM FileInfo fi" in sql:
    print("1")
else:
    print(f"unhandled sql: {sql}", file=sys.stderr)
    sys.exit(2)
EOF
chmod +x "${bin_dir}/psql"

ping_port="$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"
cat > "${tmp_root}/ping-fixture.py" <<EOF
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/v4/system/ping":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"OK"}')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

HTTPServer(("127.0.0.1", ${ping_port}), Handler).serve_forever()
EOF
python3 "${tmp_root}/ping-fixture.py" >/dev/null 2>&1 &
ping_server_pid="$!"
python3 - <<PY
from time import sleep
from urllib.request import urlopen

url = "http://127.0.0.1:${ping_port}/api/v4/system/ping"
for _ in range(50):
    try:
        with urlopen(url) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        sleep(0.1)
raise SystemExit(1)
PY

PATH="${bin_dir}:$PATH" python3 "${script_dir}/run-import-smoke-tests.py" \
  --handoff-json "${handoff_json}" \
  --database-url "postgres://unused" \
  --mattermost-url "http://127.0.0.1:${ping_port}" \
  --output-json "${smoke_report}" \
  --output-md "${smoke_report_md}"
cat > "${restore_report}" <<EOF
{"status":"success"}
EOF
cat > "${activation_report}" <<EOF
{"status":"passed","note":"synthetic"}
EOF

python3 "${script_dir}/reconcile-handoff-vs-import.py" \
  --handoff-json "${handoff_json}" \
  --observed-json "${smoke_report}" \
  --output-json "${reconcile_report}"
python3 "${script_dir}/validate-cutover-readiness.py" \
  --handoff-json "${handoff_json}" \
  --config-report "${config_report}" \
  --live-report "${live_report}" \
  --staging-report "${staging_report}" \
  --smoke-report "${smoke_report}" \
  --reconciliation-report "${reconcile_report}" \
  --restore-report "${restore_report}" \
  --activation-report "${activation_report}" \
  --rollback-owner "smoke-owner" \
  --output-json "${cutover_report}"
python3 "${script_dir}/generate-readiness-score.py" \
  --handoff-json "${handoff_json}" \
  --intake-report "${intake_report}" \
  --config-report "${config_report}" \
  --live-report "${live_report}" \
  --staging-report "${staging_report}" \
  --smoke-report "${smoke_report}" \
  --reconciliation-report "${reconcile_report}" \
  --activation-report "${activation_report}" \
  --cutover-report "${cutover_report}" \
  --restore-report "${restore_report}" \
  --output-json "${score_json}" \
  --output-md "${score_md}"
python3 "${script_dir}/generate-phase2-readiness.py" \
  --output-md "${readiness_md}" \
  --handoff-json "${handoff_json}" \
  --intake-report "${intake_report}" \
  --config-report "${config_report}" \
  --live-report "${live_report}" \
  --score-json "${score_json}" \
  --staging-report "${staging_report}" \
  --smoke-report "${smoke_report}" \
  --reconciliation-report "${reconcile_report}" \
  --activation-report "${activation_report}" \
  --cutover-report "${cutover_report}"

echo "phase2 smoke test artifacts: ${tmp_root}"
