#!/usr/bin/env python3
"""Detect a command that walks the whole disk or the whole home folder.

Reads the shell command from FS_WALK_COMMAND and the PreToolUse payload's cwd
from FS_WALK_CWD. Prints `ROOT<TAB>SEGMENT` for the first walk that starts at
a broad root, and nothing when the command is fine.

Why: on 2026-10-27 a subagent ran `bfs -S dfs / -iname '*monitoring*plan*'`.
With about 830 worktrees on disk it filled about 6 GiB of btrfs_inode and
dentry slab, free 32 KiB blocks fell to 96 (a KWin and NVIDIA risk) and the
build queue paused. The same day a Grep tool call (ugrep) with cwd
/var/tmp/claude stalled memory and paused the queue again.

Broad roots: /, ~ (/home/oystein), /home, /var, /var/tmp and /var/tmp/claude. A walk counts
when one of those is a search path, when the command has no path and the cwd
is one of those, or when the path is a top-level glob such as `~/*`.

Walking commands: find, bfs, fd, fdfind, rgg, du, ncdu, tree, `ls -R`, rg,
`grep -r`, ugrep, ug and `btrfs filesystem du`. Claude's own Grep and Glob
tools get the same rule through FS_WALK_TOOL, FS_WALK_PATH and
FS_WALK_PATTERN (Glob only when its pattern has `**`). Allowed anyway: find, bfs, fd, rg and
tree limited to depth 1 or 2. du has no such exception, because its depth
option only limits the output; du still reads every inode below the path.

Shell segmentation (quote and heredoc blanking, separator splitting) is shared
with grove-worktree-detect.py, so a quoted mention or a heredoc line is never
treated as a command. `cd DIR` earlier in the line moves the cwd, and
`sh -c '...'` and `eval` are checked recursively. Any error of its own makes
it print nothing (fail open).
"""

import importlib.util
import os
import re
import shlex
import sys
from pathlib import Path
from types import ModuleType

HOME = os.path.normpath(os.path.expanduser("~"))
BROAD = {"/", HOME, "/home", "/var", "/var/tmp", "/var/tmp/claude"}
SAFE_DEPTH = 2

ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HOME_VAR_RE = re.compile(r"^\$(?:HOME\b|\{HOME\})")
GLOB_ONLY = {"*", ".*", "*/", ".*/", "**"}

# Wrappers that run the rest of the line. Values are options that take a
# separate value token.
WRAPPERS = {
    "time": {"-f", "--format", "-o", "--output"},
    "command": set(),
    "builtin": set(),
    "nice": {"-n", "--adjustment"},
    "nohup": set(),
    "ionice": {"-c", "--class", "-n", "--classdata", "-p", "-P", "-u"},
    "stdbuf": {"-i", "-o", "-e"},
    "setsid": set(),
    "exec": set(),
    "sudo": {"-u", "--user", "-g", "--group", "-C", "-D", "--chdir"},
    "doas": {"-u", "-C"},
    "heavy-build": set(),
}
TIMEOUT_OPTS = {"-s", "--signal", "-k", "--kill-after"}
ENV_OPTS = {"-u", "--unset", "-S", "--split-string"}
XARGS_OPTS = {
    "-a", "--arg-file", "-d", "--delimiter", "-E", "-e", "-I", "-i", "-L", "-l",
    "-n", "--max-args", "-P", "--max-procs", "-s", "--max-chars",
    "--process-slot-var",
}  # fmt: skip
SHELLS = {"sh", "bash", "zsh", "dash", "fish", "ksh"}

