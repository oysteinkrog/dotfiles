#!/usr/bin/env python3
"""
partial-stage.py — Sub-hunk partial staging for git.

Parses `git diff` output into individually selectable "change groups"
(contiguous blocks of added/removed lines within a hunk), presents them
with numbered labels, and generates a minimal patch for selected groups.

Usage:
    # List change groups in a file
    python3 partial-stage.py show <file>

    # Show a specific group
    python3 partial-stage.py show <file> --group 3

    # Stage specific groups (comma-separated, ranges supported)
    python3 partial-stage.py stage <file> --groups 2,5,7-9

    # Stage groups matching a pattern (searches in diff context)
    python3 partial-stage.py stage <file> --grep "lightbox"

    # Unstage specific groups from the index
    python3 partial-stage.py unstage <file> --groups 3

    # Show only groups matching a pattern
    python3 partial-stage.py show <file> --grep "lightbox"
"""

import argparse
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class DiffLine:
    """A single line from a unified diff."""
    kind: str  # '+', '-', ' ' (context)
    text: str  # line content without the leading +/-/space
    old_no: int | None = None  # line number in old file (None for additions)
    new_no: int | None = None  # line number in new file (None for deletions)


@dataclass
class ChangeGroup:
    """A contiguous block of changes (adds and/or deletes) with surrounding context."""
    index: int  # 1-based group number
    hunk_index: int  # which hunk this belongs to (1-based)
    lines: list[DiffLine] = field(default_factory=list)
    context_before: list[DiffLine] = field(default_factory=list)
    context_after: list[DiffLine] = field(default_factory=list)

    @property
    def adds(self) -> int:
        return sum(1 for l in self.lines if l.kind == '+')

    @property
    def deletes(self) -> int:
        return sum(1 for l in self.lines if l.kind == '-')

    @property
    def summary(self) -> str:
        parts = []
        if self.adds:
            parts.append(f"+{self.adds}")
        if self.deletes:
            parts.append(f"-{self.deletes}")
        return ", ".join(parts)

    def snippet(self, max_lines: int = 6) -> str:
        """Return a short preview of the change."""
        preview = []
        for l in self.lines[:max_lines]:
            prefix = '+' if l.kind == '+' else '-'
            preview.append(f"  {prefix} {l.text}")
        if len(self.lines) > max_lines:
            preview.append(f"  ... ({len(self.lines) - max_lines} more lines)")
        return "\n".join(preview)

    def matches(self, pattern: str) -> bool:
        """Check if any line in this group (or its context) matches a pattern."""
        pat = re.compile(pattern, re.IGNORECASE)
        for l in self.context_before + self.lines + self.context_after:
            if pat.search(l.text):
                return True
        return False


@dataclass
class Hunk:
    """A diff hunk with its header and parsed lines."""
    old_start: int
    old_count: int
    new_start: int
    new_count: int
    header: str
    lines: list[DiffLine] = field(default_factory=list)


def run_git_diff(file_path: str, cached: bool = False) -> str:
    """Run git diff and return the output."""
    cmd = ["git", "diff"]
    if cached:
        cmd.append("--cached")
    cmd.extend(["--", file_path])
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running git diff: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout


def parse_hunks(diff_text: str) -> tuple[str, list[Hunk]]:
    """Parse unified diff into structured hunks. Returns (file_header, hunks)."""
    lines = diff_text.split('\n')
    hunks: list[Hunk] = []
    file_header_lines: list[str] = []
    current_hunk: Hunk | None = None
    old_no = 0
    new_no = 0

    hunk_re = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$')

    for line in lines:
        m = hunk_re.match(line)
        if m:
            current_hunk = Hunk(
                old_start=int(m.group(1)),
                old_count=int(m.group(2) or '1'),
                new_start=int(m.group(3)),
                new_count=int(m.group(4) or '1'),
                header=line,
            )
            hunks.append(current_hunk)
            old_no = current_hunk.old_start
            new_no = current_hunk.new_start
        elif current_hunk is not None:
            if line.startswith('+'):
                current_hunk.lines.append(DiffLine('+', line[1:], None, new_no))
                new_no += 1
            elif line.startswith('-'):
                current_hunk.lines.append(DiffLine('-', line[1:], old_no, None))
                old_no += 1
            elif line.startswith(' '):
                current_hunk.lines.append(DiffLine(' ', line[1:], old_no, new_no))
                old_no += 1
                new_no += 1
            elif line.startswith('\\'):
                # "\ No newline at end of file"
                current_hunk.lines.append(DiffLine(' ', line, None, None))
        else:
            file_header_lines.append(line)

    return '\n'.join(file_header_lines), hunks


