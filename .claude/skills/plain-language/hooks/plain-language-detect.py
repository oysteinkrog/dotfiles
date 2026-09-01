"""Decide whether a piece of text may reach a person.

Called by plain-language-guard.sh, which sets PYTHONPATH so the scorer imports
directly. Scoring happens in process: there is no launcher to install and no
subprocess, so the gate works on a fresh clone with nothing but python3.

Exit codes follow the Claude Code hook contract:
    0  allow
    2  block, and give the model stderr as the reason

Off switches:
    PLAINLANG_OFF=1                     everything off
    PLAINLANG_MODE=warn                 report but never block
    a `plainlang: skip` line in the text itself
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

SKILL_DIR = Path(os.environ.get("PLAINLANG_SKILL_DIR",
                               os.environ.get("PLAINLANG_HOME",
                                              Path(__file__).resolve().parents[1])))
STATE = Path(os.environ.get("TMPDIR", "/tmp")) / "plainlang-hook"

# Files a person reads as prose. Everything else is code or machine format.
PROSE_SUFFIXES = {".md", ".markdown", ".mdx", ".txt", ".rst", ".adoc"}
# Paths that carry product copy or generated text, which other rules own.
# Directory names are bounded on both sides. Unbounded, obj|bin|dist|vendor
# matched any component starting with those letters, and re.I made BUILD match
# as well, so docs/build-instructions.md, docs/object-model.md, dist-plan.md,
# binder-notes.md, vendor-selection.md and distribution.md were all silently
# exempt. Every one of those is a plausible real document.
SKIP_PATH = re.compile(
    r"(?:/|^)(?:node_modules|\.git|BUILD|obj|bin|dist|vendor|third[_-]party|"
    r"\.beads|locali[sz]ation|Resources?|Strings?)(?=/|$)"
    r"|(?:/|^)(?:CHANGELOG\.md|LICENSE)$",
    re.I,
)
SKIP_SUFFIX = re.compile(r"\.(?:resx|xaml|xlf|xliff|po|pot|json|ya?ml|csv|tsv|lock)$", re.I)
# Files that end in a prose suffix but are not prose. CMakeLists.txt is the one
# that actually bit: a backtest over 84,340 real tool calls found CMake files
# being scored as documents, with their `#` comments read as markdown headings.
SKIP_NAME = re.compile(
    r"^(?:CMakeLists\.txt|CMakeCache\.txt|requirements(?:-\w+)?\.txt|constraints\.txt|"
    r"robots\.txt|LICENSE\.txt|NOTICE\.txt|conanfile\.txt|\.?env\.txt)$", re.I)

# Content that is code even though its name says prose.
# A bare `* ` used to be in this list, meant for the interior of a C block
# comment. It also matches a markdown `* ` bullet, so a release note written with
# `*` bullets instead of `-` bullets read as 100% code at six lines or more and
# skipped the gate, while the identical text with `-` bullets was refused. `/*`
# and `*/` still match, which is what actually identifies a comment block, and
# _MD_LIST takes list lines out of the ratio either way.
_MD_LIST = re.compile(r"^\s*(?:[*+-]|\d+[.)])\s")
_CODE_LINE = re.compile(
    r"^\s*(?:#!|//|/\*|\*/|--\s|;;|<\?|\}|\{|\)|\]|"
    r"(?:if|for|while|switch|function|def|class|return|import|from|using|include|"
    r"set|option|add_\w+|target_\w+|project|cmake_\w+|export|local|declare)\s*[({\s]|"
    r"[\w.\[\]\*&]+\s*(?:=|\+=|:=|<<|->)\s*\S)|[;{}]\s*$")


def looks_like_code(text: str) -> bool:
    """True when the body reads as source rather than prose.

    Judged on the share of substantive lines that look like code. A quarter is
    enough: a document quoting a few commands stays prose, a build file with a
    long comment header does not.
    """
    lines = [ln for ln in text.splitlines() if ln.strip() and len(ln.strip()) > 2]
    # A markdown list line is evidence of neither prose nor code, so it is left
    # out of both halves of the ratio rather than counted against the text.
    lines = [ln for ln in lines if not _MD_LIST.match(ln)]
    if len(lines) < 6:
        return False
    hits = sum(1 for ln in lines if _CODE_LINE.search(ln))
    return hits / len(lines) >= 0.25

SKIP_MARKER = re.compile(r"(?mi)^\s*(?:<!--\s*)?plainlang:\s*skip")

WRITING_ASK = re.compile(
    r"\b(?:write|draft|compose|word|reword|rewrite|summari[sz]e|summary|explain|document|"
    r"docs?|readme|report|brief|memo|plan|proposal|announce|announcement|release notes|"
    r"changelog|commit message|pr body|pull request|jira|ticket|slack|message|email|mail|"
    r"comment|artifact|page|post|blog|title|heading|headline|copy)\b", re.I)

MIN_WORDS = int(os.environ.get("PLAINLANG_MIN_WORDS", "40"))
STOP_MIN_WORDS = int(os.environ.get("PLAINLANG_STOP_MIN_WORDS", "60"))

# Cheap pre-filter so short text only pays for a scorer run when there is a
# defect it could catch. Style is not in this list: below MIN_WORDS the score is
# meaningless, and no style rule gates, so a short inelegant line is let through
# on purpose.
HARD_HINT = re.compile("oaicite|contentReference|turn[0-9]+search|attributableIndex"
                       "|grok_card|ppl-ai-file-upload|utm_source="
                       "|as an AI language model|as of my last update|\\[cite:"
                       "|\\[(?:your name|insert|name here|date here|todo)\\]|lorem ipsum", re.I)


RAW_EVENT = ""


def read_event() -> dict:
    global RAW_EVENT
    try:
        RAW_EVENT = sys.stdin.read() or "{}"
        return json.loads(RAW_EVENT)
    except Exception:
        return {}


def word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z][A-Za-z'-]*", text))


_SCORER = None
_SCORER_ERROR: str | None = None


def _scorer():
    """The scorer, built once per process. None when it cannot be built."""
    global _SCORER, _SCORER_ERROR
    if _SCORER is not None or _SCORER_ERROR is not None:
        return _SCORER
    try:
        skill = Path(os.environ.get("PLAINLANG_SKILL_DIR", Path(__file__).resolve().parents[1]))
        src = skill / "tool" / "src"
        if str(src) not in sys.path:
            sys.path.insert(0, str(src))
        os.environ.setdefault("PLAINLANG_LEXICON", str(skill / "data" / "lexicon.tsv.gz"))
        from plainlang.model import Scorer, Weights  # noqa: PLC0415

        _SCORER = Scorer(Weights.load(skill / "data" / "weights.json"))
    except Exception as exc:  # noqa: BLE001 - report anything, never raise
        _SCORER_ERROR = f"{type(exc).__name__}: {exc}"
    return _SCORER


def gate(text: str, *, min_score: float | None = None) -> dict | None:
    """Score text. Returns a report dict, or None when the scorer is unavailable."""
    scorer = _scorer()
    if scorer is None:
        return None
    try:
        rep = scorer.score(text)
    except Exception as exc:  # noqa: BLE001
        global _SCORER_ERROR
        _SCORER_ERROR = f"scoring failed, {type(exc).__name__}: {exc}"
        return None
    floor = scorer.w.min_score if min_score is None else min_score
    defects = int(rep.stats.get("errors", 0))
    return {
        "score": rep.score,
        "grade": rep.grade,
        "language": rep.language,
        "stats": rep.stats,
        "findings": [
            {"rule": f.rule, "severity": f.severity, "line": f.line, "col": f.col,
             "excerpt": f.excerpt, "message": f.message, "suggest": f.suggest}
            for f in rep.findings
        ],
        "_failed": defects > scorer.w.max_errors or rep.score < floor,
    }


def summarise(rep: dict, label: str) -> str:
    defects = int(rep["stats"].get("errors", 0))
    lines = [
        f"plain-language gate: {label} scored {rep['score']:.0f}/100 ({rep['grade']})."
        + (f" {defects} defect(s): leaked markup or an unfilled placeholder." if defects else "")
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
    """Read the file named by a flag such as --body-file or -F.

    The flag pattern is wrapped in its own group: without that, an alternation
    like `-F|--file` binds looser than the rest of the pattern, so a bare `-F`
    matches with no path captured. `awk -F,` then crashed the hook, and because
    the guard fails open on any exception it silently skipped the check for every
    command containing one.
    """
    m = re.search(rf"(?:{flag})[= ]\s*(['\"]?)(?P<path>[^\s'\"]+)\1", cmd)
    if not m or not m.group("path"):
        return ""
    try:
        return Path(m.group("path")).read_text(encoding="utf-8", errors="replace")
    except (OSError, ValueError):
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
    # `git -C /repo commit` and `git --no-pager commit` are the same command.
    # Requiring git and commit to be adjacent let either spelling through.
    m_commit = re.search(
        r"(?<![\w/-])git(?:\s+-[Cc]\s+\S+|\s+--?[\w-]+(?:=\S+)?)*\s+commit\b", cmd)
    if not (m_pr or m_commit):
        return None
    at = (m_pr or m_commit).end()
    label = "pull request body" if m_pr else "commit message"
    tail = cmd[at:]

    if m_pr:
        # -F is the documented short form of --body-file for the pull request
        # creation subcommand, and was not covered.
        body = _read_file_arg(tail, r"--body-file|(?<![\w-])-F")
        if body:
            return body, label
    else:
        body = _read_file_arg(tail, r"-F|--file")
        if body:
            return body, label

    # A quoted value on the same line. Do not let it run across a newline, or a
    # short -m followed by an unrelated heredoc swallows the whole script.
    # Every quoted region for every flag that carries text, then the longest one.
    #
    # Two things were wrong before. The patterns used [^\n]*, so a message written
    # the way git documents it, title then blank line then body, was read as the
    # title alone: under eight words it gave up and the body was never scored.
    # That is the commonest real commit shape, so it bypassed the gate. And only
    # three flag spellings were covered, so `--message=`, a second `-m` carrying
    # the body, `-b`, `--body=` and `--field body=` all went through unchecked.
    #
    # Matching the closing quote properly is what makes re.DOTALL safe here. A
    # correctly paired quote cannot run past its own end into a later heredoc,
    # which is why the newline exclusion was there to begin with. The negative
    # lookbehind on the closer keeps an escaped quote inside the body.
    best = ""
    for flag in (r"-m", r"--message", r"--body", r"-b",
                 r"-f\s+body=", r"--field\s+body=", r"-F\s+body="):
        pattern = rf"(?<![\w-]){flag}(?:\s*=\s*|\s+|(?=['\"]))\$?(['\"])(?P<b>.*?)(?<!\\)\1"
        for m in re.finditer(pattern, tail, re.S):
            body = m.group("b")
            if word_count(body) > word_count(best):
                best = body
    if word_count(best) >= 8:
        return best, label

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
        if SKIP_NAME.match(Path(path).name):
            return None
        if Path(path).suffix.lower() not in PROSE_SUFFIXES:
            return None
        text = ti.get("content") or ti.get("new_string") or ""
        if not text or looks_like_code(text):
            return None
        return (text, f"write {Path(path).name}")
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


def selfcheck() -> tuple[bool, str]:
    """Is the gate fully operational? Returns (ok, what is wrong).

    Checked separately from "does it run", because the scorer degrades quietly:
    with no lexicon the pattern rules still fire, so the gate looks alive while
    the reading-cost half of it is dead.
    """
    scorer = _scorer()
    if scorer is None:
        return False, f"the scorer will not load ({_SCORER_ERROR})"
    problems = []
    if not scorer.lex.loaded or len(scorer.lex) < 10000:
        problems.append(f"the word-norm table is missing or short ({len(scorer.lex)} rows), "
                        "so word cost is not being measured")
    if not scorer.simpler:
        problems.append("data/simpler.tsv is missing, so no plainer word is ever suggested")
    if not scorer.glossary:
        problems.append("no glossary is loaded, so domain terms will be charged as hard words")
    if len(scorer.rules) < 40:
        problems.append(f"only {len(scorer.rules)} rules loaded")
    return (not problems), "; ".join(problems)


def _decision_cache(event: str, payload: str) -> tuple[Path | None, int | None]:
    """Remember this event's decision for a few seconds.

    The gate can legitimately be wired twice: once per developer in the user
    settings so it covers every repository, and once in a repository's own
    settings so it covers every developer. Both fire, and the decision is
    deterministic given the payload, so the second run is pure waste. This
    replays it instead. It is a cache, not a lock: a miss only costs time.
    """
    try:
        import hashlib

        # Everything that can change the decision goes in the key. Without the
        # mode, flipping PLAINLANG_MODE=warn was ignored for ten seconds because
        # the blocking decision from the previous run was replayed.
        config = "\x00".join([
            os.environ.get("PLAINLANG_MODE", ""),
            os.environ.get("PLAINLANG_MIN_WORDS", ""),
            os.environ.get("PLAINLANG_STOP_MIN_WORDS", ""),
            os.environ.get("PLAINLANG_HOME", ""),
            os.environ.get("PLAINLANG_SKILL_DIR", ""),
        ])
        key = hashlib.sha256(f"{event}\x00{config}\x00{payload}".encode()).hexdigest()[:32]
        STATE.mkdir(parents=True, exist_ok=True)
        marker = STATE / f"d-{key}"
        if marker.exists() and (time.time() - marker.stat().st_mtime) < 10:
            return marker, int(marker.read_text().strip() or 0)
        return marker, None
    except Exception:  # noqa: BLE001 - a cache must never be the thing that fails
        return None, None


def _remember(marker: Path | None, code: int) -> int:
    if marker is not None:
        try:
            marker.write_text(str(code))
        except OSError:
            pass
    return code


def main() -> int:
    if os.environ.get("PLAINLANG_OFF") == "1":
        return 0

    if (os.environ.get("PLAINLANG_SELFCHECK") or "") == "1":
        ok, why = selfcheck()
        if not ok:
            print(why, file=sys.stderr)
        return 0 if ok else 1
    mode = os.environ.get("PLAINLANG_MODE", "block")
    ev = read_event()
    hook = ev.get("hook_event_name") or ""
    marker, cached = _decision_cache(hook, RAW_EVENT)
    if cached is not None:
        # Same payload, same event, seconds ago. Replay without rescoring; the
        # first run already printed the reason the model needs.
        if cached != 0:
            print("plain-language gate: same text refused a moment ago, see above.", file=sys.stderr)
        return cached

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
        if not rep or rep["language"] != "en":
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
        return _remember(marker, 2)

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
        if not rep or rep["language"] != "en" or not rep.get("_failed"):
            return 0
        if mode == "warn" or blocked_recently(ev.get("session_id") or "default"):
            return 0
        print(summarise(rep, "your reply"), file=sys.stderr)
        return _remember(marker, 2)

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # never wedge a session on a bug in the guard
        print(f"plain-language guard error: {exc}", file=sys.stderr)
        sys.exit(0)
