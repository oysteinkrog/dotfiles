#!/usr/bin/env python3
"""PreToolUse hook for Bash: keep GPT-6 Astra calls bounded.

Blocks `codex exec -m gpt-6-astra` when the shell tool is left on, or when
the reasoning effort is xhigh or above. With the shell tool on, Astra opens
files by itself, and a prompt that names a reading list does not stop it:
on 2026-11-01 reviews run that way read 264k to 342k tokens each instead of
about 60k. High effort used up all three OpenAI accounts in about 90 minutes
on 2026-10-22.

Only a `codex exec` at command position counts, so a brief that quotes the
command in an echo or heredoc is not blocked. Any parse failure fails open.
Append `# noqa: astra-guard` for a deliberate exception.
"""

import json
import re
import shlex
import sys

BOUNDED = (
    'cd "$(mktemp -d -p /var/tmp/claude)" && timeout 900 codex exec -m gpt-6-astra \\\n'
    "  -c model_reasoning_effort=medium --disable shell_tool --disable unified_exec \\\n"
    "  --disable code_mode_host --skip-git-repo-check -o out.md - < prompt.md"
)
WRAPPERS = {"timeout", "nohup", "env", "nice", "ionice", "time", "command", "exec"}


SEPARATORS = set(";|&(){}\n")


def simple_commands(command):
    # Tokenize the whole command so quoted text (a prompt with "(1)" in it)
    # stays one word, then split on the unquoted shell separators.
    lex = shlex.shlex(
        command.replace("\\\n", " "), posix=True, punctuation_chars=";|&(){}\n"
    )
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = "#"
    words = []
    for tok in lex:
        if tok and set(tok) <= SEPARATORS:
            yield words
            words = []
        else:
            words.append(tok)
    yield words


def codex_segments(command):
    try:
        segments = list(simple_commands(command))
    except ValueError:
        # Unbalanced quotes (often a heredoc body): fall back to one line at a time.
        segments = []
        for line in command.replace("\\\n", " ").split("\n"):
            try:
                segments.extend(simple_commands(line))
            except ValueError:
                continue
    for words in segments:
        i = 0
        while i < len(words):
            w = words[i]
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w) or (
                i > 0 and w.startswith("-")
            ):
                # env assignment, or a wrapper option left after its value
                # (systemd-run -p MemoryMax=4G -q codex ...)
                i += 1
            elif w in WRAPPERS or w == "systemd-run":
                i += 1
                # skip the wrapper's own options and numeric args
                while i < len(words) and (
                    words[i].startswith("-") or re.match(r"^[0-9.]+[smh]?$", words[i])
                ):
                    i += 1
            else:
                break
        rest = words[i:]
        if len(rest) >= 2 and rest[0].endswith("codex") and rest[1] == "exec":
            yield rest


def problems(args):
    joined = " ".join(args)
    if "gpt-6-astra" not in joined or "--help" in args or "-h" in args:
        return []
    out = []
    shell_off = re.search(r"--disable[ =]shell_tool", joined) or re.search(
        r"features\.shell_tool\s*=\s*false", joined
    )
    if not shell_off:
        out.append("the shell tool is on, so Astra will read files by itself")
    m = re.search(r"model_reasoning_effort\s*=\s*['\"]*(\w+)", joined)
    # The oracle skills allow `high` for one stated high-stakes question;
    # xhigh and above only when Oystein asks (use the noqa marker then).
    if m and m.group(1).lower() in {"xhigh", "max", "ultra"}:
        out.append(f"effort is {m.group(1)}, above high")
    return out


def main():
    try:
        payload = json.load(sys.stdin)
        command = payload.get("tool_input", {}).get("command", "") or ""
    except Exception:
        return 0
    if "codex" not in command or "gpt-6-astra" not in command:
        return 0
    if "noqa: astra-guard" in command:
        return 0
    found = []
    try:
        for args in codex_segments(command):
            found.extend(problems(args))
    except Exception:
        return 0
    if not found:
        return 0
    sys.stderr.write(
        "BLOCKED: unbounded Astra call: " + "; ".join(sorted(set(found))) + ".\n\n"
        "Put the diff and every file Astra needs into prompt.md (about 60k tokens),\n"
        "then run it from an empty folder with the tools off:\n\n"
        f"  {BOUNDED}\n\n"
        "Why: with tools on, reviews read 264k to 342k tokens each (2026-11-01).\n"
        "Rule source: ~/.claude/CLAUDE.md, model table. For a deliberate exception\n"
        "append `# noqa: astra-guard` and say why.\n"
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
