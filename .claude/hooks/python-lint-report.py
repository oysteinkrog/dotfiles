"""PostToolUse report for Write/Edit/MultiEdit on *.py files.

Runs three checks on the edited file and hands any findings back to the agent
as additionalContext:

    ruff check            lint findings (no --fix)
    ruff format --check   whether the file needs formatting (no rewrite)
    ty check              type errors

The hook reports and never rewrites. Two reasons:

1. An agent often edits a file in steps: add an import, then add the code
   that uses it. `ruff check --fix` between those steps deletes the import as
   unused (F401), and the next step silently breaks.
2. Rewriting the file after every edit changes its text under the agent. The
   next Edit's old_string was copied from the agent's last read, so it can
   stop matching and the Edit fails.

So the fixing commands stay a manual step, run once when the work is done:
`ruff check --fix && ruff format && ty check` (the Python rule in ~/CLAUDE.md).

Skips: non-.py files, files outside a git repo, files under site-packages or a
.venv, and any tool not on PATH. Each tool is time-boxed. Every failure of
this script exits 0 with no output, so the tool call is never affected.

Test matrix in python-lint-hook.test.py.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

TIMEOUT_S = int(os.environ.get("PYLINT_HOOK_TIMEOUT", "20"))
MAX_LINES = 40
SKIP_PARTS = {"site-packages", ".venv"}


def run(cmd: list[str], cwd: Path) -> tuple[int, str] | None:
    try:
        p = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_S,
            stdin=subprocess.DEVNULL,
        )
    except subprocess.TimeoutExpired:
        return (-1, f"timed out after {TIMEOUT_S} s")
    except OSError:
        return None
    return (p.returncode, (p.stdout + p.stderr).strip())


def clip(text: str) -> str:
    lines = text.splitlines()
    if len(lines) <= MAX_LINES:
        return text
    rest = len(lines) - MAX_LINES
    return "\n".join(lines[:MAX_LINES] + [f"... {rest} more lines"])


def git_root(path: Path) -> Path | None:
    try:
        p = subprocess.run(
            ["git", "-C", str(path.parent), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
            stdin=subprocess.DEVNULL,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0 or not p.stdout.strip():
        return None
    return Path(p.stdout.strip())


def report(payload: dict) -> str | None:
    raw = (payload.get("tool_input") or {}).get("file_path") or ""
    if not raw.endswith(".py"):
        return None
    path = Path(raw)
    if not path.is_absolute():
        path = Path(payload.get("cwd") or os.getcwd()) / path
    if SKIP_PARTS & set(path.parts) or not path.is_file():
        return None
    root = git_root(path)
    if root is None:
        return None

    ruff = shutil.which("ruff")
    ty = shutil.which("ty")
    checks: list[tuple[str, list[str]]] = []
    if ruff:
        checks.append(
            (
                "ruff check",
                [ruff, "check", "--quiet", "--output-format", "concise", str(path)],
            )
        )
        checks.append(("ruff format --check", [ruff, "format", "--check", str(path)]))
    if ty:
        checks.append(("ty check", [ty, "check", str(path)]))

    findings = []
    for name, cmd in checks:
        res = run(cmd, root)
        if res is None:
            continue
        code, out = res
        if code == 0:
            continue
        if name == "ruff format --check":
            out = "file is not formatted"
        findings.append(f"[{name}]\n{clip(out) or f'exit {code}'}")

    if not findings:
        return None
    return (
        f"Python checks on {path} found issues (report only, file not changed):\n\n"
        + "\n\n".join(findings)
        + "\n\nWhen this edit sequence is done, run: "
        "ruff check --fix && ruff format && ty check"
    )


def main() -> None:
    try:
        text = report(json.loads(sys.stdin.read() or "{}"))
    except Exception:
        return
    if text:
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": text,
            }
        }
        print(json.dumps(out))


if __name__ == "__main__":
    main()
