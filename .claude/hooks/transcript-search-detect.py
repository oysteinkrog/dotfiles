#!/usr/bin/env python3
"""Detect a search over all session transcripts (~/.claude/projects).

Reads the shell command from TS_COMMAND and the cwd from TS_CWD. Prints
`ROOT<TAB>SEGMENT` for the first search that covers the whole projects folder
or a parent of it, and nothing when the command is fine.

Reuses the parsing in fs-walk-detect.py (quote and heredoc blanking, wrappers,
`cd`, `sh -c`, depth limits) and swaps in its own list of roots. Roots, in
every spelling (~, $HOME, /home/oystein, and the ~/.dotfiles/.claude target of
the ~/.claude symlink): projects itself, ~/.claude, ~, /home and /.
Extra rules on top of fs-walk:
  - ag and ack are treated like rg.
  - A path with a glob in the project-folder part (`projects/*/x.jsonl`) reads
    every session, so it counts as the whole folder, even for plain grep.
Allowed: one session folder (`projects/<dir>/...`) or one named file.
Any error of its own prints nothing (fail open).
"""

import importlib.util
import os
import re
import sys
from pathlib import Path

HOME = os.path.normpath(os.path.expanduser("~"))
DOT = os.path.join(HOME, ".dotfiles", ".claude")
CLAUDE_DIRS = [os.path.join(HOME, ".claude"), DOT]
PROJECTS = [os.path.join(d, "projects") for d in CLAUDE_DIRS]
ROOTS = set(PROJECTS + CLAUDE_DIRS + [HOME, "/home", "/"])
GLOB_RE = re.compile(r"[*?\[{]")
SEARCHERS = {"rg", "grep", "egrep", "fgrep", "ag", "ack", "find", "fd", "du"}
ALIASES = {"ag": "rg", "ack": "rg"}


def load_fs_walk():
    path = Path(__file__).with_name("fs-walk-detect.py")
    spec = importlib.util.spec_from_file_location("fs_walk_detect", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.seg_mod = mod.load_segmenter()
    return mod


def main() -> int:
    command = os.environ.get("TS_COMMAND", "")
    cwd = os.environ.get("TS_CWD", "") or None
    if not command:
        return 0
    if cwd:
        cwd = os.path.normpath(cwd)
    fw = load_fs_walk()
    fw.BROAD = ROOTS
    orig_broad_root = fw.broad_root
    orig_check_command = fw.check_command

    def under_glob(path, c):
        full = fw.resolve(path, c)
        if full is None:
            return None
        for p in PROJECTS:
            if full.startswith(p + "/"):
                first = full[len(p) + 1 :].split("/")[0]
                if GLOB_RE.search(first):
                    return p
        return None

    def broad_root(path, c):
        return orig_broad_root(path, c) or under_glob(path, c)

    def check_command(tokens, c, piped, depth):
        toks = list(tokens)
        for i in range(min(len(toks), 3)):
            base = os.path.basename(toks[i])
            if base in ALIASES:
                toks[i] = ALIASES[base]
                break
            if base in SEARCHERS:
                break
        root = orig_check_command(toks, c, piped, depth)
        if root:
            return root
        # Non-recursive greps and the like still read every file behind a glob.
        for i in range(min(len(toks), 3)):
            if os.path.basename(toks[i]) in SEARCHERS:
                for t in toks[i + 1 :]:
                    if not t.startswith("-"):
                        r = under_glob(t, c)
                        if r:
                            return r
                break
        return None

    fw.broad_root = broad_root
    fw.check_command = check_command
    root, segment = fw.check_text(command, cwd)
    if root:
        print(f"{root.replace(HOME, '~', 1)}\t{segment}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
