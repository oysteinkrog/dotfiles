#!/usr/bin/env python3
"""Detect four commands that ~/.claude/CLAUDE.md says agents must never run:

  bv                      without a --robot-* flag: opens the TUI and hangs.
  am doctor fix           rewrites every MCP config back to port 8765.
  cass index --semantic   mixes vector provenance in the index.
  cass-gpu index          hits a memory regression in the custom GPU build.

Reads the shell command from HARNESS_GUARD_COMMAND. When a segment should be
denied, prints one line `KIND<TAB>SEGMENT` and exits 0, where KIND is
`bv_tui`, `am_doctor_fix`, `cass_semantic` or `cass_gpu_index`. Prints
nothing when the command is fine.

Shell segmentation (quote and heredoc blanking, separator splitting, wrapper
stripping) is shared with grove-worktree-detect.py, so a quoted mention of
these commands inside another command's argument is never blocked.
"""

import importlib.util
import os
import shlex
import sys
from pathlib import Path


def load_segmenter():
    path = Path(__file__).with_name("grove-worktree-detect.py")
    spec = importlib.util.spec_from_file_location("grove_worktree_detect", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HELP_FLAGS = {"-h", "--help", "-V", "--version"}


def first_positional(tokens):
    """Index of the first token after tokens[0] that is not a flag."""
    for i in range(1, len(tokens)):
        if not tokens[i].startswith("-"):
            return i
    return None


def classify(tokens):
    head = os.path.basename(tokens[0])
    rest = tokens[1:]
    if HELP_FLAGS & set(rest) or "help" in rest[:1]:
        return None

    if head == "bv":
        if any(t.startswith("--robot") for t in rest):
            return None
        return "bv_tui"

    if head == "am":
        i = first_positional(tokens)
        if i is not None and tokens[i : i + 2] == ["doctor", "fix"]:
            return "am_doctor_fix"
        return None

    if head == "cass":
        i = first_positional(tokens)
        if i is not None and tokens[i] == "index":
            if any(
                t == "--semantic" or t.startswith("--semantic=")
                for t in tokens[i + 1 :]
            ):
                return "cass_semantic"
        return None

    if head == "cass-gpu":
        i = first_positional(tokens)
        if i is not None and tokens[i] == "index":
            return "cass_gpu_index"
        return None

    return None


def main():
    command = os.environ.get("HARNESS_GUARD_COMMAND", "")
    if not command:
        return 0
    seg = load_segmenter()
    blanked = seg.blank_data_regions(command)
    for raw_segment in seg.split_segments(command, blanked):
        try:
            tokens = shlex.split(raw_segment)
        except ValueError:
            continue
        tokens = seg.strip_wrappers(tokens)
        if not tokens:
            continue
        kind = classify(tokens)
        if kind:
            print(f"{kind}\t{raw_segment.strip()}")
            return 0
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # A bug in this detector must never block an unrelated command.
        sys.exit(0)
