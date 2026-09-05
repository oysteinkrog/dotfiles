#!/usr/bin/env python3
"""Detect an `rg` invocation whose short-flag cluster contains `r` (--replace).

Reads the candidate shell command from the RG_GUARD_COMMAND environment
variable. Prints the offending flag (e.g. `-rln`) and exits 0 when the command
should be denied; prints nothing when it is fine.

Kept in its own file rather than inlined into the hook script: the detector is
prose-heavy, and an apostrophe in a comment silently terminated the shell's
single-quoted string and turned the whole guard into a syntax error that blocked
every Bash call in the session.
"""

import os
import re
import sys

HEREDOC_RE = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")

# A single-dash cluster of two or more flag letters, one of which is r. Position
# inside the cluster does not matter, because both placements are silently wrong:
#   -rln  the remaining letters ARE the replacement, printed for every match
#   -nr   the r is last, so it swallows the next argument as the replacement and
#         the one after it becomes the search pattern
# A lone -r is a real --replace and is left alone. --replace itself cannot match
# because the letter class will not cross the second dash.
CLUSTER_RE = re.compile(r"\s-(?=[a-zA-Z]{2,}(?:\s|$))([a-zA-Z]*r[a-zA-Z]*)(?=\s|$)")

# rg at the head of a segment, allowing env-assignment prefixes, a path, and the
# usual wrappers.
RG_HEAD_RE = re.compile(
    r"^\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*"
    r"(?:\S*/)?"
    r"(?:(?:xargs|time|env|command|nice|nohup)\s+(?:\S+=\S+\s+)*)*"
    r"rg\b"
)

SEPARATOR_RE = re.compile(r"&&|\|\||\||;|\$\(|`|\n")


def blank_quotes(text):
    """Replace quoted spans with spaces, preserving length."""
    out = list(text)
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\\":
            i += 2
            continue
        if ch in "\"'":
            j = i + 1
            while j < n:
                if text[j] == "\\" and ch == '"':
                    j += 2
                    continue
                if text[j] == ch:
                    break
                j += 1
            for k in range(i, min(j + 1, n)):
                out[k] = " "
            i = j + 1
            continue
        i += 1
    return "".join(out)


def blank_data_regions(text):
    """Blank heredoc bodies and quoted spans so only command text is inspected.

    Heredoc boundaries are found on the ORIGINAL lines. Doing it after quote
    blanking does not work: a quoted terminator such as <<'MSG' has already been
    erased by then, so the body is never recognised and its contents are treated
    as commands.

    Quote blanking then runs over the whole remaining text rather than line by
    line, because a quoted argument legitimately spans newlines: a commit message
    passed as one -m string is a single argument, and blanking per line would
    treat its later lines as command text.
    """
    lines = text.split("\n")
    body = [False] * len(lines)

    pending = None
    for idx, line in enumerate(lines):
        if pending is not None:
            if line.strip() == pending:
                pending = None
            else:
                body[idx] = True
            continue
        m = HEREDOC_RE.search(line)
        if m:
            pending = m.group(1)

    without_bodies = "\n".join(
        " " * len(line) if body[idx] else line for idx, line in enumerate(lines)
    )
    return blank_quotes(without_bodies)


def find_offender(command):
    """Return the offending flag, or None.

    The cluster has to belong to the rg invocation, so the command is split at
    shell separators and each segment is judged on its own. Asking "is there an
    rg anywhere" and "is there an r-cluster anywhere" independently blames rg for
    another command's flags: `rg -n foo; grep -rn bar` is correct shell and was
    being denied. Recursive grep is the very habit this guard exists to catch, so
    that false positive was guaranteed to recur.
    """
    code = blank_data_regions(command)
    for segment in SEPARATOR_RE.split(code):
        if not RG_HEAD_RE.search(segment):
            continue
        m = CLUSTER_RE.search(segment)
        if m:
            return "-" + m.group(1)
    return None


def main():
    command = os.environ.get("RG_GUARD_COMMAND", "")
    if not command:
        return 0
    offender = find_offender(command)
    if offender:
        print(offender)
    return 0


if __name__ == "__main__":
    sys.exit(main())
