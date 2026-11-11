#!/usr/bin/env python3
"""Tests for wine-prefix-guard.sh. Run: python3 wine-prefix-guard.test.py <monorepo checkout>

The checkout must have tools/wine/prefix-check.sh. HOME is a temporary folder, so the prefixes
here are fakes made of files.
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = Path(sys.argv[1]).resolve()

GOOD_REG = """WINE REGISTRY Version 2
[Software\\\\Microsoft\\\\Avalon.Graphics] 1
"DisableHWAcceleration"=dword:00000000

[Software\\\\Wine\\\\DllOverrides] 1
"d3d11"="native"
"d3d9"="native"
"dxgi"="native"
"windows.storage.applicationdata"=""
"""


def make_prefix(path: Path, good: bool) -> None:
    path.mkdir(parents=True)
    (path / "system.reg").write_text("WINE REGISTRY Version 2\n")
    (path / "user.reg").write_text(GOOD_REG if good else "WINE REGISTRY Version 2\n")
    if not good:
        return
    (path / "dxvk.conf").write_text(
        "dxgi.hideNvidiaGpu = False\nd3d9.deferSurfaceCreation = True\n"
    )
    s32 = path / "drive_c/windows/system32"
    s32.mkdir(parents=True)
    for dll in ("d3d9", "d3d11", "dxgi"):
        (s32 / f"{dll}.dll").write_bytes(b"MZ dxvk")
    version = (
        (REPO / "tools/wine/prefix-check.sh")
        .read_text()
        .split("MC_DOTNET_VERSION=")[1]
        .split()[0]
    )
    shared = path / "drive_c/Program Files/dotnet/shared"
    (shared / "Microsoft.WindowsDesktop.App" / version).mkdir(parents=True)
    (
        shared / "Microsoft.WindowsDesktop.App" / version / "PresentationFramework.dll"
    ).write_bytes(b"MZ")
    (shared / "Microsoft.NETCore.App" / version).mkdir(parents=True)
    (
        shared / "Microsoft.NETCore.App" / version / "System.Private.CoreLib.dll"
    ).write_bytes(b"MZ")


def run(home: Path, command: str) -> bool:
    """True when the hook denies the command."""
    env = {k: v for k, v in os.environ.items() if k != "WINEPREFIX"}
    env["HOME"] = str(home)
    payload = json.dumps({"tool_input": {"command": command}, "cwd": str(REPO)})
    out = subprocess.run(
        ["bash", str(HERE / "wine-prefix-guard.sh")],
        input=payload,
        capture_output=True,
        text=True,
        env=env,
        check=True,
    ).stdout
    return (
        bool(out.strip())
        and json.loads(out)["hookSpecificOutput"]["permissionDecision"] == "deny"
    )


def main() -> int:
    with tempfile.TemporaryDirectory(dir="/var/tmp") as tmp:
        home = Path(tmp)
        base = home / ".local/share/wineprefixes"
        make_prefix(base / "motioncatalyst", good=True)
        make_prefix(base / "motioncatalyst-ui-bare", good=False)
        cases = [
            # (command, denied)
            ("ls -la", False),
            ("echo wine is fine", False),
            (f"WINEPREFIX={base}/motioncatalyst wine reg query HKCU", False),
            (f"WINEPREFIX={base}/motioncatalyst-ui-bare wine MotionCatalyst.exe", True),
            (
                "WINEPREFIX=~/.local/share/wineprefixes/motioncatalyst-ui-bare wineboot -u",
                True,
            ),
            (
                "WINEPREFIX=$HOME/.local/share/wineprefixes/motioncatalyst-new wineboot",
                True,
            ),
            (
                f"export WINEPREFIX={base}/motioncatalyst-ui-bare; cd /x && wine cmd /c ver",
                True,
            ),
            (
                f"env WINEPREFIX={base}/motioncatalyst-ui-bare nice -n 10 wine foo.exe",
                True,
            ),
            (
                f"timeout 60 env WINEPREFIX={base}/motioncatalyst-ui-bare winetricks dxvk",
                True,
            ),
            ("wine BUILD/x64_Debug/MotionCatalyst.exe", True),
            ("WINEPREFIX=/var/tmp/other wine notepad", False),
            ("wine notepad", False),
            (
                f"WINEPREFIX={base}/motioncatalyst-ui-bare wine x # noqa: wine-prefix",
                False,
            ),
            ("WINEPREFIX=$P/motioncatalyst-x wine foo", False),
            (f"WINEPREFIX={base}/motioncatalyst-ui-bare wineserver -k", False),
            (f"WINEPREFIX={base}/motioncatalyst-ui-bare tools/wine/run-mc.sh", False),
        ]
        failed = 0
        for command, want in cases:
            got = run(home, command)
            if got != want:
                failed += 1
                print(f"FAIL want deny={want} got {got}: {command}")
        print(f"{len(cases) - failed}/{len(cases)} passed")
        return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
