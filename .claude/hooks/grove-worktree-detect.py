#!/usr/bin/env python3
"""Detect a raw `git worktree add` / `git clone` / `gh repo clone` invocation
whose TARGET directory resolves under a grove-managed work_dir.

Reads the candidate shell command from GROVE_GUARD_COMMAND, the PreToolUse
payload's cwd from GROVE_GUARD_CWD, and newline-separated guarded work_dirs
from GROVE_GUARD_WORKDIRS. Prints the resolved (or indeterminate) target on
one line and exits 0 when the command should be denied; prints nothing when
it is fine.

Kept in its own file rather than inlined into the hook script, matching
rg-replace-detect.py's split: this needs real shell tokenization (quoting,
`git -C`, URL-derived clone dirs, heredocs), and that logic is easier to get
right and test in Python than in bash.
"""

import os
import re
import shlex
import sys

HEREDOC_RE = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")

# && || | ; $( ` and newline all start a new shell command. Splitting on
# these (found in the QUOTE-BLANKED text, never the raw text) is what lets a
# quoted mention of "git worktree add" inside some other command's argument
# -- e.g. a `br update --description` documenting this very hook -- end up
# tokenized as part of that other command's single argument instead of being
# mistaken for a real invocation.
SEPARATOR_RE = re.compile(r"&&|\|\||\||;|\$\(|`|\n")

