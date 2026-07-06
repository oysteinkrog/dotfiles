#!/usr/bin/env python3
"""Upload images to the gh-pr-images Cloudflare Worker and print their URLs.

The Worker (PUT-only, image-only, size-capped) holds the private R2 bucket
binding on Cloudflare. This client needs only the Worker URL, which is not a
secret, so there is nothing to commit, export, or rotate. Uses only the Python
standard library: no boto3, no uv, no third-party packages.

    python3 upload.py --prefix pr-7220 shot1.png shot2.png

Also importable: upload_files(files, prefix) -> [(name, url), ...].

The Worker URL comes from $GH_PR_IMAGES_WORKER_URL if set, otherwise the
WORKER_URL constant below (filled in once the company Worker is deployed). If
the Worker was deployed with an UPLOAD_TOKEN gate, set $GH_PR_IMAGES_TOKEN too.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# Public Worker URL for the company gh-pr-images service. Not a secret.
WORKER_URL = "https://gh-pr-images.REPLACE-ME.workers.dev"

_PLACEHOLDER = "REPLACE-ME"


def worker_url() -> str:
    return os.environ.get("GH_PR_IMAGES_WORKER_URL", WORKER_URL).rstrip("/")


def upload_files(files, prefix: str = "uploads"):
    """Upload each image and return [(stem, public_url), ...]."""
    base = worker_url()
    if _PLACEHOLDER in base:
        sys.exit(
            "error: the gh-pr-images Worker URL is not configured.\n"
            "Set GH_PR_IMAGES_WORKER_URL=<url>, or edit WORKER_URL in upload.py "
            "after deploying the Worker (see worker/ and SKILL.md)."
        )

    token = os.environ.get("GH_PR_IMAGES_TOKEN", "")
    results = []
    for raw in files:
        path = Path(raw)
        if not path.is_file():
            raise FileNotFoundError(f"not a file: {raw}")

        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        query = urllib.parse.urlencode({"prefix": prefix, "name": path.name})
        headers = {"Content-Type": content_type, "X-Filename": path.name}
        if token:
            headers["Authorization"] = f"Bearer {token}"

        request = urllib.request.Request(
            f"{base}/?{query}",
            data=path.read_bytes(),
            method="PUT",
            headers=headers,
        )
        try:
            with urllib.request.urlopen(request) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as exc:
            sys.exit(f"error: upload of {path.name} failed: {exc.code} {exc.read().decode(errors='replace').strip()}")

        url = payload["url"]
        print(f"uploaded {path.name} -> {url}", file=sys.stderr)
        results.append((path.stem, url))
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="Upload images via the gh-pr-images Worker.")
    parser.add_argument("files", nargs="+", help="image files to upload")
    parser.add_argument("--prefix", default="uploads", help="key prefix (e.g. pr-7220)")
    parser.add_argument(
        "--url-only",
        action="store_true",
        help="print bare URLs instead of Markdown image tags",
    )
    args = parser.parse_args()

    for name, url in upload_files(args.files, args.prefix):
        print(url if args.url_only else f"![{name}]({url})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
