import json
import shutil
import tempfile
import subprocess
import sys
from pathlib import Path

HOOK = str(Path(__file__).with_name("build-guard.sh"))
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
    # --- bypass ---
    ("CARGO_BUILD_BUILD_DIR=/var/tmp/x cargo test # noqa: build-guard", CWD, OK),
    # --- unrelated ---
    ("ls -la", CWD, OK),
    ("git status", CWD, OK),
]


def run(command, cwd):
    payload = json.dumps(
        {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "cwd": cwd,
            "tool_input": {"command": command},
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

    total = len(cases) + 2
    print(f"{total - fails}/{total} correct")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