FIND_PRE_OPTS = {"-H", "-L", "-P"}
BFS_VALUE_OPTS = {"-S", "-D", "-j"}
FD_VALUE_OPTS = {
    "-e", "--extension", "-E", "--exclude", "-t", "--type", "-x", "--exec",
    "-X", "--exec-batch", "-S", "--size", "-c", "--color", "-j", "--threads",
    "--changed-within", "--changed-before", "--change-newer-than",
    "--change-older-than", "--newer", "--older", "-o", "--owner",
    "--ignore-file", "--format", "--max-results", "--min-depth",
    "--path-separator", "--and", "--batch-size", "--max-buffer-time",
    "--hyperlink", "--strip-cwd-prefix",
}  # fmt: skip
FD_DEPTH_OPTS = {"-d", "--max-depth", "--maxdepth", "--exact-depth"}
RG_VALUE_OPTS = {
    "-e", "--regexp", "-f", "--file", "-g", "--glob", "--iglob", "-t", "--type",
    "-T", "--type-not", "--type-add", "--type-clear", "-A", "--after-context",
    "-B", "--before-context", "-C", "--context", "-m", "--max-count", "-M",
    "--max-columns", "-j", "--threads", "-E", "--encoding", "-r", "--replace",
    "--max-filesize", "--sort", "--sortr", "--colors", "--color",
    "--path-separator", "--pre", "--pre-glob", "--context-separator",
    "--field-context-separator", "--field-match-separator",
    "--dfa-size-limit", "--regex-size-limit", "--engine", "--hostname-bin",
    "--hyperlink-format", "--ignore-file",
}  # fmt: skip
RG_DEPTH_OPTS = {"-d", "--max-depth", "--maxdepth"}
GREP_VALUE_LETTERS = set("efmABCdD")
# ugrep short options that take a value (attached or as the next token).
UGREP_VALUE_LETTERS = set("efmABCdDgtOMNKJ")
GREP_VALUE_LONG = {
    "--regexp", "--file", "--max-count", "--after-context", "--before-context",
    "--context", "--directories", "--devices", "--include", "--exclude",
    "--exclude-dir", "--exclude-from", "--label", "--color", "--colour",
    "--binary-files",
}  # fmt: skip
DU_VALUE_OPTS = {
    "-B", "--block-size", "-t", "--threshold", "--exclude", "-X",
    "--exclude-from", "-d", "--max-depth", "--time-style", "--files0-from",
}  # fmt: skip
NCDU_VALUE_OPTS = {"-o", "-O", "-f", "-e", "--exclude", "-X", "--exclude-from"}
TREE_VALUE_OPTS = {
    "-P", "-I", "-o", "-H", "-T", "--charset", "--filelimit", "--sort",
    "--timefmt", "--fromfile", "--gitfile", "--infofile",
}  # fmt: skip
LS_VALUE_OPTS = {
    "-I", "--ignore", "-w", "--width", "-T", "--tabsize", "--block-size",
    "--hide", "--format", "--sort", "--time-style", "--time", "--quoting-style",
    "--indicator-style",
}  # fmt: skip


