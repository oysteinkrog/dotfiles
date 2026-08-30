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

# Cheap pre-filter so short text only pays for a scorer run when there is
# something a hard rule could catch.
HARD_HINT = re.compile("[\u2014\u2013]|oaicite|contentReference|turn[0-9]+search|utm_source="
                       "|as an AI language model|\\[cite:|not only |it's not |it is not ", re.I)


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
    lines.append(
        "Fix the findings above, not the number. Do not delete identifiers, versions, paths or "
        "backticks, and do not chop sentences into fragments: that raises the score and costs the "
        "reader. If a finding is wrong, say so and leave it. If this text is out of scope (product "
        "copy, quoted material, a machine format), say so and add a `plainlang: skip` line."
    )
    return "\n".join(lines)


# --- extracting the human-facing text from a tool call ----------------------

def _heredocs(cmd: str) -> list[str]:
    """Bodies passed as heredocs, which is how most PR and commit text arrives."""
    out = []
    for m in re.finditer(r"<<-?\s*['\"]?(?P<tag>[A-Za-z_][A-Za-z0-9_]*)['\"]?\s*\n(?P<body>.*?)\n\s*(?P=tag)\b",
                         cmd, re.S):
        out.append(m.group("body"))
    return out


def _read_file_arg(cmd: str, flag: str) -> str:
    m = re.search(rf"{flag}[= ]\s*(['\"]?)(?P<path>[^\s'\"]+)\1", cmd)
    if not m:
        return ""
    try:
        return Path(m.group("path")).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def from_gog(cmd: str) -> tuple[str, str] | None:
    """The Google Workspace CLI sends mail and writes documents from the shell."""
    m = re.search(r"\bgog\s+(?:gmail|docs?)\s+(?:send|reply|draft|create|append|update)\b", cmd)
    if not m:
        return None
    tail = cmd[m.end():]
    for pattern in (r"--body\s*(['\"])(?P<b>[^\n]*?)\1", r"--(?:text|content)\s*(['\"])(?P<b>[^\n]*?)\1"):
        q = re.search(pattern, tail)
        if q and word_count(q.group("b")) >= 8:
            return q.group("b"), "email or document"
    docs = [d for d in _heredocs(tail) if word_count(d) >= 25]
    if docs:
        return max(docs, key=word_count), "email or document"
    return None


def from_bash(cmd: str) -> tuple[str, str] | None:
    """Pull the commit message or pull request body out of a shell command.

    Everything here is anchored to the position of the git or gh token, because
    a command that merely mentions `git commit` inside a test fixture or a
    heredoc of Python must not be read as a commit message.
    """
    got = from_gog(cmd)
    if got:
        return got
    m_pr = re.search(r"\bgh\s+(?:pr|issue)\s+(?:create|edit|comment)\b", cmd) or \
        re.search(r"\bgh\s+api\b[^\n]*\bpulls?\b", cmd)
    m_commit = re.search(r"(?<![\w/-])git\s+commit\b", cmd)
    if not (m_pr or m_commit):
        return None
    at = (m_pr or m_commit).end()
    label = "pull request body" if m_pr else "commit message"
    tail = cmd[at:]

    if m_pr:
        body = _read_file_arg(tail, r"--body-file")
        if body:
            return body, label
    else:
        body = _read_file_arg(tail, r"-F|--file")
        if body:
            return body, label

    # A quoted value on the same line. Do not let it run across a newline, or a
    # short -m followed by an unrelated heredoc swallows the whole script.
    for pattern in (r"--body\s*(['\"])(?P<b>[^\n]*?)\1",
                    r"-f\s+body=(['\"])(?P<b>[^\n]*?)\1",
                    r"-m\s*(['\"])(?P<b>[^\n]*?)\1"):
        m = re.search(pattern, tail)
        if m and word_count(m.group("b")) >= 8:
            return m.group("b"), label

    # A heredoc, but only one opened after the git or gh token.
    docs = [d for d in _heredocs(tail) if word_count(d) >= 25]
    if docs:
        return max(docs, key=word_count), label
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
        if ti.get("action") == "reply":
            return (ti.get("text") or "", "artifact comment reply")
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
    if "slack" in n and any(k in n for k in ("send", "draft", "canvas", "reply")):
        for key in ("text", "message", "markdown", "content", "document_content"):
            v = ti.get(key)
            if isinstance(v, str) and v:
                return (v, "Slack message")
        return None
    if any(k in n for k in ("gmail", "mail_send", "send_email")) and \
            any(k in n for k in ("send", "draft", "reply", "forward", "create")):
        for key in ("body", "message", "text", "html"):
            v = ti.get(key)
            if isinstance(v, str) and v:
                return (v, "email")
        return None
    if "zendesk" in n and any(k in n for k in ("comment", "reply", "ticket", "create", "update")):
        for key in ("body", "comment", "html_body", "public_comment", "text"):
            v = ti.get(key)
            if isinstance(v, str) and v:
                return (v, "support reply")
        comment = ti.get("comment")
        if isinstance(comment, dict) and isinstance(comment.get("body"), str):
            return (comment["body"], "support reply")
        return None
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


def blocked_recently(session: str, seconds: int = 90) -> bool:
    """Do not block the same session twice in quick succession.

    `stop_hook_active` is the real loop guard; this is the backstop for a reply
    that keeps failing for a reason the model cannot fix, so the turn ends
    rather than spinning.
    """
    import time

    STATE.mkdir(parents=True, exist_ok=True)
    marker = STATE / f"{re.sub(r'[^A-Za-z0-9_-]', '_', session)[:64]}.stop"
    now = time.time()
    try:
        if marker.exists() and now - marker.stat().st_mtime < seconds:
            return True
    except OSError:
        return False
    try:
        marker.write_text(str(now))
    except OSError:
        pass
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
        if not text or SKIP_MARKER.search(text):
            return 0
        short = word_count(text) < MIN_WORDS
        if short and not HARD_HINT.search(text):
            # Too little text for the score to mean anything, and no sign of a
            # hard rule. Nothing to say.
            return 0
        rep = gate(text)
        if not rep:
            return 0
        if short:
            # Short text is judged on the hard rules alone. An em dash is an em
            # dash in ten words; a cost per hundred words is not.
            if not rep["stats"].get("errors"):
                return 0
            rep["findings"] = [f for f in rep["findings"] if f["severity"] == "error"]
        elif not rep.get("_failed"):
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
        if mode == "warn" or blocked_recently(ev.get("session_id") or "default"):
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
