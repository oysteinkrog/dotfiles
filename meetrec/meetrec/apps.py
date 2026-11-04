"""The call apps meetrec knows, and how each one is named in folders, the tray and notices."""

from __future__ import annotations

import re

# Short label: notifications and the tray ("Recording Teams call").
LABEL = {
    "slack": "Slack huddle",
    "meet": "Google Meet call",
    "teams": "Teams call",
}
# Folder and transcript heading ("2026-11-04 1708 Microsoft Teams - Weekly sync").
FOLDER = {
    "slack": "Slack huddle",
    "meet": "Google Meet",
    "teams": "Microsoft Teams",
}
# Apps that run in Chrome. The meetrec extension or Chrome's history says which one.
BROWSER = ("meet", "teams")

# Tab titles that name the app, not the meeting.
_GENERIC = {
    "meet": re.compile(r"(Meet|Google Meet)( - [a-z-]+)?"),
    "teams": re.compile(
        r"(Microsoft Teams( meeting| møte| call| anrop)?|Teams|Meeting|Møte|Calendar|Kalender|Chat)",
        re.IGNORECASE,
    ),
}


def meeting_title(app: str, title: str | None) -> str | None:
    """The meeting's own name from a tab title, or None when the title is generic."""
    if not title or app not in _GENERIC:
        return None
    t = title.strip()
    if app == "meet":
        if _GENERIC["meet"].fullmatch(t):
            return None
        return t.removeprefix("Meet - ") or None
    # Teams titles look like "Weekly sync | Microsoft Teams", sometimes with a "(2) " badge.
    t = re.sub(r"^\(\d+\)\s*", "", t)
    t = re.sub(r"\s*\|\s*Microsoft Teams\s*$", "", t).strip()
    if not t or _GENERIC["teams"].fullmatch(t):
        return None
    return t


def folder_label(app: str, title: str | None) -> str:
    label = FOLDER.get(app, app)
    name = meeting_title(app, title)
    return f"{label} - {name}" if name else label
