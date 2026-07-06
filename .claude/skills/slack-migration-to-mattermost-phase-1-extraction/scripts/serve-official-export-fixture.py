#!/usr/bin/env python3
import argparse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
from urllib.parse import urlparse


def html_document(export_ready: bool) -> str:
    links = ""
    if export_ready:
        links = """
        <section>
          <a href="/downloads/slack-export.zip">Download export ZIP</a>
          <a href="/downloads/channel-audit.csv">Download channel audit CSV</a>
          <a href="/downloads/member-list.csv">Download member list CSV</a>
        </section>
        """
    return f"""<!doctype html>
<html lang="en">
  <body>
    <h1>Slack Admin Export</h1>
    <form action="/services/export" method="post">
      <input type="hidden" name="workspace" value="fixture-workspace" />
      <button type="submit">Request export</button>
    </form>
    {links}
  </body>
</html>
"""


class FixtureHandler(BaseHTTPRequestHandler):
    server_version = "SlackExportFixture/1.0"

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/services/export":
            self._send_html(HTTPStatus.OK, html_document(self.server.export_ready))
            return
        if parsed.path == "/downloads/slack-export.zip":
            self._send_file(self.server.archive_path, "application/zip")
            return
        if parsed.path == "/downloads/channel-audit.csv":
            self._send_file(self.server.channel_audit_csv, "text/csv; charset=utf-8")
            return
        if parsed.path == "/downloads/member-list.csv":
            self._send_file(self.server.member_csv, "text/csv; charset=utf-8")
            return
        self.send_error(HTTPStatus.NOT_FOUND, "not found")

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path != "/services/export":
            self.send_error(HTTPStatus.NOT_FOUND, "not found")
            return
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length:
            self.rfile.read(content_length)
        self.server.export_ready = True
        self._send_html(
            HTTPStatus.OK,
            "<html><body><p>Export request accepted. Data is ready.</p></body></html>",
        )

    def log_message(self, format: str, *args) -> None:
        sys.stderr.write(f"{self.address_string()} - - [{self.log_date_time_string()}] {format % args}\n")

    def _send_html(self, status: HTTPStatus, body: str) -> None:
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _send_file(self, path: Path, content_type: str) -> None:
        payload = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main() -> int:
    parser = argparse.ArgumentParser(description="Serve a local official Slack export fixture with a triggerable export page.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--channel-audit-csv", required=True)
    parser.add_argument("--member-csv", required=True)
    args = parser.parse_args()

    archive_path = Path(args.archive)
    channel_audit_csv = Path(args.channel_audit_csv)
    member_csv = Path(args.member_csv)
    for path in (archive_path, channel_audit_csv, member_csv):
        if not path.exists():
            print(f"error: missing fixture file: {path}", file=sys.stderr)
            return 1

    server = ThreadingHTTPServer((args.host, args.port), FixtureHandler)
    server.archive_path = archive_path
    server.channel_audit_csv = channel_audit_csv
    server.member_csv = member_csv
    server.export_ready = False
    print(f"http://{args.host}:{args.port}/services/export")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
