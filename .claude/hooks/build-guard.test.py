import json
import os
import shutil
import tempfile
import subprocess
import sys
from pathlib import Path

HOOK = os.environ.get("BUILD_GUARD_HOOK") or str(
    Path(__file__).with_name("build-guard.sh")
)
HOME = str(Path.home())
CWD = f"{HOME}/src/frankenterm"
MONO = f"{HOME}/work/desktop/master"

B, W, OK = "block", "warn", "allow"

# (command, cwd, expected)
cases = [
    # --- wrapped builds: allowed, no warning ---
    ("heavy-build cargo test -p mux --lib", CWD, OK),
    ("heavy-build cargo build --release", CWD, OK),
    ("cd ~/src/frankenterm && heavy-build cargo clippy --all-targets", CWD, OK),
    (
        'flock -w 7200 "$XDG_RUNTIME_DIR/heavy-build.lock" systemd-run --user --scope '
        "--slice=builds.slice -p MemoryMax=18G env CARGO_BUILD_JOBS=8 cargo test",
        CWD,
        OK,
    ),
    ("CARGO_TARGET_DIR=/var/tmp/claude/ft-x heavy-build cargo test", CWD, OK),
    ("heavy-build localbuild build frankenterm", CWD, OK),
    # --- light cargo commands: allowed, no warning ---
    ("cargo fmt", CWD, OK),
    ("cargo fmt --check", CWD, OK),
    ("cargo metadata --format-version 1 | jq .", CWD, OK),
    ("cargo tree -p mux", CWD, OK),
    ("cargo add serde", CWD, OK),
    ("cargo update -p foo", CWD, OK),
    ("cargo --version", CWD, OK),
    ("cargo test --help", CWD, OK),
    ("cargo install --list", CWD, OK),
    ("cargo run -- --help", CWD, OK),
    ("cargo nextest list", CWD, OK),
    ("cargo clean", CWD, OK),
    ("dotnet --info", CWD, OK),
    ("dotnet tool list", CWD, OK),
    # --- quoted mentions and heredocs: allowed ---
    (
        'br update x --description "run cargo test with CARGO_BUILD_BUILD_DIR=/x"',
        CWD,
        OK,
    ),
    ('git commit -m "cargo test now uses heavy-build" -- a.rs', CWD, OK),
    (
        "cat <<'EOF'\ncargo test\nCARGO_BUILD_BUILD_DIR=/var/tmp/x cargo build\nEOF",
        CWD,
        OK,
    ),
    ("rg 'cargo build' ~/src", CWD, OK),
    ("echo cargo test", CWD, OK),
    # --- unwrapped heavy builds: warned, not blocked ---
    ("cargo test", CWD, W),
    ("cargo +nightly test -p mux", CWD, W),
    ("cargo b --release", CWD, W),
    ("cd ~/src/frankenterm && cargo check", CWD, W),
    ("env FOO=1 cargo test", CWD, W),
    ("nice -n 5 cargo build", CWD, W),
    ("timeout 600 cargo test", CWD, W),
    ("(cargo test)", CWD, W),
    ("rustup run nightly cargo clippy", CWD, W),
    ("CARGO_TARGET_DIR=/var/tmp/claude/ft-x cargo test", CWD, W),
    ("dotnet build Foo.sln", CWD, W),
    ("dotnet test", CWD, W),
    ("dotnet run -- /var/tmp/x", CWD, W),
    ("timeout 600 dotnet run -- /var/tmp/x 2>&1 | tail -80", CWD, W),
    ("cd /var/tmp/claude/x && dotnet build -nodeReuse:false --no-restore", CWD, W),
    ("heavy-build dotnet run -- /var/tmp/x", CWD, OK),
    ("heavy-build dotnet build Foo.sln", CWD, OK),
    ("./build.cmd build", CWD, W),
    # --- build dir overrides: blocked ---
    ("CARGO_BUILD_BUILD_DIR=/var/tmp/x cargo test", CWD, B),
    ("env CARGO_BUILD_BUILD_DIR=/var/tmp/x cargo test", CWD, B),
    ("export CARGO_BUILD_BUILD_DIR=/var/tmp/x", CWD, B),
    ("heavy-build env CARGO_BUILD_BUILD_DIR=/var/tmp/x cargo test", CWD, B),
    ("cargo test --config 'build.build-dir=\"/var/tmp/x\"'", CWD, B),
    # --- localbuild's own build dir: allowed ---
    ('export CARGO_BUILD_BUILD_DIR="$HOME/.cache/build/cass/target"', CWD, OK),
    # --- /tmp: blocked ---
    ("git clone https://github.com/foo/bar.git /tmp/bar", CWD, B),
    ("gh repo clone foo/bar /tmp/bar", CWD, B),
    ("git -C ~/work/ifkb worktree add --detach /tmp/x HEAD", CWD, B),
    ("cd /tmp/x && cargo build", CWD, B),
    ("cargo build", "/tmp/scratch", B),
    ("heavy-build cargo build", "/tmp/scratch", OK),
    ("cargo test --target-dir /tmp/t", CWD, B),
    # --- /var/tmp: allowed ---
    ("git -C ~/work/ifkb worktree add --detach /var/tmp/claude/x HEAD", CWD, OK),
    ("git clone https://github.com/foo/bar.git /var/tmp/claude/bar", CWD, OK),
    # --- monorepo lanes outside grove: blocked ---
    ("git -C ~/work/desktop/master worktree add ~/lane-wt/x", CWD, B),
    ("git worktree add -b lane-x ~/lane-wt/x HEAD", MONO, B),
    ("git -C ~/work/desktop/master worktree add /var/tmp/claude/x", CWD, B),
    # --- monorepo lanes inside grove's work_dir: left to grove-worktree-guard ---
    ("git -C ~/work/desktop/master worktree add ~/work/desktop/.scratch/x", CWD, OK),
    # --- CPU pinning, realtime and busy loops: warned, not blocked ---
    ("taskset -c 30,31 ./run-tests.sh", CWD, W),
    ("taskset -a -p 0x3 1234", CWD, W),
    ("for i in $(seq 40); do taskset -c 30 sh -c 'while :; do :; done' & done", CWD, W),
    ("heavy-build taskset -c 0 cargo test", CWD, W),
    ("env FOO=1 nice -n 5 taskset -c 0 make", CWD, W),
    ("sh -c 'taskset -c 1 sleep 1'", CWD, W),
    ("bash -lc 'numactl --physcpubind=30,31 ./bench'", CWD, W),
    ("numactl -C 0-3 ./bench", CWD, W),
    ("numactl --physcpubind 4 ./bench", CWD, W),
    ("chrt -f 50 ./latency-test", CWD, W),
    ("chrt -r 10 ./latency-test", CWD, W),
    ("chrt --fifo 50 ./latency-test", CWD, W),
    ("chrt 50 ./latency-test", CWD, W),
    ("sudo chrt -f -p 50 1234", CWD, W),
    ("sh -c 'while :; do :; done' &", CWD, W),
    ("while true; do true; done", CWD, W),
    ("timeout 5 bash -c 'while :; do :; done'", CWD, W),
    ("taskset -c 0 sleep 1 # noqa: build-guard", CWD, OK),
    # --- CPU-related commands that are fine ---
    ("numactl --hardware", CWD, OK),
    ("numactl --interleave=all ./bench", CWD, OK),
    ("chrt -p 1234", CWD, OK),
    ("chrt -b 0 ./batch-job", CWD, OK),
    ("chrt -i 0 ./idle-job", CWD, OK),
    ("while :; do sleep 1; done", CWD, OK),
    ("while true; do date; sleep 5; done", CWD, OK),
    ("while read -r l; do echo $l; done < f", CWD, OK),
    ("rg taskset ~/src", CWD, OK),
    ('git commit -m "warn on taskset" -- a.sh', CWD, OK),
    # --- forced dotnet rebuilds: warned, wrapped or not ---
    ("heavy-build dotnet build X.csproj -c Debug --no-incremental", CWD, W),
    ("dotnet test X.csproj --no-incremental", CWD, W),
    ("heavy-build dotnet msbuild X.sln -t:Rebuild", CWD, W),
    ("heavy-build dotnet build X.sln '/t:Clean;Rebuild'", CWD, W),
    ("heavy-build dotnet build X.sln -target:Rebuild", CWD, W),
    ("heavy-build dotnet build X.sln -t:Build", CWD, OK),
    ("heavy-build dotnet build X.csproj --no-restore", CWD, OK),
    ('git commit -m "drop --no-incremental from dotnet build" -- a.sh', CWD, OK),
    ("rg -- --no-incremental tools/", CWD, OK),
    # --- monorepo Wine test runner: warned when not under heavy-build ---
    ("tools/wine/run-tests.sh --filter Foo Bar.Tests", MONO, W),
    ("./tools/wine/run-tests.sh Bar.Tests", MONO, W),
    ("bash tools/wine/run-tests.sh Bar.Tests", MONO, W),
    ("./run-tests.sh --filter Foo Bar.Tests", f"{MONO}/tools/wine", W),
    ("cd ~/work/desktop/master && tools/wine/run-tests.sh X", CWD, W),
    ("heavy-build tools/wine/run-tests.sh --filter Foo Bar.Tests", MONO, OK),
    ("HEAVY_BUILD_PRIORITY=low heavy-build ./tools/wine/run-tests.sh X", MONO, OK),
    ("./run-tests.sh", CWD, OK),
    ("sed -n 1,20p tools/wine/run-tests.sh", MONO, OK),
    # --- heavy-build in the foreground: no background warning ---
    ("heavy-build --help", CWD, OK),
    # --- bypass ---
    ("CARGO_BUILD_BUILD_DIR=/var/tmp/x cargo test # noqa: build-guard", CWD, OK),
    # --- unrelated ---
    ("ls -la", CWD, OK),
    ("git status", CWD, OK),
]


