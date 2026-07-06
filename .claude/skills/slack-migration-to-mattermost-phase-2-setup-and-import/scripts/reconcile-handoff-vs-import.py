#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import sys


def load_json(path: Path, label: str) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"missing {label}: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"{label} root must be a JSON object: {path}")
    return payload


def safe_int(value, label: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} is not an integer: {value!r}") from exc


def dict_field(payload: dict, key: str, label: str) -> dict:
    value = payload.get(key, {})
    if value in ("", None):
        return {}
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be a JSON object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare Phase 1 handoff counts with observed import counts.")
    parser.add_argument("--handoff-json", required=True)
    parser.add_argument("--observed-json", required=True)
    parser.add_argument("--output-json", required=True)
    args = parser.parse_args()

    handoff_path = Path(args.handoff_json)
    observed_path = Path(args.observed_json)
    if not handoff_path.exists() or not observed_path.exists():
        print("error: missing handoff or observed counts json", file=sys.stderr)
        return 1

    try:
        handoff = load_json(handoff_path, "handoff json")
        observed = load_json(observed_path, "observed counts json")
        expected_counts = dict_field(handoff, "counts", "handoff counts")
        observed_counts = dict_field(observed, "counts", "observed counts") if "counts" in observed else observed
    except (FileNotFoundError, json.JSONDecodeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    delta = {}
    try:
        for key in ("users", "channels", "posts", "direct_channels", "direct_posts", "emoji", "attachments"):
            expected = safe_int(expected_counts.get(key, 0), f"expected {key}")
            actual = safe_int(observed_counts.get(key, 0), f"observed {key}")
            delta[key] = {
                "expected": expected,
                "actual": actual,
                "difference": actual - expected,
            }
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    payload = {
        "workspace": handoff.get("workspace", ""),
        "status": "matched" if all(item["difference"] == 0 for item in delta.values()) else "drift-detected",
        "delta": delta,
    }

    output = Path(args.output_json)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
