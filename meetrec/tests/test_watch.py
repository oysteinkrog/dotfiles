"""Call detection: which app a Chrome mic stream belongs to, and the folder labels.

No PipeWire, no Chrome and no real recording: read_graph, pw-record and systemctl are
replaced with fakes, and Chrome's history is a small SQLite file in a temp HOME.
"""

from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path

import pytest

from meetrec import apps, watch

CHROME_EPOCH = 11644473600


def chrome_time(t: float) -> int:
    return int((t + CHROME_EPOCH) * 1e6)


def make_history(home: Path, visits: list[tuple[str, float]]) -> None:
    prof = home / ".config/google-chrome/Profile 1"
    prof.mkdir(parents=True)
    con = sqlite3.connect(prof / "History")
    con.execute(
        "CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, last_visit_time INTEGER)"
    )
    con.executemany(
        "INSERT INTO urls (url, last_visit_time) VALUES (?, ?)",
        [(u, chrome_time(t)) for u, t in visits],
    )
    con.commit()
    con.close()


# URLs copied from Chrome's history for the Teams joins on 2026-11-03 and 2026-11-04.
TEAMS_JOIN = [
    "https://teams.microsoft.com/meet/3634607810271244?p=R3kMtsyQ5b1Q3lnvKA",
    "https://teams.microsoft.com/v2/?meetingjoin=true#/meet/3634607810271244?p=R3kMtsyQ5b1Q3lnvKA&anon=true",
    "https://teams.microsoft.com/light-meetings/launch?p=R3kMtsyQ5b1Q3lnvKA&anon=true&launchAgent=join_launcher_web",
    "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0",
    "https://teams.live.com/meet/9876543210123",
    "https://teams.cloud.microsoft/meet/3634607810271244?p=x",
    "https://teams.cloud.microsoft/light-meetings/launch?p=x",
]
NOT_A_CALL = [
    "https://teams.microsoft.com/v2/",
    "https://teams.microsoft.com/v2/#/calendarv2",
    "https://teams.cloud.microsoft/",
    "https://meet.google.com/home?authuser=0",
    "https://www.google.com/url?q=https://teams.microsoft.com/meet/3634607810271244",
]


@pytest.fixture
def home(tmp_path, monkeypatch):
    h = tmp_path / "home"
    h.mkdir()
    monkeypatch.setenv("HOME", str(h))
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: h))
    root = tmp_path / "meetings"
    root.mkdir()
    (root / "config.json").write_text(
        json.dumps({"notify": False, "live_transcript": False})
    )
    monkeypatch.setenv("MEETREC_ROOT", str(root))
    return h


@pytest.mark.parametrize("url", TEAMS_JOIN)
def test_teams_join_urls_count(home, url):
    now = time.time()
    make_history(home, [(url, now - 60)])
    assert abs(watch.last_visit(watch.HISTORY_GLOBS["teams"]) - (now - 60)) < 1
    assert watch.last_visit(watch.HISTORY_GLOBS["meet"]) == 0


@pytest.mark.parametrize("url", NOT_A_CALL)
def test_open_teams_tab_or_meet_home_does_not_count(home, url):
    make_history(home, [(url, time.time() - 60)])
    assert watch.last_visit(watch.HISTORY_GLOBS["teams"]) == 0
    assert watch.last_visit(watch.HISTORY_GLOBS["meet"]) == 0


def test_chrome_streams_group_as_chrome():
    assert watch.app_of({"application.process.binary": "chrome"}) == "chrome"
    assert watch.app_of({"application.name": "Google Chrome"}) == "chrome"
    assert watch.app_of({"application.process.binary": "slack"}) == "slack"


# Fake PipeWire ---------------------------------------------------------------------
class FakeProc:
    def __init__(self, *a, **k):
        self.stdout = None

    def poll(self):
        return None


@pytest.fixture
def watcher(home, monkeypatch):
    monkeypatch.setattr(watch.subprocess, "run", lambda *a, **k: None)
    monkeypatch.setattr(watch.TrackRecorder, "__init__", lambda self, *a, **k: None)
    monkeypatch.setattr(watch.TrackRecorder, "stop", lambda self: None)
    monkeypatch.setattr(watch.TrackRecorder, "proc", FakeProc(), raising=False)
    return watch.Watcher()


def chrome_mic_graph() -> watch.Graph:
    g = watch.Graph()
    g.mic_streams["chrome"] = [42]
    g.out_streams["chrome"] = [41]
    g.sources_for["chrome"] = {7}
    g.serial = {41: "41", 42: "42", 7: "7"}
    return g


def run_ticks(w, monkeypatch, graph, clock, n=4):
    for _ in range(n):
        monkeypatch.setattr(watch, "read_graph", lambda: graph)
        monkeypatch.setattr(watch.time, "time", lambda: clock[0])
        w.tick()
        clock[0] += 1.0