def extract_change_groups(hunks: list[Hunk], context: int = 3) -> list[ChangeGroup]:
    """Extract individually selectable change groups from hunks."""
    groups: list[ChangeGroup] = []
    group_idx = 0

    for hunk_idx, hunk in enumerate(hunks, 1):
        current_changes: list[DiffLine] = []
        context_buffer: list[DiffLine] = []

        def flush_group():
            nonlocal group_idx, current_changes, context_buffer
            if not current_changes:
                return
            group_idx += 1
            g = ChangeGroup(index=group_idx, hunk_index=hunk_idx)
            g.lines = current_changes[:]
            g.context_before = context_buffer[-context:]
            current_changes.clear()
            groups.append(g)

        for i, dl in enumerate(hunk.lines):
            if dl.kind == ' ':
                if current_changes:
                    # Context after the change group
                    # Look ahead to find the context_after
                    after = []
                    for j in range(i, min(i + context, len(hunk.lines))):
                        if hunk.lines[j].kind == ' ':
                            after.append(hunk.lines[j])
                        else:
                            break
                    if current_changes:
                        flush_group()
                        groups[-1].context_after = after
                context_buffer.append(dl)
            else:
                current_changes.append(dl)

        flush_group()

    return groups


def build_patch(file_header: str, hunks: list[Hunk], groups: list[ChangeGroup],
                selected_indices: set[int]) -> str:
    """Build a valid unified diff containing only the selected change groups."""
    selected_groups = [g for g in groups if g.index in selected_indices]
    if not selected_groups:
        return ""

    # Group selected changes by hunk
    by_hunk: dict[int, list[ChangeGroup]] = {}
    for g in selected_groups:
        by_hunk.setdefault(g.hunk_index, []).append(g)

    patch_hunks: list[str] = []

    for hunk_idx in sorted(by_hunk.keys()):
        hunk = hunks[hunk_idx - 1]
        selected_in_hunk = {g.index for g in by_hunk[hunk_idx]}

        # Rebuild this hunk: keep context, keep selected changes, convert
        # unselected changes back to context
        out_lines: list[str] = []
        current_changes: list[DiffLine] = []
        group_counter_base = min(g.index for g in groups if g.hunk_index == hunk_idx) - 1
        local_group_idx = group_counter_base

        def flush_local():
            nonlocal local_group_idx, current_changes
            if not current_changes:
                return
            local_group_idx += 1
            if local_group_idx in selected_in_hunk:
                # Keep the change
                for dl in current_changes:
                    if dl.kind == '+':
                        out_lines.append('+' + dl.text)
                    elif dl.kind == '-':
                        out_lines.append('-' + dl.text)
            else:
                # Convert to context (keep old lines, drop new lines)
                for dl in current_changes:
                    if dl.kind == '-':
                        out_lines.append(' ' + dl.text)
                    # '+' lines are dropped (not in old file)
            current_changes.clear()

        for dl in hunk.lines:
            if dl.kind == ' ':
                flush_local()
                out_lines.append(' ' + dl.text)
            else:
                current_changes.append(dl)
        flush_local()

        # Recalculate hunk header counts
        old_count = sum(1 for l in out_lines if l.startswith(' ') or l.startswith('-'))
        new_count = sum(1 for l in out_lines if l.startswith(' ') or l.startswith('+'))
        hunk_header = f"@@ -{hunk.old_start},{old_count} +{hunk.new_start},{new_count} @@"

        patch_hunks.append(hunk_header + '\n' + '\n'.join(out_lines))

    return file_header + '\n' + '\n'.join(patch_hunks) + '\n'


def parse_selection(spec: str, max_idx: int) -> set[int]:
    """Parse a selection spec like '1,3,5-7' into a set of indices."""
    result: set[int] = set()
    for part in spec.split(','):
        part = part.strip()
        if '-' in part:
            a, b = part.split('-', 1)
            result.update(range(int(a), int(b) + 1))
        elif part.lower() == 'all':
            result.update(range(1, max_idx + 1))
        else:
            result.add(int(part))
    return {i for i in result if 1 <= i <= max_idx}


def format_group(g: ChangeGroup, verbose: bool = False) -> str:
    """Format a change group for display."""
    header = f"── Group {g.index} (hunk {g.hunk_index}) [{g.summary}] ──"
    parts = [header]

    if verbose and g.context_before:
        for l in g.context_before:
            parts.append(f"   {l.text}")

    for l in g.lines:
        prefix = '+' if l.kind == '+' else '-'
        parts.append(f"  {prefix} {l.text}")

    if verbose and g.context_after:
        for l in g.context_after:
            parts.append(f"   {l.text}")

    return '\n'.join(parts)


