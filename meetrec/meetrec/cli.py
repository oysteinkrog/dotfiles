"""meetrec: record Slack huddles and Google Meet calls, transcribe them with names."""

from __future__ import annotations

import argparse
import json
import logging
import shutil
from pathlib import Path

from . import config


def main() -> None:
    ap = argparse.ArgumentParser(prog="meetrec", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("watch", help="run the recorder daemon (meetrec.service runs this)")
    sub.add_parser(
        "process-queue", help="transcribe every finished recording in the queue"
    )
    p = sub.add_parser("process", help="transcribe one recording folder")
    p.add_argument("dir", type=Path)
    p = sub.add_parser(
        "label", help='name speakers in a transcript: S1="Kari Nordmann"'
    )
    p.add_argument("dir", type=Path)
    p.add_argument("assignments", nargs="+", metavar="SPEAKER=NAME")
    p.add_argument(
        "--unsure",
        action="append",
        default=[],
        metavar="SPEAKER",
        help="name this speaker but do not save the voice (repeatable)",
    )
    p = sub.add_parser("redo", help="transcribe a finished call again from its audio")
    p.add_argument("dir", type=Path)
    p = sub.add_parser("voices", help="list or remove stored voiceprints")
    p.add_argument("--forget", metavar="NAME", help="delete one person's voiceprints")
    sub.add_parser("status", help="show recordings in progress, queued and failed")
    args = ap.parse_args()

    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )
    if args.cmd == "watch":
        from . import watch

        watch.main()
    elif args.cmd == "process-queue":
        from . import process

        process.process_queue()
    elif args.cmd == "process":
        from . import process

        print(process.process(args.dir))
    elif args.cmd == "redo":
        from . import process

        print(process.redo(args.dir.resolve()))
    elif args.cmd == "label":
        from . import process

        pairs = dict(a.split("=", 1) for a in args.assignments)
        process.relabel(args.dir, pairs, frozenset(args.unsure))
        print(args.dir / "transcript.md")
    elif args.cmd == "voices":
        from . import voices

        lib = voices.load()
        if args.forget:
            lib.pop(args.forget, None)
            voices.save(lib)
        for name, person in sorted(lib.items()):
            print(f"{name}: {len(person['embeddings'])} samples")
    elif args.cmd == "status":
        root = config.root()
        for state in (".recording", ".queue", ".failed"):
            d = root / state
            items = sorted(d.iterdir()) if d.exists() else []
            print(f"{state.lstrip('.')}: {len(items)}")
            for i in items:
                meta = i / "meta.json"
                app = json.loads(meta.read_text()).get("app") if meta.exists() else "?"
                size = sum(f.stat().st_size for f in i.iterdir()) / 1e6
                print(f"  {i.name} ({app}, {size:.1f} MB)")
        print(f"disk free: {shutil.disk_usage(root).free / 1e9:.0f} GB")