def test_teams_heartbeat_starts_a_teams_session(watcher, monkeypatch):
    clock = [time.time()]
    monkeypatch.setattr(watch.time, "time", lambda: clock[0])
    watcher.on_event(
        {
            "t": clock[0] * 1000,
            "source": "teams",
            "title": "Weekly sync | Microsoft Teams",
        }
    )
    run_ticks(watcher, monkeypatch, chrome_mic_graph(), clock)
    s = watcher.sessions["chrome"]
    assert s.app == "teams"
    assert s.dir.name.endswith("-teams")
    assert json.loads((s.dir / "meta.json").read_text())["app"] == "teams"
    assert watcher.status()["recording"][0]["app"] == "teams"


def test_no_signal_means_no_recording(watcher, monkeypatch):
    # An open Teams tab (no hang-up button, so no heartbeat) and no join link in history.
    make_history(Path.home(), [("https://teams.microsoft.com/v2/", time.time() - 60)])
    run_ticks(watcher, monkeypatch, chrome_mic_graph(), [time.time()])
    assert "chrome" not in watcher.sessions


def test_history_picks_teams_over_an_older_meet_room(watcher, monkeypatch):
    # 2026-11-03: a Meet room at 17:22, then a Teams join at 17:30. This was recorded as Meet.
    now = time.time()
    make_history(
        Path.home(),
        [
            ("https://meet.google.com/uds-jdkt-gvx?authuser=0", now - 9 * 60),
            (TEAMS_JOIN[2], now - 60),
        ],
    )
    run_ticks(watcher, monkeypatch, chrome_mic_graph(), [now])
    s = watcher.sessions["chrome"]
    assert s.app == "teams" and s.from_history


def test_history_teams_join_alone_records(watcher, monkeypatch):
    # 2026-11-04: Teams join at 17:07, no Meet room. This was not recorded at all.
    make_history(Path.home(), [(TEAMS_JOIN[0], time.time() - 120)])
    run_ticks(watcher, monkeypatch, chrome_mic_graph(), [time.time()])
    assert watcher.sessions["chrome"].app == "teams"


def test_extension_corrects_a_history_guess(watcher, monkeypatch):
    now = time.time()
    make_history(Path.home(), [("https://meet.google.com/abc-defg-hij", now - 60)])
    clock = [now]
    run_ticks(watcher, monkeypatch, chrome_mic_graph(), clock)
    s = watcher.sessions["chrome"]
    assert s.app == "meet"
    watcher.on_event({"t": clock[0] * 1000, "source": "teams", "title": "x"})
    assert s.app == "teams" and s.events == 1
    assert json.loads((s.dir / "meta.json").read_text())["app"] == "teams"


def test_skip_by_app_name(watcher, monkeypatch):
    clock = [time.time()]
    monkeypatch.setattr(watch.time, "time", lambda: clock[0])
    watcher.on_event({"t": clock[0] * 1000, "source": "teams"})
    run_ticks(watcher, monkeypatch, chrome_mic_graph(), clock)
    d = watcher.sessions["chrome"].dir
    assert watcher.skip("teams")
    assert "chrome" not in watcher.sessions and not d.exists()


def test_call_end_queues_teams_recording(watcher, monkeypatch):
    clock = [time.time()]
    monkeypatch.setattr(watch.time, "time", lambda: clock[0])
    watcher.on_event({"t": clock[0] * 1000, "source": "teams"})
    run_ticks(watcher, monkeypatch, chrome_mic_graph(), clock)
    s = watcher.sessions["chrome"]
    (s.dir / "me-7-000000000.pcm").write_bytes(b"\0\0")
    run_ticks(watcher, monkeypatch, watch.Graph(), clock, n=int(watch.STOP_AFTER_S) + 3)
    assert "chrome" not in watcher.sessions
    queued = list((watch.config.root() / ".queue").iterdir())
    assert [q.name.endswith("-teams") for q in queued] == [True]


def test_unknown_event_source_is_ignored(watcher):
    watcher.on_event({"source": "zoom"})
    assert all(t == 0 for t in watcher.heartbeat_at.values())


# Labels ----------------------------------------------------------------------------
@pytest.mark.parametrize(
    ("app", "title", "label"),
    [
        ("teams", "Microsoft Teams meeting | Microsoft Teams", "Microsoft Teams"),
        ("teams", "Weekly sync | Microsoft Teams", "Microsoft Teams - Weekly sync"),
        (
            "teams",
            "(2) Full Swing intro | Microsoft Teams",
            "Microsoft Teams - Full Swing intro",
        ),
        ("teams", "Calendar | Microsoft Teams", "Microsoft Teams"),
        ("teams", None, "Microsoft Teams"),
        ("meet", "Meet - Development review", "Google Meet - Development review"),
        ("meet", "Meet - abc-defg-hij", "Google Meet"),
        ("meet", "Google Meet", "Google Meet"),
        ("slack", "anything", "Slack huddle"),
    ],
)
def test_folder_label(app, title, label):
    assert apps.folder_label(app, title) == label


def test_every_app_has_labels():
    for app in ("slack", *apps.BROWSER):
        assert app in apps.LABEL and app in apps.FOLDER
    assert apps.LABEL["teams"] == "Teams call"
