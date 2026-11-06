#!/usr/bin/env python3
"""Detect build commands that break the "Builds" rules in ~/.claude/CLAUDE.md.

Reads the shell command from BUILD_GUARD_COMMAND and the PreToolUse payload's
cwd from BUILD_GUARD_CWD. Prints one line per finding,
`ACTION<TAB>KIND<TAB>DETAIL`, where ACTION is `block` or `warn`:

  block build_dir     sets CARGO_BUILD_BUILD_DIR or `--config build.build-dir`
                      (allowed when the value is under ~/.cache/build, which
                      is localbuild's).
  block tmp           git clone, gh repo clone or git worktree add into /tmp,
                      or a heavy build whose directory is under /tmp. /tmp is
                      tmpfs, so every byte there is RAM.
  block grove_lane    git worktree add from a grove repo (the monorepo) to a
                      path outside grove's work_dir. Use grove new --ephemeral.
  block bare_systemd_run  `systemd-run` (unit or --scope) that runs a build,
                      Wine, MotionCatalyst or headless-mc.sh without
                      heavy-build or `job submit`/`job run`. Such a job skips
                      jobd's memory check. A wrapper script given to
                      systemd-run is read (comment lines dropped) and counts
                      when it runs one of those. Oystein chose block,
                      2026-11-06, after `systemd-run --user --unit
                      lane17078-runmc ... 17078-runmc.sh` ran MC outside jobd.
  warn  no_wrapper    a heavy cargo or dotnet command, build.cmd/build.sh or
                      the monorepo's tools/wine/run-tests.sh, that does not run under heavy-build or the old
                      `flock ... systemd-run` rule.
  warn  no_incremental  a dotnet build, test, msbuild or publish with
                      --no-incremental or a Rebuild target, wrapped or not.
                      It forces a full rebuild of the project and its
                      dependencies.
  warn  background    BUILD_GUARD_BACKGROUND=1 (the Bash call has
                      run_in_background) and the command runs heavy-build or
                      a heavy build directly. Claude Code kills background
                      shells when memory runs low.
  warn  cpu_pin       taskset, numactl --physcpubind (or -C), realtime chrt
                      (-f, -r), or a `while :; do :; done` busy loop. On
                      2026-10-13 40 busy loops pinned to CPUs 30 and 31 starved
                      the NVIDIA modeset thread and KWin's output thread there,
                      and the desktop froze for seconds at a time.

Prints nothing when the command is fine. Shell segmentation (quote and
heredoc blanking, separator splitting) is shared with grove-worktree-detect.py,
so a quoted mention or a heredoc line is never treated as a command. Any
error of its own makes it print nothing (fail open).
"""

import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

HOME = os.path.expanduser("~")
LOCALBUILD_DIR = os.path.join(HOME, ".cache", "build")
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)

# Wrappers that run the rest of the line as a command. Values are the options
# that take a separate value token.
WRAPPERS = {
    "env": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"},
    "time": {"-f", "--format", "-o", "--output"},
    "command": set(),
    "nice": {"-n", "--adjustment"},
    "nohup": set(),
    "ionice": {"-c", "--class", "-n", "--classdata", "-p", "-P", "-u"},
    "stdbuf": {"-i", "-o", "-e"},
    "setsid": set(),
    "chrt": set(),
    "exec": set(),
}
# Wrappers that take one positional argument before the command.
POSITIONAL_WRAPPERS = {"timeout": {"-s", "--signal", "-k", "--kill-after"}}
# These run the build under the machine-wide lock already.
LOCKED_HEADS = {"heavy-build", "flock", "systemd-run"}

