---
name: publish-site
description: |
  Publish static content to GitHub Pages (oysteinkrog/sites repo).
  Use when user says "publish site", "deploy to pages", "publish to gh-pages",
  or wants to put static HTML somewhere shareable.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
---

# Publish Static Site to GitHub Pages

Publish a directory of static content to `oysteinkrog/sites` on the `gh-pages` branch.

## Arguments

The user should provide:
- **source**: path to directory containing static content (must have `index.html`)
- **category**: top-level grouping (e.g., `bv`, `docs`, `reports`)
- **slug**: unique name within category (e.g., `bb-bbox`, `my-feature`)

If not provided, infer from context or ask.

## Steps

1. Verify source directory exists and contains `index.html`
2. Ensure local checkout exists at `/c/work/sites-repo`:
   ```bash
   # First time:
   git clone --branch gh-pages --single-branch https://github.com/oysteinkrog/sites.git /c/work/sites-repo
   # Subsequent times:
   cd /c/work/sites-repo && git pull origin gh-pages
   ```
3. Copy content into place:
   ```bash
   mkdir -p /c/work/sites-repo/<category>/<slug>
   cp -r <source>/* /c/work/sites-repo/<category>/<slug>/
   ```
4. Commit and push:
   ```bash
   cd /c/work/sites-repo && git add -A && git commit -m "add <category>/<slug>" && git push origin gh-pages
   ```
5. Report the live URL: `https://oysteinkrog.github.io/sites/<category>/<slug>/`

## Common Patterns

### bv (beads viewer) export
```bash
bv -export-pages ./bv-pages -pages-title "Title"
# then publish with category=bv, slug=<project-slug>
```

### Updating an existing site
Same steps — `cp -r` overwrites the existing directory, commit message: `update <category>/<slug>`.

## Notes
- Fixed local checkout: `/c/work/sites-repo` (reused across publishes)
- Each site must be self-contained (all assets relative, own `index.html`)
- No landing page at root — sites are accessed by direct URL
