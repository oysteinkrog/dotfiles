#!/usr/bin/env python3
"""diff-scorecards.py — compare two passes; emit uplift_diff.md +
regression_alerts.md.

Usage: diff-scorecards.py <workspace> <pass-A-tag> <pass-B-tag>

Reads <workspace>/scorecard_pass_<A>.md and <workspace>/scorecard_pass_<B>.md. Writes
<workspace>/uplift_diff.md and <workspace>/regression_alerts.md.

Hard-stops (exits 1) if any FM regressed > 50 points unless the regression
is explicitly acked in regression_alerts.md.
"""

import re
import sys
from pathlib import Path


def parse_scorecard(path: Path):
    """Parse the per-FM table; returns {fm_id: median}."""
    text = path.read_text()
    fms = {}
    for line in text.splitlines():
        m = re.match(r"^\| (fm-[a-z0-9-]+) \| (\d+) \|", line)
        if m:
            fms[m.group(1)] = int(m.group(2))
    return fms


def main():
    if len(sys.argv) != 4:
        print("usage: diff-scorecards.py <workspace> <pass-A> <pass-B>", file=sys.stderr)
        sys.exit(64)
    workspace = Path(sys.argv[1])
    pa, pb = sys.argv[2], sys.argv[3]

    a = parse_scorecard(workspace / f"scorecard_pass_{pa}.md")
    b = parse_scorecard(workspace / f"scorecard_pass_{pb}.md")

    deltas = []
    for fm in sorted(set(a) | set(b)):
        delta = b.get(fm, 0) - a.get(fm, 0)
        deltas.append((fm, a.get(fm, 0), b.get(fm, 0), delta))

    uplift = workspace / "uplift_diff.md"
    with open(uplift, "w") as f:
        f.write(f"# Uplift Diff: pass {pa} → pass {pb}\n\n")
        f.write("| FM | pass-A | pass-B | Δ |\n|---|---|---|---|\n")
        for fm, sa, sb, d in sorted(deltas, key=lambda x: x[3]):
            f.write(f"| {fm} | {sa} | {sb} | {'+' if d >= 0 else ''}{d} |\n")
    print(f"wrote {uplift}", file=sys.stderr)

    regressions = [(fm, sa, sb, d) for fm, sa, sb, d in deltas if d < -50]
    alerts_path = workspace / "regression_alerts.md"
    PLACEHOLDER = "<fill in reason or revert the change>"

    # Preserve any existing ACKs the user may have written between runs.
    existing_acks = {}
    if alerts_path.exists():
        prior_text = alerts_path.read_text()
        # Parse existing per-FM ACK blocks; capture non-placeholder ACK content.
        # Marker uses a trailing newline so `## REGRESSION: fm-a` doesn't match
        # `## REGRESSION: fm-aaa` as a prefix.
        for fm, _, _, _ in regressions:
            marker = f"## REGRESSION: {fm}\n"
            if marker not in prior_text:
                continue
            after = prior_text.split(marker, 1)[1]
            # Block ends at the next REGRESSION header (also newline-terminated)
            # OR end-of-file.
            block = after.split("\n## REGRESSION: ", 1)[0]
            # Find each ACK: line and keep the non-placeholder content.
            ack_lines = []
            for line in block.splitlines():
                stripped = line.strip()
                if stripped.startswith("ACK:") and PLACEHOLDER not in stripped:
                    ack_lines.append(stripped)
            if ack_lines:
                existing_acks[fm] = ack_lines

    if regressions:
        with open(alerts_path, "w") as f:
            f.write(f"# REGRESSION ALERTS: pass {pa} → pass {pb}\n\n")
            f.write("Each regression below must be either reverted or explicitly\n")
            f.write("acked with `ACK: <reason>` on a separate line BEFORE the next\n")
            f.write("phase can proceed. Existing ACKs are preserved across runs.\n\n")
            for fm, sa, sb, d in regressions:
                f.write(f"## REGRESSION: {fm}\n")
                f.write(f"- pass-A score: {sa}\n- pass-B score: {sb}\n- delta: {d}\n\n")
                if fm in existing_acks:
                    for ack in existing_acks[fm]:
                        f.write(f"{ack}\n")
                    f.write("\n")
                else:
                    f.write(f"ACK: {PLACEHOLDER}\n\n")
        print(f"wrote {alerts_path} ({len(regressions)} regressions, "
              f"{len(existing_acks)} preserved ACKs)", file=sys.stderr)
        # Hard-stop if any regression has only the placeholder ACK.
        unacked = sum(1 for fm, _, _, _ in regressions if fm not in existing_acks)
        if unacked > 0:
            print(f"REGRESSION: {unacked} unacked regression(s) > 50 points", file=sys.stderr)
            sys.exit(1)
    else:
        if alerts_path.exists():
            alerts_path.write_text(f"# No regressions: pass {pa} → pass {pb}\n")

    print(f"diff complete: {len(deltas)} FMs, {len(regressions)} regressions", file=sys.stderr)


if __name__ == "__main__":
    main()