CARGO_HEAVY = {
    "build", "b", "check", "c", "test", "t", "clippy", "bench", "nextest",
    "llvm-cov", "doc", "d", "install", "miri", "rustc", "fix",
}  # fmt: skip
CARGO_LIGHT_FLAGS = {"-h", "--help", "-V", "--version", "--list"}
DOTNET_HEAVY = {"build", "test", "publish", "pack", "msbuild", "run", "vstest"}
DOTNET_REBUILDABLE = {"build", "test", "publish", "msbuild"}
REBUILD_TARGET_RE = re.compile(
    r"^[-/](?:t|target):(?:.*[;,])?Rebuild(?:[;,].*)?$", re.I
)
SCRIPT_SHELLS = {"bash", "sh", "dash", "zsh"}


def is_wine_run_tests(path, cwd):
    """True for the monorepo's tools/wine/run-tests.sh, however it is named."""
    if os.path.basename(path) != "run-tests.sh":
        return False
    full = os.path.normpath(os.path.join(cwd or "", expand(path)))
    return full.endswith(os.path.join("tools", "wine", "run-tests.sh"))


def script_head(tokens):
    """`bash tools/wine/run-tests.sh ...` -> the script path, else tokens[0]."""
    if os.path.basename(tokens[0]) in SCRIPT_SHELLS:
        for t in tokens[1:]:
            if t.startswith("-"):
                if t == "-c" or (not t.startswith("--") and "c" in t[1:]):
                    return tokens[0]
                continue
            return t
    return tokens[0]


def forced_rebuild(tokens):
    """Flag text when tokens contain a dotnet build/test/msbuild/publish that
    forces a full rebuild. Looks past wrappers such as heavy-build."""
    for i, t in enumerate(tokens):
        if os.path.basename(t) != "dotnet":
            continue
        args = tokens[i + 1 :]
        sub = next((a for a in args if not a.startswith("-")), None)
        if sub not in DOTNET_REBUILDABLE:
            return None
        for a in args:
            if a == "--no-incremental":
                return a
            if REBUILD_TARGET_RE.match(a):
                return a
        return None
    return None


