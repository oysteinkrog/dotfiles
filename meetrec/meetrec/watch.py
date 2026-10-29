"""Recorder daemon: start recording when Slack or Chrome opens a microphone stream.

Each call gets two tracks. "me" is the microphone source the app reads from,
"others" is the app's own playback stream. Both are written as raw s16le 48 kHz
mono, the rate PipeWire runs at, so nothing is lost before processing. A reader thread pads silence whenever PipeWire stops delivering data, so
every file stays aligned to the wall clock and the tracks line up later.
"""

from __future__ import annotations

import json
import logging
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import config

log = logging.getLogger("meetrec.watch")

RATE = 48000
BYTES_PER_SEC = RATE * 2
POLL_S = 1.0
START_AFTER_S = 2.0
STOP_AFTER_S = 20.0
MEET_FRESH_S = 10.0  # the extension sends a heartbeat every second
EVENT_PORT = 47833

# Matched against application.process.binary, then application.name (lowercased).
APPS = {
    "slack": {"slack"},
    "meet": {"chrome", "google-chrome", "google chrome", "chromium"},
}
OWN_BINARIES = {"pw-record", "pw-cat"}


def pw_dump() -> list[dict]:
    out = subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=10).stdout
    return json.loads(out) if out.strip() else []


def app_of(props: dict) -> str | None:
    keys = (
        props.get("application.process.binary", ""),
        props.get("application.name", "").lower(),
    )
    for app, names in APPS.items():
        if any(k in names for k in keys):
            return app
    return None


@dataclass
class Graph:
    """The parts of the PipeWire graph the recorder cares about, per app."""

    mic_streams: dict[str, list[int]] = field(default_factory=dict)
    out_streams: dict[str, list[int]] = field(default_factory=dict)
    sources_for: dict[str, set[int]] = field(default_factory=dict)
    serial: dict[int, str] = field(default_factory=dict)
    props: dict[int, dict] = field(default_factory=dict)


def read_graph() -> Graph:
    g = Graph()
    objs = pw_dump()
    links: list[tuple[int, int]] = []
    for o in objs:
        t = o.get("type", "")
        info = o.get("info") or {}
        if t == "PipeWire:Interface:Link":
            links.append((info.get("output-node-id"), info.get("input-node-id")))
            continue
        if t != "PipeWire:Interface:Node":
            continue
        props = info.get("props") or {}
        g.serial[o["id"]] = str(props.get("object.serial", o["id"]))
        g.props[o["id"]] = props
        if (
            props.get("application.process.binary") in OWN_BINARIES
            or props.get("application.name") in OWN_BINARIES
        ):
            continue
        app = app_of(props)
        if not app:
            continue
        cls = props.get("media.class", "")
        if cls == "Stream/Input/Audio":
            g.mic_streams.setdefault(app, []).append(o["id"])
        elif cls == "Stream/Output/Audio":
            g.out_streams.setdefault(app, []).append(o["id"])
    for app, streams in g.mic_streams.items():
        g.sources_for[app] = {out for out, inp in links if inp in streams}
    return g


