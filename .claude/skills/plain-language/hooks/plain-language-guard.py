#!/usr/bin/env python3
"""Run the plain-language gate on anything about to reach a person.

Wired as a PreToolUse hook on the tools that publish text (file writes,
artifacts, commits, pull requests, Jira, Slack, email) and as a Stop hook on
the reply itself. Product strings, code and machine formats are out of scope,
so those paths are skipped.

Exit codes follow the Claude Code hook contract:
    0  allow
    2  block, and give the model stderr as the reason

Off switches, in order of precedence:
    PLAINLANG_OFF=1                     everything off
    PLAINLANG_MODE=warn                 report but never block
    a `plainlang: skip` line in the text itself
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

SKILL_DIR = Path(os.environ.get("PLAINLANG_HOME", Path.home() / ".claude/skills/plain-language"))
PL = os.environ.get("PLAINLANG_BIN", str(Path.home() / "bin/pl"))
STATE = Path(os.environ.get("TMPDIR", "/tmp")) / "plainlang-hook"

# Files a person reads as prose. Everything else is code or machine format.
PROSE_SUFFIXES = {".md", ".markdown", ".mdx", ".txt", ".rst", ".adoc"}
# Paths that carry product copy or generated text, which other rules own.
SKIP_PATH = re.compile(
    r"(?:/|^)(?:node_modules|\.git|BUILD|obj|bin|dist|vendor|third[_-]party|"
    r"CHANGELOG\.md|LICENSE|\.beads/|locali[sz]ation|Resources?/|Strings?/)",
    re.I,
)
SKIP_SUFFIX = re.compile(r"\.(?:resx|xaml|xlf|xliff|po|pot|json|ya?ml|csv|tsv|lock)$", re.I)

SKIP_MARKER = re.compile(r"(?mi)^\s*(?:<!--\s*)?plainlang:\s*skip")

WRITING_ASK = re.compile(
    r"\b(?:write|draft|compose|word|reword|rewrite|summari[sz]e|summary|explain|document|"
    r"docs?|readme|report|brief|memo|plan|proposal|announce|announcement|release notes|"
    r"changelog|commit message|pr body|pull request|jira|ticket|slack|message|email|mail|"
    r"comment|artifact|page|post|blog|title|heading|headline|copy)\b", re.I)

MIN_WORDS = int(os.environ.get("PLAINLANG_MIN_WORDS", "40"))
STOP_MIN_WORDS = int(os.environ.get("PLAINLANG_STOP_MIN_WORDS", "60"))


def read_event() -> dict:
    try:
        return json.loads(sys.stdin.read() or "{}")
    except Exception:
        return {}


def word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z][A-Za-z'-]*", text))


def gate(text: str, *, min_score: float | None = None) -> dict | None:
    """Score text. Returns the report dict, or None when the tool is unavailable."""
    args = [PL, "json", "-"]
    if min_score is not None:
        args += ["--min-score", str(min_score)]
    try:
        proc = subprocess.run(args, input=text, capture_output=True, text=True, timeout=25)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if not proc.stdout.strip():
        return None
    try:
        rep = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    rep["_failed"] = proc.returncode != 0
    return rep


def summarise(rep: dict, label: str) -> str:
    lines = [
        f"plain-language gate: {label} scored {rep['score']:.0f}/100 ({rep['grade']}), "
        f"{int(rep['stats'].get('errors', 0))} hard-rule violation(s)."
    ]
    shown = 0
    for f in rep.get("findings", []):
        if f["severity"] == "info" and shown >= 3:
            continue
        if shown >= 8:
            break
        excerpt = (f.get("excerpt") or "").strip().replace("\n", " ")[:70]
        fix = f" -> {f['suggest']}" if f.get("suggest") else ""
        lines.append(f"  {f['line']}:{f['col']} [{f['severity']}] {f['rule']}: {f['message']} \"{excerpt}\"{fix}")
        shown += 1
    lines.append("Rewrite the text against the plain-language skill, then try again. "
                 "If this text is out of scope (product copy, quoted material, a machine format), "
                 "say so and add a `plainlang: skip` line.")
    return "\n".join(lines)


# --- extracting the human-facing text from a tool call ----------------------

def from_bash(cmd: str) -> tuple[str, str] | None:
    m = re.search(r"git\s+commit\b[^\n]*?-m\s*(['\"])(?P<msg>.*?)\1", cmd, re.S)
    if m and word_count(m.group("msg")) >= 25:
        return m.group("msg"), "commit message"
    m = re.search(r"gh\s+(?:pr|issue)\s+(?:create|edit)\b.*?--body(?:-file)?\s*(['\"])(?P<b>.*?)\1", cmd, re.S)
    if m:
        return m.group("b"), "pull request body"
    m = re.search(r"gh\s+api\b.*?-f\s+body=(['\"])(?P<b>.*?)\1", cmd, re.S)
    if m:
        return m.group("b"), "pull request body"
    return None


def from_tool(name: str, ti: dict) -> tuple[str, str] | None:
    n = name.lower()
    if name in {"Write", "Edit"}:
        path = ti.get("file_path") or ""
        if SKIP_PATH.search(path) or SKIP_SUFFIX.search(path):
            return None
        if Path(path).suffix.lower() not in PROSE_SUFFIXES:
            return None
        text = ti.get("content") or ti.get("new_string") or ""
        return (text, f"write {Path(path).name}") if text else None
    if name == "Bash":
        return from_bash(ti.get("command") or "")
    if name == "Artifact":
        # The page is a file on disk; score its visible text.
        path = ti.get("file_path")
        if not path or ti.get("action") not in (None, "publish"):
            return None
        try:
            html = Path(path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None
        html = re.sub(r"<(script|style)\b.*?</\1>", " ", html, flags=re.S | re.I)
        html = re.sub(r"<[^>]+>", " ", html)
        return (html, f"artifact {Path(path).name}")
    if "slack" in n and "send" in n:
        return (ti.get("text") or ti.get("message") or "", "Slack message")
    if "gmail" in n and any(k in n for k in ("send", "draft", "reply", "forward")):
        return (ti.get("body") or ti.get("message") or "", "email")
    if "jira" in n or "confluence" in n:
        for key in ("body", "commentBody", "description", "bodyMarkdown"):
            v = ti.get(key)
            if isinstance(v, str) and v:
                return (v, "Jira/Confluence text")
        fields = ti.get("fields")
        if isinstance(fields, dict) and isinstance(fields.get("description"), str):
            return (fields["description"], "Jira description")
    return None


# --- the Stop path ----------------------------------------------------------

def last_assistant_text(transcript: str) -> str:
    try:
        lines = Path(transcript).read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    for line in reversed(lines):
        if '"assistant"' not in line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("type") != "assistant":
            continue
        msg = d.get("message") or {}
        parts = msg.get("content")
        if not isinstance(parts, list):
            continue
        text = "\n".join(p.get("text", "") for p in parts if isinstance(p, dict) and p.get("type") == "text")
        if text.strip():
            return text
    return ""


def blocked_once(session: str) -> bool:
    """One block per turn, so a stubborn reply cannot spin the loop."""
    STATE.mkdir(parents=True, exist_ok=True)
    marker = STATE / f"{re.sub(r'[^A-Za-z0-9_-]', '_', session)[:64]}.stop"
    if marker.exists():
        marker.unlink(missing_ok=True)
        return True
    marker.write_text("1")
    return False


def main() -> int:
    if os.environ.get("PLAINLANG_OFF") == "1":
        return 0
    mode = os.environ.get("PLAINLANG_MODE", "block")
    ev = read_event()
    hook = ev.get("hook_event_name") or ""

    if hook == "PreToolUse":
        got = from_tool(ev.get("tool_name") or "", ev.get("tool_input") or {})
        if not got:
            return 0
        text, label = got
        if not text or SKIP_MARKER.search(text) or word_count(text) < MIN_WORDS:
            return 0
        rep = gate(text)
        if not rep or not rep.get("_failed"):
            return 0
        if mode == "warn":
            print(summarise(rep, label), file=sys.stderr)
            return 0
        print(summarise(rep, label), file=sys.stderr)
        return 2

    if hook == "UserPromptSubmit":
        prompt = ev.get("prompt") or ""
        if not WRITING_ASK.search(prompt):
            return 0
        session = re.sub(r"[^A-Za-z0-9_-]", "_", ev.get("session_id") or "default")[:64]
        STATE.mkdir(parents=True, exist_ok=True)
        marker = STATE / f"{session}.prompt"
        try:
            n = int(marker.read_text()) if marker.exists() else 0
        except (OSError, ValueError):
            n = 0
        marker.write_text(str(n + 1))
        if n % 8 != 0:
            return 0
        print(
            "This turn produces text a person will read. Load the plain-language skill before "
            "you draft, and run `pl check <file>` (or pipe the draft to `pl check -`) before you "
            "send, publish or hand it over. The gate blocks writes, commits, pull requests, Jira, "
            "Slack, email and artifacts that fail it.",
            file=sys.stdout,
        )
        return 0

    if hook == "Stop":
        if ev.get("stop_hook_active"):
            return 0
        text = last_assistant_text(ev.get("transcript_path") or "")
        if not text or SKIP_MARKER.search(text) or word_count(text) < STOP_MIN_WORDS:
            return 0
        rep = gate(text)
        if not rep or not rep.get("_failed"):
            return 0
        if mode == "warn" or blocked_once(ev.get("session_id") or "default"):
            return 0
        print(summarise(rep, "your reply"), file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # never wedge a session on a bug in the guard
        print(f"plain-language guard error: {exc}", file=sys.stderr)
        sys.exit(0)
