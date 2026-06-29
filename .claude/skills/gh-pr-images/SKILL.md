---
name: gh-pr-images
description: >-
  Post images (screenshots, diagrams) inline in a GitHub PR or issue comment, including
  PRIVATE repos, without committing them to git. Hosts each image on a Cloudflare R2
  public bucket and embeds the public URL; GitHub's camo proxy renders it inline. Use when
  asked to add screenshots/images to a PR or issue, or when "paste this image into the PR".
---

# Inline images in GitHub PRs/issues (private-repo safe)

## Why this exists

GitHub only renders an image inline in a comment if it can fetch the bytes without
authentication. For a private repo that rules out almost everything:

- Committed files / `raw.githubusercontent.com` URLs: the camo image proxy cannot
  authenticate to private content, so they render as a broken-image icon.
- Release assets: same problem, plus they need auth.
- The web-UI paste flow (`github.com/user-attachments/...`) works, but it requires your
  `user_session` browser cookie. A token (PAT/OAuth) is rejected with HTTP 422.

The one thing camo always renders is a **publicly reachable https image URL**. So we host
the image on a public Cloudflare R2 bucket and embed that URL. Posting the comment needs
only a normal `gh` token; nothing touches git, and nothing needs a session cookie.

Tradeoff: the image is **public-by-URL**. Keys are random UUIDs and the bucket has no public
listing, so the URLs are unguessable and cannot be enumerated, but anyone given a URL can
open it. Do not use this for secrets. For truly private rendering see "Fallback" below.

## One-time setup (Cloudflare dashboard, done once per team)

R2 cannot be provisioned from the standard Cloudflare API token, so this part is manual:

1. **Enable R2** on the account (R2 > activate; free tier covers screenshots).
2. **Create a bucket**, e.g. `gh-pr-attachments`.
3. **Enable public access** on the bucket: either the managed `r2.dev` subdomain or a
   custom domain. This serves objects by key and does **not** list them.
4. **Create an R2 API token** scoped to **Object Read & Write** on that bucket only (not
   account-admin). This is the shared write credential; it cannot enumerate other buckets.
5. Put the values in your secret store (`~/.config/secrets/.env`) and run
   `~/bin/refresh-secrets-list`:
   ```
   R2_ACCOUNT_ID=...                 # from the R2 endpoint / account id
   R2_ACCESS_KEY_ID=...              # the API token's access key id
   R2_SECRET_ACCESS_KEY=...          # the API token's secret
   R2_BUCKET=gh-pr-attachments
   R2_PUBLIC_BASE_URL=https://pub-xxxx.r2.dev   # or your custom domain
   ```

For a team install, share the bucket + token through whatever shared-secret mechanism the
team uses; the skill only reads the five `R2_*` variables by name.

## Usage

One command uploads the images and posts them as a PR/issue comment:

```bash
with-secrets R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_PUBLIC_BASE_URL -- \
  uv run --with boto3 scripts/post_pr_images.py \
    --repo InitialForce/ScDesktop --number 7220 \
    --title "Installer theme screenshots" \
    shot1.png shot2.png shot3.png
```

(`with-secrets` is the fish helper; `gh` must be authenticated for the post step. `--number`
works for both PRs and issues, which share the comment endpoint. It prints the new comment's
URL.)

Just the upload (no comment), to get Markdown image lines you can paste anywhere:

```bash
with-secrets R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_PUBLIC_BASE_URL -- \
  uv run --with boto3 scripts/upload_r2.py --prefix pr-7220 shot1.png shot2.png
```

Add `--url-only` for bare URLs. Both scripts run through `uv`, so boto3 is fetched on demand
and nothing is installed globally; they are cross-platform (use `python3` / `uv` on any OS).

## Security model

- **Unguessable keys.** Each object is stored as `<prefix>/<uuid>-<name>`, so URLs cannot be
  guessed from the PR number or filename.
- **No enumeration.** Public R2 access serves objects by key only; it does not list the
  bucket. The shared token is Object Read & Write on a single bucket, so a leaked key cannot
  enumerate other buckets.
- **Deletable.** Objects can be removed any time from the dashboard or via the S3 API.
- **Hardening (optional).** To remove even Object-level listing over S3, front uploads with a
  small Cloudflare Worker bound to the bucket that only accepts `PUT` behind a shared bearer,
  and distribute the Worker URL instead of S3 keys.

## Video

Camo proxies images only. Inline **video playback** in a comment works solely through
GitHub's own user-attachments flow, so a self-hosted URL gives an inline image plus a
video-as-download link, not an embedded player.

## Fallback: truly private (no public exposure)

If the image must never be public, use the user-attachments flow via the `gh-image`
extension (`gh extension install drogers0/gh-image`). It reads your `user_session` cookie
from the local browser store (or `GH_SESSION_TOKEN`), replays the web upload, and prints a
private `github.com/user-attachments/assets/<uuid>` link that inherits repo visibility. This
needs your full-account session cookie and an undocumented internal endpoint, which is why
the R2 path above is the default.