class TrackRecorder:
    """One pw-record process writing a wall-clock aligned raw file."""

    def __init__(
        self,
        session_dir: Path,
        role: str,
        node_id: int,
        serial: str,
        t0: float,
        props: dict | None = None,
    ):
        self.node_id = node_id
        start = time.time()
        stem = f"{role}-{node_id}-{int((start - t0) * 1000):09d}"
        self.path = session_dir / f"{stem}.pcm"
        (session_dir / f"{stem}.json").write_text(
            json.dumps(
                {
                    "role": role,
                    "node": node_id,
                    "offset_s": start - t0,
                    "rate": RATE,
                    # Which device or stream this was, for finding problems later.
                    "props": {k: v for k, v in (props or {}).items() if "." in k},
                },
                indent=1,
            )
        )
        self.proc = subprocess.Popen(
            [
                "pw-record",
                "--target",
                serial,
                "--rate",
                str(RATE),
                "--channels",
                "1",
                "--format",
                "s16",
                "--raw",
                "-P",
                "{ node.dont-reconnect = true }",
                "-",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        self.thread = threading.Thread(target=self._pump, args=(start,), daemon=True)
        self.thread.start()

    def _pump(self, start: float) -> None:
        assert self.proc.stdout
        written = 0
        with open(self.path, "wb") as f:
            while True:
                chunk = self.proc.stdout.read1(9600)
                if not chunk:
                    break
                # Pad the gap if the stream stalled (corked or idle) for more than 300 ms.
                behind = (
                    int((time.time() - start) * BYTES_PER_SEC) - written - len(chunk)
                )
                if behind > BYTES_PER_SEC * 0.3:
                    behind -= behind % 2
                    f.write(b"\0" * behind)
                    written += behind
                f.write(chunk)
                written += len(chunk)

    def stop(self) -> None:
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.thread.join(5)


class Session:
    def __init__(self, app: str, root: Path):
        self.app = app
        self.t0 = time.time()
        stamp = time.strftime("%Y-%m-%d_%H%M%S", time.localtime(self.t0))
        self.dir = root / ".recording" / f"{stamp}-{app}"
        self.dir.mkdir(parents=True)
        self.recorders: dict[tuple[str, int], TrackRecorder] = {}
        self.skipped = False
        self.meet_events = 0
        self.last_seen = self.t0
        self.write_meta()
        self.live: subprocess.Popen | None = None
        if config.load().get("live_transcript", True):
            self.live = subprocess.Popen(
                [sys.executable, "-m", "meetrec.cli", "live", str(self.dir)]
            )

    def write_meta(self, **extra) -> None:
        meta = {"app": self.app, "start": self.t0}
        p = self.dir / "meta.json"
        if p.exists():
            meta.update(json.loads(p.read_text()))
        meta.update(extra)
        p.write_text(json.dumps(meta, indent=2))

    def sync(self, g: Graph) -> None:
        wanted = {("others", n) for n in g.out_streams.get(self.app, [])}
        wanted |= {("me", n) for n in g.sources_for.get(self.app, set())}
        for key, rec in list(self.recorders.items()):
            if key not in wanted or rec.proc.poll() is not None:
                rec.stop()
                del self.recorders[key]
        for role, node in wanted - set(self.recorders):
            if node in g.serial:
                log.info("%s: recording %s from node %s", self.app, role, node)
                self.recorders[(role, node)] = TrackRecorder(
                    self.dir, role, node, g.serial[node], self.t0, g.props.get(node)
                )

    def stop(self) -> None:
        for rec in self.recorders.values():
            rec.stop()
        self.recorders.clear()
        if self.live and self.live.poll() is None:
            self.live.terminate()
        self.write_meta(end=time.time())

    def status(self) -> dict:
        meta = json.loads((self.dir / "meta.json").read_text())
        return {
            "app": self.app,
            "dir": str(self.dir),
            "start": self.t0,
            "title": meta.get("title"),
        }

    def add_event(self, ev: dict) -> None:
        self.meet_events += 1
        with open(self.dir / "events.jsonl", "a") as f:
            f.write(json.dumps(ev) + "\n")


class Watcher:
    def __init__(self) -> None:
        self.cfg = config.load()
        self.root = config.root()
        self.sessions: dict[str, Session] = {}
        self.pending: dict[str, float] = {}
        self.suppressed: set[str] = set()
        self.lock = threading.Lock()
        # Meet events that arrive before the mic opens (the roster on the green room page).
        self.early_events: list[dict] = []
        self.last_meet: tuple = ()
        self.last_meet_at = 0.0

    # Extension events -----------------------------------------------------------
    def on_event(self, ev: dict) -> None:
        with self.lock:
            self.last_meet_at = time.time()
            state = (ev.get("code"), ev.get("title"), tuple(ev.get("participants", [])))
            if state != self.last_meet:
                self.last_meet = state
                log.info("meet: extension reports %s %r, participants %s", *state)
            s = self.sessions.get("meet")
            if s:
                s.add_event(ev)
                if ev.get("title") and s.meet_events == 1:
                    s.write_meta(title=ev["title"], meet_code=ev.get("code"))
            else:
                now = time.time() * 1000
                self.early_events = [
                    e for e in self.early_events if now - e.get("t", 0) < 60_000
                ]
                self.early_events.append(ev)

    # Notification ---------------------------------------------------------------
    def notify(self, s: Session) -> None:
        label = {"slack": "Slack huddle", "meet": "Google Meet call"}[s.app]
        if not self.cfg.get("notify", True):
            return

        def run() -> None:
            try:
                r = subprocess.run(
                    [
                        "notify-send",
                        "--app-name=meetrec",
                        "--icon=media-record",
                        "--expire-time=20000",
                        "--action=skip=Stop and delete",
                        f"Recording {label}",
                        "Transcript goes to ~/meetings when the call ends.",
                    ],
                    capture_output=True,
                    text=True,
                )
            except FileNotFoundError:
                return
            if r.stdout.strip() == "skip":
                self.skip(s.app, s)

        threading.Thread(target=run, daemon=True).start()

    def skip(self, app: str, only: Session | None = None) -> bool:
        """Stop a recording and delete it; it stays off until the app releases the mic."""
        with self.lock:
            s = self.sessions.get(app)
            if not s or (only and s is not only):
                return False
            log.info("%s: skipped by user, deleting %s", app, s.dir)
            s.stop()
            s.skipped = True
            shutil.rmtree(s.dir, ignore_errors=True)
            del self.sessions[app]
            self.suppressed.add(app)
            return True

    def status(self) -> dict:
        with self.lock:
            recording = [s.status() for s in self.sessions.values()]
        queue = self.root / ".queue"
        return {
            "recording": recording,
            "queue": sorted(p.name for p in queue.iterdir()) if queue.exists() else [],
        }

    # Main loop ------------------------------------------------------------------
    def finish(self, s: Session) -> None:
        s.stop()
        # Chrome counts only while the meetrec extension reports an open Meet call.
        # Anything else using the mic (Claude voice chat, a dictation site) is dropped.
        if s.app == "meet" and s.meet_events == 0:
            log.info(
                "meet: Chrome used the mic but no Meet call was seen, discarding %s",
                s.dir,
            )
            shutil.rmtree(s.dir, ignore_errors=True)
            return
        if not any(s.dir.glob("*.pcm")):
            shutil.rmtree(s.dir, ignore_errors=True)
            return
        queue = self.root / ".queue"
        queue.mkdir(exist_ok=True)
        dest = queue / s.dir.name
        s.dir.rename(dest)
        log.info("%s: call ended, queued %s", s.app, dest)
        subprocess.run(
            ["systemctl", "--user", "start", "--no-block", "meetrec-process.service"]
        )

    def tick(self) -> None:
        g = read_graph()
        now = time.time()
        with self.lock:
            # Chrome counts as a call only while the extension reports an open Meet call.
            meet_open = now - self.last_meet_at < MEET_FRESH_S
            for app in APPS:
                active = bool(g.mic_streams.get(app)) and (app != "meet" or meet_open)
                s = self.sessions.get(app)
                if not active:
                    self.pending.pop(app, None)
                    self.suppressed.discard(app)
                if s:
                    if active:
                        s.last_seen = now
                        s.sync(g)
                    elif now - s.last_seen > STOP_AFTER_S:
                        del self.sessions[app]
                        self.finish(s)
                    else:
                        s.sync(g)
                    continue
                if not active or app in self.suppressed:
                    continue
                first = self.pending.setdefault(app, now)
                if now - first >= START_AFTER_S:
                    self.pending.pop(app)
                    s = Session(app, self.root)
                    log.info("%s: mic in use, recording to %s", app, s.dir)
                    if app == "meet":
                        for ev in self.early_events:
                            s.add_event(ev)
                        self.early_events.clear()
                    self.sessions[app] = s
                    s.sync(g)
                    self.notify(s)

    def run(self) -> None:
        self.recover()
        start_event_server(self)
        log.info("watching PipeWire for Slack and Meet calls")
        while True:
            try:
                self.tick()
            except Exception:
                log.exception("tick failed")
            time.sleep(POLL_S)

    def recover(self) -> None:
        """Queue recordings left behind by a crash or reboot."""
        rec = self.root / ".recording"
        if not rec.exists():
            return
        for d in rec.iterdir():
            if any(d.glob("*.pcm")):
                queue = self.root / ".queue"
                queue.mkdir(exist_ok=True)
                d.rename(queue / d.name)
                log.info("recovered unfinished recording %s", d.name)
            else:
                shutil.rmtree(d, ignore_errors=True)


def start_event_server(w: Watcher) -> None:
    class Handler(BaseHTTPRequestHandler):
        def reply(self, code: int, body: dict | None = None) -> None:
            data = json.dumps(body).encode() if body is not None else b""
            self.send_response(code)
            if body is not None:
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass  # the caller gave up waiting (tray or extension poll timed out)

        def do_GET(self) -> None:
            # Read-only. No CORS headers, so a web page cannot read the answer.
            if self.path == "/status":
                self.reply(200, w.status())
            else:
                self.reply(404)

        def do_POST(self) -> None:
            if self.path.startswith("/skip/"):
                # Local tools only: browsers always send Origin on a cross-site POST.
                if "Origin" in self.headers or self.headers.get("X-Meetrec") != "1":
                    self.reply(403)
                else:
                    self.reply(
                        200, {"skipped": w.skip(self.path.removeprefix("/skip/"))}
                    )
                return
            # Only the extension's service worker may post. Web pages send their own
            # Origin and cannot set the custom header without a CORS preflight we never answer.
            origin = self.headers.get("Origin", "")
            if (
                not origin.startswith("chrome-extension://")
                or self.headers.get("X-Meetrec") != "1"
            ):
                self.send_response(403)
                self.end_headers()
                return
            n = int(self.headers.get("Content-Length", "0"))
            try:
                ev = json.loads(self.rfile.read(min(n, 1_000_000)))
                w.on_event(ev)
                self.send_response(204)
            except Exception:
                self.send_response(400)
            self.end_headers()

        def log_message(self, *args) -> None:
            pass

    srv = ThreadingHTTPServer(("127.0.0.1", EVENT_PORT), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()


def main() -> None:
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )
    Watcher().run()
