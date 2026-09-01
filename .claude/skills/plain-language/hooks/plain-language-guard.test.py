"""Test matrix for the plain-language hook.

    python3 hooks/plain-language-guard.test.py

Each case is a real hook payload, run through plain-language-guard.sh, which is
what Claude Code actually invokes. Exit 2 means the gate refused the call and the
model gets the findings; exit 0 means the call goes through.

Run this after any change to plain-language-guard.sh or plain-language-detect.py.
Several cases exist because a real bug got past review: `awk -F,` crashing the
guard, CMakeLists.txt scored as prose, and a `git commit` mentioned inside an
unrelated heredoc read as a commit message.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Test what Claude Code runs: the wrapper, not the detector underneath it.
GUARD = os.environ.get("PLAINLANG_GUARD", str(HERE / "plain-language-guard.sh"))

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

# --- fixtures for the 2026-09-01 hook audit ---------------------------------
# A release note written with `*` bullets. Six lines was the threshold: at six or
# more, every line matched the code heuristic and the whole document skipped the
# gate, while the identical text with `-` bullets was refused.
STAR_BULLETS = "\n".join([
    "* In todays fast-paced world our journey to remote capture is a testament",
    "* It is worth noting that experts agree this marks a pivotal moment",
    "* The evolving landscape of mobile motion analysis is not just a feature",
    "* This delivers a seamless and robust experience for the whole team",
    "* At its core the solution empowers users to unlock their full potential",
    "* Needless to say the journey ahead is a testament to our shared vision",
])
DASH_BULLETS = STAR_BULLETS.replace("* ", "- ")
# The commit shape git's own documentation teaches: title, blank line, body.
MULTILINE_COMMIT = f'git commit -m "video: rebuild index\n\n{SLOP}"'


CASES = [
    # name, tool_name, tool_input, expected exit
    ("write .md, inflated", "Write", {"file_path": "/tmp/a.md", "content": SLOP}, 2),
    ("write .md, plain", "Write", {"file_path": "/tmp/a.md", "content": PLAIN}, 0),
    ("write .cs is out of scope", "Write", {"file_path": "/tmp/a.cs", "content": SLOP}, 0),
    ("write a resource file is out of scope", "Write", {"file_path": "/tmp/Strings/a.resx", "content": SLOP}, 0),
    ("skip marker is honoured", "Write", {"file_path": "/tmp/a.md", "content": "plainlang: skip\n" + SLOP}, 0),
    # Short text is judged on defects alone, and an em dash is not a defect. A
    # cost per hundred words means nothing at fourteen words, and a fourteen-word
    # line is almost never why a reader fails to understand something.
    ("short .md with an em dash", "Edit", {"file_path": "/tmp/a.md", "new_string": EM_DASH}, 0),
    ("short .md, clean", "Edit", {"file_path": "/tmp/a.md", "new_string": "The seek path rebuilds the index, which is why the first scrub is slow."}, 0),
    ("short .md, only soft findings", "Edit", {"file_path": "/tmp/a.md", "new_string": "In today's fast-paced world, our journey to capture is a testament to the landscape."}, 0),
    ("short .cs with an em dash", "Edit", {"file_path": "/tmp/a.cs", "new_string": EM_DASH}, 0),
    ("commit message, inflated", "Bash", {"command": 'git commit -m "%s"' % SLOP}, 2),
    ("short commit with an em dash", "Bash", {"command": 'git commit -m "video: rebuild the index \u2014 it was stale after import and the scrubber read past the end"'}, 0),
    ("short commit with leaked markup", "Bash", {"command": 'git commit -m "video: rebuild the index citeturn0search3 because it was stale after the import"'}, 2),
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
    # --- 2026-09-01 hook audit. Each of these went through unchecked. ---------
    #
    # The worst was the commit shape git documents: title, blank line, body. The
    # message pattern excluded newlines, so it read the title alone, found fewer
    # than eight words and gave up. Any agent writing a conventional commit
    # message bypassed the gate completely.
    ("multi-line -m, body after a blank line", "Bash", {"command": MULTILINE_COMMIT}, 2),
    ("second -m carries the body", "Bash",
     {"command": f'git commit -m "fix: rebuild index" -m "{SLOP}"'}, 2),
    ("--message= spelling", "Bash", {"command": f'git commit --message="{SLOP}"'}, 2),
    ("--message with a space", "Bash", {"command": f'git commit --message "{SLOP}"'}, 2),
    ("git -C dir commit", "Bash", {"command": f'git -C /repo commit -m "{SLOP}"'}, 2),
    ("git --no-pager commit", "Bash", {"command": f'git --no-pager commit -m "{SLOP}"'}, 2),
    ("--body= spelling", "Bash", {"command": f'gh pr edit 1 --body="{SLOP}"'}, 2),
    ("-b short flag for the body", "Bash", {"command": f'gh pr edit 1 -b "{SLOP}"'}, 2),
    ("--field body=", "Bash",
     {"command": f'gh api repos/x/y/pulls/1 --field body="{SLOP}"'}, 2),
    ("ANSI-C quoting", "Bash", {"command": "git commit -m $'" + SLOP.replace("'", "") + "'"}, 2),
    # A `*` bullet matched the code heuristic, so the same text passed or failed
    # depending on which bullet character the writer used.
    ("release note in * bullets", "Write", {"file_path": "/tmp/rel.md", "content": STAR_BULLETS}, 2),
    ("release note in - bullets", "Write", {"file_path": "/tmp/rel.md", "content": DASH_BULLETS}, 2),
    # The directory names in SKIP_PATH were unbounded and matched case-insensitively,
    # so any path component merely starting with obj, bin, dist, vendor or build was
    # exempt. All five of these are plausible real documents.
    ("docs/build-instructions.md", "Write",
     {"file_path": "/docs/build-instructions.md", "content": SLOP}, 2),
    ("object-model.md", "Write", {"file_path": "/tmp/object-model.md", "content": SLOP}, 2),
    ("dist-plan.md", "Write", {"file_path": "/tmp/dist-plan.md", "content": SLOP}, 2),
    ("binder-notes.md", "Write", {"file_path": "/tmp/binder-notes.md", "content": SLOP}, 2),
    ("vendor-selection.md", "Write", {"file_path": "/tmp/vendor-selection.md", "content": SLOP}, 2),
    # The other direction: the real build and resource directories must stay out.
    ("BUILD/ is still skipped", "Write", {"file_path": "/repo/BUILD/notes.md", "content": SLOP}, 0),
    ("obj/ is still skipped", "Write", {"file_path": "/repo/obj/notes.md", "content": SLOP}, 0),
    ("bin/ is still skipped", "Write", {"file_path": "/repo/bin/notes.md", "content": SLOP}, 0),
    ("dist/ is still skipped", "Write", {"file_path": "/repo/dist/notes.md", "content": SLOP}, 0),
    ("vendor/ is still skipped", "Write", {"file_path": "/repo/vendor/lib/README.md", "content": SLOP}, 0),
    ("node_modules/ is still skipped", "Write",
     {"file_path": "/repo/node_modules/pkg/README.md", "content": SLOP}, 0),
    ("localisation/ is still skipped", "Write",
     {"file_path": "/repo/localisation/strings.md", "content": SLOP}, 0),
    ("CHANGELOG.md is still skipped", "Write", {"file_path": "/repo/CHANGELOG.md", "content": SLOP}, 0),
]


def run(payload: dict, env: dict | None = None) -> int:
    e = dict(os.environ)
    e.setdefault("PLAINLANG_HOME", str(HERE.parent))
    e.update(env or {})
    cmd = ["bash", GUARD] if GUARD.endswith(".sh") else [sys.executable, GUARD]
    return subprocess.run(cmd, input=json.dumps(payload),
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