WRAPPERS = {"time", "command", "env", "nice", "nohup"}
ENV_ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def blank_quotes(text):
    """Replace quoted spans with spaces, preserving length and position."""
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
    """Blank heredoc bodies and quoted spans, keeping length/position so the
    result can be used only to locate segment boundaries -- the ORIGINAL
    text at those same boundaries is what gets tokenized, so real quoting
    (a clone URL, a worktree path) survives intact.
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


def split_segments(original, blanked):
    """Split ORIGINAL text at the separator positions found in BLANKED text."""
    segments = []
    pos = 0
    for m in SEPARATOR_RE.finditer(blanked):
        segments.append(original[pos : m.start()])
        pos = m.end()
    segments.append(original[pos:])
    return segments


def strip_wrappers(tokens):
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if ENV_ASSIGN_RE.match(t) or t in WRAPPERS:
            i += 1
            continue
        break
    return tokens[i:]


def resolve_dir(value, base):
    """Resolve VALUE against BASE. Absolute values ignore BASE. Returns None
    when VALUE is relative and BASE is unknown (indeterminate).
    """
    if not value:
        return base
    if os.path.isabs(value):
        return os.path.normpath(value)
    if not base:
        return None
    return os.path.normpath(os.path.join(base, value))


def derive_clone_dirname(source):
    """Mirror git's own rule for the implicit clone destination: the
    basename of the source (URL, scp-like remote, or local path), with a
    trailing .git stripped.
    """
    name = source.rstrip("/")
    name = re.split(r"[/:]", name)[-1]
    if name.endswith(".git"):
        name = name[:-4]
    return name or None


def parse_git(tokens, payload_cwd):
    """tokens[0] == 'git'. Returns (kind, resolved_target_or_None,
    effective_cwd) for worktree-add/clone, or None if this is some other
    git subcommand (worktree list/prune/remove/... are intentionally left
    alone here).
    """
    i = 1
    cwd = payload_cwd
    while i < len(tokens):
        t = tokens[i]
        if t == "-C":
            if i + 1 >= len(tokens):
                return None
            cwd = resolve_dir(tokens[i + 1], cwd)
            i += 2
            continue
        if t.startswith("-C") and len(t) > 2:
            cwd = resolve_dir(t[2:], cwd)
            i += 1
            continue
        break

    if i >= len(tokens):
        return None

    sub = tokens[i]
    if sub == "worktree":
        # Only `worktree add` creates a directory outside the registry;
        # list/status/prune/remove/lock/unlock are read/maintenance ops.
        if i + 1 < len(tokens) and tokens[i + 1] == "add":
            return finish_target("worktree_add", tokens[i + 2 :], cwd, is_clone=False)
        return None
    if sub == "clone":
        return finish_target("clone", tokens[i + 1 :], cwd, is_clone=True)
    return None


def finish_target(kind, args, cwd, is_clone):
    # Candidate target = last non-flag argument. For `worktree add PATH
    # [COMMITISH]` this is wrong if an explicit commit-ish trailer is given
    # (PATH is second-to-last, not last) -- a known, accepted limitation;
    # normal agent usage omits the commit-ish, so PATH is last. For `clone`,
    # a trailing --branch/--depth style flag+value pair never displaces the
    # true positional args, because flag values don't start with '-' but
    # they're never LAST when a real destination or source follows them.
    positional = [a for a in args if not a.startswith("-")]
    if is_clone:
        if len(positional) >= 2:
            resolved = resolve_dir(positional[-1], cwd)
        elif len(positional) == 1:
            derived = derive_clone_dirname(positional[0])
            resolved = resolve_dir(derived, cwd) if derived else None
        else:
            resolved = None
    else:
        resolved = resolve_dir(positional[-1], cwd) if positional else None
    return (kind, resolved, cwd)


def parse_gh(tokens, payload_cwd):
    if len(tokens) < 3 or tokens[1] != "repo" or tokens[2] != "clone":
        return None
    args = tokens[3:]
    positional = [a for a in args if not a.startswith("-")]
    if len(positional) >= 2:
        resolved = resolve_dir(positional[-1], payload_cwd)
    elif len(positional) == 1:
        derived = derive_clone_dirname(positional[0])
        resolved = resolve_dir(derived, payload_cwd) if derived else None
    else:
        resolved = None
    return ("gh_clone", resolved, payload_cwd)


def classify_segment(raw_segment, payload_cwd):
    try:
        tokens = shlex.split(raw_segment)
    except ValueError:
        return None
    tokens = strip_wrappers(tokens)
    if not tokens:
        return None
    head = tokens[0]
    if head == "git":
        return parse_git(tokens, payload_cwd)
    if head == "gh":
        return parse_gh(tokens, payload_cwd)
    return None


def find_guard(path, workdirs):
    """Return the guarded work_dir PATH sits under, or None. `.scratch`
    subtrees of a work_dir are explicitly exempt (grove gc TTL-sweeps them).
    """
    if not path:
        return None
    norm = os.path.normpath(path)
    for wd in workdirs:
        wd = os.path.normpath(wd)
        if norm != wd and not norm.startswith(wd + os.sep):
            continue
        scratch_prefix = wd + os.sep + ".scratch"
        if norm == scratch_prefix or norm.startswith(scratch_prefix + os.sep):
            continue
        return wd
    return None


def main():
    command = os.environ.get("GROVE_GUARD_COMMAND", "")
    payload_cwd = os.environ.get("GROVE_GUARD_CWD", "") or None
    workdirs = [w for w in os.environ.get("GROVE_GUARD_WORKDIRS", "").splitlines() if w.strip()]
    if not command or not workdirs:
        return 0

    blanked = blank_data_regions(command)
    for raw_segment in split_segments(command, blanked):
        result = classify_segment(raw_segment, payload_cwd)
        if result is None:
            continue
        _kind, resolved, effective_cwd = result
        if resolved is not None:
            guard = find_guard(resolved, workdirs)
            if guard:
                print(resolved)
                return 0
        else:
            # Target undeterminable. Fail CLOSED only if we're already
            # inside a guarded tree -- otherwise this is almost certainly
            # unrelated to grove and failing open avoids nuisance blocks.
            guard = find_guard(effective_cwd, workdirs)
            if guard:
                print(f"{effective_cwd} (target undeterminable; failing closed because cwd is inside {guard})")
                return 0
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Any unexpected parse error of our own inputs: allow. The one
        # deliberate fail-closed path is the indeterminate-target branch
        # above, not a crash here.
        sys.exit(0)
