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
    rc, ctx1, _ = run(claude("dotnet test Foo.sln", 370, str(plain)), e, now=T - 900)
    rc, ctx2, _ = run(claude("dotnet test Foo.sln", 365, str(plain)), e)
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

    # 5c. A retried job counts both attempts as run time.
    rid2 = f"{sub_ns}-4343-abcd5678"
    a1, a2 = f"{rid2}-a{int(t0 + 11)}", f"{rid2}-a{int(t0 + 261)}"
    events.write_text(
        f"{ts(t0 + 1)} request={rid2} event=submit class=cargo-test prio=normal cwd={plain} argv0=cargo\n"
        f"{ts(t0 + 11)} attempt={a1} request={rid2} event=start worker=home\n"
        f"{ts(t0 + 251)} attempt={a1} request={rid2} event=route-failed worker=home\n"
        f"{ts(t0 + 261)} attempt={a2} request={rid2} event=start\n"
        f"{ts(T)} request={rid2} event=end exit=0 reason=ok\n"
    )
    rc, ctx, _ = run(claude("heavy-build -- cargo test", 400, str(plain)), env("st5c"))
    check(
        "retried job sums both attempts",
        ctx.startswith(
            "Command took 6 min 40 s: 20 s waiting in the jobd queue, 6 min 19 s running."
        ),
        ctx,
    )

    # 5d. An absolute path to heavy-build is still a queue call.
    rc, ctx, _ = run(
        claude("/usr/local/bin/heavy-build -- cargo test", 400, str(plain)),
        env("st5d"),
    )
    check(
        "absolute heavy-build path gets the split",
        "waiting in the jobd queue" in ctx,
        ctx,
    )

    # 5e. Two jobs from the same folder but one queue call: no split, no warn.
    rid3 = f"{sub_ns}-4444-abcd9999"
    events.write_text(
        events.read_text()
        + f"{ts(t0 + 2)} request={rid3} event=submit class=cargo-test prio=normal cwd={plain} argv0=cargo\n"
        f"{ts(t0 + 2)} attempt={rid3}-a{int(t0 + 2)} request={rid3} event=start\n"
        f"{ts(T - 1)} request={rid3} event=end exit=0 reason=ok\n"
    )
    e = env("st5e")
    run(claude("heavy-build -- cargo test", 400, str(plain)), e, now=T - 600)
    rc, ctx, _ = run(claude("heavy-build -- cargo test", 400, str(plain)), e)
    check(
        "ambiguous jobs give no split and no warning",
        ctx == "Command took 6 min 40 s.",
        ctx,
    )

    # 5f. Queue call with no matching jobd events: never warn on elapsed time.
    events.write_text("")
    e = env("st5f")
    run(claude("heavy-build -- cargo test", 400, str(plain)), e, now=T - 600)
    rc, ctx, _ = run(claude("heavy-build -- cargo test", 400, str(plain)), e)
    check(
        "queue call without events does not warn",
        ctx == "Command took 6 min 40 s.",
        ctx,
    )

    # 5g. Wait with no attempt at all (cancelled in the queue) is all wait.
    rid4 = f"{sub_ns}-4545-abcd0000"
    events.write_text(
        f"{ts(t0 + 1)} request={rid4} event=submit class=cargo-test prio=normal cwd={plain} argv0=cargo\n"
        f"{ts(T)} request={rid4} event=end exit=75 reason=cancel\n"
    )
    rc, ctx, _ = run(claude("heavy-build -- cargo test", 400, str(plain)), env("st5g"))
    check(
        "job that never started is all wait",
        ctx
        == "Command took 6 min 40 s: 6 min 39 s waiting in the jobd queue, 0 s running.",
        ctx,
    )

    # 5h. Our job still queued while another session's job in the same
    # folder ended: no split.
    rid5, rid6 = f"{sub_ns}-4646-aaaa0001", f"{sub_ns}-4747-aaaa0002"
    events.write_text(
        f"{ts(t0 + 1)} request={rid5} event=submit class=cargo-test prio=normal cwd={plain} argv0=cargo\n"
        f"{ts(t0 + 3)} request={rid6} event=submit class=cargo-test prio=normal cwd={plain} argv0=cargo\n"
        f"{ts(t0 + 3)} attempt={rid6}-a{int(t0 + 3)} request={rid6} event=start\n"
        f"{ts(T - 5)} request={rid6} event=end exit=0 reason=ok\n"
    )
    rc, ctx, _ = run(claude("heavy-build -- cargo test", 400, str(plain)), env("st5h"))
    check("unfinished own job gives no split", ctx == "Command took 6 min 40 s.", ctx)

    # 5i. A failed last attempt stops counting at the failure.
    rid7 = f"{sub_ns}-4848-aaaa0003"
    a7 = f"{rid7}-a{int(t0 + 11)}"
    events.write_text(
        f"{ts(t0 + 1)} request={rid7} event=submit class=cargo-test prio=normal cwd={plain} argv0=cargo\n"
        f"{ts(t0 + 11)} attempt={a7} request={rid7} event=start worker=home\n"
        f"{ts(t0 + 21)} attempt={a7} request={rid7} event=route-failed worker=home\n"
        f"{ts(T)} request={rid7} event=end exit=75 reason=cancel\n"
    )
    rc, ctx, _ = run(claude("heavy-build -- cargo test", 400, str(plain)), env("st5i"))
    check(
        "failed last attempt is not run time",
        ctx
        == "Command took 6 min 40 s: 6 min 29 s waiting in the jobd queue, 10 s running.",
        ctx,
    )

    # 5j. Two queue jobs ran in parallel: queue time exceeds elapsed, no split.
    t2 = T - 210
    s8 = int((t2 + 1) * 1e9)
    r8, r9 = f"{s8}-4949-aaaa0008", f"{s8}-5050-aaaa0009"
    events.write_text(
        f"{ts(t2 + 1)} request={r8} event=submit class=cargo-test prio=normal cwd={plain} argv0=cargo\n"
        f"{ts(t2 + 1)} request={r9} event=submit class=cargo-test prio=normal cwd={plain} argv0=cargo\n"
        f"{ts(t2 + 2)} attempt={r8}-a{int(t2 + 2)} request={r8} event=start\n"
        f"{ts(t2 + 2)} attempt={r9}-a{int(t2 + 2)} request={r9} event=start\n"
        f"{ts(T - 1)} request={r8} event=end exit=0 reason=ok\n"
        f"{ts(T - 1)} request={r9} event=end exit=0 reason=ok\n"
    )
    rc, ctx, _ = run(
        claude(
            "heavy-build -- cargo test -p a & heavy-build -- cargo test -p b; wait",
            210,
            str(plain),
        ),
        env("st5j"),
    )
    check("parallel queue jobs give no split", ctx == "Command took 3 min 30 s.", ctx)

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

    # 12. The build's own folder is used, not the folder after a later cd.
    e = env("st12")
    cmd = f"cd {repo} && cargo test; cd /"
    run(claude(cmd, 20, str(plain)), e, now=T - 600)
    src.write_text(src.read_text().replace("other 5\n", "changed 5\n"))
    rc, ctx, _ = run(claude(cmd, 360, str(plain)), e)
    check("build folder is taken at the build segment", "Slow test loop" in ctx, ctx)

    # 13. A changed binary file is not a small change.
    blob = repo / "data.bin"
    blob.write_bytes(bytes(range(256)) * 4)
    git_c = ["git", "-C", str(repo), "-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run([*git_c, "add", "data.bin"], check=True)
    subprocess.run([*git_c, "commit", "-qm", "bin"], check=True)
    e = env("st13")
    run(claude("cargo test", 20, str(repo)), e, now=T - 600)
    blob.write_bytes(bytes(reversed(range(256))) * 400)
    rc, ctx, _ = run(claude("cargo test", 360, str(repo)), e)
    check("binary change does not count as small", ctx == "Command took 6 min.", ctx)

    # 14. Fast path: tool_response before tool_input still records the build.
    e = env("st14")
    raw = (
        '{"session_id":"s14","hook_event_name":"PostToolUse","tool_name":"Bash",'
        '"tool_response":{"stdout":"ok"},"tool_input":{"command":"cargo test"},'
        f'"cwd":"{repo}","duration_ms":1000}}'
    )
    run(raw, e)
    check(
        "field order does not skip build tracking", (tmp / "st14" / "s14.json").exists()
    )

    # 15. Fast path: a duration_ms inside the tool output is not used.
    raw = (
        '{"session_id":"s15","hook_event_name":"PostToolUse","tool_name":"Bash",'
        '"tool_input":{"command":"ls"},"tool_response":{"duration_ms":1},'
        f'"cwd":"{plain}","duration_ms":60000}}'
    )
    rc, ctx, _ = run(raw, env("st15"))
    check(
        "nested duration_ms does not hide the report", ctx == "Command took 1 min.", ctx
    )

    # 16. Codex call with one duration_ms nested in the output: still timed.
    e = env("st16")
    pre16 = {
        "session_id": "codex-16",
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": "ls"},
        "tool_use_id": "call_16",
        "cwd": str(plain),
    }
    run(pre16, e, now=T - 60)
    post16 = dict(
        pre16, hook_event_name="PostToolUse", tool_response={"duration_ms": 1}
    )
    rc, ctx, _ = run(post16, e)
    check(
        "Codex call with nested duration_ms is reported",
        ctx == "Command took 1 min.",
        ctx,
    )

    # 17. exec-style input with cmd and workdir.
    e = env("st17")
    pre17 = {
        "session_id": "codex-17",
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"cmd": "cargo test", "workdir": str(repo)},
        "tool_use_id": "call_17",
        "cwd": str(plain),
    }
    run(pre17, e, now=T - 45)
    rc, ctx, _ = run(dict(pre17, hook_event_name="PostToolUse"), e)
    snaps = json.loads((tmp / "st17" / "codex-17.json").read_text())["snapshots"]
    check(
        "cmd and workdir inputs are used",
        ctx == "Command took 45 s." and str(repo) in snaps,
        f"{ctx} {snaps}",
    )

    # 18. Options with values before the subcommand.
    e = env("st18")
    run(claude("npm --prefix web test", 5, str(repo), sid="s18"), e)
    check(
        "npm --prefix web test is a test run",
        (tmp / "st18" / "s18.json").exists(),
    )

    # 19. A cd inside ( ... ) does not change the folder after it.
    e = env("st19")
    run(claude("(cd / && true); cargo test", 5, str(repo), sid="s19"), e)
    snaps = json.loads((tmp / "st19" / "s19.json").read_text())["snapshots"]
    check("subshell cd is scoped", str(repo) in snaps, snaps)

    # 20. go -C names the build folder.
    e = env("st20")
    run(claude(f"go -C {repo} test ./...", 5, str(plain), sid="s20"), e)
    snaps = json.loads((tmp / "st20" / "s20.json").read_text())["snapshots"]
    check("go -C sets the build folder", str(repo) in snaps, snaps)

    # 21. A call that moved to the background after its time limit: silent.
    p21 = claude("cargo test", 120, str(plain), sid="s21")
    p21["tool_response"] = {"stdout": "", "backgroundTaskId": "bg1"}
    rc, ctx, out = run(p21, env("st21"))
    check(
        "auto-backgrounded call is silent",
        out == "" and not (tmp / "st21" / "s21.json").exists(),
        out,
    )

    # 22. Edits inside a dirty submodule are not a small change.
    sub = tmp / "subsrc"
    sub.mkdir()
    gs = ["git", "-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run([*gs, "init", "-q", str(sub)], check=True)
    (sub / "a.txt").write_text("".join(f"s {i}\n" for i in range(100)))
    subprocess.run([*gs, "-C", str(sub), "add", "."], check=True)
    subprocess.run([*gs, "-C", str(sub), "commit", "-qm", "s"], check=True)
    sup = tmp / "super"
    sup.mkdir()
    subprocess.run([*gs, "init", "-q", str(sup)], check=True)
    subprocess.run(
        [
            *gs,
            "-C",
            str(sup),
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "add",
            "-q",
            str(sub),
            "mod",
        ],
        check=True,
        capture_output=True,
    )
    subprocess.run([*gs, "-C", str(sup), "commit", "-qm", "add mod"], check=True)
    e = env("st22")
    run(claude("cargo test", 20, str(sup), sid="s22"), e, now=T - 600)
    (sup / "mod" / "a.txt").write_text("".join(f"t {i}\n" for i in range(100)))
    rc, ctx, _ = run(claude("cargo test", 360, str(sup), sid="s22"), e)
    check("dirty submodule is not a small change", ctx == "Command took 6 min.", ctx)

    # 23. --manifest-path points the snapshot at the tested repo.
    e = env("st23")
    run(
        claude(
            f"cargo test --manifest-path {repo}/Cargo.toml", 5, str(plain), sid="s23"
        ),
        e,
    )
    snaps = json.loads((tmp / "st23" / "s23.json").read_text())["snapshots"]
    check("--manifest-path sets the build folder", str(repo) in snaps, snaps)

    # 24. A submodule moved to another clean commit is not a small change.
    (sub / "a.txt").write_text("".join(f"u {i}\n" for i in range(100)))
    subprocess.run([*gs, "-C", str(sub), "commit", "-qam", "u"], check=True)
    subprocess.run(
        [*gs, "-C", str(sup / "mod"), "checkout", "-q", "--", "."], check=True
    )
    e = env("st24")
    run(claude("cargo test", 20, str(sup), sid="s24"), e, now=T - 600)
    subprocess.run(
        [*gs, "-C", str(sup / "mod"), "-c", "protocol.file.allow=always", "pull", "-q"],
        check=True,
        capture_output=True,
    )
    rc, ctx, _ = run(claude("cargo test", 360, str(sup), sid="s24"), e)
    check(
        "new submodule commit is not a small change", ctx == "Command took 6 min.", ctx
    )

    # 25. cmake --build on an outside build folder snapshots the source repo.
    bdir = tmp / "cmbuild"
    bdir.mkdir()
    (bdir / "CMakeCache.txt").write_text(f"CMAKE_HOME_DIRECTORY:INTERNAL={repo}\n")
    e = env("st25")
    run(claude(f"cmake --build {bdir}", 5, str(plain), sid="s25"), e)
    snaps = json.loads((tmp / "st25" / "s25.json").read_text())["snapshots"]
    check("cmake --build uses the source repo", str(repo) in snaps, snaps)

    # 26. Removing a submodule is not a small change.
    e = env("st26")
    run(claude("cargo test", 20, str(sup), sid="s26"), e, now=T - 600)
    subprocess.run([*gs, "-C", str(sup), "rm", "-q", "-f", "mod"], check=True)
    rc, ctx, _ = run(claude("cargo test", 360, str(sup), sid="s26"), e)
    check("removed submodule is not a small change", ctx == "Command took 6 min.", ctx)

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