def cmd_show(args):
    """Show change groups for a file."""
    diff_text = run_git_diff(args.file, cached=args.cached)
    if not diff_text.strip():
        print(f"No {'staged' if args.cached else 'unstaged'} changes in {args.file}")
        return

    file_header, hunks = parse_hunks(diff_text)
    groups = extract_change_groups(hunks, context=args.context)

    if not groups:
        print("No change groups found.")
        return

    # Filter by grep if requested
    if args.grep:
        groups = [g for g in groups if g.matches(args.grep)]
        if not groups:
            print(f"No groups matching '{args.grep}'")
            return

    # Filter by specific group number
    if args.group:
        groups = [g for g in groups if g.index == args.group]
        if not groups:
            print(f"Group {args.group} not found.")
            return

    print(f"\n{len(groups)} change group(s) in {args.file}:\n")
    for g in groups:
        print(format_group(g, verbose=args.verbose))
        print()


def cmd_stage(args):
    """Stage selected change groups."""
    diff_text = run_git_diff(args.file, cached=False)
    if not diff_text.strip():
        print(f"No unstaged changes in {args.file}")
        return

    file_header, hunks = parse_hunks(diff_text)
    groups = extract_change_groups(hunks, context=args.context)

    if not groups:
        print("No change groups found.")
        return

    # Determine selection
    if args.grep:
        selected = {g.index for g in groups if g.matches(args.grep)}
        if not selected:
            print(f"No groups matching '{args.grep}'")
            return
        print(f"Matched groups: {sorted(selected)}")
    elif args.groups:
        selected = parse_selection(args.groups, len(groups))
    else:
        print("Error: specify --groups or --grep", file=sys.stderr)
        sys.exit(1)

    if not selected:
        print("No valid groups selected.")
        return

    # Show what will be staged
    for g in groups:
        if g.index in selected:
            print(format_group(g))
            print()

    # Build and apply patch
    patch = build_patch(file_header, hunks, groups, selected)

    with tempfile.NamedTemporaryFile(mode='w', suffix='.diff', delete=False) as f:
        f.write(patch)
        patch_path = f.name

    result = subprocess.run(
        ["git", "apply", "--cached", patch_path],
        capture_output=True, text=True
    )

    Path(patch_path).unlink(missing_ok=True)

    if result.returncode != 0:
        print(f"Failed to apply patch:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(f"Staged {len(selected)} group(s) from {args.file}")

    # Show summary
    subprocess.run(["git", "diff", "--cached", "--stat"])


def cmd_unstage(args):
    """Unstage selected change groups (reverse apply from index)."""
    diff_text = run_git_diff(args.file, cached=True)
    if not diff_text.strip():
        print(f"No staged changes in {args.file}")
        return

    file_header, hunks = parse_hunks(diff_text)
    groups = extract_change_groups(hunks, context=args.context)

    if not groups:
        print("No change groups found.")
        return

    if args.grep:
        selected = {g.index for g in groups if g.matches(args.grep)}
    elif args.groups:
        selected = parse_selection(args.groups, len(groups))
    else:
        print("Error: specify --groups or --grep", file=sys.stderr)
        sys.exit(1)

    patch = build_patch(file_header, hunks, groups, selected)

    with tempfile.NamedTemporaryFile(mode='w', suffix='.diff', delete=False) as f:
        f.write(patch)
        patch_path = f.name

    result = subprocess.run(
        ["git", "apply", "--cached", "--reverse", patch_path],
        capture_output=True, text=True
    )

    Path(patch_path).unlink(missing_ok=True)

    if result.returncode != 0:
        print(f"Failed to reverse-apply patch:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(f"Unstaged {len(selected)} group(s) from {args.file}")
    subprocess.run(["git", "diff", "--cached", "--stat"])


def main():
    p = argparse.ArgumentParser(
        description="Sub-hunk partial staging for git",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    p.add_argument('--context', type=int, default=3,
                   help='Context lines around changes (default: 3)')
    sub = p.add_subparsers(dest='command', required=True)

    # show
    s = sub.add_parser('show', help='Show change groups in a file')
    s.add_argument('file', help='File to inspect')
    s.add_argument('--group', type=int, help='Show only this group number')
    s.add_argument('--grep', help='Filter groups by regex pattern')
    s.add_argument('--cached', action='store_true', help='Show staged changes')
    s.add_argument('--verbose', '-v', action='store_true',
                   help='Show context lines around changes')
    s.set_defaults(func=cmd_show)

    # stage
    s = sub.add_parser('stage', help='Stage specific change groups')
    s.add_argument('file', help='File to stage from')
    s.add_argument('--groups', help='Groups to stage (e.g. "1,3,5-7" or "all")')
    s.add_argument('--grep', help='Stage groups matching regex pattern')
    s.set_defaults(func=cmd_stage)

    # unstage
    s = sub.add_parser('unstage', help='Unstage specific change groups')
    s.add_argument('file', help='File to unstage from')
    s.add_argument('--groups', help='Groups to unstage (e.g. "1,3")')
    s.add_argument('--grep', help='Unstage groups matching regex pattern')
    s.set_defaults(func=cmd_unstage)

    args = p.parse_args()
    args.context = getattr(args, 'context', 3)
    args.func(args)


if __name__ == '__main__':
    main()
