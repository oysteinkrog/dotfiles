"""Tests for cmd-timing.sh / cmd-timing.py. Run: python3 cmd-timing.test.py"""

import json
import os
import subprocess
import tempfile
from pathlib import Path

HOOK = str(Path(__file__).with_name("cmd-timing.sh"))
T = 1793865000.0  # a fixed "now" for the tests

failures = 0


def check(name, ok, detail=""):
    global failures
    if ok:
        print(f"PASS  {name}")
    else:
        failures += 1
        print(f"FAIL  {name}\n      {detail}")


def run(payload, env_extra, now=T):
    env = dict(os.environ, CMD_TIMING_NOW=str(now), **env_extra)
    p = subprocess.run(
        ["bash", HOOK],
        input=payload if isinstance(payload, str) else json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
    )
    ctx = ""
    if p.stdout.strip():
        ctx = json.loads(p.stdout)["hookSpecificOutput"]["additionalContext"]
    return p.returncode, ctx, p.stdout


def claude(cmd, secs, cwd, sid="s1", event="PostToolUse", **extra):
    return {
        "session_id": sid,
        "hook_event_name": event,
        "tool_name": "Bash",
        "tool_input": {"command": cmd, **extra},
        "tool_response": {"stdout": "ok"},
        "tool_use_id": "toolu_1",
        "cwd": cwd,
        "duration_ms": int(secs * 1000),
    }


