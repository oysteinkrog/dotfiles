"""Tests for the hook that runs the gate on anything about to reach a person.

    python3 hooks/test_guard.py

Each case is a real hook payload. Exit 2 means the gate refused the call and the
model gets the findings; exit 0 means the call goes through.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

GUARD = os.environ.get("PLAINLANG_GUARD", str(Path.home() / ".claude/hooks/plain-language-guard.py"))

SLOP = ("In today's fast-paced world, our journey to remote capture is not just a feature, it is a "
        "testament to the evolving landscape of mobile motion analysis. It is worth noting that "
        "experts agree this marks a pivotal moment for the whole team and the product overall.")
PLAIN = ("The phone now owns its settings. The desktop shows them and sends changes back over the "
         "existing protocol. Version 26.2 adds white balance. The 26.1 protocol ignores unknown "
         "field types, so we do not need a backport. Tested on four handsets over two days, with "
         "no dropped frames.")
EM_DASH = "The seek path rebuilds the index \u2014 that is why the first scrub is slow."
CMAKE = """cmake_minimum_required(VERSION 3.20)
project(bertec_emulator C)
set(CMAKE_C_STANDARD 11)

# ---- Headless-test discipline: strip /RTC1 from all Debug builds ----------
# /RTC1 calls _RTC_Failure on a runtime check, which opens a modal dialog and
# hangs the headless test runner for ever, so it is stripped everywhere.
option(BERTEC_FREEZE_GOLDENS "Replay tests --freeze instead of --check" OFF)
if(MSVC)
  target_compile_options(bertec_ftdi_shim PRIVATE /MT /wd4100)
endif()"""

CASES = [
    # name, tool_name, tool_input, expected exit
    ("write .md, inflated", "Write", {"file_path": "/tmp/a.md", "content": SLOP}, 2),
    ("write .md, plain", "Write", {"file_path": "/tmp/a.md", "content": PLAIN}, 0),
    ("write .cs is out of scope", "Write", {"file_path": "/tmp/a.cs", "content": SLOP}, 0),
    ("write a resource file is out of scope", "Write", {"file_path": "/tmp/Strings/a.resx", "content": SLOP}, 0),
    ("skip marker is honoured", "Write", {"file_path": "/tmp/a.md", "content": "plainlang: skip\n" + SLOP}, 0),
    ("short .md with an em dash", "Edit", {"file_path": "/tmp/a.md", "new_string": EM_DASH}, 2),
    ("short .md, clean", "Edit", {"file_path": "/tmp/a.md", "new_string": "The seek path rebuilds the index, which is why the first scrub is slow."}, 0),
    ("short .md, only soft findings", "Edit", {"file_path": "/tmp/a.md", "new_string": "In today's fast-paced world, our journey to capture is a testament to the landscape."}, 0),
    ("short .cs with an em dash", "Edit", {"file_path": "/tmp/a.cs", "new_string": EM_DASH}, 0),
    ("commit message, inflated", "Bash", {"command": 'git commit -m "%s"' % SLOP}, 2),
    ("commit message with an em dash", "Bash", {"command": 'git commit -m "video: rebuild the index \u2014 it was stale after import and the scrubber read past the end"'}, 2),
    ("a script that mentions git commit", "Bash", {"command": "python3 - <<'PY'\ncases = [\"git commit -m oaicite\"]\nprint(cases)\nPY"}, 0),
    ("pull request body in a heredoc", "Bash", {"command": "gh pr create --title x --body \"$(cat <<'EOF'\n" + SLOP + "\nEOF\n)\""}, 2),
    ("heredoc opened before any git token", "Bash", {"command": "cat <<'EOF' > /tmp/n.txt\n" + SLOP + "\nEOF\ngit commit -m 'fix: one line'"}, 0),
    ("an ordinary shell command", "Bash", {"command": "ls -la /tmp && git status"}, 0),
    ("Slack message, inflated", "mcp__claude_ai_Slack__slack_send_message", {"text": SLOP}, 2),
    ("email body, inflated", "mcp__claude_ai_Gmail__send_message", {"body": SLOP}, 2),
    ("Jira comment, inflated", "mcp__claude_ai_Atlassian__addCommentToJiraIssue", {"commentBody": SLOP}, 2),
    ("artifact comment reply, inflated", "Artifact", {"action": "reply", "text": SLOP}, 2),
    ("artifact listing is not text", "Artifact", {"action": "list"}, 0),
    ("Zendesk comment, inflated", "mcp__zendesk__add_comment", {"body": SLOP}, 2),
    ("Zendesk nested comment body", "mcp__zendesk__update_ticket", {"comment": {"body": SLOP}}, 2),
    ("Slack canvas, inflated", "mcp__claude_ai_Slack__slack_create_canvas", {"markdown": SLOP}, 2),
    ("gog gmail send", "Bash", {"command": "gog gmail send -a x@y.com --to z --subject s --body \"$(cat <<'EOF'\n" + SLOP + "\nEOF\n)\""}, 2),
    ("gog gmail list", "Bash", {"command": "gog gmail list -a x@y.com --max 10"}, 0),
    # Found by the historical backtest. A bare -F used to crash the guard, and
    # because it fails open that silently skipped the check for every command
    # containing one.
    ("awk -F does not crash the guard", "Bash", {"command": "awk -F, '{print $1}' data.csv | sort -u"}, 0),
    ("grep -F does not crash the guard", "Bash", {"command": "grep -F 'literal' log.txt | head"}, 0),
    # Also from the backtest: CMakeLists.txt ends in .txt, and its # comments were
    # read as markdown headings.
    ("CMakeLists.txt is not prose", "Write", {"file_path": "/x/CMakeLists.txt", "content": CMAKE}, 0),
    ("code saved as .txt is not prose", "Write", {"file_path": "/x/notes.txt", "content": CMAKE}, 0),
]


def run(payload: dict, env: dict | None = None) -> int:
    e = dict(os.environ)
    e.update(env or {})
    return subprocess.run([sys.executable, GUARD], input=json.dumps(payload),
                          capture_output=True, text=True, env=e).returncode


def main() -> int:
    failures = 0
    for name, tool, ti, want in CASES:
        got = run({"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": ti})
        ok = got == want
        failures += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name:<40} exit={got} want={want}")

    off = run({"hook_event_name": "PreToolUse", "tool_name": "Write",
               "tool_input": {"file_path": "/tmp/a.md", "content": SLOP}}, {"PLAINLANG_OFF": "1"})
    warn = run({"hook_event_name": "PreToolUse", "tool_name": "Write",
                "tool_input": {"file_path": "/tmp/a.md", "content": SLOP}}, {"PLAINLANG_MODE": "warn"})
    for name, got in (("PLAINLANG_OFF=1", off), ("PLAINLANG_MODE=warn", warn)):
        ok = got == 0
        failures += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name:<40} exit={got} want=0")

    print(f"\n{len(CASES) + 2} cases, {failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
