#!/usr/bin/env python3
"""PreToolUse(Bash) hook: steer grep/find away from raw GNU tools.

Reads the Claude Code PreToolUse JSON envelope from stdin, parses the bash
command via shlex (so quoted strings and most heredocs are skipped naturally),
and emits a permissionDecision of "deny" with a coaching message when the
command uses grep/egrep/fgrep/find at a command position, or hits the
`cat <file> | grep` / `ls | grep` antipatterns. Allows everything else.

Suggestions point at the fff MCP tools (mcp__fff__ffgrep / mcp__fff__fffind)
when fff is registered in ~/.claude.json, with rg/fd as the fallback.
"""

from __future__ import annotations

import json
import os
import shlex
import sys
from pathlib import Path

SEARCH_CMDS = {"grep", "egrep", "fgrep"}
FIND_CMDS = {"find"}
LISTING_CMDS = {"ls"}
CAT_CMDS = {"cat"}
# Separators after which the next token is a fresh command position.
SEPARATORS = {"|", "||", "&&", ";", "&", "|&"}


def fff_registered() -> bool:
    """Best-effort check: does the user's Claude config mention fff as MCP server?"""
    cfg = Path.home() / ".claude.json"
    if not cfg.is_file():
        return False
    try:
        data = json.loads(cfg.read_text())
    except (OSError, json.JSONDecodeError):
        return False
    # Check user-scope mcpServers and any project-scope ones too.
    if "fff" in (data.get("mcpServers") or {}):
        return True
    for proj in (data.get("projects") or {}).values():
        if "fff" in (proj.get("mcpServers") or {}):
            return True
    return False


def tokenize(command: str) -> list[str] | None:
    """Tokenize a bash command. Returns None if it can't be parsed cleanly."""
    try:
        # posix=True respects quotes; comments=False to keep #-things intact.
        return shlex.split(command, posix=True, comments=False)
    except ValueError:
        return None


def command_position_tokens(tokens: list[str]) -> list[tuple[int, str, str | None]]:
    """Indices where a new command begins, with the separator that opened them.

    Returns (token_index, first_token, preceding_separator). The preceding
    separator is None for the first command and the literal separator token
    (|, ||, &&, ;, &, |&) otherwise. Used to distinguish pipe-fed grep
    (stdin stream filter — fine) from grep-as-primary-search (worth steering).
    """
    positions: list[tuple[int, str, str | None]] = []
    at_start = True
    last_sep: str | None = None
    for i, tok in enumerate(tokens):
        if at_start and tok and tok not in SEPARATORS:
            positions.append((i, tok, last_sep))
            at_start = False
        if tok in SEPARATORS:
            at_start = True
            last_sep = tok
    return positions


def strip_env_prefix(tokens: list[str], start: int) -> int:
    """Skip VAR=value env-var prefixes, return index of the actual command word."""
    i = start
    while i < len(tokens) and "=" in tokens[i] and not tokens[i].startswith("="):
        head = tokens[i].split("=", 1)[0]
        if head.isidentifier() or all(c.isalnum() or c == "_" for c in head):
            i += 1
            continue
        break
    return i


def detect_issues(command: str) -> list[str]:
    """Return a list of human-readable issues. Empty = allow."""
    tokens = tokenize(command)
    if tokens is None:
        # Unparseable — don't block; let Claude run it.
        return []

    issues: list[str] = []
    positions = command_position_tokens(tokens)

    # Track the "previous command at position" for pipe-antipattern detection.
    prev_cmd_name: str | None = None
    prev_cmd_idx: int | None = None

    for idx, _first_tok, prev_sep in positions:
        cmd_idx = strip_env_prefix(tokens, idx)
        if cmd_idx >= len(tokens):
            continue
        cmd = tokens[cmd_idx]
        pipe_fed = prev_sep in {"|", "|&"}

        # Skip `git grep` and `git ls-files | grep` style — `git` itself is fine.
        if cmd == "git":
            prev_cmd_name = "git"
            prev_cmd_idx = cmd_idx
            continue

        # cat <file> | grep <pat>  → suggest rg <pat> <file>
        if cmd in SEARCH_CMDS and prev_cmd_name in CAT_CMDS:
            issues.append(
                f"`cat ... | {cmd} ...` is a useless-cat antipattern. "
                "Run the searcher directly on the file."
            )
        # ls | grep  → suggest fd or rg --files
        elif cmd in SEARCH_CMDS and prev_cmd_name in LISTING_CMDS:
            issues.append(
                f"`ls | {cmd} ...` listing-then-filter antipattern. "
                "Use `fd <pattern>` or `rg --files | rg <pattern>`."
            )
        elif cmd in SEARCH_CMDS and not pipe_fed:
            # grep as a primary command (reading files itself) — rg is better.
            # Skip when grep is pipe-fed (`... | grep foo`); there it's just a
            # stream filter and forcing rg buys nothing.
            issues.append(f"`{cmd}` is slower and worse-defaulted than `rg`.")
        elif cmd in FIND_CMDS and not pipe_fed:
            # Only flag `find` when it looks like a name/path search.
            tail = tokens[cmd_idx + 1 : ]
            if any(t in {"-name", "-iname", "-path", "-ipath", "-regex", "-iregex"} for t in tail):
                issues.append("`find -name/-path/-regex` is slower than `fd`.")
            # `find . -type f` with no filter is fine; don't nag.

        prev_cmd_name = cmd
        prev_cmd_idx = cmd_idx

    return issues


def build_reason(issues: list[str], have_fff: bool) -> str:
    bullets = "\n".join(f"  - {x}" for x in issues)
    if have_fff:
        prefer = (
            "Prefer the fff MCP tools (frecency-ranked, git-aware) — "
            "`mcp__fff__ffgrep` for content search, `mcp__fff__fffind` for paths. "
            "Fall back to `rg <pattern> [path]` / `fd <pattern>` when fff doesn't fit."
        )
    else:
        prefer = (
            "Use `rg <pattern> [path]` for content search and "
            "`fd <pattern>` (or `fd -e ext`) for file-name search."
        )
    return (
        "Search tool steering:\n"
        f"{bullets}\n\n"
        f"{prefer}\n\n"
        "Re-run with the suggested tool. (See ~/.claude/hooks/rewrite-search.py "
        "for the exact rules.)"
    )


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        # Malformed input — fail open.
        return 0

    tool_name = payload.get("tool_name")
    have_fff = fff_registered()

    if tool_name == "Grep":
        # Only steer if fff is actually registered — otherwise the built-in
        # Grep tool (ripgrep under the hood) is the right answer.
        if not have_fff:
            return 0
        pattern = (payload.get("tool_input") or {}).get("pattern") or ""
        if "noqa: search-rewrite" in pattern:
            return 0
        reason = (
            "Prefer the fff MCP tool `mcp__fff__ffgrep` over the built-in Grep — "
            "it's frecency-ranked, git-aware, and benchmarked faster for repeated "
            "searches. Use Grep only when ffgrep doesn't fit (e.g. searching outside "
            "the git tree). Append `noqa: search-rewrite` to the pattern to override."
        )
        json.dump({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }, sys.stdout)
        return 0

    if tool_name != "Bash":
        return 0

    command = (payload.get("tool_input") or {}).get("command") or ""
    if not command:
        return 0

    # Escape hatch: trailing `# noqa: search-rewrite` lets you opt out.
    if "noqa: search-rewrite" in command:
        return 0

    issues = detect_issues(command)
    if not issues:
        return 0

    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": build_reason(issues, have_fff),
        }
    }
    json.dump(out, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
