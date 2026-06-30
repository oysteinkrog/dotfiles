---
name: gh-pr-images
description: >-
  Post images (screenshots, diagrams) inline in a GitHub PR or issue comment, including
  PRIVATE repos, without committing them to git. Uploads each image to a company Cloudflare
  Worker (backed by a private R2 bucket) and embeds the returned URL; GitHub's camo proxy
  renders it inline. Use when asked to add screenshots/images to a PR or issue, or when
  "paste this image into the PR".
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
the image behind a small Cloudflare Worker that owns a private R2 bucket, and embed the URL
the Worker returns. Posting the comment needs only a normal `gh` token; nothing touches git,
and nothing needs a session cookie.

The client only ever needs the **Worker URL**, which is not a secret. There are no S3
credentials in the repo, nothing to export with `with-secrets`, and nothing to rotate on the
client side. A leaked Worker URL grants at most the ability to upload an image (see Security
model). That is what makes this safe to hardcode and share across the whole company.

Tradeoff: an uploaded image is **public-by-URL**. Keys are random and the bucket has no
public listing, so URLs are unguessable and cannot be enumerated, but anyone given a URL can
open it. Do not use this for secrets. For truly private rendering see "Fallback" below.

## One-time setup (one Worker for the whole company)

Done once by an admin. The `worker/` directory next to this file is the deployable source.

1. **Install wrangler** and log in:
   ```bash
   npm install -g wrangler   # or: npx wrangler ...
   wrangler login
   ```
2. **Create the private R2 bucket** (no public access needed; the Worker fronts it):
   ```bash
   wrangler r2 bucket create gh-pr-attachments
   ```
3. **Deploy the Worker** from `worker/`:
   ```bash
   cd worker && wrangler deploy
   ```
   wrangler prints the Worker URL, e.g. `https://gh-pr-images.<subdomain>.workers.dev`.
4. **Hardcode that URL** into `scripts/upload.py` (replace the `WORKER_URL` placeholder) and
   commit. From then on every colleague uses the skill with zero setup.
5. **Optional upload gate.** To require a bearer token on uploads:
   ```bash
   cd worker && wrangler secret put UPLOAD_TOKEN
   ```
   Distribute that token out-of-band; clients set `GH_PR_IMAGES_TOKEN`. Leave it unset for
   open upload-only access (the accepted default: a leaked URL can only add images).

That is the entire infrastructure. The R2 bucket binding lives on Cloudflare, so it never
appears in the repo.

## Usage

No secrets, no `with-secrets`, no `uv`. The scripts are pure standard-library Python.

One command uploads the images and posts them as a PR/issue comment:

```bash
python3 scripts/post_pr_images.py \
  --repo InitialForce/ScDesktop --number 7220 \
  --title "Installer theme screenshots" \
  shot1.png shot2.png shot3.png
```

(`gh` must be authenticated for the post step. `--number` works for both PRs and issues,
which share the comment endpoint. It prints the new comment's URL.)

Just the upload (no comment), to get Markdown image lines you can paste anywhere:

```bash
python3 scripts/upload.py --prefix pr-7220 shot1.png shot2.png
```

Add `--url-only` for bare URLs. To point at a different Worker without editing the file, set
`GH_PR_IMAGES_WORKER_URL`; if the Worker has an upload gate, set `GH_PR_IMAGES_TOKEN`.

## Security model

- **No secret on the client.** The Worker URL is public information. The R2 bucket binding
  exists only inside the Worker on Cloudflare, so there is no S3 key in the repo to leak.
- **Upload-only by construction.** The Worker accepts `PUT` for images only (png/jpeg/gif/
  webp), caps size (10 MB), and stores each object under a server-generated random key. A
  caller cannot overwrite an existing object, enumerate the bucket, or read arbitrary keys.
  Worst case from a leaked URL: someone uploads an image.
- **Unguessable keys.** Objects are stored as `<prefix>/<random>-<name>`, so URLs cannot be
  guessed from the PR number or filename.
- **Optional bearer gate.** Set `UPLOAD_TOKEN` on the Worker to require a shared token even
  for uploads.
- **Revocable.** Delete an object from the dashboard / S3 API, or `wrangler delete` the whole
  Worker to take the service offline instantly.

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
the Worker path above is the default.