def load_segmenter() -> ModuleType:
    path = Path(__file__).with_name("grove-worktree-detect.py")
    spec = importlib.util.spec_from_file_location("grove_worktree_detect", path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


seg_mod: ModuleType | None = None


def expand(value: str) -> str:
    value = HOME_VAR_RE.sub(HOME, value)
    return os.path.expanduser(value)


def resolve(path: str, cwd: str | None) -> str | None:
    """Absolute normalised PATH, or None when it is relative and cwd unknown."""
    path = expand(path)
    if os.path.isabs(path):
        return os.path.normpath(path)
    if not cwd:
        return None
    return os.path.normpath(os.path.join(cwd, path))


def broad_root(path: str, cwd: str | None) -> str | None:
    """The broad root PATH walks, or None. `~/*` counts as walking `~`."""
    full = resolve(path, cwd)
    if full is None:
        return None
    if full in BROAD:
        return full
    stripped = path.rstrip("/") if path not in ("/", "") else path
    base = os.path.basename(stripped) + ("/" if path.endswith("/") else "")
    if base in GLOB_ONLY or os.path.basename(stripped) in GLOB_ONLY:
        parent = os.path.dirname(full)
        if parent in BROAD:
            return parent
    return None


def depth_ok(value: str) -> bool:
    try:
        return int(value) <= SAFE_DEPTH
    except ValueError:
        return False


def walk_roots(paths: list[str], cwd: str | None, implicit: bool) -> str | None:
    """First broad root among PATHS, or cwd when there are no paths."""
    if not paths:
        return cwd if implicit and cwd in BROAD else None
    for p in paths:
        root = broad_root(p, cwd)
        if root:
            return root
    return None


def check_find(args: list[str], cwd: str | None, implicit: bool, bfs: bool):
    i = 0
    while i < len(args):
        t = args[i]
        if t in FIND_PRE_OPTS or (t.startswith("-O") and t[2:].isdigit()):
            i += 1
        elif t == "-D" or (bfs and t in BFS_VALUE_OPTS):
            i += 2
        elif bfs and (t.startswith("-j") or t in {"-E", "-X", "-s", "-x"}):
            i += 1
        else:
            break
    paths = []
    while i < len(args):
        t = args[i]
        if bfs and t == "-f" and i + 1 < len(args):
            paths.append(args[i + 1])
            i += 2
            continue
        if t.startswith("-") or t in ("(", "!", ")", ","):
            break
        paths.append(t)
        i += 1
    expr = args[i:]
    depths = [expr[j + 1] for j, t in enumerate(expr[:-1]) if t == "-maxdepth"]
    if depths and depth_ok(depths[-1]):
        return None
    if bfs:
        # bfs also takes paths after the expression, and `-f PATH`. A token
        # after an option is that option's argument, not a path.
        for j, t in enumerate(expr):
            prev = expr[j - 1] if j else ""
            if prev == "-f" or (not t.startswith("-") and prev in ("(", ")", "!")):
                paths.append(t)
            elif j and not t.startswith("-") and not prev.startswith("-"):
                paths.append(t)
    return walk_roots(paths, cwd, implicit)


def option_scan(
    args: list[str], value_opts: set[str], depth_opts: set[str]
) -> tuple[list[str], dict[str, list[str]], bool]:
    """Split ARGS into positionals and options. Returns (positionals, opts,
    depth_limited). opts maps each option to all its values, so a repeated
    option keeps every value. Handles --opt=value, -Xvalue and `--`. The last
    depth option wins, as it does in the tools.
    """
    pos: list[str] = []
    opts: dict[str, list[str]] = {}
    depth: str | None = None

    def add(name: str, val: str) -> None:
        nonlocal depth
        opts.setdefault(name, []).append(val)
        if name in depth_opts:
            depth = val

    i = 0
    while i < len(args):
        t = args[i]
        if t == "--":
            pos.extend(args[i + 1 :])
            break
        if t.startswith("--") and "=" in t:
            add(*t.split("=", 1))
            i += 1
            continue
        if t in value_opts or t in depth_opts:
            add(t, args[i + 1] if i + 1 < len(args) else "")
            i += 2
            continue
        if t.startswith("-") and len(t) > 1:
            short = t[:2]
            if len(t) > 2 and (short in value_opts or short in depth_opts):
                add(short, t[2:])
            else:
                add(t, "")
            i += 1
            continue
        pos.append(t)
        i += 1
    return pos, opts, depth is not None and depth_ok(depth)


def check_fd(args, cwd, implicit):
    pos, opts, limited = option_scan(
        args, FD_VALUE_OPTS | {"--base-directory", "--search-path"}, FD_DEPTH_OPTS
    )
    if limited:
        return None
    base = opts.get("--base-directory")
    if base:
        cwd = resolve(base[-1], cwd)
        implicit = True
    paths = pos[1:] + opts.get("--search-path", [])
    return walk_roots(paths, cwd, implicit)


def check_rg(args, cwd, implicit, piped):
    pos, opts, limited = option_scan(args, RG_VALUE_OPTS, RG_DEPTH_OPTS)
    if limited:
        return None
    files_mode = "--files" in opts
    pattern_given = any(k in opts for k in ("-e", "--regexp", "-f", "--file"))
    paths = pos if files_mode or pattern_given else pos[1:]
    if not paths and piped and not files_mode:
        return None  # rg reads stdin
    return walk_roots(paths, cwd, implicit)


def grep_recursive(args: list[str]) -> bool:
    for i, t in enumerate(args):
        if t == "--":
            return False
        if t in ("--recursive", "--dereference-recursive"):
            return True
        if t in ("--directories=recurse", "-drecurse"):
            return True
        if t in ("-d", "--directories") and i + 1 < len(args):
            if args[i + 1] == "recurse":
                return True
        if t.startswith("-") and not t.startswith("--") and len(t) > 1:
            for ch in t[1:]:
                if ch in "rR":
                    return True
                if ch in GREP_VALUE_LETTERS:
                    break
    return False


def ugrep_shallow(args: list[str]) -> bool:
    """True when ugrep will not go deep: -1 .. -9, --depth=N (also MIN,MAX),
    or `-d skip` / `--directories=skip`. The token after a value option such
    as `-e` is that option's value, never a depth flag."""
    depth = None
    prev = ""
    for t in args:
        if t == "--":
            break
        after_value_opt = (
            len(prev) == 2 and prev[0] == "-" and prev[1] in UGREP_VALUE_LETTERS
        )
        if after_value_opt:
            if prev == "-d" and t == "skip":
                return True
        elif t in ("--directories=skip", "-dskip"):
            return True
        elif t.startswith("--depth="):
            depth = t.split("=", 1)[1].split(",")[-1]
        elif len(t) == 2 and t[0] == "-" and t[1].isdigit():
            depth = t[1]
        prev = "" if after_value_opt else t
    return depth is not None and depth_ok(depth)


def check_grep(args, cwd, implicit, ugrep=False, piped=False):
    """grep -r, and ugrep or ug, which recurse into the cwd by default."""
    if ugrep:
        if ugrep_shallow(args):
            return None
    elif not grep_recursive(args):
        return None
    value_letters = UGREP_VALUE_LETTERS if ugrep else GREP_VALUE_LETTERS
    pos: list[str] = []
    pattern_given = False
    i = 0
    while i < len(args):
        t = args[i]
        if t == "--":
            pos.extend(args[i + 1 :])
            break
        if t.startswith("--"):
            name = t.split("=", 1)[0]
            if name in ("--regexp", "--file"):
                pattern_given = True
            i += 2 if (t in GREP_VALUE_LONG) else 1
            continue
        if t.startswith("-") and len(t) > 1:
            letters = t[1:]
            for k, ch in enumerate(letters):
                if ch in value_letters:
                    if ch in "ef":
                        pattern_given = True
                    if k == len(letters) - 1:
                        i += 1  # value is the next token
                    break
            i += 1
            continue
        pos.append(t)
        i += 1
    paths = pos if pattern_given else pos[1:]
    if ugrep and not paths and piped:
        return None  # ugrep reads stdin
    return walk_roots(paths, cwd, implicit)


def check_simple(args, cwd, implicit, value_opts, depth_opts=frozenset()):
    pos, _, limited = option_scan(args, value_opts, set(depth_opts))
    if limited:
        return None
    return walk_roots(pos, cwd, implicit)


def check_ls(args, cwd, implicit):
    pos, opts, _ = option_scan(args, LS_VALUE_OPTS, set())
    short = "".join(k[1:] for k in opts if k.startswith("-") and k[1:2] != "-")
    recursive = "--recursive" in opts or "R" in short
    if not recursive or "d" in short or "--directory" in opts:
        return None
    return walk_roots(pos, cwd, implicit)


def check_btrfs(args, cwd, implicit):
    # btrfs [global opts] filesystem|fi|f du [opts] paths
    pos = [a for a in args if not a.startswith("-")]
    if len(pos) < 2:
        return None
    if not "filesystem".startswith(pos[0]) or pos[1] != "du":
        return None
    sub = args[args.index(pos[1]) + 1 :]
    paths = [a for a in sub if not a.startswith("-")]
    return walk_roots(paths, cwd, implicit)


def check_command(
    tokens: list[str], cwd: str | None, piped: bool, depth: int
) -> str | None:
    """Root walked by one simple command, or None."""
    implicit = True
    i = 0
    while i < len(tokens):
        t = tokens[i]
        head = os.path.basename(t)
        if ASSIGN_RE.match(t):
            i += 1
            continue
        if head in ("command", "type", "which") and any(
            a in ("-v", "-V") for a in tokens[i + 1 : i + 2]
        ):
            return None
        if head in WRAPPERS:
            opts = WRAPPERS[head]
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                if head == "sudo" and tokens[i] in ("-D", "--chdir"):
                    cwd = resolve(tokens[i + 1], cwd) if i + 1 < len(tokens) else cwd
                i += 2 if tokens[i] in opts else 1
            continue
        if head == "env":
            i += 1
            while i < len(tokens) and (
                tokens[i].startswith("-") or ASSIGN_RE.match(tokens[i])
            ):
                t2 = tokens[i]
                if t2 in ("-C", "--chdir") and i + 1 < len(tokens):
                    cwd = resolve(tokens[i + 1], cwd)
                    i += 2
                    continue
                if t2.startswith("--chdir="):
                    cwd = resolve(t2.split("=", 1)[1], cwd)
                i += 2 if t2 in ENV_OPTS else 1
            continue
        if head == "timeout":
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                i += 2 if tokens[i] in TIMEOUT_OPTS else 1
            i += 1
            continue
        if head == "xargs":
            # Paths then come from stdin, so a missing path is not the cwd.
            implicit = False
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                i += 2 if tokens[i] in XARGS_OPTS else 1
            continue
        break
    if i >= len(tokens):
        return None
    head = os.path.basename(tokens[i])
    args = tokens[i + 1 :]

    if head in SHELLS and depth < 3:
        for j, a in enumerate(args):
            if a == "-c" or (a.startswith("-") and not a.startswith("--") and "c" in a):
                if j + 1 < len(args):
                    return check_text(args[j + 1], cwd, depth + 1)[0]
                return None
        return None
    if head == "eval" and depth < 3:
        return check_text(" ".join(args), cwd, depth + 1)[0]
    if head in ("find", "gfind"):
        return check_find(args, cwd, implicit, bfs=False)
    if head == "bfs":
        return check_find(args, cwd, implicit, bfs=True)
    if head in ("fd", "fdfind"):
        return check_fd(args, cwd, implicit)
    if head == "rgg":
        return cwd if implicit and cwd in BROAD else None
    if head == "rg":
        return check_rg(args, cwd, implicit, piped)
    if head in ("grep", "egrep", "fgrep"):
        return check_grep(args, cwd, implicit)
    if head in ("ugrep", "ug"):
        return check_grep(args, cwd, implicit, ugrep=True, piped=piped)
    if head == "du":
        return check_simple(args, cwd, implicit, DU_VALUE_OPTS)
    if head == "ncdu":
        if "-f" in args:
            return None  # reads an export file, no scan
        return check_simple(args, cwd, implicit, NCDU_VALUE_OPTS)
    if head == "tree":
        return check_simple(args, cwd, implicit, TREE_VALUE_OPTS, {"-L"})
    if head == "ls":
        return check_ls(args, cwd, implicit)
    if head == "btrfs":
        return check_btrfs(args, cwd, implicit)
    return None


REDIRECT_RE = re.compile(r"^(?:\d*|&)(?:>>?|<<?<?|>&|<&|&>>?)(.*)$")


def drop_redirects(tokens: list[str]) -> list[str]:
    """Remove `2>/dev/null`, `> out`, `<in` and the like, so a redirect
    target is never read as a search path."""
    out: list[str] = []
    skip = False
    for t in tokens:
        if skip:
            skip = False
            continue
        m = REDIRECT_RE.match(t)
        if m:
            skip = not m.group(1)
            continue
        out.append(t)
    return out


def new_cwd(tokens: list[str], cwd: str | None) -> tuple[bool, str | None]:
    """(is_cd, cwd after it) for `cd X` and `pushd X`."""
    if not tokens or tokens[0] not in ("cd", "pushd"):
        return False, cwd
    args = [t for t in tokens[1:] if not t.startswith("-") or t == "-"]
    if not args:
        return True, HOME
    if args[0] == "-":
        return True, None
    return True, resolve(args[0], cwd)


def check_text(command: str, cwd: str | None, depth: int = 0) -> tuple[str | None, str]:
    """(root, segment) for the first broad walk in COMMAND."""
    assert seg_mod is not None
    blanked = seg_mod.blank_data_regions(command)
    pos = 0
    sep = ""
    pieces: list[tuple[str, str]] = []
    for m in seg_mod.SEPARATOR_RE.finditer(blanked):
        if blanked[pos : m.start()].strip():
            pieces.append((sep, command[pos : m.start()]))
        sep = m.group(0)
        pos = m.end()
    if blanked[pos:].strip():
        pieces.append((sep, command[pos:]))
    for sep, raw in pieces:
        stripped = raw.strip().lstrip("({ ").rstrip(")} ").strip()
        if not stripped:
            continue
        try:
            tokens = shlex.split(stripped, comments=True)
        except ValueError:
            continue
        tokens = drop_redirects(tokens)
        if not tokens:
            continue
        is_cd, after = new_cwd(tokens, cwd)
        if is_cd:
            # `(cd /)` changes only the subshell's cwd.
            raw_s = raw.strip()
            if not (raw_s.startswith("(") and raw_s.endswith(")")):
                cwd = after
            continue
        root = check_command(tokens, cwd, sep == "|", depth)
        if root:
            return root, stripped
    return None, ""


GLOB_CHARS_RE = re.compile(r"[*?\[{]")


def check_tool(tool: str, path: str, pattern: str, cwd: str | None) -> str | None:
    """Root walked by Claude's own Grep or Glob tool, or None.

    Grep always searches recursively. Glob walks only when its pattern has
    `**`; `*.md` in a broad folder reads that one folder. A Glob pattern's
    fixed folder prefix narrows the walk: `my-task/**/*.py` from
    /var/tmp/claude walks only my-task, and `/home/oystein/**/x` walks ~.
    """
    if tool == "Glob":
        if "**" not in pattern:
            return None
        m = GLOB_CHARS_RE.search(pattern)
        prefix = pattern[: m.start()] if m else pattern
        prefix = prefix if prefix.endswith("/") else os.path.dirname(prefix)
        if prefix:
            if os.path.isabs(expand(prefix)):
                path = prefix
            else:
                base = resolve(path, cwd) if path else cwd
                path = os.path.join(base, prefix) if base else ""
                if not path:
                    return None
    if path:
        full = resolve(path, cwd)
        return full if full in BROAD else None
    return cwd if cwd in BROAD else None


def main() -> int:
    global seg_mod
    command = os.environ.get("FS_WALK_COMMAND", "")
    cwd = os.environ.get("FS_WALK_CWD", "") or None
    tool = os.environ.get("FS_WALK_TOOL", "Bash")
    if cwd:
        cwd = os.path.normpath(cwd)
    if tool in ("Grep", "Glob"):
        path = os.environ.get("FS_WALK_PATH", "")
        root = check_tool(tool, path, os.environ.get("FS_WALK_PATTERN", ""), cwd)
        if root:
            shown = "~" if root == HOME else root
            print(f"{shown}\t{tool} tool, path {path or '(none, so the cwd)'}")
        return 0
    if not command:
        return 0
    seg_mod = load_segmenter()
    root, segment = check_text(command, cwd)
    if root:
        shown = "~" if root == HOME else root
        print(f"{shown}\t{segment}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # A bug in this detector must never block an unrelated command.
        sys.exit(0)
