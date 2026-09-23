import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HOOK = str(Path(__file__).with_name("python-lint-hook.sh"))

BAD = "import os\ndef f( x ):\n    return x+1\n"
TYPE_BAD = 'def g() -> int:\n    return "s"\n'
CLEAN = "def f(x: int) -> int:\n    return x + 1\n"


def run_hook(payload: str, env: dict | None = None) -> tuple[int, str, str]:
    p = subprocess.run(
        ["bash", HOOK],
        input=payload,
        capture_output=True,
        text=True,
        timeout=120,
        env=env,
    )
    return p.returncode, p.stdout, p.stderr


def payload_for(path: Path, tool: str = "Edit") -> str:
    return json.dumps(
        {
            "hook_event_name": "PostToolUse",
            "tool_name": tool,
            "tool_input": {"file_path": str(path)},
            "cwd": str(path.parent),
        }
    )


failures = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global failures
    if ok:
        print(f"PASS  {name}")
    else:
        failures += 1
        print(f"FAIL  {name}\n      {detail}")


with tempfile.TemporaryDirectory() as tmp:
    repo = Path(tmp) / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    outside = Path(tmp) / "outside"
    outside.mkdir()

    bad = repo / "bad.py"
    bad.write_text(BAD)
    typebad = repo / "typebad.py"
    typebad.write_text(TYPE_BAD)
    clean = repo / "clean.py"
    clean.write_text(CLEAN)
    venv = repo / ".venv" / "lib" / "mod.py"
    venv.parent.mkdir(parents=True)
    venv.write_text(BAD)
    sitep = repo / "lib" / "site-packages" / "mod.py"
    sitep.parent.mkdir(parents=True)
    sitep.write_text(BAD)
    out_file = outside / "bad.py"
    out_file.write_text(BAD)
    notpy = repo / "notes.txt"
    notpy.write_text(BAD)

    have_ruff = shutil.which("ruff") is not None
    have_ty = shutil.which("ty") is not None

    # --- reports findings, never rewrites ---
    code, out, _ = run_hook(payload_for(bad))
    check("bad file: exit 0", code == 0, f"exit {code}")
    check("bad file: not rewritten", bad.read_text() == BAD, repr(bad.read_text()))
    if have_ruff:
        try:
            ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        except (ValueError, KeyError, TypeError):
            ctx = ""
        check("bad file: JSON additionalContext", bool(ctx), repr(out))
        check("bad file: ruff check finding", "F401" in ctx, ctx)
        check("bad file: format finding", "not formatted" in ctx, ctx)
    if have_ty:
        code, out, _ = run_hook(payload_for(typebad, "Write"))
        check("type error: reported", "ty check" in out, repr(out))

    # --- silent cases ---
    for name, pl in [
        ("clean file", payload_for(clean)),
        ("under .venv", payload_for(venv)),
        ("under site-packages", payload_for(sitep)),
        ("outside git repo", payload_for(out_file)),
        ("not a .py file", payload_for(notpy)),
        ("missing file", payload_for(repo / "gone.py")),
        ("empty payload", ""),
        ("malformed JSON", '{"tool_input": {"file_path": "x.py"'),
        ("no tool_input", '{"tool_name": "Edit", "x": "a.py"}'),
        ("file_path not a string", '{"tool_input": {"file_path": 5}, "y": "a.py"}'),
    ]:
        code, out, err = run_hook(pl)
        check(
            f"{name}: exit 0, no output",
            code == 0 and out == "",
            f"{code} {out!r} {err!r}",
        )

    # --- tools missing from PATH: skip silently ---
    env = dict(os.environ)
    env["PATH"] = os.pathsep.join(
        str(Path(p)) for p in ["/usr/bin", "/bin", str(Path(sys.executable).parent)]
    )
    if shutil.which("ruff", path=env["PATH"]) is None:
        code, out, _ = run_hook(payload_for(bad), env)
        check(
            "no ruff/ty on PATH: exit 0, no output", code == 0 and out == "", repr(out)
        )

    # --- timeout is reported, not raised ---
    if have_ruff:
        env = dict(os.environ, PYLINT_HOOK_TIMEOUT="0")
        code, out, _ = run_hook(payload_for(bad), env)
        check("timeout: exit 0", code == 0, f"exit {code}")
        check("timeout: reported", "timed out" in out, repr(out))

print(f"\n{'OK' if failures == 0 else f'{failures} FAILED'}")
sys.exit(1 if failures else 0)