base = Path("/var/tmp/claude")
base.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir=base) as tmp:
    tmp = Path(tmp)
    plain = tmp / "plain"
    plain.mkdir()
    repo = tmp / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    src = repo / "lib.rs"
    src.write_text("".join(f"line {i}\n" for i in range(100)))
    subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "-c",
            "user.email=t@t",
            "-c",
            "user.name=t",
            "add",
            ".",
        ],
        check=True,
    )
    subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "-c",
            "user.email=t@t",
            "-c",
            "user.name=t",
            "commit",
            "-qm",
            "init",
        ],
        check=True,
    )
    events = tmp / "events.log"
    events.write_text("")

    def env(state):
        return {
            "CMD_TIMING_STATE": str(tmp / state),
            "CMD_TIMING_JOBD_EVENTS": str(events),
        }

    # 1. Under 30 s: silent.
    rc, ctx, out = run(claude("ls -la", 10, str(plain)), env("st1"))
    check("10 s command is silent", rc == 0 and out == "", out)

    # 2. 45 s: report.
    rc, ctx, _ = run(claude("ls -la", 45, str(plain)), env("st1"))
    check("45 s command is reported", ctx == "Command took 45 s.", ctx)

    # 3. 6 min test after a 3-line change: warn.
    e = env("st3")
    run(claude("cargo test", 20, str(repo)), e, now=T - 600)
    src.write_text("".join(f"line {i}{'x' if i < 3 else ''}\n" for i in range(100)))
    rc, ctx, _ = run(claude("cargo test", 360, str(repo)), e)
    check(
        "6 min test after small diff warns",
        ctx.startswith("Command took 6 min.")
        and "Slow test loop: cargo test ran 6 min after a change of only 6 lines" in ctx
        and "check-only build" in ctx
        and "Run the full suite once at the end" in ctx,
        ctx,
    )

    # 3b. 6 min test after a big change: report only.
    e = env("st3b")
    run(claude("cargo test", 20, str(repo)), e, now=T - 600)
    src.write_text("".join(f"new {i}\n" for i in range(100)))
    rc, ctx, _ = run(claude("cargo test", 360, str(repo)), e)
    check("6 min test after big diff only reports", ctx == "Command took 6 min.", ctx)

    # 3c. Rewriting lines that were already dirty counts as a change, even
    # though the per-file add/remove counts against HEAD stay the same. The
    # real index must not change.
    e = env("st3c")
    index = repo / ".git" / "index"
    before = index.read_bytes()
    run(claude("cargo test", 20, str(repo)), e, now=T - 600)
    src.write_text("".join(f"other {i}\n" for i in range(100)))
    rc, ctx, _ = run(claude("cargo test", 360, str(repo)), e)
    check("rewrite of dirty lines is a big change", ctx == "Command took 6 min.", ctx)
    check("real git index is untouched", index.read_bytes() == before)

    # 4. Two 6 min runs within 30 min: second warns.
    e = env("st4")
    rc, ctx1, _ = run(
        claude("heavy-build -- dotnet test Foo.sln", 370, str(plain)), e, now=T - 900
    )
    rc, ctx2, _ = run(claude("heavy-build -- dotnet test Foo.sln", 365, str(plain)), e)
    check("first 6 min run only reports", ctx1 == "Command took 6 min 10 s.", ctx1)
    check(
        "second 6 min run within 30 min warns",
        "Slow test loop: dotnet test ran 6 min 5 s, and it is slow run 2 in the last 30 min (12 min 15 s in total)"
        in ctx2,
        ctx2,
    )

    # 4b. Two slow runs 40 min apart: no warn.
    e = env("st4b")
    run(claude("cargo build", 370, str(plain)), e, now=T - 2400)
    rc, ctx, _ = run(claude("cargo build", 370, str(plain)), e)
    check("slow runs 40 min apart do not warn", ctx == "Command took 6 min 10 s.", ctx)

    # 5. jobd wait split: 400 s total, 120 s wait, 280 s run.
    t0 = T - 400
    sub_ns = int((t0 + 1) * 1e9)
    rid = f"{sub_ns}-4242-abcd1234"
    from datetime import datetime, timezone

    def ts(t):
        return (
            datetime.fromtimestamp(t, timezone.utc)
            .astimezone()
            .strftime("%Y-%m-%dT%H:%M:%S%z")
        )

    other = f"{sub_ns}-999-ffff0000"
    events.write_text(
        f"{ts(t0 - 5000)} request=old-1-x event=end exit=0 reason=ok\n"
        f"{ts(t0 + 1)} request={rid} event=submit class=cargo-test prio=normal cwd={plain} argv0=cargo\n"
        f"{ts(t0 + 1)} request={other} event=submit class=cargo-test prio=normal cwd=/elsewhere argv0=cargo\n"
        f"{ts(t0 + 121)} attempt={rid}-a{int(t0 + 121)} request={rid} event=start\n"
        f"{ts(T)} request={rid} event=end exit=0 reason=ok\n"
    )
    rc, ctx, _ = run(
        claude("heavy-build -- cargo test -p foo", 400, str(plain)), env("st5")
    )
    check(
        "jobd wait is split from run time",
        ctx
        == "Command took 6 min 40 s: 2 min waiting in the jobd queue, 4 min 39 s running.",
        ctx,
    )

    # 5b. Long queue wait but short run does not count as a slow run.
    rc, ctx, _ = run(
        claude("heavy-build -- cargo test -p foo", 400, str(plain)),
        env("st5"),
        now=T + 1,
    )
    check("long wait, short run does not warn", "Slow test loop" not in ctx, ctx)

    # 6. Non-build long command: report, no warn.
    e = env("st6")
    run(claude("sleep 400", 400, str(repo)), e, now=T - 600)
    rc, ctx, _ = run(claude("sleep 400", 400, str(repo)), e)
    check(
        "long non-build command reports without warning",
        ctx == "Command took 6 min 40 s.",
        ctx,
    )

    # 7. Failure event gets the same report.
    rc, ctx, out = run(
        claude("cargo test", 45, str(plain), event="PostToolUseFailure"), env("st7")
    )
    check(
        "PostToolUseFailure is reported",
        ctx == "Command took 45 s." and '"hookEventName": "PostToolUseFailure"' in out,
        out,
    )

    # 8. Background command: silent.
    rc, ctx, out = run(
        claude("sleep 60", 60, str(plain), run_in_background=True), env("st8")
    )
    check("background command is silent", out == "", out)

    # 9. Codex: PreToolUse start time, PostToolUse without duration_ms.
    e = env("st9")
    pre = {
        "session_id": "codex-1",
        "turn_id": "t",
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": "sleep 50"},
        "tool_use_id": "call_9",
        "cwd": str(plain),
    }
    rc, _, out = run(pre, e, now=T - 50)
    post = dict(pre, hook_event_name="PostToolUse", tool_response="done")
    rc, ctx, _ = run(post, e)
    left = list((tmp / "st9" / "start").glob("*/*"))
    check(
        "Codex start/stop timing reports",
        ctx == "Command took 50 s." and not left,
        f"{ctx} {left}",
    )

    # 10. Garbage input: exit 0, no output.
    rc, ctx, out = run("not json", env("st10"))
    check("bad input fails open", rc == 0 and out == "", out)

    # 11. Other tools are ignored.
    p = claude("x", 100, str(plain))
    p["tool_name"] = "Read"
    rc, ctx, out = run(p, env("st11"))
    check("non-Bash tool is ignored", out == "", out)

print(f"\n{'OK' if not failures else f'{failures} FAILED'}")
raise SystemExit(1 if failures else 0)
