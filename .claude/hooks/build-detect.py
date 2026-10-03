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
  warn  no_wrapper    a heavy cargo or dotnet command, or build.cmd/build.sh,
                      that does not run under heavy-build or the old
                      `flock ... systemd-run` rule.

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

    label = is_heavy(rest)
    if label:
        if label.startswith("cargo") and config_build_dir(rest):
            findings.append(("block", "build_dir", seg.strip()))
        td = target_dir_arg(rest) or assigns.get("CARGO_TARGET_DIR")
        if (cwd and in_tmp(cwd)) or (td and in_tmp(expand(td))):
            findings.append(("block", "tmp", seg.strip()))
        findings.append(("warn", "no_wrapper", f"{label}: {seg.strip()}"))
    return cwd


seg_mod = None


def main():
    global seg_mod
    command = os.environ.get("BUILD_GUARD_COMMAND", "")
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
