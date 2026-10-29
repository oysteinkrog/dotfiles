"""Tray icon: shows while a call records or transcribes, with a live transcript window.

The icon asks the recorder for its state once a second (GET /status on 127.0.0.1).
Hidden when nothing is happening. Left click opens the live transcript.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QAction, QColor, QFont, QIcon, QPainter, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QMenu,
    QMessageBox,
    QPlainTextEdit,
    QSystemTrayIcon,
    QVBoxLayout,
    QWidget,
)

from . import config

BASE = os.environ.get("MEETREC_URL", "http://127.0.0.1:47833")
LABEL = {"slack": "Slack huddle", "meet": "Google Meet call"}


def get_status() -> dict | None:
    try:
        with urllib.request.urlopen(f"{BASE}/status", timeout=1) as r:
            return json.load(r)
    except OSError:
        return None


def skip(app: str) -> None:
    req = urllib.request.Request(
        f"{BASE}/skip/{app}", method="POST", headers={"X-Meetrec": "1"}
    )
    try:
        urllib.request.urlopen(req, timeout=5).close()
    except OSError:
        pass


def clock(seconds: float) -> str:
    s = int(seconds)
    return (
        f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}"
        if s >= 3600
        else f"{s // 60}:{s % 60:02d}"
    )


class LiveWindow(QWidget):
    """Appends new lines from the recording's live.jsonl as they arrive."""

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("meetrec live transcript")
        self.resize(720, 520)
        self.text = QPlainTextEdit(readOnly=True)
        self.text.setFont(QFont("sans", 11))
        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.addWidget(self.text)
        self.source: Path | None = None
        self.offset = 0
        self.lines: list[dict] = []

    def follow(self, session_dir: str | None) -> None:
        path = Path(session_dir) / "live.jsonl" if session_dir else None
        if path != self.source and path is not None:
            self.source, self.offset, self.lines = path, 0, []
            self.render()
        if not self.source or not self.source.exists():
            return
        with open(self.source, "rb") as f:
            f.seek(self.offset)
            data = f.read()
        # Only consume whole lines; the writer may be mid-line.
        end = data.rfind(b"\n") + 1
        if not end:
            return
        self.offset += end
        new = sorted(
            (json.loads(raw) for raw in data[:end].splitlines()), key=lambda n: n["t"]
        )
        # The two tracks are transcribed separately, so lines can arrive out of order.
        in_order = not self.lines or min(n["t"] for n in new) >= self.lines[-1]["t"]
        self.lines = sorted(self.lines + new, key=lambda n: n["t"])
        bar = self.text.verticalScrollBar()
        at_bottom = bar.value() >= bar.maximum() - 4
        if in_order:
            for n in new:
                self.text.appendPlainText(fmt(n))
        else:
            keep = bar.value()
            self.render()
            bar.setValue(keep)
        if at_bottom:
            bar.setValue(bar.maximum())

    def render(self) -> None:
        self.text.setPlainText(
            "Listening. Lines appear about 5 to 10 seconds after they are said.\n"
        )
        for n in self.lines:
            self.text.appendPlainText(fmt(n))


def fmt(n: dict) -> str:
    return f"[{clock(n['t'])}] {n['who']}: {n['text']}"


def dot(color: str) -> QIcon:
    """A filled circle, so the icon never depends on the icon theme."""
    pix = QPixmap(64, 64)
    pix.fill(Qt.GlobalColor.transparent)
    p = QPainter(pix)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    p.setPen(Qt.PenStyle.NoPen)
    p.setBrush(QColor(color))
    p.drawEllipse(8, 8, 48, 48)
    p.end()
    return QIcon(pix)


class Tray:
    def __init__(self, app: QApplication) -> None:
        self.app = app
        self.red, self.amber = dot("#d93025"), dot("#e8a33d")
        self.icon = QSystemTrayIcon(self.red)
        self.window = LiveWindow()
        self.current: dict | None = None

        menu = QMenu()
        self.status_action = QAction("meetrec")
        self.status_action.setEnabled(False)
        self.live_action = QAction("Show live transcript")
        self.live_action.triggered.connect(self.show_window)
        self.skip_action = QAction("Stop and delete recording")
        self.skip_action.triggered.connect(self.confirm_skip)
        folder = QAction("Open meetings folder")
        folder.triggered.connect(
            lambda: subprocess.Popen(["xdg-open", str(config.root())])
        )
        for a in (self.status_action, self.live_action, self.skip_action):
            menu.addAction(a)
        menu.addSeparator()
        menu.addAction(folder)
        self.menu = menu
        self.icon.setContextMenu(menu)
        self.icon.activated.connect(self.on_click)

        self.timer = QTimer()
        self.timer.timeout.connect(self.refresh)
        self.timer.start(1000)
        self.refresh()

    def on_click(self, reason) -> None:
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self.show_window()

    def show_window(self) -> None:
        self.window.show()
        self.window.raise_()
        self.window.activateWindow()

    def confirm_skip(self) -> None:
        if not self.current:
            return
        what = LABEL.get(self.current["app"], "call")
        answer = QMessageBox.question(
            None,
            "Stop and delete?",
            f"Stop recording this {what} and delete what was recorded so far?",
        )
        if answer == QMessageBox.StandardButton.Yes:
            skip(self.current["app"])

    def refresh(self) -> None:
        st = get_status()
        recording = (st or {}).get("recording") or []
        queue = (st or {}).get("queue") or []
        self.current = recording[0] if recording else None
        if self.current:
            what = LABEL.get(self.current["app"], "call")
            title = self.current.get("title")
            text = f"Recording {what} · {clock(time.time() - self.current['start'])}"
            if title:
                text += f"\n{title}"
            self.icon.setIcon(self.red)
            self.skip_action.setVisible(True)
            self.window.follow(self.current["dir"])
        elif queue:
            n = len(queue)
            text = f"Transcribing {n} call{'s' if n > 1 else ''}"
            self.icon.setIcon(self.amber)
            self.skip_action.setVisible(False)
        else:
            text = "meetrec: not recording"
            self.skip_action.setVisible(False)
        self.status_action.setText(text.splitlines()[0])
        self.icon.setToolTip(text)
        self.icon.setVisible(bool(self.current or queue))
        if st is None:
            self.status_action.setText("Recorder not running")


def main() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName("meetrec")
    app.setDesktopFileName("meetrec")
    app.setQuitOnLastWindowClosed(False)
    tray = Tray(app)  # must stay referenced, or Python frees the timer and icon
    code = app.exec()
    del tray
    sys.exit(code)
