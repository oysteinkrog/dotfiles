#!/usr/bin/env python3
"""compute-fm-id.py — deterministic content-derived FM id.

Usage: compute-fm-id.py --subsystem <name> --symptom <short-symptom>

Output: a stable id of the form `fm-<subsystem-slug>-<symptom-slug>`.
Slugs are lowercase ASCII, hyphen-separated, max 40 chars total per slug.
"""

import argparse
import re
import sys


def slug(s, maxlen=40):
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = s.strip("-")
    return s[:maxlen]


class _UsageExitParser(argparse.ArgumentParser):
    """ArgumentParser that exits with the IO-CONTRACTS-mandated code 64
    (usage_error) instead of argparse's default 2, so this script matches
    the contract documented in references/methodology/IO-CONTRACTS.md."""

    def error(self, message):
        self.print_usage(sys.stderr)
        sys.stderr.write(f"{self.prog}: error: {message}\n")
        sys.exit(64)


def main():
    p = _UsageExitParser()
    p.add_argument("--subsystem", required=True)
    p.add_argument("--symptom", required=True)
    args = p.parse_args()

    sub_slug = slug(args.subsystem)
    sym_slug = slug(args.symptom)
    print(f"fm-{sub_slug}-{sym_slug}")


if __name__ == "__main__":
    main()
