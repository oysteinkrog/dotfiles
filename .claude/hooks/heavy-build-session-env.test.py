"""Tests for heavy-build-session-env.py. Run: python3 heavy-build-session-env.test.py"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HOOK = str(Path(__file__).with_name("heavy-build-session-env.py"))
fails = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global fails
    print(("ok: " if ok else "FAIL: ") + name + ("" if ok else f"\n  | {detail}"))
    fails += not ok


def proc_start(pid: int) -> str:
    s = Path(f"/proc/{pid}/stat").read_text()
    return s[s.rfind(")") + 2 :].split()[19]


def run(
    tmp: Path, env_extra: dict, stdin: dict | str, env_file: Path | None
) -> subprocess.CompletedProcess:
    env = {
        k: v
        for k, v in os.environ.items()
        if k not in ("CLAUDE_PID", "CLAUDE_ENV_FILE")
    }
    env["MACHINE_SESSION_SESSIONS_DIR"] = str(tmp / "sess")
    if env_file is not None:
        env["CLAUDE_ENV_FILE"] = str(env_file)
    env.update(env_extra)
    data = stdin if isinstance(stdin, str) else json.dumps(stdin)
    return subprocess.run(
        [sys.executable, HOOK], input=data, text=True, capture_output=True, env=env
    )


def session(tmp: Path, pid: int, **fields) -> None:
    (tmp / "sess").mkdir(exist_ok=True)
    (tmp / "sess" / f"{pid}.json").write_text(
        json.dumps({"pid": pid, "procStart": proc_start(pid), **fields})
    )


def sourced(
    env_file: Path, cmd: str, shell: str = "bash", inherit: dict | None = None
) -> str:
    """Runs CMD in bash after sourcing ENV_FILE, as Claude Code does, with a
    fake systemd-run that prints its arguments."""
    script = f"source {env_file}; {cmd}"
    fake = env_file.parent / "bin"
    fake.mkdir(exist_ok=True)
    (fake / "systemd-run").write_text('#!/bin/sh\necho "systemd-run $*"\n')
    (fake / "systemd-run").chmod(0o755)
    env = {**os.environ, "PATH": f"{fake}:{os.environ['PATH']}", **(inherit or {})}
    return subprocess.run(
        [shell, "-c", script], capture_output=True, text=True, env=env
    ).stdout.strip()


with tempfile.TemporaryDirectory(dir="/var/tmp") as t:
    tmp = Path(t)
    me = (
        os.getpid()
    )  # the test is the hook's parent, so it stands in for the Claude process

    # A named session found through the parent chain.
    session(tmp, me, name="sess-a", sessionId="sid-1")
    ef = tmp / "env1"
    r = run(tmp, {}, {"session_id": "sid-1", "source": "startup"}, ef)
    text = ef.read_text() if ef.exists() else ""
    check(
        "writes the pid and the name",
        f"export HEAVY_BUILD_SESSION_PID={me}\n" in text
        and "export HEAVY_BUILD_SESSION=sess-a\n" in text,
        text,
    )
    check(
        "prints nothing (stdout becomes model context) and exits 0",
        r.stdout == "" and r.returncode == 0,
        r.stdout + r.stderr,
    )
    out = sourced(
        ef,
        "echo $HEAVY_BUILD_SESSION $HEAVY_BUILD_SESSION_PID; systemd-run --user --unit=x heavy-build true",
    )
    check(
        "sourced: variables set, systemd-run gets -E for all three and the original args",
        out.splitlines()
        == [
            f"sess-a {me}",
            "systemd-run -E HEAVY_BUILD_SESSION -E HEAVY_BUILD_SESSION_PID -E CLAUDE_PID --user --unit=x heavy-build true",
        ],
        out,
    )
    out = subprocess.run(
        ["zsh", "-c", f"source {ef}; whence -w systemd-run"],
        capture_output=True,
        text=True,
    ).stdout.strip()
    check(
        "zsh (the Bash tool's shell here) reads it too",
        out == "systemd-run: function",
        out,
    )

    # A second run (resume, clear, compact) replaces the block and keeps other lines.
    ef.write_text("export OTHER=1\n" + ef.read_text())
    session(tmp, me, name="sess-a-renamed", sessionId="sid-1")
    run(tmp, {}, {"session_id": "sid-1", "source": "resume"}, ef)
    text = ef.read_text()
    check(
        "a second run replaces its block and keeps other lines",
        text.count("# >>> heavy-build session") == 1
        and "export OTHER=1\n" in text
        and "HEAVY_BUILD_SESSION=sess-a-renamed" in text,
        text,
    )

    # A name outside [A-Za-z0-9._@+-] is left out (heavy-build uses the pid).
    session(tmp, me, name="it's a test", sessionId="sid-1")
    ef3 = tmp / "env3"
    run(tmp, {}, {"session_id": "sid-1"}, ef3)
    out = sourced(
        ef3, 'printf "%s|%s" "${HEAVY_BUILD_SESSION-unset}" "$HEAVY_BUILD_SESSION_PID"'
    )
    check(
        "a name with a space and a quote is left out, the pid stays",
        out == f"unset|{me}",
        out,
    )

    # Astra 1: a name built to fake the end marker cannot inject a command,
    # on the first write or on the rewrite after it, in bash or zsh.
    evil = '\n# <<< heavy-build session\nprintf "INJECTED\\n"\n#'
    session(tmp, me, name=evil, sessionId="sid-1")
    ef9 = tmp / "env9"
    run(tmp, {}, {"session_id": "sid-1"}, ef9)
    run(tmp, {}, {"session_id": "sid-1", "source": "resume"}, ef9)
    text = ef9.read_text()
    outs = [
        sourced(ef9, 'echo "${HEAVY_BUILD_SESSION-unset}"', sh)
        for sh in ("bash", "zsh")
    ]
    check(
        "a name with a newline and a fake end marker is not written and runs nothing",
        "INJECTED" not in text
        and text.count("# <<< heavy-build session") == 1
        and outs == ["unset", "unset"],
        text + repr(outs),
    )

    # An unnamed session: the pid only.
    session(tmp, me, sessionId="sid-1")
    ef4 = tmp / "env4"
    run(tmp, {}, {"session_id": "sid-1"}, ef4)
    text = ef4.read_text()
    check(
        "an unnamed session gets the pid and no name",
        "HEAVY_BUILD_SESSION_PID=" in text
        and "export HEAVY_BUILD_SESSION=" not in text,
        text,
    )
    # Astra 2: a name inherited from another session is unset.
    outs = [
        sourced(
            ef4,
            'echo "${HEAVY_BUILD_SESSION-unset}"',
            sh,
            {"HEAVY_BUILD_SESSION": "someone-else"},
        )
        for sh in ("bash", "zsh")
    ]
    check(
        "an unnamed session unsets an inherited HEAVY_BUILD_SESSION (bash, zsh)",
        outs == ["unset", "unset"],
        repr(outs),
    )

    # A session file of another session id does not count.
    session(tmp, me, name="other", sessionId="sid-2")
    ef5 = tmp / "env5"
    run(tmp, {}, {"session_id": "sid-1"}, ef5)
    text = ef5.read_text() if ef5.exists() else ""
    check(
        "a file with another sessionId is not used for the name",
        "other" not in text and "unset HEAVY_BUILD_SESSION\n" in text,
        text,
    )

    # CLAUDE_PID wins over the parent chain.
    sp = subprocess.Popen(["sleep", "60"])
    try:
        session(tmp, sp.pid, name="via-claude-pid", sessionId="sid-1")
        session(tmp, me, name="parent", sessionId="sid-1")
        ef6 = tmp / "env6"
        run(tmp, {"CLAUDE_PID": str(sp.pid)}, {"session_id": "sid-1"}, ef6)
        text = ef6.read_text()
        check(
            "CLAUDE_PID names the session first",
            f"HEAVY_BUILD_SESSION_PID={sp.pid}\n" in text
            and "=via-claude-pid\n" in text,
            text,
        )
    finally:
        sp.kill()
        sp.wait()

    # A stale session file (procStart of another process) is ignored.
    (tmp / "sess" / f"{me}.json").write_text(
        json.dumps({"pid": me, "procStart": "1", "name": "stale", "sessionId": "sid-1"})
    )
    ef7 = tmp / "env7"
    run(tmp, {}, {"session_id": "sid-1"}, ef7)
    text = ef7.read_text() if ef7.exists() else ""
    check(
        "a session file with the wrong procStart is ignored", "stale" not in text, text
    )

    # Astra 3: no session file at all. The block is still written: the pid
    # from CLAUDE_PID, the wrapper, the name unset, and an old block replaced.
    (tmp / "sess" / f"{me}.json").unlink()
    sp = subprocess.Popen(["sleep", "60"])
    try:
        ef10 = tmp / "env10"
        ef10.write_text(
            "# >>> heavy-build session (heavy-build-session-env.py)\nexport HEAVY_BUILD_SESSION_PID=1\n"
            "export HEAVY_BUILD_SESSION=old\n# <<< heavy-build session\n"
        )
        run(tmp, {"CLAUDE_PID": str(sp.pid)}, {"session_id": "sid-1"}, ef10)
        text = ef10.read_text()
        out = sourced(
            ef10,
            'echo "${HEAVY_BUILD_SESSION-unset} $HEAVY_BUILD_SESSION_PID"; systemd-run x',
        )
        check(
            "no session file: pid from CLAUDE_PID, wrapper written, old block replaced",
            out.splitlines()
            == [
                f"unset {sp.pid}",
                "systemd-run -E HEAVY_BUILD_SESSION -E HEAVY_BUILD_SESSION_PID -E CLAUDE_PID x",
            ]
            and text.count("# >>> heavy-build session") == 1,
            text + out,
        )
    finally:
        sp.kill()
        sp.wait()
    # With a dead CLAUDE_PID the pid comes from the nearest parent named claude
    # (here the real Claude Code process, if any) or is unset; the wrapper stays.
    ef11 = tmp / "env11"
    run(tmp, {"CLAUDE_PID": "999999999"}, {"session_id": "sid-1"}, ef11)
    text = ef11.read_text() if ef11.exists() else ""
    check(
        "a dead CLAUDE_PID is not written; the wrapper still is",
        "=999999999" not in text and "systemd-run() {" in text,
        text,
    )

    # No CLAUDE_ENV_FILE, bad input: exit 0, nothing printed.
    r = run(tmp, {}, {"session_id": "sid-1"}, None)
    r2 = run(tmp, {}, "not json", tmp / "env8")
    check(
        "no CLAUDE_ENV_FILE or bad JSON: exit 0, no output",
        r.returncode == 0 and r.stdout == "" and r2.returncode == 0 and r2.stdout == "",
        r.stderr + r2.stderr,
    )

sys.exit(1 if fails else 0)
