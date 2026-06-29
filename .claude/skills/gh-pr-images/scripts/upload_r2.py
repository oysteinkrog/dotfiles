#!/usr/bin/env -S uv run --with boto3 --quiet python
"""Upload files to a Cloudflare R2 public bucket and print their public URLs.

Run with uv so boto3 is fetched on demand and nothing is installed globally:

    uv run --with boto3 upload_r2.py --prefix pr-7220 shot1.png shot2.png

Each file is stored under an unguessable key (`<prefix>/<uuid>-<name>`) so that,
even though the bucket is public-by-URL, the objects cannot be guessed or
enumerated. One Markdown image line is printed per file on stdout; progress and
errors go to stderr.

Required environment variables (referenced by name, never hard-coded):
  R2_ACCOUNT_ID         Cloudflare account id (the R2 S3 endpoint host prefix)
  R2_ACCESS_KEY_ID      R2 API token access key id (Object Read & Write)
  R2_SECRET_ACCESS_KEY  R2 API token secret
  R2_BUCKET             target bucket name
  R2_PUBLIC_BASE_URL    public base, e.g. https://pub-xxxx.r2.dev or a custom domain
"""

from __future__ import annotations

import argparse
import mimetypes
import os
import sys
import uuid
from pathlib import Path

import boto3
from botocore.config import Config


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"error: required environment variable {name} is not set")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Upload files to Cloudflare R2 and print public URLs."
    )
    parser.add_argument("files", nargs="+", help="files to upload")
    parser.add_argument(
        "--prefix",
        default="uploads",
        help="key prefix (e.g. pr-7220); default 'uploads'",
    )
    parser.add_argument(
        "--markdown", action="store_true", help="print Markdown image syntax (default)"
    )
    parser.add_argument(
        "--url-only", action="store_true", help="print bare URLs instead of Markdown"
    )
    args = parser.parse_args()

    account_id = env("R2_ACCOUNT_ID")
    bucket = env("R2_BUCKET")
    public_base = env("R2_PUBLIC_BASE_URL").rstrip("/")

    client = boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=env("R2_ACCESS_KEY_ID"),
        aws_secret_access_key=env("R2_SECRET_ACCESS_KEY"),
        region_name="auto",
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )

    exit_code = 0
    for raw in args.files:
        path = Path(raw)
        if not path.is_file():
            print(f"error: not a file: {raw}", file=sys.stderr)
            exit_code = 1
            continue

        key = f"{args.prefix.strip('/')}/{uuid.uuid4().hex[:12]}-{path.name}"
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"

        with path.open("rb") as body:
            client.put_object(
                Bucket=bucket,
                Key=key,
                Body=body,
                ContentType=content_type,
                ContentDisposition="inline",
            )

        url = f"{public_base}/{key}"
        print(f"uploaded {path.name} -> {url}", file=sys.stderr)
        if args.url_only:
            print(url)
        else:
            print(f"![{path.stem}]({url})")

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