# Run with tool_input.run_in_background = true (shape checked on a real
# payload 2026-10-20: the key is present and true only for background calls).
bg_cases = [
    ("heavy-build cargo test -p mux", CWD, W),
    ("heavy-build dotnet build Foo.sln", CWD, W),
    ("HEAVY_BUILD_PRIORITY=low heavy-build tools/wine/run-tests.sh X", MONO, W),
    ("nohup heavy-build cargo build > log 2>&1", CWD, W),
    ("cd ~/src/frankenterm && heavy-build cargo build", CWD, W),
    ("cargo test", CWD, W),
    (
        "systemd-run --user --unit=hb-x --collect --same-dir heavy-build cargo test",
        CWD,
        OK,
    ),
    ("sleep 30; echo done", CWD, OK),
    ("tail -f ~/.local/state/heavy-build/live.log", CWD, OK),
    ("heavy-build cargo test # noqa: build-guard", CWD, OK),
]


def run(command, cwd, background=None):
    tool_input = {"command": command}
    if background is not None:
        tool_input["run_in_background"] = background
    payload = json.dumps(
        {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "cwd": cwd,
            "tool_input": tool_input,
        }
    )
    return subprocess.run(["bash", HOOK], input=payload, capture_output=True, text=True)


def outcome(result):
    if result.returncode == 2:
        return B
    if result.returncode == 0 and "additionalContext" in result.stdout:
        return W
    if result.returncode == 0:
        return OK
    return f"rc={result.returncode}"