def load_segmenter():
    path = Path(__file__).with_name("grove-worktree-detect.py")
    spec = importlib.util.spec_from_file_location("grove_worktree_detect", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expand(value):
    return os.path.expanduser(os.path.expandvars(value))


def under(path, root):
    if not path:
        return False
    p = os.path.normpath(path)
    r = os.path.normpath(root)
    return p == r or p.startswith(r + os.sep)


def in_tmp(path):
    return under(path, "/tmp")


def strip(tokens):
    """Drop env assignments and wrapper commands. Returns (assignments, rest)."""
    assigns = {}
    i = 0
    while i < len(tokens):
        t = tokens[i]
        m = ASSIGN_RE.match(t)
        if m:
            assigns[m.group(1)] = m.group(2)
            i += 1
            continue
        head = os.path.basename(t)
        if head in WRAPPERS:
            value_opts = WRAPPERS[head]
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                i += 2 if tokens[i] in value_opts else 1
            continue
        if head in POSITIONAL_WRAPPERS:
            value_opts = POSITIONAL_WRAPPERS[head]
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                i += 2 if tokens[i] in value_opts else 1
            i += 1  # the duration
            continue
        break
    return assigns, tokens[i:]


def cargo_parts(tokens):
    """tokens[0] is cargo (or `rustup run TC cargo`). Returns (subcommand, args)."""
    i = 1
    while i < len(tokens):
        t = tokens[i]
        if t.startswith("+"):
            i += 1
            continue
        if t in ("-C", "--config", "-Z", "--color"):
            i += 2
            continue
        if t.startswith("-"):
            if t in CARGO_LIGHT_FLAGS:
                return None, tokens[i:]
            i += 1
            continue
        return t, tokens[i + 1 :]
    return None, []


def config_build_dir(tokens):
    for i, t in enumerate(tokens):
        val = None
        if t == "--config" and i + 1 < len(tokens):
            val = tokens[i + 1]
        elif t.startswith("--config="):
            val = t[len("--config=") :]
        if val and re.match(r"^\s*build\.build-dir\s*=", val):
            return val
    return None


def target_dir_arg(tokens):
    for i, t in enumerate(tokens):
        if t == "--target-dir" and i + 1 < len(tokens):
            return tokens[i + 1]
        if t.startswith("--target-dir="):
            return t.split("=", 1)[1]
    return None


def is_heavy(tokens):
    """Return a short label when the stripped tokens are a heavy build."""
    head = os.path.basename(tokens[0])
    if head == "rustup" and len(tokens) > 3 and tokens[1] == "run":
        tokens = tokens[3:]
        head = os.path.basename(tokens[0])
    if head == "cargo" or head.startswith("cargo-"):
        sub, args = cargo_parts(tokens)
        if head.startswith("cargo-"):
            sub = head[len("cargo-") :]
            args = tokens[1:]
        if sub not in CARGO_HEAVY:
            return None
        if CARGO_LIGHT_FLAGS & set(args):
            return None
        if sub == "nextest" and args[:1] in (["list"], ["show-config"]):
            return None
        if sub == "llvm-cov" and args[:1] in (["report"], ["clean"]):
            return None
        return f"cargo {sub}"
    if head == "dotnet":
        args = [t for t in tokens[1:] if not t.startswith("-")]
        if args and args[0] in DOTNET_HEAVY and not CARGO_LIGHT_FLAGS & set(tokens):
            return f"dotnet {args[0]}"
        return None
    if head in ("build.cmd", "build.sh"):
        return head
    return None


def is_heavy_in(tokens, cwd):
    """is_heavy plus the monorepo's Wine test runner."""
    label = is_heavy(tokens)
    if label:
        return label
    if is_wine_run_tests(script_head(tokens), cwd):
        return "tools/wine/run-tests.sh"
    return None


def grove_repos():
    """[(work_dir, common_git_dir)] for each repo in ~/.config/grove/repos.json."""
    try:
        cfg = json.loads(Path(HOME, ".config/grove/repos.json").read_text())
    except (OSError, ValueError):
        return []
    out = []
    for repo in (cfg.get("repos") or {}).values():
        wd, main = repo.get("work_dir"), repo.get("main_repo")
        if not wd or not main:
            continue
        out.append((os.path.normpath(wd), git_common_dir(main)))
    return out


def git_common_dir(path):
    if not path or not os.path.isdir(path):
        return None
    try:
        r = subprocess.run(
            [
                "git",
                "-C",
                path,
                "rev-parse",
                "--path-format=absolute",
                "--git-common-dir",
            ],
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return (
        os.path.normpath(r.stdout.strip())
        if r.returncode == 0 and r.stdout.strip()
        else None
    )


# systemd-run options that take a separate value token.
SYSTEMD_RUN_VALUE_OPTS = {
    "-u", "--unit", "-p", "--property", "--slice", "--description", "-E",
    "--setenv", "--working-directory", "--uid", "--gid", "--nice",
    "--service-type", "--on-active", "--on-boot", "--on-startup",
    "--on-unit-active", "--on-unit-inactive", "--on-calendar", "-M",
    "--machine", "-H", "--host", "--path-property", "--socket-property",
    "--timer-property", "--capsule", "-C", "--json", "--expand-environment",
}  # fmt: skip
SCRIPT_READ_MAX = 256 * 1024
WINE_HEADS = {"wine", "wine64", "wine64-preloader", "headless-mc.sh"}
# Shell words that can come before a command on a script line.
LEAD_WORDS = {"then", "do", "else", "elif", "if", "while", "until", "!", "{", "(", "time"}


def systemd_run_inner(args):
    """args follow `systemd-run`. Returns (command tokens, working directory
    from --working-directory/-d or None)."""
    wd = None
    i = 0
    while i < len(args):
        t = args[i]
        if t == "--":
            return args[i + 1 :], wd
        if t.startswith("--working-directory="):
            wd = t.split("=", 1)[1]
        elif t == "--working-directory" and i + 1 < len(args):
            wd = args[i + 1]
        if not t.startswith("-") or t == "-":
            return args[i:], wd
        i += 2 if t in SYSTEMD_RUN_VALUE_OPTS else 1
    return [], wd


def script_text(path, cwd):
    """The text of a wrapper script, or None when PATH is not a script file."""
    full = os.path.normpath(os.path.join(cwd or "", expand(path)))
    try:
        if not os.path.isfile(full) or os.path.getsize(full) > SCRIPT_READ_MAX:
            return None
        with open(full, "rb") as f:
            head = f.read(SCRIPT_READ_MAX)
    except OSError:
        return None
    if b"\0" in head:
        return None  # a binary, not a script
    text = head.decode("utf-8", "replace")
    if not (text.startswith("#!") or full.endswith(".sh")):
        return None
    return text


def guarded_text(text, cwd, depth):
    """The first command in shell TEXT that a bare systemd-run must not run."""
    if depth > 3:
        return None
    blanked = seg_mod.blank_data_regions(text)
    for raw in seg_mod.split_segments(text, blanked):
        stripped = raw.strip().lstrip("({ ").rstrip(")} ").strip()
        if not stripped:
            continue
        try:
            tokens = shlex.split(stripped, comments=True)
        except ValueError:
            continue
        hit = guarded_cmd(tokens, cwd, depth)
        if hit:
            return hit
    return None


def guarded_cmd(tokens, cwd, depth=0):
    """What TOKENS (one command) runs outside the queue, or None. A command
    that is heavy-build or `job submit`/`job run` is queued and fine."""
    _, rest = strip(tokens)
    while rest and rest[0] in LEAD_WORDS:
        _, rest = strip(rest[1:])
    if not rest:
        return None
    head = os.path.basename(rest[0])
    if head == "heavy-build" or (head == "job" and rest[1:2] in (["submit"], ["run"])):
        return None
    if head in SHELLS:
        for j, a in enumerate(rest[1:], 1):
            if a == "-c" or (a.startswith("-") and not a.startswith("--") and "c" in a):
                return guarded_text(rest[j + 1], cwd, depth + 1) if j + 1 < len(rest) else None
        path = script_head(rest)
        if path is rest[0]:
            return None
        body = script_text(path, cwd)
        hit = body and guarded_text(body, cwd, depth + 1)
        return f"{hit} (in {path})" if hit else None
    if head in WINE_HEADS or head.startswith("MotionCatalyst"):
        return head
    label = is_heavy_in(rest, cwd)
    if label:
        return label
    if head == "ninja" and not {"--version", "-h", "--help"} & set(rest):
        return "ninja"
    if head == "cmake" and "--build" in rest:
        return "cmake --build"
    if "/" in rest[0]:
        body = script_text(rest[0], cwd)
        hit = body and guarded_text(body, cwd, depth + 1)
        return f"{hit} (in {rest[0]})" if hit else None
    return None


def bare_systemd_run(rest, cwd):
    """rest starts with systemd-run. Returns what it runs outside the queue,
    or None when it runs nothing guarded or goes through heavy-build/job."""
    inner, wd = systemd_run_inner(rest[1:])
    if wd:
        cwd = os.path.normpath(os.path.join(cwd or "", expand(wd)))
    return guarded_cmd(inner, cwd) if inner else None


def check_segment(seg, tokens, cwd, findings, grove):
    assigns, rest = strip(tokens)
    if not rest and not assigns:
        return cwd

    # export CARGO_BUILD_BUILD_DIR=...
    if rest and rest[0] == "export":
        for t in rest[1:]:
            m = ASSIGN_RE.match(t)
            if m:
                assigns[m.group(1)] = m.group(2)
        rest = []

    bd = assigns.get("CARGO_BUILD_BUILD_DIR")
    if bd is not None and not under(expand(bd), LOCALBUILD_DIR):
        findings.append(("block", "build_dir", seg.strip()))
    if not rest:
        return cwd

    head = os.path.basename(rest[0])

    flag = forced_rebuild(rest)
    if flag:
        findings.append(("warn", "no_incremental", f"{flag}: {seg.strip()}"))

    if head == "cd":
        target = rest[1] if len(rest) > 1 else HOME
        return seg_mod.resolve_dir(expand(target), cwd) if target != "-" else None

    if head == "git" or head == "gh":
        expanded = shlex.join([os.path.expanduser(t) for t in tokens])
        result = seg_mod.classify_segment(expanded, cwd)
        if result and not result[0].startswith("grove_"):
            kind, target, eff_cwd = result
            if target and in_tmp(target):
                findings.append(("block", "tmp", f"{seg.strip()}  (target {target})"))
            elif kind == "worktree_add" and target and grove:
                src = git_common_dir(eff_cwd)
                for wd, common in grove:
                    if src and common and src == common and not under(target, wd):
                        findings.append(
                            ("block", "grove_lane", f"{seg.strip()}  (target {target})")
                        )
                        break
        return cwd

    if head == "heavy-build" and BACKGROUND:
        findings.append(("warn", "background", seg.strip()))

    if head == "systemd-run":
        hit = bare_systemd_run(rest, cwd)
        if hit:
            findings.append(("block", "bare_systemd_run", f"{hit}: {seg.strip()}"))
            return cwd

    if head in LOCKED_HEADS:
        # Still check a build dir override written after the wrapper.
        inner_assigns = {
            m.group(1): m.group(2) for t in rest if (m := ASSIGN_RE.match(t))
        }
        bd = inner_assigns.get("CARGO_BUILD_BUILD_DIR")
        if bd is not None and not under(expand(bd), LOCALBUILD_DIR):
            findings.append(("block", "build_dir", seg.strip()))
        inner = rest[1:]
        if config_build_dir(inner):
            findings.append(("block", "build_dir", seg.strip()))
        return cwd

    label = is_heavy_in(rest, cwd)
    if label:
        if BACKGROUND:
            findings.append(("warn", "background", seg.strip()))
        if label.startswith("cargo") and config_build_dir(rest):
            findings.append(("block", "build_dir", seg.strip()))
        td = target_dir_arg(rest) or assigns.get("CARGO_TARGET_DIR")
        if (cwd and in_tmp(cwd)) or (td and in_tmp(expand(td))):
            findings.append(("block", "tmp", seg.strip()))
        findings.append(("warn", "no_wrapper", f"{label}: {seg.strip()}"))
    return cwd


SHELLS = {"sh", "bash", "zsh", "dash", "fish"}
CHRT_REALTIME = {"-f", "--fifo", "-r", "--rr"}
# `while :; do :; done`, `while true; do true; done` and the like: a loop
# whose body never waits. Checked on the raw text, so it is found inside
# `sh -c '...'` too.
BUSY_LOOP_RE = re.compile(
    r"\bwhile\s+(?::|true)\s*(?:;|\n)\s*do\s+(?:(?::|true)\s*(?:;|\n)\s*)*done\b"
)


def chrt_realtime(args):
    """args follow `chrt`. True when they set SCHED_FIFO or SCHED_RR.

    Without a policy flag chrt sets SCHED_RR, so `chrt 50 cmd` counts too.
    """
    flags = set()
    i = 0
    while i < len(args) and args[i].startswith("-"):
        t = args[i]
        if t in CHRT_REALTIME:
            return True
        if t.startswith("--"):
            flags.add(t)
        else:
            flags.update(t[1:])
        i += 1
    if "f" in flags or "r" in flags:
        return True
    other = {"o", "b", "i", "d", "e", "m", "--other", "--batch", "--idle"}
    other |= {"--deadline", "--ext", "--max", "-h", "--help", "-V", "--version"}
    if flags & other:
        return False
    positional = args[i:]
    if "p" in flags or "--pid" in flags:
        return len(positional) >= 2
    return bool(positional) and positional[0].isdigit()


def numactl_pins(args):
    return any(
        t == "-C" or t.startswith("-C") or t.startswith("--physcpubind") for t in args
    )


def pin_findings(tokens, depth=0):
    """Labels for CPU pinning or realtime commands in one segment's tokens.

    Walks through env assignments, wrappers, heavy-build and `sh -c '...'`,
    so `heavy-build taskset ...` and `sh -c 'taskset ...'` are found too.
    """
    found = []
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if ASSIGN_RE.match(t):
            i += 1
            continue
        head = os.path.basename(t)
        rest = tokens[i + 1 :]
        if head == "taskset":
            found.append("taskset")
            return found
        if head == "numactl":
            if numactl_pins(rest):
                found.append("numactl --physcpubind")
            return found
        if head == "chrt":
            if chrt_realtime(rest):
                found.append("realtime chrt")
            return found
        if head in SHELLS and depth < 3:
            for j, a in enumerate(rest):
                if a == "-c" or (
                    a.startswith("-") and not a.startswith("--") and "c" in a
                ):
                    if j + 1 < len(rest):
                        found.extend(pin_findings_text(rest[j + 1], depth + 1))
                    break
            return found
        if (
            head in WRAPPERS
            or head in POSITIONAL_WRAPPERS
            or head in LOCKED_HEADS
            or head == "sudo"
        ):
            # Skip the wrapper and its options; what follows may be the pin.
            value_opts = WRAPPERS.get(head) or POSITIONAL_WRAPPERS.get(head) or set()
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                i += 2 if tokens[i] in value_opts else 1
            if head in POSITIONAL_WRAPPERS:
                i += 1
            continue
        return found
    return found


def pin_findings_text(command, depth=0):
    found = []
    assert seg_mod is not None
    blanked = seg_mod.blank_data_regions(command)
    for raw in seg_mod.split_segments(command, blanked):
        stripped = raw.strip().lstrip("({ ").rstrip(")} ").strip()
        if not stripped:
            continue
        try:
            tokens = shlex.split(stripped, comments=True)
        except ValueError:
            continue
        if tokens:
            found.extend(pin_findings(tokens, depth))
    return found


def cpu_pin_finding(command):
    labels = pin_findings_text(command)
    if BUSY_LOOP_RE.search(command):
        labels.append("busy loop")
    if not labels:
        return None
    return ("warn", "cpu_pin", ", ".join(dict.fromkeys(labels)))


seg_mod = None
BACKGROUND = False


def main():
    global seg_mod, BACKGROUND
    command = os.environ.get("BUILD_GUARD_COMMAND", "")
    BACKGROUND = os.environ.get("BUILD_GUARD_BACKGROUND") == "1"
    cwd = os.environ.get("BUILD_GUARD_CWD", "") or None
    if not command:
        return 0
    seg_mod = load_segmenter()
    grove = grove_repos() if "worktree" in command else []
    blanked = seg_mod.blank_data_regions(command)
    findings = []
    for raw in seg_mod.split_segments(command, blanked):
        stripped = raw.strip().lstrip("({ ").rstrip(")} ").strip()
        if not stripped:
            continue
        try:
            tokens = shlex.split(stripped, comments=True)
        except ValueError:
            continue
        if not tokens:
            continue
        cwd = check_segment(stripped, tokens, cwd, findings, grove)
    pin = cpu_pin_finding(command)
    if pin:
        findings.append(pin)
    seen = set()
    for action, kind, detail in findings:
        if (action, kind) in seen:
            continue
        seen.add((action, kind))
        print(f"{action}\t{kind}\t{detail}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # A bug in this detector must never block an unrelated command.
        sys.exit(0)
