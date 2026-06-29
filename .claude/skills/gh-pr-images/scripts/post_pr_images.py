#!/usr/bin/env -S uv run --with boto3 --quiet python
"""Upload images to Cloudflare R2 and post them inline in a GitHub PR/issue comment.

For PRIVATE repos this is the only way to render images inline without committing
them: GitHub's camo proxy fetches the public R2 URL and serves it in the comment.

    uv run --with boto3 post_pr_images.py \\
        --repo InitialForce/ScDesktop --number 7220 \\
        --title "Installer theme screenshots" shot1.png shot2.png

Auth:
  - The five R2_* env vars must be set (see upload_r2.py) for the upload.
  - `gh` must be installed and authenticated; its token is used only to post the
    comment. PRs and issues share the /issues/{n}/comments endpoint, so --number
    works for either.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys

from upload_r2 import upload_files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", help="image files to upload")
    parser.add_argument("--repo", required=True, help="OWNER/REPO")
    parser.add_argument(
        "--number", required=True, help="PR or issue number (shared comment endpoint)"
    )
    parser.add_argument("--title", default="", help="optional heading for the comment")
    parser.add_argument(
        "--prefix", default="", help="R2 key prefix; defaults to pr-<number>"
    )
    args = parser.parse_args()

    if shutil.which("gh") is None:
        sys.exit("error: gh CLI not found on PATH (needed to post the comment)")

    prefix = args.prefix or f"pr-{args.number}"
    uploaded = upload_files(args.files, prefix)

    body = ""
    if args.title:
        body += f"## {args.title}\n\n"
    for name, url in uploaded:
        body += f"![{name}]({url})\n\n"

    result = subprocess.run(
        [
            "gh",
            "api",
            f"repos/{args.repo}/issues/{args.number}/comments",
            "-F",
            "body=@-",
            "--jq",
            ".html_url",
        ],
        input=body,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        return result.returncode

    print(result.stdout.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
