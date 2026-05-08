#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import hashlib
import json
import mimetypes
from pathlib import Path
import sys
from urllib.parse import urlparse
from urllib.request import Request, urlopen


API_URL = "https://slack.com/api/emoji.list"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch_json(url: str, token: str) -> dict:
    request = Request(url, headers={"Authorization": f"Bearer {token}"})
    with urlopen(request) as response:
        return json.load(response)


def download_file(url: str, token: str, destination: Path) -> None:
    request = Request(url, headers={"Authorization": f"Bearer {token}"})
    with urlopen(request) as response:
        destination.write_bytes(response.read())


def file_suffix(url: str) -> str:
    parsed = urlparse(url)
    path = Path(parsed.path)
    if path.suffix:
        return path.suffix
    content_type, _ = mimetypes.guess_type(url)
    if content_type:
        guessed = mimetypes.guess_extension(content_type)
        if guessed:
            return guessed
    return ".bin"


def main() -> int:
    parser = argparse.ArgumentParser(description="Export Slack custom emoji assets and alias metadata.")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--manifest-out", required=True)
    parser.add_argument("--aliases-out", required=True)
    parser.add_argument("--api-url", default=API_URL)
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    images_dir = output_dir / "images"
    images_dir.mkdir(parents=True, exist_ok=True)

    try:
        payload = fetch_json(args.api_url, args.token)
    except Exception as exc:  # pragma: no cover - network failures are environment-dependent
        print(f"error: failed to fetch Slack emoji list: {exc}", file=sys.stderr)
        return 1

    if not payload.get("ok"):
        print(f"error: Slack emoji.list failed: {payload}", file=sys.stderr)
        return 1

    emoji_map = payload.get("emoji", {})
    if not isinstance(emoji_map, dict):
        print("error: emoji.list returned an invalid payload", file=sys.stderr)
        return 1

    aliases: dict[str, str] = {}
    manifest_entries: list[dict] = []
    warnings: list[str] = []

    for name, value in sorted(emoji_map.items()):
        if not isinstance(value, str):
            warnings.append(f"{name}: skipping non-string emoji value")
            continue
        if value.startswith("alias:"):
            aliases[name] = value.split(":", 1)[1]
            continue

        suffix = file_suffix(value)
        image_path = images_dir / f"{name}{suffix}"
        try:
            download_file(value, args.token, image_path)
        except Exception as exc:  # pragma: no cover - network failures are environment-dependent
            warnings.append(f"{name}: download failed: {exc}")
            continue

        manifest_entries.append(
            {
                "name": name,
                "path": str(image_path.resolve()),
                "sha256": sha256_file(image_path),
                "bytes": image_path.stat().st_size,
                "source_url": value,
            }
        )

    manifest = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "workspace": args.workspace,
        "custom_emoji": manifest_entries,
        "alias_count": len(aliases),
        "warnings": warnings,
    }

    manifest_out = Path(args.manifest_out)
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {manifest_out}")

    aliases_out = Path(args.aliases_out)
    aliases_out.parent.mkdir(parents=True, exist_ok=True)
    aliases_out.write_text(json.dumps({"aliases": aliases}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {aliases_out}")

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
