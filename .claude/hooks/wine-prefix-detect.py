#!/usr/bin/env python3
"""Find a direct Wine call that would run in a MotionCatalyst prefix setup-prefix.sh did not make.

Reads the shell command from WINE_GUARD_COMMAND and the session's working directory from
WINE_GUARD_CWD. Prints the reason and exits 0 when the command should be denied; prints nothing
when it is fine.

The monorepo's tools/wine scripts check the prefix themselves when they source wine-env.sh.
This catches the calls that skip them: `WINEPREFIX=... wine ...`, `wineboot`, `winetricks`,
and `wine MotionCatalyst.exe` with no prefix at all, which runs in the bare ~/.wine. On
2026-11-11 a bare wineboot prefix ran MC on wined3d without DXVK, and the menu background took
a full CPU core.

The check itself is the repo's tools/wine/prefix-check.sh, taken from the repo the command runs
in, else from the master checkout. With neither, nothing is checked.
"""

import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
PREFIXES = HOME / ".local/share/wineprefixes"
SEPARATOR_RE = re.compile(r"&&|\|\||\||;|\n|\$\(|`")
WINE_TOOLS = {
    "wine",
    "wine64",
    "wineboot",
    "winecfg",
    "winetricks",
    "msiexec",
    "regedit",
}
WRAPPERS = {
    "env",
    "nice",
    "nohup",
    "time",
    "command",
    "exec",
    "timeout",
    "setsid",
    "heavy-build",
}
# Something that only MotionCatalyst's own runs use, so a call naming it is an MC run whatever
# the prefix is called.
MC_HINT_RE = re.compile(
    r"MotionCatalyst(?:-cli)?\.exe|UiMcpHost\.exe|/BUILD/x64_", re.I
)
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)


def expand(value: str) -> str | None:
    """Expands ~ and $HOME; returns None for any other variable, which cannot be known here."""
    value = value.replace("${HOME}", str(HOME)).replace("$HOME", str(HOME))
    if value.startswith("~/") or value == "~":
        value = str(HOME) + value[1:]
    return None if "$" in value else value


def words(segment: str) -> list[str]:
    try:
        return shlex.split(segment, comments=True)
    except ValueError:
        return []


def wine_calls(command: str):
    """Yields (prefix or None if unknown, segment text) for each direct Wine call."""
    exported = os.environ.get("WINEPREFIX") or None
    for segment in SEPARATOR_RE.split(command):
        ws = words(segment)
        if not ws:
            continue
        if ws[0] == "export":
            for w in ws[1:]:
                m = ASSIGN_RE.match(w)
                if m and m.group(1) == "WINEPREFIX":
                    exported = expand(m.group(2))
            continue
        prefix = exported
        i = 0
        while i < len(ws):
            m = ASSIGN_RE.match(ws[i])
            if m:
                if m.group(1) == "WINEPREFIX":
                    prefix = expand(m.group(2))
                i += 1
                continue
            name = os.path.basename(ws[i])
            if name in WRAPPERS:
                i += 1
                # timeout's duration and nice's -n value
                while i < len(ws) and (
                    ws[i].startswith("-") or re.fullmatch(r"[0-9.]+[smhd]?", ws[i])
                ):
                    i += 1
                continue
            break
        if i < len(ws) and os.path.basename(ws[i]) in WINE_TOOLS:
            yield prefix, segment


def checker(cwd: str) -> Path | None:
    candidates = []
    try:
        top = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout.strip()
        if top:
            candidates.append(Path(top) / "tools/wine/prefix-check.sh")
    except (OSError, subprocess.SubprocessError):
        pass
    candidates.append(HOME / "work/desktop/master/tools/wine/prefix-check.sh")
    return next((c for c in candidates if c.is_file()), None)


def main() -> int:
    command = os.environ.get("WINE_GUARD_COMMAND", "")
    cwd = os.environ.get("WINE_GUARD_CWD") or os.getcwd()
    script = None
    for prefix, segment in wine_calls(command):
        if prefix is None and "WINEPREFIX" in segment:
            continue  # a value this hook cannot expand; wine-env.sh is the check there
        path = Path(prefix) if prefix else HOME / ".wine"
        if not path.is_absolute():
            path = Path(cwd) / path
        path = Path(os.path.normpath(path))
        is_mc_prefix = path.parent == PREFIXES and path.name.startswith(
            "motioncatalyst"
        )
        if not is_mc_prefix and not MC_HINT_RE.search(segment):
            continue
        script = script or checker(cwd)
        if script is None:
            return 0
        result = subprocess.run(
            [
                "bash",
                "-c",
                '. "$1"; mc_prefix_problems "$2"',
                "_",
                str(script),
                str(path),
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        lines = [line for line in result.stdout.splitlines() if line]
        # A prefix that lacks only the current .NET runtime was set up for an older master.
        # wine-env.sh copies the runtime in the next time a tools/wine script sources it, and MC
        # without it stops at once with a clear error, so it does not hide a fault like wined3d.
        if result.returncode != 0 and not (
            len(lines) == 1 and lines[0].startswith(".NET Windows Desktop runtime ")
        ):
            missing = "; ".join(lines)
            print(f"{path} is not a prefix setup-prefix.sh made (it lacks: {missing})")
            return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