def main():
    syntax = subprocess.run(["bash", "-n", HOOK], capture_output=True, text=True)
    if syntax.returncode != 0:
        print("FAIL hook is not valid bash:", syntax.stderr.strip())
        sys.exit(1)

    fails = 0
    for command, cwd, expected in cases:
        result = run(command, cwd)
        got = outcome(result)
        if got != expected:
            fails += 1
            print(f"FAIL got={got} want={expected}  {command!r} (cwd={cwd})")
            if result.stderr.strip():
                print("   stderr:", result.stderr.strip()[:300])

    for command, cwd, expected in bg_cases:
        got = outcome(run(command, cwd, background=True))
        if got != expected:
            fails += 1
            print(f"FAIL background got={got} want={expected}  {command!r}")

    # run_in_background false or a non-boolean value: no background warning.
    for value in (False, "true", 1):
        got = outcome(run("heavy-build cargo test", CWD, background=value))
        if got != OK:
            fails += 1
            print(f"FAIL run_in_background={value!r} got={got} want={OK}")

    # The warnings name the right advice.
    checks = (
        (
            ("heavy-build cargo test", CWD, True),
            ("background shell", "systemd-run --user"),
        ),
        (
            ("dotnet build X.csproj --no-incremental", CWD, None),
            ("full rebuild", "heavy-build <command>"),
        ),
        (
            ("tools/wine/run-tests.sh X", MONO, None),
            ("tools/wine/run-tests.sh", "heavy-build <command>"),
        ),
    )
    for (command, cwd, background), wants in checks:
        text = run(command, cwd, background).stdout
        for want in wants:
            if want not in text:
                fails += 1
                print(f"FAIL warning for {command!r} lacks {want!r}")
    # The no_wrapper warning no longer suggests a background shell.
    if "in the background if" in run("cargo test", CWD).stdout:
        fails += 1
        print("FAIL no_wrapper warning still suggests a background shell")

    # A garbage payload must fail open.
    bad = subprocess.run(
        ["bash", HOOK], input="not json", capture_output=True, text=True
    )
    if bad.returncode != 0 or bad.stdout.strip():
        fails += 1
        print(f"FAIL garbage payload rc={bad.returncode}")

    # A detector that crashes after printing a block line must fail open.
    with tempfile.TemporaryDirectory(dir="/var/tmp/claude") as tmp:
        shutil.copy(HOOK, tmp)
        Path(tmp, "build-detect.py").write_text(
            "import sys\nprint('block\\tbuild_dir\\tx')\nsys.exit(1)\n"
        )
        broken = subprocess.run(
            ["bash", str(Path(tmp, "build-guard.sh"))],
            input=json.dumps({"cwd": CWD, "tool_input": {"command": "cargo test"}}),
            capture_output=True,
            text=True,
        )
    if broken.returncode != 0:
        fails += 1
        print(f"FAIL broken detector rc={broken.returncode}")

    # The dotnet warning names the compiler server; the cargo warning does not.
    server = "Roslyn compiler server"
    for command, want in (
        ("dotnet run", True),
        ("dotnet test", True),
        ("cargo test", False),
    ):
        text = run(command, CWD).stdout
        if (server in text) != want:
            fails += 1
            print(f"FAIL compiler server note for {command!r}: want={want}")

    # The pin warning names the incident and keeps the build warning.
    text = run("cargo test; taskset -c 30 sleep 1", CWD).stdout
    for want in (
        "2026-10-13",
        "CPUs 30 and 31",
        "heavy-build <command>",
        "noqa: build-guard",
    ):
        if want not in text:
            fails += 1
            print(f"FAIL pin warning lacks {want!r}")

    total = len(cases) + len(bg_cases) + 3 + 6 + 1 + 2 + 3 + 4
    print(f"{total - fails}/{total} correct")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
